import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/orden.dart';
import 'direccion_navegacion_service.dart';

/// Abre rutas en Google Maps con direcciones postales completas.
class GoogleMapsRutaService {
  GoogleMapsRutaService._();

  /// Ruta multi-parada usando direcciones (país, provincia, municipio, calle).
  static Future<bool> abrirRutaConDirecciones({
    required List<String> direccionesCompletas,
    String? origenDireccion,
  }) async {
    final paradas = direccionesCompletas
        .map((d) => d.trim())
        .where((d) => d.isNotEmpty)
        .toList();
    if (paradas.isEmpty) return false;

    try {
      final destino = paradas.last;
      final params = <String, String>{
        'api': '1',
        'destination': destino,
        'travelmode': 'driving',
      };

      if (origenDireccion != null && origenDireccion.trim().isNotEmpty) {
        params['origin'] = origenDireccion.trim();
      }

      if (paradas.length > 1) {
        params['waypoints'] = paradas.sublist(0, paradas.length - 1).join('|');
      }

      final uri = Uri.https('www.google.com', '/maps/dir/', params);
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      print('⚠️ Google Maps ruta direcciones: $e');
      return false;
    }
  }

  /// Varias órdenes en orden de ruta (resuelve sucursal / vendedor / destinatario).
  static Future<bool> abrirRutaOrdenes({
    required List<Orden> ordenes,
    Map<String, Map<String, dynamic>>? sucursalesPorOrdenId,
    String? paisOperacion,
    LatLng? origenCoordenadas,
  }) async {
    final direcciones = <String>[];

    for (final orden in ordenes) {
      final suc = sucursalesPorOrdenId?[orden.id];
      final res = DireccionNavegacionService.resolver(
        orden: orden,
        sucursal: suc,
        paisOperacion: paisOperacion,
      );
      if (res.esValida) {
        direcciones.add(res.direccionCompleta);
      } else if (orden.latitudEntrega != null && orden.longitudEntrega != null) {
        direcciones.add('${orden.latitudEntrega},${orden.longitudEntrega}');
      }
    }

    if (direcciones.isEmpty) return false;

    String? origen;
    if (origenCoordenadas != null) {
      origen =
          '${origenCoordenadas.latitude},${origenCoordenadas.longitude}';
    }

    return abrirRutaConDirecciones(
      direccionesCompletas: direcciones,
      origenDireccion: origen,
    );
  }

  /// Compatibilidad: solo coordenadas (evitar si hay órdenes con dirección).
  static Future<bool> abrirRutaEnGoogleMaps({
    LatLng? origen,
    required List<LatLng> paradas,
  }) async {
    if (paradas.isEmpty) return false;

    try {
      final destino = paradas.last;
      final params = <String, String>{
        'api': '1',
        'destination': '${destino.latitude},${destino.longitude}',
        'travelmode': 'driving',
      };

      if (origen != null) {
        params['origin'] = '${origen.latitude},${origen.longitude}';
      }

      if (paradas.length > 1) {
        params['waypoints'] = paradas
            .sublist(0, paradas.length - 1)
            .map((p) => '${p.latitude},${p.longitude}')
            .join('|');
      }

      final uri = Uri.https('www.google.com', '/maps/dir/', params);
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      print('⚠️ Google Maps ruta coords: $e');
      return false;
    }
  }
}
