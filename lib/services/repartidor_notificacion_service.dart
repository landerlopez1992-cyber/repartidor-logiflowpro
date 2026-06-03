import 'package:repartidor_logiflow_pro/main.dart' show supabase;
import 'package:repartidor_logiflow_pro/constants/repartidor_notificacion_tipos.dart';

/// Alineado con VolonexPro+: el panel inserta en `notificaciones_repartidores`
/// (tipo `nueva_orden`, con `tenant_id`). La app repartidor no inserta filas
/// (evita RLS y duplicados); solo lee la BD y muestra push local.
class RepartidorNotificacionService {
  RepartidorNotificacionService._();

  /// Tras Realtime en `ordenes`: esperar notificación del panel y refrescar UI.
  static Future<Map<String, dynamic>?> buscarNotificacionOrdenEnBd({
    required String repartidorId,
    required String numeroOrden,
    String? ordenId,
    Duration esperaPanel = const Duration(milliseconds: 800),
  }) async {
    await Future<void>.delayed(esperaPanel);

    for (var intento = 0; intento < 3; intento++) {
      try {
        var query = supabase
            .from('notificaciones_repartidores')
            .select('id, tipo, titulo, mensaje, numero_orden, leida, orden_id')
            .eq('repartidor_id', repartidorId)
            .inFilter('tipo', RepartidorNotificacionTipos.tiposOrdenNueva);

        if (ordenId != null && ordenId.isNotEmpty) {
          query = query.eq('orden_id', ordenId);
        } else if (numeroOrden.isNotEmpty && numeroOrden != 'N/A') {
          query = query.eq('numero_orden', numeroOrden);
        }

        final row = await query
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (row != null) return Map<String, dynamic>.from(row);
      } catch (e) {
        print('⚠️ buscarNotificacionOrdenEnBd: $e');
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    return null;
  }

  static Future<Map<String, dynamic>?> buscarNotificacionPagoEnBd({
    required String repartidorId,
    required String pagoId,
    required String tipo,
  }) async {
    try {
      final row = await supabase
          .from('notificaciones_repartidores')
          .select('id, tipo, titulo, mensaje, leida, pago_id')
          .eq('repartidor_id', repartidorId)
          .eq('pago_id', pagoId)
          .eq('tipo', tipo)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      if (row != null) return Map<String, dynamic>.from(row);
    } catch (e) {
      print('⚠️ buscarNotificacionPagoEnBd: $e');
    }
    return null;
  }

  /// Coincide con asignación en panel (`repartidor_nombre` = `usuarios.nombre`).
  static bool nombresRepartidorCoinciden(String? a, String? b) {
    if (a == null || b == null) return false;
    return a.trim() == b.trim();
  }
}
