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

  bool get esPorOrden => metodoPago == 'por_orden';
  bool get esPorDistancia => metodoPago == 'por_distancia';
  bool get esPorDia => metodoPago == 'por_dia';
  bool get unidadEsMilla => unidad == 'milla';

  String get etiquetaUnidadDistancia => unidadEsMilla ? 'millas' : 'kilómetros';
}

class RepartidorSolicitudPagoService {
  RepartidorSolicitudPagoService._();

  static Future<RepartidorSolicitudPreview?> cargarPreview(String repartidorId) async {
    final raw = await supabase.rpc(
      'repartidor_preview_solicitud_pago',
      params: {'p_repartidor_id': repartidorId},
    );
    final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    if (map['ok'] != true) return null;

    final ultima = map['ultima_nomina_fecha']?.toString();
    DateTime? fechaUltima;
    if (ultima != null && ultima.isNotEmpty) {
      fechaUltima = DateTime.tryParse(ultima);
    }

    final tarifaRaw = map['tarifa'];
    final saldoRaw = map['saldo_acumulado'];
    final montoDiaRaw = map['monto_estimado_por_dia'];

    return RepartidorSolicitudPreview(
      metodoPago: map['metodo_pago']?.toString() ?? 'por_orden',
      tarifa: tarifaRaw is num ? tarifaRaw.toDouble() : double.tryParse('$tarifaRaw') ?? 0,
      unidad: map['unidad']?.toString() ?? 'orden',
      moneda: map['moneda']?.toString() ?? 'USD',
      saldoAcumulado: saldoRaw is num ? saldoRaw.toDouble() : double.tryParse('$saldoRaw') ?? 0,
      solicitudPendiente: map['solicitud_pendiente'] == true,
      ultimaNominaFecha: fechaUltima,
      diasDesdeUltimaNomina: map['dias_desde_ultima_nomina'] is int
          ? map['dias_desde_ultima_nomina'] as int
          : int.tryParse('${map['dias_desde_ultima_nomina']}') ?? 0,
      montoEstimadoPorDia: montoDiaRaw is num
          ? montoDiaRaw.toDouble()
          : double.tryParse('$montoDiaRaw') ?? 0,
    );
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
