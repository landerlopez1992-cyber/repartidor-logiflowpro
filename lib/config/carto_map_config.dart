/// Clave API de CARTO Basemaps (gratis dentro del límite de uso).
///
/// Solicitar en: https://carto.com/basemaps/apikey
///
/// Compilar / ejecutar con:
/// `--dart-define=CARTO_BASEMAP_KEY=tu_clave_aqui`
///
/// Sin clave: no usamos Carto (marca de agua "API KEY REQUIRED");
/// caemos a teselas OpenStreetMap limpio.
class CartoMapConfig {
  CartoMapConfig._();

  static const String apiKey = String.fromEnvironment('CARTO_BASEMAP_KEY');

  static const String _stylePath =
      'rastertiles/voyager/{z}/{x}/{y}.png';

  /// Sin `{s}` — OpenStreetMap no usa subdominios tipo Carto.
  static const String _osmTemplate =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// Plantilla FlutterMap / fetch HTTP (incluye `?key=` si hay clave).
  static String get urlTemplate {
    final key = apiKey.trim();
    if (key.isEmpty) return _osmTemplate;
    return 'https://{s}.basemaps.cartocdn.com/$_stylePath'
        '?key=${Uri.encodeComponent(key)}';
  }

  static bool get hasApiKey => apiKey.trim().isNotEmpty;

  /// Subdominios solo para Carto; OSM no lleva `{s}`.
  static List<String> get subdomains =>
      hasApiKey ? const ['a', 'b', 'c', 'd'] : const <String>[];

  static const String attribution =
      '© OpenStreetMap © CARTO';
}
