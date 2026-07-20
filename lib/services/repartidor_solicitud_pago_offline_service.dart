import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'orden_cache_service.dart';
import 'repartidor_perfil_cache_service.dart';
import 'repartidor_solicitud_pago_service.dart';
import 'sync_service.dart';

/// Solicitud de nómina y preview de pago sin conexión (cola + caché).
class RepartidorSolicitudPagoOfflineService {
  RepartidorSolicitudPagoOfflineService._();

  static String _previewKey(String repartidorId) =>
      'cached_preview_solicitud_pago_$repartidorId';
  static String _localSolicitudKey(String repartidorId) =>
      'local_solicitud_pago_$repartidorId';

  static bool tieneSolicitudEnColaSync(String repartidorId) {
    return SyncService().pendingOperationsSnapshot.any(
          (op) =>
              op['type'] == 'solicitud_pago_repartidor' &&
              op['orden_id']?.toString() == repartidorId,
        );
  }

  static Future<bool> tieneSolicitudPendienteLocal(String repartidorId) async {
    if (tieneSolicitudEnColaSync(repartidorId)) return true;
    final local = await getSolicitudLocal(repartidorId);
    return local != null;
  }

  static Future<void> cachePreview(
    String repartidorId,
    RepartidorSolicitudPreview preview,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _previewKey(repartidorId),
        jsonEncode({
          'metodo_pago': preview.metodoPago,
          'tarifa': preview.tarifa,
          'unidad': preview.unidad,
          'moneda': preview.moneda,
          'saldo_acumulado': preview.saldoAcumulado,
          'solicitud_pendiente': preview.solicitudPendiente,
          'ultima_nomina_fecha': preview.ultimaNominaFecha?.toIso8601String(),
          'dias_desde_ultima_nomina': preview.diasDesdeUltimaNomina,
          'monto_estimado_por_dia': preview.montoEstimadoPorDia,
          'dias_laborables_etiqueta': preview.diasLaborablesEtiqueta,
        }),
      );
    } catch (e) {
      print('⚠️ cachePreview solicitud pago: $e');
    }
  }

  /// Borra preview local (p. ej. tras configurar tarifa en el panel).
  static Future<void> clearPreviewCache(String repartidorId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_previewKey(repartidorId));
    } catch (e) {
      print('⚠️ clearPreviewCache: $e');
    }
  }

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  static Future<RepartidorSolicitudPreview?> previewDesdeCache(
    String repartidorId, {
    double? saldoOverride,
    bool? solicitudPendienteOverride,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_previewKey(repartidorId));
      final perfil = await RepartidorPerfilCacheService.getCachedPerfilData();
      final saldoCache = await RepartidorPerfilCacheService.getCachedSaldo();
      final tarifaPerfil = _asDouble(perfil?['repartidor_tarifa']);

      Map<String, dynamic> map;
      if (raw != null && raw.isNotEmpty) {
        map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
        // Si el preview quedó con tarifa 0 pero el perfil ya tiene tarifa > 0
        // (empresa la configuró después), preferir la del perfil.
        final tarifaCached = _asDouble(map['tarifa']);
        if (tarifaCached <= 0 && tarifaPerfil > 0) {
          map['tarifa'] = tarifaPerfil;
          map['metodo_pago'] =
              perfil?['repartidor_metodo_pago'] ?? map['metodo_pago'] ?? 'por_orden';
          map['moneda'] =
              perfil?['repartidor_saldo_moneda'] ?? map['moneda'] ?? 'USD';
        }
      } else {
        if (perfil == null) return null;
        map = {
          'metodo_pago': perfil['repartidor_metodo_pago'] ?? 'por_orden',
          'tarifa': perfil['repartidor_tarifa'] ?? 0,
          'unidad': 'orden',
          'moneda': perfil['repartidor_saldo_moneda'] ?? saldoCache?['moneda'] ?? 'USD',
          'saldo_acumulado': saldoCache?['saldo'] ?? 0,
          'solicitud_pendiente': saldoCache?['solicitud_pendiente'] == true,
          'dias_desde_ultima_nomina': 0,
          'monto_estimado_por_dia': 0,
          'dias_laborables_etiqueta': '',
        };
      }

      final pendienteLocal = await tieneSolicitudPendienteLocal(repartidorId);
      final ultima = map['ultima_nomina_fecha']?.toString();
      DateTime? fechaUltima;
      if (ultima != null && ultima.isNotEmpty) {
        fechaUltima = DateTime.tryParse(ultima);
      }

      final tarifaRaw = map['tarifa'];
      final saldoRaw = saldoOverride ?? map['saldo_acumulado'];
      final montoDiaRaw = map['monto_estimado_por_dia'];

      return RepartidorSolicitudPreview(
        metodoPago: map['metodo_pago']?.toString() ?? 'por_orden',
        tarifa: _asDouble(tarifaRaw),
        unidad: map['unidad']?.toString() ?? 'orden',
        moneda: map['moneda']?.toString() ?? 'USD',
        saldoAcumulado: _asDouble(saldoRaw),
        solicitudPendiente: solicitudPendienteOverride ??
            (pendienteLocal || map['solicitud_pendiente'] == true),
        ultimaNominaFecha: fechaUltima,
        diasDesdeUltimaNomina: map['dias_desde_ultima_nomina'] is int
            ? map['dias_desde_ultima_nomina'] as int
            : int.tryParse('${map['dias_desde_ultima_nomina']}') ?? 0,
        montoEstimadoPorDia: _asDouble(montoDiaRaw),
        diasLaborablesEtiqueta: map['dias_laborables_etiqueta']?.toString() ?? '',
      );
    } catch (e) {
      print('⚠️ previewDesdeCache: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getSolicitudLocal(String repartidorId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_localSolicitudKey(repartidorId));
      if (raw == null || raw.isEmpty) return null;
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> guardarSolicitudLocal({
    required String repartidorId,
    required Map<String, dynamic> solicitudUi,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localSolicitudKey(repartidorId), jsonEncode(solicitudUi));
  }

  static Future<void> limpiarSolicitudLocal(String repartidorId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_localSolicitudKey(repartidorId));
  }

  /// Registra solicitud en cola sync + historial local + flag de saldo.
  static Future<void> encolarSolicitud({
    required String repartidorId,
    required String tenantId,
    required String repartidorNombre,
    required String moneda,
    double? monto,
    int totalOrdenes = 0,
    List<String> ordenesIds = const [],
    double? kilometrosRecorridos,
    int? diasTrabajados,
    String metodoPago = 'por_orden',
  }) async {
    final localId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    final ahora = DateTime.now().toIso8601String();

    final solicitudUi = {
      'id': localId,
      'estado': 'PENDIENTE',
      'monto': monto ?? 0,
      'moneda': moneda,
      'fecha_solicitud': ahora,
      'total_ordenes_entregadas': totalOrdenes,
      'ordenes_incluidas': ordenesIds,
      'kilometros_recorridos': kilometrosRecorridos,
      'dias_trabajados': diasTrabajados,
      'metodo_pago_solicitud': metodoPago,
      'pendiente_sync': true,
    };

    await guardarSolicitudLocal(repartidorId: repartidorId, solicitudUi: solicitudUi);

    final historial = await RepartidorPerfilCacheService.getCachedHistorialPagos();
    final sinDuplicado =
        historial.where((h) => h['pendiente_sync'] != true).toList();
    await RepartidorPerfilCacheService.cacheHistorialPagos([solicitudUi, ...sinDuplicado]);

    final saldoCache = await RepartidorPerfilCacheService.getCachedSaldo();
    final saldoRaw = saldoCache?['saldo'];
    final saldoNum =
        saldoRaw is num ? saldoRaw.toDouble() : double.tryParse('$saldoRaw') ?? 0;
    await RepartidorPerfilCacheService.cacheSaldo(
      saldoNum,
      moneda,
      solicitudPendiente: true,
    );

    await SyncService().addOperation(
      type: 'solicitud_pago_repartidor',
      ordenId: repartidorId,
      data: {
        'repartidor_id': repartidorId,
        'tenant_id': tenantId,
        'repartidor_nombre': repartidorNombre,
        'moneda': moneda,
        'monto': monto ?? 0,
        'total_ordenes': totalOrdenes,
        'ordenes_incluidas': ordenesIds,
        'kilometros_recorridos': kilometrosRecorridos,
        'dias_trabajados': diasTrabajados,
        'local_id': localId,
      },
    );
  }

  /// Órdenes cobrables desde caché local (modo offline).
  static Future<List<String>> ordenesIdsDesdeCache({
    required String repartidorNombre,
    required bool esRecolector,
  }) async {
    final ordenes = await OrdenCacheService.getCachedOrders();
    final estadoObjetivo = esRecolector ? 'RECOGIDO' : 'ENTREGADO';
    final out = <String>[];
    for (final orden in ordenes) {
      if ((orden.repartidor ?? '').trim() != repartidorNombre.trim()) continue;
      if (orden.estado != estadoObjetivo) continue;
      if (orden.fechaEntrega == null) continue;
      if (orden.pagada == true) continue;
      if (esRecolector && orden.tipoOrden?.toUpperCase() != 'RECOGIDA') continue;
      out.add(orden.id);
    }
    return out;
  }

  static Future<List<Map<String, dynamic>>> historialConLocales(
    String repartidorId,
  ) async {
    final base = await RepartidorPerfilCacheService.getCachedHistorialPagos();
    final local = await getSolicitudLocal(repartidorId);
    if (local == null) return base;
    final sinLocales = base.where((h) => h['pendiente_sync'] != true).toList();
    return [local, ...sinLocales];
  }
}
