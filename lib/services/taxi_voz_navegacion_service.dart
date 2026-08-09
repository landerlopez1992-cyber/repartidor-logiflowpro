import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Guía por voz del taxi (español), con mute persistente.
class TaxiVozNavegacionService {
  TaxiVozNavegacionService._();
  static final TaxiVozNavegacionService instance = TaxiVozNavegacionService._();

  static const _prefsMuteKey = 'taxi_chofer_voz_mute';

  final FlutterTts _tts = FlutterTts();
  bool _listo = false;
  bool _mute = false;
  String? _ultimaFrase;
  DateTime? _ultimoSpeakAt;

  bool get isMuted => _mute;

  Future<void> init() async {
    if (_listo) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _mute = prefs.getBool(_prefsMuteKey) ?? false;
      await _tts.setLanguage('es-ES');
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      try {
        await _tts.awaitSpeakCompletion(false);
      } catch (_) {}
      _listo = true;
    } catch (_) {
      _listo = false;
    }
  }

  Future<bool> toggleMute() async {
    await init();
    _mute = !_mute;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsMuteKey, _mute);
    } catch (_) {}
    if (_mute) {
      try {
        await _tts.stop();
      } catch (_) {}
    } else {
      await speak('Guía por voz activada', forzar: true);
    }
    return _mute;
  }

  Future<void> setMuted(bool muted) async {
    await init();
    _mute = muted;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsMuteKey, _mute);
    } catch (_) {}
    if (_mute) {
      try {
        await _tts.stop();
      } catch (_) {}
    }
  }

  /// Habla [texto] si no está en mute. Evita repetir la misma frase muy seguido.
  Future<void> speak(String texto, {bool forzar = false}) async {
    final t = texto.trim();
    if (t.isEmpty) return;
    await init();
    if (_mute && !forzar) return;
    if (_mute) return;
    final ahora = DateTime.now();
    if (!forzar &&
        _ultimaFrase == t &&
        _ultimoSpeakAt != null &&
        ahora.difference(_ultimoSpeakAt!) < const Duration(seconds: 12)) {
      return;
    }
    _ultimaFrase = t;
    _ultimoSpeakAt = ahora;
    try {
      await _tts.stop();
      await _tts.speak(t);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  static String formatDistanciaVoz(num metros) {
    final m = metros.toDouble();
    if (m >= 1000) {
      final km = m / 1000.0;
      if (km >= 10) return '${km.round()} kilómetros';
      final redondeado = (km * 10).round() / 10.0;
      if (redondeado == redondeado.roundToDouble()) {
        final n = redondeado.round();
        return n == 1 ? '1 kilómetro' : '$n kilómetros';
      }
      final txt = redondeado.toStringAsFixed(1).replaceAll('.', ',');
      return '$txt kilómetros';
    }
    final metrosR = m.round().clamp(10, 999);
    return '$metrosR metros';
  }
}
