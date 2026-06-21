import 'package:geolocator/geolocator.dart';

/// Valida proximidad del repartidor al punto de entrega según `radio_entrega` (metros).
class EntregaGeoValidacionUtil {
  EntregaGeoValidacionUtil._();

  static double distanciaMetros({
    required double latRepartidor,
    required double lngRepartidor,
    required double latDestino,
    required double lngDestino,
  }) {
    return Geolocator.distanceBetween(
      latRepartidor,
      lngRepartidor,
      latDestino,
      lngDestino,
    );
  }

  /// [radioMetros] 0 o negativo = sin límite.
  static ({bool ok, double? distanciaMetros, String? mensaje}) validarRadioEntrega({
    required Position? posicionRepartidor,
    required double? latDestino,
    required double? lngDestino,
    required int radioMetros,
    required bool geolocalizacionObligatoria,
  }) {
    if (!geolocalizacionObligatoria && radioMetros <= 0) {
      return (ok: true, distanciaMetros: null, mensaje: null);
    }

    if (posicionRepartidor == null) {
      if (geolocalizacionObligatoria) {
        return (
          ok: false,
          distanciaMetros: null,
          mensaje: 'Activa la ubicación del dispositivo para confirmar la entrega.',
        );
      }
      return (ok: true, distanciaMetros: null, mensaje: null);
    }

    if (latDestino == null || lngDestino == null) {
      // Sin coordenadas de destino: no bloquear si solo hay radio (no hay referencia)
      if (geolocalizacionObligatoria && radioMetros > 0) {
        return (
          ok: false,
          distanciaMetros: null,
          mensaje: 'Esta orden no tiene coordenadas de entrega. Contacta a la empresa.',
        );
      }
      return (ok: true, distanciaMetros: null, mensaje: null);
    }

    final dist = distanciaMetros(
      latRepartidor: posicionRepartidor.latitude,
      lngRepartidor: posicionRepartidor.longitude,
      latDestino: latDestino,
      lngDestino: lngDestino,
    );

    if (radioMetros > 0 && dist > radioMetros) {
      final metros = dist.round();
      return (
        ok: false,
        distanciaMetros: dist,
        mensaje:
            'Estás a $metros m del punto de entrega. Debes estar dentro de $radioMetros m para marcar como entregada.',
      );
    }

    return (ok: true, distanciaMetros: dist, mensaje: null);
  }
}
