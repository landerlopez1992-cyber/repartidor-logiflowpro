/// Servicio para resolver el problema del viajante (TSP - Traveling Salesman Problem)
class TSPOptimizadorService {
  /// Resuelve TSP usando algoritmo Nearest Neighbor (Vecino Más Cercano)
  /// 
  /// [matrizDistancias]: Matriz n×n con distancias entre puntos
  /// [puntoInicio]: Índice del punto de inicio (repartidor, generalmente 0)
  /// 
  /// Retorna: Lista de índices en orden optimizado
  List<int> resolverNearestNeighbor(
    List<List<double>> matrizDistancias,
    int puntoInicio,
  ) {
    final n = matrizDistancias.length;
    final ruta = <int>[puntoInicio];
    final visitados = List<bool>.filled(n, false);
    visitados[puntoInicio] = true;
    
    int puntoActual = puntoInicio;
    
    // Visitar todos los puntos
    while (ruta.length < n) {
      int siguientePunto = -1;
      double distanciaMinima = double.infinity;
      
      // Encontrar el punto no visitado más cercano
      for (int i = 0; i < n; i++) {
        if (!visitados[i] && matrizDistancias[puntoActual][i] < distanciaMinima) {
          distanciaMinima = matrizDistancias[puntoActual][i];
          siguientePunto = i;
        }
      }
      
      if (siguientePunto != -1) {
        ruta.add(siguientePunto);
        visitados[siguientePunto] = true;
        puntoActual = siguientePunto;
      } else {
        break; // No hay más puntos por visitar
      }
    }
    
    return ruta;
  }
  
  /// Mejora una ruta usando algoritmo 2-Opt
  List<int> mejorarRuta2Opt(
    List<int> rutaInicial,
    List<List<double>> matrizDistancias,
  ) {
    List<int> mejorRuta = List.from(rutaInicial);
    double mejorDistancia = calcularDistanciaTotal(mejorRuta, matrizDistancias);
    bool mejorado = true;
    int maxIteraciones = 100; // Límite de seguridad
    int iteraciones = 0;
    
    // Iterar hasta que no se pueda mejorar más
    while (mejorado && iteraciones < maxIteraciones) {
      mejorado = false;
      iteraciones++;
      
      // Intentar todos los posibles intercambios de 2 aristas
      for (int i = 1; i < mejorRuta.length - 2; i++) {
        for (int j = i + 1; j < mejorRuta.length; j++) {
          // Crear nueva ruta intercambiando segmento
          final nuevaRuta = _intercambiarSegmento(mejorRuta, i, j);
          final nuevaDistancia = calcularDistanciaTotal(nuevaRuta, matrizDistancias);
          
          // Si es mejor, aceptarla
          if (nuevaDistancia < mejorDistancia) {
            mejorRuta = nuevaRuta;
            mejorDistancia = nuevaDistancia;
            mejorado = true;
            break; // Reiniciar búsqueda con nueva ruta
          }
        }
        if (mejorado) break;
      }
    }
    
    return mejorRuta;
  }
  
  /// Calcula la distancia total de una ruta
  double calcularDistanciaTotal(
    List<int> ruta,
    List<List<double>> matrizDistancias,
  ) {
    if (ruta.length < 2) return 0.0;
    
    double total = 0.0;
    
    for (int i = 0; i < ruta.length - 1; i++) {
      final desde = ruta[i];
      final hasta = ruta[i + 1];
      total += matrizDistancias[desde][hasta];
    }
    
    return total;
  }
  
  /// Intercambia un segmento de la ruta (operación 2-Opt)
  List<int> _intercambiarSegmento(List<int> ruta, int i, int j) {
    final nuevaRuta = <int>[];
    
    // Mantener inicio hasta i
    nuevaRuta.addAll(ruta.sublist(0, i));
    
    // Invertir segmento de i a j
    nuevaRuta.addAll(ruta.sublist(i, j + 1).reversed);
    
    // Mantener desde j+1 hasta el final
    nuevaRuta.addAll(ruta.sublist(j + 1));
    
    return nuevaRuta;
  }
}



