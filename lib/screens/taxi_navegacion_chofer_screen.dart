import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../config/app_colors.dart';
import '../services/repartidor_suspension_service.dart';
import '../services/taxi_chofer_service.dart';
import '../services/taxi_directions_service.dart';
import '../widgets/taxi_cash_cobrar_completar_modal.dart';
import '../widgets/taxi_cash_comision_aviso_modal.dart';
import '../widgets/taxi_chofer_maplibre.dart';
import '../widgets/taxi_itinerario_chofer_panel.dart';
import 'repartidor_mobile_screen.dart';
import 'taxi_comision_pendiente_screen.dart';
import 'taxi_ganancias_screen.dart';

/// Navegación GPS del socio (estilo Uber):
/// · Recogidas (1 o más si es compartido)
/// · Paradas intermedias
/// · Destinos (si hay varios, el más cercano en ruta primero)
class TaxiNavegacionChoferScreen extends StatefulWidget {
  const TaxiNavegacionChoferScreen({super.key, required this.oferta});

  final TaxiOfertaChofer oferta;

  @override
  State<TaxiNavegacionChoferScreen> createState() =>
      _TaxiNavegacionChoferScreenState();
}

class _TaxiNavegacionChoferScreenState extends State<TaxiNavegacionChoferScreen> {
  late TaxiOfertaChofer _oferta;
  LatLng? _yo;
  StreamSubscription<Position>? _posSub;
  Timer? _pingTimer;
  bool _busy = false;
  List<LatLng> _rutaReal = const [];
  /// Overview por calles A→paradas→B (gris), aparte del tramo activo (azul).
  List<LatLng> _rutaOverview = const [];
  int? _overviewEtaSegundos;
  bool _cargandoOverview = false;
  bool _cargandoRuta = false;
  DateTime? _ultimaRutaAt;
  LatLng? _ultimoOrigenRuta;
  String? _etaLabel;
  int? _etaSegundos;
  bool _etaConTrafico = false;
  /// Velocidad GPS actual (m/s). Null si aún no hay lectura.
  double? _speedMps;
  Timer? _chatBadgeTimer;
  int _chatNoLeidos = 0;
  String? _ultimoClienteMsgIdLeido;
  bool _chatSheetAbierto = false;
  Timer? _estadoPollTimer;
  bool _salidaRemotaManejada = false;
  bool _estadoPollEnCurso = false;

  /// Índice del tramo actual en [_legs].
  int _legIndex = 0;
  /// Tras «Llegada» en una recogida: espera abordaje.
  bool _awaitingBoard = false;
  /// Legs con destinos reordenados tras iniciar viaje compartido.
  List<TaxiItinerarioStop>? _legsOrdered;

  LatLng get _puntoA => LatLng(_oferta.origenLat, _oferta.origenLng);
  LatLng get _puntoB => LatLng(_oferta.destinoLat, _oferta.destinoLng);

  List<TaxiItinerarioStop> get _legs =>
      _legsOrdered ?? _oferta.legsNavegacion();

  TaxiItinerarioStop? get _legActual {
    final legs = _legs;
    if (legs.isEmpty) return null;
    return legs[_legIndex.clamp(0, legs.length - 1)];
  }

  String get _solicitudPasajeroActual {
    final id = (_legActual?.solicitudId ?? '').trim();
    return id.isNotEmpty ? id : _oferta.id;
  }

  String get _pasajeroActualNombre {
    final nombre = (_legActual?.pasajero ?? '').trim();
    return nombre.isNotEmpty ? nombre : _oferta.pasajeroNombre;
  }

  bool get _pasajeroActualEsCompanero =>
      _solicitudPasajeroActual != _oferta.id;

  bool get _multiTramo =>
      _oferta.esCompartido ||
      _oferta.tieneParadas ||
      _legs.length > 2;

  bool get _faseEspera {
    if (_multiTramo) return _awaitingBoard;
    return _awaitingBoard ||
        (_oferta.esperandoPasajero &&
            !_oferta.haciaDestino &&
            (_legActual?.esRecogida ?? true));
  }

  bool get _faseDestino =>
      _oferta.haciaDestino || (_legActual?.esDestino ?? false);

  bool get _faseParada => _legActual?.esParada ?? false;

  LatLng get _navTarget {
    final ll = _legActual?.latLng;
    if (ll != null) return ll;
    if (_faseDestino) return _puntoB;
    return _puntoA;
  }

  String get _tituloFase {
    final leg = _legActual;
    if (_faseEspera) {
      final nom = (leg?.pasajero ?? '').trim();
      if (nom.isNotEmpty) return 'Esperando a $nom';
      return 'Esperando al pasajero';
    }
    if (leg != null) {
      if (leg.esRecogida) return 'Hacia recogida';
      if (leg.esParada) return 'Hacia parada';
      if (leg.esDestino) {
        return _legs.where((e) => e.esDestino).length > 1
            ? 'Hacia destino'
            : 'Hacia el destino';
      }
    }
    if (_faseDestino) return 'Hacia el destino';
    return 'Hacia el pasajero';
  }

  String get _botonLabel {
    final legs = _legs;
    final leg = _legActual;
    final haySiguiente = _legIndex < legs.length - 1;

    if (_faseEspera) {
      if (leg != null && leg.esRecogida) {
        final quedanRecogidas = legs
            .skip(_legIndex + 1)
            .any((e) => e.esRecogida);
        if (quedanRecogidas) return 'A bordo · ir al siguiente pasajero';
      }
      return 'Iniciar viaje';
    }
    if (_faseParada) return 'Parada completada';
    if (_faseDestino) {
      if (haySiguiente && (legs[_legIndex + 1].esDestino)) {
        return 'Pasajero bajó · siguiente destino';
      }
      return 'Completar viaje';
    }
    return 'Llegada';
  }

  @override
  void initState() {
    super.initState();
    _oferta = widget.oferta;
    _sincronizarLegConEstado();
    unawaited(_bloquearSiCuentaSuspendida());
    unawaited(_refrescarFotoPasajero());
    unawaited(_cargarRatingPasajero());
    _iniciarGps();
    _pingTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      unawaited(_enviarUbicacion());
    });
    _chatBadgeTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_actualizarBadgeChat());
    });
    _estadoPollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_pollEstadoViajeRemoto());
    });
    unawaited(_actualizarBadgeChat());
    unawaited(_pollEstadoViajeRemoto());
  }

  /// Alinea el tramo local con el estado del backend (reabrir app a mitad).
  void _sincronizarLegConEstado() {
    final legs = _legs;
    if (legs.isEmpty) return;
    if (_oferta.itinerarioPersistido) {
      _legsOrdered = List<TaxiItinerarioStop>.of(_oferta.itinerario);
      _legIndex =
          _oferta.itinerarioIndice.clamp(0, _legsOrdered!.length - 1);
      _awaitingBoard = _oferta.itinerarioEsperando;
      return;
    }
    if (_oferta.haciaDestino) {
      _legsOrdered ??= _oferta.legsNavegacion(
        desdeParaDestinos: _yo ?? _puntoA,
      );
      final idx = _legs.indexWhere((e) => e.esParada || e.esDestino);
      _legIndex = idx >= 0 ? idx : 0;
      _awaitingBoard = false;
    } else if (_oferta.esperandoPasajero) {
      _legIndex = 0;
      _awaitingBoard = true;
    } else {
      _legIndex = 0;
      _awaitingBoard = false;
    }
  }

  void _avanzarLeg() {
    final legs = _legs;
    if (_legIndex < legs.length - 1) {
      _legIndex++;
      _awaitingBoard = false;
    }
  }

  void _prepararLegsTrasIniciar() {
    _legsOrdered = _oferta.legsNavegacion(
      desdeParaDestinos: _yo ?? _navTarget,
    );
    final idx = _legs.indexWhere((e) => e.esParada || e.esDestino);
    _legIndex = idx >= 0 ? idx : (_legs.length - 1);
    _awaitingBoard = false;
  }

  Future<bool> _guardarProgreso() async {
    for (var intento = 0; intento < 2; intento++) {
      final res =
          await TaxiChoferService.instance.guardarProgresoItinerario(
        solicitudId: _oferta.id,
        orden: _legs,
        indice: _legIndex,
        esperando: _awaitingBoard,
      );
      if (res.ok) return true;
      if (intento == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No se guardó el avance del itinerario. Revisa la conexión e inténtalo otra vez.',
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
    return false;
  }

  Future<void> _cargarRatingPasajero() async {
    final id = _oferta.id;
    if (id.isEmpty) return;
    final r =
        await TaxiChoferService.instance.pasajeroRatingPorSolicitud(id);
    if (!mounted) return;
    setState(() {
      _oferta = _oferta.copyWith(
        pasajeroRating: r.rating,
        pasajeroReviews: r.reviews,
      );
    });
  }

  Future<void> _pedirValoracionPasajero() async {
    if (!mounted) return;
    var estrellas = 5;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              constraints: const BoxConstraints(maxWidth: 400),
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              title: const Text(
                '¿Cómo fue el pasajero?',
                style: TextStyle(
                  color: Color(0xFF2C2C2C),
                  fontWeight: FontWeight.w700,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _oferta.pasajeroNombre.trim().isEmpty
                        ? 'Pasajero'
                        : _oferta.pasajeroNombre.trim(),
                    style: const TextStyle(
                      color: Color(0xFF666666),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (i) {
                      final n = i + 1;
                      return IconButton(
                        onPressed: () => setLocal(() => estrellas = n),
                        icon: Icon(
                          n <= estrellas
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: const Color(0xFFFF9800),
                          size: 32,
                        ),
                      );
                    }),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text(
                    'Omitir',
                    style: TextStyle(color: Color(0xFF666666)),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF37474F),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text(
                    'Enviar',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true || !mounted) return;
    await TaxiChoferService.instance.guardarReviewPasajero(
      solicitudId: _oferta.id,
      estrellas: estrellas,
    );
  }

  Future<void> _bloquearSiCuentaSuspendida() async {
    final suspendido =
        await RepartidorSuspensionService.instance.estaSuspendidoAhora();
    if (suspendido != true || !mounted) return;
    _posSub?.cancel();
    _pingTimer?.cancel();
    _chatBadgeTimer?.cancel();
    _estadoPollTimer?.cancel();
    if (!mounted) return;
    // No bloquea toda la app: vuelve al home (pestaña Viajes mostrará suspensión).
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const RepartidorMobileScreen(),
      ),
      (_) => false,
    );
  }

  /// Si el pasajero (u otro lado) cancela, salir del mapa y no quedar colgado.
  Future<void> _pollEstadoViajeRemoto() async {
    if (_salidaRemotaManejada ||
        _busy ||
        _estadoPollEnCurso ||
        !mounted) {
      return;
    }
    final id = _oferta.id;
    if (id.isEmpty) return;
    _estadoPollEnCurso = true;
    try {
      final det = await TaxiChoferService.instance.detalleOferta(id);
      if (!mounted || _salidaRemotaManejada || _busy) return;

      // null = error temporal / RPC; no cerrar la navegación.
      if (det == null) return;

      final est = det.estado.trim().toLowerCase();
      if (est == 'cancelado') {
        await _cerrarPorCancelacionRemota(
          'El viaje fue cancelado.',
        );
        return;
      }
      if (est == 'completado') {
        await _cerrarPorCancelacionRemota(
          'El viaje ya finalizó.',
        );
        return;
      }
      // Actualizar oferta en vivo (fases / foto) sin salir.
      if (est == 'aceptado' || est == 'en_camino' || est == 'en_viaje') {
        if (det.estado != _oferta.estado ||
            det.rutaFase != _oferta.rutaFase ||
            det.pasajeroFotoUrl != _oferta.pasajeroFotoUrl ||
            det.itinerarioIndice != _legIndex ||
            det.itinerarioEsperando != _awaitingBoard) {
          setState(() {
            _oferta = det;
            if (det.itinerarioPersistido) {
              _legsOrdered = List<TaxiItinerarioStop>.of(det.itinerario);
              _legIndex =
                  det.itinerarioIndice.clamp(0, _legsOrdered!.length - 1);
              _awaitingBoard = det.itinerarioEsperando;
            }
          });
        }
      }
    } catch (_) {
    } finally {
      _estadoPollEnCurso = false;
    }
  }

  Future<void> _cerrarPorCancelacionRemota(String mensaje) async {
    if (_salidaRemotaManejada || !mounted) return;
    _salidaRemotaManejada = true;
    _estadoPollTimer?.cancel();
    _pingTimer?.cancel();
    _chatBadgeTimer?.cancel();
    _posSub?.cancel();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: const Color(0xFF37474F),
      ),
    );
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  /// Asegura la foto de perfil del usuario web (CubaLink) en el círculo.
  Future<void> _refrescarFotoPasajero() async {
    final id = _oferta.id;
    if (id.isEmpty) return;
    try {
      final det = await TaxiChoferService.instance.detalleOferta(id);
      if (!mounted || det == null) return;
      final foto = det.pasajeroFotoUrl?.trim();
      if (foto == null || foto.isEmpty) return;
      if (foto == _oferta.pasajeroFotoUrl?.trim() &&
          det.pasajeroNombre == _oferta.pasajeroNombre) {
        return;
      }
      setState(() => _oferta = det);
    } catch (_) {}
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
      setState(() {
        _yo = LatLng(pos.latitude, pos.longitude);
        _speedMps = pos.speed >= 0 ? pos.speed : null;
      });
      await _enviarUbicacion();
      unawaited(_actualizarRutaReal(forzar: true));
    unawaited(_cargarOverviewItinerario(forzar: true));

      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 25,
        ),
      ).listen((p) {
        if (!mounted) return;
        setState(() {
          _yo = LatLng(p.latitude, p.longitude);
          _speedMps = p.speed >= 0 ? p.speed : null;
        });
        unawaited(_actualizarRutaReal());
      });
    } catch (_) {}
  }


  List<LatLng> get _paradasIntermedias {
    final fromOferta = _oferta.paradasLatLng;
    if (fromOferta.isNotEmpty) return fromOferta;
    // Fallback: legs marcados como parada
    return _legs
        .where((e) => e.esParada)
        .map((e) => e.latLng)
        .whereType<LatLng>()
        .toList();
  }

  /// Ruta completa del viaje (calles) para que el chofer vea A→C→B como Uber.
  Future<void> _cargarOverviewItinerario({bool forzar = false}) async {
    if (_cargandoOverview) return;
    if (!forzar && _rutaOverview.length >= 3) return;
    _cargandoOverview = true;
    try {
      final paradas = _paradasIntermedias;
      final result = await TaxiDirectionsService.instance.rutaItinerario(
        origen: _puntoA,
        destino: _puntoB,
        paradas: paradas,
      );
      if (!mounted) return;
      setState(() {
        _rutaOverview = result.points.length >= 2
            ? result.points
            : [_puntoA, ...paradas, _puntoB];
        _overviewEtaSegundos = result.durationS;
        _cargandoOverview = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rutaOverview = [_puntoA, ..._paradasIntermedias, _puntoB];
        _cargandoOverview = false;
      });
    }
  }

  /// Trayecto por calles + ETA (Google Directions con tráfico; fallback OSRM).
  Future<void> _actualizarRutaReal({bool forzar = false}) async {
    if (_cargandoRuta) return;
    final ahora = DateTime.now();
    if (!forzar &&
        _ultimaRutaAt != null &&
        ahora.difference(_ultimaRutaAt!) < const Duration(seconds: 12)) {
      return;
    }

    final LatLng origen;
    final LatLng destino = _navTarget;
    if (_faseEspera) {
      // En recogida: ETA informativo al siguiente tramo.
      origen = _navTarget;
      final legs = _legs;
      LatLng? next;
      for (var i = _legIndex + 1; i < legs.length; i++) {
        next = legs[i].latLng;
        if (next != null) break;
      }
      // destino ya es _navTarget; si hay next, usarlo para preview
      final previewDest = next ?? _puntoB;
      _cargandoRuta = true;
      try {
        final result = await TaxiDirectionsService.instance.rutaConEta(
          origen: origen,
          destino: previewDest,
        );
        if (!mounted) return;
        setState(() {
          _rutaReal = result.points.length >= 2
              ? result.points
              : [origen, previewDest];
          _ultimaRutaAt = DateTime.now();
          _ultimoOrigenRuta = origen;
          _etaSegundos = result.durationS;
          _etaConTrafico = result.traffic;
          _etaLabel = 'En el punto de recogida — espera al pasajero';
          _cargandoRuta = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _rutaReal = [origen, previewDest];
          _cargandoRuta = false;
        });
      }
      return;
    } else {
      final yo = _yo;
      if (yo == null && !_faseDestino && !_faseParada) return;
      origen = yo ?? _puntoA;
      if (!forzar &&
          yo != null &&
          _ultimoOrigenRuta != null &&
          Geolocator.distanceBetween(
                _ultimoOrigenRuta!.latitude,
                _ultimoOrigenRuta!.longitude,
                yo.latitude,
                yo.longitude,
              ) <
              80) {
        return;
      }
    }

    _cargandoRuta = true;
    try {
      final result = await TaxiDirectionsService.instance.rutaConEta(
        origen: origen,
        destino: destino,
      );
      if (!mounted) return;
      final haciaPasajero = _legActual?.esRecogida == true;
      final eta = TaxiDirectionsService.formatEtaChofer(
              haciaPasajero: haciaPasajero,
              haciaDestino: _faseDestino || _faseParada,
              durationS: result.durationS,
              durationText: result.durationText,
            );
      setState(() {
        _rutaReal =
            result.points.length >= 2 ? result.points : [origen, destino];
        _ultimaRutaAt = DateTime.now();
        _ultimoOrigenRuta = origen;
        _etaSegundos = result.durationS;
        _etaConTrafico = result.traffic;
        _etaLabel = eta;
        _cargandoRuta = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rutaReal = [origen, destino];
        _cargandoRuta = false;
      });
    }
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

  Future<void> _completarViajeFinal() async {
    if (_oferta.esPagoCash) {
      final totalCobrar = _oferta.precioUsd ?? _oferta.gananciaUsd;
      final comision = _oferta.comisionViajeUsd > 0
          ? _oferta.comisionViajeUsd
          : (totalCobrar > 0 && _oferta.comisionPct > 0
              ? totalCobrar * _oferta.comisionPct / 100.0
              : (totalCobrar - _oferta.gananciaUsd).clamp(0.0, totalCobrar));
      final cobrado = await TaxiCashCobrarCompletarModal.show(
        context,
        totalCobrarUsd: totalCobrar,
        gananciaChoferUsd: _oferta.gananciaUsd,
        comisionEmpresaUsd: comision,
      );
      if (cobrado != true || !mounted) return;
    }

    setState(() => _busy = true);
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
    if (res.esCash || _oferta.esPagoCash) {
      final total = _oferta.precioUsd ?? _oferta.gananciaUsd;
      final comision = res.comisionUsd ?? _oferta.comisionViajeUsd;
      final irPerfil = await TaxiCashComisionAvisoModal.show(
        context,
        totalViajeUsd: total,
        comisionUsd: comision,
        topeDeudaUsd: _oferta.topeDeudaUsd,
        comisionPct: _oferta.comisionPct,
        gananciaChoferUsd: res.gananciaUsd ?? _oferta.gananciaUsd,
        tituloAccion: 'Ir a pagar',
        mostrarCancelar: true,
      );
      if (!mounted) return;
      await _pedirValoracionPasajero();
      if (!mounted) return;
      Navigator.of(context).pop();
      if (irPerfil == true && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const TaxiComisionPendienteScreen(),
          ),
        );
      }
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.gananciaUsd != null
              ? 'Viaje completado · +\$${res.gananciaUsd!.toStringAsFixed(2)} USD'
              : 'Viaje completado',
        ),
        backgroundColor: const Color(0xFF4CAF50),
      ),
    );
    await _pedirValoracionPasajero();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _accionPrincipal() async {
    if (_busy) return;

    final legs = _legs;
    final leg = _legActual;
    final haySiguiente = _legIndex < legs.length - 1;

    // Parada intermedia: persistir antes de mostrar el siguiente tramo.
    if (_faseParada && !_faseEspera) {
      final indiceAnterior = _legIndex;
      setState(() {
        _busy = true;
        _avanzarLeg();
      });
      final guardado = await _guardarProgreso();
      if (!mounted) return;
      setState(() => _busy = false);
      if (!guardado) {
        setState(() => _legIndex = indiceAnterior);
        return;
      }
      unawaited(_actualizarRutaReal(forzar: true));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Parada marcada. Continúa al siguiente punto.'),
          backgroundColor: Color(0xFF37474F),
        ),
      );
      return;
    }

    // Destino intermedio (viaje compartido con 2 bajadas).
    if (_faseDestino &&
        haySiguiente &&
        legs[_legIndex + 1].esDestino &&
        !_faseEspera) {
      final indiceAnterior = _legIndex;
      setState(() {
        _busy = true;
        _avanzarLeg();
      });
      final guardado = await _guardarProgreso();
      if (!mounted) return;
      setState(() => _busy = false);
      if (!guardado) {
        setState(() => _legIndex = indiceAnterior);
        return;
      }
      unawaited(_actualizarRutaReal(forzar: true));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pasajero bajó. Navegando al siguiente destino.',
          ),
          backgroundColor: Color(0xFF37474F),
        ),
      );
      return;
    }

    // Último destino → completar.
    if (_faseDestino && !_faseEspera) {
      await _completarViajeFinal();
      return;
    }

    setState(() => _busy = true);

    if (_faseEspera) {
      final quedanRecogidas =
          legs.skip(_legIndex + 1).any((e) => e.esRecogida);

      // Compartido: tras abordar A, ir a recoger B (aún no inicia trayecto final).
      if (quedanRecogidas) {
        final indiceAnterior = _legIndex;
        setState(() {
          _avanzarLeg();
        });
        final guardado = await _guardarProgreso();
        if (!mounted) return;
        setState(() => _busy = false);
        if (!guardado) {
          setState(() {
            _legIndex = indiceAnterior;
            _awaitingBoard = true;
          });
          return;
        }
        unawaited(_actualizarRutaReal(forzar: true));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Pasajero a bordo. Ahora recoge al siguiente pasajero.',
            ),
            backgroundColor: Color(0xFF37474F),
          ),
        );
        return;
      }

      // Última recogida → iniciar viaje y ordenar destinos (Uber Share).
      final res = await TaxiChoferService.instance.iniciarViaje(_oferta.id);
      if (!mounted) return;
      if (!res.ok || res.oferta == null) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.err ?? 'No se pudo iniciar el viaje'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      setState(() {
        _oferta = res.oferta!;
        _prepararLegsTrasIniciar();
      });
      final guardado = await _guardarProgreso();
      if (!mounted) return;
      setState(() => _busy = false);
      if (!guardado) return;
      unawaited(_actualizarRutaReal(forzar: true));
      final msg = _multiTramo
          ? 'Viaje iniciado. Sigue el itinerario (paradas / destinos en orden).'
          : 'Ruta al destino cargada. ¡Buen viaje!';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: const Color(0xFF37474F),
        ),
      );
      return;
    }

    // Llegada a recogida.
    final esPrimeraRecogida = leg == null ||
        legs.take(_legIndex + 1).where((e) => e.esRecogida).length <= 1;

    if (esPrimeraRecogida && !_oferta.esperandoPasajero) {
      final res = await TaxiChoferService.instance.lleguePasajero(_oferta.id);
      if (!mounted) return;
      if (!res.ok || res.oferta == null) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.err ?? 'No se pudo marcar la llegada'),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
      setState(() {
        _oferta = res.oferta!;
        _awaitingBoard = true;
      });
      final guardado = await _guardarProgreso();
      if (!mounted) return;
      if (!guardado) {
        setState(() => _busy = false);
        return;
      }
    } else {
      final esperandoAnterior = _awaitingBoard;
      setState(() {
        _awaitingBoard = true;
      });
      final guardado = await _guardarProgreso();
      if (!mounted) return;
      if (!guardado) {
        setState(() {
          _busy = false;
          _awaitingBoard = esperandoAnterior;
        });
        return;
      }
    }
    setState(() => _busy = false);
    unawaited(_actualizarRutaReal(forzar: true));
    final quedanMas = legs.skip(_legIndex + 1).any((e) => e.esRecogida);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          quedanMas
              ? 'Llegaste a la recogida. Cuando aborde, ve al siguiente pasajero.'
              : 'Aviso enviado. Cuando aborde, pulsa «Iniciar viaje».',
        ),
        backgroundColor: const Color(0xFF37474F),
      ),
    );
  }

  Future<void> _abrirChatPasajero() async {
    if (!mounted) return;
    _chatSheetAbierto = true;
    if (_chatNoLeidos > 0) {
      setState(() => _chatNoLeidos = 0);
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: _TaxiChoferChatSheet(
          solicitudId: _solicitudPasajeroActual,
          pasajeroNombre: _pasajeroActualNombre,
        ),
      ),
    );
    _chatSheetAbierto = false;
    if (!mounted) return;
    // Al cerrar el chat, todo lo visto cuenta como leído.
    final list =
        await TaxiChoferService.instance.listarMensajes(
      _solicitudPasajeroActual,
    );
    final cliente =
        list.where((m) => m.autorRol == 'cliente').toList();
    if (cliente.isNotEmpty) {
      _ultimoClienteMsgIdLeido = cliente.last.id;
    }
    unawaited(
      TaxiChoferService.instance.marcarChatTaxiLeido(
        _solicitudPasajeroActual,
      ),
    );
    if (mounted) setState(() => _chatNoLeidos = 0);
  }

  /// Badge en «Enviar mensaje…» con mensajes del pasajero aún no abiertos.
  Future<void> _actualizarBadgeChat() async {
    if (!mounted || !_faseEspera || _chatSheetAbierto) return;
    final list =
        await TaxiChoferService.instance.listarMensajes(
      _solicitudPasajeroActual,
    );
    if (!mounted || _chatSheetAbierto) return;
    final cliente =
        list.where((m) => m.autorRol == 'cliente').toList();
    int n;
    final visto = _ultimoClienteMsgIdLeido;
    if (visto == null || visto.isEmpty) {
      n = cliente.length;
    } else {
      final idx = cliente.indexWhere((m) => m.id == visto);
      n = idx < 0 ? cliente.length : (cliente.length - idx - 1);
      if (n < 0) n = 0;
    }
    if (n != _chatNoLeidos) {
      setState(() => _chatNoLeidos = n);
    }
  }

  Future<void> _confirmarCancelarChofer() async {
    // Tras iniciar trayecto a B el socio no puede cancelar.
    if (_busy || _faseDestino || _oferta.esCompartido) return;
    final esCash = _oferta.esPagoCash;
    final esReserva = _oferta.esReserva;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 400),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        title: Text(
          esReserva ? '¿Liberar esta reserva?' : '¿Cancelar este viaje?',
          style: const TextStyle(
            color: Color(0xFF2C2C2C),
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          esReserva
              ? 'Si liberas la reserva, se buscará otro conductor para el '
                  'pasajero. Tú dejas de tener este viaje asignado.\n\n'
                  'El pasajero será notificado y la reserva seguirá activa '
                  'hasta que otro socio la acepte.'
              : esCash
                  ? 'Si cancelas, pierdes esta carrera. Era pago en efectivo: '
                      'no se devolverá saldo al pasajero porque no se cobró billetera.\n\n'
                      'No recibirás ganancia por este viaje.'
                  : 'Si cancelas (por seguridad o algo sospechoso), pierdes esta carrera '
                      'y el importe se devuelve completo al pasajero.\n\n'
                      'No recibirás ganancia por este viaje.',
          style: const TextStyle(
            color: Color(0xFF666666),
            height: 1.4,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              esReserva ? 'Mantener reserva' : 'Seguir el viaje',
              style: const TextStyle(color: Color(0xFF666666)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              esReserva ? 'Liberar reserva' : 'Cancelar viaje',
              style: const TextStyle(color: Colors.white),
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

    _salidaRemotaManejada = true;
    _estadoPollTimer?.cancel();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.reasignada == true || esReserva
              ? 'Reserva liberada. Se buscará otro conductor para el pasajero.'
              : esCash
                  ? 'Viaje cancelado. No se devolvió saldo (era cash).'
                  : 'Viaje cancelado. El saldo se devolvió al pasajero.',
        ),
        backgroundColor: const Color(0xFF37474F),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _pingTimer?.cancel();
    _chatBadgeTimer?.cancel();
    _estadoPollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final foto = _pasajeroActualEsCompanero
        ? null
        : _oferta.pasajeroFotoUrl?.trim();
    final actual = _pasajeroActualNombre.trim();
    final nombre = actual.isEmpty
        ? 'Pasajero'
        : actual;
    final inicial =
        nombre.isNotEmpty ? nombre.substring(0, 1).toUpperCase() : '?';

    return Scaffold(
      backgroundColor: const Color(0xFF12151C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF37474F),
        foregroundColor: const Color(0xFFECEFF1),
        title: Text(
          _tituloFase,
          style: const TextStyle(
            color: Color(0xFFECEFF1),
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          if (!_faseEspera)
            IconButton(
              tooltip: 'Abrir en Maps / Waze',
              onPressed: () async {
                final dest = _navTarget;
                final leg = _legActual;
                await abrirNavegacionExterna(
                  context: context,
                  lat: dest.latitude,
                  lng: dest.longitude,
                  etiqueta: leg?.etiqueta ??
                      (_faseDestino ? 'destino' : 'recogida'),
                );
              },
              icon: const Icon(Icons.directions),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _faseEspera
                ? _panelEsperandoPasajero(foto, inicial, nombre)
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      TaxiChoferMapLibre(
                        driver: _yo,
                        pickup: _puntoA,
                        destination: _puntoB,
                        routePoints: _rutaReal,
                        showDestination: true,
                        stops: _paradasIntermedias,
                        overviewPoints: _rutaOverview.length >= 2
                            ? _rutaOverview
                            : [_puntoA, ..._paradasIntermedias, _puntoB],
                        activeTarget: _navTarget,
                        totalTripEtaLabel: _overviewEtaSegundos != null &&
                                _overviewEtaSegundos! > 0
                            ? TaxiDirectionsService.formatDuracionCorta(
                                _overviewEtaSegundos,
                              )
                            : null,
                      ),
                      // Foto del pasajero: esquina inferior izquierda del mapa.
                      Positioned(
                        left: 14,
                        bottom: 14,
                        child: _pasajeroAvatar(foto, inicial),
                      ),
                    ],
                  ),
          ),
          Material(
            color: const Color(0xFF1E232E),
            elevation: 12,
            child: SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxPanel = MediaQuery.sizeOf(context).height * 0.48;
                  return ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxPanel),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                    Text(
                      nombre,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFECEFF1),
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            color: Color(0xFFFF9800), size: 16),
                        const SizedBox(width: 4),
                        Text(
                          _oferta.pasajeroReviews > 0
                              ? '${_oferta.pasajeroRating.toStringAsFixed(1)} · ${_oferta.pasajeroReviews} val.'
                              : 'Pasajero nuevo',
                          style: const TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildEtaBanner(),
                    const SizedBox(height: 12),
                    _buildRutaDirecciones(),
                    if (_faseEspera) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF252A35),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: const Text(
                          'El pasajero ya recibió el aviso de que estás afuera.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFECEFF1),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _panelPagoYGanancia(),
                    const SizedBox(height: 14),
                    if (_faseEspera) ...[
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : _abrirChatPasajero,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFECEFF1),
                                side: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.22),
                                ),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(
                                Icons.chat_bubble_outline,
                                size: 18,
                              ),
                              label: const Text(
                                'Enviar mensaje al pasajero',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          if (_chatNoLeidos > 0)
                            Positioned(
                              right: 10,
                              top: -6,
                              child: Container(
                                constraints: const BoxConstraints(
                                  minWidth: 20,
                                  minHeight: 20,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDC2626),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFF1E232E),
                                    width: 1.5,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  _chatNoLeidos > 99
                                      ? '99+'
                                      : '$_chatNoLeidos',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    height: 1.1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _busy ? null : _accionPrincipal,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF37474F),
                          foregroundColor: const Color(0xFFECEFF1),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
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
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                    if (!_faseDestino && !_oferta.esCompartido) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _busy ? null : _confirmarCancelarChofer,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),
                            side: const BorderSide(
                              color: Color(0xFFDC2626),
                              width: 1.2,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Cancelar viaje',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _oferta.esPagoCash
                            ? 'Si cancelas, pierdes la carrera (cash: sin reembolso de billetera).'
                            : 'Si cancelas, pierdes la carrera y el pasajero recupera su saldo.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Banner claro: tiempo hasta el pasajero (A) o hasta el destino (B).
  Widget _buildEtaBanner() {
    final label = _etaLabel ??
        (_faseEspera
            ? 'En el punto de recogida'
            : (_faseDestino
                ? 'Calculando llegada al destino…'
                : 'Calculando llegada al pasajero…'));
    final minutos = _etaSegundos != null && _etaSegundos! > 0
        ? (_etaSegundos! / 60).ceil()
        : null;
    final sub = _faseEspera
        ? 'El pasajero te ve en el mapa'
        : (_etaConTrafico
            ? 'Según tráfico actual'
            : 'Estimación por ruta');
    final speedKmh = (_speedMps != null && _speedMps! >= 1.0)
        ? (_speedMps! * 3.6).round().clamp(1, 200)
        : null;
    final subConVel = speedKmh != null && !_faseEspera
        ? '$sub · $speedKmh km/h'
        : sub;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF252A35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF37474F),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _faseEspera
                  ? Icons.person_pin_circle_outlined
                  : Icons.schedule,
              color: const Color(0xFFECEFF1),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFFECEFF1),
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  minutos != null && !_faseEspera
                      ? '$subConVel · ~$minutos min'
                      : subConVel,
                  style: const TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (minutos != null && !_faseEspera)
            Text(
              '$minutos',
              style: const TextStyle(
                color: Color(0xFFECEFF1),
                fontWeight: FontWeight.w900,
                fontSize: 28,
                height: 1,
              ),
            ),
          if (minutos != null && !_faseEspera) ...[
            const SizedBox(width: 4),
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'min',
                style: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Itinerario completo (paradas + compartido) con tramo activo.
  Widget _buildRutaDirecciones() {
    return TaxiItinerarioChoferPanel(
      oferta: _oferta,
      legs: _legs,
      activoOrden: _legIndex,
      compact: true,
      dark: true,
    );
  }

  /// Ganancia + indicador cash/empresa (compacto, montos claros).
  Widget _panelPagoYGanancia() {
    final esCash = _oferta.esPagoCash;
    final totalCobrar = _oferta.precioUsd ?? _oferta.gananciaUsd;
    final empresa = _oferta.comisionViajeUsd > 0
        ? _oferta.comisionViajeUsd
        : (totalCobrar - _oferta.gananciaUsd).clamp(0.0, totalCobrar).toDouble();
    final accent = esCash ? const Color(0xFF4CAF50) : const Color(0xFF64B5F6);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF252A35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                esCash
                    ? Icons.payments_rounded
                    : Icons.account_balance_wallet_outlined,
                color: accent,
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                esCash ? 'Cash' : 'Pago empresa',
                style: TextStyle(
                  color: accent,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '· ${_oferta.distanciaKm.toStringAsFixed(1)} km',
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (esCash) ...[
            _filaMonto('Cobrar al cliente', totalCobrar, const Color(0xFF4CAF50)),
            const SizedBox(height: 4),
            _filaMonto('Te quedas', _oferta.gananciaUsd, const Color(0xFFECEFF1)),
            const SizedBox(height: 4),
            _filaMonto('Dar a la empresa', empresa, const Color(0xFFFF9800)),
          ] else
            _filaMonto(
              'Tu ganancia',
              _oferta.gananciaUsd,
              const Color(0xFF4CAF50),
            ),
        ],
      ),
    );
  }

  Widget _filaMonto(String label, double monto, Color color) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 12,
            ),
          ),
        ),
        Text(
          '\$${monto.toStringAsFixed(2)}',
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  /// Tras «Llegada»: sustituye el mapa por confirmación visual del pasajero.
  Widget _panelEsperandoPasajero(
    String? foto,
    String inicial,
    String nombre,
  ) {
    return ColoredBox(
      color: const Color(0xFF12151C),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              _pasajeroAvatarGrande(foto, inicial),
              const SizedBox(height: 24),
              Text(
                '¿Ya ves a tu pasajero $nombre?',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFFECEFF1),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Cuando aborde, pulsa «Iniciar viaje».',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pasajeroAvatarGrande(String? foto, String inicial) {
    final url = (foto ?? '').trim();
    final tieneFoto = url.startsWith('http://') || url.startsWith('https://');
    const size = 120.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: tieneFoto
            ? Image.network(
                url,
                fit: BoxFit.cover,
                width: size,
                height: size,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) =>
                    _avatarFallback(inicial, fontSize: 40),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return _avatarFallback(inicial, fontSize: 40);
                },
              )
            : _avatarFallback(inicial, fontSize: 40),
      ),
    );
  }

  Widget _pasajeroAvatar(String? foto, String inicial) {
    final url = (foto ?? '').trim();
    final tieneFoto = url.startsWith('http://') || url.startsWith('https://');
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipOval(
        child: tieneFoto
            ? Image.network(
                url,
                fit: BoxFit.cover,
                width: 72,
                height: 72,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => _avatarFallback(inicial),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return _avatarFallback(inicial);
                },
              )
            : _avatarFallback(inicial),
      ),
    );
  }

  Widget _avatarFallback(String inicial, {double fontSize = 24}) {
    return Container(
      color: const Color(0xFF37474F),
      alignment: Alignment.center,
      child: Text(
        inicial,
        style: TextStyle(
          color: const Color(0xFFECEFF1),
          fontWeight: FontWeight.w800,
          fontSize: fontSize,
        ),
      ),
    );
  }
}

class _TaxiChoferChatSheet extends StatefulWidget {
  const _TaxiChoferChatSheet({
    required this.solicitudId,
    required this.pasajeroNombre,
  });

  final String solicitudId;
  final String pasajeroNombre;

  @override
  State<_TaxiChoferChatSheet> createState() => _TaxiChoferChatSheetState();
}

class _TaxiChoferChatSheetState extends State<_TaxiChoferChatSheet> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final List<TaxiViajeChatMsg> _mensajes = [];
  Timer? _poll;
  bool _cargando = true;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    unawaited(_cargar());
    _poll = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_cargar(silencioso: true));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso && mounted) setState(() => _cargando = true);
    final list =
        await TaxiChoferService.instance.listarMensajes(widget.solicitudId);
    if (!mounted) return;
    setState(() {
      _mensajes
        ..clear()
        ..addAll(list);
      _cargando = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _enviar() async {
    final texto = _ctrl.text.trim();
    if (texto.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    final m = await TaxiChoferService.instance.enviarMensaje(
      solicitudId: widget.solicitudId,
      cuerpo: texto,
    );
    if (!mounted) return;
    setState(() => _enviando = false);
    if (m == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo enviar'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }
    _ctrl.clear();
    setState(() => _mensajes.add(m));
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final nombre = widget.pasajeroNombre.trim().isEmpty
        ? 'Pasajero'
        : widget.pasajeroNombre.trim();

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        constraints: BoxConstraints(maxWidth: 480, maxHeight: h * 0.7),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              color: const Color(0xFF37474F),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Chat con $nombre',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _cargando && _mensajes.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: _mensajes.length,
                      itemBuilder: (_, i) {
                        final m = _mensajes[i];
                        final mio = m.autorRol == 'chofer';
                        return Align(
                          alignment: mio
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            constraints: const BoxConstraints(maxWidth: 280),
                            decoration: BoxDecoration(
                              color: mio
                                  ? const Color(0xFFFFF3E0)
                                  : const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              m.cuerpo,
                              style: const TextStyle(
                                color: Color(0xFF2C2C2C),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        decoration: InputDecoration(
                          hintText: 'Escribe un mensaje…',
                          filled: true,
                          fillColor: const Color(0xFFF5F5F5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => unawaited(_enviar()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFFF9800),
                      ),
                      onPressed: _enviando ? null : () => unawaited(_enviar()),
                      icon: const Icon(Icons.send, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
