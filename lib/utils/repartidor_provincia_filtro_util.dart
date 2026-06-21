import '../models/orden.dart';

/// Filtra órdenes según `provincias_config` / `provincias_asignadas` del repartidor.
class RepartidorProvinciaFiltroUtil {
  RepartidorProvinciaFiltroUtil._();

  static Map<String, Map<String, dynamic>> parseProvinciasConfig(dynamic raw) {
    final out = <String, Map<String, dynamic>>{};
    if (raw is! List) return out;
    for (final item in raw) {
      if (item is! Map) continue;
      final provincia = item['provincia']?.toString().trim();
      if (provincia == null || provincia.isEmpty) continue;
      out[provincia.toLowerCase()] = {
        'tipo': item['tipo']?.toString() ?? 'normal',
        'municipios': (item['municipios'] as List<dynamic>?)
                ?.map((e) => e.toString().trim().toLowerCase())
                .where((s) => s.isNotEmpty)
                .toList() ??
            <String>[],
      };
    }
    return out;
  }

  static List<String> parseProvinciasAsignadasCsv(String? csv) {
    if (csv == null || csv.trim().isEmpty) return [];
    return csv
        .split(',')
        .map((p) => p.trim().toLowerCase())
        .where((p) => p.isNotEmpty)
        .toList();
  }

  static bool tieneCoberturaConfigurada({
    required Map<String, Map<String, dynamic>> provinciasConfig,
    required List<String> provinciasAsignadas,
  }) {
    return provinciasConfig.isNotEmpty || provinciasAsignadas.isNotEmpty;
  }

  static String _norm(String? v) => (v ?? '').trim().toLowerCase();

  /// Si la orden está asignada a [repartidorNombre], siempre visible.
  /// Si no hay cobertura configurada, visible (comportamiento previo).
  static bool ordenEnCobertura({
    required Orden orden,
    required String? repartidorNombre,
    required Map<String, Map<String, dynamic>> provinciasConfig,
    required List<String> provinciasAsignadas,
  }) {
    final asignado = orden.repartidorNombre?.trim();
    final yo = repartidorNombre?.trim();
    if (yo != null && yo.isNotEmpty && asignado == yo) return true;

    if (!tieneCoberturaConfigurada(
      provinciasConfig: provinciasConfig,
      provinciasAsignadas: provinciasAsignadas,
    )) {
      return true;
    }

    final provincia = _norm(orden.provinciaDestino);
    final municipio = _norm(orden.municipioDestino);
    if (provincia.isEmpty) return false;

    if (provinciasConfig.containsKey(provincia)) {
      final cfg = provinciasConfig[provincia]!;
      final municipios = (cfg['municipios'] as List<String>?) ?? [];
      if (municipios.isEmpty) return true;
      if (municipio.isEmpty) return false;
      return municipios.contains(municipio);
    }

    if (provinciasAsignadas.contains(provincia)) return true;

    return false;
  }

  static List<Orden> filtrarOrdenes({
    required List<Orden> ordenes,
    required String? repartidorNombre,
    required Map<String, Map<String, dynamic>> provinciasConfig,
    required List<String> provinciasAsignadas,
  }) {
    if (!tieneCoberturaConfigurada(
      provinciasConfig: provinciasConfig,
      provinciasAsignadas: provinciasAsignadas,
    )) {
      return ordenes;
    }
    return ordenes
        .where((o) => ordenEnCobertura(
              orden: o,
              repartidorNombre: repartidorNombre,
              provinciasConfig: provinciasConfig,
              provinciasAsignadas: provinciasAsignadas,
            ))
        .toList();
  }
}
