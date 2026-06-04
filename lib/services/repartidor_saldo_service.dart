import '../main.dart';
import 'sync_service.dart';
import 'repartidor_perfil_cache_service.dart';

/// Saldo acumulado del repartidor (columna usuarios + solicitudes pendientes).
class RepartidorSaldoService {
  RepartidorSaldoService._();

  static Future<({double saldo, String moneda, bool solicitudPendiente})> cargarSaldo(
    String repartidorId,
  ) async {
    if (!SyncService().isOnline) {
      final cache = await RepartidorPerfilCacheService.getCachedSaldo();
      if (cache != null) {
        final raw = cache['saldo'];
        final saldo = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0.0;
        return (
          saldo: saldo,
          moneda: cache['moneda']?.toString() ?? 'USD',
          solicitudPendiente: cache['solicitud_pendiente'] == true,
        );
      }
    }

    final pendiente = await supabase
        .from('solicitudes_pago_repartidores')
        .select('id')
        .eq('repartidor_id', repartidorId)
        .eq('estado', 'PENDIENTE')
        .limit(1)
        .maybeSingle();

    if (pendiente != null) {
      await RepartidorPerfilCacheService.cacheSaldo(0, 'USD', solicitudPendiente: true);
      return (saldo: 0.0, moneda: 'USD', solicitudPendiente: true);
    }

    final row = await supabase
        .from('usuarios')
        .select('repartidor_saldo_acumulado, repartidor_saldo_moneda')
        .eq('id', repartidorId)
        .maybeSingle();

    final raw = row?['repartidor_saldo_acumulado'];
    final saldo = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
    final moneda = row?['repartidor_saldo_moneda']?.toString() ?? 'USD';

    await RepartidorPerfilCacheService.cacheSaldo(saldo, moneda);

    return (saldo: saldo, moneda: moneda, solicitudPendiente: false);
  }
}
