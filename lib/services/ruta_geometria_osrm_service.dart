import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Geometría de ruta por carretera (OSRM). Sustituye líneas rectas en el mapa.
class RutaGeometriaOsrmService {
  RutaGeometriaOsrmService._();

  static const String _baseUrl = 'https://router.project-osrm.org';

  static List<LatLng> _lineaRecta(List<LatLng> puntos) => List<LatLng>.from(puntos);

  /// Obtiene la polilínea siguiendo calles entre waypoints en orden.
  static Future<List<LatLng>> obtenerGeometriaConduccion(List<LatLng> waypoints) async {
    if (waypoints.length < 2) return waypoints;

    try {
      final coords = waypoints.map((p) => '${p.longitude},${p.latitude}').join(';');
      final url = Uri.parse(
        '$_baseUrl/route/v1/driving/$coords?overview=full&geometries=geojson',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        return _lineaRecta(waypoints);
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') return _lineaRecta(waypoints);

      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) return _lineaRecta(waypoints);

      final geometry = routes.first['geometry'] as Map<String, dynamic>?;
      final coordinates = geometry?['coordinates'] as List?;
      if (coordinates == null || coordinates.isEmpty) {
        return _lineaRecta(waypoints);
      }

      return coordinates.map((c) {
        final pair = c as List;
        return LatLng(
          (pair[1] as num).toDouble(),
          (pair[0] as num).toDouble(),
        );
      }).toList();
    } catch (e) {
      print('⚠️ OSRM geometría ruta: $e');
      return _lineaRecta(waypoints);
    }
  }
}
