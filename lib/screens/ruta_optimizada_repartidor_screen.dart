import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import '../models/orden.dart';
import '../services/paises_service.dart';
import '../services/mapa_region_service.dart';
import '../services/google_maps_ruta_service.dart';
import '../services/direccion_navegacion_service.dart';
import '../services/orden_estado_sync_helper.dart';
import '../services/sync_service.dart';
import '../services/taxi_directions_service.dart';
import '../main.dart';
import 'detalle_orden_screen.dart';
import '../config/app_colors.dart';
import '../widgets/volonex_dialog.dart';
import '../widgets/taxi_uber_map_car.dart';
import '../widgets/repartidor_map_tile_layer.dart';

/// Pantalla que muestra la ruta optimizada con todas las órdenes numeradas en el mapa
/// Similar a Uber cuando tiene múltiples pedidos
class RutaOptimizadaRepartidorScreen extends StatefulWidget {
  final List<Orden> ordenes;
  final String repartidorNombre;
  /// Datos de sucursal por orden (desde lista principal), para navegación correcta.
  final Map<String, Map<String, dynamic>>? sucursalesPorOrdenId;

  const RutaOptimizadaRepartidorScreen({
    super.key,
    required this.ordenes,
    required this.repartidorNombre,
    this.sucursalesPorOrdenId,
  });

  @override
  State<RutaOptimizadaRepartidorScreen> createState() => _RutaOptimizadaRepartidorScreenState();
}

class _RutaOptimizadaRepartidorScreenState extends State<RutaOptimizadaRepartidorScreen> {
  final MapController _mapController = MapController();
  LatLng? _ubicacionRepartidor;
  bool _isLoading = true;
  int _ordenActualIndex = 0; // Índice de la orden actual en la ruta
  bool _rutaIniciada = false;
  bool _priorizarUrgentesAtrasadas = false; // Si true, las prioritarias van primero
  bool _autoStartHecho = false;
  Timer? _timerUbicacion;
  
  // Map para almacenar coordenadas geocodificadas temporalmente
  final Map<String, LatLng> _coordenadasGeocodificadas = {};
  
  // Lista de órdenes actualizada (para reflejar cambios de estado)
  List<Orden> _ordenesActualizadas = [];
  
  // Nombre de la empresa para mostrar en mensajes
  String? _nombreEmpresa;

  String? _paisOperacion;
  LatLng? _centroMapaInicial;
  double _zoomMapaInicial = 12.0;
  List<LatLng> _geometriaRutaCarretera = [];
  bool _cargandoGeometriaRuta = false;
  /// Evita que una respuesta de red vieja pise geometría más reciente.
  int _geometriaRutaGen = 0;
  /// Segundos de conducción hasta esa parada (desde la anterior / repartidor).
  final Map<String, int> _etaSegundosHastaOrden = {};
  /// Km de conducción hasta esa parada.
  final Map<String, double> _kmHastaOrden = {};
  int? _etaTotalRutaS;
  double? _kmTotalRuta;

  bool get _sinInternet {
    try {
      return !SyncService().isOnline;
    } catch (_) {
      return false;
    }
  }

  // Lista de órdenes ordenadas por orden_ruta o por índice si no tienen orden_ruta
  // Excluye órdenes entregadas y canceladas
  List<Orden> get _ordenesOrdenadas {
    // Usar órdenes actualizadas si existen, sino usar las originales
    final ordenes = _ordenesActualizadas.isNotEmpty 
        ? List<Orden>.from(_ordenesActualizadas)
        : List<Orden>.from(widget.ordenes);
    
    // Filtrar órdenes entregadas y canceladas (no deben aparecer en la ruta)
    final ordenesActivas = ordenes.where((orden) => 
      orden.estado != 'ENTREGADO' && orden.estado != 'CANCELADA'
    ).toList();
    
    // Si las órdenes ya fueron ordenadas por distancia en _ordenesActualizadas,
    // mantener ese orden (independientemente del flag _priorizarUrgentesAtrasadas)
    // Esto asegura que tanto "Entregar Primero" como "Seguir Ruta" respeten el orden por distancia
    if (_ordenesActualizadas.isNotEmpty && _rutaIniciada) {
      // Las órdenes ya están ordenadas por distancia (ya sea con o sin priorizar urgentes),
      // solo filtrar entregadas/canceladas manteniendo el orden
      return ordenesActivas;
    }
    
    ordenesActivas.sort((a, b) {
      // PRIORIDAD 1: Órdenes de recoger en sucursal van de ÚLTIMO siempre
      if (a.recogerEnSucursal && !b.recogerEnSucursal) return 1;  // a es recoger en sucursal, b no -> b primero
      if (!a.recogerEnSucursal && b.recogerEnSucursal) return -1; // b es recoger en sucursal, a no -> a primero
      
      // Si ambas son recoger en sucursal o ambas no, continuar con otros criterios
      
      // Ordenamiento normal: por orden_ruta
      // Si ambas tienen orden_ruta, ordenar por orden_ruta
      if (a.ordenRuta != null && b.ordenRuta != null) {
        return a.ordenRuta!.compareTo(b.ordenRuta!);
      }
      // Si solo una tiene orden_ruta, esa va primero
      if (a.ordenRuta != null && b.ordenRuta == null) return -1;
      if (a.ordenRuta == null && b.ordenRuta != null) return 1;
      // Si ninguna tiene orden_ruta, mantener el orden actual (ya ordenado por distancia)
      return 0;
    });
    return ordenesActivas;
  }
  
  // Verificar si una orden es prioritaria (urgente o atrasada)
  // Excluye órdenes de recoger en sucursal
  bool _esOrdenPrioritaria(Orden orden) {
    // Excluir órdenes de recoger en sucursal
    if (orden.recogerEnSucursal) return false;
    
    // Verificar si es urgente
    if (orden.esUrgente) return true;
    
    if (orden.estado == 'ENTREGADO' || orden.estado == 'CANCELADA') {
      return false;
    }
    
    // Verificar si está marcada como atrasada por admin
    if (orden.estado == 'ATRASADO') {
      return true;
    }
    
    // Verificar si la fecha estimada de entrega ya pasó
    if (orden.fechaEstimadaEntrega != null) {
      return DateTime.now().isAfter(orden.fechaEstimadaEntrega!);
    }
    
    return false;
  }

  Orden? get _ordenActual {
    if (_ordenActualIndex < _ordenesOrdenadas.length) {
      return _ordenesOrdenadas[_ordenActualIndex];
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _cargarNombreEmpresa();
    _inicializarRegionMapa();
    _obtenerUbicacionRepartidor();
    _geocodificarOrdenesSinCoordenadas();
  }

  Future<void> _inicializarRegionMapa() async {
    String? pais;
    if (widget.ordenes.isNotEmpty && widget.ordenes.first.tenantId != null) {
      try {
        pais = await PaisesService.obtenerPaisOperacion(widget.ordenes.first.tenantId!);
      } catch (_) {}
    }
    pais ??= await PaisesService.obtenerPaisOperacionActual();
    _paisOperacion = pais;

    final guardada = await MapaRegionService.cargarRegionGuardada();
    if (!mounted) return;
    setState(() {
      _centroMapaInicial = guardada?.centro ?? MapaRegionService.centroPorPais(pais);
      _zoomMapaInicial = guardada?.zoom ?? MapaRegionService.zoomInicialPorPais(pais);
    });
  }

  String _formatEtaSegundos(int? s) {
    if (s == null || s <= 0) return '';
    if (s < 60) return 'menos de 1 min';
    final min = (s / 60).ceil();
    if (min < 60) return '$min min';
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

  /// Geometría + ETA solo con coordenadas en caché (sin red).
  void _aplicarGeometriaLocal(
    List<LatLng> waypoints,
    List<Orden> ordenesConCoord, {
    required bool hayRepartidor,
  }) {
    final etas = <String, int>{};
    final kms = <String, double>{};
    var totalS = 0;
    var totalM = 0;
    for (var i = 0; i < waypoints.length - 1; i++) {
      final leg = TaxiDirectionsService.offlineHaversine(
        waypoints[i],
        waypoints[i + 1],
      );
      final dur = leg.durationS ?? 0;
      final dist = leg.distanceM ?? 0;
      totalS += dur;
      totalM += dist;
      final ordenIdx = hayRepartidor ? i : (i + 1);
      if (ordenIdx >= 0 && ordenIdx < ordenesConCoord.length) {
        final oid = ordenesConCoord[ordenIdx].id;
        etas[oid] = dur;
        kms[oid] = dist / 1000.0;
      }
    }
    if (!mounted) return;
    setState(() {
      _geometriaRutaCarretera = List<LatLng>.from(waypoints);
      _etaSegundosHastaOrden
        ..clear()
        ..addAll(etas);
      _kmHastaOrden
        ..clear()
        ..addAll(kms);
      _etaTotalRutaS = totalS > 0 ? totalS : null;
      _kmTotalRuta = totalM > 0 ? totalM / 1000.0 : null;
      _cargandoGeometriaRuta = false;
    });
  }

  /// Primero dibuja desde caché (offline). Si hay red, mejora con calles
  /// con timeout; nunca deja el spinner colgado.
  Future<void> _actualizarGeometriaRutaEnMapa() async {
    final gen = ++_geometriaRutaGen;
    final ordenes = _ordenesOrdenadas;
    final ordenesConCoord = <Orden>[];
    final waypoints = <LatLng>[];
    if (_ubicacionRepartidor != null) {
      waypoints.add(_ubicacionRepartidor!);
    }
    for (final orden in ordenes) {
      final c = _obtenerCoordenadas(orden);
      if (c != null) {
        ordenesConCoord.add(orden);
        waypoints.add(c);
      }
    }
    if (waypoints.length < 2) {
      if (mounted && gen == _geometriaRutaGen) {
        setState(() {
          _geometriaRutaCarretera = waypoints;
          _etaSegundosHastaOrden.clear();
          _kmHastaOrden.clear();
          _etaTotalRutaS = null;
          _kmTotalRuta = null;
          _cargandoGeometriaRuta = false;
        });
      }
      return;
    }

    final hayRepartidor = _ubicacionRepartidor != null;
    // Siempre útil al instante (modo offline / caché).
    _aplicarGeometriaLocal(
      waypoints,
      ordenesConCoord,
      hayRepartidor: hayRepartidor,
    );

    if (_sinInternet) return;

    // Mejora por calles en segundo plano (no bloquea «Ir a esta parada»).
    unawaited(
      _mejorarGeometriaConRed(
        gen: gen,
        waypoints: waypoints,
        ordenesConCoord: ordenesConCoord,
        hayRepartidor: hayRepartidor,
      ),
    );
  }

  Future<void> _mejorarGeometriaConRed({
    required int gen,
    required List<LatLng> waypoints,
    required List<Orden> ordenesConCoord,
    required bool hayRepartidor,
  }) async {
    if (!mounted || gen != _geometriaRutaGen) return;
    setState(() => _cargandoGeometriaRuta = true);

    final geometria = <LatLng>[];
    final etas = <String, int>{};
    final kms = <String, double>{};
    var totalS = 0;
    var totalM = 0;

    try {
      await Future(() async {
        for (var i = 0; i < waypoints.length - 1; i++) {
          if (gen != _geometriaRutaGen) return;
          try {
            final leg = await TaxiDirectionsService.instance.rutaConEta(
              origen: waypoints[i],
              destino: waypoints[i + 1],
            );
            if (leg.points.length >= 2) {
              if (geometria.isEmpty) {
                geometria.addAll(leg.points);
              } else {
                geometria.addAll(leg.points.skip(1));
              }
            } else {
              if (geometria.isEmpty) geometria.add(waypoints[i]);
              geometria.add(waypoints[i + 1]);
            }
            final dur = leg.durationS ?? 0;
            final dist = leg.distanceM ?? 0;
            totalS += dur;
            totalM += dist;
            final ordenIdx = hayRepartidor ? i : (i + 1);
            if (ordenIdx >= 0 && ordenIdx < ordenesConCoord.length) {
              final oid = ordenesConCoord[ordenIdx].id;
              etas[oid] = dur;
              kms[oid] = dist / 1000.0;
            }
          } catch (_) {
            if (geometria.isEmpty) geometria.add(waypoints[i]);
            geometria.add(waypoints[i + 1]);
          }
        }
      }).timeout(const Duration(seconds: 12));
    } catch (_) {
      // Se queda la geometría local ya aplicada.
    }

    if (_ubicacionRepartidor != null) {
      var zoom = _zoomMapaInicial;
      try {
        zoom = _mapController.camera.zoom;
      } catch (_) {}
      try {
        await MapaRegionService.guardarRegion(
          pais: _paisOperacion ?? 'Cuba',
          centro: _ubicacionRepartidor!,
          zoom: zoom,
        ).timeout(const Duration(seconds: 2));
      } catch (_) {}
    }

    if (!mounted || gen != _geometriaRutaGen) return;
    if (geometria.length >= 2) {
      setState(() {
        _geometriaRutaCarretera = geometria;
        if (etas.isNotEmpty) {
          _etaSegundosHastaOrden
            ..clear()
            ..addAll(etas);
        }
        if (kms.isNotEmpty) {
          _kmHastaOrden
            ..clear()
            ..addAll(kms);
        }
        if (totalS > 0) _etaTotalRutaS = totalS;
        if (totalM > 0) _kmTotalRuta = totalM / 1000.0;
        _cargandoGeometriaRuta = false;
      });
    } else {
      setState(() => _cargandoGeometriaRuta = false);
    }
  }

  /// Encaja el mapa para ver repartidor + todas las paradas + polyline.
  void _ajustarVistaRutaCompleta() {
    final pts = <LatLng>[
      if (_ubicacionRepartidor != null) _ubicacionRepartidor!,
      ..._geometriaRutaCarretera,
    ];
    for (final o in _ordenesOrdenadas) {
      final c = _obtenerCoordenadas(o);
      if (c != null) pts.add(c);
    }
    if (pts.isEmpty) return;
    try {
      if (pts.length == 1) {
        _mapController.move(pts.first, 15);
        return;
      }
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(pts),
          padding: const EdgeInsets.fromLTRB(48, 100, 48, 240),
        ),
      );
    } catch (e) {
      print('⚠️ ajustarVistaRutaCompleta: $e');
    }
  }

  /// Centra en la entrega actual sin salir de la app.
  void _enfocarEntregaActual() {
    final orden = _ordenActual;
    final dest = orden != null ? _obtenerCoordenadas(orden) : null;
    if (dest == null) return;
    final pts = <LatLng>[
      if (_ubicacionRepartidor != null) _ubicacionRepartidor!,
      dest,
    ];
    try {
      if (pts.length == 1) {
        _mapController.move(pts.first, 15.5);
      } else {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(pts),
            padding: const EdgeInsets.fromLTRB(56, 120, 56, 260),
          ),
        );
      }
    } catch (_) {
      _mapController.move(dest, 15.5);
    }
  }

  /// Opcional: Google Maps externo (no es el flujo principal).
  Future<void> _abrirRutaEnGoogleMapsOpcional() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => VolonexDialog(
        title: 'Abrir fuera de la app',
        leading: const Icon(Icons.open_in_new, color: AppColors.info, size: 26),
        child: const Text(
          'La ruta ya está en el mapa de Repartidor. '
          '¿Quieres abrirla también en Google Maps u otra app?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.header,
              foregroundColor: AppColors.onAccentButton,
            ),
            child: const Text('Abrir externo'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final ok = await GoogleMapsRutaService.abrirRutaOrdenes(
      ordenes: _ordenesOrdenadas,
      sucursalesPorOrdenId: widget.sucursalesPorOrdenId,
      paisOperacion: _paisOperacion,
      origenCoordenadas: _ubicacionRepartidor,
    );
    if (!ok) {
      final paradas = <LatLng>[];
      for (final orden in _ordenesOrdenadas) {
        final c = _obtenerCoordenadas(orden);
        if (c != null) paradas.add(c);
      }
      if (paradas.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No hay direcciones válidas para la app externa'),
          ),
        );
        return;
      }
      await GoogleMapsRutaService.abrirRutaEnGoogleMaps(
        origen: _ubicacionRepartidor,
        paradas: paradas,
      );
    }
  }
  
  // Cargar nombre de la empresa desde el tenant_id
  Future<void> _cargarNombreEmpresa() async {
    try {
      // Obtener tenant_id de la primera orden
      if (widget.ordenes.isNotEmpty && widget.ordenes.first.tenantId != null) {
        final tenantData = await supabase
            .from('tenants')
            .select('nombre')
            .eq('id', widget.ordenes.first.tenantId!)
            .maybeSingle();
        
        if (tenantData != null && tenantData['nombre'] != null) {
          setState(() {
            _nombreEmpresa = tenantData['nombre'] as String;
          });
        }
      }
    } catch (e) {
      print('⚠️ Error cargando nombre de empresa: $e');
    }
  }
  
  // Mostrar mensaje informativo cuando la orden está "POR ENVIAR"
  void _mostrarMensajeOrdenNoDisponible() {
    final nombreEmpresa = _nombreEmpresa ?? 'la empresa';
    showDialog(
      context: context,
      builder: (ctx) => VolonexDialog(
        title: 'Orden No Disponible',
        leading: const Icon(Icons.info_outline, color: AppColors.botonPrincipal, size: 24),
        child: Text(
          'No se puede comenzar la entrega porque la orden aún no ha sido recibida desde la bodega.\n\n'
          'Por favor, espere a que las órdenes se envíen desde la bodega de $nombreEmpresa. '
          'Una vez recibida, podrá comenzar a repartirla.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Entendido',
              style: TextStyle(color: AppColors.botonPrincipal, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // Geocodificar órdenes que no tienen coordenadas
  Future<void> _geocodificarOrdenesSinCoordenadas() async {
    final ordenesSinCoords = _ordenesOrdenadas.where((orden) => 
      (orden.latitudEntrega == null || orden.longitudEntrega == null) &&
      !_coordenadasGeocodificadas.containsKey(orden.id)
    ).toList();
    
    if (ordenesSinCoords.isEmpty) {
      print('✅ Todas las órdenes ya tienen coordenadas');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        await _autoIniciarRutaSiCorresponde();
      }
      return;
    }

    // Sin internet no se puede geocodificar: usar solo lat/lng ya en caché/BD.
    if (_sinInternet) {
      print(
        '📴 Offline: ${ordenesSinCoords.length} órdenes sin coordenadas; '
        'se muestran las que ya tienen lat/lng en caché',
      );
      if (mounted) {
        setState(() => _isLoading = false);
        await _autoIniciarRutaSiCorresponde();
      }
      return;
    }
    
    print('🔍 Geocodificando ${ordenesSinCoords.length} órdenes sin coordenadas...');
    
    for (var orden in ordenesSinCoords) {
      try {
        final suc = widget.sucursalesPorOrdenId?[orden.id];
        final res = await DireccionNavegacionService.resolverConPaisOrden(
          orden,
          sucursal: suc,
        );
        if (!res.esValida) {
          print('   ⚠️ Sin dirección completa para orden #${orden.numeroOrden}');
          continue;
        }
        final direccionCompleta = res.direccionCompleta;
        print('   📍 Geocodificando (${res.tipoDestino}): $direccionCompleta');
        
        final locations = await locationFromAddress(direccionCompleta)
            .timeout(const Duration(seconds: 5));
        if (locations.isNotEmpty) {
          final location = locations.first;
          // Guardar en el Map temporal
          _coordenadasGeocodificadas[orden.id] = LatLng(location.latitude, location.longitude);
          print('   ✅ Coordenadas obtenidas: ${location.latitude}, ${location.longitude}');
        } else {
          print('   ⚠️ No se encontraron coordenadas para: $direccionCompleta');
        }
      } catch (e) {
        print('   ❌ Error geocodificando orden #${orden.numeroOrden}: $e');
      }
    }
    
    // Actualizar el estado para refrescar el mapa
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      await _autoIniciarRutaSiCorresponde();
    }
  }

  /// Un solo flujo: al abrir «Ver ruta» se inicia la ruta por distancia
  /// sin pedir otro tap ni modales de ida y vuelta.
  Future<void> _autoIniciarRutaSiCorresponde() async {
    if (!mounted || _autoStartHecho || _rutaIniciada) return;
    _autoStartHecho = true;
    await _iniciarRutaNormal();
  }
  
  // Obtener coordenadas de una orden (de la BD o del Map temporal)
  LatLng? _obtenerCoordenadas(Orden orden) {
    if (orden.latitudEntrega != null && orden.longitudEntrega != null) {
      return LatLng(orden.latitudEntrega!, orden.longitudEntrega!);
    }
    return _coordenadasGeocodificadas[orden.id];
  }

  @override
  void dispose() {
    _timerUbicacion?.cancel();
    super.dispose();
  }

  Future<void> _obtenerUbicacionRepartidor() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() {
          _ubicacionRepartidor = LatLng(position.latitude, position.longitude);
          _isLoading = false;
        });
        // Solo mover el marcador; la ruta completa se calcula al iniciar / avanzar.
      }
      
      if (_ubicacionRepartidor != null) {
        print('📍 Ubicación del repartidor actualizada: ${_ubicacionRepartidor!.latitude}, ${_ubicacionRepartidor!.longitude}');
      }
    } catch (e) {
      print('❌ Error obteniendo ubicación: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  // Método para centrar el mapa en la ubicación del repartidor (llamado por el botón)
  void _centrarEnRepartidor() {
    if (_ubicacionRepartidor != null) {
      _mapController.move(_ubicacionRepartidor!, 15.0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mapa centrado en tu ubicación'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ubicación no disponible'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // Obtener lista base de órdenes (sin ordenar)
  List<Orden> get _ordenesBase {
    final ordenes = _ordenesActualizadas.isNotEmpty 
        ? List<Orden>.from(_ordenesActualizadas)
        : List<Orden>.from(widget.ordenes);
    
    // Filtrar órdenes entregadas y canceladas
    final ordenesFiltradas = ordenes.where((orden) => 
      orden.estado != 'ENTREGADO' && orden.estado != 'CANCELADA'
    ).toList();
    
    // Debug: Imprimir información de las órdenes base
    print('📦 [ORDENES BASE] Total: ${ordenesFiltradas.length}');
    for (var orden in ordenesFiltradas) {
      print('   - Orden #${orden.numeroOrden}: estado=${orden.estado}, esUrgente=${orden.esUrgente}, recogerEnSucursal=${orden.recogerEnSucursal}, fechaEstimada=${orden.fechaEstimadaEntrega}');
    }
    
    return ordenesFiltradas;
  }
  
  // Detectar órdenes urgentes (excluyendo recoger en sucursal)
  List<Orden> get _ordenesUrgentes {
    return _ordenesBase.where((orden) {
      // Excluir órdenes de recoger en sucursal
      if (orden.recogerEnSucursal) return false;
      return orden.esUrgente;
    }).toList();
  }
  
  // Detectar órdenes atrasadas (excluyendo recoger en sucursal)
  // Una orden está atrasada si:
  // 1. Estado == 'ATRASADO' (marcada por admin), O
  // 2. fechaEstimadaEntrega es anterior a la fecha actual
  List<Orden> get _ordenesAtrasadas {
    final ahora = DateTime.now();
    return _ordenesBase.where((orden) {
      // Excluir órdenes de recoger en sucursal
      if (orden.recogerEnSucursal) return false;
      
      if (orden.estado == 'ENTREGADO' || orden.estado == 'CANCELADA') {
        return false;
      }
      
      // Verificar si está marcada como atrasada por admin
      if (orden.estado == 'ATRASADO') {
        return true;
      }
      
      // Verificar si la fecha estimada de entrega ya pasó
      if (orden.fechaEstimadaEntrega != null) {
        return orden.fechaEstimadaEntrega!.isBefore(ahora);
      }
      
      return false;
    }).toList();
  }
  
  // Obtener órdenes prioritarias (urgentes + atrasadas, excluyendo recoger en sucursal)
  List<Orden> get _ordenesPrioritarias {
    final urgentes = _ordenesUrgentes.map((o) => o.id).toSet();
    final atrasadas = _ordenesAtrasadas.map((o) => o.id).toSet();
    return _ordenesBase.where((orden) {
      // Excluir órdenes de recoger en sucursal
      if (orden.recogerEnSucursal) return false;
      return urgentes.contains(orden.id) || atrasadas.contains(orden.id);
    }).toList();
  }
  
  // Obtener órdenes de recoger en sucursal (van de último)
  List<Orden> get _ordenesRecogerEnSucursal {
    return _ordenesBase.where((orden) => orden.recogerEnSucursal).toList();
  }

  void _iniciarRuta() {
    // Flujo directo: siempre ruta por distancia (sin modal que manda
    // al repartidor de un lado a otro). Las urgentes se pueden priorizar
    // con el chip en la hoja inferior.
    unawaited(_iniciarRutaNormal());
  }
  
  Future<void> _iniciarRutaNormal() async {
    print('🚀 Iniciando ruta normal (optimizada por distancia)...');
    
    // Obtener ubicación actual del repartidor
    if (_ubicacionRepartidor == null) {
      await _obtenerUbicacionRepartidor();
    }
    
    if (_ubicacionRepartidor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo obtener tu ubicación. Usando ordenamiento por defecto.'),
          backgroundColor: AppColors.botonPrincipal,
        ),
      );
      // Continuar sin optimización por distancia
      if (mounted) {
        setState(() {
          _rutaIniciada = true;
          _ordenActualIndex = 0;
          _priorizarUrgentesAtrasadas = false;
        });
      }
      await _actualizarGeometriaRutaEnMapa();
      if (mounted) _ajustarVistaRutaCompleta();
      
      // Actualizar ubicación periódicamente
      _timerUbicacion?.cancel();
      _timerUbicacion = Timer.periodic(const Duration(seconds: 10), (timer) {
        if (mounted) {
          _obtenerUbicacionRepartidor();
        } else {
          timer.cancel();
        }
      });
      return;
    }
    
    // Obtener todas las órdenes base (sin separar prioritarias)
    final ordenesBase = _ordenesBase;
    final ordenesRecogerEnSucursal = _ordenesRecogerEnSucursal;
    
    // Obtener IDs de recoger en sucursal para excluirlas
    final idsRecogerEnSucursal = ordenesRecogerEnSucursal.map((o) => o.id).toSet();
    
    // Todas las órdenes excepto las de recoger en sucursal
    final todasLasOrdenes = ordenesBase.where((orden) {
      return !idsRecogerEnSucursal.contains(orden.id);
    }).toList();
    
    print('📦 Total órdenes para optimizar: ${todasLasOrdenes.length}');
    print('📦 Órdenes recoger en sucursal: ${ordenesRecogerEnSucursal.length}');
    
    // Calcular distancias desde el repartidor a todas las órdenes
    final Map<String, double> distanciasDesdeRepartidor = {};
    
    print('📍 Calculando distancias desde repartidor...');
    for (var orden in todasLasOrdenes) {
      final coords = await _obtenerCoordenadasOrden(orden);
      if (coords != null) {
        final distancia = _calcularDistanciaHaversine(
          _ubicacionRepartidor!.latitude,
          _ubicacionRepartidor!.longitude,
          coords.latitude,
          coords.longitude,
        );
        distanciasDesdeRepartidor[orden.id] = distancia;
        print('   - Orden #${orden.numeroOrden}: ${distancia.toStringAsFixed(2)} km');
      } else {
        distanciasDesdeRepartidor[orden.id] = double.infinity;
        print('   - Orden #${orden.numeroOrden}: Sin coordenadas');
      }
    }
    
    // Ordenar TODAS las órdenes por distancia (más cerca primero)
    // NO priorizar urgentes - entregar por distancia pura
    todasLasOrdenes.sort((a, b) {
      final distA = distanciasDesdeRepartidor[a.id] ?? double.infinity;
      final distB = distanciasDesdeRepartidor[b.id] ?? double.infinity;
      return distA.compareTo(distB);
    });
    
    print('📍 Órdenes ordenadas por distancia desde repartidor (SIN priorizar urgentes):');
    for (int i = 0; i < todasLasOrdenes.length; i++) {
      final orden = todasLasOrdenes[i];
      final dist = distanciasDesdeRepartidor[orden.id] ?? double.infinity;
      final esPrioritaria = _esOrdenPrioritaria(orden);
      final tipo = esPrioritaria ? '🔴 PRIORITARIA' : '⚪ NORMAL';
      print('   ${i + 1}. Orden #${orden.numeroOrden} ($tipo) - ${dist.toStringAsFixed(2)} km');
    }
    
    // Construir ruta final: órdenes por distancia + recoger en sucursal al final
    final List<Orden> rutaFinal = [
      ...todasLasOrdenes,
      ...ordenesRecogerEnSucursal,
    ];
    
    print('✅ Ruta final construida: ${rutaFinal.length} órdenes');
    print('   - Órdenes por distancia: ${todasLasOrdenes.length}');
    print('   - Recoger en sucursal (al final): ${ordenesRecogerEnSucursal.length}');
    
    // Actualizar la lista (NO activar flag de priorización de urgentes)
    if (mounted) {
      setState(() {
        _priorizarUrgentesAtrasadas = false; // NO priorizar urgentes
        _ordenesActualizadas = rutaFinal;
        _rutaIniciada = true;
        _ordenActualIndex = 0;
      });
      
      // Mostrar mensaje informativo
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ruta en el mapa de la app: ${todasLasOrdenes.length} paradas. '
            'Se muestran 1 → 2 → 3… con navegación real.',
          ),
          backgroundColor: AppColors.exito,
          duration: const Duration(seconds: 4),
        ),
      );
    }

    // Dibujar ruta completa en el mapa interno (sin abrir Google Maps).
    await _actualizarGeometriaRutaEnMapa();
    if (mounted) _ajustarVistaRutaCompleta();
    
    // Actualizar ubicación periódicamente
    _timerUbicacion?.cancel();
    _timerUbicacion = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        _obtenerUbicacionRepartidor();
      } else {
        timer.cancel();
      }
    });
  }
  
  void _mostrarModalPrioridad(List<Orden> urgentes, List<Orden> atrasadas) {
    final totalUrgentes = urgentes.length;
    final totalAtrasadas = atrasadas.length;
    final totalPrioritarias = totalUrgentes + totalAtrasadas;
    
    print('📋 [MODAL] Mostrando modal con: $totalUrgentes urgentes, $totalAtrasadas atrasadas, total: $totalPrioritarias');
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => VolonexDialog(
        title: 'Órdenes prioritarias',
        maxWidth: AppLayout.dialogWideMaxWidth,
        leading: const Icon(Icons.priority_high, color: AppColors.error, size: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.darkElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.botonPrincipal, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (totalUrgentes > 0) ...[
                    Row(
                      children: [
                        const Icon(Icons.warning, color: AppColors.error, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$totalUrgentes ${totalUrgentes == 1 ? 'orden urgente' : 'órdenes urgentes'}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (totalAtrasadas > 0) const SizedBox(height: 10),
                  ],
                  if (totalAtrasadas > 0)
                    Row(
                      children: [
                        const Icon(Icons.schedule, color: AppColors.botonPrincipal, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$totalAtrasadas ${totalAtrasadas == 1 ? 'orden atrasada' : 'órdenes atrasadas'}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.botonPrincipal,
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  Text(
                    'Total: $totalPrioritarias ${totalPrioritarias == 1 ? 'orden prioritaria' : 'órdenes prioritarias'}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              '¿Cómo deseas proceder?',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.darkText,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '• Entregar primero: va directo a las prioritarias; si hay otras en el camino, se entregan de paso.\n\n'
              '• Seguir ruta: continúa con el orden optimizado por distancia.',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.darkTextMuted,
                height: 1.45,
              ),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _iniciarRutaConPrioridad();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error, width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            child: const Text('Entregar primero', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _iniciarRutaNormal();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.exito,
              foregroundColor: AppColors.onAccentButton,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            child: const Text('Seguir ruta', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
  
  // Calcular distancia Haversine entre dos puntos
  double _calcularDistanciaHaversine(double lat1, double lon1, double lat2, double lon2) {
    const double radioTierra = 6371; // km
    final dLat = (lat2 - lat1) * (math.pi / 180);
    final dLon = (lon2 - lon1) * (math.pi / 180);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) * math.cos(lat2 * math.pi / 180) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return radioTierra * c;
  }
  
  // Obtener coordenadas de una orden (de BD o geocodificadas)
  Future<LatLng?> _obtenerCoordenadasOrden(Orden orden) async {
    // Si ya tiene coordenadas en la BD, usarlas
    if (orden.latitudEntrega != null && orden.longitudEntrega != null) {
      return LatLng(orden.latitudEntrega!, orden.longitudEntrega!);
    }
    
    // Si ya está en el mapa temporal, usarlo
    if (_coordenadasGeocodificadas.containsKey(orden.id)) {
      return _coordenadasGeocodificadas[orden.id];
    }
    
    try {
      final suc = widget.sucursalesPorOrdenId?[orden.id];
      final res = await DireccionNavegacionService.resolverConPaisOrden(
        orden,
        sucursal: suc,
      );
      if (!res.esValida) return null;

      final locations = await locationFromAddress(res.direccionCompleta);
      if (locations.isNotEmpty) {
        final coords = LatLng(locations.first.latitude, locations.first.longitude);
        _coordenadasGeocodificadas[orden.id] = coords;
        return coords;
      }
    } catch (e) {
      print('⚠️ Error geocodificando orden ${orden.numeroOrden}: $e');
    }
    
    return null;
  }
  
  Future<void> _iniciarRutaConPrioridad() async {
    print('🚀 Iniciando ruta con prioridad...');
    
    // Obtener ubicación actual del repartidor
    if (_ubicacionRepartidor == null) {
      await _obtenerUbicacionRepartidor();
    }
    
    if (_ubicacionRepartidor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo obtener tu ubicación. Usando ordenamiento por defecto.'),
          backgroundColor: AppColors.botonPrincipal,
        ),
      );
      // Continuar sin optimización por distancia
    }
    
    // Obtener órdenes prioritarias, normales y de recoger en sucursal
    final ordenesPrioritarias = _ordenesPrioritarias;
    final ordenesRecogerEnSucursal = _ordenesRecogerEnSucursal;
    final ordenesBase = _ordenesBase;
    
    // Obtener IDs de prioritarias y recoger en sucursal para excluirlas de normales
    final idsPrioritarias = ordenesPrioritarias.map((o) => o.id).toSet();
    final idsRecogerEnSucursal = ordenesRecogerEnSucursal.map((o) => o.id).toSet();
    
    final ordenesNormales = ordenesBase.where((orden) {
      return !idsPrioritarias.contains(orden.id) && 
             !idsRecogerEnSucursal.contains(orden.id);
    }).toList();
    
    print('📦 Órdenes prioritarias: ${ordenesPrioritarias.length}');
    print('📦 Órdenes normales: ${ordenesNormales.length}');
    print('📦 Órdenes recoger en sucursal: ${ordenesRecogerEnSucursal.length}');
    
    // Si no hay ubicación del repartidor, usar ordenamiento simple
    if (_ubicacionRepartidor == null) {
      final nuevaListaOrdenada = <Orden>[
        ...ordenesPrioritarias,
        ...ordenesNormales,
        ...ordenesRecogerEnSucursal,
      ];
      
      if (mounted) {
        setState(() {
          _priorizarUrgentesAtrasadas = true;
          _ordenesActualizadas = nuevaListaOrdenada;
          _rutaIniciada = true;
          _ordenActualIndex = 0;
        });
      }
      await _actualizarGeometriaRutaEnMapa();
      if (mounted) _ajustarVistaRutaCompleta();
      return;
    }
    
    // Calcular distancias desde el repartidor a todas las órdenes
    final Map<String, double> distanciasDesdeRepartidor = {};
    final Map<String, LatLng> coordenadasOrdenes = {};
    
    print('📍 Calculando distancias desde repartidor...');
    for (var orden in [...ordenesPrioritarias, ...ordenesNormales]) {
      final coords = await _obtenerCoordenadasOrden(orden);
      if (coords != null) {
        coordenadasOrdenes[orden.id] = coords;
        final distancia = _calcularDistanciaHaversine(
          _ubicacionRepartidor!.latitude,
          _ubicacionRepartidor!.longitude,
          coords.latitude,
          coords.longitude,
        );
        distanciasDesdeRepartidor[orden.id] = distancia;
        print('   - Orden #${orden.numeroOrden}: ${distancia.toStringAsFixed(2)} km');
      } else {
        distanciasDesdeRepartidor[orden.id] = double.infinity;
        print('   - Orden #${orden.numeroOrden}: Sin coordenadas');
      }
    }
    
    // NUEVA LÓGICA: Ordenar TODAS las órdenes por distancia (más cerca primero)
    // Las prioritarias se mantienen visualmente destacadas pero se entregan por distancia
    // Esto evita desperdiciar gasolina yendo lejos cuando hay órdenes cerca
    
    // Combinar prioritarias y normales
    final todasLasOrdenes = [...ordenesPrioritarias, ...ordenesNormales];
    
    // Ordenar TODAS por distancia desde el repartidor
    todasLasOrdenes.sort((a, b) {
      final distA = distanciasDesdeRepartidor[a.id] ?? double.infinity;
      final distB = distanciasDesdeRepartidor[b.id] ?? double.infinity;
      return distA.compareTo(distB);
    });
    
    print('📍 Órdenes ordenadas por distancia desde repartidor:');
    for (int i = 0; i < todasLasOrdenes.length; i++) {
      final orden = todasLasOrdenes[i];
      final dist = distanciasDesdeRepartidor[orden.id] ?? double.infinity;
      final esPrioritaria = idsPrioritarias.contains(orden.id);
      final tipo = esPrioritaria ? '🔴 PRIORITARIA' : '⚪ NORMAL';
      print('   ${i + 1}. Orden #${orden.numeroOrden} ($tipo) - ${dist.toStringAsFixed(2)} km');
    }
    
    // Construir ruta final: órdenes por distancia + recoger en sucursal al final
    final List<Orden> rutaFinal = [
      ...todasLasOrdenes,
      ...ordenesRecogerEnSucursal,
    ];
    
    print('✅ Ruta final construida: ${rutaFinal.length} órdenes');
    print('   - Órdenes por distancia: ${todasLasOrdenes.length}');
    print('   - Recoger en sucursal (al final): ${ordenesRecogerEnSucursal.length}');
    
    // Activar el flag de priorización y actualizar la lista
    if (mounted) {
      setState(() {
        _priorizarUrgentesAtrasadas = true;
        _ordenesActualizadas = rutaFinal;
        _rutaIniciada = true;
        _ordenActualIndex = 0;
      });
      
      // Mostrar mensaje informativo
      final mensaje = ordenesRecogerEnSucursal.isNotEmpty
          ? 'Ruta optimizada por distancia: ${todasLasOrdenes.length} órdenes (${ordenesPrioritarias.length} prioritarias). ${ordenesRecogerEnSucursal.length} de recoger en sucursal al final. Se entregarán las más cercanas primero para ahorrar gasolina.'
          : 'Ruta optimizada por distancia: ${todasLasOrdenes.length} órdenes (${ordenesPrioritarias.length} prioritarias). Se entregarán las más cercanas primero para ahorrar gasolina.';
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensaje),
          backgroundColor: AppColors.botonPrincipal,
          duration: const Duration(seconds: 4),
        ),
      );
    }

    await _actualizarGeometriaRutaEnMapa();
    if (mounted) _ajustarVistaRutaCompleta();
    
    // Actualizar ubicación periódicamente
    _timerUbicacion?.cancel(); // Cancelar timer anterior si existe
    _timerUbicacion = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        _obtenerUbicacionRepartidor();
      } else {
        timer.cancel();
      }
    });
  }
  
  // Marcar una orden como "EN REPARTO"
  Future<void> _marcarOrdenComoEnReparto(Orden orden) async {
    try {
      print('🔄 Marcando orden #${orden.numeroOrden} como EN REPARTO...');

      final ordenActualizada = Orden(
        id: orden.id,
        numeroOrden: orden.numeroOrden,
        emisor: orden.emisor,
        receptor: orden.receptor,
        descripcion: orden.descripcion,
        direccionDestino: orden.direccionDestino,
        telefonoDestinatario: orden.telefonoDestinatario,
        ciudadDestino: orden.ciudadDestino,
        provinciaDestino: orden.provinciaDestino,
        municipioDestino: orden.municipioDestino,
        consejoPopularBatey: orden.consejoPopularBatey,
        peso: orden.peso,
        largo: orden.largo,
        ancho: orden.ancho,
        alto: orden.alto,
        estado: 'EN REPARTO',
        fechaCreacion: orden.fechaCreacion,
        fechaEntrega: orden.fechaEntrega,
        fechaEstimadaEntrega: orden.fechaEstimadaEntrega,
        notas: orden.notas,
        repartidor: orden.repartidor,
        esUrgente: orden.esUrgente,
        fotoEntrega: orden.fotoEntrega,
        creadoPorNombre: orden.creadoPorNombre,
        creadoPorEmail: orden.creadoPorEmail,
        cantidadBultos: orden.cantidadBultos,
        requierePago: orden.requierePago,
        montoCobrar: orden.montoCobrar,
        moneda: orden.moneda,
        pagado: orden.pagado,
        fechaPago: orden.fechaPago,
        notasPago: orden.notasPago,
        tieneRemesa: orden.tieneRemesa,
        cantidadRemesa: orden.cantidadRemesa,
        requiereFirma: orden.requiereFirma,
        firmaUrl: orden.firmaUrl,
        itemsAdicionales: orden.itemsAdicionales,
        tenantId: orden.tenantId,
        ordenRuta: orden.ordenRuta,
        latitudEntrega: orden.latitudEntrega,
        longitudEntrega: orden.longitudEntrega,
        distanciaDesdeAnterior: orden.distanciaDesdeAnterior,
        tiempoEstimadoDesdeAnterior: orden.tiempoEstimadoDesdeAnterior,
      );

      await OrdenEstadoSyncHelper.persistirCambioEstado(
        ordenId: orden.id,
        ordenEnCache: ordenActualizada,
        updateData: const {'estado': 'EN REPARTO'},
      );

      // Actualizar en la lista
      final index = _ordenesActualizadas.indexWhere((o) => o.id == orden.id);
      if (index != -1) {
        _ordenesActualizadas[index] = ordenActualizada;
      } else {
        _ordenesActualizadas.add(ordenActualizada);
      }
      
      if (mounted) {
        setState(() {});
      }
      
      print('✅ Orden #${orden.numeroOrden} marcada como EN REPARTO');
    } catch (e) {
      print('❌ Error marcando orden como EN REPARTO: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al actualizar estado: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _siguienteOrden() {
    if (!mounted) return;

    if (_ordenActualIndex < _ordenesOrdenadas.length - 1) {
      setState(() {
        _ordenActualIndex++;
      });

      final siguienteOrden = _ordenActual;
      if (siguienteOrden != null) {
        final coordenadas = _obtenerCoordenadas(siguienteOrden);
        if (coordenadas != null) {
          _mapController.move(coordenadas, 15.0);
        }
      }
      unawaited(_actualizarGeometriaRutaEnMapa());
      return;
    }

    // Última parada: salir a home (no volver a la orden 1).
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Fin de la ruta'),
        duration: Duration(seconds: 2),
        backgroundColor: AppColors.exito,
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _marcarComoEntregado(Orden orden) async {
    // Verificar que la orden esté en "EN REPARTO"
    if (orden.estado != 'EN REPARTO') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La orden debe estar en "EN REPARTO" para poder entregarla'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    
    // Navegar a la pantalla de detalle para marcar como entregado
    final resultado = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DetalleOrdenScreen(orden: orden),
      ),
    );
    
    // Si la orden fue entregada exitosamente, avanzar a la siguiente orden
    if (resultado == true && mounted) {
      print('✅ Orden entregada exitosamente, recargando órdenes...');
      
      // Recargar órdenes para obtener el estado actualizado
      await _recargarOrdenes();
      
      // Esperar un momento para que el estado se actualice
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Verificar cuántas órdenes quedan después de filtrar entregadas
      final ordenesRestantes = _ordenesOrdenadas;
      print('📦 Órdenes restantes después de entregar: ${ordenesRestantes.length}');
      
      if (ordenesRestantes.isEmpty) {
        // No hay más órdenes, mostrar mensaje de ruta completada
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('¡Todas las órdenes han sido entregadas!'),
              duration: Duration(seconds: 3),
              backgroundColor: AppColors.exito,
            ),
          );
        }
        return;
      }
      
      // Guardar el ID de la orden entregada
      final ordenIdEntregada = orden.id;
      
      // Ajustar el índice: si la orden entregada estaba antes del índice actual, reducir el índice
      int nuevoIndice = _ordenActualIndex;
      final indiceOrdenEntregada = ordenesRestantes.indexWhere((o) => o.id == ordenIdEntregada);
      
      // Si la orden entregada estaba en la lista y su índice era menor o igual al actual, ajustar
      if (indiceOrdenEntregada != -1 && indiceOrdenEntregada <= _ordenActualIndex) {
        nuevoIndice = _ordenActualIndex; // Mantener el mismo índice (la siguiente orden ocupará este lugar)
      }
      
      // Asegurar que el índice no exceda el tamaño de la lista
      if (nuevoIndice >= ordenesRestantes.length) {
        nuevoIndice = ordenesRestantes.length > 0 ? ordenesRestantes.length - 1 : 0;
      }
      
      // Si no hay más órdenes, no hacer nada más
      if (ordenesRestantes.isEmpty) {
        if (mounted) {
          setState(() {
            _ordenActualIndex = 0;
          });
        }
        return;
      }
      
      // Actualizar el índice
      if (mounted) {
        setState(() {
          _ordenActualIndex = nuevoIndice;
        });
      }
      
      // Centrar mapa en la nueva orden actual
      final nuevaOrdenActual = _ordenActual;
      if (nuevaOrdenActual != null) {
        final coordenadas = _obtenerCoordenadas(nuevaOrdenActual);
        if (coordenadas != null) {
          _mapController.move(coordenadas, 15.0);
        }
        unawaited(_actualizarGeometriaRutaEnMapa());
        
        // Marcar la nueva orden como "EN REPARTO" si está en "EN TRANSITO"
        if (nuevaOrdenActual.estado == 'EN TRANSITO' || nuevaOrdenActual.estado == 'ATRASADO') {
          await _marcarOrdenComoEnReparto(nuevaOrdenActual);
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Avanzando a orden #${nuevaOrdenActual.numeroOrden} (${ordenesRestantes.length} restantes)'),
              duration: const Duration(seconds: 2),
              backgroundColor: AppColors.exito,
            ),
          );
        }
      } else {
        // Si no hay orden actual, ir a la primera
        if (ordenesRestantes.isNotEmpty && mounted) {
          setState(() {
            _ordenActualIndex = 0;
          });
          final primeraOrden = ordenesRestantes.first;
          final coordenadas = _obtenerCoordenadas(primeraOrden);
          if (coordenadas != null) {
            _mapController.move(coordenadas, 15.0);
          }
        }
      }
    }
  }
  
  // Recargar órdenes desde la base de datos (solo con internet).
  Future<void> _recargarOrdenes() async {
    if (_sinInternet) {
      print('📴 Offline: se mantienen órdenes en memoria/caché (sin recargar BD)');
      return;
    }
    try {
      final ordenIds = widget.ordenes.map((o) => o.id).toList();
      
      // Obtener órdenes una por una (más confiable que usar filtros complejos)
      final List<Orden> ordenesRecargadas = [];
      for (final ordenId in ordenIds) {
        try {
          final response = await supabase
              .from('ordenes')
              .select()
              .eq('id', ordenId)
              .single()
              .timeout(const Duration(seconds: 5));
          
          ordenesRecargadas.add(Orden.fromJson(response));
        } catch (e) {
          print('⚠️ Error recargando orden $ordenId: $e');
          // Si falla, mantener la orden original
          final ordenOriginal = widget.ordenes.firstWhere(
            (o) => o.id == ordenId,
            orElse: () => _ordenesActualizadas.firstWhere((o) => o.id == ordenId),
          );
          ordenesRecargadas.add(ordenOriginal);
        }
      }
      
      if (ordenesRecargadas.isNotEmpty) {
        _ordenesActualizadas = ordenesRecargadas;
        
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      print('❌ Error recargando órdenes: $e');
    }
  }
  
  // Explorar orden (ver detalles sin entregar)
  void _explorarOrden(Orden orden) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DetalleOrdenScreen(orden: orden),
      ),
    );
  }

  /// Enfoca la parada actual en el mapa. Si está en tránsito, pasa a EN REPARTO
  /// sin diálogo intermedio (un solo paso).
  Future<void> _abrirNavegacion(Orden orden) async {
    if (!mounted) return;

    // UI inmediata con datos en caché (sin esperar red).
    final idx = _ordenesOrdenadas.indexWhere((o) => o.id == orden.id);
    if (idx >= 0) {
      setState(() {
        _rutaIniciada = true;
        _ordenActualIndex = idx;
      });
    }
    _enfocarEntregaActual();

    final estado = orden.estado.toUpperCase();
    if (estado == 'EN TRANSITO' || estado == 'ATRASADO') {
      // Caché + cola offline; no recargar desde BD (bloquea sin internet).
      unawaited(_marcarOrdenComoEnReparto(orden));
    }

    // Geometría: primero local; si hay red, mejora con timeout.
    unawaited(_actualizarGeometriaRutaEnMapa());
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.darkBg,
        appBar: AppBar(
          title: const Text('Ruta Optimizada'),
          backgroundColor: AppColors.header,
          foregroundColor: AppColors.onAccentButton,
        ),
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.botonPrincipal),
        ),
      );
    }

    // Obtener órdenes con coordenadas (de BD o geocodificadas)
    final ordenesConCoordenadas = _ordenesOrdenadas.where((o) => 
      _obtenerCoordenadas(o) != null
    ).toList();
    
    final ordenesSinCoordenadas = _ordenesOrdenadas.where((o) => 
      _obtenerCoordenadas(o) == null
    ).toList();

    if (ordenesConCoordenadas.isEmpty && ordenesSinCoordenadas.isEmpty) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        title: const Text('Ruta Optimizada'),
        backgroundColor: AppColors.header,
        foregroundColor: AppColors.onAccentButton,
        actions: [
          if (_ubicacionRepartidor != null)
            IconButton(
              icon: const Icon(Icons.my_location, color: AppColors.onAccentButton),
              onPressed: _centrarEnRepartidor,
              tooltip: 'Rastrear Repartidor',
            ),
        ],
      ),
        body: const Center(
          child: Text(
            'No hay órdenes para mostrar en el mapa',
            style: TextStyle(color: AppColors.darkTextMuted),
          ),
        ),
      );
    }
    
    // Si hay órdenes sin coordenadas, mostrar mensaje pero continuar
    if (ordenesSinCoordenadas.isNotEmpty) {
      print('⚠️ ${ordenesSinCoordenadas.length} órdenes sin coordenadas. Se mostrarán en la lista pero no en el mapa.');
    }

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        title: const Text('Ruta Optimizada'),
        backgroundColor: AppColors.header,
        foregroundColor: AppColors.onAccentButton,
        actions: [
          IconButton(
            icon: const Icon(Icons.route, color: AppColors.onAccentButton),
            onPressed: () {
              unawaited(() async {
                await _actualizarGeometriaRutaEnMapa();
                if (mounted) _ajustarVistaRutaCompleta();
              }());
            },
            tooltip: 'Ver ruta completa en el mapa',
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new, color: AppColors.onAccentButton),
            onPressed: _abrirRutaEnGoogleMapsOpcional,
            tooltip: 'Abrir en app externa (opcional)',
          ),
          if (_ubicacionRepartidor != null)
            IconButton(
              icon: const Icon(Icons.my_location, color: AppColors.onAccentButton),
              onPressed: _centrarEnRepartidor,
              tooltip: 'Rastrear Repartidor',
            ),
        ],
      ),
      body: Stack(
        children: [
          // Mapa
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _ubicacionRepartidor ??
                _centroMapaInicial ??
                (ordenesConCoordenadas.isNotEmpty
                    ? _obtenerCoordenadas(ordenesConCoordenadas.first)!
                    : MapaRegionService.centroPorPais(_paisOperacion)),
              initialZoom: _zoomMapaInicial,
              minZoom: 3.0,
              maxZoom: 18.0,
              backgroundColor: const Color(0xFFE8EEF4),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              // Con internet: calles Carto modernas (no MBTiles en blanco).
              RepartidorMapTileLayer(
                preferOnline: true,
                maxZoom: 18,
                tenantId: _ordenesOrdenadas.isNotEmpty
                    ? _ordenesOrdenadas.first.tenantId
                    : (widget.ordenes.isNotEmpty
                        ? widget.ordenes.first.tenantId
                        : null),
              ),

              // Ruta real de navegación (no líneas rectas).
              if (_geometriaRutaCarretera.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _geometriaRutaCarretera,
                      strokeWidth: 5.5,
                      color: const Color(0xFF1A73E8),
                      borderStrokeWidth: 2.0,
                      borderColor: Colors.white.withValues(alpha: 0.85),
                    ),
                  ],
                ),

              if (_ubicacionRepartidor != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _ubicacionRepartidor!,
                      width: 44,
                      height: 44,
                      child: const TaxiUberMapCar(size: 42),
                    ),
                  ],
                ),

              MarkerLayer(
                markers: ordenesConCoordenadas.asMap().entries
                  .where((entry) => _obtenerCoordenadas(entry.value) != null)
                  .map((entry) {
                    final index = entry.key;
                    final orden = entry.value;
                    final ordenRuta = orden.ordenRuta ?? (index + 1);
                    final coordenadas = _obtenerCoordenadas(orden)!;
                    final esActual =
                        _ordenActualIndex == index && _rutaIniciada;

                  return Marker(
                    point: coordenadas,
                    width: 44,
                    height: 44,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: esActual
                            ? const Color(0xFFFF9800)
                            : const Color(0xFF1A73E8),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.28),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          '$ordenRuta',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          if (_cargandoGeometriaRuta)
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Material(
                  color: AppColors.darkElevated,
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  elevation: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.darkBorder),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.botonPrincipal,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Mejorando ruta (opcional)…',
                          style: TextStyle(fontSize: 12, color: AppColors.darkText),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Resumen ETA de la ruta / próxima entrega
          if (!_cargandoGeometriaRuta &&
              (_etaTotalRutaS != null || _ordenActual != null))
            Positioned(
              top: 12,
              left: 12,
              right: 72,
              child: Material(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(12),
                elevation: 3,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_rutaIniciada && _ordenActual != null) ...[
                        Text(
                          'A la próxima entrega',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF666666),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          () {
                            final eta = _formatEtaSegundos(
                              _etaSegundosHastaOrden[_ordenActual!.id],
                            );
                            final km = _kmHastaOrden[_ordenActual!.id];
                            final parts = <String>[];
                            if (eta.isNotEmpty) parts.add(eta);
                            if (km != null && km > 0) {
                              parts.add('${km.toStringAsFixed(1)} km');
                            }
                            return parts.isEmpty
                                ? 'Calculando…'
                                : parts.join(' · ');
                          }(),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2C2C2C),
                          ),
                        ),
                      ] else ...[
                        const Text(
                          'Ruta completa',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF666666),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          () {
                            final eta = _formatEtaSegundos(_etaTotalRutaS);
                            final parts = <String>[];
                            if (eta.isNotEmpty) parts.add(eta);
                            if (_kmTotalRuta != null && _kmTotalRuta! > 0) {
                              parts.add(
                                '${_kmTotalRuta!.toStringAsFixed(1)} km',
                              );
                            }
                            parts.add('${_ordenesOrdenadas.length} paradas');
                            return parts.join(' · ');
                          }(),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2C2C2C),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          
          // Botones de zoom (+ y -) en la esquina superior derecha
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.darkElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.darkBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        final currentZoom = _mapController.camera.zoom;
                        final newZoom = (currentZoom + 1).clamp(3.0, 16.0);
                        _mapController.move(_mapController.camera.center, newZoom);
                      },
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: AppColors.darkBorder, width: 1),
                          ),
                        ),
                        child: const Icon(
                          Icons.add,
                          color: AppColors.info,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        final currentZoom = _mapController.camera.zoom;
                        final newZoom = (currentZoom - 1).clamp(3.0, 16.0);
                        _mapController.move(_mapController.camera.center, newZoom);
                      },
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                      child: const SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(
                          Icons.remove,
                          color: AppColors.info,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Panel inferior con información de la orden actual
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              top: false,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.darkSurface,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  border: const Border(
                    top: BorderSide(color: AppColors.darkBorder, width: 1),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                  // Barra de arrastre
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.darkBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  
                  if (!_rutaIniciada) ...[
                    // Mientras auto-inicia: no pedir otro tap «Iniciar Ruta».
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            '${_ordenesOrdenadas.length} paradas en orden',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.darkText,
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Preparando ruta en el mapa…',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.darkTextMuted,
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: _iniciarRuta,
                            child: const Text(
                              'Reintentar si tarda',
                              style: TextStyle(color: AppColors.botonPrincipal),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_ordenActual != null) ...[
                    // Información de la orden actual
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((_ordenesUrgentes.isNotEmpty ||
                                  _ordenesAtrasadas.isNotEmpty) &&
                              !_priorizarUrgentesAtrasadas)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Material(
                                color: AppColors.botonPrincipal
                                    .withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => unawaited(
                                    _iniciarRutaConPrioridad(),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.priority_high,
                                          color: AppColors.botonPrincipal,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Hay urgentes/atrasadas. '
                                            'Toca para priorizarlas '
                                            '(sin salir de aquí).',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: AppColors.darkText,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.botonPrincipal,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Parada ${_ordenActualIndex + 1} de ${_ordenesOrdenadas.length}',
                                  style: const TextStyle(
                                    color: AppColors.onAccentButton,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '#${_ordenActual!.numeroOrden}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.darkText,
                                  ),
                                ),
                              ),
                              Builder(
                                builder: (_) {
                                  final eta = _formatEtaSegundos(
                                    _etaSegundosHastaOrden[_ordenActual!.id],
                                  );
                                  final kmNav =
                                      _kmHastaOrden[_ordenActual!.id];
                                  final kmFallback =
                                      _ordenActual!.distanciaDesdeAnterior;
                                  final km = kmNav ?? kmFallback;
                                  final parts = <String>[];
                                  if (eta.isNotEmpty) parts.add(eta);
                                  if (km != null && km > 0) {
                                    parts.add('${km.toStringAsFixed(1)} km');
                                  }
                                  if (parts.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Text(
                                      parts.join(' · '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1A73E8),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _ordenActual!.direccionDestino,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.darkText,
                            ),
                          ),
                          if (_ordenActual!.receptor.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Destinatario: ${_ordenActual!.receptor}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.darkTextMuted,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          // Acciones compactas (sin estirar a todo el ancho).
                          Center(
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  unawaited(_abrirNavegacion(_ordenActual!)),
                              icon: const Icon(Icons.navigation, size: 18),
                              label: Text(
                                (_ordenActual!.estado == 'EN TRANSITO' ||
                                        _ordenActual!.estado == 'ATRASADO')
                                    ? 'Ir a parada (iniciar)'
                                    : 'Ir a esta parada',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.info,
                                foregroundColor: AppColors.onAccentButton,
                                elevation: 0,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Center(
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (_ordenActual!.estado == 'EN REPARTO')
                                  ElevatedButton.icon(
                                    onPressed: () =>
                                        _marcarComoEntregado(_ordenActual!),
                                    icon: const Icon(Icons.check_circle,
                                        size: 18),
                                    label: const Text('Entregar'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.exito,
                                      foregroundColor:
                                          AppColors.onAccentButton,
                                      elevation: 0,
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 11),
                                    ),
                                  )
                                else
                                  OutlinedButton.icon(
                                    onPressed: () =>
                                        _explorarOrden(_ordenActual!),
                                    icon: const Icon(Icons.info_outline,
                                        size: 18),
                                    label: const Text('Detalle'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppColors.darkText,
                                      side: const BorderSide(
                                          color: AppColors.darkBorder),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 11),
                                    ),
                                  ),
                                ElevatedButton.icon(
                                  onPressed: _siguienteOrden,
                                  icon: Icon(
                                    _ordenActualIndex <
                                            _ordenesOrdenadas.length - 1
                                        ? Icons.arrow_forward
                                        : Icons.done_all,
                                    size: 18,
                                  ),
                                  label: Text(
                                    _ordenActualIndex <
                                            _ordenesOrdenadas.length - 1
                                        ? 'Siguiente'
                                        : 'Finalizar',
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.header,
                                    foregroundColor: AppColors.onAccentButton,
                                    elevation: 0,
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 11),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_ordenActual!.estado == 'EN REPARTO') ...[
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.center,
                              child: TextButton(
                                onPressed: () =>
                                    _explorarOrden(_ordenActual!),
                                child: const Text(
                                  'Ver detalle de la orden',
                                  style: TextStyle(
                                    color: AppColors.darkTextMuted,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ] else ...[
                    // Ruta completada
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: AppColors.exito,
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            '¡Ruta Completada!',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.exito,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Has completado todas las ${_ordenesOrdenadas.length} órdenes',
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.darkTextMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                    ],
                  ),
                ),
            ),
            ),
          ),
        ],
      ),
    );
  }
}

