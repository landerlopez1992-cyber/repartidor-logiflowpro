import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

/// Sonido y notificación local cuando llega un mensaje de la empresa (chat soporte).
/// Configurado para sonar aunque el teléfono esté en modo silencio (volumen de alarma / playback iOS).
class RepartidorChatMensajeSonidoService {
  RepartidorChatMensajeSonidoService._();

  static const _assetSonido = 'sounds/chat_mensaje.mp3';
  /// Canal nuevo (v2): usa stream de alarma en Android; el canal anterior no se puede migrar.
  static const _canalAndroidId = 'chat_mensajes_alerta_v2';
  static const _canalAndroidNombre = 'Mensajes de soporte (alerta)';
  static const _canalAndroidIdLegacy = 'chat_mensajes_channel';

  static FlutterLocalNotificationsPlugin? _notificaciones;
  static AudioPlayer? _reproductor;
  static AudioContext? _contextoAlarma;

  /// Conversación abierta en pantalla de chat (no alertar si coincide).
  static String? conversacionActivaId;

  static String? _ultimoMensajeAlertado;
  static DateTime? _ultimaAlertaUtc;

  static AudioContext _crearContextoAlarma() {
    return AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: {
          AVAudioSessionOptions.defaultToSpeaker,
          AVAudioSessionOptions.mixWithOthers,
        },
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

  static Future<void> init(FlutterLocalNotificationsPlugin notificaciones) async {
    _notificaciones = notificaciones;
    _contextoAlarma = _crearContextoAlarma();

    await AudioPlayer.global.setAudioContext(_contextoAlarma!);

    _reproductor ??= AudioPlayer();
    await _reproductor!.setReleaseMode(ReleaseMode.stop);
    await _reproductor!.setVolume(1.0);
    await _reproductor!.setAudioContext(_contextoAlarma!);

    final android = notificaciones.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      try {
        await android.deleteNotificationChannel(_canalAndroidIdLegacy);
      } catch (_) {}

      const canal = AndroidNotificationChannel(
        _canalAndroidId,
        _canalAndroidNombre,
        description:
            'Mensajes de la empresa. Suena aunque el teléfono esté en silencio (volumen de alarma).',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('chat_mensaje'),
        enableVibration: true,
        showBadge: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      );
      await android.createNotificationChannel(canal);
    }
  }

  /// Llamar al recibir INSERT en `mensajes_soporte` desde la empresa.
  static Future<void> onMensajeEmpresaRecibido({
    required String mensajeId,
    required String conversacionId,
    required String preview,
    String tituloRemitente = 'Tu empresa',
  }) async {
    if (preview.trim().isEmpty) return;
    if (conversacionActivaId != null &&
        conversacionActivaId == conversacionId) {
      return;
    }

    if (mensajeId.isNotEmpty && mensajeId == _ultimoMensajeAlertado) {
      return;
    }
    final ahora = DateTime.now().toUtc();
    if (_ultimaAlertaUtc != null &&
        ahora.difference(_ultimaAlertaUtc!) < const Duration(seconds: 2)) {
      return;
    }

    _ultimoMensajeAlertado = mensajeId.isNotEmpty ? mensajeId : null;
    _ultimaAlertaUtc = ahora;

    await _vibrar();
    await _reproducirSonidoEnApp();
    await _mostrarNotificacionLocal(
      titulo: tituloRemitente,
      cuerpo: preview,
    );
  }

  static Future<void> _vibrar() async {
    try {
      if (await Vibration.hasVibrator() ?? false) {
        final tieneModo = await Vibration.hasAmplitudeControl() ?? false;
        if (tieneModo) {
          await Vibration.vibrate(
            pattern: [0, 200, 100, 350],
            intensities: [0, 255, 0, 255],
          );
        } else {
          await Vibration.vibrate(
            pattern: [0, 200, 100, 350],
          );
        }
      }
    } catch (_) {}
  }

  static Future<void> _reproducirSonidoEnApp() async {
    try {
      final ctx = _contextoAlarma ?? _crearContextoAlarma();
      final player = _reproductor ?? AudioPlayer();
      _reproductor = player;

      await player.setAudioContext(ctx);
      await player.setVolume(1.0);
      await player.stop();
      await player.play(
        AssetSource(_assetSonido),
        mode: PlayerMode.mediaPlayer,
      );
    } catch (e) {
      print('⚠️ No se pudo reproducir sonido de chat: $e');
    }
  }

  static Future<void> _mostrarNotificacionLocal({
    required String titulo,
    required String cuerpo,
  }) async {
    final plugin = _notificaciones;
    if (plugin == null) return;

    try {
      final android = AndroidNotificationDetails(
        _canalAndroidId,
        _canalAndroidNombre,
        channelDescription:
            'Mensajes de la empresa. Suena aunque el teléfono esté en silencio.',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('chat_mensaje'),
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
        category: AndroidNotificationCategory.alarm,
        audioAttributesUsage: AudioAttributesUsage.alarm,
        styleInformation: BigTextStyleInformation(cuerpo, contentTitle: titulo),
        visibility: NotificationVisibility.public,
        fullScreenIntent: false,
      );

      const ios = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        sound: 'chat_mensaje.wav',
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      await plugin.show(
        DateTime.now().millisecondsSinceEpoch % 100000,
        titulo,
        cuerpo,
        NotificationDetails(android: android, iOS: ios),
        payload: 'chat_soporte',
      );
    } catch (e) {
      print('⚠️ Notificación local de chat: $e');
    }
  }
}
