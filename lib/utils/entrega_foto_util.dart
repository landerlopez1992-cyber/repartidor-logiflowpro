import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/orden.dart';
import '../services/orden_cache_service.dart';
import '../services/offline_storage_service.dart';
import '../services/sync_service.dart';

/// Resuelve y persiste la foto de entrega (online, local:// y cola offline).
class EntregaFotoUtil {
  EntregaFotoUtil._();

  static bool urlTieneFoto(String? url) =>
      url != null && url.trim().isNotEmpty;

  static bool ordenTieneFoto(Orden orden) => urlTieneFoto(orden.fotoEntrega);

  /// Ruta de archivo local desde `local://` o `file://`.
  static String? rutaArchivoLocal(String? url) {
    if (!urlTieneFoto(url)) return null;
    if (url!.startsWith('local://')) return url.substring(8);
    if (url.startsWith('file://')) return url.substring(7);
    return null;
  }

  static Future<bool> _fotoEliminacionPendiente(String ordenId) async {
    if (SyncService().hasPendingOperation('delete_foto_entrega', ordenId)) {
      return true;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final operationsJson = prefs.getString('pending_sync_operations');
      if (operationsJson == null || operationsJson.isEmpty) return false;
      final operationsList = jsonDecode(operationsJson) as List;
      for (final raw in operationsList) {
        final op = Map<String, dynamic>.from(raw as Map);
        if (op['type'] == 'delete_foto_entrega' &&
            op['orden_id']?.toString() == ordenId) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  static Future<String?> resolverUrlFoto(Orden orden) async {
    if (await _fotoEliminacionPendiente(orden.id)) return null;

    try {
      final pending = await OfflineStorageService().getPendingPhotos();
      for (final photo in pending) {
        if (photo['orden_id']?.toString() != orden.id) continue;
        final path = photo['file_path']?.toString();
        if (path == null || path.isEmpty) continue;
        if (await File(path).exists()) return 'local://$path';
      }
    } catch (_) {}

    try {
      final cached = await OrdenCacheService.getCachedOrderById(orden.id);
      if (cached != null) {
        if (!urlTieneFoto(cached.fotoEntrega)) return null;
        return cached.fotoEntrega!.trim();
      }
    } catch (_) {}

    if (urlTieneFoto(orden.fotoEntrega)) return orden.fotoEntrega!.trim();

    return null;
  }

  static Future<Orden> ordenConFotoResuelta(Orden orden) async {
    final url = await resolverUrlFoto(orden);
    if (!urlTieneFoto(url)) {
      if (ordenTieneFoto(orden)) return quitarFotoDeOrden(orden);
      return orden;
    }
    return aplicarFotoAOrden(orden, url!);
  }

  static Orden aplicarFotoAOrden(Orden orden, String fotoUrl) {
    final json = orden.toJson();
    json['foto_entrega'] = fotoUrl;
    return Orden.fromJson(json);
  }

  static Orden quitarFotoDeOrden(Orden orden) {
    final json = orden.toJson();
    json['foto_entrega'] = null;
    return Orden.fromJson(json);
  }

  static Future<void> guardarFotoEnCache(Orden orden, String fotoUrl) async {
    await SyncService().removePendingOperationsForOrden(
      type: 'delete_foto_entrega',
      ordenId: orden.id,
    );
    final actualizada = aplicarFotoAOrden(orden, fotoUrl);
    await OrdenCacheService.updateCachedOrder(actualizada);
  }

  /// Elimina la foto local/remota en caché, cola offline y BD (al reconectar).
  static Future<Orden> eliminarFotoDeOrden(Orden orden) async {
    final urlActual = await resolverUrlFoto(orden);
    final ruta = rutaArchivoLocal(urlActual ?? orden.fotoEntrega);
    if (ruta != null) {
      try {
        final file = File(ruta);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }

    await OfflineStorageService().deletePendingPhotosByOrdenId(orden.id);
    await SyncService().removePendingOperationsForOrden(
      type: 'upload_photo',
      ordenId: orden.id,
    );

    final sinFoto = quitarFotoDeOrden(orden);
    await OrdenCacheService.updateCachedOrder(sinFoto);

    await SyncService().addOperation(
      type: 'delete_foto_entrega',
      ordenId: orden.id,
      data: const {},
    );

    return sinFoto;
  }
}
