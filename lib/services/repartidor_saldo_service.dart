import 'package:flutter/foundation.dart';

import '../main.dart';
import 'sync_service.dart';
import 'repartidor_perfil_cache_service.dart';
import 'repartidor_saldo_offline_service.dart';
import 'repartidor_solicitud_pago_offline_service.dart';

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

  /// Incrementa cuando el saldo cambia (fianza, nómina, entrega, etc.).
  /// Las pantallas de billetera deben escuchar y recargar.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Actualiza caché local y avisa a listeners (billetera / perfil / home).
  static Future<void> aplicarSaldoServidorYNotificar({
    required double saldoServidor,
    String moneda = 'USD',
    bool? solicitudPendiente,
  }) async {
    var pendiente = solicitudPendiente;
    if (pendiente == null) {
      final cache = await RepartidorPerfilCacheService.getCachedSaldo();
      pendiente = cache?['solicitud_pendiente'] == true;
    }
    await RepartidorPerfilCacheService.cacheSaldo(
      saldoServidor,
      moneda,
      solicitudPendiente: pendiente,
    );
    revision.value = revision.value + 1;
  }

  /// Solo notifica (p. ej. tras operación que no devolvió saldo explícito).
  static void notificarCambioSaldo() {
    revision.value = revision.value + 1;
  }

  static Future<RepartidorSaldoCargado> _desdeCache({
    required double pendienteCola,
    bool? solicitudPendienteExtra,
  }) async {
    final cache = await RepartidorPerfilCacheService.getCachedSaldo();
    if (cache != null) {
      final raw = cache['saldo'];
      final saldoServidor =
          raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0.0;
      var solicitudPendiente = cache['solicitud_pendiente'] == true;
      if (solicitudPendienteExtra == true) solicitudPendiente = true;
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
      solicitudPendiente: solicitudPendienteExtra ?? false,
    );
  }

  static Future<RepartidorSaldoCargado> cargarSaldo(String repartidorId) async {
    final pendienteCola =
        await RepartidorSaldoOfflineService.totalPendienteEnCola();
    final pendienteLocal =
        await RepartidorSolicitudPagoOfflineService.tieneSolicitudPendienteLocal(
      repartidorId,
    );

    if (!SyncService().isOnline) {
      return _desdeCache(
        pendienteCola: pendienteCola,
        solicitudPendienteExtra: pendienteLocal,
      );
    }

    try {
      final pendiente = await supabase
          .from('solicitudes_pago_repartidores')
          .select('id, monto, moneda')
          .eq('repartidor_id', repartidorId)
          .eq('estado', 'PENDIENTE')
          .limit(1)
          .maybeSingle();

      final solicitudPendiente = pendiente != null || pendienteLocal;

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
      final saldoServidor =
          raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
      final moneda = row?['repartidor_saldo_moneda']?.toString() ?? 'USD';

      await RepartidorPerfilCacheService.cacheSaldo(
        saldoServidor,
        moneda,
        solicitudPendiente: solicitudPendiente,
      );

      final perfilCache =
          await RepartidorPerfilCacheService.getCachedPerfilData();
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
        solicitudPendiente: solicitudPendiente,
      );

      return (
        saldo: visible,
        saldoServidor: saldoServidor,
        saldoPendienteSync: pendienteCola,
        moneda: moneda,
        solicitudPendiente: solicitudPendiente,
      );
    } catch (e) {
      print('⚠️ cargarSaldo online falló, usando caché: $e');
      return _desdeCache(
        pendienteCola: pendienteCola,
        solicitudPendienteExtra: pendienteLocal,
      );
    }
  }
}
