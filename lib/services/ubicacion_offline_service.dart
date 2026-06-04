import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import 'sync_service.dart';

/// Cola de posiciones GPS cuando no hay red (se suben al reconectar).
class UbicacionOfflineService {
  UbicacionOfflineService._();

  static const String _key = 'pending_ubicaciones_repartidor';

  static Future<void> encolar({
    required String repartidorId,
    required String tenantId,
    required double latitude,
    required double longitude,
    double? accuracy,
    double? heading,
    double? speed,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      final list = raw != null && raw.isNotEmpty
          ? (jsonDecode(raw) as List).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];

      list.add({
        'repartidor_id': repartidorId,
        'tenant_id': tenantId,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'heading': heading,
        'speed': speed,
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Evitar crecimiento infinito en rutas largas offline
      while (list.length > 500) {
        list.removeAt(0);
      }

      await prefs.setString(_key, jsonEncode(list));
      print('📍 Ubicación encolada offline (${list.length} pendientes)');
    } catch (e) {
      print('⚠️ encolar ubicación: $e');
    }
  }

  static Future<int> sincronizarPendientes() async {
    final sync = SyncService();
    if (!sync.isOnline) return 0;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return 0;

      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) return 0;

      var ok = 0;
      final restantes = <Map<String, dynamic>>[];

      for (final item in list) {
        try {
          await supabase.from('ubicaciones_repartidores').insert({
            'repartidor_id': item['repartidor_id']?.toString(),
            'tenant_id': item['tenant_id']?.toString(),
            'latitude': item['latitude'],
            'longitude': item['longitude'],
            'accuracy': item['accuracy'],
            'heading': item['heading'],
            'speed': item['speed'],
          });
          ok++;
        } catch (e) {
          print('⚠️ sync ubicación pendiente: $e');
          restantes.add(item);
        }
      }

      if (restantes.isEmpty) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, jsonEncode(restantes));
      }

      if (ok > 0) {
        print('✅ $ok ubicación(es) GPS sincronizada(s)');
      }
      return ok;
    } catch (e) {
      print('⚠️ sincronizarPendientes ubicación: $e');
      return 0;
    }
  }

  static Future<void> limpiar() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
