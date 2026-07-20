import 'package:supabase_flutter/supabase_flutter.dart';

/// Oferta / viaje taxi para el socio (app Repartidor).
class TaxiOfertaChofer {
  const TaxiOfertaChofer({
    required this.id,
    required this.estado,
    required this.origenLat,
    required this.origenLng,
    required this.destinoLat,
    required this.destinoLng,
    required this.origenTexto,
    required this.destinoTexto,
    required this.distanciaKm,
    required this.distanciaMi,
    required this.gananciaUsd,
    required this.pasajeroNombre,
    this.pasajeroFotoUrl,
    this.rutaFase = 'hacia_pasajero',
  });

  final String id;
  final String estado;
  final double origenLat;
  final double origenLng;
  final double destinoLat;
  final double destinoLng;
  final String origenTexto;
  final String destinoTexto;
  final double distanciaKm;
  final double distanciaMi;
  final double gananciaUsd;
  final String pasajeroNombre;
  final String? pasajeroFotoUrl;
  final String rutaFase;

  bool get haciaPasajero =>
      rutaFase == 'hacia_pasajero' || estado == 'aceptado';

  bool get haciaDestino =>
      rutaFase == 'hacia_destino' || estado == 'en_viaje';

  factory TaxiOfertaChofer.fromJson(Map<String, dynamic> m) {
    return TaxiOfertaChofer(
      id: m['id']?.toString() ?? '',
      estado: m['estado']?.toString() ?? '',
      origenLat: (m['origen_lat'] as num?)?.toDouble() ?? 0,
      origenLng: (m['origen_lng'] as num?)?.toDouble() ?? 0,
      destinoLat: (m['destino_lat'] as num?)?.toDouble() ?? 0,
      destinoLng: (m['destino_lng'] as num?)?.toDouble() ?? 0,
      origenTexto: m['origen_texto']?.toString() ?? '',
      destinoTexto: m['destino_texto']?.toString() ?? '',
      distanciaKm: (m['distancia_km'] as num?)?.toDouble() ?? 0,
      distanciaMi: (m['distancia_mi'] as num?)?.toDouble() ?? 0,
      gananciaUsd: (m['ganancia_usd'] as num?)?.toDouble() ??
          (m['precio_usd'] as num?)?.toDouble() ??
          0,
      pasajeroNombre: m['pasajero_nombre']?.toString() ?? 'Pasajero',
      pasajeroFotoUrl: m['pasajero_foto_url']?.toString(),
      rutaFase: m['ruta_fase']?.toString() ?? 'hacia_pasajero',
    );
  }
}

class TaxiChoferService {
  TaxiChoferService._();
  static final TaxiChoferService instance = TaxiChoferService._();

  SupabaseClient get _db => Supabase.instance.client;

  Future<TaxiOfertaChofer?> detalleOferta(String solicitudId) async {
    final res = await _db.rpc(
      'taxi_oferta_detalle_chofer',
      params: {'p_solicitud_id': solicitudId},
    );
    if (res is! Map || res['ok'] != true) return null;
    return TaxiOfertaChofer.fromJson(Map<String, dynamic>.from(res));
  }

  Future<({bool ok, String? err, TaxiOfertaChofer? oferta})> aceptar(
    String solicitudId,
  ) async {
    try {
      final res = await _db.rpc(
        'taxi_aceptar_viaje_chofer',
        params: {'p_solicitud_id': solicitudId},
      );
      if (res is! Map) {
        return (ok: false, err: 'Respuesta inválida', oferta: null);
      }
      final map = Map<String, dynamic>.from(res);
      if (map['ok'] != true) {
        return (
          ok: false,
          err: map['mensaje']?.toString() ??
              map['error']?.toString() ??
              'No se pudo aceptar',
          oferta: null,
        );
      }
      return (
        ok: true,
        err: null,
        oferta: TaxiOfertaChofer.fromJson(map),
      );
    } catch (e) {
      return (ok: false, err: e.toString(), oferta: null);
    }
  }

  Future<({bool ok, String? err})> rechazar(String solicitudId) async {
    try {
      final res = await _db.rpc(
        'taxi_rechazar_viaje_chofer',
        params: {'p_solicitud_id': solicitudId},
      );
      if (res is Map && res['ok'] == true) {
        return (ok: true, err: null);
      }
      return (ok: false, err: 'No se pudo rechazar');
    } catch (e) {
      return (ok: false, err: e.toString());
    }
  }

  Future<({bool ok, String? err, TaxiOfertaChofer? oferta})> lleguePasajero(
    String solicitudId,
  ) async {
    try {
      final res = await _db.rpc(
        'taxi_chofer_llegue_pasajero',
        params: {'p_solicitud_id': solicitudId},
      );
      if (res is! Map || res['ok'] != true) {
        return (
          ok: false,
          err: res is Map ? res['error']?.toString() : 'Error',
          oferta: null,
        );
      }
      return (
        ok: true,
        err: null,
        oferta: TaxiOfertaChofer.fromJson(Map<String, dynamic>.from(res)),
      );
    } catch (e) {
      return (ok: false, err: e.toString(), oferta: null);
    }
  }

  Future<({bool ok, String? err})> completar(String solicitudId) async {
    try {
      final res = await _db.rpc(
        'taxi_chofer_completar_viaje',
        params: {'p_solicitud_id': solicitudId},
      );
      if (res is Map && res['ok'] == true) return (ok: true, err: null);
      return (ok: false, err: 'No se pudo completar');
    } catch (e) {
      return (ok: false, err: e.toString());
    }
  }

  Future<void> actualizarUbicacion({
    required String solicitudId,
    required double lat,
    required double lng,
  }) async {
    try {
      await _db.rpc(
        'taxi_chofer_actualizar_ubicacion',
        params: {
          'p_solicitud_id': solicitudId,
          'p_lat': lat,
          'p_lng': lng,
        },
      );
    } catch (_) {}
  }
}
