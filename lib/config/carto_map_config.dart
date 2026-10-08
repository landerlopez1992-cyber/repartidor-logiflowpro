/// Mapa CARTO Voyager. La clave va en el código para que ninguna
/// compilación (local o de tienda) pida teselas sin ella.
/// Sin clave, CARTO pinta «API KEY REQUIRED».
class CartoMapConfig {
  CartoMapConfig._();

  static const String apiKey = 'cb1_4erj_1_d46a5e0e8e16e9fe0bfc7029';

  static const bool hasApiKey = true;

  static const String urlTemplate =
      'https://basemaps.cartocdn.com/rastertiles/voyager/'
      '{z}/{x}/{y}.png?key=$apiKey';

  static const List<String> subdomains = <String>[];

  static const String attribution = '© OpenStreetMap © CARTO';
}
