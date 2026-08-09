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
    this.focusActiveLeg = true,
    this.driverHeadingDeg = 0,
    this.streetLevelFollow = false,
    this.tenantId,
    this.totalTripEtaLabel,
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
  /// Si true y hay [activeTarget], la cámara encuadra solo el tramo activo
  /// (chofer → parada/destino actual), no todo A→Miami.
  final bool focusActiveLeg;
  /// Rumbo GPS del vehículo (grados; 0 = norte).
  final double driverHeadingDeg;
  /// Tras iniciar viaje: zoom calle (chofer + tramo cercano), no toda la ruta.
  final bool streetLevelFollow;
  final String? tenantId;
  /// Etiqueta de tiempo total del viaje (A→paradas→B), estilo Uber.
  final String? totalTripEtaLabel;

  @override
  State<TaxiChoferMapLibre> createState() => TaxiChoferMapLibreState();
}

class TaxiChoferMapLibreState extends State<TaxiChoferMapLibre> {
  WebViewController? _web;
  bool _webReady = false;
  bool _useFallback = false;
  bool _resolviendoOffline = true;
  Timer? _bootTimeout;
  final MapController _map = MapController();
  /// Si el chofer movió el mapa a mano, no re-encuadrar hasta «Mi ubicación».
  bool _seguimientoPausado = false;

  bool get _preferMapLibre {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  LatLng get _center => widget.driver ?? widget.pickup;

  /// Recentrar en chofer / tramo activo (botón «Mi ubicación»).
  void recenter() {
    _seguimientoPausado = false;
    if (_useFallback) {
      _fitFallback();
    } else if (_webReady) {
      unawaited(_syncWeb(fit: true));
    }
  }

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
      if (!_seguimientoPausado) _fitFallback();
    } else if (_webReady) {
      unawaited(_syncWeb(fit: !_seguimientoPausado));
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
      final pts = _fitPointsLngLat();
      await _runJs(
        'window.fitPoints && window.fitPoints(${jsonEncode(pts)},48,48,48,48,15.5);',
      );
    }
  }

  bool get _debeEnfocarTramoActivo =>
      widget.focusActiveLeg && widget.activeTarget != null;

  List<List<double>> _fitPointsLngLat() {
    if (_debeEnfocarTramoActivo) {
      final t = widget.activeTarget!;
      final pts = <List<double>>[
        if (widget.driver != null)
          [widget.driver!.longitude, widget.driver!.latitude],
        [t.longitude, t.latitude],
        for (final p in widget.routePoints) [p.longitude, p.latitude],
      ];
      if (pts.length >= 2) return pts;
    }
    final pts = <List<double>>[];
    if (widget.driver != null) {
      pts.add([widget.driver!.longitude, widget.driver!.latitude]);
    }
    pts.add([widget.pickup.longitude, widget.pickup.latitude]);
    if (widget.showDestination && widget.destination != null) {
      pts.add([
        widget.destination!.longitude,
        widget.destination!.latitude,
      ]);
    }
    for (final p in widget.routePoints) {
      pts.add([p.longitude, p.latitude]);
    }
    return pts;
  }

  List<LatLng> _fitPointsLatLng() {
    // Guía activa: encuadre calle (chofer + tramo próximo), no Miami entero.
    if (widget.streetLevelFollow && widget.driver != null) {
      final d = widget.driver!;
      final pts = <LatLng>[d];
      final route = widget.routePoints;
      if (route.length >= 2) {
        const distCalc = Distance();
        var acc = 0.0;
        for (var i = 0; i < route.length; i++) {
          pts.add(route[i]);
          if (i > 0) {
            acc += distCalc.as(LengthUnit.Meter, route[i - 1], route[i]);
            if (acc >= 1200) break;
          }
          if (pts.length >= 24) break;
        }
      } else if (widget.activeTarget != null) {
        pts.add(widget.activeTarget!);
      }
      if (pts.length >= 2) return pts;
    }
    if (_debeEnfocarTramoActivo) {
      final t = widget.activeTarget!;
      final pts = <LatLng>[
        if (widget.driver != null) widget.driver!,
        t,
        ...widget.routePoints,
      ];
      if (pts.length >= 2) return pts;
    }
    return <LatLng>[
      if (widget.driver != null) widget.driver!,
      widget.pickup,
      if (widget.showDestination && widget.destination != null)
        widget.destination!,
      ...widget.stops,
      ...widget.overviewPoints,
      if (widget.activeTarget != null) widget.activeTarget!,
      ...widget.routePoints,
    ];
  }

  void _fitFallback() {
    try {
      final pts = _fitPointsLatLng();
      if (pts.length < 2) {
        _map.move(
          pts.isEmpty ? widget.pickup : pts.first,
          widget.streetLevelFollow ? 16.5 : 14,
        );
        return;
      }
      final bounds = LatLngBounds.fromPoints(pts);
      _map.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: EdgeInsets.all(widget.streetLevelFollow ? 56 : 48),
          maxZoom: widget.streetLevelFollow ? 17.2 : (_debeEnfocarTramoActivo ? 16 : 15),
        ),
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
    // Overview completo (A→paradas→B) solo como guía tenue; el trazo azul
    // del tramo activo (p. ej. hacia la parada) es el que manda en cámara.
    if (widget.overviewPoints.length >= 2 &&
        !_debeEnfocarTramoActivo) {
      polylines.add(
        Polyline(
          points: widget.overviewPoints,
          color: const Color(0xFF607D8B).withValues(alpha: 0.85),
          strokeWidth: 4,
        ),
      );
    } else if (widget.overviewPoints.length >= 2) {
      polylines.add(
        Polyline(
          points: widget.overviewPoints,
          color: const Color(0xFF607D8B).withValues(alpha: 0.28),
          strokeWidth: 2.5,
        ),
      );
    }
    if (widget.routePoints.length >= 2) {
      polylines.add(
        Polyline(
          points: widget.routePoints,
          color: const Color(0xFF1A73E8),
          strokeWidth: 5.5,
        ),
      );
    }
    final eta = (widget.totalTripEtaLabel ?? '').trim();
    final markers = <Marker>[
      Marker(
        point: widget.pickup,
        width: eta.isNotEmpty ? 110 : 44,
        height: eta.isNotEmpty ? 56 : 44,
        child: _PinLabeled(
          letter: 'A',
          color: const Color(0xFF4CAF50),
          topLabel: eta.isNotEmpty ? eta : null,
        ),
      ),
      for (var i = 0; i < widget.stops.length && i < 2; i++)
        Marker(
          point: widget.stops[i],
          width: 44,
          height: 52,
          child: _PinLabeled(
            letter: widget.stops.length == 1 ? 'C' : 'C${i + 1}',
            color: const Color(0xFFDC2626),
            isFlag: true,
          ),
        ),
      if (widget.showDestination && widget.destination != null)
        Marker(
          point: widget.destination!,
          width: 44,
          height: 52,
          child: const _PinLabeled(
            letter: 'B',
            color: Color(0xFFDC2626),
            isFlag: true,
          ),
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
          width: 44,
          height: 44,
          child: TaxiUberMapCar(
            size: 44,
            headingDeg: widget.driverHeadingDeg,
          ),
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
        onPositionChanged: (camera, hasGesture) {
          if (hasGesture && !_seguimientoPausado) {
            _seguimientoPausado = true;
          }
        },
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

class _PinLabeled extends StatelessWidget {
  const _PinLabeled({
    required this.letter,
    required this.color,
    this.topLabel,
    this.isFlag = false,
  });

  final String letter;
  final Color color;
  final String? topLabel;
  final bool isFlag;

  @override
  Widget build(BuildContext context) {
    final pin = isFlag
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 18,
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(2),
                    topRight: Radius.circular(2),
                    bottomRight: Radius.circular(2),
                  ),
                ),
              ),
              Container(width: 2, height: 8, color: const Color(0xFF1A1A1A)),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFDDDDDD)),
                ),
                child: Text(
                  letter,
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ],
          )
        : Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              letter,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          );

    final label = (topLabel ?? '').trim();
    if (label.isEmpty) return pin;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF37474F),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 4),
        pin,
      ],
    );
  }
}
