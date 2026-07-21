import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Taxis decorativos cerca de un punto (impresión de flota estilo Uber).
class TaxiNearbyFleetUtil {
  TaxiNearbyFleetUtil._();

  static List<LatLng> around({
    required LatLng center,
    int count = 6,
    int seed = 7,
  }) {
    final rng = math.Random(seed);
    final out = <LatLng>[];
    for (var i = 0; i < count; i++) {
      final bearing = rng.nextDouble() * 2 * math.pi;
      final distM = 90 + rng.nextDouble() * 380;
      out.add(_offset(center, distM, bearing));
    }
    return out;
  }

  static List<LatLng> nudge(List<LatLng> cars, {int seed = 0}) {
    final rng = math.Random(seed ^ cars.length);
    return cars.map((c) {
      final bearing = rng.nextDouble() * 2 * math.pi;
      final distM = 15 + rng.nextDouble() * 40;
      return _offset(c, distM, bearing);
    }).toList(growable: false);
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
