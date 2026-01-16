/// Modelo para representar una ruta optimizada
class RutaOptimizada {
  final String id;
  final String repartidorId;
  final String repartidorNombre;
  final DateTime fechaCreacion;
  final double distanciaTotal; // km
  final int tiempoTotalEstimado; // minutos
  final String estado; // PENDIENTE, EN_CURSO, COMPLETADA
  final List<OrdenRuta> ordenes;

  RutaOptimizada({
    required this.id,
    required this.repartidorId,
    required this.repartidorNombre,
    required this.fechaCreacion,
    required this.distanciaTotal,
    required this.tiempoTotalEstimado,
    required this.estado,
    required this.ordenes,
  });

  factory RutaOptimizada.fromMap(Map<String, dynamic> map) {
    return RutaOptimizada(
      id: map['id'] ?? '',
      repartidorId: map['repartidor_id'] ?? '',
      repartidorNombre: map['repartidor_nombre'] ?? '',
      fechaCreacion: map['fecha_creacion'] != null
          ? DateTime.parse(map['fecha_creacion'])
          : DateTime.now(),
      distanciaTotal: (map['distancia_total'] ?? 0.0).toDouble(),
      tiempoTotalEstimado: map['tiempo_total_estimado'] ?? 0,
      estado: map['estado'] ?? 'PENDIENTE',
      ordenes: (map['ordenes'] as List<dynamic>?)
              ?.map((o) => OrdenRuta.fromMap(o))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'repartidor_id': repartidorId,
      'repartidor_nombre': repartidorNombre,
      'fecha_creacion': fechaCreacion.toIso8601String(),
      'distancia_total': distanciaTotal,
      'tiempo_total_estimado': tiempoTotalEstimado,
      'estado': estado,
      'ordenes': ordenes.map((o) => o.toMap()).toList(),
    };
  }
}

/// Modelo para representar una orden en una ruta optimizada
class OrdenRuta {
  final String ordenId;
  final int ordenSecuencia; // Orden en la ruta (1, 2, 3, ...)
  final double distanciaDesdeAnterior; // km
  final int tiempoDesdeAnterior; // minutos
  final double? latitud;
  final double? longitud;
  final String? direccion;

  OrdenRuta({
    required this.ordenId,
    required this.ordenSecuencia,
    required this.distanciaDesdeAnterior,
    required this.tiempoDesdeAnterior,
    this.latitud,
    this.longitud,
    this.direccion,
  });

  factory OrdenRuta.fromMap(Map<String, dynamic> map) {
    return OrdenRuta(
      ordenId: map['orden_id'] ?? '',
      ordenSecuencia: map['orden_secuencia'] ?? 0,
      distanciaDesdeAnterior: (map['distancia_desde_anterior'] ?? 0.0).toDouble(),
      tiempoDesdeAnterior: map['tiempo_desde_anterior'] ?? 0,
      latitud: map['latitud'] != null ? (map['latitud'] as num).toDouble() : null,
      longitud: map['longitud'] != null ? (map['longitud'] as num).toDouble() : null,
      direccion: map['direccion'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'orden_id': ordenId,
      'orden_secuencia': ordenSecuencia,
      'distancia_desde_anterior': distanciaDesdeAnterior,
      'tiempo_desde_anterior': tiempoDesdeAnterior,
      'latitud': latitud,
      'longitud': longitud,
      'direccion': direccion,
    };
  }
}



