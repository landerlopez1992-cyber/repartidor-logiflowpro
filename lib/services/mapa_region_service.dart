import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centro/zoom del mapa según país de operación (caché local para reabrir offline).
class MapaRegionService {
  MapaRegionService._();

  static const _keyCentroLat = 'mapa_region_centro_lat';
  static const _keyCentroLon = 'mapa_region_centro_lon';
  static const _keyZoom = 'mapa_region_zoom';
  static const _keyPais = 'mapa_region_pais';

  static LatLng centroPorPais(String? pais) {
    final p = (pais ?? 'Cuba').toLowerCase();
    if (p.contains('estados') || p.contains('united') || p == 'usa') {
      return const LatLng(25.7617, -80.1918); // Miami área referencia
    }
    if (p.contains('méxico') || p.contains('mexico')) {
      return const LatLng(19.4326, -99.1332);
    }
    return const LatLng(23.1136, -82.3666); // La Habana
  }

  static double zoomInicialPorPais(String? pais) {
    final p = (pais ?? 'Cuba').toLowerCase();
    if (p.contains('estados') || p.contains('united') || p == 'usa') {
      return 10.0;
    }
    if (p.contains('méxico') || p.contains('mexico')) {
      return 10.0;
    }
    return 11.0;
  }

  static Future<void> guardarRegion({
    required String pais,
    required LatLng centro,
    double zoom = 11,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyPais, pais);
      await prefs.setDouble(_keyCentroLat, centro.latitude);
      await prefs.setDouble(_keyCentroLon, centro.longitude);
      await prefs.setDouble(_keyZoom, zoom);
    } catch (e) {
      print('⚠️ guardarRegion mapa: $e');
    }
  }

  static Future<({LatLng centro, double zoom, String? pais})?> cargarRegionGuardada() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble(_keyCentroLat);
      final lon = prefs.getDouble(_keyCentroLon);
      if (lat == null || lon == null) return null;
      return (
        centro: LatLng(lat, lon),
        zoom: prefs.getDouble(_keyZoom) ?? 11,
        pais: prefs.getString(_keyPais),
      );
    } catch (e) {
      return null;
    }
  }
}
