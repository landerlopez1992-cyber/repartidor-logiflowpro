import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

/// Caché + avisos locales de reservas (día del viaje, también sin red).
class TaxiReservaReminderChoferService {
  TaxiReservaReminderChoferService._();
  static final TaxiReservaReminderChoferService instance =
      TaxiReservaReminderChoferService._();

  static const _prefsKey = 'taxi_reservas_chofer_cache_v1';
  static const _channelId = 'taxi_reservas_chofer';
  static const _channelName = 'Reservas de viajes';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _inited = false;

  Future<void> ensureInit() async {
    if (_inited) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    // Darwin sirve para iOS y macOS (debug en Mac).
    const darwin = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(
        android: android,
        iOS: darwin,
        macOS: darwin,
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: 'Avisos del día de la reserva (también offline).',
            importance: Importance.high,
          ),
        );
    _inited = true;
  }

  Future<void> syncFromReservas(List<Map<String, dynamic>> reservas) async {
    await ensureInit();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(reservas));

    for (final r in reservas) {
      final id = r['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      await _plugin.cancel(_notifId(id, 1));
      await _plugin.cancel(_notifId(id, 2));
    }

    final loc = tz.getLocation('America/Havana');
    final now = tz.TZDateTime.now(loc);

    for (final r in reservas) {
      final id = r['id']?.toString() ?? '';
      final prog = DateTime.tryParse(r['programado_en']?.toString() ?? '');
      if (id.isEmpty || prog == null) continue;
      final localProg = prog.toLocal();
      final origen = (r['origen_texto']?.toString() ?? 'recogida').trim();
      final horaTxt =
          '${localProg.hour.toString().padLeft(2, '0')}:${localProg.minute.toString().padLeft(2, '0')}';
      final dia8 = tz.TZDateTime(
        loc,
        localProg.year,
        localProg.month,
        localProg.day,
        8,
      );
      final horaViaje = tz.TZDateTime.from(localProg, loc);

      if (dia8.isAfter(now)) {
        await _zoned(
          _notifId(id, 1),
          dia8,
          'Hoy tienes un viaje',
          'Hoy a las $horaTxt · Recogida: ${origen.length > 48 ? '${origen.substring(0, 48)}…' : origen}',
          id,
        );
      } else if (dia8.year == now.year &&
          dia8.month == now.month &&
          dia8.day == now.day &&
          horaViaje.isAfter(now) &&
          now.hour < 12) {
        await _plugin.show(
          _notifId(id, 1),
          'Hoy tienes un viaje',
          'Hoy a las $horaTxt · Recogida: ${origen.length > 48 ? '${origen.substring(0, 48)}…' : origen}',
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              _channelName,
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          payload: id,
        );
      }

      final unaHora = horaViaje.subtract(const Duration(hours: 1));
      if (unaHora.isAfter(now)) {
        await _zoned(
          _notifId(id, 2),
          unaHora,
          'Viaje en 1 hora',
          'Cita a las $horaTxt · Dirígete a la recogida.',
          id,
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> rescheduleFromCache() async {
    final c = await loadCache();
    if (c.isEmpty) return;
    await syncFromReservas(c);
  }

  Future<void> cancelReserva(String id) async {
    await ensureInit();
    await _plugin.cancel(_notifId(id, 1));
    await _plugin.cancel(_notifId(id, 2));
    final next =
        (await loadCache()).where((e) => e['id']?.toString() != id).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(next));
  }

  Future<void> _zoned(
    int id,
    tz.TZDateTime when,
    String title,
    String body,
    String payload,
  ) async {
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  int _notifId(String solicitudId, int slot) {
    var h = 0;
    for (final c in solicitudId.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return (h + slot * 19) % 2000000000;
  }
}
