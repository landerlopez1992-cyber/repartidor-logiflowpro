import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../main.dart';
import 'ruta_optimizador_service.dart';
import 'tsp_optimizador_service.dart';
import '../models/ruta_optimizada.dart';

/// Servicio principal para optimizar rutas de repartidores
class OptimizadorRutasService {
  final RutaOptimizadorService _rutaOptimizador = RutaOptimizadorService();
  final TSPOptimizadorService _tspOptimizador = TSPOptimizadorService();

  /// Convierte una dirección a coordenadas (geocoding)
  Future<Map<String, double>?> geocodificarDireccion(String direccion) async {
    try {
      // Agregar país si no está en la dirección (mejora la precisión)
      String direccionCompleta = direccion;
      if (!direccion.toLowerCase().contains('cuba') && 
          !direccion.toLowerCase().contains('usa') &&
          !direccion.toLowerCase().contains('united states') &&
          !direccion.toLowerCase().contains('estados unidos')) {
        // Intentar con Cuba primero (más común en este sistema)
        direccionCompleta = '$direccion, Cuba';
      }
      
      print('   🔍 Geocodificando: "$direccionCompleta"');
      final locations = await locationFromAddress(direccionCompleta);
      
      if (locations.isNotEmpty) {
        final result = {
          'lat': locations.first.latitude,
          'lon': locations.first.longitude,
        };
        print('   ✅ Coordenadas obtenidas: ${result['lat']}, ${result['lon']}');
        return result;
      }
      
      // Si falla con Cuba, intentar sin país
      if (direccionCompleta != direccion) {
        print('   🔄 Reintentando sin país...');
        final locations2 = await locationFromAddress(direccion);
        if (locations2.isNotEmpty) {
          final result = {
            'lat': locations2.first.latitude,
            'lon': locations2.first.longitude,
          };
          print('   ✅ Coordenadas obtenidas (sin país): ${result['lat']}, ${result['lon']}');
          return result;
        }
      }
      
      print('   ⚠️ No se encontraron ubicaciones para: "$direccion"');
      return null;
    } catch (e) {
      print('❌ Error geocodificando dirección "$direccion": $e');
      // Intentar sin país si falló
      if (direccion.contains(', Cuba')) {
        try {
          final direccionSinPais = direccion.replaceAll(', Cuba', '').trim();
          print('   🔄 Reintentando sin país: "$direccionSinPais"');
          final locations = await locationFromAddress(direccionSinPais);
          if (locations.isNotEmpty) {
            return {
              'lat': locations.first.latitude,
              'lon': locations.first.longitude,
            };
          }
        } catch (e2) {
          print('   ❌ Error en reintento: $e2');
        }
      }
      return null;
    }
  }

  /// Obtiene la ubicación actual del repartidor
  Future<Map<String, double>?> obtenerUbicacionRepartidor() async {
    try {
      // Verificar permisos
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('⚠️ Servicio de ubicación deshabilitado');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('⚠️ Permisos de ubicación denegados');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('⚠️ Permisos de ubicación denegados permanentemente');
        return null;
      }

      // Obtener ubicación
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      return {
        'lat': position.latitude,
        'lon': position.longitude,
      };
    } catch (e) {
      print('❌ Error obteniendo ubicación: $e');
      return null;
    }
  }

  /// Optimiza la ruta de entrega para un repartidor
  /// 
  /// [repartidorId]: ID del repartidor
  /// [repartidorNombre]: Nombre del repartidor
  /// [ordenes]: Lista de órdenes con {id, direccion_entrega, ...}
  /// [ubicacionRepartidor]: {lat, lon} del repartidor (opcional, si no se proporciona se obtiene con GPS)
  /// 
  /// Retorna: RutaOptimizada con órdenes ordenadas
  Future<RutaOptimizada?> optimizarRuta({
    required String repartidorId,
    required String repartidorNombre,
    required List<Map<String, dynamic>> ordenes,
    Map<String, double>? ubicacionRepartidor,
    String? tenantId,
  }) async {
    try {
      print('🚀 Iniciando optimización de ruta para $repartidorNombre');
      print('📦 Número de órdenes: ${ordenes.length}');

      // 1. Obtener ubicación del repartidor (última ubicación conocida desde BD)
      Map<String, double>? ubicacion;
      bool usarPuntoPartida = false; // Si incluir punto de partida en la optimización
      
      if (ubicacionRepartidor != null) {
        ubicacion = ubicacionRepartidor;
        usarPuntoPartida = true;
        print('📍 Ubicación repartidor proporcionada: ${ubicacion['lat']}, ${ubicacion['lon']}');
      } else {
        // Intentar obtener última ubicación conocida del repartidor desde la BD
        print('📍 Buscando última ubicación conocida del repartidor...');
        try {
          final ubicacionResponse = await supabase
              .from('ubicaciones_repartidores')
              .select('latitude, longitude, ubicacion_timestamp')
              .eq('repartidor_id', repartidorId)
              .order('ubicacion_timestamp', ascending: false)
              .limit(1)
              .maybeSingle();
          
          if (ubicacionResponse != null) {
            final lat = ubicacionResponse['latitude'] as double?;
            final lon = ubicacionResponse['longitude'] as double?;
            final timestamp = ubicacionResponse['ubicacion_timestamp'] as String?;
            
            if (lat != null && lon != null) {
              // Verificar que la ubicación no sea muy antigua (máximo 24 horas)
              if (timestamp != null) {
                final fechaUbicacion = DateTime.parse(timestamp);
                final horasDesdeUbicacion = DateTime.now().difference(fechaUbicacion).inHours;
                
                if (horasDesdeUbicacion <= 24) {
                  ubicacion = {'lat': lat, 'lon': lon};
                  usarPuntoPartida = true;
                  print('✅ Última ubicación conocida del repartidor: $lat, $lon (hace $horasDesdeUbicacion horas)');
                } else {
                  print('⚠️ Última ubicación del repartidor es muy antigua (hace $horasDesdeUbicacion horas)');
                  print('   ℹ️ Se optimizará solo el orden de las órdenes entre sí');
                }
              } else {
                ubicacion = {'lat': lat, 'lon': lon};
                usarPuntoPartida = true;
                print('✅ Última ubicación conocida del repartidor: $lat, $lon');
              }
            }
          } else {
            print('ℹ️ No hay ubicación conocida del repartidor en la BD');
            print('   ℹ️ Se optimizará solo el orden de las órdenes entre sí');
          }
        } catch (e) {
          print('⚠️ Error obteniendo ubicación del repartidor: $e');
          print('   ℹ️ Se optimizará solo el orden de las órdenes entre sí');
        }
      }

      // 2. Preparar puntos (solo órdenes, o repartidor + órdenes si hay ubicación)
      final puntos = <Map<String, dynamic>>[];
      
      // Solo agregar punto de partida si tenemos ubicación del repartidor
      if (usarPuntoPartida && ubicacion != null) {
        puntos.add({
          'lat': ubicacion['lat']!,
          'lon': ubicacion['lon']!,
          'tipo': 'repartidor',
        });
        print('📍 Incluyendo punto de partida del repartidor en la optimización');
      } else {
        print('📍 NO se incluirá punto de partida - optimizando solo orden de órdenes');
      }

      final ordenesConCoordenadas = <Map<String, dynamic>>[];

      // 3. Geocodificar direcciones de las órdenes
      print('🗺️ Geocodificando direcciones de órdenes...');
      for (var orden in ordenes) {
        final direccion = orden['direccion_entrega'] as String?;
        if (direccion == null || direccion.isEmpty) {
          print('⚠️ Orden ${orden['id']} no tiene dirección de entrega');
          continue;
        }

        // Intentar usar coordenadas existentes si están disponibles
        double? lat = orden['latitud_entrega'] != null
            ? (orden['latitud_entrega'] as num).toDouble()
            : null;
        double? lon = orden['longitud_entrega'] != null
            ? (orden['longitud_entrega'] as num).toDouble()
            : null;

        // Si no hay coordenadas, geocodificar
        if (lat == null || lon == null) {
          print('   Geocodificando: $direccion');
          final coordenadas = await geocodificarDireccion(direccion);
          if (coordenadas != null) {
            lat = coordenadas['lat'];
            lon = coordenadas['lon'];
            print('   ✅ Coordenadas obtenidas: $lat, $lon');
          } else {
            print('   ❌ No se pudieron obtener coordenadas');
            continue;
          }
        } else {
          print('   ✅ Usando coordenadas existentes: $lat, $lon');
        }

        puntos.add({
          'lat': lat!,
          'lon': lon!,
          'tipo': 'orden',
        });

        ordenesConCoordenadas.add({
          ...orden,
          'lat': lat,
          'lon': lon,
        });
      }

      if (ordenesConCoordenadas.isEmpty) {
        print('❌ No se pudieron obtener coordenadas para ninguna orden');
        return null;
      }

      print('✅ ${ordenesConCoordenadas.length} órdenes con coordenadas');

      // 4. Obtener matriz de distancias
      print('📊 Calculando distancias...');
      final matrizDistancias = await _rutaOptimizador.obtenerMatrizDistancias(puntos);
      print('✅ Matriz de distancias calculada (${matrizDistancias.length}x${matrizDistancias.length})');

      // 5. Resolver TSP con Nearest Neighbor
      print('🔍 Optimizando ruta con Nearest Neighbor...');
      int puntoInicio = usarPuntoPartida ? 0 : 0; // Si no hay punto de partida, empezar desde la primera orden
      
      // Si no hay punto de partida, empezar desde la orden más cercana al centro de todas
      if (!usarPuntoPartida && puntos.isNotEmpty) {
        // Calcular centroide de todas las órdenes
        double latPromedio = 0;
        double lonPromedio = 0;
        for (var punto in puntos) {
          latPromedio += punto['lat'] as double;
          lonPromedio += punto['lon'] as double;
        }
        latPromedio /= puntos.length;
        lonPromedio /= puntos.length;
        
        // Encontrar la orden más cercana al centroide usando distancia Haversine
        double distanciaMinima = double.infinity;
        const double radioTierra = 6371; // km
        
        for (int i = 0; i < puntos.length; i++) {
          final lat = puntos[i]['lat'] as double;
          final lon = puntos[i]['lon'] as double;
          
          // Calcular distancia Haversine
          final dLat = (lat - latPromedio) * (pi / 180);
          final dLon = (lon - lonPromedio) * (pi / 180);
          final a = sin(dLat / 2) * sin(dLat / 2) +
              cos(latPromedio * (pi / 180)) * cos(lat * (pi / 180)) *
              sin(dLon / 2) * sin(dLon / 2);
          final c = 2 * atan2(sqrt(a), sqrt(1 - a));
          final distancia = radioTierra * c;
          
          if (distancia < distanciaMinima) {
            distanciaMinima = distancia;
            puntoInicio = i;
          }
        }
        print('📍 Punto de inicio: orden más cercana al centro (índice $puntoInicio)');
      }
      
      var rutaOptimizada = _tspOptimizador.resolverNearestNeighbor(
        matrizDistancias,
        puntoInicio,
      );
      print('✅ Ruta inicial: ${rutaOptimizada.join(" → ")}');

      // 6. Mejorar con 2-Opt
      print('✨ Mejorando ruta con 2-Opt...');
      rutaOptimizada = _tspOptimizador.mejorarRuta2Opt(
        rutaOptimizada,
        matrizDistancias,
      );
      print('✅ Ruta optimizada: ${rutaOptimizada.join(" → ")}');

      // 7. Calcular distancias y tiempos, crear lista de órdenes optimizadas
      final ordenesRuta = <OrdenRuta>[];
      double distanciaTotal = 0.0;
      int tiempoTotal = 0;
      
      int indiceOffset = usarPuntoPartida ? 1 : 0; // Si hay punto de partida, las órdenes empiezan en índice 1

      for (int i = 0; i < rutaOptimizada.length - 1; i++) {
        final puntoActual = rutaOptimizada[i];
        final puntoSiguiente = rutaOptimizada[i + 1];

        final distancia = matrizDistancias[puntoActual][puntoSiguiente];
        distanciaTotal += distancia;

        // Calcular tiempo estimado (asumiendo velocidad promedio de 50 km/h)
        final tiempoMinutos = (distancia / 50 * 60).round();
        tiempoTotal += tiempoMinutos;

        // Si hay punto de partida, el índice 0 es el repartidor, las órdenes empiezan en 1
        // Si NO hay punto de partida, todos los índices son órdenes
        if (!usarPuntoPartida || puntoActual > 0) {
          final ordenIndex = puntoActual - indiceOffset;
          if (ordenIndex >= 0 && ordenIndex < ordenesConCoordenadas.length) {
            final orden = ordenesConCoordenadas[ordenIndex];
            ordenesRuta.add(OrdenRuta(
              ordenId: orden['id'] as String,
              ordenSecuencia: ordenesRuta.length + 1,
              distanciaDesdeAnterior: distancia,
              tiempoDesdeAnterior: tiempoMinutos,
              latitud: orden['lat'] as double?,
              longitud: orden['lon'] as double?,
              direccion: orden['direccion_entrega'] as String?,
            ));
          }
        }
      }

      print('✅ Ruta optimizada: ${distanciaTotal.toStringAsFixed(2)} km, ${tiempoTotal} minutos');

      // 8. Crear objeto RutaOptimizada
      final ruta = RutaOptimizada(
        id: '', // Se asignará al guardar en BD
        repartidorId: repartidorId,
        repartidorNombre: repartidorNombre,
        fechaCreacion: DateTime.now(),
        distanciaTotal: distanciaTotal,
        tiempoTotalEstimado: tiempoTotal,
        estado: 'PENDIENTE',
        ordenes: ordenesRuta,
      );

      return ruta;
    } catch (e, stackTrace) {
      print('❌ Error optimizando ruta: $e');
      print('❌ Stack trace: $stackTrace');
      return null;
    }
  }

  /// Guarda una ruta optimizada en la base de datos
  Future<String?> guardarRutaOptimizada(RutaOptimizada ruta, String tenantId) async {
    try {
      // Insertar ruta
      final rutaResponse = await supabase
          .from('rutas_repartidor')
          .insert({
            'repartidor_id': ruta.repartidorId,
            'repartidor_nombre': ruta.repartidorNombre,
            'fecha_creacion': ruta.fechaCreacion.toIso8601String(),
            'distancia_total': ruta.distanciaTotal,
            'tiempo_total_estimado': ruta.tiempoTotalEstimado,
            'estado': ruta.estado,
            'tenant_id': tenantId,
          })
          .select()
          .single();

      final rutaId = rutaResponse['id'] as String;

      // Insertar órdenes de la ruta
      for (var ordenRuta in ruta.ordenes) {
        await supabase.from('ordenes_ruta').insert({
          'ruta_id': rutaId,
          'orden_id': ordenRuta.ordenId,
          'orden_secuencia': ordenRuta.ordenSecuencia,
          'distancia_desde_anterior': ordenRuta.distanciaDesdeAnterior,
          'tiempo_desde_anterior': ordenRuta.tiempoDesdeAnterior,
          'latitud': ordenRuta.latitud,
          'longitud': ordenRuta.longitud,
        });

        // Actualizar orden con información de ruta
        await supabase
            .from('ordenes')
            .update({
              'orden_ruta': ordenRuta.ordenSecuencia,
              'distancia_desde_anterior': ordenRuta.distanciaDesdeAnterior,
              'tiempo_estimado_desde_anterior': ordenRuta.tiempoDesdeAnterior,
              'latitud_entrega': ordenRuta.latitud,
              'longitud_entrega': ordenRuta.longitud,
            })
            .eq('id', ordenRuta.ordenId);
      }

      print('✅ Ruta guardada con ID: $rutaId');
      return rutaId;
    } catch (e) {
      print('❌ Error guardando ruta: $e');
      return null;
    }
  }

  /// Obtiene la preferencia del repartidor (usar ruta optimizada o no)
  Future<bool> obtenerPreferenciaRutaOptimizada(String repartidorId) async {
    try {
      final response = await supabase
          .from('usuarios')
          .select('usar_ruta_optimizada')
          .eq('id', repartidorId)
          .single();

      return response['usar_ruta_optimizada'] as bool? ?? true;
    } catch (e) {
      print('❌ Error obteniendo preferencia: $e');
      return true; // Por defecto, usar ruta optimizada
    }
  }

  /// Guarda la preferencia del repartidor
  Future<void> guardarPreferenciaRutaOptimizada(
    String repartidorId,
    bool usarRutaOptimizada,
  ) async {
    try {
      await supabase
          .from('usuarios')
          .update({'usar_ruta_optimizada': usarRutaOptimizada})
          .eq('id', repartidorId);

      print('✅ Preferencia guardada: usar_ruta_optimizada = $usarRutaOptimizada');
    } catch (e) {
      print('❌ Error guardando preferencia: $e');
    }
  }

  /// Obtiene la ruta optimizada activa para un repartidor
  Future<RutaOptimizada?> obtenerRutaActiva(String repartidorId) async {
    try {
      final response = await supabase
          .from('rutas_repartidor')
          .select('''
            *,
            ordenes_ruta (
              orden_id,
              orden_secuencia,
              distancia_desde_anterior,
              tiempo_desde_anterior,
              latitud,
              longitud
            )
          ''')
          .eq('repartidor_id', repartidorId)
          .eq('estado', 'EN_CURSO')
          .order('fecha_creacion', ascending: false)
          .limit(1);

      if (response.isEmpty) {
        return null;
      }

      final rutaData = response[0];
      final ordenesRutaData = rutaData['ordenes_ruta'] as List<dynamic>? ?? [];

      final ordenes = ordenesRutaData.map((o) {
        // Obtener dirección de la orden
        return OrdenRuta(
          ordenId: o['orden_id'] as String,
          ordenSecuencia: o['orden_secuencia'] as int,
          distanciaDesdeAnterior: (o['distancia_desde_anterior'] as num).toDouble(),
          tiempoDesdeAnterior: o['tiempo_desde_anterior'] as int,
          latitud: o['latitud'] != null ? (o['latitud'] as num).toDouble() : null,
          longitud: o['longitud'] != null ? (o['longitud'] as num).toDouble() : null,
        );
      }).toList();

      return RutaOptimizada(
        id: rutaData['id'] as String,
        repartidorId: rutaData['repartidor_id'] as String,
        repartidorNombre: rutaData['repartidor_nombre'] as String,
        fechaCreacion: DateTime.parse(rutaData['fecha_creacion'] as String),
        distanciaTotal: (rutaData['distancia_total'] as num).toDouble(),
        tiempoTotalEstimado: rutaData['tiempo_total_estimado'] as int,
        estado: rutaData['estado'] as String,
        ordenes: ordenes,
      );
    } catch (e) {
      print('❌ Error obteniendo ruta activa: $e');
      return null;
    }
  }
}

