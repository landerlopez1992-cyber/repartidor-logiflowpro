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
import '../services/taxi_ubicacion_matching_service.dart';
import '../services/tenant_mapa_offline_service.dart';
import '../utils/pais_mapa_centro.dart';
import '../utils/repartidor_connectivity.dart';
import '../utils/taxi_nearby_fleet_util.dart';
import '../utils/taxi_road_fleet_util.dart';
import '../widgets/repartidor_map_tile_layer.dart';
import '../widgets/taxi_reservas_chofer_panel.dart';
import '../widgets/taxi_uber_map_car.dart';
import '../widgets/volonex_dialog.dart';

/// Pantalla Taxis del socio: mapa del país de operación + modo «Buscando viajes».
class TaxiChoferMapaScreen extends StatefulWidget {
  const TaxiChoferMapaScreen({
    super.key,
    this.paisOperacion,
    this.embedded = false,
    this.onBuscandoChanged,
    this.mapVisible = true,
  });

  final String? paisOperacion;

  /// Si true, se embebe en el home (sin botón atrás / sin Scaffold propio).
  final bool embedded;

  final ValueChanged<bool>? onBuscandoChanged;

  /// Visible en IndexedStack (pestaña Viajes). Al volver a true, Cubalink23
  /// recentra la zona Habana con taxis caminando.
  final bool mapVisible;

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
  bool _toggleBusy = false;
  bool _esCubalink23 = false;
  StreamSubscription<Position>? _posSub;
  Timer? _fleetTimer;
  Timer? _pubGpsTimer;
  List<TaxiFleetCar> _nearbyCars = const [];
  int _fleetSeed = 0;
  DateTime? _fleetLastTick;

  @override
  void initState() {
    super.initState();
    _radar = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _iniciar();
  }

  @override
  void didUpdateWidget(covariant TaxiChoferMapaScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Cada vez que se abre la pestaña Viajes (Cubalink23): misma zona + taxis.
    if (!oldWidget.mapVisible &&
        widget.mapVisible &&
        _esCubalink23 &&
        !_buscando &&
        !_cargando) {
      unawaited(_aplicarVistaCubalink23Habana(recentrarMapa: true));
    }
  }

  /// Cubalink23: mapa Habana + taxis del mismo tamaño circulando por calles.
  Future<void> _aplicarVistaCubalink23Habana({required bool recentrarMapa}) async {
    final vista = PaisMapaCentro.cubalink23HabanaViajes;
    final routes = await TaxiRoadFleetUtil.loadHabanaRoadRoutes();
    if (!mounted) return;
    final cars = TaxiRoadFleetUtil.spawnOnRoutes(
      routes: routes,
      count: 8,
      seed: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
    setState(() {
      _vista = vista;
      _yo = vista.center;
      _nearbyCars = cars;
    });
    if (recentrarMapa) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _map.move(vista.center, vista.zoom);
        } catch (_) {}
      });
    }
  }

  Future<void> _iniciar() async {
    final pais = (widget.paisOperacion?.trim().isNotEmpty == true)
        ? widget.paisOperacion!.trim()
        : (await PaisesService.obtenerPaisOperacionActual()) ?? 'Cuba';

    final tenantId = await TenantMapaOfflineService.instance.tenantIdChofer();
    final esCubalink = PaisMapaCentro.esTenantCubalink23(tenantId);

    // Persistencia: local + servidor. Solo se apaga si el usuario lo desactiva.
    final buscandoLocal = await TaxiBuscandoPrefs.esActivo();
    TaxiTarifaChofer? tarifa;
    try {
      // Caché primero (nunca cuelga). Red con timeout dentro de get().
      tarifa = await TaxiTarifasChoferService.instance.get();
    } catch (_) {}

    final buscandoServidor = tarifa?.disponible == true;
    final buscando = buscandoLocal || buscandoServidor;

    if (buscando) {
      await TaxiBuscandoPrefs.setActivo(true);
      if (tarifa?.configurado == true && !buscandoServidor) {
        unawaited(TaxiTarifasChoferService.instance.setDisponible(true));
      }
    }

    // Cubalink23 (sin buscar): Habana + flota por calles reales.
    // Otros tenants: vista país como hasta ahora.
    final vista = esCubalink && !buscando
        ? PaisMapaCentro.cubalink23HabanaViajes
        : PaisMapaCentro.forPais(pais);

    List<TaxiFleetCar> fleet;
    if (esCubalink && !buscando) {
      final routes = await TaxiRoadFleetUtil.loadHabanaRoadRoutes();
      fleet = TaxiRoadFleetUtil.spawnOnRoutes(
        routes: routes,
        count: 8,
        seed: pais.hashCode ^ 23,
      );
    } else {
      fleet = TaxiNearbyFleetUtil.around(
        center: vista.center,
        count: 10,
        seed: pais.hashCode,
        minDistM: 8000,
        maxDistM: 65000,
      );
    }

    if (!mounted) return;
    setState(() {
      _pais = pais;
      _esCubalink23 = esCubalink;
      _vista = vista;
      _yo = vista.center;
      _buscando = buscando;
      _cargando = false;
      _nearbyCars = fleet;
    });
    widget.onBuscandoChanged?.call(buscando);
    _startFleetAnim();
    if (_buscando) {
      _radar.repeat();
      unawaited(_iniciarGpsMatching());
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
    _fleetLastTick = DateTime.now();
    // ~20 fps: avance continuo (estilo Uber), no saltos cada segundo.
    _fleetTimer = Timer.periodic(const Duration(milliseconds: 48), (_) {
      if (!mounted || _nearbyCars.isEmpty) return;
      final now = DateTime.now();
      final last = _fleetLastTick ?? now;
      _fleetLastTick = now;
      var dt = now.difference(last).inMilliseconds / 1000.0;
      if (dt <= 0 || dt > 0.25) dt = 0.048;
      _fleetSeed++;
      // Cubalink23: siempre por calles (idle Habana o GPS al buscar).
      final onRoads = _esCubalink23 &&
          _nearbyCars.isNotEmpty &&
          _nearbyCars.every((c) => c.onRoad);
      if (onRoads) {
        TaxiRoadFleetUtil.tickOnRoads(_nearbyCars, dt: dt);
      } else {
        final anchor = _yo ?? _vista.center;
        final maxR = _buscando ? 5200.0 : 70000.0;
        TaxiNearbyFleetUtil.tick(
          _nearbyCars,
          dt: dt,
          anchor: anchor,
          maxRadiusM: maxR,
          seed: _fleetSeed,
        );
      }
      setState(() {});
    });
  }

  void _pararPublicacionGps() {
    _pubGpsTimer?.cancel();
    _pubGpsTimer = null;
  }

  void _iniciarPublicacionGpsPeriodica() {
    _pararPublicacionGps();
    // Matching usa GPS ≤20 min; refresco cada 45s.
    _pubGpsTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(_publicarGpsMatchingSilencioso());
    });
  }

  Future<void> _publicarGpsMatchingSilencioso() async {
    try {
      final pos = await TaxiUbicacionMatchingService.instance.leerPosicion();
      if (pos == null) return;
      await TaxiUbicacionMatchingService.instance.publicarPosicion(pos);
      if (!mounted || !_buscando) return;
      setState(() => _yo = LatLng(pos.latitude, pos.longitude));
    } catch (_) {}
  }

  /// GPS real → BD (matching). El pin del mapa sigue tu ubicación al buscar.
  Future<({bool ok, String? err, String? accionAjustes})> _iniciarGpsMatching()
      async {
    try {
      final pub = await TaxiUbicacionMatchingService.instance.publicarAhora();
      if (!pub.ok) {
        return (
          ok: false,
          err: pub.err,
          accionAjustes: pub.accionAjustes,
        );
      }
      final pos = pub.pos!;
      if (!mounted) return (ok: true, err: null, accionAjustes: null);
      final yo = LatLng(pos.latitude, pos.longitude);

      List<TaxiFleetCar> fleet;
      if (_esCubalink23) {
        // Mismo zoom calle + taxis por rutas reales alrededor del GPS.
        final routes = await TaxiRoadFleetUtil.loadRoadRoutesAround(yo);
        fleet = TaxiRoadFleetUtil.spawnOnRoutes(
          routes: routes,
          count: 8,
          seed: (pos.latitude * 1000).round() ^ (pos.longitude * 100).round(),
        );
      } else {
        fleet = TaxiNearbyFleetUtil.around(
          center: yo,
          count: 9,
          seed: (pos.latitude * 1000).round() ^ (pos.longitude * 100).round(),
          minDistM: 350,
          maxDistM: 4800,
        );
      }

      if (!mounted) return (ok: true, err: null, accionAjustes: null);
      final zoom = _esCubalink23
          ? PaisMapaCentro.cubalink23StreetZoom
          : 14.0;
      setState(() {
        _yo = yo;
        _vista = PaisMapaCentro(center: yo, zoom: zoom);
        _nearbyCars = fleet;
      });
      try {
        _map.move(yo, zoom);
      } catch (_) {}
      _iniciarPublicacionGpsPeriodica();
      // GPS ya en BD: si hay pasajeros buscando, avisar ahora (no esperar
      // a que el pasajero cancele y reintente).
      if (_buscando) {
        unawaited(
          TaxiTarifasChoferService.instance.avisarSolicitudesPendientes(),
        );
      }
      _posSub?.cancel();
      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 40,
        ),
      ).listen((p) {
        if (!mounted) return;
        final ll = LatLng(p.latitude, p.longitude);
        setState(() => _yo = ll);
        if (_buscando) {
          unawaited(
            TaxiUbicacionMatchingService.instance.publicarPosicion(p),
          );
          // Cubalink23: mantener zoom calle centrado en el GPS del chofer.
          if (_esCubalink23) {
            try {
              _map.move(ll, PaisMapaCentro.cubalink23StreetZoom);
            } catch (_) {}
          }
        }
      });
      return (ok: true, err: null, accionAjustes: null);
    } catch (_) {
      return (
        ok: false,
        err: 'No se pudo activar la ubicación.',
        accionAjustes: 'app_settings',
      );
    }
  }

  Future<void> _mostrarDialogoUbicacionRequerida({
    required String mensaje,
    String? accionAjustes,
  }) async {
    if (!mounted) return;
    final esPermiso = accionAjustes == 'app_settings';
    final esGps = accionAjustes == 'location_service';
    final mostrarBoton = accionAjustes != null && accionAjustes.isNotEmpty;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => VolonexDialog(
        title: 'Ubicación necesaria',
        leading: const Icon(
          Icons.location_off_outlined,
          color: Color(0xFFECEFF1),
          size: 22,
        ),
        maxWidth: 400,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cerrar',
              style: TextStyle(color: AppColors.darkTextMuted),
            ),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              mensaje,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.darkText,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            if (mostrarBoton) ...[
              const SizedBox(height: 18),
              Center(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    final ok =
                        await TaxiUbicacionMatchingService.abrirAjustesUbicacion(
                      accionAjustes,
                    );
                    if (!mounted) return;
                    if (!ok) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'No se pudieron abrir los ajustes. Ábrelos manualmente en el teléfono.',
                          ),
                          backgroundColor: AppColors.error,
                        ),
                      );
                    }
                  },
                  icon: Icon(
                    esGps ? Icons.gps_fixed : Icons.settings,
                    size: 18,
                  ),
                  label: Text(
                    esPermiso
                        ? 'Abrir permisos de la app'
                        : esGps
                            ? 'Abrir ajustes de ubicación'
                            : 'Abrir ajustes',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.botonPrincipal,
                    foregroundColor: AppColors.onAccentButton,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'En iPhone: Ajustes → Privacidad → Ubicación → esta app.\n'
                'En Android: Ajustes → Ubicación / Permisos de la app.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.darkTextMuted,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _cerrarModalCargaBuscando() async {
    if (!mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    if (nav.canPop()) {
      nav.pop();
    }
  }

  Future<void> _toggleBuscando() async {
    if (_toggleBusy || _cargando) return;
    _toggleBusy = true;

    final next = !_buscando;
    final activando = next;

    if (!mounted) {
      _toggleBusy = false;
      return;
    }

    // ——— DESACTIVAR: caché + UI al instante (evita ANR sin internet) ———
    if (!activando) {
      try {
        await TaxiBuscandoPrefs.setActivo(false);
        await TaxiBuscandoPrefs.marcarPendienteSyncDisponible(false);
      } catch (_) {}
      if (mounted) {
        setState(() => _buscando = false);
      }
      widget.onBuscandoChanged?.call(false);
      _radar.stop();
      _radar.reset();
      _pararPublicacionGps();
      await _posSub?.cancel();
      _posSub = null;
      if (_esCubalink23) {
        unawaited(_aplicarVistaCubalink23Habana(recentrarMapa: true));
      }

      try {
        try {
          await TaxiBuscandoSonidoService.alDesactivar();
        } catch (e) {
          debugPrint('⚠️ Sonido desactivar: $e');
        }

        final sinRed = RepartidorConnectivity.online.value == false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                sinRed
                    ? 'Viajes desactivados sin internet. Se actualizará al volver la red.'
                    : 'Viajes desactivados.',
              ),
              backgroundColor: AppColors.header,
              duration: const Duration(seconds: 3),
            ),
          );
        }

        // Nunca await en el hilo del toque: sin red el RPC colgaba → ANR.
        // Cola en prefs; SyncService / reconnect empuja a BD.
        if (!sinRed) {
          unawaited(
            TaxiTarifasChoferService.instance.setDisponible(false),
          );
        }
      } finally {
        _toggleBusy = false;
      }
      return;
    }

    // ——— ACTIVAR ———
    unawaited(
      showVolonexProgressDialog(
        context,
        title: 'Activando viajes',
        message: 'Activando su cuenta para empezar a recibir viajes…',
      ),
    );

    final started = DateTime.now();
    var okFinal = false;
    String? errorMsg;
    String? accionAjustes;
    var queued = false;

    try {
      final gps = await _iniciarGpsMatching().timeout(
        const Duration(seconds: 12),
        onTimeout: () => (
          ok: false,
          err:
              'No se pudo obtener GPS a tiempo. Activa la ubicación e intenta de nuevo.',
          accionAjustes: 'app_settings',
        ),
      );
      if (!gps.ok) {
        errorMsg = gps.err ?? 'Activa la ubicación para buscar viajes.';
        accionAjustes = gps.accionAjustes;
      } else {
        await TaxiBuscandoPrefs.setActivo(true);
        final res =
            await TaxiTarifasChoferService.instance.setDisponible(true);
        if (!res.ok) {
          await TaxiBuscandoPrefs.setActivo(false);
          _pararPublicacionGps();
          await _posSub?.cancel();
          _posSub = null;
          errorMsg = res.err ?? 'Configura tu tarifa en Ajustes de taxis';
        } else {
          queued = res.queued;
          try {
            await TaxiBuscandoSonidoService.alActivar();
          } catch (e) {
            debugPrint('⚠️ Sonido buscando viajes: $e');
          }
          okFinal = true;
        }
      }

      const minShow = Duration(milliseconds: 900);
      final elapsed = DateTime.now().difference(started);
      if (elapsed < minShow) {
        await Future<void>.delayed(minShow - elapsed);
      }
    } finally {
      await _cerrarModalCargaBuscando();
      _toggleBusy = false;
    }

    if (!mounted) return;

    if (!okFinal) {
      if (errorMsg != null) {
        final esUbicacion = accionAjustes != null ||
            errorMsg.toLowerCase().contains('ubicación') ||
            errorMsg.toLowerCase().contains('gps') ||
            errorMsg.toLowerCase().contains('localiza');
        if (esUbicacion) {
          await _mostrarDialogoUbicacionRequerida(
            mensaje: errorMsg,
            accionAjustes: accionAjustes,
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMsg),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
      return;
    }

    setState(() => _buscando = true);
    widget.onBuscandoChanged?.call(true);
    _radar.repeat();
    if (queued) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Viajes activados en el dispositivo. Se sincronizará al tener internet.',
          ),
          backgroundColor: AppColors.header,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _fleetTimer?.cancel();
    _pararPublicacionGps();
    _radar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mismo tamaño en flota demo Cubalink23 (credibilidad visual).
    const fleetSize = 30.0;
    final yoSize = _esCubalink23 ? fleetSize : 40.0;

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
                  maxZoom: _esCubalink23 ? 17 : 16,
                  backgroundColor: const Color(0xFFE8EEF4),
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  RepartidorMapTileLayer(
                    // Con internet: Carto calles; sin red el widget cae a MBTiles.
                    preferOnline: true,
                    maxZoom: 18,
                  ),
                  if (_nearbyCars.isNotEmpty)
                    MarkerLayer(
                      markers: [
                        for (final c in _nearbyCars)
                          Marker(
                            point: c.point,
                            width: fleetSize,
                            height: fleetSize,
                            alignment: Alignment.center,
                            child: TaxiUberMapCar(
                              size: fleetSize,
                              headingDeg: c.headingDeg,
                            ),
                          ),
                      ],
                    ),
                  if (_yo != null)
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: _yo!,
                          width: yoSize,
                          height: yoSize,
                          child: TaxiUberMapCar(size: yoSize),
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
                    const TaxiReservasChoferPanel(),
                    const Spacer(),
                    LayoutBuilder(
                      builder: (context, panelConstraints) {
                        final compact =
                            MediaQuery.sizeOf(context).height < 480;
                        return Padding(
                          padding: EdgeInsets.fromLTRB(
                            24,
                            0,
                            24,
                            compact ? 12 : 28,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _BuscandoRadarButton(
                                activo: _buscando,
                                animation: _radar,
                                onTap: _toggleBuscando,
                                size: compact ? 96 : 132,
                              ),
                              SizedBox(height: compact ? 8 : 16),
                              Text(
                                _buscando
                                    ? 'Buscando viajes · activo'
                                    : 'Toca para buscar viajes',
                                style: TextStyle(
                                  color: _buscando
                                      ? const Color(0xFF4CAF50)
                                      : const Color(0xFFECEFF1),
                                  fontSize: compact ? 15 : 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (!compact) ...[
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
                            ],
                          ),
                        );
                      },
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
    this.size = 132,
  });

  final bool activo;
  final Animation<double> animation;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final inner = size * 0.59;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: AnimatedBuilder(
          animation: animation,
          builder: (context, child) {
            final t = activo ? animation.value : 0.0;
            return CustomPaint(
              painter: _RadarPainter(progress: t, activo: activo),
              child: Center(
                child: Container(
                  width: inner,
                  height: inner,
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
