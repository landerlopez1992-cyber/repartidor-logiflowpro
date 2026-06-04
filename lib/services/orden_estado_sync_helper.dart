import '../main.dart';
import '../models/orden.dart';
import 'goodbarber_sync_service.dart';
import 'orden_cache_service.dart';
import 'sync_service.dart';

/// Resultado al persistir un cambio de estado (BD y/o cola offline).
class OrdenEstadoSyncResult {
  final bool persistedToDb;
  final bool queued;

  const OrdenEstadoSyncResult({
    required this.persistedToDb,
    required this.queued,
  });

  bool get ok => persistedToDb || queued;
}

/// Patrón único: caché → Supabase → cola si falla o sin red.
/// Las notificaciones email/WhatsApp del emisor las dispara el trigger en BD al cambiar `estado`.
class OrdenEstadoSyncHelper {
  OrdenEstadoSyncHelper._();

  static Future<OrdenEstadoSyncResult> persistirCambioEstado({
    required String ordenId,
    required Orden ordenEnCache,
    required Map<String, dynamic> updateData,
    String queueType = 'update_orden_estado',
    bool syncGoodBarber = true,
  }) async {
    await OrdenCacheService.updateCachedOrder(ordenEnCache);

    final syncService = SyncService();
    final nuevoEstado = updateData['estado']?.toString().trim();

    Future<void> encolar() async {
      await syncService.addOperation(
        type: queueType,
        ordenId: ordenId,
        data: Map<String, dynamic>.from(updateData),
      );
    }

    if (!syncService.isOnline) {
      await encolar();
      return const OrdenEstadoSyncResult(persistedToDb: false, queued: true);
    }

    try {
      await supabase.from('ordenes').update(updateData).eq('id', ordenId);

      if (syncGoodBarber && nuevoEstado != null && nuevoEstado.isNotEmpty) {
        try {
          await GoodBarberSyncService.sincronizarEstadoAGoodBarber(
            supabase,
            ordenId,
            nuevoEstado,
          );
        } catch (e) {
          print('⚠️ GoodBarber sync estado: $e');
        }
      }

      return const OrdenEstadoSyncResult(persistedToDb: true, queued: false);
    } catch (e) {
      print('⚠️ persistirCambioEstado BD: $e — encolando');
      await encolar();
      return const OrdenEstadoSyncResult(persistedToDb: false, queued: true);
    }
  }
}
