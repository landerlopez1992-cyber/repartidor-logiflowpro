import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Feedback audible al activar / desactivar «Buscando viajes» (taxi).
/// Pitidos propios (más largos y brillantes), distintos del sonido de chat.
class TaxiBuscandoSonidoService {
  TaxiBuscandoSonidoService._();

  static const _assetOn = 'sounds/taxi_buscando_on.wav';
  static const _assetOff = 'sounds/taxi_buscando_off.wav';

  static AudioPlayer? _player;
  static AudioContext? _ctx;
  static bool _ctxListo = false;

  static AudioContext _contexto() {
    return AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: {
          AVAudioSessionOptions.mixWithOthers,
          AVAudioSessionOptions.duckOthers,
        },
      ),
      android: AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: false,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.assistanceSonification,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
    );
  }

  static Future<void> _asegurarContexto() async {
    if (_ctxListo) return;
    _ctx ??= _contexto();
    try {
      await AudioPlayer.global.setAudioContext(_ctx!);
      _ctxListo = true;
    } catch (_) {}
  }

  static Future<AudioPlayer> _obtenerPlayer() async {
    await _asegurarContexto();
    final p = _player ?? AudioPlayer();
    _player = p;
    try {
      await p.setAudioContext(_ctx!);
    } catch (_) {}
    await p.setReleaseMode(ReleaseMode.stop);
    return p;
  }

  static Future<void> _vibrar({required bool activando}) async {
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
    try {
      if (await Vibration.hasVibrator() != true) return;
      if (activando) {
        await Vibration.vibrate(pattern: [0, 80, 70, 90, 70, 120]);
      } else {
        await Vibration.vibrate(pattern: [0, 70, 90, 160]);
      }
    } catch (_) {}
  }

  static Future<void> _reproducir(String asset, {required double volumen}) async {
    try {
      final p = await _obtenerPlayer();
      await p.stop();
      await p.setVolume(volumen.clamp(0.0, 1.0));
      // mediaPlayer: más fiable con WAV que lowLatency en varios dispositivos.
      await p.play(AssetSource(asset), mode: PlayerMode.mediaPlayer);
    } catch (e) {
      print('⚠️ Sonido buscando viajes ($asset): $e');
      try {
        await SystemSound.play(SystemSoundType.click);
      } catch (_) {}
    }
  }

  /// Socio activa el modo: pitido ascendente brillante.
  static Future<void> alActivar() async {
    // Sonido + vibración en paralelo (feedback inmediato al tocar).
    await Future.wait([
      _vibrar(activando: true),
      _reproducir(_assetOn, volumen: 1.0),
    ]);
  }

  /// Socio desactiva el modo: pitido descendente distinto.
  static Future<void> alDesactivar() async {
    await Future.wait([
      _vibrar(activando: false),
      _reproducir(_assetOff, volumen: 0.9),
    ]);
  }
}
