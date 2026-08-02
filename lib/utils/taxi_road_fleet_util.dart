import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../services/ruta_geometria_osrm_service.dart';
import 'taxi_nearby_fleet_util.dart';

/// Flota demo que circula por polilíneas de calle (no vuela en línea libre).
class TaxiRoadFleetUtil {
  TaxiRoadFleetUtil._();

  static List<List<LatLng>>? _rutasCache;

  /// Waypoints reales del barrio 10 de Octubre (Habana) → OSRM las pega a calles.
  static final List<List<LatLng>> _semillasHabana = [
    // Calzada del 10 de Octubre (tramo)
    [
      const LatLng(23.1068, -82.3728),
      const LatLng(23.1088, -82.3692),
      const LatLng(23.1108, -82.3650),
    ],
    // Santa Catalina
    [
      const LatLng(23.1112, -82.3715),
      const LatLng(23.1104, -82.3680),
      const LatLng(23.1096, -82.3642),
    ],
    // Luis Estévez
    [
      const LatLng(23.1072, -82.3688),
      const LatLng(23.1092, -82.3682),
      const LatLng(23.1116, -82.3676),
    ],
    // Remedios / paralelo
    [
      const LatLng(23.1080, -82.3708),
      const LatLng(23.1095, -82.3675),
      const LatLng(23.1110, -82.3645),
    ],
    // Bucle corto barrio
    [
      const LatLng(23.1085, -82.3700),
      const LatLng(23.1100, -82.3685),
      const LatLng(23.1100, -82.3665),
      const LatLng(23.1085, -82.3655),
      const LatLng(23.1075, -82.3675),
      const LatLng(23.1085, -82.3700),
    ],
  ];

  /// Fallback sin red: segmentos densos aproximados a la trama urbana.
  static List<List<LatLng>> get _fallbackHabana {
    List<LatLng> densify(List<LatLng> pts, {int steps = 8}) {
      if (pts.length < 2) return pts;
      final out = <LatLng>[pts.first];
      for (var i = 0; i < pts.length - 1; i++) {
        final a = pts[i];
        final b = pts[i + 1];
        for (var s = 1; s <= steps; s++) {
          final t = s / steps;
          out.add(LatLng(
            a.latitude + (b.latitude - a.latitude) * t,
            a.longitude + (b.longitude - a.longitude) * t,
          ));
        }
      }
      return out;
    }

    return _semillasHabana.map((r) {
      final d = densify(r);
      if (d.length < 3) return d;
      return [...d, ...d.reversed.skip(1)];
    }).toList();
  }

  /// Carga rutas pegadas a calles (OSRM). Cache en memoria.
  static Future<List<List<LatLng>>> loadHabanaRoadRoutes() async {
    if (_rutasCache != null && _rutasCache!.isNotEmpty) {
      return _rutasCache!;
    }
    final rutas = await _rutasDesdeSemillas(_semillasHabana);
    _rutasCache = rutas.isNotEmpty ? rutas : _fallbackHabana;
    return _rutasCache!;
  }

  static String? _aroundKey;
  static List<List<LatLng>>? _aroundCache;

  /// Rutas reales alrededor de la GPS del chofer (mismo estilo calle).
  static Future<List<List<LatLng>>> loadRoadRoutesAround(LatLng center) async {
    final key =
        '${(center.latitude * 200).round()}_${(center.longitude * 200).round()}';
    if (_aroundKey == key &&
        _aroundCache != null &&
        _aroundCache!.isNotEmpty) {
      return _aroundCache!;
    }

    final semillas = <List<LatLng>>[
      // Cruceta N–S / E–O + diagonales cortas (~350–550 m)
      [
        _offsetM(center, 420, 0),
        center,
        _offsetM(center, 420, math.pi),
      ],
      [
        _offsetM(center, 380, math.pi / 2),
        center,
        _offsetM(center, 380, -math.pi / 2),
      ],
      [
        _offsetM(center, 300, math.pi / 4),
        center,
        _offsetM(center, 300, math.pi / 4 + math.pi),
      ],
      [
        _offsetM(center, 300, -math.pi / 4),
        center,
        _offsetM(center, 300, -math.pi / 4 + math.pi),
      ],
      [
        _offsetM(center, 250, 0.3),
        _offsetM(center, 250, 1.2),
        _offsetM(center, 250, 2.2),
        _offsetM(center, 250, 3.4),
        _offsetM(center, 250, 0.3),
      ],
    ];

    final rutas = await _rutasDesdeSemillas(semillas);
    if (rutas.isEmpty) {
      // Fallback densificado alrededor del GPS (sin red).
      final fb = semillas.map((r) {
        final d = _densify(r);
        if (d.length < 3) return d;
        return [...d, ...d.reversed.skip(1)];
      }).toList();
      _aroundKey = key;
      _aroundCache = fb;
      return fb;
    }
    _aroundKey = key;
    _aroundCache = rutas;
    return rutas;
  }

  static Future<List<List<LatLng>>> _rutasDesdeSemillas(
    List<List<LatLng>> semillas,
  ) async {
    final rutas = <List<LatLng>>[];
    for (final seed in semillas) {
      try {
        final geo =
            await RutaGeometriaOsrmService.obtenerGeometriaConduccion(seed);
        if (geo.length >= 3) {
          final loop = <LatLng>[...geo, ...geo.reversed.skip(1)];
          rutas.add(loop);
        }
      } catch (_) {}
    }
    return rutas;
  }

  static List<LatLng> _densify(List<LatLng> pts, {int steps = 8}) {
    if (pts.length < 2) return pts;
    final out = <LatLng>[pts.first];
    for (var i = 0; i < pts.length - 1; i++) {
      final a = pts[i];
      final b = pts[i + 1];
      for (var s = 1; s <= steps; s++) {
        final t = s / steps;
        out.add(LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        ));
      }
    }
    return out;
  }

  static LatLng _offsetM(LatLng c, double distM, double bearingRad) {
    const r = 6371000.0;
    final ang = distM / r;
    final lat1 = c.latitude * math.pi / 180;
    final lng1 = c.longitude * math.pi / 180;
    final lat2 = math.asin(
      math.sin(lat1) * math.cos(ang) +
          math.cos(lat1) * math.sin(ang) * math.cos(bearingRad),
    );
    final lng2 = lng1 +
        math.atan2(
          math.sin(bearingRad) * math.sin(ang) * math.cos(lat1),
          math.cos(ang) - math.sin(lat1) * math.sin(lat2),
        );
    return LatLng(lat2 * 180 / math.pi, lng2 * 180 / math.pi);
  }

  /// Spawnea [count] taxis repartidos en las rutas, mismo tamaño lógico.
  static List<TaxiFleetCar> spawnOnRoutes({
    required List<List<LatLng>> routes,
    int count = 8,
    int seed = 7,
    double speedMpsMin = 6.5,
    double speedMpsMax = 12.0,
  }) {
    if (routes.isEmpty) return const [];
    final rng = math.Random(seed);
    final n = count.clamp(3, 14);
    final out = <TaxiFleetCar>[];

    for (var i = 0; i < n; i++) {
      final path = routes[i % routes.length];
      final cum = _cumulativeMeters(path);
      final total = cum.isEmpty ? 0.0 : cum.last;
      if (total < 20 || path.length < 2) continue;

      final startDist = (i / n) * total + rng.nextDouble() * (total * 0.08);
      final dist = startDist % total;
      final pos = _pointAtDistance(path, cum, dist);
      final heading = _headingAtDistance(path, cum, dist);
      final speed =
          speedMpsMin + rng.nextDouble() * (speedMpsMax - speedMpsMin);

      out.add(
        TaxiFleetCar(
          point: pos,
          headingDeg: heading,
          speedMps: speed,
          turnDegPerSec: 0,
          roadPath: path,
          roadCumDist: cum,
          distAlongM: dist,
        ),
      );
    }
    return out;
  }

  /// Avanza solo por la polilínea de calle (rumbo = dirección del tramo).
  static void tickOnRoads(List<TaxiFleetCar> cars, {required double dt}) {
    if (cars.isEmpty || dt <= 0) return;
    final d = dt.clamp(0.008, 0.12);

    for (final car in cars) {
      final path = car.roadPath;
      final cum = car.roadCumDist;
      if (path == null || cum == null || path.length < 2 || cum.isEmpty) {
        continue;
      }
      final total = cum.last;
      if (total < 5) continue;

      car.distAlongM = (car.distAlongM + car.speedMps * d) % total;
      car.point = _pointAtDistance(path, cum, car.distAlongM);
      car.headingDeg = _headingAtDistance(path, cum, car.distAlongM);
    }
  }

  static List<double> _cumulativeMeters(List<LatLng> path) {
    final cum = <double>[0];
    for (var i = 1; i < path.length; i++) {
      cum.add(cum.last + _haversineM(path[i - 1], path[i]));
    }
    return cum;
  }

  static LatLng _pointAtDistance(
    List<LatLng> path,
    List<double> cum,
    double distM,
  ) {
    final total = cum.last;
    var d = distM % total;
    if (d < 0) d += total;
    for (var i = 1; i < cum.length; i++) {
      if (d <= cum[i]) {
        final segLen = cum[i] - cum[i - 1];
        final t = segLen <= 0 ? 0.0 : (d - cum[i - 1]) / segLen;
        final a = path[i - 1];
        final b = path[i];
        return LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        );
      }
    }
    return path.last;
  }

  static double _headingAtDistance(
    List<LatLng> path,
    List<double> cum,
    double distM,
  ) {
    final total = cum.last;
    var d = distM % total;
    if (d < 0) d += total;
    // Mirar un poco adelante para rumbo estable.
    final look = (d + 12).clamp(0.0, total - 0.01);
    final from = _pointAtDistance(path, cum, d);
    final to = _pointAtDistance(path, cum, look);
    return _bearingDeg(from, to);
  }

  static double _haversineM(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  static double _bearingDeg(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLng = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }
}
