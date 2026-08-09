import 'dart:math' as math;

import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'ruta_geometria_osrm_service.dart';
import 'sync_service.dart';

/// Un paso de navegación (giro / continuar), estilo Google Directions.
class TaxiNavStep {
  const TaxiNavStep({
    required this.instruction,
    required this.maneuver,
    required this.lat,
    required this.lng,
    this.distanceM = 0,
    this.distanceText = '',
  });

  final String instruction;
  final String maneuver;
  final double lat;
  final double lng;
  final int distanceM;
  final String distanceText;

  TaxiManeuverIcon get iconKind {
    final m = maneuver.toLowerCase();
    if (m.contains('uturn') || m.contains('u-turn')) {
      return TaxiManeuverIcon.uTurn;
    }
    if (m.contains('left')) return TaxiManeuverIcon.left;
    if (m.contains('right')) return TaxiManeuverIcon.right;
    if (m.contains('roundabout') || m.contains('rotary')) {
      return TaxiManeuverIcon.roundabout;
    }
    if (m.contains('arrive') || m.contains('destination')) {
      return TaxiManeuverIcon.arrive;
    }
    return TaxiManeuverIcon.straight;
  }

  factory TaxiNavStep.fromJson(Map<String, dynamic> m) {
    return TaxiNavStep(
      instruction: m['instruction']?.toString() ?? '',
      maneuver: m['maneuver']?.toString() ?? '',
      lat: (m['lat'] as num?)?.toDouble() ?? 0,
      lng: (m['lng'] as num?)?.toDouble() ?? 0,
      distanceM: (m['distance_m'] as num?)?.toInt() ?? 0,
      distanceText: m['distance_text']?.toString() ?? '',
    );
  }
}

enum TaxiManeuverIcon { left, right, straight, uTurn, roundabout, arrive }

/// Resultado de ruta + ETA (Google Directions con tráfico vía Edge, o OSRM).
class TaxiDirectionsResult {
  const TaxiDirectionsResult({
    required this.points,
    this.durationS,
    this.distanceM,
    this.durationText = '',
    this.traffic = false,
    this.provider = '',
    this.steps = const [],
  });

  final List<LatLng> points;
  final int? durationS;
  final int? distanceM;
  final String durationText;
  final bool traffic;
  final String provider;
  final List<TaxiNavStep> steps;
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

  static List<TaxiNavStep> _parseSteps(dynamic raw) {
    if (raw is! List) return const [];
    final out = <TaxiNavStep>[];
    for (final e in raw) {
      if (e is Map) {
        final s = TaxiNavStep.fromJson(Map<String, dynamic>.from(e));
        if (s.instruction.isNotEmpty) out.add(s);
      }
    }
    return out;
  }

  /// Próximo giro respecto a la posición del chofer.
  static TaxiNavStep? proximoPaso({
    required List<TaxiNavStep> steps,
    required LatLng yo,
  }) {
    if (steps.isEmpty) return null;
    TaxiNavStep? best;
    var bestDist = double.infinity;
    for (final s in steps) {
      final d = _haversineM(yo, LatLng(s.lat, s.lng));
      if (d < 25) continue;
      if (d < bestDist) {
        bestDist = d;
        best = s;
      }
    }
    return best ?? steps.last;
  }

  /// Ruta + duración (preferencia: Google Directions con tráfico vía Edge, o OSRM).
  Future<TaxiDirectionsResult> rutaConEta({
    required LatLng origen,
    required LatLng destino,
    List<LatLng> waypoints = const [],
  }) async {
    final vias = waypoints.take(2).toList();
    final local = vias.isEmpty
        ? offlineHaversine(origen, destino)
        : _offlineMulti(origen, destino, vias);
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
                if (vias.isNotEmpty)
                  'waypoints': [
                    for (final w in vias)
                      {'lat': w.latitude, 'lng': w.longitude},
                  ],
              },
            )
            .timeout(const Duration(seconds: 8));
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
              steps: _parseSteps(data['steps']),
            );
          }
        }
      } catch (_) {}
    }

    try {
      final geom = await RutaGeometriaOsrmService.obtenerGeometriaConduccion([
        origen,
        ...vias,
        destino,
      ]).timeout(
        const Duration(seconds: 8),
        onTimeout: () => [origen, ...vias, destino],
      );
      var distM = 0.0;
      for (var i = 0; i < geom.length - 1; i++) {
        distM += _haversineM(geom[i], geom[i + 1]);
      }
      final etaS =
          (distM / 1000.0 / 32.0 * 3600.0).round().clamp(60, 24 * 3600);
      return TaxiDirectionsResult(
        points: geom.length >= 2 ? geom : local.points,
        durationS: etaS,
        distanceM: distM.round(),
        traffic: false,
        provider: geom.length >= 2 ? 'osrm_local' : 'offline_haversine',
      );
    } catch (_) {
      return local;
    }
  }

  /// Overview completo del viaje: A → paradas → B.
  Future<TaxiDirectionsResult> rutaItinerario({
    required LatLng origen,
    required LatLng destino,
    List<LatLng> paradas = const [],
  }) {
    return rutaConEta(
      origen: origen,
      destino: destino,
      waypoints: paradas,
    );
  }

  static TaxiDirectionsResult _offlineMulti(
    LatLng origen,
    LatLng destino,
    List<LatLng> vias,
  ) {
    final pts = [origen, ...vias, destino];
    var distM = 0.0;
    for (var i = 0; i < pts.length - 1; i++) {
      distM += _haversineM(pts[i], pts[i + 1]);
    }
    final etaS =
        (distM / 1000.0 / 32.0 * 3600.0).round().clamp(60, 24 * 3600);
    return TaxiDirectionsResult(
      points: pts,
      durationS: etaS,
      distanceM: distM.round(),
      traffic: false,
      provider: 'offline_haversine',
    );
  }

  static String formatDuracionCorta(int? durationS) {
    if (durationS == null || durationS <= 0) return '';
    if (durationS < 60) return 'menos de 1 min';
    final min = (durationS / 60).ceil();
    if (min < 60) return '$min min';
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

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
