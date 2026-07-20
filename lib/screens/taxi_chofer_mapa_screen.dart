import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_colors.dart';
import '../services/paises_service.dart';
import '../services/taxi_buscando_prefs.dart';
import '../utils/pais_mapa_centro.dart';

/// Pantalla Taxis del socio: mapa del país de operación + modo «Buscando viajes».
class TaxiChoferMapaScreen extends StatefulWidget {
  const TaxiChoferMapaScreen({super.key, this.paisOperacion});

  final String? paisOperacion;

  @override
  State<TaxiChoferMapaScreen> createState() => _TaxiChoferMapaScreenState();
}

class _TaxiChoferMapaScreenState extends State<TaxiChoferMapaScreen>
    with SingleTickerProviderStateMixin {
  final MapController _map = MapController();
  late AnimationController _radar;
  String _pais = 'Cuba';
  PaisMapaCentro _vista = PaisMapaCentro.forPais('Cuba');
  LatLng? _yo;
  bool _buscando = false;
  bool _cargando = true;
  StreamSubscription<Position>? _posSub;

  @override
  void initState() {
    super.initState();
    _radar = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _iniciar();
  }

  Future<void> _iniciar() async {
    final pais = (widget.paisOperacion?.trim().isNotEmpty == true)
        ? widget.paisOperacion!.trim()
        : (await PaisesService.obtenerPaisOperacionActual()) ?? 'Cuba';
    final buscando = await TaxiBuscandoPrefs.esActivo();
    final vista = PaisMapaCentro.forPais(pais);
    if (!mounted) return;
    setState(() {
      _pais = pais;
      _vista = vista;
      _buscando = buscando;
      _cargando = false;
    });
    if (buscando) {
      _radar.repeat();
      unawaited(_iniciarGps());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _map.move(vista.center, vista.zoom);
      } catch (_) {}
    });
  }

  Future<void> _iniciarGps() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() => _yo = LatLng(pos.latitude, pos.longitude));
      _posSub?.cancel();
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 40,
        ),
      ).listen((p) {
        if (!mounted) return;
        setState(() => _yo = LatLng(p.latitude, p.longitude));
      });
    } catch (_) {}
  }

  Future<void> _toggleBuscando() async {
    final next = !_buscando;
    await TaxiBuscandoPrefs.setActivo(next);
    if (!mounted) return;
    setState(() => _buscando = next);
    if (next) {
      _radar.repeat();
      await _iniciarGps();
    } else {
      _radar.stop();
      _radar.reset();
      await _posSub?.cancel();
      _posSub = null;
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _radar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: _cargando
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF9800)),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _vista.center,
                    initialZoom: _vista.zoom,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'com.logiflow.repartidor',
                    ),
                    if (_yo != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: _yo!,
                            width: 44,
                            height: 44,
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF1565C0),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2.5,
                                ),
                              ),
                              child: const Icon(
                                Icons.local_taxi,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                // Gradiente superior
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 140,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.darkBg.withValues(alpha: 0.92),
                            AppColors.darkBg.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Gradiente inferior
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 280,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            AppColors.darkBg.withValues(alpha: 0.96),
                            AppColors.darkBg.withValues(alpha: 0.55),
                            AppColors.darkBg.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(
                                Icons.arrow_back,
                                color: Color(0xFFECEFF1),
                              ),
                              tooltip: 'Volver',
                            ),
                            const SizedBox(width: 4),
                            const Expanded(
                              child: Text(
                                'Taxis',
                                style: TextStyle(
                                  color: Color(0xFFECEFF1),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.darkElevated,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.public,
                                    size: 14,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    _pais,
                                    style: const TextStyle(
                                      color: Color(0xFFECEFF1),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                        child: Column(
                          children: [
                            _BuscandoRadarButton(
                              activo: _buscando,
                              animation: _radar,
                              onTap: _toggleBuscando,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _buscando
                                  ? 'Buscando viajes'
                                  : 'Toca para buscar viajes',
                              style: TextStyle(
                                color: _buscando
                                    ? const Color(0xFF4CAF50)
                                    : const Color(0xFFECEFF1),
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _buscando
                                  ? 'En espera de un viaje en $_pais'
                                  : 'Activa el modo para recibir ofertas de taxi',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF9CA3AF),
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _BuscandoRadarButton extends StatelessWidget {
  const _BuscandoRadarButton({
    required this.activo,
    required this.animation,
    required this.onTap,
  });

  final bool activo;
  final Animation<double> animation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 132,
        height: 132,
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final t = activo ? animation.value : 0.0;
            return CustomPaint(
              painter: _RadarPainter(progress: t, activo: activo),
              child: Center(
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: activo
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFF37474F),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 1.5,
                    ),
                    boxShadow: activo
                        ? [
                            BoxShadow(
                              color: const Color(0xFF4CAF50)
                                  .withValues(alpha: 0.28),
                              blurRadius: 8,
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    Icons.local_taxi,
                    color: Colors.white,
                    size: activo ? 34 : 30,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.progress, required this.activo});

  final double progress;
  final bool activo;

  @override
  void paint(Canvas canvas, Size size) {
    if (!activo) return;
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    for (var i = 0; i < 3; i++) {
      final phase = (progress + i / 3) % 1.0;
      final r = 28 + phase * (maxR - 28);
      final opacity = (1.0 - phase) * 0.45;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF4CAF50).withValues(alpha: opacity);
      canvas.drawCircle(center, r, paint);
    }

    // Arco de barrido suave
    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = const Color(0xFF4CAF50).withValues(alpha: 0.55);
    final rect = Rect.fromCircle(center: center, radius: maxR * 0.92);
    canvas.drawArc(
      rect,
      -math.pi / 2 + progress * math.pi * 2,
      math.pi / 5,
      false,
      sweep,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.activo != activo;
}
