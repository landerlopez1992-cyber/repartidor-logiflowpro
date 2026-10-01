import 'package:flutter_test/flutter_test.dart';
import 'package:repartidor_logiflow_pro/services/repartidor_actualizacion_forzada_service.dart';

void main() {
  final ahora = DateTime.utc(2026, 9, 30, 12);
  final hace2Dias = ahora.subtract(const Duration(days: 2));
  final hace2Horas = ahora.subtract(const Duration(hours: 2));

  bool regla({
    required String installed,
    String minVersion = '',
    int nonce = 0,
    int ondaServidor = 0,
    int ondaLocal = 0,
    String? store,
    bool play = false,
    bool? playOk,
    DateTime? release,
    required String plataforma,
  }) {
    return RepartidorActualizacionForzadaService.requiresMandatoryUpdate(
      installed: installed,
      minVersion: minVersion,
      nonce: nonce,
      ondaServidor: ondaServidor,
      ondaLocal: ondaLocal,
      storePublishedVersion: store,
      playUpdateAvailable: play,
      playCheckSucceeded: playOk,
      storeReleaseDate: release,
      now: ahora,
      plataforma: plataforma,
    );
  }

  group('Android — solo Play API bloquea', () {
    test('Play con update → bloquear', () {
      expect(
        regla(installed: '1.0.30', store: '1.0.30', play: true, plataforma: 'android'),
        isTrue,
      );
    });

    test('ficha + mínima + onda, pero Play sin update → NO bloquear', () {
      expect(
        regla(
          installed: '1.0.30',
          minVersion: '1.0.34',
          nonce: 7,
          ondaServidor: 3,
          ondaLocal: 0,
          store: '1.0.34',
          play: false,
          playOk: true,
          plataforma: 'android',
        ),
        isFalse,
      );
    });

    test('Play no respondió → NO bloquear', () {
      expect(
        regla(
          installed: '1.0.30',
          minVersion: '1.0.34',
          nonce: 7,
          store: '1.0.34',
          playOk: null,
          plataforma: 'android',
        ),
        isFalse,
      );
    });
  });

  group('iOS — App Store propagada', () {
    test('sin ficha → no bloquear', () {
      expect(
        regla(installed: '1.0.30', minVersion: '1.0.34', nonce: 7, plataforma: 'ios'),
        isFalse,
      );
    });

    test('publicada hace 2 h → esperar', () {
      expect(
        regla(
          installed: '1.0.30',
          store: '1.0.34',
          release: hace2Horas,
          plataforma: 'ios',
        ),
        isFalse,
      );
    });

    test('propagada + mínima publicada + instalada atrás → bloquear', () {
      expect(
        regla(
          installed: '1.0.30',
          minVersion: '1.0.34',
          nonce: 7,
          store: '1.0.34',
          release: hace2Dias,
          plataforma: 'ios',
        ),
        isTrue,
      );
    });

    test('mínima mayor que lo publicado → no bloquear', () {
      expect(
        regla(
          installed: '1.0.30',
          minVersion: '1.0.35',
          nonce: 7,
          store: '1.0.34',
          release: hace2Dias,
          plataforma: 'ios',
        ),
        isFalse,
      );
    });

    test('onda pendiente con ficha propagada → bloquear', () {
      expect(
        regla(
          installed: '1.0.30',
          ondaServidor: 3,
          ondaLocal: 1,
          store: '1.0.34',
          release: hace2Dias,
          plataforma: 'ios',
        ),
        isTrue,
      );
    });

    test('ya al día → no bloquear', () {
      expect(
        regla(
          installed: '1.0.34',
          minVersion: '1.0.34',
          nonce: 7,
          store: '1.0.34',
          release: hace2Dias,
          plataforma: 'ios',
        ),
        isFalse,
      );
    });
  });
}
