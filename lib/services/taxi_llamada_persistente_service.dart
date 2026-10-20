import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

import '../constants/repartidor_notificacion_tipos.dart';
import '../navigation/repartidor_navigator.dart';
import 'taxi_chofer_service.dart';

/// Alerta estilo Uber: ringtone + vibración + notificación persistente
/// hasta aceptar, rechazar, o que otro socio tome el viaje.
class TaxiLlamadaPersistenteService {
  TaxiLlamadaPersistenteService._();
  static final TaxiLlamadaPersistenteService instance =
      TaxiLlamadaPersistenteService._();

  static const int notificacionId = 77021;
  /// v4: el canal no vibra ni suena. El timbre lo controla solo esta clase,
  /// porque Android no deja cambiar un canal ya creado (v3 vibraba solo).
  static const String canalId = 'taxi_llamada_v4';
  static const String canalIdLegacy = 'taxi_llamada_v3';
  static const String canalIdLegacyV1 = 'taxi_llamada_v2';
  static const String canalIdLegacyV0 = 'taxi_llamada_v1';
  static const String canalNombre = 'Llamadas de viaje (taxi)';
  static const String _assetRingtone = 'sounds/taxi_buscando_on.mp3';
  static const String _assetFallback = 'sounds/chat_mensaje.mp3';

  FlutterLocalNotificationsPlugin? _plugin;
  AudioPlayer? _player;
  AudioPlayer? _pitidoPlayer;
  AudioContext? _audioCtx;
  Timer? _vibTimer;
  Timer? _pollTimer;
  Timer? _ringtoneWatchdog;
  Completer<bool?>? _resultado;
  String? _solicitudId;
  Future<bool?>? _iniciarEnCurso;
  int _epoch = 0;
  bool _puedeVibrar = false;
  final Set<String> _sinTimbre = <String>{};
  final Set<String> _pitidoInicioHecho = <String>{};

  String? get solicitudActiva => _solicitudId;
  bool get activa => _solicitudId != null;

  Future<void> init(FlutterLocalNotificationsPlugin plugin) async {
    _plugin = plugin;
    _audioCtx = _crearContextoAlarma();
    try {
      await AudioPlayer.global.setAudioContext(_audioCtx!);
    } catch (_) {}

    _player ??= AudioPlayer();
    try {
      await _player!.setAudioContext(_audioCtx!);
      await _player!.setVolume(1.0);
    } catch (_) {}

    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      try {
        await android.deleteNotificationChannel(canalIdLegacy);
        await android.deleteNotificationChannel(canalIdLegacyV1);
        await android.deleteNotificationChannel(canalIdLegacyV0);
      } catch (_) {}

      const canal = AndroidNotificationChannel(
        canalId,
        canalNombre,
        description:
            'Alerta persistente de viaje. Suena aunque el teléfono esté en vibración (volumen de alarma).',
        importance: Importance.max,
        playSound: false,
        enableVibration: false,
        showBadge: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      );
      await android.createNotificationChannel(canal);
    }
  }

  static AudioContext _crearContextoAlarma() {
    // Mismo patrón que chat / «Buscando viajes»: USAGE_ALARM suena en silencio.
    return AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: {AVAudioSessionOptions.mixWithOthers},
      ),
      android: AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: true,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.alarm,
        audioFocus: AndroidAudioFocus.gain,
      ),
    );
  }

  /// Consulta de precio y búsqueda de socio deben sonar igual.
  bool _estadoAlertaTaxiActiva(String raw) {
    final e = raw.trim().toLowerCase();
    return e == 'buscando_chofer' ||
        e == 'pidiendo_precios' ||
        e == 'reserva_pendiente_chofer' ||
        e == 'reserva_reasignando';
  }

  /// Arranca ringtone + notificación ongoing. No cierra sola.
  Future<bool?> iniciar({
    required String solicitudId,
    String titulo = 'Viaje de taxi entrante',
    String mensaje = 'Acepta o rechaza. Esta alerta no se quita sola.',
  }) {
    final id = solicitudId.trim();
    if (id.isEmpty) return Future.value(null);
    if (_sinTimbre.contains(id)) return Future.value(false);

    // Si ya hay una alerta activa de la misma solicitud, unirse a ella.
    final activo = _resultado;
    if (_solicitudId == id && activo != null && !activo.isCompleted) {
      return activo.future;
    }

    // Serializar inicios concurrentes (FCM + Realtime + dialog a la vez).
    final enCurso = _iniciarEnCurso;
    if (enCurso != null) {
      return enCurso.then((_) async {
        final r = _resultado;
        if (_solicitudId == id && r != null && !r.isCompleted) {
          return r.future;
        }
        return iniciar(
          solicitudId: id,
          titulo: titulo,
          mensaje: mensaje,
        );
      });
    }

    final future = _iniciarInterno(
      id: id,
      titulo: titulo,
      mensaje: mensaje,
    );
    _iniciarEnCurso = future;
    future.whenComplete(() {
      if (_iniciarEnCurso == future) {
        _iniciarEnCurso = null;
      }
    });
    return future;
  }

  Future<bool?> _iniciarInterno({
    required String id,
    required String titulo,
    required String mensaje,
  }) async {
    final activo = _resultado;
    if (_solicitudId == id && activo != null && !activo.isCompleted) {
      return activo.future;
    }

    if (_solicitudId != null && _solicitudId != id) {
      await detener(motivo: 'reemplazo');
    }

    final otraVez = _resultado;
    if (_solicitudId == id && otraVez != null && !otraVez.isCompleted) {
      return otraVez.future;
    }

    // Completer LOCAL: nunca usar _resultado! tras un await.
    final completer = Completer<bool?>();
    _solicitudId = id;
    _resultado = completer;

    try {
      // No arrancar ringtone si el viaje ya no está en búsqueda o consulta.
      final oferta = await TaxiChoferService.instance.detalleOferta(id);
      if (oferta == null || !_estadoAlertaTaxiActiva(oferta.estado)) {
        if (identical(_resultado, completer) && !completer.isCompleted) {
          completer.complete(false);
        }
        if (identical(_resultado, completer)) {
          _solicitudId = null;
          _resultado = null;
        }
        print('🚕 Alerta taxi omitida: viaje $id ya no disponible');
        return completer.future;
      }

      if (_sinTimbre.contains(id)) {
        if (!completer.isCompleted) completer.complete(false);
        return completer.future;
      }
      _puedeVibrar = true;
      await _mostrarNotificacionPersistente(
        titulo: titulo,
        mensaje: mensaje,
        solicitudId: id,
      );
      // Si otro detener/reemplazo invalidó este ciclo, no seguir.
      if (!identical(_resultado, completer) || !_puedeVibrar) {
        await _cortarMedios();
        if (!completer.isCompleted) completer.complete(null);
        return completer.future;
      }

      await _iniciarRingtoneYVibracion();
      if (!identical(_resultado, completer) || _sinTimbre.contains(id)) {
        await _cortarMedios();
        if (!completer.isCompleted) completer.complete(null);
        return completer.future;
      }

      _iniciarPollEstado(id);
    } catch (e) {
      print('⚠️ iniciar taxi alerta: $e');
      if (identical(_resultado, completer) && !completer.isCompleted) {
        // Mantener alerta aunque falle notif/ringtone (el modal igual sirve).
      }
    }

    return completer.future;
  }

  /// Un solo pitido cuando el pasajero ya pagó y el viaje comenzó.
  /// No usa el timbre en bucle de la oferta.
  Future<void> pitidoViajeComenzo(String solicitudId) async {
    final id = solicitudId.trim();
    if (id.isEmpty || !_pitidoInicioHecho.add(id)) return;
    try {
      _pitidoPlayer ??= AudioPlayer();
      final ctx = _audioCtx ?? _crearContextoAlarma();
      await _pitidoPlayer!.setAudioContext(ctx);
      await _pitidoPlayer!.setReleaseMode(ReleaseMode.release);
      await _pitidoPlayer!.setVolume(1.0);
      await _pitidoPlayer!.stop();
      await _pitidoPlayer!.play(AssetSource(_assetFallback));
    } catch (e) {
      print('⚠️ pitido viaje comenzó: $e');
    }
    unawaited(Future<void>.delayed(const Duration(milliseconds: 800), () async {
      try {
        if (await Vibration.hasVibrator() == true) {
          await Vibration.vibrate(duration: 700);
        }
      } catch (_) {}
    }));
  }

  /// El timbre en bucle solo vive en la pantalla abierta.
  /// El aviso con la app cerrada no arranca otro bucle: ese isolate no se puede apagar
  /// cuando el socio envía el precio y el teléfono se queda vibrando.
  Future<void> iniciarRingtoneEnSegundoPlano() async {}

  /// El socio ya envió el precio o el viaje ya no es suyo: no volver a sonar.
  void marcarSinTimbre(String solicitudId) {
    final id = solicitudId.trim();
    if (id.isNotEmpty) _sinTimbre.add(id);
  }

  /// Corta timbre y vibración de esta solicitud sin apagar una alerta más nueva.
  Future<void> silenciarSolicitud(String solicitudId) async {
    final id = solicitudId.trim();
    if (id.isEmpty) return;
    _sinTimbre.add(id);
    _puedeVibrar = false;
    if (_solicitudId != null && _solicitudId != id) return;
    _epoch++;
    _solicitudId = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _vibTimer?.cancel();
    _vibTimer = null;
    _ringtoneWatchdog?.cancel();
    _ringtoneWatchdog = null;
    try {
      await _plugin?.cancel(notificacionId);
    } catch (_) {}
    await _cortarMedios();
  }

  /// App cerrada / isolate background: solo notification ongoing.
  Future<void> mostrarSoloNotificacionPersistente({
    required String solicitudId,
    String titulo = 'Viaje de taxi entrante',
    String mensaje = 'Toca para aceptar o rechazar',
  }) async {
    final id = solicitudId.trim();
    if (id.isEmpty || _sinTimbre.contains(id)) return;
    _solicitudId ??= id;
    try {
      await _mostrarNotificacionPersistente(
        titulo: titulo,
        mensaje: mensaje,
        solicitudId: id,
      );
    } catch (e) {
      print('⚠️ notif persistente background: $e');
    }
  }

  Future<void> onAceptadoDesdeUi() async {
    await detener(motivo: 'aceptado', resultado: true);
  }

  Future<void> onRechazadoDesdeUi() async {
    await detener(motivo: 'rechazado', resultado: false);
  }

  Future<void> detener({
    required String motivo,
    bool? resultado,
  }) async {
    final id = _solicitudId;
    final completer = _resultado;
    _puedeVibrar = false;
    _epoch++;
    if (id != null) _sinTimbre.add(id);
    _solicitudId = null;
    _resultado = null;

    _pollTimer?.cancel();
    _pollTimer = null;
    await _cortarMedios();
    try {
      await _plugin?.cancel(notificacionId);
    } catch (_) {}

    if (completer != null && !completer.isCompleted) {
      completer.complete(resultado);
    }

    // Cerrar el modal de llamada si el viaje ya no es ofrecible a este socio.
    // (aceptado/rechazado desde UI hacen pop ellos mismos; no duplicar).
    if (motivo == 'tomado_por_otro' ||
        motivo == 'ya_no_disponible' ||
        motivo == 'cancelado_pasajero') {
      final nav = RepartidorNavigator.state;
      if (nav != null && nav.canPop()) {
        try {
          nav.pop(false);
        } catch (_) {}
      }
    }

    print('🚕 Alerta taxi detenida ($motivo) solicitud=$id');
  }

  /// True solo si el viaje activo del chofer autenticado es esta solicitud.
  Future<bool> _esMiViajeActivo(String solicitudId) async {
    try {
      final activo = await TaxiChoferService.instance.viajeActivo();
      if (activo == null) return false;
      return activo.id.trim() == solicitudId.trim();
    } catch (_) {
      return false;
    }
  }

  void _iniciarPollEstado(String solicitudId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (_solicitudId != solicitudId) return;
      try {
        final o = await TaxiChoferService.instance.detalleOferta(solicitudId);
        if (_solicitudId != solicitudId) return;
        if (o == null) {
          await detener(motivo: 'ya_no_disponible', resultado: false);
          return;
        }
        final est = o.estado.toLowerCase();
        if (est == 'aceptado' || est == 'en_camino' || est == 'en_viaje') {
          // Crítico: otro socio puede haber aceptado → estado "aceptado"
          // no significa "yo lo tomé". Confirmar con viaje activo.
          final mio = await _esMiViajeActivo(solicitudId);
          if (_solicitudId != solicitudId) return;
          if (mio) {
            await detener(motivo: 'viaje_en_curso', resultado: true);
          } else {
            await detener(motivo: 'tomado_por_otro', resultado: false);
          }
          return;
        }
        if (est == 'cancelado') {
          await detener(motivo: 'cancelado_pasajero', resultado: false);
          return;
        }
        if (!_estadoAlertaTaxiActiva(est)) {
          await detener(motivo: 'tomado_por_otro', resultado: false);
        }
      } catch (_) {
        // No tumbar la alerta por un fallo puntual de red.
      }
    });
  }

  Future<void> _cortarMedios() async {
    _puedeVibrar = false;
    _vibTimer?.cancel();
    _vibTimer = null;
    _ringtoneWatchdog?.cancel();
    _ringtoneWatchdog = null;
    try {
      await _plugin?.cancel(notificacionId);
    } catch (_) {}
    try {
      await Vibration.cancel();
    } catch (_) {}
    try {
      await _player?.stop();
    } catch (_) {}
  }

  Future<bool> _playAssetLoop(String asset, int epoch) async {
    try {
      if (epoch != _epoch) return false;
      final ctx = _audioCtx ?? _crearContextoAlarma();
      try {
        await AudioPlayer.global.setAudioContext(ctx);
      } catch (_) {}
      _player ??= AudioPlayer();
      final p = _player!;
      await p.setAudioContext(ctx);
      if (epoch != _epoch) return false;
      await p.setReleaseMode(ReleaseMode.loop);
      await p.setVolume(1.0);
      await p.stop();
      if (epoch != _epoch) return false;
      await p.setSource(AssetSource(asset));
      if (epoch != _epoch) {
        await p.stop();
        return false;
      }
      await p.resume();
      if (epoch != _epoch) {
        await p.stop();
        return false;
      }
      return true;
    } catch (e) {
      print('⚠️ Ringtone taxi $asset: $e');
      return false;
    }
  }

  Future<void> _iniciarRingtoneYVibracion() async {
    final epoch = _epoch;
    final solicitud = _solicitudId;
    if (solicitud != null && _sinTimbre.contains(solicitud)) return;
    _puedeVibrar = true;

    var ok = await _playAssetLoop(_assetRingtone, epoch);
    if (!ok && epoch == _epoch) {
      ok = await _playAssetLoop(_assetFallback, epoch);
    }
    if (epoch != _epoch || _solicitudId == null || !_puedeVibrar) {
      await _cortarMedios();
      return;
    }
    if (!ok) {
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
      if (epoch != _epoch) return;
    }

    Future<void> vibrar() async {
      if (!_puedeVibrar || epoch != _epoch) return;
      try {
        if (await Vibration.hasVibrator() == true) {
          if (!_puedeVibrar || epoch != _epoch) return;
          await Vibration.vibrate(pattern: [0, 400, 200, 400], repeat: -1);
          if (!_puedeVibrar || epoch != _epoch) {
            await Vibration.cancel();
          }
        }
      } catch (_) {}
    }

    if (!_puedeVibrar || epoch != _epoch) return;
    unawaited(vibrar());
    _vibTimer?.cancel();
    _vibTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_puedeVibrar || epoch != _epoch) {
        _vibTimer?.cancel();
        _vibTimer = null;
        return;
      }
      unawaited(vibrar());
    });

    _ringtoneWatchdog?.cancel();
    _ringtoneWatchdog = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (epoch != _epoch || _solicitudId == null) return;
      final p = _player;
      if (p == null) return;
      try {
        if (p.state == PlayerState.playing) return;
        await _playAssetLoop(_assetRingtone, epoch);
      } catch (_) {}
    });
  }

  Future<void> _mostrarNotificacionPersistente({
    required String titulo,
    required String mensaje,
    required String solicitudId,
  }) async {
    final plugin = _plugin;
    if (plugin == null) return;

    final payload = [
      RepartidorNotificacionTipos.taxiViaje,
      '',
      solicitudId,
      '',
      '',
    ].join('|');

    final android = AndroidNotificationDetails(
      canalId,
      canalNombre,
      channelDescription:
          'Alerta persistente de viaje. No se quita hasta aceptar o rechazar.',
      importance: Importance.max,
      priority: Priority.max,
      playSound: false,
      enableVibration: false,
      icon: '@mipmap/ic_launcher',
      category: AndroidNotificationCategory.status,
      ongoing: true,
      autoCancel: false,
      fullScreenIntent: true,
      visibility: NotificationVisibility.public,
      styleInformation: BigTextStyleInformation(
        mensaje,
        contentTitle: titulo,
        summaryText: 'Responde para silenciar',
      ),
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'taxi_abrir',
          'Ver viaje',
          showsUserInterface: true,
          cancelNotification: false,
        ),
      ],
    );

    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );

    try {
      await plugin.show(
        notificacionId,
        titulo,
        mensaje,
        NotificationDetails(android: android, iOS: ios),
        payload: payload,
      );
      if (_sinTimbre.contains(solicitudId.trim())) {
        await plugin.cancel(notificacionId);
      }
    } catch (e) {
      print('⚠️ Notificación persistente taxi: $e');
    }
  }
}
