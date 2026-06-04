import 'orden_cache_service.dart';
import 'offline_storage_service.dart';
import 'sync_service.dart';
import 'ubicacion_offline_service.dart';
import 'repartidor_pantallas_offline_service.dart';

/// Limpia cola de sync, órdenes en caché y fotos/firmas pendientes al cambiar de usuario.
class SesionOfflineCleanup {
  SesionOfflineCleanup._();

  static Future<void> limpiarTodo() async {
    try {
      await SyncService().clearPendingOperations();
    } catch (e) {
      print('⚠️ clearPendingOperations: $e');
    }
    try {
      await OrdenCacheService.clearCache();
    } catch (e) {
      print('⚠️ clearCache órdenes: $e');
    }
    try {
      await OfflineStorageService().clearAll();
    } catch (e) {
      print('⚠️ clearAll offline storage: $e');
    }
    try {
      await UbicacionOfflineService.limpiar();
    } catch (e) {
      print('⚠️ clear ubicaciones GPS: $e');
    }
    try {
      await RepartidorPantallasOfflineService.limpiarTodo();
    } catch (e) {
      print('⚠️ clear caché pantallas: $e');
    }
  }
}
