import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'repartidor_map_tile_layer.dart';
import 'taxi_uber_map_car.dart';

/// Mapa de navegación taxi: MapLibre online, o MBTiles offline del tenant.
class TaxiChoferMapLibre extends StatefulWidget {
  const TaxiChoferMapLibre({
    super.key,
    required this.driver,
    required this.pickup,
    this.destination,
    this.routePoints = const [],
    this.showDestination = false,
    this.stops = const [],
    this.overviewPoints = const [],
    this.activeTarget,
    this.tenantId,
  });

  final LatLng? driver;
  final LatLng pickup;
  final LatLng? destination;
  final List<LatLng> routePoints;
  final bool showDestination;
  /// Paradas intermedias / puntos extra del itinerario.
  final List<LatLng> stops;
  /// Vista general de toda la secuencia; la ruta azul sigue siendo el tramo activo.
  final List<LatLng> overviewPoints;
  /// Punto al que navega ahora (naranja).
  final LatLng? activeTarget;
  final String? tenantId;

  @override
  State<TaxiChoferMapLibre> createState() => _TaxiChoferMapLibreState();
}

class _TaxiChoferMapLibreState extends State<TaxiChoferMapLibre> {
  WebViewController? _web;
  bool _webReady = false;
  bool _useFallback = false;
  bool _resolviendoOffline = true;
  Timer? _bootTimeout;
  final MapController _map = MapController();

  bool get _preferMapLibre {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  LatLng get _center => widget.driver ?? widget.pickup;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    // FlutterMap + Carto/MBTiles (offline-first). Evita WebView en blanco sin red.
    if (!mounted) return;
    setState(() {
      _useFallback = true;
      _resolviendoOffline = false;
    });
  }

  @override
  void dispose() {
    _bootTimeout?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TaxiChoferMapLibre oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_useFallback) {
      _fitFallback();
    } else if (_webReady) {
      unawaited(_syncWeb());
    }
  }

  Future<void> _initWeb() async {
    if (!_preferMapLibre) {
      if (mounted) setState(() => _useFallback = true);
      return;
    }
    try {
      final ctrl = WebViewController();
      await ctrl.setJavaScriptMode(JavaScriptMode.unrestricted);
      try {
        await ctrl.setBackgroundColor(const Color(0xFFE8EEF4));
      } catch (_) {}
      await ctrl.addJavaScriptChannel(
        'TaxiNavMap',
        onMessageReceived: (msg) {
          if (msg.message == 'ready' && mounted) {
            _bootTimeout?.cancel();
            setState(() => _webReady = true);
            unawaited(_syncWeb(fit: true));
          }
        },
      );
      final c = _center;
      await ctrl.loadHtmlString(
        _html(lat: c.latitude, lng: c.longitude, zoom: 14.5),
      );
      if (!mounted) return;
      setState(() => _web = ctrl);
    } catch (_) {
      if (mounted) setState(() => _useFallback = true);
    }
  }

  Future<void> _runJs(String js) async {
    final w = _web;
    if (w == null || !_webReady) return;
    try {
      await w.runJavaScript(js);
    } catch (_) {}
  }

  Future<void> _syncWeb({bool fit = false}) async {
    final route = widget.routePoints.length >= 2
        ? widget.routePoints
            .map((p) => [p.longitude, p.latitude])
            .toList(growable: false)
        : <List<double>>[];
    await _runJs('window.setRoute && window.setRoute(${jsonEncode(route)});');

    final d = widget.driver;
    if (d != null) {
      await _runJs(
        'window.setDriver && window.setDriver(${d.latitude},${d.longitude},0);',
      );
    }

    await _runJs(
      'window.setPickup && window.setPickup(${widget.pickup.latitude},${widget.pickup.longitude});',
    );

    if (widget.showDestination && widget.destination != null) {
      final b = widget.destination!;
      await _runJs(
        'window.setDest && window.setDest(${b.latitude},${b.longitude});',
      );
    } else {
      await _runJs('window.setDest && window.setDest(null,null);');
    }

    if (fit) {
      final pts = <List<double>>[];
      if (d != null) pts.add([d.longitude, d.latitude]);
      pts.add([widget.pickup.longitude, widget.pickup.latitude]);
      if (widget.showDestination && widget.destination != null) {
        pts.add([widget.destination!.longitude, widget.destination!.latitude]);
      }
      for (final p in widget.routePoints) {
        pts.add([p.longitude, p.latitude]);
      }
      await _runJs(
        'window.fitPoints && window.fitPoints(${jsonEncode(pts)},48,48,48,48,15.5);',
      );
    }
  }

  void _fitFallback() {
    try {
      final pts = <LatLng>[
        if (widget.driver != null) widget.driver!,
        widget.pickup,
        if (widget.showDestination && widget.destination != null)
          widget.destination!,
        ...widget.stops,
        ...widget.overviewPoints,
        if (widget.activeTarget != null) widget.activeTarget!,
        ...widget.routePoints,
      ];
      if (pts.length < 2) {
        _map.move(pts.isEmpty ? widget.pickup : pts.first, 14);
        return;
      }
      final bounds = LatLngBounds.fromPoints(pts);
      _map.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(48)),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_resolviendoOffline) {
      return const ColoredBox(
        color: Color(0xFFE8EEF4),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFFF9800)),
        ),
      );
    }
    if (_useFallback || (!_preferMapLibre && _web == null)) {
      return _buildFallback();
    }
    final w = _web;
    if (w == null) {
      return const ColoredBox(
        color: Color(0xFFE8EEF4),
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFFF9800)),
        ),
      );
    }
    return WebViewWidget(controller: w);
  }

  Widget _buildFallback() {
    final polylines = <Polyline>[];
    if (widget.overviewPoints.length >= 2) {
      polylines.add(
        Polyline(
          points: widget.overviewPoints,
          color: const Color(0xFF37474F).withValues(alpha: 0.7),
          strokeWidth: 3,
        ),
      );
    }
    if (widget.routePoints.length >= 2) {
      polylines.add(
        Polyline(
          points: widget.routePoints,
          color: const Color(0xFF1A73E8),
          strokeWidth: 5,
        ),
      );
    }
    final markers = <Marker>[
      Marker(
        point: widget.pickup,
        width: 40,
        height: 40,
        child: const Icon(
          Icons.person_pin_circle,
          color: Color(0xFF4CAF50),
          size: 36,
        ),
      ),
      for (var i = 0; i < widget.stops.length; i++)
        Marker(
          point: widget.stops[i],
          width: 34,
          height: 34,
          child: const Icon(
            Icons.add_location_alt,
            color: Color(0xFFFF9800),
            size: 30,
          ),
        ),
      if (widget.showDestination && widget.destination != null)
        Marker(
          point: widget.destination!,
          width: 40,
          height: 40,
          child: const Icon(Icons.flag, color: Color(0xFFDC2626), size: 34),
        ),
      if (widget.activeTarget != null)
        Marker(
          point: widget.activeTarget!,
          width: 44,
          height: 44,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFFF9800), width: 3),
              color: const Color(0xFFFF9800).withValues(alpha: 0.15),
            ),
            child: const Icon(
              Icons.navigation,
              color: Color(0xFFFF9800),
              size: 22,
            ),
          ),
        ),
      if (widget.driver != null)
        Marker(
          point: widget.driver!,
          width: 40,
          height: 40,
          child: const TaxiUberMapCar(size: 40),
        ),
    ];
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: _center,
        initialZoom: 14,
        minZoom: 3,
        maxZoom: 18,
        backgroundColor: const Color(0xFFE8EEF4),
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onMapReady: _fitFallback,
      ),
      children: [
        RepartidorMapTileLayer(
          preferOnline: true,
          maxZoom: 18,
          tenantId: widget.tenantId,
        ),
        if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
        MarkerLayer(markers: markers),
      ],
    );
  }
  String _html({
    required double lat,
    required double lng,
    required double zoom,
  }) {
    return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"/>
<link href="https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.css" rel="stylesheet"/>
<script src="https://unpkg.com/maplibre-gl@4.7.1/dist/maplibre-gl.js"></script>
<style>
  html,body,#map{margin:0;padding:0;height:100%;width:100%;background:#e8eef4;}
  .car-mark{width:34px;height:34px;display:flex;align-items:center;justify-content:center;}
  .car-svg{width:28px;height:28px;filter:drop-shadow(0 2px 3px rgba(0,0,0,.35));}
  .pin-a{width:18px;height:18px;border-radius:50%;background:#4CAF50;border:2.5px solid #fff;box-shadow:0 1px 4px rgba(0,0,0,.35);}
  .pin-b{width:0;height:0;border-left:8px solid transparent;border-right:8px solid transparent;border-top:16px solid #DC2626;filter:drop-shadow(0 1px 3px rgba(0,0,0,.35));}
</style>
</head>
<body>
<div id="map"></div>
<script>
const CAR_SVG = '<svg class="car-svg" viewBox="0 0 32 32" xmlns="http://www.w3.org/2000/svg">'
  + '<rect x="9.5" y="4.5" width="13" height="23" rx="3.5" fill="#F5F5F5" stroke="#2C2C2C" stroke-width="1.1"/>'
  + '<rect x="11.5" y="7" width="9" height="4.5" rx="1.2" fill="#9E9E9E"/>'
  + '<rect x="11.5" y="20.5" width="9" height="3.8" rx="1.2" fill="#9E9E9E"/>'
  + '<rect x="11.75" y="12.5" width="8.5" height="7" rx="1.5" fill="#E8E8E8"/>'
  + '<circle cx="12.8" cy="5.8" r="1.3" fill="#FFF59D"/>'
  + '<circle cx="19.2" cy="5.8" r="1.3" fill="#FFF59D"/>'
  + '</svg>';

const map = new maplibregl.Map({
  container: 'map',
  style: 'https://tiles.openfreemap.org/styles/liberty',
  center: [$lng, $lat],
  zoom: $zoom,
  attributionControl: false,
  interactive: true,
  maxZoom: 16,
  minZoom: 3,
  dragRotate: false,
  pitchWithRotate: false
});

let driverMarker = null;
let pickupMarker = null;
let destMarker = null;

function ensureRoute() {
  if (map.getSource('route')) return;
  map.addSource('route', {
    type: 'geojson',
    data: { type: 'Feature', geometry: { type: 'LineString', coordinates: [] } }
  });
  map.addLayer({
    id: 'route-glow', type: 'line', source: 'route',
    layout: { 'line-cap': 'round', 'line-join': 'round' },
    paint: { 'line-color': '#1565C0', 'line-width': 10, 'line-opacity': 0.22 }
  });
  map.addLayer({
    id: 'route-line', type: 'line', source: 'route',
    layout: { 'line-cap': 'round', 'line-join': 'round' },
    paint: { 'line-color': '#1A73E8', 'line-width': 5, 'line-opacity': 0.95 }
  });
}

window.setRoute = function(coords) {
  ensureRoute();
  map.getSource('route').setData({
    type: 'Feature',
    geometry: { type: 'LineString', coordinates: coords || [] }
  });
};

window.setDriver = function(lat, lng, bearing) {
  if (lat == null || lng == null) {
    if (driverMarker) { driverMarker.remove(); driverMarker = null; }
    return;
  }
  if (!driverMarker) {
    const el = document.createElement('div');
    el.className = 'car-mark';
    el.innerHTML = CAR_SVG;
    driverMarker = new maplibregl.Marker({
      element: el, rotationAlignment: 'map', pitchAlignment: 'map'
    }).setLngLat([lng, lat]).addTo(map);
  } else {
    driverMarker.setLngLat([lng, lat]);
  }
  try { driverMarker.setRotation(bearing || 0); } catch (e) {}
};

window.setPickup = function(lat, lng) {
  if (lat == null || lng == null) return;
  if (!pickupMarker) {
    const el = document.createElement('div');
    el.className = 'pin-a';
    pickupMarker = new maplibregl.Marker({ element: el, anchor: 'center' })
      .setLngLat([lng, lat]).addTo(map);
  } else {
    pickupMarker.setLngLat([lng, lat]);
  }
};

window.setDest = function(lat, lng) {
  if (lat == null || lng == null) {
    if (destMarker) { destMarker.remove(); destMarker = null; }
    return;
  }
  if (!destMarker) {
    const el = document.createElement('div');
    el.className = 'pin-b';
    destMarker = new maplibregl.Marker({ element: el, anchor: 'top' })
      .setLngLat([lng, lat]).addTo(map);
  } else {
    destMarker.setLngLat([lng, lat]);
  }
};

window.fitPoints = function(pts, top, right, bottom, left, maxZ) {
  if (!pts || !pts.length) return;
  if (pts.length === 1) {
    map.easeTo({ center: pts[0], zoom: Math.min(maxZ || 14.5, 15), duration: 400 });
    return;
  }
  const b = new maplibregl.LngLatBounds(pts[0], pts[0]);
  pts.forEach(function(p) { b.extend(p); });
  map.fitBounds(b, {
    padding: { top: top||48, right: right||48, bottom: bottom||48, left: left||48 },
    maxZoom: maxZ || 15.5,
    duration: 450
  });
};

map.on('load', function() {
  ensureRoute();
  try { TaxiNavMap.postMessage('ready'); } catch (e) {}
});
</script>
</body>
</html>
''';
  }

}
