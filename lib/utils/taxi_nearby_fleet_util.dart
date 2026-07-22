import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Taxi decorativo con rumbo y velocidad propios (avanza de frente, no de lado).
class TaxiFleetCar {
  TaxiFleetCar({
    required this.point,
    required this.headingDeg,
    required this.speedMps,
    required this.turnDegPerSec,
  });

  LatLng point;
  double headingDeg;
  double speedMps;
  double turnDegPerSec;
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
