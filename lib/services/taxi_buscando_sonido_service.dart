import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

/// Feedback audible al activar / desactivar «Buscando viajes» (taxi).
/// Mismo patrón que [RepartidorChatMensajeSonidoService] (MP3 + alarma),
/// que sí suena en dispositivo real.
class TaxiBuscandoSonidoService {
  TaxiBuscandoSonidoService._();

  static const _assetOn = 'sounds/taxi_buscando_on.mp3';
  static const _assetOff = 'sounds/taxi_buscando_off.mp3';
  static const _assetFallback = 'sounds/chat_mensaje.mp3';

  static AudioPlayer? _player;
  static AudioContext? _ctx;

  static AudioContext _crearContexto() {
    return AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: {AVAudioSessionOptions.mixWithOthers},
      ),
      android: AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: false,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.alarm,
        audioFocus: AndroidAudioFocus.gain,
      ),
    );
  }

  static Future<void> _asegurarPlayer() async {
    _ctx ??= _crearContexto();
    try {
      await AudioPlayer.global.setAudioContext(_ctx!);
    } catch (_) {}

    _player ??= AudioPlayer();
    final p = _player!;
    try {
      await p.setAudioContext(_ctx!);
    } catch (_) {}
    await p.setReleaseMode(ReleaseMode.stop);
    await p.setVolume(1.0);
  }

  static Future<void> _vibrar({required bool activando}) async {
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
    try {
      if (await Vibration.hasVibrator() != true) return;
      if (activando) {
        await Vibration.vibrate(pattern: [0, 100, 60, 100, 60, 140]);
      } else {
        await Vibration.vibrate(pattern: [0, 80, 80, 180]);
      }
    } catch (_) {}
  }

  static Future<bool> _playAsset(String asset) async {
    try {
      await _asegurarPlayer();
      final p = _player!;
      await p.stop();
      await p.setVolume(1.0);
      // setSource + resume es más fiable que play() en algunos Android.
      await p.setSource(AssetSource(asset));
      await p.resume();
      return true;
    } catch (e) {
      debugPrint('⚠️ TaxiBuscandoSonido $asset: $e');
      return false;
    }
  }

  static Future<void> _reproducir(String preferido) async {
    if (await _playAsset(preferido)) return;
    if (await _playAsset(_assetFallback)) return;
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {
      try {
        await SystemSound.play(SystemSoundType.click);
      } catch (_) {}
    }
  }

  /// Socio activa el modo.
  static Future<void> alActivar() async {
    unawaited(_vibrar(activando: true));
    await _reproducir(_assetOn);
  }

  /// Socio desactiva el modo.
  static Future<void> alDesactivar() async {
    unawaited(_vibrar(activando: false));
    await _reproducir(_assetOff);
  }
}
