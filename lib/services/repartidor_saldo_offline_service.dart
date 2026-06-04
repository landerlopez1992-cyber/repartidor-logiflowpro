import 'repartidor_perfil_cache_service.dart';
import 'sync_service.dart';

/// Créditos de saldo por entregas aún no reflejados en el servidor.
///
/// No persiste montos aparte: solo suma tarifas de órdenes que siguen en la cola
/// (`mark_delivered` / `update_orden_estado` → ENTREGADO o RECOGIDO). Al sincronizar,
/// la operación sale de la cola y el trigger en BD acredita (idempotente); el UI deja
/// de sumar el pendiente local y muestra el saldo del servidor.
class RepartidorSaldoOfflineService {
  RepartidorSaldoOfflineService._();

  static const _estadosAcreditan = {'ENTREGADO', 'RECOGIDO'};

  static Future<({bool aplica, double tarifa, String moneda})> _configPago() async {
    final perfil = await RepartidorPerfilCacheService.getCachedPerfilData();
    if (perfil == null) {
      return (aplica: false, tarifa: 0.0, moneda: 'USD');
    }
    final metodo =
        (perfil['repartidor_metodo_pago'] ?? 'por_orden').toString().trim().toLowerCase();
    final rawTarifa = perfil['repartidor_tarifa'];
    final tarifa = rawTarifa is num
        ? rawTarifa.toDouble()
        : double.tryParse('$rawTarifa') ?? 0;
    final moneda = (perfil['repartidor_saldo_moneda'] ?? 'USD').toString();
    final aplica = metodo == 'por_orden' && tarifa > 0;
    return (aplica: aplica, tarifa: tarifa, moneda: moneda);
  }

  static bool _operacionAcreditaSaldo(String type, Map<String, dynamic> data) {
    if (type == 'mark_delivered') {
      final est = data['estado']?.toString().trim().toUpperCase() ?? 'ENTREGADO';
      return _estadosAcreditan.contains(est);
    }
    if (type == 'update_orden_estado') {
      final est = data['estado']?.toString().trim().toUpperCase() ?? '';
      return _estadosAcreditan.contains(est);
    }
    return false;
  }

  /// Suma tarifas de entregas en cola (una vez por orden).
  static Future<double> totalPendienteEnCola() async {
    final cfg = await _configPago();
    if (!cfg.aplica) return 0;

    final ops = SyncService().pendingOperationsSnapshot;
    final vistos = <String>{};
    var sum = 0.0;

    for (final op in ops) {
      final ordenId = op['orden_id']?.toString() ?? '';
      if (ordenId.isEmpty || vistos.contains(ordenId)) continue;

      final type = op['type']?.toString() ?? '';
      final rawData = op['data'];
      final data = rawData is Map
          ? Map<String, dynamic>.from(rawData)
          : <String, dynamic>{};

      if (!_operacionAcreditaSaldo(type, data)) continue;

      vistos.add(ordenId);
      sum += cfg.tarifa;
    }

    return sum;
  }

  /// Saldo mostrado = servidor (o caché) + pendiente en cola, salvo solicitud de pago abierta.
  static double combinarSaldoVisible({
    required double saldoServidor,
    required double pendienteEnCola,
    required bool solicitudPendiente,
  }) {
    if (solicitudPendiente) return 0;
    return saldoServidor + pendienteEnCola;
  }
}
