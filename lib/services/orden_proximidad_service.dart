import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import '../models/orden.dart';
import 'direccion_navegacion_service.dart';
import 'paises_service.dart';

/// Ordena órdenes de la más cercana a la más lejana respecto al repartidor.
class OrdenProximidadService {
  OrdenProximidadService._();

  static Future<Position?> obtenerPosicionActual() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      return Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
    } catch (e) {
      print('⚠️ GPS proximidad: $e');
      return null;
    }
  }

  static Future<({double lat, double lon})?> resolverCoordenadasOrden(
    Orden orden, {
    String? paisOperacion,
    Map<String, dynamic>? sucursal,
  }) async {
    if (orden.latitudEntrega != null && orden.longitudEntrega != null) {
      return (lat: orden.latitudEntrega!, lon: orden.longitudEntrega!);
    }

    try {
      final res = await DireccionNavegacionService.resolverConPaisOrden(
        orden,
        sucursal: sucursal,
      );
      if (!res.esValida) return null;

      final locations = await locationFromAddress(res.direccionCompleta);
      if (locations.isEmpty) return null;
      return (
        lat: locations.first.latitude,
        lon: locations.first.longitude,
      );
    } catch (e) {
      print('⚠️ Geocoding orden #${orden.numeroOrden}: $e');
      return null;
    }
  }

  static double distanciaMetros(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  /// Devuelve órdenes ordenadas + secuencia (1..n) y distancia en metros desde el repartidor.
  static Future<({
    List<Orden> ordenadas,
    Map<String, int> secuencia,
    Map<String, double> distanciaMetros,
    Position? posicion,
  })> ordenarPorCercania({
    required List<Orden> ordenes,
    String? paisOperacion,
    Map<String, Map<String, dynamic>>? sucursalesPorOrdenId,
  }) async {
    final pos = await obtenerPosicionActual();
    if (pos == null) {
      return (
        ordenadas: List<Orden>.from(ordenes),
        secuencia: <String, int>{},
        distanciaMetros: <String, double>{},
        posicion: null as Position?,
      );
    }

    final conDistancia = <({Orden orden, double metros})>[];

    for (final orden in ordenes) {
      final coord = await resolverCoordenadasOrden(
        orden,
        paisOperacion: paisOperacion,
        sucursal: sucursalesPorOrdenId?[orden.id],
      );
      if (coord == null) {
        conDistancia.add((orden: orden, metros: double.infinity));
        continue;
      }
      final m = distanciaMetros(
        pos.latitude,
        pos.longitude,
        coord.lat,
        coord.lon,
      );
      conDistancia.add((orden: orden, metros: m));
    }

    conDistancia.sort((a, b) => a.metros.compareTo(b.metros));

    final ordenadas = conDistancia.map((e) => e.orden).toList();
    final secuencia = <String, int>{};
    final distancias = <String, double>{};
    for (var i = 0; i < conDistancia.length; i++) {
      final id = conDistancia[i].orden.id;
      secuencia[id] = i + 1;
      distancias[id] = conDistancia[i].metros;
    }

    return (
      ordenadas: ordenadas,
      secuencia: secuencia,
      distanciaMetros: distancias,
      posicion: pos,
    );
  }
}
