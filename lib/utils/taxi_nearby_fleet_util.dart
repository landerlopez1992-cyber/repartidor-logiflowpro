import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Taxi decorativo con rumbo y velocidad propios (avanza de frente, no de lado).
class TaxiFleetCar {
  TaxiFleetCar({
    required this.point,
    required this.headingDeg,
    required this.speedMps,
    required this.turnDegPerSec,
    this.roadPath,
    this.roadCumDist,
    this.distAlongM = 0,
    this.home,
    this.maxWanderM = 0,
  });

  LatLng point;
  double headingDeg;
  double speedMps;
  double turnDegPerSec;

  /// Si está definido, el auto solo se mueve alrededor de este punto (tierra).
  LatLng? home;
  double maxWanderM;

  /// Si no es null, el auto se anima por esta polilínea de calle.
  List<LatLng>? roadPath;
  List<double>? roadCumDist;
  double distAlongM;

  bool get onRoad =>
      roadPath != null &&
      roadCumDist != null &&
      roadPath!.length >= 2 &&
      roadCumDist!.isNotEmpty;
}

/// Flota decorativa estilo Uber: dispersa + movimiento continuo suave.
class TaxiNearbyFleetUtil {
  TaxiNearbyFleetUtil._();

  static List<TaxiFleetCar> around({
    required LatLng center,
    int count = 9,
    int seed = 7,
    double maxDistM = 4500,
    double minDistM = 400,
  }) {
    final rng = math.Random(seed);
    final out = <TaxiFleetCar>[];
    final maxD = maxDistM.clamp(200.0, 120000.0);
    final minD = minDistM.clamp(80.0, maxD * 0.45);
    final n = count.clamp(3, 18);

    for (var i = 0; i < n; i++) {
      final sector = (i + rng.nextDouble() * 0.65) / n;
      final bearing = sector * 2 * math.pi + (rng.nextDouble() - 0.5) * 0.4;
      final ring = i % 3;
      final t = switch (ring) {
        0 => 0.12 + rng.nextDouble() * 0.28,
        1 => 0.40 + rng.nextDouble() * 0.28,
        _ => 0.70 + rng.nextDouble() * 0.30,
      };
      final distM = minD + t * (maxD - minD);
      final p = _offset(center, distM, bearing);
      // Rumbo inicial distinto por auto (hacia donde “mira” el capó).
      final heading = (bearing * 180 / math.pi + (rng.nextDouble() - 0.5) * 50 + 360) %
          360;
      // Velocidad: ciudad ~25–58 km/h; vista país más rápida para verse en el mapa.
      final city = maxD < 12000;
      final speed = city
          ? (7.0 + rng.nextDouble() * 9.0)
          : (120.0 + rng.nextDouble() * 220.0);
      final turn = city
          ? ((rng.nextDouble() - 0.5) * 28)
          : ((rng.nextDouble() - 0.5) * 18);
      out.add(TaxiFleetCar(
        point: p,
        headingDeg: heading,
        speedMps: speed,
        turnDegPerSec: turn,
      ));
    }
    return out;
  }

  /// Taxis de demostración repartidos por tierra de Cuba (no en el mar).
  /// Un auto por ciudad interior, de Pinar del Río a Guantánamo, más
  /// uno en Isla de la Juventud. El radio corto los mantiene en tierra.
  static List<TaxiFleetCar> acrossCuba({int seed = 7}) {
    const homes = <LatLng>[
      LatLng(22.417, -83.698), // Pinar del Río
      LatLng(22.813, -82.763), // Artemisa
      LatLng(23.052, -82.390), // La Habana (interior, al sur del Malecón)
      LatLng(22.968, -82.156), // San José de las Lajas
      LatLng(22.800, -81.537), // Unión de Reyes
      LatLng(22.722, -80.906), // Colón
      LatLng(22.342, -80.269), // Cruces (interior, fuera de la bahía)
      LatLng(22.406, -79.965), // Santa Clara
      LatLng(21.929, -79.443), // Sancti Spíritus
      LatLng(21.848, -78.763), // Ciego de Ávila
      LatLng(21.381, -77.917), // Camagüey
      LatLng(20.960, -76.954), // Las Tunas
      LatLng(20.887, -76.263), // Holguín
      LatLng(20.373, -76.643), // Bayamo
      LatLng(20.214, -75.992), // Palma Soriano
      LatLng(20.144, -75.209), // Guantánamo
      LatLng(21.820, -82.820), // Nueva Gerona (Isla de la Juventud)
    ];
    final rng = math.Random(seed);
    final out = <TaxiFleetCar>[];
    for (final home in homes) {
      if (!_enTierraCuba(home)) continue;
      var point = home;
      final dist = 180.0 + rng.nextDouble() * 520.0;
      final bearing = rng.nextDouble() * 2 * math.pi;
      final jitter = _offset(home, dist, bearing);
      if (_enTierraCuba(jitter) && _haversineM(home, jitter) < 900) {
        point = jitter;
      }
      final heading = rng.nextDouble() * 360;
      out.add(TaxiFleetCar(
        point: point,
        headingDeg: heading,
        speedMps: 7.0 + rng.nextDouble() * 6.0,
        turnDegPerSec: (rng.nextDouble() - 0.5) * 22,
        home: home,
        maxWanderM: 1100,
      ));
    }
    return out;
  }

  /// Avanza [dt] segundos: cada auto gira un poco y se mueve **hacia delante**.
  static void tick(
    List<TaxiFleetCar> cars, {
    required double dt,
    LatLng? anchor,
    double maxRadiusM = 5000,
    int seed = 0,
  }) {
    if (cars.isEmpty || dt <= 0) return;
    final rng = math.Random(seed ^ (DateTime.now().millisecondsSinceEpoch ~/ 200));
    final maxR = maxRadiusM.clamp(300.0, 120000.0);
    final d = dt.clamp(0.008, 0.12);

    for (var i = 0; i < cars.length; i++) {
      final car = cars[i];
      // Cambios ocasionales de intención (no cada frame).
      if (rng.nextDouble() < 0.012) {
        car.turnDegPerSec = (rng.nextDouble() - 0.5) * 32;
      }
      if (rng.nextDouble() < 0.008) {
        final city = maxR < 15000;
        car.speedMps = city
            ? (6.5 + rng.nextDouble() * 10.5)
            : (110.0 + rng.nextDouble() * 240.0);
      }

      car.headingDeg = (car.headingDeg + car.turnDegPerSec * d) % 360;
      if (car.headingDeg < 0) car.headingDeg += 360;

      final rad = car.headingDeg * math.pi / 180;
      var next = _offset(car.point, car.speedMps * d, rad);

      final home = car.home;
      if (home != null && car.maxWanderM > 0) {
        if (!_enTierraCuba(next) || _haversineM(home, next) > car.maxWanderM) {
          final back = _bearingDeg(next, home);
          var delta = ((back - car.headingDeg + 540) % 360) - 180;
          car.headingDeg = (car.headingDeg + delta.clamp(-50, 50)) % 360;
          if (car.headingDeg < 0) car.headingDeg += 360;
          final radHome = car.headingDeg * math.pi / 180;
          final retry = _offset(car.point, car.speedMps * d, radHome);
          if (_enTierraCuba(retry) &&
              _haversineM(home, retry) <= car.maxWanderM) {
            car.point = retry;
          }
        } else {
          car.point = next;
        }
        continue;
      }

      if (anchor != null) {
        final dist = _haversineM(anchor, next);
        if (dist > maxR) {
          // Gira hacia el ancla y sigue avanzando de frente.
          final toAnchor = _bearingDeg(next, anchor);
          var delta = ((toAnchor - car.headingDeg + 540) % 360) - 180;
          car.headingDeg = (car.headingDeg + delta.clamp(-40, 40)) % 360;
          if (car.headingDeg < 0) car.headingDeg += 360;
          final rad2 = car.headingDeg * math.pi / 180;
          next = _offset(car.point, car.speedMps * d, rad2);
        }
      }
      car.point = next;
    }
  }

  /// Máscara de tierra (interior de la costa). La bahía de Cienfuegos queda fuera.
  static bool _enTierraCuba(LatLng p) {
    if (_enCaja(p, 22.02, 22.16, -80.55, -80.38)) return false;
    return _enAnillo(p, _cubaInterior) || _enAnillo(p, _islaJuventud);
  }

  static bool _enCaja(
    LatLng p,
    double latMin,
    double latMax,
    double lngMin,
    double lngMax,
  ) {
    return p.latitude >= latMin &&
        p.latitude <= latMax &&
        p.longitude >= lngMin &&
        p.longitude <= lngMax;
  }

  static bool _enAnillo(LatLng p, List<LatLng> ring) {
    var inside = false;
    for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final yi = ring[i].latitude;
      final yj = ring[j].latitude;
      final xi = ring[i].longitude;
      final xj = ring[j].longitude;
      final dy = yj - yi;
      final intersect = ((yi > p.latitude) != (yj > p.latitude)) &&
          (p.longitude < (xj - xi) * (p.latitude - yi) / (dy == 0 ? 1e-15 : dy) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  /// Polígono erosionado: va por dentro de la costa, no incluye el mar.
  static const List<LatLng> _cubaInterior = [
    LatLng(22.28, -84.20),
    LatLng(22.55, -83.80),
    LatLng(22.82, -83.30),
    LatLng(22.96, -82.85),
    LatLng(23.08, -82.52),
    LatLng(23.08, -82.18),
    LatLng(23.00, -81.82),
    LatLng(22.92, -81.35),
    LatLng(22.88, -80.95),
    LatLng(22.74, -80.42),
    LatLng(22.54, -79.92),
    LatLng(22.40, -79.35),
    LatLng(22.20, -78.80),
    LatLng(21.96, -78.25),
    LatLng(21.70, -77.72),
    LatLng(21.42, -77.18),
    LatLng(21.15, -76.68),
    LatLng(20.96, -76.15),
    LatLng(20.80, -75.68),
    LatLng(20.52, -75.38),
    LatLng(20.26, -75.20),
    LatLng(20.08, -75.16),
    LatLng(20.04, -75.48),
    LatLng(20.10, -75.95),
    LatLng(20.22, -76.55),
    LatLng(20.20, -76.90),
    LatLng(20.45, -77.25),
    LatLng(20.80, -77.75),
    LatLng(21.15, -78.25),
    LatLng(21.50, -78.85),
    LatLng(21.78, -79.45),
    LatLng(21.95, -80.10),
    LatLng(22.08, -80.70),
    LatLng(22.08, -81.40),
    LatLng(22.05, -82.15),
    LatLng(22.15, -82.85),
    LatLng(22.22, -83.45),
    LatLng(22.28, -84.20),
  ];

  static const List<LatLng> _islaJuventud = [
    LatLng(21.94, -82.98),
    LatLng(21.78, -83.08),
    LatLng(21.60, -82.98),
    LatLng(21.56, -82.78),
    LatLng(21.68, -82.60),
    LatLng(21.86, -82.64),
    LatLng(21.96, -82.80),
    LatLng(21.94, -82.98),
  ];

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

  static LatLng _offset(LatLng c, double distM, double bearingRad) {
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
}
