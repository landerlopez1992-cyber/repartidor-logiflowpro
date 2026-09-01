/// Clave API de CARTO Basemaps (gratis dentro del límite de uso).
///
/// Solicitar en: https://carto.com/basemaps/apikey
///
/// Compilar / ejecutar con:
/// `--dart-define=CARTO_BASEMAP_KEY=tu_clave_aqui`
///
/// Sin clave, Carto sirve las teselas con la marca de agua
/// "API KEY REQUIRED" (el mapa funciona pero se ve feo).
class CartoMapConfig {
  CartoMapConfig._();

  static const String apiKey = String.fromEnvironment('CARTO_BASEMAP_KEY');

  static const String _stylePath =
      'rastertiles/voyager/{z}/{x}/{y}.png';

  /// Plantilla FlutterMap / fetch HTTP (incluye `?key=` si hay clave).
  static String get urlTemplate {
    final base =
        'https://{s}.basemaps.cartocdn.com/$_stylePath';
    final key = apiKey.trim();
    if (key.isEmpty) return base;
    return '$base?key=${Uri.encodeComponent(key)}';
  }

  static bool get hasApiKey => apiKey.trim().isNotEmpty;

  static const String attribution =
      '© OpenStreetMap © CARTO';
}
