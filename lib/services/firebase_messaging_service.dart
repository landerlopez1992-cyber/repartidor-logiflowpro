import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../models/orden.dart';
import '../navigation/repartidor_navigator.dart';
import '../screens/chat_repartidor_lista_screen.dart';
import '../screens/chat_soporte_filtrado_screen.dart';
import '../screens/detalle_orden_screen.dart';
import '../screens/historial_pagos_completo_screen.dart';
import '../screens/taxi_incoming_call_dialog.dart';
import '../constants/repartidor_notificacion_tipos.dart';
import 'taxi_llamada_persistente_service.dart';

/// Push FCM para la app Repartidor (app cerrada / background).
class FirebaseMessagingService {
  static final FirebaseMessagingService _instance =
      FirebaseMessagingService._internal();
  factory FirebaseMessagingService() => _instance;
  FirebaseMessagingService._internal();

  static const String prefsPushEnabled = 'push_notifications_repartidor';
  static const String _prefsToken = 'fcm_token_repartidor';
  static const String androidChannelId = 'ordenes_channel';

  FirebaseMessaging get _firebaseMessaging => FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  bool _initialized = false;

  String? get fcmToken => _fcmToken;

  static Future<bool> isPushEnabledPreference() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(prefsPushEnabled) ?? true;
  }

  Future<void> initialize() async {
    if (kIsWeb) return;
    if (_initialized) return;

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      await _initLocalNotifications();

      final enabled = await isPushEnabledPreference();
      if (!enabled) {
        _initialized = true;
        return;
      }

      await _requestPermissions();
      await _getAndRegisterToken();
      _setupMessageHandlers();
      _initialized = true;
      print('✅ Firebase Messaging (repartidor) inicializado');
    } catch (e) {
      print('❌ Error inicializando Firebase Messaging: $e');
    }
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _local.initialize(
      const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
        macOS: iosInit,
      ),
      onDidReceiveNotificationResponse: (response) {
        unawaited(handlePayload(response.payload));
      },
    );

    final androidImpl = _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      await androidImpl.requestNotificationsPermission();
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          androidChannelId,
          'Órdenes',
          description: 'Notificaciones de órdenes, nómina y chat',
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        ),
      );
    }

    final launch = await _local.getNotificationAppLaunchDetails();
    final launchPayload = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true &&
        launchPayload != null &&
        launchPayload.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 900), () {
        unawaited(handlePayload(launchPayload));
      });
    }
  }

  Future<void> _requestPermissions() async {
    await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    await _firebaseMessaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> _getAndRegisterToken() async {
    try {
      _fcmToken = await _firebaseMessaging.getToken();
      if (_fcmToken == null || _fcmToken!.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsToken, _fcmToken!);
      await _sendTokenToBackend(_fcmToken!, enabled: true);
      _firebaseMessaging.onTokenRefresh.listen((t) async {
        _fcmToken = t;
        final p = await SharedPreferences.getInstance();
        await p.setString(_prefsToken, t);
        await _sendTokenToBackend(t, enabled: true);
      });
    } catch (e) {
      print('❌ Error obteniendo FCM Token: $e');
    }
  }

  /// Reasocia el token con el usuario autenticado tras el login.
  Future<void> refreshRegistrationForCurrentUser() async {
    if (kIsWeb || !(await isPushEnabledPreference())) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      var token = _fcmToken ?? await _firebaseMessaging.getToken();
      if (token == null || token.isEmpty) {
        await Future<void>.delayed(const Duration(seconds: 2));
        token = await _firebaseMessaging.getToken();
      }
      if (token == null || token.isEmpty) return;
      _fcmToken = token;
      await _sendTokenToBackend(token, enabled: true);
    } catch (e) {
      print('❌ Error re-registrando token FCM: $e');
    }
  }

  Future<void> _sendTokenToBackend(String token, {required bool enabled}) async {
    try {
      if (supabase.auth.currentSession == null) {
        print('ℹ️ FCM: sin sesión, se registrará al login');
        return;
      }
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final userRow = await supabase
          .from('usuarios')
          .select('tenant_id')
          .eq('auth_id', user.id)
          .maybeSingle();
      final tenantId = userRow?['tenant_id']?.toString();
      if (tenantId == null || tenantId.isEmpty) {
        print('⚠️ FCM: sin tenant_id');
        return;
      }

      String? packageName;
      try {
        packageName = (await PackageInfo.fromPlatform()).packageName;
      } catch (_) {}

      final platform = (!kIsWeb && Platform.isIOS) ? 'ios' : 'android';
      await supabase.rpc(
        'registrar_repartidor_app_push_token',
        params: {
          'p_tenant_id': tenantId,
          'p_fcm_token': token,
          'p_platform': platform,
          'p_enabled': enabled,
          'p_package_name': packageName,
        },
      );
      print('✅ Token FCM repartidor registrado');
    } catch (e) {
      print('❌ Error enviando token FCM: $e');
    }
  }

  void _setupMessageHandlers() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final tipo = (message.data['tipo'] ?? message.data['type'] ?? '')
          .toString()
          .trim();
      // Taxi: abrir modal tipo llamada de inmediato (foreground).
      if (RepartidorNotificacionTipos.tiposTaxiViaje.contains(tipo)) {
        unawaited(handleRemoteMessage(message));
        return;
      }
      unawaited(_showLocalFromRemote(message));
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      unawaited(handleRemoteMessage(message));
    });

    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        Future.delayed(const Duration(milliseconds: 900), () {
          unawaited(handleRemoteMessage(message));
        });
      }
    });
  }

  Future<void> _showLocalFromRemote(RemoteMessage message) async {
    final title = message.notification?.title ??
        message.data['titulo']?.toString() ??
        'Aviso';
    final body = message.notification?.body ??
        message.data['mensaje']?.toString() ??
        '';
    final payload = payloadFromData(message.data);
    await _local.show(
      message.hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          androidChannelId,
          'Órdenes',
          channelDescription: 'Notificaciones de órdenes, nómina y chat',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  static String? payloadFromData(Map<String, dynamic> data) {
    final tipo = (data['tipo'] ?? data['type'] ?? '').toString().trim();
    if (tipo.isEmpty) return null;
    final ordenId = (data['orden_id'] ?? '').toString().trim();
    final numeroOrden = (data['numero_orden'] ?? '').toString().trim();
    final pagoId = (data['pago_id'] ?? '').toString().trim();
    final conversacionId = (data['conversacion_id'] ?? '').toString().trim();
    return encodePayload(
      tipo: tipo,
      ordenId: ordenId,
      numeroOrden: numeroOrden,
      pagoId: pagoId,
      conversacionId: conversacionId,
    );
  }

  static String encodePayload({
    required String tipo,
    String ordenId = '',
    String numeroOrden = '',
    String pagoId = '',
    String conversacionId = '',
  }) {
    return [
      tipo,
      ordenId,
      numeroOrden,
      pagoId,
      conversacionId,
    ].join('|');
  }

  Future<void> handleRemoteMessage(RemoteMessage message) async {
    await handlePayload(payloadFromData(message.data));
  }

  /// Deep link: orden / nómina / chat.
  Future<void> handlePayload(String? payload) async {
    if (payload == null || payload.isEmpty) return;
    final parts = payload.split('|');
    final tipo = parts.isNotEmpty ? parts[0].trim() : '';
    final ordenId = parts.length > 1 ? parts[1].trim() : '';
    final numeroOrden = parts.length > 2 ? parts[2].trim() : '';
    final pagoId = parts.length > 3 ? parts[3].trim() : '';
    final conversacionId = parts.length > 4 ? parts[4].trim() : '';

    // Compat: payload local antiguo = solo número de orden
    if (tipo.isNotEmpty &&
        !tipo.contains('_') &&
        tipo != 'PAGO_ACEPTADO' &&
        tipo != 'mensaje_soporte' &&
        tipo != 'MENSAJE_SOPORTE' &&
        tipo != 'chat_soporte' &&
        ordenId.isEmpty &&
        numeroOrden.isEmpty &&
        !tipo.toLowerCase().contains('orden') &&
        !tipo.toLowerCase().contains('pago')) {
      // Si parece un número de orden suelto
      await _abrirOrden(ordenId: '', numeroOrden: tipo);
      return;
    }

    final t = tipo.toUpperCase();
    if (RepartidorNotificacionTipos.tiposTaxiViaje.contains(tipo) ||
        t == 'TAXI_VIAJE') {
      final solicitudId =
          numeroOrden.isNotEmpty ? numeroOrden : ordenId;
      if (solicitudId.isEmpty) return;
      final nav = RepartidorNavigator.state;
      if (nav == null) return;
      // El dialog ya arranca la alerta persistente (evitar doble iniciar).
      await TaxiIncomingCallDialog.show(nav.context, solicitudId);
      return;
    }
    if (t == 'NUEVA_ORDEN' ||
        t == 'ORDEN_NUEVA' ||
        tipo == 'nueva_orden' ||
        tipo == 'ORDEN_NUEVA') {
      await _abrirOrden(ordenId: ordenId, numeroOrden: numeroOrden);
      return;
    }
    if (t == 'PAGO_ACEPTADO' || tipo == 'PAGO_ACEPTADO') {
      await _abrirHistorialNomina(pagoId: pagoId);
      return;
    }
    if (tipo == 'mensaje_soporte' ||
        tipo == 'MENSAJE_SOPORTE' ||
        tipo == 'chat_soporte' ||
        t.contains('MENSAJE') ||
        t.contains('CHAT')) {
      await _abrirChat(conversacionId: conversacionId);
      return;
    }

    // Fallback: si hay orden_id en payload
    if (ordenId.isNotEmpty || numeroOrden.isNotEmpty) {
      await _abrirOrden(ordenId: ordenId, numeroOrden: numeroOrden);
    }
  }

  Future<void> _abrirOrden({
    required String ordenId,
    required String numeroOrden,
  }) async {
    final nav = RepartidorNavigator.state;
    if (nav == null) return;
    try {
      Map<String, dynamic>? row;
      if (ordenId.isNotEmpty) {
        row = await supabase.from('ordenes').select('*').eq('id', ordenId).maybeSingle();
      }
      if (row == null && numeroOrden.isNotEmpty) {
        row = await supabase
            .from('ordenes')
            .select('*')
            .eq('numero_orden', numeroOrden)
            .maybeSingle();
      }
      if (row == null) return;
      final orden = Orden.fromJson(row);
      await nav.push(
        MaterialPageRoute(builder: (_) => DetalleOrdenScreen(orden: orden)),
      );
    } catch (e) {
      print('⚠️ Deep link orden: $e');
    }
  }

  Future<void> _abrirHistorialNomina({required String pagoId}) async {
    final nav = RepartidorNavigator.state;
    if (nav == null) return;
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      final u = await supabase
          .from('usuarios')
          .select('id, nombre')
          .eq('auth_id', user.id)
          .maybeSingle();
      final rid = u?['id']?.toString() ?? '';
      final nombre = u?['nombre']?.toString() ?? 'Repartidor';
      if (rid.isEmpty) return;
      await nav.push(
        MaterialPageRoute(
          builder: (_) => HistorialPagosCompletoScreen(
            repartidorId: rid,
            repartidorNombre: nombre,
          ),
        ),
      );
    } catch (e) {
      print('⚠️ Deep link nómina: $e');
    }
  }

  Future<void> _abrirChat({required String conversacionId}) async {
    final nav = RepartidorNavigator.state;
    if (nav == null) return;
    try {
      if (conversacionId.isEmpty) {
        await nav.push(
          MaterialPageRoute(builder: (_) => const ChatRepartidorListaScreen()),
        );
        return;
      }
      final user = supabase.auth.currentUser;
      if (user == null) return;
      // Abrir lista; si hay un mensaje reciente de la empresa, intentar chat filtrado.
      final msg = await supabase
          .from('mensajes_soporte')
          .select('remitente_auth_id, remitente_nombre')
          .eq('conversacion_id', conversacionId)
          .neq('remitente_auth_id', user.id)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      final remitenteId = msg?['remitente_auth_id']?.toString() ?? '';
      final nombre = msg?['remitente_nombre']?.toString() ?? 'Tu empresa';
      if (remitenteId.isEmpty) {
        await nav.push(
          MaterialPageRoute(builder: (_) => const ChatRepartidorListaScreen()),
        );
        return;
      }
      await nav.push(
        MaterialPageRoute(
          builder: (_) => ChatSoporteFiltradoScreen(
            conversacionId: conversacionId,
            remitenteAuthId: remitenteId,
            nombreRemitente: nombre,
            rolRemitente: 'ADMINISTRADOR',
          ),
        ),
      );
    } catch (e) {
      print('⚠️ Deep link chat: $e');
      try {
        await nav.push(
          MaterialPageRoute(builder: (_) => const ChatRepartidorListaScreen()),
        );
      } catch (_) {}
    }
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}

  final tipo = (message.data['tipo'] ?? message.data['type'] ?? '')
      .toString()
      .trim();
  final solicitudId = (message.data['numero_orden'] ??
          message.data['orden_id'] ??
          '')
      .toString()
      .trim();

  if (RepartidorNotificacionTipos.tiposTaxiViaje.contains(tipo) &&
      solicitudId.isNotEmpty) {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await plugin.initialize(
        const InitializationSettings(
          android: androidInit,
          iOS: iosInit,
          macOS: iosInit,
        ),
      );
      await TaxiLlamadaPersistenteService.instance.init(plugin);
      final titulo = message.notification?.title ??
          message.data['titulo']?.toString() ??
          'Viaje de taxi entrante';
      final cuerpo = message.notification?.body ??
          message.data['mensaje']?.toString() ??
          'Toca para aceptar o rechazar. La alerta no se quita sola.';
      await TaxiLlamadaPersistenteService.instance
          .mostrarSoloNotificacionPersistente(
        solicitudId: solicitudId,
        titulo: titulo,
        mensaje: cuerpo,
      );
    } catch (e) {
      print('⚠️ Background taxi persistente: $e');
    }
  }

  print('📱 Push repartidor background: ${message.messageId}');
}
