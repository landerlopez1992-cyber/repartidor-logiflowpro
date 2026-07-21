import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_colors.dart';
import '../services/taxi_chofer_service.dart';

/// Navegación GPS del socio:
/// 1) Ubicación actual → punto A (recogida)
/// 2) Llegada → espera abordaje («Iniciar viaje»)
/// 3) Punto A → punto B (destino)
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

  LatLng get _puntoA => LatLng(_oferta.origenLat, _oferta.origenLng);
  LatLng get _puntoB => LatLng(_oferta.destinoLat, _oferta.destinoLng);

  bool get _faseEspera => _oferta.esperandoPasajero && !_oferta.haciaDestino;
  bool get _faseDestino => _oferta.haciaDestino;

  String get _tituloFase {
    if (_faseDestino) return 'Hacia el destino';
    if (_faseEspera) return 'Esperando al pasajero';
    return 'Hacia el pasajero';
  }

  String get _subtituloFase {
    if (_faseDestino) {
      return _oferta.destinoTexto.isEmpty
          ? 'Destino del viaje (punto B)'
          : _oferta.destinoTexto;
    }
    if (_faseEspera) {
      return 'Ya estás en el punto de recogida. Cuando el pasajero aborde, inicia el viaje.';
    }
    return _oferta.origenTexto.isEmpty
        ? 'Punto de recogida (punto A)'
        : _oferta.origenTexto;
  }

  String get _botonLabel {
    if (_faseDestino) return 'Completar viaje';
    if (_faseEspera) return 'Iniciar viaje';
    return 'Llegada';
  }

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

    if (_faseDestino) {
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

    if (_faseEspera) {
      final res = await TaxiChoferService.instance.iniciarViaje(_oferta.id);
      if (!mounted) return;
      setState(() => _busy = false);
      if (!res.ok || res.oferta == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.err ?? 'No se pudo iniciar el viaje'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      setState(() => _oferta = res.oferta!);
      _map.move(_puntoB, 14);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ruta al destino cargada. ¡Buen viaje!'),
          backgroundColor: Color(0xFF37474F),
        ),
      );
      return;
    }

    // Fase 1 → llegada al punto A
    final res = await TaxiChoferService.instance.lleguePasajero(_oferta.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!res.ok || res.oferta == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.err ?? 'No se pudo marcar la llegada'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() => _oferta = res.oferta!);
    _map.move(_puntoA, 16);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Aviso enviado al pasajero. Cuando aborde, pulsa «Iniciar viaje».',
        ),
        backgroundColor: Color(0xFF37474F),
      ),
    );
  }

  Future<void> _confirmarCancelarChofer() async {
    if (_busy) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 400),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        title: const Text(
          '¿Cancelar este viaje?',
          style: TextStyle(
            color: Color(0xFF2C2C2C),
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Text(
          'Si cancelas (por seguridad o algo sospechoso), pierdes esta carrera '
          'y el importe se devuelve completo al pasajero.\n\n'
          'No recibirás ganancia por este viaje.',
          style: TextStyle(color: Color(0xFF666666), height: 1.4, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Seguir el viaje',
              style: TextStyle(color: Color(0xFF666666)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Cancelar viaje',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    setState(() => _busy = true);
    final res = await TaxiChoferService.instance.cancelarViajeChofer(_oferta.id);
    if (!mounted) return;
    setState(() => _busy = false);

    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.err ?? 'No se pudo cancelar'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Viaje cancelado. El saldo se devolvió al pasajero.',
        ),
        backgroundColor: Color(0xFF37474F),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _pingTimer?.cancel();
    super.dispose();
  }

  List<Polyline> _polylines() {
    final out = <Polyline>[];
    if (_faseDestino) {
      // Trayectoria A → B
      out.add(
        Polyline(
          points: [_puntoA, _puntoB],
          color: const Color(0xFF1A73E8),
          strokeWidth: 5,
        ),
      );
      if (_yo != null) {
        out.add(
          Polyline(
            points: [_yo!, _puntoB],
            color: const Color(0xFF90CAF9),
            strokeWidth: 3,
          ),
        );
      }
      return out;
    }
    if (_faseEspera) {
      // En punto A: sin ruta de navegación
      return out;
    }
    // Fase 1: ubicación actual → punto A
    if (_yo != null) {
      out.add(
        Polyline(
          points: [_yo!, _puntoA],
          color: const Color(0xFF1A73E8),
          strokeWidth: 4,
        ),
      );
    }
    return out;
  }

  List<Marker> _markers() {
    final markers = <Marker>[
      Marker(
        point: _puntoA,
        width: 40,
        height: 40,
        child: const Icon(
          Icons.person_pin_circle,
          color: Color(0xFF4CAF50),
          size: 36,
        ),
      ),
    ];
    if (_faseDestino || _faseEspera) {
      markers.add(
        Marker(
          point: _puntoB,
          width: 40,
          height: 40,
          child: Icon(
            Icons.flag,
            color: _faseDestino
                ? const Color(0xFFDC2626)
                : const Color(0xFF9E9E9E),
            size: 34,
          ),
        ),
      );
    }
    if (_yo != null) {
      markers.add(
        Marker(
          point: _yo!,
          width: 36,
          height: 36,
          child: const Icon(Icons.local_taxi, color: Color(0xFF1565C0), size: 32),
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final polylines = _polylines();
    final markers = _markers();
    final center = _yo ?? (_faseDestino ? _puntoB : _puntoA);

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
                initialCenter: center,
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
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF666666),
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                    if (_faseEspera) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFFE082)),
                        ),
                        child: const Text(
                          'El pasajero ya recibió el aviso de que estás afuera.',
                          style: TextStyle(
                            color: Color(0xFF6D4C41),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
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
                        backgroundColor: _faseEspera
                            ? const Color(0xFFFF9800)
                            : const Color(0xFF37474F),
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
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _busy ? null : _confirmarCancelarChofer,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: const BorderSide(
                          color: Color(0xFFDC2626),
                          width: 1.2,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text(
                        'Cancelar viaje',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Si cancelas, pierdes la carrera y el pasajero recupera su saldo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF9E9E9E),
                        fontSize: 11,
                        height: 1.3,
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
