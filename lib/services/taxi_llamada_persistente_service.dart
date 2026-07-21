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
    String mensaje =
        'Acepta o rechaza. Esta alerta no se quita sola.',
  }) async {
    final id = solicitudId.trim();
    if (id.isEmpty) return null;

    if (_solicitudId == id && _resultado != null) {
      return _resultado!.future;
    }

    if (_solicitudId != null && _solicitudId != id) {
      await detener(motivo: 'reemplazo');
    }

    _solicitudId = id;
    _resultado = Completer<bool?>();

    await _mostrarNotificacionPersistente(
      titulo: titulo,
      mensaje: mensaje,
      solicitudId: id,
    );
    await _iniciarRingtoneYVibracion();
    _iniciarPollEstado(id);

    return _resultado!.future;
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
    await _mostrarNotificacionPersistente(
      titulo: titulo,
      mensaje: mensaje,
      solicitudId: id,
    );
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
    _solicitudId = null;

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

    if (_resultado != null && !_resultado!.isCompleted) {
      _resultado!.complete(resultado);
    }
    _resultado = null;

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
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_solicitudId != solicitudId) return;
      try {
        final o = await TaxiChoferService.instance.detalleOferta(solicitudId);
        if (_solicitudId != solicitudId) return;
        if (o == null || o.estado != 'buscando_chofer') {
          await detener(
            motivo: o == null ? 'ya_no_disponible' : 'tomado_por_otro',
            resultado: false,
          );
        }
      } catch (_) {}
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
