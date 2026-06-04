import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import 'sync_service.dart';

/// Caché de lectura y cola de mensajes de soporte para modo offline.
class RepartidorPantallasOfflineService {
  RepartidorPantallasOfflineService._();

  static const _notifKey = 'cache_notificaciones_repartidor_';
  static const _chatMensajesKey = 'cache_chat_mensajes_';
  static const _chatConvKey = 'cache_chat_conversaciones_';
  static const _mapaUbicKey = 'cache_mapa_ubicacion_';
  static const _pendingMensajesKey = 'pending_mensajes_soporte';

  // ——— Notificaciones ———

  static Future<void> guardarNotificaciones(
    String repartidorId, {
    required List<Map<String, dynamic>> ordenes,
    required List<Map<String, dynamic>> pagos,
    required List<Map<String, dynamic>> generales,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_notifKey$repartidorId',
        jsonEncode({'ordenes': ordenes, 'pagos': pagos, 'generales': generales}),
      );
    } catch (e) {
      print('⚠️ guardarNotificaciones: $e');
    }
  }

  static Future<({List<Map<String, dynamic>> ordenes, List<Map<String, dynamic>> pagos, List<Map<String, dynamic>> generales})?>
      cargarNotificaciones(String repartidorId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_notifKey$repartidorId');
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return (
        ordenes: _listaMap(m['ordenes']),
        pagos: _listaMap(m['pagos']),
        generales: _listaMap(m['generales']),
      );
    } catch (e) {
      return null;
    }
  }

  // ——— Chat mensajes (conversación) ———

  static Future<void> guardarMensajesChat(String conversacionId, List<Map<String, dynamic>> mensajes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_chatMensajesKey$conversacionId', jsonEncode(mensajes));
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>?> cargarMensajesChat(String conversacionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_chatMensajesKey$conversacionId');
      if (raw == null) return null;
      return _listaMap(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  static Future<void> guardarConversacionesChat(String authId, List<Map<String, dynamic>> conversaciones) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_chatConvKey$authId', jsonEncode(conversaciones));
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>?> cargarConversacionesChat(String authId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_chatConvKey$authId');
      if (raw == null) return null;
      return _listaMap(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  // ——— Mapa: última ubicación conocida del repartidor ———

  static Future<void> guardarUbicacionMapa(
    String repartidorId, {
    required double lat,
    required double lng,
    String? timestamp,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_mapaUbicKey$repartidorId',
        jsonEncode({'lat': lat, 'lng': lng, 'ts': timestamp ?? DateTime.now().toIso8601String()}),
      );
    } catch (_) {}
  }

  static Future<({double lat, double lng, String? ts})?> cargarUbicacionMapa(String repartidorId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_mapaUbicKey$repartidorId');
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return (lat: (m['lat'] as num).toDouble(), lng: (m['lng'] as num).toDouble(), ts: m['ts']?.toString());
    } catch (_) {
      return null;
    }
  }

  // ——— Mensajes de soporte pendientes de envío ———

  static Future<void> encolarMensajeSoporte(Map<String, dynamic> datosMensaje) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingMensajesKey);
      final list = raw != null && raw.isNotEmpty
          ? (jsonDecode(raw) as List).cast<Map<String, dynamic>>()
          : <Map<String, dynamic>>[];
      list.add({
        ...datosMensaje,
        'local_id': DateTime.now().millisecondsSinceEpoch.toString(),
        'created_at_local': DateTime.now().toIso8601String(),
      });
      while (list.length > 200) {
        list.removeAt(0);
      }
      await prefs.setString(_pendingMensajesKey, jsonEncode(list));
      print('💬 Mensaje de soporte encolado (${list.length} pendientes)');
    } catch (e) {
      print('⚠️ encolarMensajeSoporte: $e');
    }
  }

  static Future<int> sincronizarMensajesSoporte() async {
    if (!SyncService().isOnline) return 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingMensajesKey);
      if (raw == null || raw.isEmpty) return 0;

      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) return 0;

      var ok = 0;
      final restantes = <Map<String, dynamic>>[];

      for (final item in list) {
        final payload = Map<String, dynamic>.from(item);
        payload.remove('local_id');
        payload.remove('created_at_local');
        try {
          await supabase.from('mensajes_soporte').insert(payload);
          ok++;
        } catch (e) {
          print('⚠️ sync mensaje soporte: $e');
          restantes.add(item);
        }
      }

      if (restantes.isEmpty) {
        await prefs.remove(_pendingMensajesKey);
      } else {
        await prefs.setString(_pendingMensajesKey, jsonEncode(restantes));
      }
      if (ok > 0) print('✅ $ok mensaje(s) de soporte sincronizado(s)');
      return ok;
    } catch (e) {
      print('⚠️ sincronizarMensajesSoporte: $e');
      return 0;
    }
  }

  static Future<void> limpiarTodo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().toList();
      for (final k in keys) {
        if (k.startsWith(_notifKey) ||
            k.startsWith(_chatMensajesKey) ||
            k.startsWith(_chatConvKey) ||
            k.startsWith(_mapaUbicKey) ||
            k == _pendingMensajesKey) {
          await prefs.remove(k);
        }
      }
    } catch (_) {}
  }

  static List<Map<String, dynamic>> _listaMap(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static bool esErrorDeRed(Object e) {
    final s = e.toString();
    return s.contains('Failed host lookup') ||
        s.contains('SocketException') ||
        s.contains('ClientException') ||
        s.contains('TimeoutException');
  }
}
