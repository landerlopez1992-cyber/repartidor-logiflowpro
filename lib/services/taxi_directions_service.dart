import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ruta_geometria_osrm_service.dart';
import 'sync_service.dart';

/// Resultado de ruta + ETA (Google Directions con tráfico vía Edge, o OSRM).
class TaxiDirectionsResult {
  const TaxiDirectionsResult({
    required this.points,
    this.durationS,
    this.distanceM,
    this.durationText = '',
    this.traffic = false,
    this.provider = '',
  });

  final List<LatLng> points;
  final int? durationS;
  final int? distanceM;
  final String durationText;
  final bool traffic;
  final String provider;
}

/// Directions para navegación taxi del socio (misma Edge que CubaLink).
class TaxiDirectionsService {
  TaxiDirectionsService._();
  static final TaxiDirectionsService instance = TaxiDirectionsService._();

  SupabaseClient get _db => Supabase.instance.client;
  String? _tenantId;

  Future<String?> _resolveTenantId() async {
    if (_tenantId != null && _tenantId!.isNotEmpty) return _tenantId;
    final authId = _db.auth.currentUser?.id;
    if (authId == null) return null;
    try {
      final row = await _db
          .from('usuarios')
          .select('tenant_id')
          .eq('auth_id', authId)
          .maybeSingle()
          .timeout(const Duration(seconds: 3));
      _tenantId = row?['tenant_id']?.toString();
    } catch (_) {
      return null;
    }
    return _tenantId;
  }

  static double _haversineM(LatLng a, LatLng b) {
    const r = 6371000.0;
    final p1 = a.latitude * math.pi / 180;
    final p2 = b.latitude * math.pi / 180;
    final dp = (b.latitude - a.latitude) * math.pi / 180;
    final dl = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return 2 * r * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  /// ETA + geometría sin red (línea recta + Haversine).
  static TaxiDirectionsResult offlineHaversine(LatLng origen, LatLng destino) {
    final distM = _haversineM(origen, destino);
    final etaS = (distM / 1000.0 / 32.0 * 3600.0).round().clamp(60, 7200);
    return TaxiDirectionsResult(
      points: [origen, destino],
      durationS: etaS,
      distanceM: distM.round(),
      traffic: false,
      provider: 'offline_haversine',
    );
  }

  bool get _pareceOffline {
    try {
      return !SyncService().isOnline;
    } catch (_) {
      return false;
    }
  }

  /// Ruta + duración (preferencia: Google Directions con tráfico vía Edge, o OSRM).
  /// Sin red o con timeout → geometría local inmediata (nunca cuelga).
  Future<TaxiDirectionsResult> rutaConEta({
    required LatLng origen,
    required LatLng destino,
  }) async {
    final local = offlineHaversine(origen, destino);
    if (_pareceOffline) return local;

    final tid = await _resolveTenantId();
    if (tid != null && tid.isNotEmpty) {
      try {
        final res = await _db.functions
            .invoke(
              'fetch-product-page-html',
              body: {
                'action': 'places_directions',
                'tenant_id': tid,
                'origin_lat': origen.latitude,
                'origin_lng': origen.longitude,
                'dest_lat': destino.latitude,
                'dest_lng': destino.longitude,
              },
            )
            .timeout(const Duration(seconds: 5));
        final data = res.data;
        if (res.status == 200 && data is Map && data['ok'] == true) {
          final pts = <LatLng>[];
          final raw = data['points'];
          if (raw is List) {
            for (final p in raw) {
              if (p is Map) {
                final lat = (p['lat'] as num?)?.toDouble();
                final lng = (p['lng'] as num?)?.toDouble();
                if (lat != null && lng != null) {
                  pts.add(LatLng(lat, lng));
                }
              }
            }
          }
          if (pts.length >= 2) {
            return TaxiDirectionsResult(
              points: pts,
              durationS: (data['duration_s'] as num?)?.toInt(),
              distanceM: (data['distance_m'] as num?)?.toInt(),
              durationText: data['duration_text']?.toString() ?? '',
              traffic: data['traffic'] == true,
              provider: data['provider']?.toString() ?? 'google',
            );
          }
        }
      } catch (_) {}
    }

    // Fallback OSRM (timeout corto; si falla → local).
    try {
      final geom = await RutaGeometriaOsrmService.obtenerGeometriaConduccion([
        origen,
        destino,
      ]).timeout(const Duration(seconds: 6), onTimeout: () => [origen, destino]);
      return TaxiDirectionsResult(
        points: geom.length >= 2 ? geom : local.points,
        durationS: local.durationS,
        distanceM: local.distanceM,
        traffic: false,
        provider: geom.length >= 2 ? 'osrm_local' : 'offline_haversine',
      );
    } catch (_) {
      return local;
    }
  }

  /// Texto ETA para UI del chofer.
  static String formatEtaChofer({
    required bool haciaPasajero,
    required bool haciaDestino,
    int? durationS,
    String durationText = '',
  }) {
    final destinoLabel = haciaDestino
        ? 'al destino'
        : (haciaPasajero ? 'al pasajero' : '');
    late final String tiempo;
    if (durationS != null && durationS > 0) {
      if (durationS < 60) {
        tiempo = 'menos de 1 min';
      } else {
        final min = (durationS / 60).ceil();
        if (min < 60) {
          tiempo = '$min min';
        } else {
          final h = min ~/ 60;
          final m = min % 60;
          tiempo = m == 0 ? '$h h' : '$h h $m min';
        }
      }
    } else if (durationText.trim().isNotEmpty) {
      tiempo = durationText.trim();
    } else {
      return haciaDestino
          ? 'Calculando llegada al destino…'
          : 'Calculando llegada al pasajero…';
    }
    if (destinoLabel.isEmpty) return tiempo;
    return 'Llegas $destinoLabel en $tiempo';
  }
}
