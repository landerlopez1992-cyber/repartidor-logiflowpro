import 'dart:convert';

import '../main.dart';

/// Datos para solicitar nómina según método configurado por la empresa.
class RepartidorSolicitudPreview {
  RepartidorSolicitudPreview({
    required this.metodoPago,
    required this.tarifa,
    required this.unidad,
    required this.moneda,
    required this.saldoAcumulado,
    required this.solicitudPendiente,
    this.ultimaNominaFecha,
    this.diasDesdeUltimaNomina = 0,
    this.montoEstimadoPorDia = 0,
    this.diasLaborablesEtiqueta = '',
  });

  final String metodoPago;
  final double tarifa;
  final String unidad;
  final String moneda;
  final double saldoAcumulado;
  final bool solicitudPendiente;
  final DateTime? ultimaNominaFecha;
  final int diasDesdeUltimaNomina;
  final double montoEstimadoPorDia;
  final String diasLaborablesEtiqueta;

  bool get esPorOrden => metodoPago == 'por_orden';
  bool get esPorDistancia => metodoPago == 'por_distancia';
  bool get esPorDia => metodoPago == 'por_dia';
  bool get unidadEsMilla => unidad == 'milla';

  String get etiquetaUnidadDistancia => unidadEsMilla ? 'millas' : 'kilómetros';
}

class RepartidorSolicitudPagoService {
  RepartidorSolicitudPagoService._();

  static bool _okFlag(dynamic v) => v == true || v == 'true' || v == 1;

  static double _asDouble(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  static Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  static RepartidorSolicitudPreview? _previewFromMap(Map<String, dynamic> map) {
    if (map.isEmpty) return null;
    if (map.containsKey('ok') && !_okFlag(map['ok'])) return null;

    final ultima = map['ultima_nomina_fecha']?.toString();
    DateTime? fechaUltima;
    if (ultima != null && ultima.isNotEmpty) {
      fechaUltima = DateTime.tryParse(ultima);
    }

    return RepartidorSolicitudPreview(
      metodoPago: map['metodo_pago']?.toString() ?? 'por_orden',
      tarifa: _asDouble(map['tarifa']),
      unidad: map['unidad']?.toString() ?? 'orden',
      moneda: map['moneda']?.toString() ?? 'USD',
      saldoAcumulado: _asDouble(map['saldo_acumulado']),
      solicitudPendiente: map['solicitud_pendiente'] == true,
      ultimaNominaFecha: fechaUltima,
      diasDesdeUltimaNomina: map['dias_desde_ultima_nomina'] is int
          ? map['dias_desde_ultima_nomina'] as int
          : int.tryParse('${map['dias_desde_ultima_nomina']}') ?? 0,
      montoEstimadoPorDia: _asDouble(map['monto_estimado_por_dia']),
      diasLaborablesEtiqueta: map['dias_laborables_etiqueta']?.toString() ?? '',
    );
  }

  /// Lee tarifa/método directo de `usuarios` (fallback si la RPC falla o hay caché vieja).
  static Future<RepartidorSolicitudPreview?> cargarPreviewDesdeUsuarios(
    String repartidorId,
  ) async {
    final row = await supabase
        .from('usuarios')
        .select(
          'repartidor_metodo_pago, repartidor_tarifa, repartidor_tarifa_unidad, '
          'repartidor_saldo_moneda, repartidor_saldo_acumulado',
        )
        .eq('id', repartidorId)
        .maybeSingle();
    if (row == null) return null;

    final unidadRaw = row['repartidor_tarifa_unidad']?.toString();
    final metodo =
        (row['repartidor_metodo_pago']?.toString() ?? 'por_orden').toLowerCase();
    String unidad;
    if (unidadRaw != null && unidadRaw.trim().isNotEmpty) {
      unidad = unidadRaw.trim().toLowerCase();
    } else if (metodo == 'por_distancia') {
      unidad = 'km';
    } else if (metodo == 'por_dia') {
      unidad = 'dia';
    } else {
      unidad = 'orden';
    }

    return RepartidorSolicitudPreview(
      metodoPago: metodo,
      tarifa: _asDouble(row['repartidor_tarifa']),
      unidad: unidad,
      moneda: (row['repartidor_saldo_moneda']?.toString() ?? 'USD').toUpperCase(),
      saldoAcumulado: _asDouble(row['repartidor_saldo_acumulado']),
      solicitudPendiente: false,
    );
  }

  static Future<RepartidorSolicitudPreview?> cargarPreview(String repartidorId) async {
    try {
      final raw = await supabase.rpc(
        'repartidor_preview_solicitud_pago',
        params: {'p_repartidor_id': repartidorId},
      );
      final map = _asMap(raw);
      final fromRpc = _previewFromMap(map);

      if (fromRpc != null && fromRpc.tarifa > 0) return fromRpc;

      // Si RPC no trae tarifa (o falló ok), leer columnas reales del perfil.
      final fromUser = await cargarPreviewDesdeUsuarios(repartidorId);
      if (fromUser != null && fromUser.tarifa > 0) {
        return RepartidorSolicitudPreview(
          metodoPago: fromRpc?.metodoPago ?? fromUser.metodoPago,
          tarifa: fromUser.tarifa,
          unidad: fromUser.unidad.isNotEmpty
              ? fromUser.unidad
              : (fromRpc?.unidad ?? 'orden'),
          moneda: fromRpc?.moneda ?? fromUser.moneda,
          saldoAcumulado: fromRpc?.saldoAcumulado ?? fromUser.saldoAcumulado,
          solicitudPendiente: fromRpc?.solicitudPendiente ?? false,
          ultimaNominaFecha: fromRpc?.ultimaNominaFecha,
          diasDesdeUltimaNomina: fromRpc?.diasDesdeUltimaNomina ?? 0,
          montoEstimadoPorDia: fromRpc?.montoEstimadoPorDia ?? 0,
          diasLaborablesEtiqueta: fromRpc?.diasLaborablesEtiqueta ?? '',
        );
      }
      return fromRpc ?? fromUser;
    } catch (e) {
      print('⚠️ cargarPreview RPC: $e — fallback usuarios');
      return cargarPreviewDesdeUsuarios(repartidorId);
    }
  }

  static double calcularMontoDistancia({
    required double tarifa,
    required double distancia,
  }) {
    if (tarifa <= 0 || distancia <= 0) return 0;
    return (tarifa * distancia * 100).roundToDouble() / 100;
  }

  static Future<Map<String, dynamic>> crearSolicitud({
    required String repartidorId,
    required String tenantId,
    required String repartidorNombre,
    required String moneda,
    double? monto,
    int totalOrdenes = 0,
    List<String> ordenesIds = const [],
    double? kilometrosRecorridos,
    int? diasTrabajados,
  }) async {
    final raw = await supabase.rpc(
      'repartidor_crear_solicitud_pago',
      params: {
        'p_repartidor_id': repartidorId,
        'p_monto': monto ?? 0,
        'p_moneda': moneda,
        'p_total_ordenes': totalOrdenes,
        'p_ordenes_incluidas': ordenesIds,
        'p_kilometros_recorridos': kilometrosRecorridos,
        'p_repartidor_nombre': repartidorNombre,
        'p_tenant_id': tenantId,
        'p_dias_trabajados': diasTrabajados,
      },
    );
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }
}
