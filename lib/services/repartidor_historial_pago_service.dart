import '../main.dart';

/// Solicitud de nómina con órdenes resueltas para mostrar en historial.
class HistorialNominaItem {
  HistorialNominaItem({
    required this.solicitud,
    this.ordenesDetalle = const [],
  });

  final Map<String, dynamic> solicitud;
  final List<Map<String, dynamic>> ordenesDetalle;

  String get id => solicitud['id']?.toString() ?? '';
  String get estado => solicitud['estado']?.toString() ?? 'PENDIENTE';
  String get metodo => solicitud['metodo_pago_solicitud']?.toString() ?? 'por_orden';
  double get monto {
    final m = solicitud['monto'];
    return m is num ? m.toDouble() : double.tryParse('$m') ?? 0;
  }

  String get moneda => solicitud['moneda']?.toString() ?? 'USD';
  int get totalOrdenes => solicitud['total_ordenes_entregadas'] is int
      ? solicitud['total_ordenes_entregadas'] as int
      : int.tryParse('${solicitud['total_ordenes_entregadas']}') ?? ordenesDetalle.length;

  double? get kilometros {
    final k = solicitud['kilometros_recorridos'];
    if (k == null) return null;
    return k is num ? k.toDouble() : double.tryParse('$k');
  }

  int? get diasTrabajados {
    final d = solicitud['dias_trabajados'];
    if (d == null) return null;
    return d is int ? d : int.tryParse('$d');
  }

  String get unidadDistancia {
    final u = solicitud['tarifa_unidad_snapshot']?.toString() ?? 'km';
    return u == 'milla' ? 'milla' : 'km';
  }

  bool get dineroEnviado => solicitud['dinero_enviado'] == true;

  DateTime? get fechaSolicitud => _parseFecha(solicitud['fecha_solicitud']);
  DateTime? get fechaAceptacion => _parseFecha(solicitud['fecha_aceptacion']);

  static DateTime? _parseFecha(dynamic raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  static String etiquetaMetodo(String metodo) {
    switch (metodo) {
      case 'por_distancia':
        return 'Por recorrido';
      case 'por_dia':
        return 'Por días laborables';
      case 'por_orden':
      default:
        return 'Por órdenes / saldo';
    }
  }
}

class RepartidorHistorialPagoService {
  RepartidorHistorialPagoService._();

  static List<String> _parseOrdenesIds(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    }
    return [];
  }

  /// Últimos [meses] de solicitudes con detalle de órdenes incluidas.
  static Future<List<HistorialNominaItem>> cargarHistorial(
    String repartidorId, {
    int meses = 24,
    int limite = 200,
  }) async {
    final desde = DateTime.now().subtract(Duration(days: meses * 31));

    final rows = await supabase
        .from('solicitudes_pago_repartidores')
        .select(
          'id, estado, monto, moneda, fecha_solicitud, fecha_aceptacion, '
          'total_ordenes_entregadas, ordenes_incluidas, kilometros_recorridos, '
          'dias_trabajados, metodo_pago_solicitud, tarifa_unidad_snapshot, '
          'aceptado_por_nombre, dinero_enviado, notas, created_at',
        )
        .eq('repartidor_id', repartidorId)
        .gte('fecha_solicitud', desde.toIso8601String())
        .order('fecha_solicitud', ascending: false)
        .limit(limite);

    final solicitudes = List<Map<String, dynamic>>.from(rows);
    final todosIds = <String>{};
    for (final s in solicitudes) {
      todosIds.addAll(_parseOrdenesIds(s['ordenes_incluidas']));
    }

    final ordenesMap = <String, Map<String, dynamic>>{};
    if (todosIds.isNotEmpty) {
      try {
        final ids = todosIds.toList();
        for (var i = 0; i < ids.length; i += 80) {
          final chunk = ids.sublist(i, i + 80 > ids.length ? ids.length : i + 80);
          final ordenes = await supabase
              .from('ordenes')
              .select('id, numero_orden, fecha_entrega, estado, destinatario_nombre')
              .inFilter('id', chunk);
          for (final o in List<Map<String, dynamic>>.from(ordenes)) {
            final oid = o['id']?.toString();
            if (oid != null) ordenesMap[oid] = o;
          }
        }
      } catch (e) {
        print('⚠️ Detalle de órdenes en historial de nómina (se muestran solicitudes): $e');
      }
    }

    return solicitudes.map((s) {
      final ids = _parseOrdenesIds(s['ordenes_incluidas']);
      final detalle = ids
          .map((id) => ordenesMap[id])
          .whereType<Map<String, dynamic>>()
          .toList();
      return HistorialNominaItem(solicitud: s, ordenesDetalle: detalle);
    }).toList();
  }

  /// Acreditaciones de saldo (entregas que sumaron al saldo), últimos meses.
  static Future<List<Map<String, dynamic>>> cargarAcreditacionesSaldo(
    String repartidorId, {
    int meses = 6,
    int limite = 100,
  }) async {
    final desde = DateTime.now().subtract(Duration(days: meses * 31));
    try {
      final rows = await supabase
          .from('repartidor_movimientos_saldo')
          .select('id, tipo, monto, moneda, detalle, created_at, orden_id')
          .eq('repartidor_id', repartidorId)
          .gte('created_at', desde.toIso8601String())
          .gt('monto', 0)
          .order('created_at', ascending: false)
          .limit(limite);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      print('⚠️ Movimientos saldo no disponibles: $e');
      return [];
    }
  }
}
