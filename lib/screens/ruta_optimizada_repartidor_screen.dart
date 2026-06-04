import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/orden.dart';
import '../services/paises_service.dart';
import '../services/orden_estado_sync_helper.dart';
import '../main.dart';
import 'detalle_orden_screen.dart';
import '../config/app_colors.dart';
import '../widgets/volonex_dialog.dart';

/// Pantalla que muestra la ruta optimizada con todas las órdenes numeradas en el mapa
/// Similar a Uber cuando tiene múltiples pedidos
class RutaOptimizadaRepartidorScreen extends StatefulWidget {
  final List<Orden> ordenes;
  final String repartidorNombre;

  const RutaOptimizadaRepartidorScreen({
    super.key,
    required this.ordenes,
    required this.repartidorNombre,
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
  Timer? _timerUbicacion;
  
  // Map para almacenar coordenadas geocodificadas temporalmente
  final Map<String, LatLng> _coordenadasGeocodificadas = {};
  
  // Lista de órdenes actualizada (para reflejar cambios de estado)
  List<Orden> _ordenesActualizadas = [];
  
  // Nombre de la empresa para mostrar en mensajes
  String? _nombreEmpresa;

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
    _obtenerUbicacionRepartidor();
    _geocodificarOrdenesSinCoordenadas();
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
        setState(() {});
      }
      return;
    }
    
    print('🔍 Geocodificando ${ordenesSinCoords.length} órdenes sin coordenadas...');
    
    // Obtener país de operación del tenant (usar la primera orden para obtener tenant_id)
    String? paisOperacion;
    if (ordenesSinCoords.isNotEmpty && ordenesSinCoords.first.tenantId != null) {
      try {
        paisOperacion = await PaisesService.obtenerPaisOperacion(ordenesSinCoords.first.tenantId!);
        print('🌍 País de operación obtenido: $paisOperacion');
      } catch (e) {
        print('⚠️ Error obteniendo país de operación: $e');
      }
    }
    
    // Si no se pudo obtener, intentar desde el usuario actual
    if (paisOperacion == null || paisOperacion.isEmpty) {
      try {
        paisOperacion = await PaisesService.obtenerPaisOperacionActual();
        print('🌍 País de operación obtenido del usuario actual: $paisOperacion');
      } catch (e) {
        print('⚠️ Error obteniendo país del usuario actual: $e');
      }
    }
    
    // País por defecto si no se encontró (Estados Unidos en lugar de Cuba)
    final paisDefault = paisOperacion ?? 'Estados Unidos';
    print('🌍 Usando país para geocodificación: $paisDefault');
    
    for (var orden in ordenesSinCoords) {
      try {
        // Construir dirección completa
        String direccionCompleta = orden.direccionDestino;
        if (orden.municipioDestino != null && orden.municipioDestino!.isNotEmpty) {
          direccionCompleta += ', ${orden.municipioDestino}';
        }
        if (orden.provinciaDestino != null && orden.provinciaDestino!.isNotEmpty) {
          direccionCompleta += ', ${orden.provinciaDestino}';
        }
        
        // Agregar país solo si no está especificado en la dirección
        final direccionLower = direccionCompleta.toLowerCase();
        final tienePais = direccionLower.contains('cuba') || 
                         direccionLower.contains('usa') ||
                         direccionLower.contains('united states') ||
                         direccionLower.contains('estados unidos') ||
                         direccionLower.contains('united states of america');
        
        if (!tienePais) {
          // Usar el país de operación del tenant, no hardcodear "Cuba"
          direccionCompleta += ', $paisDefault';
        }
        
        print('   📍 Geocodificando: $direccionCompleta');
        
        final locations = await locationFromAddress(direccionCompleta);
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
    }
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
      }
      
      // NO mover el mapa automáticamente - solo actualizar el marcador
      // El usuario puede presionar el botón "Rastrear Repartidor" si quiere centrar el mapa
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
    // Detectar órdenes prioritarias antes de iniciar (usando lista base)
    final ordenesBase = _ordenesBase;
    final ordenesUrgentes = _ordenesUrgentes;
    final ordenesAtrasadas = _ordenesAtrasadas;
    
    // Debug: Imprimir información de las órdenes
    print('🔍 [INICIAR RUTA] Total órdenes base: ${ordenesBase.length}');
    print('🔍 [INICIAR RUTA] Órdenes urgentes: ${ordenesUrgentes.length}');
    for (var orden in ordenesUrgentes) {
      print('   - Urgente: #${orden.numeroOrden}, esUrgente: ${orden.esUrgente}, recogerEnSucursal: ${orden.recogerEnSucursal}');
    }
    print('🔍 [INICIAR RUTA] Órdenes atrasadas: ${ordenesAtrasadas.length}');
    for (var orden in ordenesAtrasadas) {
      print('   - Atrasada: #${orden.numeroOrden}, estado: ${orden.estado}, fechaEstimada: ${orden.fechaEstimadaEntrega}, recogerEnSucursal: ${orden.recogerEnSucursal}');
    }
    
    // Debug: Mostrar todas las órdenes base
    print('🔍 [INICIAR RUTA] Todas las órdenes base:');
    for (var orden in ordenesBase) {
      print('   - Orden #${orden.numeroOrden}: estado=${orden.estado}, esUrgente=${orden.esUrgente}, recogerEnSucursal=${orden.recogerEnSucursal}, fechaEstimada=${orden.fechaEstimadaEntrega}');
    }
    
    // Contar total de prioritarias (evitando duplicados)
    final idsPrioritarias = <String>{};
    ordenesUrgentes.forEach((o) => idsPrioritarias.add(o.id));
    ordenesAtrasadas.forEach((o) => idsPrioritarias.add(o.id));
    final totalPrioritarias = idsPrioritarias.length;
    
    print('🔍 [INICIAR RUTA] Total prioritarias (sin duplicados): $totalPrioritarias');
    
    // Si hay órdenes prioritarias, mostrar modal de confirmación
    if (totalPrioritarias > 0) {
      print('✅ [INICIAR RUTA] Mostrando modal de prioridad');
      _mostrarModalPrioridad(ordenesUrgentes, ordenesAtrasadas);
    } else {
      print('ℹ️ [INICIAR RUTA] No hay prioritarias, iniciando ruta normal');
      // Si no hay prioritarias, iniciar ruta normalmente
      _iniciarRutaNormal();
    }
  }
  
  void _iniciarRutaNormal() async {
    print('🚀 Iniciando ruta normal (optimizada por distancia)...');
    
    // Obtener ubicación actual del repartidor
    if (_ubicacionRepartidor == null) {
      await _obtenerUbicacionRepartidor();
    }
    
    if (_ubicacionRepartidor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo obtener tu ubicación. Usando ordenamiento por defecto.'),
          backgroundColor: Color(0xFFFF9800),
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
          content: Text('Ruta optimizada por distancia: ${todasLasOrdenes.length} órdenes. Se entregarán las más cercanas primero.'),
          backgroundColor: const Color(0xFF4CAF50),
          duration: const Duration(seconds: 4),
        ),
      );
    }
    
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
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header con icono
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.priority_high,
                        color: Color(0xFFDC2626),
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Órdenes Prioritarias Detectadas',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2C2C2C),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Información de órdenes
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFFF9800),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (totalUrgentes > 0) ...[
                        Row(
                          children: [
                            const Icon(
                              Icons.warning,
                              color: Color(0xFFDC2626),
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$totalUrgentes ${totalUrgentes == 1 ? 'orden urgente' : 'órdenes urgentes'}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                          ],
                        ),
                        if (totalAtrasadas > 0) const SizedBox(height: 12),
                      ],
                      if (totalAtrasadas > 0) ...[
                        Row(
                          children: [
                            const Icon(
                              Icons.schedule,
                              color: Color(0xFFFF9800),
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$totalAtrasadas ${totalAtrasadas == 1 ? 'orden atrasada' : 'órdenes atrasadas'}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFFF9800),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        'Total: $totalPrioritarias ${totalPrioritarias == 1 ? 'orden prioritaria' : 'órdenes prioritarias'}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2C2C2C),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                
                // Descripción
                const Text(
                  '¿Cómo deseas proceder?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2C2C2C),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '• Entregar Primero: Optimiza la ruta para ir directo a las órdenes prioritarias. Si hay otras órdenes en el camino, se entregarán de paso.\n\n'
                  '• Seguir Ruta: Continúa con la ruta optimizada normal (por distancia).',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF666666),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                
                // Botones
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _iniciarRutaConPrioridad();
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(
                            color: Color(0xFFDC2626),
                            width: 2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Entregar Primero',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _iniciarRutaNormal();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF50),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Seguir Ruta',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
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
    
    // Intentar geocodificar
    try {
      String? paisOperacion;
      if (orden.tenantId != null) {
        try {
          paisOperacion = await PaisesService.obtenerPaisOperacion(orden.tenantId!);
        } catch (e) {
          print('⚠️ Error obteniendo país: $e');
        }
      }
      
      if (paisOperacion == null || paisOperacion.isEmpty) {
        try {
          paisOperacion = await PaisesService.obtenerPaisOperacionActual();
        } catch (e) {
          print('⚠️ Error obteniendo país actual: $e');
        }
      }
      
      String direccionCompleta = orden.direccionDestino;
      if (paisOperacion != null && paisOperacion.isNotEmpty) {
        if (!direccionCompleta.toLowerCase().contains(paisOperacion.toLowerCase())) {
          direccionCompleta = '$direccionCompleta, $paisOperacion';
        }
      }
      
      final locations = await locationFromAddress(direccionCompleta);
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
  
  void _iniciarRutaConPrioridad() async {
    print('🚀 Iniciando ruta con prioridad...');
    
    // Obtener ubicación actual del repartidor
    if (_ubicacionRepartidor == null) {
      await _obtenerUbicacionRepartidor();
    }
    
    if (_ubicacionRepartidor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo obtener tu ubicación. Usando ordenamiento por defecto.'),
          backgroundColor: Color(0xFFFF9800),
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
          backgroundColor: const Color(0xFFFF9800),
          duration: const Duration(seconds: 4),
        ),
      );
    }
    
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
      
      // Centrar mapa en la siguiente orden
      final siguienteOrden = _ordenActual;
      if (siguienteOrden != null) {
        final coordenadas = _obtenerCoordenadas(siguienteOrden);
        if (coordenadas != null) {
          _mapController.move(coordenadas, 15.0);
        }
      }
    } else {
      // Si ya está en la última orden, volver al inicio
      setState(() {
        _ordenActualIndex = 0;
      });
      
      // Centrar mapa en la primera orden
      if (_ordenesOrdenadas.isNotEmpty) {
        final primeraOrden = _ordenesOrdenadas.first;
        final coordenadas = _obtenerCoordenadas(primeraOrden);
        if (coordenadas != null) {
          _mapController.move(coordenadas, 15.0);
        }
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Volviendo al inicio de la ruta'),
          duration: Duration(seconds: 2),
        ),
      );
    }
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
              backgroundColor: Color(0xFF4CAF50),
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
        
        // Marcar la nueva orden como "EN REPARTO" si está en "EN TRANSITO"
        if (nuevaOrdenActual.estado == 'EN TRANSITO' || nuevaOrdenActual.estado == 'ATRASADO') {
          await _marcarOrdenComoEnReparto(nuevaOrdenActual);
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Avanzando a orden #${nuevaOrdenActual.numeroOrden} (${ordenesRestantes.length} restantes)'),
              duration: const Duration(seconds: 2),
              backgroundColor: const Color(0xFF4CAF50),
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
  
  // Recargar órdenes desde la base de datos
  Future<void> _recargarOrdenes() async {
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
              .single();
          
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

  Future<void> _abrirNavegacion(Orden orden) async {
    // Mostrar modal preguntando si va a iniciar la entrega o solo ver la ubicación
    if (orden.estado == 'EN TRANSITO' || orden.estado == 'ATRASADO') {
      final resultado = await showDialog<String>(
        context: context,
        builder: (ctx) => VolonexDialog(
          title: '¿Iniciar entrega?',
          leading: const Icon(Icons.navigation, color: AppColors.info, size: 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Orden #${orden.numeroOrden}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text('¿Vas a iniciar la entrega de este pedido ahora?'),
              const SizedBox(height: 8),
              Text(
                'Si solo deseas ver la ubicación sin iniciar la entrega, selecciona "Solo ver ubicación".',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.darkTextMuted,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop('solo_ver'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.darkTextMuted,
                side: const BorderSide(color: AppColors.darkBorder),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_on, size: 18),
                  SizedBox(width: 6),
                  Text('Solo ver ubicación'),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop('iniciar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.exito,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow, size: 18),
                  SizedBox(width: 6),
                  Text('Sí, iniciar entrega'),
                ],
              ),
            ),
          ],
        ),
      );
      
      // Si el usuario canceló el diálogo, no hacer nada
      if (resultado == null) return;
      
      // Si el usuario seleccionó "Sí, iniciar entrega", cambiar estado a "EN REPARTO"
      if (resultado == 'iniciar') {
        await _marcarOrdenComoEnReparto(orden);
        // Recargar la orden actualizada para reflejar el cambio
        await _recargarOrdenes();
      }
      // Si seleccionó "Solo ver ubicación", no cambiar el estado, solo continuar con la navegación
    }
    
    // Obtener coordenadas (de BD o geocodificadas)
    LatLng? coordenadas = _obtenerCoordenadas(orden);
    
    // Si no tiene coordenadas, intentar geocodificar primero
    if (coordenadas == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Obteniendo coordenadas...'),
          duration: Duration(seconds: 2),
        ),
      );
      
      try {
        // Obtener país de operación del tenant
        String? paisOperacion;
        if (orden.tenantId != null) {
          try {
            paisOperacion = await PaisesService.obtenerPaisOperacion(orden.tenantId!);
          } catch (e) {
            print('⚠️ Error obteniendo país: $e');
          }
        }
        
        // Si no se pudo obtener, intentar desde el usuario actual
        if (paisOperacion == null || paisOperacion.isEmpty) {
          try {
            paisOperacion = await PaisesService.obtenerPaisOperacionActual();
          } catch (e) {
            print('⚠️ Error obteniendo país del usuario: $e');
          }
        }
        
        // País por defecto si no se encontró
        final paisDefault = paisOperacion ?? 'Estados Unidos';
        
        // Construir dirección completa
        String direccionCompleta = orden.direccionDestino;
        if (orden.municipioDestino != null && orden.municipioDestino!.isNotEmpty) {
          direccionCompleta += ', ${orden.municipioDestino}';
        }
        if (orden.provinciaDestino != null && orden.provinciaDestino!.isNotEmpty) {
          direccionCompleta += ', ${orden.provinciaDestino}';
        }
        
        // Agregar país solo si no está especificado en la dirección
        final direccionLower = direccionCompleta.toLowerCase();
        final tienePais = direccionLower.contains('cuba') || 
                         direccionLower.contains('usa') ||
                         direccionLower.contains('united states') ||
                         direccionLower.contains('estados unidos') ||
                         direccionLower.contains('united states of america');
        
        if (!tienePais) {
          // Usar el país de operación del tenant, no hardcodear "Cuba"
          direccionCompleta += ', $paisDefault';
        }
        
        final locations = await locationFromAddress(direccionCompleta);
        if (locations.isNotEmpty) {
          final location = locations.first;
          coordenadas = LatLng(location.latitude, location.longitude);
          _coordenadasGeocodificadas[orden.id] = coordenadas;
          
          // Actualizar estado
          if (mounted) {
            setState(() {});
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se encontraron coordenadas para: $direccionCompleta')),
          );
          return;
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error obteniendo coordenadas: $e')),
        );
        return;
      }
    }

    // Ahora abrir navegación con las coordenadas
    // Intentar primero con Google Maps app (si está instalada)
    final googleMapsUrl = 'https://www.google.com/maps/dir/?api=1&destination=${coordenadas.latitude},${coordenadas.longitude}';
    // También preparar URL alternativa con formato geo:
    final geoUrl = 'geo:${coordenadas.latitude},${coordenadas.longitude}?q=${coordenadas.latitude},${coordenadas.longitude}';
    
    try {
      // Intentar con Google Maps URL primero
      final uri = Uri.parse(googleMapsUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Si no funciona, intentar con geo: URL
        final geoUri = Uri.parse(geoUrl);
        if (await canLaunchUrl(geoUri)) {
          await launchUrl(geoUri, mode: LaunchMode.externalApplication);
        } else {
          // Último intento: usar platformDefault
          await launchUrl(uri, mode: LaunchMode.platformDefault);
        }
      }
    } catch (e) {
      print('❌ Error abriendo navegación: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo abrir la navegación: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
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
        actions: [
          // Botón para centrar el mapa en la ubicación del repartidor
          if (_ubicacionRepartidor != null)
            IconButton(
              icon: const Icon(Icons.my_location, color: Colors.white),
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
        foregroundColor: Colors.white,
        actions: [
          // Botón para centrar el mapa en la ubicación del repartidor
          if (_ubicacionRepartidor != null)
            IconButton(
              icon: const Icon(Icons.my_location, color: Colors.white),
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
                (ordenesConCoordenadas.isNotEmpty 
                  ? _obtenerCoordenadas(ordenesConCoordenadas.first)!
                  : const LatLng(23.1136, -82.3666)), // Coordenadas por defecto (La Habana, Cuba)
              initialZoom: 12.0,
              minZoom: 10.0,
              maxZoom: 18.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.logiflowpro.app',
              ),
              
              // Línea desde el repartidor hasta la primera orden
              if (_ubicacionRepartidor != null && ordenesConCoordenadas.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [
                        _ubicacionRepartidor!,
                        _obtenerCoordenadas(ordenesConCoordenadas.first)!,
                      ],
                      strokeWidth: 4.0,
                      color: const Color(0xFF4CAF50), // Verde para la línea del camión
                      borderStrokeWidth: 2.0,
                      borderColor: Colors.white,
                    ),
                  ],
                ),
              
              // Marcador de ubicación del repartidor (camión)
              if (_ubicacionRepartidor != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _ubicacionRepartidor!,
                      width: 50,
                      height: 50,
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50), // Verde para el camión
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.local_shipping, color: Colors.white, size: 28),
                      ),
                    ),
                  ],
                ),
              
              // Marcadores de órdenes numeradas
              MarkerLayer(
                markers: ordenesConCoordenadas.asMap().entries
                  .where((entry) => _obtenerCoordenadas(entry.value) != null)
                  .map((entry) {
                    final index = entry.key;
                    final orden = entry.value;
                    final ordenRuta = orden.ordenRuta ?? (index + 1);
                    final coordenadas = _obtenerCoordenadas(orden)!;
                  
                  return Marker(
                    point: coordenadas,
                    width: 60,
                    height: 75, // Altura ajustada para incluir el icono de paquete arriba
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Icono de paquete arriba
                        Positioned(
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF9800), // Naranja para el paquete
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.inventory_2,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                        // Círculo con número de orden (más pequeño)
                        Positioned(
                          top: 25,
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _ordenActualIndex == index && _rutaIniciada
                                  ? const Color(0xFFFF9800) // Naranja para orden actual
                                  : const Color(0xFF1976D2), // Azul para otras órdenes
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.4),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Text(
                                '$ordenRuta',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
              
              // Línea de ruta conectando todas las órdenes (línea azul moderna)
              if (ordenesConCoordenadas.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: ordenesConCoordenadas
                        .map((orden) => _obtenerCoordenadas(orden))
                        .whereType<LatLng>()
                        .toList(),
                      strokeWidth: 5.0,
                      color: const Color(0xFF1976D2), // Azul moderno
                      borderStrokeWidth: 3.0,
                      borderColor: Colors.white,
                    ),
                  ],
                ),
            ],
          ),
          
          // Botones de zoom (+ y -) en la esquina superior derecha
          Positioned(
            top: 16,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Botón de zoom in (+)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        final currentZoom = _mapController.camera.zoom;
                        final newZoom = (currentZoom + 1).clamp(10.0, 18.0);
                        _mapController.move(_mapController.camera.center, newZoom);
                      },
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: Color(0xFFE0E0E0), width: 1),
                          ),
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Color(0xFF1976D2),
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                  // Botón de zoom out (-)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        final currentZoom = _mapController.camera.zoom;
                        final newZoom = (currentZoom - 1).clamp(10.0, 18.0);
                        _mapController.move(_mapController.camera.center, newZoom);
                      },
                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                      child: Container(
                        width: 48,
                        height: 48,
                        child: const Icon(
                          Icons.remove,
                          color: Color(0xFF1976D2),
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
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
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
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  
                  if (!_rutaIniciada) ...[
                    // Botón "Iniciar Ruta"
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text(
                            '${_ordenesOrdenadas.length} órdenes en la ruta optimizada',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2C2C2C),
                            ),
                          ),
                          // Debug: Mostrar información adicional
                          Builder(
                            builder: (context) {
                              final urgentes = _ordenesUrgentes.length;
                              final atrasadas = _ordenesAtrasadas.length;
                              final recogerEnSucursal = _ordenesRecogerEnSucursal.length;
                              if (urgentes > 0 || atrasadas > 0 || recogerEnSucursal > 0) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    'Urgentes: $urgentes | Atrasadas: $atrasadas | Recoger en sucursal: $recogerEnSucursal',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _iniciarRuta,
                            icon: const Icon(Icons.play_arrow, size: 24),
                            label: const Text(
                              'Iniciar Ruta',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4CAF50),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF9800),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'Orden ${_ordenActual!.ordenRuta ?? (_ordenActualIndex + 1)} de ${_ordenesOrdenadas.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '#${_ordenActual!.numeroOrden}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2C2C2C),
                                    ),
                                  ),
                                ],
                              ),
                              if (_ordenActual!.distanciaDesdeAnterior != null)
                                Text(
                                  '${_ordenActual!.distanciaDesdeAnterior!.toStringAsFixed(1)} km',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF666666),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _ordenActual!.direccionDestino,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF2C2C2C),
                            ),
                          ),
                          if (_ordenActual!.receptor.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Destinatario: ${_ordenActual!.receptor}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF666666),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          // Botón "Explorar Orden"
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => _explorarOrden(_ordenActual!),
                              icon: const Icon(Icons.info_outline, size: 18),
                              label: const Text('Explorar Orden'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF666666),
                                side: const BorderSide(color: Color(0xFF666666)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _abrirNavegacion(_ordenActual!),
                                  icon: const Icon(Icons.navigation, size: 18),
                                  label: const Text('Navegar'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF1976D2),
                                    side: const BorderSide(color: Color(0xFF1976D2)),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              // Botón "Entregado" solo si la orden está en "EN REPARTO"
                              if (_ordenActual!.estado == 'EN REPARTO')
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => _marcarComoEntregado(_ordenActual!),
                                    icon: const Icon(Icons.check_circle, size: 18),
                                    label: const Text('Entregar'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF4CAF50),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                )
                              else
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      // Si está en "POR ENVIAR", mostrar mensaje informativo
                                      if (_ordenActual!.estado == 'POR ENVIAR') {
                                        _mostrarMensajeOrdenNoDisponible();
                                      } else {
                                        // Para otros estados, también mostrar mensaje informativo
                                        _mostrarMensajeOrdenNoDisponible();
                                      }
                                    },
                                    icon: const Icon(Icons.check_circle, size: 18),
                                    label: Text(
                                      _ordenActual!.estado == 'EN TRANSITO' 
                                        ? 'Iniciar Entrega' 
                                        : 'No disponible',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.grey[400],
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _siguienteOrden,
                            icon: Icon(
                              _ordenActualIndex < _ordenesOrdenadas.length - 1 
                                ? Icons.arrow_forward 
                                : Icons.refresh,
                              size: 18,
                            ),
                            label: Text(
                              _ordenActualIndex < _ordenesOrdenadas.length - 1 
                                ? 'Siguiente Orden' 
                                : 'Volver al Inicio',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1976D2),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
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
                            color: Color(0xFF4CAF50),
                            size: 48,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            '¡Ruta Completada!',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4CAF50),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Has completado todas las ${_ordenesOrdenadas.length} órdenes',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF666666),
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

