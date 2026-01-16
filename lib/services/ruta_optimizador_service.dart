import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math';

/// Servicio para calcular distancias usando OSRM (Open Source Routing Machine)
class RutaOptimizadorService {
  // OSRM endpoint público (para pruebas)
  // En producción, usar tu propio servidor OSRM
  static const String OSRM_BASE_URL = 'http://router.project-osrm.org';
  
  /// Obtiene la distancia entre dos puntos usando OSRM
  Future<double> obtenerDistancia(
    double lat1, double lon1, // Punto origen
    double lat2, double lon2,  // Punto destino
  ) async {
    try {
      // Construir URL para OSRM
      final url = Uri.parse(
        '$OSRM_BASE_URL/route/v1/driving/'
        '$lon1,$lat1;$lon2,$lat2'
        '?overview=false'
      );
      
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['code'] == 'Ok' && data['routes'] != null && data['routes'].isNotEmpty) {
          // OSRM devuelve la distancia en metros
          final distanciaMetros = data['routes'][0]['distance'] as double;
          
          // Convertir a kilómetros
          return distanciaMetros / 1000.0;
        } else {
          throw Exception('OSRM no pudo calcular la ruta');
        }
      } else {
        throw Exception('Error al obtener distancia: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error obteniendo distancia de OSRM: $e');
      // Fallback: calcular distancia euclidiana usando Haversine
      return _calcularDistanciaHaversine(lat1, lon1, lat2, lon2);
    }
  }
  
  /// Obtiene matriz de distancias entre todos los puntos usando OSRM Table API
  Future<List<List<double>>> obtenerMatrizDistancias(
    List<Map<String, dynamic>> puntos, // [{lat, lon}, {lat, lon}, ...]
  ) async {
    final n = puntos.length;
    final matriz = List.generate(n, (_) => List<double>.filled(n, 0.0));
    
    try {
      // OSRM Table API permite obtener distancias desde un origen a múltiples destinos
      // Construir URL con todos los puntos
      final waypoints = puntos.map((p) => '${p['lon']},${p['lat']}').join(';');
      
      // Obtener distancias desde el primer punto (repartidor) a todos los demás
      final url = Uri.parse(
        '$OSRM_BASE_URL/table/v1/driving/$waypoints'
        '?sources=0' // El primer punto es el origen (repartidor)
      );
      
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['code'] == 'Ok' && data['distances'] != null) {
          final distancias = data['distances'][0] as List;
          
          // Llenar primera fila (desde el repartidor)
          for (int i = 0; i < n && i < distancias.length; i++) {
            matriz[0][i] = (distancias[i] as num).toDouble() / 1000.0; // km
          }
          
          // Para distancias entre órdenes, usar Haversine como aproximación rápida
          // (o hacer requests adicionales a OSRM si se necesita más precisión)
          for (int i = 1; i < n; i++) {
            for (int j = 0; j < n; j++) {
              if (i != j && matriz[i][j] == 0.0) {
                matriz[i][j] = _calcularDistanciaHaversine(
                  puntos[i]['lat']!,
                  puntos[i]['lon']!,
                  puntos[j]['lat']!,
                  puntos[j]['lon']!,
                );
              }
            }
          }
          
          return matriz;
        } else {
          throw Exception('OSRM no pudo calcular la matriz');
        }
      } else {
        throw Exception('Error al obtener matriz: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error obteniendo matriz de OSRM: $e');
      // Fallback: usar distancias Haversine
      return _calcularMatrizHaversine(puntos);
    }
  }
  
  /// Calcula distancia usando fórmula de Haversine (fallback, menos precisa que OSRM)
  double _calcularDistanciaHaversine(
    double lat1, double lon1,
    double lat2, double lon2,
  ) {
    const double radioTierra = 6371; // km
    
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return radioTierra * c;
  }
  
  double _toRadians(double degrees) => degrees * (pi / 180);
  
  List<List<double>> _calcularMatrizHaversine(List<Map<String, dynamic>> puntos) {
    final n = puntos.length;
    final matriz = List.generate(n, (_) => List<double>.filled(n, 0.0));
    
    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        if (i != j) {
          matriz[i][j] = _calcularDistanciaHaversine(
            puntos[i]['lat']!,
            puntos[i]['lon']!,
            puntos[j]['lat']!,
            puntos[j]['lon']!,
          );
        }
      }
    }
    
    return matriz;
  }
}

