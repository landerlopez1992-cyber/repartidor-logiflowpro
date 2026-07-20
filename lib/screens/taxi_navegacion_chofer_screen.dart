import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_colors.dart';
import '../services/taxi_chofer_service.dart';

/// Navegación GPS del socio: primero al pasajero, luego al destino final.
class TaxiNavegacionChoferScreen extends StatefulWidget {
  const TaxiNavegacionChoferScreen({super.key, required this.oferta});

  final TaxiOfertaChofer oferta;

  @override
  State<TaxiNavegacionChoferScreen> createState() =>
      _TaxiNavegacionChoferScreenState();
}

class _TaxiNavegacionChoferScreenState extends State<TaxiNavegacionChoferScreen> {
  late TaxiOfertaChofer _oferta;
  final MapController _map = MapController();
  LatLng? _yo;
  StreamSubscription<Position>? _posSub;
  Timer? _pingTimer;
  bool _busy = false;

  LatLng get _destinoActual {
    if (_oferta.haciaDestino) {
      return LatLng(_oferta.destinoLat, _oferta.destinoLng);
    }
    return LatLng(_oferta.origenLat, _oferta.origenLng);
  }

  String get _tituloFase =>
      _oferta.haciaDestino ? 'Hacia el destino final' : 'Hacia el pasajero';

  String get _subtituloFase => _oferta.haciaDestino
      ? (_oferta.destinoTexto.isEmpty ? 'Destino del viaje' : _oferta.destinoTexto)
      : (_oferta.origenTexto.isEmpty
          ? 'Punto de recogida'
          : _oferta.origenTexto);

  String get _botonLabel =>
      _oferta.haciaDestino ? 'Completar viaje' : 'Ya llegué al pasajero';

  @override
  void initState() {
    super.initState();
    _oferta = widget.oferta;
    _iniciarGps();
    _pingTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(_enviarUbicacion());
    });
  }

  Future<void> _iniciarGps() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever ||
          perm == LocationPermission.denied) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() => _yo = LatLng(pos.latitude, pos.longitude));
      _map.move(_yo!, 15);
      await _enviarUbicacion();

      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 25,
        ),
      ).listen((p) {
        if (!mounted) return;
        setState(() => _yo = LatLng(p.latitude, p.longitude));
      });
    } catch (_) {}
  }

  Future<void> _enviarUbicacion() async {
    final y = _yo;
    if (y == null) return;
    await TaxiChoferService.instance.actualizarUbicacion(
      solicitudId: _oferta.id,
      lat: y.latitude,
      lng: y.longitude,
    );
  }

  Future<void> _accionPrincipal() async {
    if (_busy) return;
    setState(() => _busy = true);
    if (_oferta.haciaDestino) {
      final res = await TaxiChoferService.instance.completar(_oferta.id);
      if (!mounted) return;
      setState(() => _busy = false);
      if (!res.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.err ?? 'No se pudo completar'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Viaje completado'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
      Navigator.of(context).pop();
      return;
    }

    final res = await TaxiChoferService.instance.lleguePasajero(_oferta.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok || res.oferta == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.err ?? 'No se pudo actualizar'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() => _oferta = res.oferta!);
    _map.move(_destinoActual, 15);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ahora navega al destino final del pasajero'),
        backgroundColor: Color(0xFF37474F),
      ),
    );
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _pingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dest = _destinoActual;
    final markers = <Marker>[
      Marker(
        point: dest,
        width: 40,
        height: 40,
        child: Icon(
          _oferta.haciaDestino ? Icons.flag : Icons.person_pin_circle,
          color: _oferta.haciaDestino
              ? const Color(0xFFDC2626)
              : const Color(0xFF4CAF50),
          size: 36,
        ),
      ),
      if (_yo != null)
        Marker(
          point: _yo!,
          width: 36,
          height: 36,
          child: const Icon(Icons.local_taxi, color: Color(0xFF1565C0), size: 32),
        ),
    ];

    final polylines = <Polyline>[];
    if (_yo != null) {
      polylines.add(
        Polyline(
          points: [_yo!, dest],
          color: const Color(0xFF1A73E8),
          strokeWidth: 4,
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF37474F),
        title: Text(_tituloFase),
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: _yo ?? dest,
                initialZoom: 14,
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.logiflow.repartidor',
                ),
                if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
                MarkerLayer(markers: markers),
              ],
            ),
          ),
          Material(
            color: Colors.white,
            elevation: 8,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _oferta.pasajeroNombre,
                      style: const TextStyle(
                        color: Color(0xFF2C2C2C),
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtituloFase,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF666666),
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Ganancia: \$${_oferta.gananciaUsd.toStringAsFixed(2)} · '
                      '${_oferta.distanciaKm.toStringAsFixed(1)} km',
                      style: const TextStyle(
                        color: Color(0xFF4CAF50),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _busy ? null : _accionPrincipal,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF37474F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _botonLabel,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
