import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_colors.dart';
import '../services/paises_service.dart';
import '../services/taxi_buscando_prefs.dart';
import '../services/taxi_buscando_sonido_service.dart';
import '../services/taxi_tarifas_chofer_service.dart';
import '../utils/pais_mapa_centro.dart';
import '../utils/taxi_nearby_fleet_util.dart';
import '../widgets/taxi_uber_map_car.dart';

/// Pantalla Taxis del socio: mapa del país de operación + modo «Buscando viajes».
class TaxiChoferMapaScreen extends StatefulWidget {
  const TaxiChoferMapaScreen({
    super.key,
    this.paisOperacion,
    this.embedded = false,
    this.onBuscandoChanged,
  });

  final String? paisOperacion;

  /// Si true, se embebe en el home (sin botón atrás / sin Scaffold propio).
  final bool embedded;

  final ValueChanged<bool>? onBuscandoChanged;

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
  Timer? _fleetTimer;
  List<LatLng> _nearbyCars = const [];
  int _fleetSeed = 0;

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

    // Persistencia: local + servidor. Solo se apaga si el usuario lo desactiva.
    final buscandoLocal = await TaxiBuscandoPrefs.esActivo();
    TaxiTarifaChofer? tarifa;
    try {
      tarifa = await TaxiTarifasChoferService.instance.get();
    } catch (_) {}

    final buscandoServidor = tarifa?.disponible == true;
    final buscando = buscandoLocal || buscandoServidor;

    if (buscando) {
      // Reafirmar en dispositivo y servidor tras reinicio.
      await TaxiBuscandoPrefs.setActivo(true);
      if (tarifa?.configurado == true && !buscandoServidor) {
        await TaxiTarifasChoferService.instance.setDisponible(true);
      }
    }

    final vista = PaisMapaCentro.forPais(pais);
    if (!mounted) return;
    setState(() {
      _pais = pais;
      _vista = vista;
      _buscando = buscando;
      _cargando = false;
      _nearbyCars = TaxiNearbyFleetUtil.around(
        center: vista.center,
        count: 6,
        seed: pais.hashCode,
      );
    });
    widget.onBuscandoChanged?.call(buscando);
    _startFleetAnim();
    if (_buscando) {
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

  void _startFleetAnim() {
    _fleetTimer?.cancel();
    _fleetTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _nearbyCars.isEmpty) return;
      _fleetSeed++;
      setState(() {
        _nearbyCars = TaxiNearbyFleetUtil.nudge(
          _nearbyCars,
          seed: _fleetSeed,
        );
      });
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
      final yo = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _yo = yo;
        _nearbyCars = TaxiNearbyFleetUtil.around(
          center: yo,
          count: 6,
          seed: (pos.latitude * 1000).round(),
        );
      });
      try {
        _map.move(yo, 14);
      } catch (_) {}
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
    // Sonido primero y await (no unawaited): garantiza init del player + asset.
    try {
      if (next) {
        await TaxiBuscandoSonidoService.alActivar();
      } else {
        await TaxiBuscandoSonidoService.alDesactivar();
      }
    } catch (e) {
      debugPrint('⚠️ Sonido buscando viajes: $e');
    }
    if (next) {
      // Guardar ya en local para que sobreviva reinicio aunque falle la red.
      await TaxiBuscandoPrefs.setActivo(true);
      final res = await TaxiTarifasChoferService.instance.setDisponible(true);
      if (!res.ok) {
        await TaxiBuscandoPrefs.setActivo(false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.err ?? 'Configura tu tarifa en Ajustes de taxis'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    } else {
      // Solo se desactiva cuando el socio lo apaga explícitamente.
      await TaxiBuscandoPrefs.setActivo(false);
      await TaxiTarifasChoferService.instance.setDisponible(false);
    }
    if (!mounted) return;
    setState(() => _buscando = next);
    widget.onBuscandoChanged?.call(next);
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
    _fleetTimer?.cancel();
    _radar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contenido = _cargando
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
                  minZoom: 3,
                  maxZoom: 16,
                  backgroundColor: const Color(0xFFE8EEF4),
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  // Mismo raster Voyager que el fallback de CubaLink taxi
                  // (sin {r}: evita warning retina / tiles distintos).
                  TileLayer(
                    urlTemplate:
                        'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                    subdomains: const ['a', 'b', 'c', 'd'],
                    userAgentPackageName: 'com.logiflow.repartidor',
                    maxZoom: 16,
                    maxNativeZoom: 16,
                    retinaMode: false,
                  ),
                  if (_nearbyCars.isNotEmpty)
                    MarkerLayer(
                      markers: [
                        for (final c in _nearbyCars)
                          Marker(
                            point: c,
                            width: 32,
                            height: 32,
                            child: const TaxiUberMapCar(),
                          ),
                      ],
                    ),
                  if (_yo != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _yo!,
                          width: 40,
                          height: 40,
                          child: const TaxiUberMapCar(size: 40),
                        ),
                      ],
                    ),
                ],
              ),
              // Gradiente superior suave (mapa claro)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Container(
                    height: 120,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.72),
                          Colors.white.withValues(alpha: 0.0),
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
                          AppColors.darkBg.withValues(alpha: 0.92),
                          AppColors.darkBg.withValues(alpha: 0.45),
                          AppColors.darkBg.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: !widget.embedded,
                child: Column(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        widget.embedded ? 16 : 8,
                        widget.embedded ? 8 : 4,
                        16,
                        0,
                      ),
                      child: Row(
                        children: [
                          if (!widget.embedded) ...[
                            Material(
                              color: Colors.white,
                              elevation: 4,
                              shadowColor: Colors.black38,
                              shape: const CircleBorder(),
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => Navigator.of(context).pop(),
                                child: const SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: Icon(
                                    Icons.arrow_back,
                                    color: Color(0xFF2C2C2C),
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.18),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  widget.embedded ? 'Viajes' : 'Taxis',
                                  style: const TextStyle(
                                    color: Color(0xFF2C2C2C),
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
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
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
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
                                ? 'Buscando viajes · activo'
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
                                ? 'Seguirás activo aunque cierres la app. '
                                    'Toca de nuevo para desactivar.'
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
          );

    if (widget.embedded) {
      return ColoredBox(
        color: AppColors.darkBg,
        child: contenido,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: contenido,
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
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Image.asset(
                      'assets/images/taxi-icon-3d-v3.png',
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.local_taxi,
                        color: Colors.white,
                        size: activo ? 34 : 30,
                      ),
                    ),
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

    // Ondas suaves
    for (var i = 0; i < 2; i++) {
      final phase = (progress + i / 2) % 1.0;
      final r = 34 + phase * (maxR - 34);
      final opacity = (1.0 - phase) * 0.35;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF4CAF50).withValues(alpha: opacity);
      canvas.drawCircle(center, r, paint);
    }

    // Raya que va y viene (ida y vuelta)
    final ping = progress <= 0.5 ? (progress * 2) : (2 - progress * 2);
    final y = size.height * (0.22 + ping * 0.56);
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF4CAF50).withValues(alpha: 0.85);
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF4CAF50).withValues(alpha: 0.22);

    final left = size.width * 0.18;
    final right = size.width * 0.82;
    canvas.drawLine(Offset(left, y), Offset(right, y), glowPaint);
    canvas.drawLine(Offset(left, y), Offset(right, y), linePaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.activo != activo;
}
