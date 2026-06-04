import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import 'sync_service.dart';

/// Caché de lectura y cola de mensajes de soporte para modo offline.
class RepartidorPantallasOfflineService {
  RepartidorPantallasOfflineService._();

  static const _notifKey = 'cache_notificaciones_repartidor_';
  static const _chatMensajesKey = 'cache_chat_mensajes_';
  static const _chatConvKey = 'cache_chat_conversaciones_';
  static const _chatMetaKey = 'cache_chat_meta_';
  static const _chatRemitentesKey = 'cache_chat_remitentes_';
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

  static Future<void> guardarMetaChat(
    String authId, {
    required String? conversacionId,
    String? tenantId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_chatMetaKey$authId',
        jsonEncode({
          'conversacion_id': conversacionId,
          'tenant_id': tenantId,
        }),
      );
    } catch (_) {}
  }

  /// Nombre del repartidor desde `cached_user_data_*` (login / perfil).
  static Future<String?> cargarNombreRepartidor(String authId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nombreDirecto = prefs.getString('cached_repartidor_nombre_$authId');
      if (nombreDirecto != null && nombreDirecto.trim().isNotEmpty) {
        return nombreDirecto.trim();
      }
      final raw = prefs.getString('cached_user_data_$authId');
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final nombre = m['nombre']?.toString().trim();
      return (nombre != null && nombre.isNotEmpty) ? nombre : null;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> cargarTenantIdRepartidor(String authId) async {
    try {
      final meta = await cargarMetaChat(authId);
      if (meta?.tenantId != null && meta!.tenantId!.isNotEmpty) {
        return meta.tenantId;
      }
      final prefs = await SharedPreferences.getInstance();
      final tid = prefs.getString('cached_tenant_id_$authId');
      if (tid != null && tid.isNotEmpty) return tid;
      final raw = prefs.getString('cached_user_data_$authId');
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m['tenant_id']?.toString();
    } catch (_) {
      return null;
    }
  }

  static Future<void> guardarRemitenteChat(
    String remitenteAuthId, {
    required String nombre,
    required String rol,
    String? foto,
    String? email,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_chatRemitentesKey$remitenteAuthId';
      await prefs.setString(
        key,
        jsonEncode({
          'nombre': nombre,
          'rol': rol,
          'foto_perfil': foto,
          'email': email,
        }),
      );
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> cargarRemitenteChat(String remitenteAuthId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_chatRemitentesKey$remitenteAuthId');
      if (raw == null) return null;
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  /// Arma la lista de conversaciones solo con mensajes guardados en el dispositivo.
  static Future<List<Map<String, dynamic>>> conversacionesDesdeMensajesCache({
    required String conversacionId,
    required String repartidorAuthId,
  }) async {
    final mensajes = await cargarMensajesChat(conversacionId);
    if (mensajes == null || mensajes.isEmpty) return [];

    final map = <String, Map<String, dynamic>>{};

    for (final raw in mensajes) {
      final m = Map<String, dynamic>.from(raw);
      final remitenteId = m['remitente_auth_id']?.toString();
      if (remitenteId == null ||
          remitenteId.isEmpty ||
          remitenteId == repartidorAuthId) {
        continue;
      }

      final preview = _previewMensaje(m);
      final created = m['created_at']?.toString() ?? '';
      if (preview.isEmpty) continue;

      if (map.containsKey(remitenteId)) {
        final actual = map[remitenteId]!;
        final fa = DateTime.tryParse(actual['ultimo_mensaje_fecha']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final fn = DateTime.tryParse(created) ?? fa;
        if (fn.isAfter(fa)) {
          actual['ultimo_mensaje'] = preview;
          actual['ultimo_mensaje_fecha'] = created.isNotEmpty ? created : fa.toIso8601String();
        }
      } else {
        final remCache = await cargarRemitenteChat(remitenteId);
        map[remitenteId] = {
          'remitente_auth_id': remitenteId,
          'remitente_nombre': remCache?['nombre']?.toString() ?? 'Soporte',
          'remitente_rol': remCache?['rol']?.toString() ?? 'EMPLEADO',
          'remitente_foto': remCache?['foto_perfil'],
          'remitente_email': remCache?['email'],
          'ultimo_mensaje': preview,
          'ultimo_mensaje_fecha':
              created.isNotEmpty ? created : DateTime.now().toIso8601String(),
          'mensajes_no_leidos': 0,
          'conversacion_id': conversacionId,
        };
      }
    }

    final lista = map.values.toList();
    lista.sort((a, b) {
      final fa = DateTime.tryParse(a['ultimo_mensaje_fecha']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final fb = DateTime.tryParse(b['ultimo_mensaje_fecha']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return fb.compareTo(fa);
    });
    return lista;
  }

  /// Actualiza una fila de la lista de conversaciones en caché (tras abrir/enviar chat).
  static Future<void> upsertConversacionEnCache(
    String authId, {
    required String conversacionId,
    required String remitenteAuthId,
    required String remitenteNombre,
    required String remitenteRol,
    String? remitenteFoto,
    String? ultimoMensaje,
    String? ultimoMensajeFecha,
  }) async {
    await guardarRemitenteChat(
      remitenteAuthId,
      nombre: remitenteNombre,
      rol: remitenteRol,
      foto: remitenteFoto,
    );

    final actuales = await cargarConversacionesChat(authId) ?? <Map<String, dynamic>>[];
    final idx = actuales.indexWhere(
      (c) => c['remitente_auth_id']?.toString() == remitenteAuthId,
    );

    final fila = {
      'remitente_auth_id': remitenteAuthId,
      'remitente_nombre': remitenteNombre,
      'remitente_rol': remitenteRol,
      'remitente_foto': remitenteFoto,
      'ultimo_mensaje': ultimoMensaje ?? '',
      'ultimo_mensaje_fecha':
          ultimoMensajeFecha ?? DateTime.now().toIso8601String(),
      'mensajes_no_leidos': 0,
      'conversacion_id': conversacionId,
    };

    if (idx >= 0) {
      actuales[idx] = {...actuales[idx], ...fila};
    } else {
      actuales.insert(0, fila);
    }

    actuales.sort((a, b) {
      final fa = DateTime.tryParse(a['ultimo_mensaje_fecha']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final fb = DateTime.tryParse(b['ultimo_mensaje_fecha']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return fb.compareTo(fa);
    });

    await guardarConversacionesChat(authId, actuales);
  }

  static String _previewMensaje(Map<String, dynamic> m) {
    final texto = m['mensaje']?.toString().trim() ?? '';
    if (texto.isNotEmpty && texto != '📷 Foto') return texto;
    final local = m['foto_local_path']?.toString().trim() ?? '';
    final foto = m['foto_url']?.toString().trim() ?? '';
    if (local.isNotEmpty || foto.isNotEmpty) return '📷 Foto';
    return '';
  }

  /// Copia la imagen a almacenamiento persistente para envío offline.
  static Future<String?> persistirFotoChatPendiente(String sourcePath) async {
    try {
      final src = File(sourcePath);
      if (!await src.exists()) return null;
      final dir = await getApplicationDocumentsDirectory();
      final sub = Directory('${dir.path}/chat_pendiente');
      if (!await sub.exists()) {
        await sub.create(recursive: true);
      }
      final dest = File(
        '${sub.path}/chat_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await src.copy(dest.path);
      return dest.path;
    } catch (e) {
      print('⚠️ persistirFotoChatPendiente: $e');
      return null;
    }
  }

  static String? _fotoUrlParaUi(Map<String, dynamic> item) {
    final local = item['foto_local_path']?.toString().trim() ?? '';
    if (local.isNotEmpty) return 'local://$local';
    return item['foto_url']?.toString();
  }

  static Future<({String? conversacionId, String? tenantId})?> cargarMetaChat(
    String authId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_chatMetaKey$authId');
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return (
        conversacionId: m['conversacion_id']?.toString(),
        tenantId: m['tenant_id']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Mensajes del repartidor aún no enviados al servidor (cola offline).
  static Future<List<Map<String, dynamic>>> mensajesPendientesParaConversacion({
    required String conversacionId,
    required String repartidorAuthId,
    required String nombreRepartidor,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingMensajesKey);
      if (raw == null || raw.isEmpty) return [];

      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final visibles = <Map<String, dynamic>>[];

      for (final item in list) {
        if (item['conversacion_id']?.toString() != conversacionId) continue;
        if (item['remitente_auth_id']?.toString() != repartidorAuthId) continue;

        final fotoUi = _fotoUrlParaUi(item);
        visibles.add({
          ...item,
          if (fotoUi != null && fotoUi.isNotEmpty) 'foto_url': fotoUi,
          'local_id': item['local_id']?.toString() ??
              DateTime.now().millisecondsSinceEpoch.toString(),
          'remitente_nombre': nombreRepartidor,
          'remitente_rol': 'REPARTIDOR',
          'created_at': item['created_at_local']?.toString() ??
              DateTime.now().toIso8601String(),
          'pending_local': true,
        });
      }
      return visibles;
    } catch (_) {
      return [];
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
        final localId = payload.remove('local_id');
        payload.remove('created_at_local');
        final fotoLocal = payload.remove('foto_local_path')?.toString();

        try {
          if (fotoLocal != null && fotoLocal.isNotEmpty) {
            final file = File(fotoLocal);
            if (!await file.exists()) {
              print('⚠️ Foto chat pendiente no encontrada: $fotoLocal');
              restantes.add(item);
              continue;
            }
            final authId =
                payload['remitente_auth_id']?.toString() ?? 'repartidor';
            final fileName =
                'chat_${DateTime.now().millisecondsSinceEpoch}_$authId.jpg';
            await supabase.storage
                .from('fotos-perfil')
                .upload(fileName, file);
            payload['foto_url'] = supabase.storage
                .from('fotos-perfil')
                .getPublicUrl(fileName);
            try {
              await file.delete();
            } catch (_) {}
          }

          await supabase.from('mensajes_soporte').insert(payload);
          ok++;
          print('✅ Mensaje chat sincronizado (local_id: $localId)');
        } catch (e) {
          print('⚠️ sync mensaje soporte: $e');
          if (!esErrorDeRed(e) && fotoLocal != null && fotoLocal.isNotEmpty) {
            // Error de servidor con foto: conservar cola
          }
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
            k.startsWith(_chatMetaKey) ||
            k.startsWith(_chatRemitentesKey) ||
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
