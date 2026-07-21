import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
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
  static const String canalId = 'taxi_llamada_v1';
  static const String canalNombre = 'Llamadas de viaje (taxi)';
  static const String _assetRingtone = 'sounds/chat_mensaje.mp3';

  FlutterLocalNotificationsPlugin? _plugin;
  AudioPlayer? _player;
  AudioContext? _audioCtx;
  Timer? _vibTimer;
  Timer? _pollTimer;
  Completer<bool?>? _resultado;
  String? _solicitudId;
  Future<bool?>? _iniciarEnCurso;

  String? get solicitudActiva => _solicitudId;
  bool get activa => _solicitudId != null;

  Future<void> init(FlutterLocalNotificationsPlugin plugin) async {
    _plugin = plugin;
    _audioCtx = _crearContextoAlarma();
    try {
      await AudioPlayer.global.setAudioContext(_audioCtx!);
    } catch (_) {}

    final android = plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      const canal = AndroidNotificationChannel(
        canalId,
        canalNombre,
        description:
            'Alerta persistente de viaje entrante. Suena hasta aceptar o rechazar.',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('chat_mensaje'),
        enableVibration: true,
        showBadge: true,
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
      );
      await android.createNotificationChannel(canal);
    }
  }

  static AudioContext _crearContextoAlarma() {
    return AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: {AVAudioSessionOptions.mixWithOthers},
      ),
      android: AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: true,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.notificationRingtone,
        audioFocus: AndroidAudioFocus.gainTransientMayDuck,
      ),
    );
  }

  /// Arranca ringtone + notificación ongoing. No cierra sola.
  Future<bool?> iniciar({
    required String solicitudId,
    String titulo = 'Viaje de taxi entrante',
    String mensaje = 'Acepta o rechaza. Esta alerta no se quita sola.',
  }) {
    final id = solicitudId.trim();
    if (id.isEmpty) return Future.value(null);

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
      await _mostrarNotificacionPersistente(
        titulo: titulo,
        mensaje: mensaje,
        solicitudId: id,
      );
      // Si otro detener/reemplazo invalidó este ciclo, no seguir.
      if (!identical(_resultado, completer)) {
        if (!completer.isCompleted) completer.complete(null);
        return completer.future;
      }

      await _iniciarRingtoneYVibracion();
      if (!identical(_resultado, completer)) {
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

  /// App cerrada / isolate background: solo notification ongoing.
  Future<void> mostrarSoloNotificacionPersistente({
    required String solicitudId,
    String titulo = 'Viaje de taxi entrante',
    String mensaje = 'Toca para aceptar o rechazar',
  }) async {
    final id = solicitudId.trim();
    if (id.isEmpty) return;
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
    _solicitudId = null;
    _resultado = null;

    _pollTimer?.cancel();
    _pollTimer = null;
    _vibTimer?.cancel();
    _vibTimer = null;

    try {
      await _player?.stop();
    } catch (_) {}

    try {
      await _plugin?.cancel(notificacionId);
    } catch (_) {}

    if (completer != null && !completer.isCompleted) {
      completer.complete(resultado);
    }

    // Solo cerrar el modal si otro se quedó con el viaje / ya no existe.
    // Si yo acepté, el dialog hace pop(true) y abre el mapa.
    if (motivo == 'tomado_por_otro' || motivo == 'ya_no_disponible') {
      final nav = RepartidorNavigator.state;
      if (nav != null && nav.canPop()) {
        try {
          nav.pop(false);
        } catch (_) {}
      }
    }

    print('🚕 Alerta taxi detenida ($motivo) solicitud=$id');
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
        // Yo (u otro flujo) ya aceptó: silenciar alerta SIN tratarlo como perdido.
        if (est == 'aceptado' || est == 'en_viaje') {
          await detener(motivo: 'viaje_en_curso', resultado: true);
          return;
        }
        if (est != 'buscando_chofer') {
          await detener(motivo: 'tomado_por_otro', resultado: false);
        }
      } catch (_) {
        // No tumbar la alerta por un fallo puntual de red.
      }
    });
  }

  Future<void> _iniciarRingtoneYVibracion() async {
    try {
      final ctx = _audioCtx ?? _crearContextoAlarma();
      _player ??= AudioPlayer();
      await _player!.setAudioContext(ctx);
      await _player!.setReleaseMode(ReleaseMode.loop);
      await _player!.setVolume(1.0);
      await _player!.stop();
      await _player!.play(
        AssetSource(_assetRingtone),
        mode: PlayerMode.mediaPlayer,
      );
    } catch (e) {
      print('⚠️ Ringtone taxi: $e');
    }

    _vibTimer?.cancel();
    _vibTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        if (await Vibration.hasVibrator() == true) {
          await Vibration.vibrate(pattern: [0, 500, 200, 500]);
        }
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
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('chat_mensaje'),
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 600, 400, 600, 400, 600]),
      icon: '@mipmap/ic_launcher',
      category: AndroidNotificationCategory.call,
      audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
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
    } catch (e) {
      print('⚠️ Notificación persistente taxi: $e');
    }
  }
}
