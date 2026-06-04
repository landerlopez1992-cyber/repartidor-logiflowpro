import 'dart:io';

import '../models/orden.dart';
import '../services/orden_cache_service.dart';
import '../services/offline_storage_service.dart';

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

  static Future<String?> resolverUrlFoto(Orden orden) async {
    if (urlTieneFoto(orden.fotoEntrega)) return orden.fotoEntrega!.trim();

    try {
      final cached = await OrdenCacheService.getCachedOrderById(orden.id);
      if (cached != null && urlTieneFoto(cached.fotoEntrega)) {
        return cached.fotoEntrega!.trim();
      }
    } catch (_) {}

    try {
      final pending = await OfflineStorageService().getPendingPhotos();
      for (final photo in pending) {
        if (photo['orden_id']?.toString() != orden.id) continue;
        final path = photo['file_path']?.toString();
        if (path == null || path.isEmpty) continue;
        if (await File(path).exists()) return 'local://$path';
      }
    } catch (_) {}

    return null;
  }

  static Future<Orden> ordenConFotoResuelta(Orden orden) async {
    final url = await resolverUrlFoto(orden);
    if (!urlTieneFoto(url)) return orden;
    return aplicarFotoAOrden(orden, url!);
  }

  static Orden aplicarFotoAOrden(Orden orden, String fotoUrl) {
    final json = orden.toJson();
    json['foto_entrega'] = fotoUrl;
    return Orden.fromJson(json);
  }

  static Future<void> guardarFotoEnCache(Orden orden, String fotoUrl) async {
    final actualizada = aplicarFotoAOrden(orden, fotoUrl);
    await OrdenCacheService.updateCachedOrder(actualizada);
  }
}
