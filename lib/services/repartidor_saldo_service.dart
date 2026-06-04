import '../main.dart';
import 'sync_service.dart';
import 'repartidor_perfil_cache_service.dart';
import 'repartidor_saldo_offline_service.dart';

/// Resultado al cargar saldo (servidor + entregas en cola offline).
typedef RepartidorSaldoCargado = ({
  double saldo,
  double saldoServidor,
  double saldoPendienteSync,
  String moneda,
  bool solicitudPendiente,
});

/// Saldo acumulado del repartidor (columna usuarios + solicitudes pendientes).
class RepartidorSaldoService {
  RepartidorSaldoService._();

  static Future<RepartidorSaldoCargado> cargarSaldo(String repartidorId) async {
    final pendienteCola = await RepartidorSaldoOfflineService.totalPendienteEnCola();

    if (!SyncService().isOnline) {
      final cache = await RepartidorPerfilCacheService.getCachedSaldo();
      if (cache != null) {
        final raw = cache['saldo'];
        final saldoServidor =
            raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0.0;
        final solicitudPendiente = cache['solicitud_pendiente'] == true;
        final moneda = cache['moneda']?.toString() ?? 'USD';
        final visible = RepartidorSaldoOfflineService.combinarSaldoVisible(
          saldoServidor: saldoServidor,
          pendienteEnCola: pendienteCola,
          solicitudPendiente: solicitudPendiente,
        );
        return (
          saldo: visible,
          saldoServidor: saldoServidor,
          saldoPendienteSync: pendienteCola,
          moneda: moneda,
          solicitudPendiente: solicitudPendiente,
        );
      }
      return (
        saldo: pendienteCola,
        saldoServidor: 0.0,
        saldoPendienteSync: pendienteCola,
        moneda: 'USD',
        solicitudPendiente: false,
      );
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
      return (
        saldo: 0.0,
        saldoServidor: 0.0,
        saldoPendienteSync: pendienteCola,
        moneda: 'USD',
        solicitudPendiente: true,
      );
    }

    try {
      final syncRaw = await supabase.rpc(
        'repartidor_sincronizar_saldo_acumulado',
        params: {'p_repartidor_id': repartidorId},
      );
      if (syncRaw is Map && syncRaw['ok'] != true) {
        print('⚠️ repartidor_sincronizar_saldo_acumulado: $syncRaw');
      }
    } catch (e) {
      print('⚠️ repartidor_sincronizar_saldo_acumulado: $e');
    }

    final row = await supabase
        .from('usuarios')
        .select(
          'repartidor_saldo_acumulado, repartidor_saldo_moneda, '
          'repartidor_metodo_pago, repartidor_tarifa',
        )
        .eq('id', repartidorId)
        .maybeSingle();

    final raw = row?['repartidor_saldo_acumulado'];
    final saldoServidor = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
    final moneda = row?['repartidor_saldo_moneda']?.toString() ?? 'USD';

    await RepartidorPerfilCacheService.cacheSaldo(saldoServidor, moneda);

    final perfilCache = await RepartidorPerfilCacheService.getCachedPerfilData();
    if (perfilCache != null) {
      await RepartidorPerfilCacheService.cachePerfilData({
        ...perfilCache,
        'repartidor_metodo_pago': row?['repartidor_metodo_pago'],
        'repartidor_tarifa': row?['repartidor_tarifa'],
        'repartidor_saldo_moneda': moneda,
      });
    }

    final visible = RepartidorSaldoOfflineService.combinarSaldoVisible(
      saldoServidor: saldoServidor,
      pendienteEnCola: pendienteCola,
      solicitudPendiente: false,
    );

    return (
      saldo: visible,
      saldoServidor: saldoServidor,
      saldoPendienteSync: pendienteCola,
      moneda: moneda,
      solicitudPendiente: false,
    );
  }
}
