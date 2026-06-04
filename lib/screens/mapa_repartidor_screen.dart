import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../main.dart';
import '../services/repartidor_pantallas_offline_service.dart';
import '../services/sync_service.dart';
import '../services/network_timeout.dart';
import '../models/orden.dart';
import '../widgets/profile_avatar.dart';
import '../config/app_colors.dart';

class MapaRepartidorScreen extends StatefulWidget {
  final Orden orden;

  const MapaRepartidorScreen({
    super.key,
    required this.orden,
  });

  @override
  State<MapaRepartidorScreen> createState() => _MapaRepartidorScreenState();
}

class _MapaRepartidorScreenState extends State<MapaRepartidorScreen> {
  final MapController _mapController = MapController();
  LatLng? _ubicacionRepartidor;
  bool _isLoading = true;
  String? _error;
  RealtimeChannel? _channelUbicaciones;
  Timer? _timerActualizacion;
  String? _repartidorId;
  String? _repartidorNombre;
  String? _fotoPerfilUrl;

  @override
  void initState() {
    super.initState();
    _cargarRepartidorId();
  }

  @override
  void dispose() {
    _timerActualizacion?.cancel();
    _channelUbicaciones?.unsubscribe();
    super.dispose();
  }

  Future<void> _cargarRepartidorId() async {
    try {
      // Determinar qué repartidor rastrear:
      // Si existe entregado_por y la orden está en reparto, rastrear al que está entregando
      // De lo contrario, rastrear al repartidor asignado originalmente
      String? nombreRepartidorARastrear;
      if (widget.orden.entregadoPor != null && 
          widget.orden.entregadoPor!.isNotEmpty &&
          widget.orden.estado == 'EN REPARTO') {
        nombreRepartidorARastrear = widget.orden.entregadoPor;
        print('📍 Rastreando repartidor que está entregando: $nombreRepartidorARastrear');
        print('📍 (Orden originalmente asignada a: ${widget.orden.repartidor})');
      } else if (widget.orden.repartidor != null && widget.orden.repartidor!.isNotEmpty) {
        nombreRepartidorARastrear = widget.orden.repartidor;
        print('📍 Rastreando repartidor asignado: $nombreRepartidorARastrear');
      }
      
      if (nombreRepartidorARastrear == null || nombreRepartidorARastrear.isEmpty) {
        setState(() {
          _error = 'No hay repartidor asignado a esta orden';
          _isLoading = false;
        });
        return;
      }

      _repartidorNombre = nombreRepartidorARastrear;

      // CRÍTICO: Obtener tenant_id de la orden para filtrar correctamente
      String? tenantIdOrden = widget.orden.tenantId;
      if (tenantIdOrden == null || tenantIdOrden.isEmpty) {
        // Si no hay tenant_id en la orden, intentar obtenerlo del usuario actual
        try {
          final user = supabase.auth.currentUser;
          if (user != null) {
            final userData = await supabase
                .from('usuarios')
                .select('tenant_id')
                .eq('auth_id', user.id)
                .maybeSingle();
            tenantIdOrden = userData?['tenant_id']?.toString();
          }
        } catch (e) {
          print('⚠️ Error obteniendo tenant_id: $e');
        }
      }

      // CRÍTICO: Filtrar por tenant_id para evitar mostrar repartidores de otras empresas
      var query = supabase
          .from('usuarios')
          .select('id, foto_perfil')
          .eq('nombre', nombreRepartidorARastrear)
          .eq('rol', 'REPARTIDOR');
      
      if (tenantIdOrden != null && tenantIdOrden.isNotEmpty) {
        query = query.eq('tenant_id', tenantIdOrden);
        print('🔒 Filtrando repartidor por tenant_id: $tenantIdOrden');
      } else {
        print('⚠️ No hay tenant_id disponible, búsqueda sin filtro de tenant (puede ser peligroso)');
      }
      
      final response = await query.limit(1).maybeSingle();

      if (response == null) {
        setState(() {
          _error = 'No se encontró el repartidor en la base de datos';
          _isLoading = false;
        });
        return;
      }

      _repartidorId = response['id'] as String?;
      _fotoPerfilUrl = response['foto_perfil'] as String?;

      if (_repartidorId == null) {
        setState(() {
          _error = 'No se pudo obtener el ID del repartidor';
          _isLoading = false;
        });
        return;
      }

      // Cargar ubicación inicial
      await _cargarUbicacionInicial();

      // Suscribirse a actualizaciones en tiempo real
      _suscribirseARealtime();

      // Configurar timer para actualizaciones periódicas (cada 5 segundos)
      _timerActualizacion = Timer.periodic(const Duration(seconds: 5), (_) {
        _cargarUbicacionActual();
      });
    } catch (e) {
      print('❌ Error cargando ID del repartidor: $e');
      setState(() {
        _error = 'Error al cargar información del repartidor: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _cargarUbicacionInicial() async {
    try {
      final cached = await RepartidorPantallasOfflineService.cargarUbicacionMapa(_repartidorId!);
      if (cached != null) {
        final ubicacion = LatLng(cached.lat, cached.lng);
        if (mounted) {
          setState(() {
            _ubicacionRepartidor = ubicacion;
            _isLoading = false;
            _error = SyncService().isOnline
                ? null
                : 'Sin conexión — última ubicación guardada';
          });
          _mapController.move(ubicacion, 15);
        }
        if (!SyncService().isOnline) return;
      }

      final response = await ejecutarConTimeout(
        supabase
            .from('ubicaciones_repartidores')
            .select('latitude, longitude, ubicacion_timestamp')
            .eq('repartidor_id', _repartidorId!)
            .order('ubicacion_timestamp', ascending: false)
            .limit(1)
            .maybeSingle(),
      );

      if (response != null &&
          response['latitude'] != null &&
          response['longitude'] != null) {
        await RepartidorPantallasOfflineService.guardarUbicacionMapa(
          _repartidorId!,
          lat: (response['latitude'] as num).toDouble(),
          lng: (response['longitude'] as num).toDouble(),
          timestamp: response['ubicacion_timestamp']?.toString(),
        );
        final ubicacion = LatLng(
          (response['latitude'] as num).toDouble(),
          (response['longitude'] as num).toDouble(),
        );
        
        setState(() {
          _ubicacionRepartidor = ubicacion;
          _isLoading = false;
        });

        // Centrar el mapa en la ubicación del repartidor después de un pequeño delay
        // para asegurar que el mapa esté inicializado
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && _ubicacionRepartidor != null) {
            _mapController.move(_ubicacionRepartidor!, 15.0);
          }
        });
      } else {
        setState(() {
          _error = SyncService().isOnline
              ? 'No hay ubicación disponible para este repartidor'
              : 'Sin conexión — no hay ubicación guardada en el dispositivo';
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ Error cargando ubicación inicial: $e');
      setState(() {
        _error = 'Error al cargar ubicación: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _cargarUbicacionActual() async {
    if (_repartidorId == null) return;
    if (!SyncService().isOnline) return;

    try {
      final response = await ejecutarConTimeout(
        supabase
            .from('ubicaciones_repartidores')
            .select('latitude, longitude, ubicacion_timestamp')
            .eq('repartidor_id', _repartidorId!)
            .order('ubicacion_timestamp', ascending: false)
            .limit(1)
            .maybeSingle(),
      );

      if (response != null &&
          response['latitude'] != null &&
          response['longitude'] != null) {
        final nuevaUbicacion = LatLng(
          (response['latitude'] as num).toDouble(),
          (response['longitude'] as num).toDouble(),
        );

        await RepartidorPantallasOfflineService.guardarUbicacionMapa(
          _repartidorId!,
          lat: nuevaUbicacion.latitude,
          lng: nuevaUbicacion.longitude,
          timestamp: response['ubicacion_timestamp']?.toString(),
        );

        if (mounted) {
          setState(() {
            _ubicacionRepartidor = nuevaUbicacion;
            _error = null;
          });

          if (_ubicacionRepartidor != null) {
            _mapController.move(_ubicacionRepartidor!, _mapController.camera.zoom);
          }
        }
      }
    } catch (e) {
      print('❌ Error actualizando ubicación: $e');
    }
  }

  void _suscribirseARealtime() {
    if (_repartidorId == null) return;
    if (!SyncService().isOnline) return;

    try {
      _channelUbicaciones = supabase
          .channel('ubicaciones_repartidor_${_repartidorId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'ubicaciones_repartidores',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'repartidor_id',
              value: _repartidorId,
            ),
            callback: (payload) {
              print('📍 Nueva ubicación recibida en tiempo real');
              final newRecord = payload.newRecord;
              if (newRecord != null && 
                  newRecord['latitude'] != null && 
                  newRecord['longitude'] != null) {
                final nuevaUbicacion = LatLng(
                  (newRecord['latitude'] as num).toDouble(),
                  (newRecord['longitude'] as num).toDouble(),
                );

                if (mounted) {
                  setState(() {
                    _ubicacionRepartidor = nuevaUbicacion;
                  });

                  // Actualizar posición del mapa suavemente
                  if (_ubicacionRepartidor != null) {
                    _mapController.move(_ubicacionRepartidor!, _mapController.camera.zoom);
                  }
                }
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'ubicaciones_repartidores',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'repartidor_id',
              value: _repartidorId,
            ),
            callback: (payload) {
              print('📍 Ubicación actualizada en tiempo real');
              final newRecord = payload.newRecord;
              if (newRecord != null && 
                  newRecord['latitude'] != null && 
                  newRecord['longitude'] != null) {
                final nuevaUbicacion = LatLng(
                  (newRecord['latitude'] as num).toDouble(),
                  (newRecord['longitude'] as num).toDouble(),
                );

                if (mounted) {
                  setState(() {
                    _ubicacionRepartidor = nuevaUbicacion;
                  });

                  // Actualizar posición del mapa suavemente
                  if (_ubicacionRepartidor != null) {
                    _mapController.move(_ubicacionRepartidor!, _mapController.camera.zoom);
                  }
                }
              }
            },
          )
          .subscribe();

      print('✅ Suscrito a actualizaciones de ubicación en tiempo real');
    } catch (e) {
      print('❌ Error suscribiéndose a Realtime: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF37474F),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ubicación: ',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            ProfileAvatar(
              fotoUrl: _fotoPerfilUrl,
              nombre: _repartidorNombre ?? widget.orden.repartidor ?? "Repartidor",
              radius: 18,
              backgroundColor: const Color(0xFF4CAF50),
              textColor: Colors.white,
              fontSize: 14,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _repartidorNombre ?? widget.orden.repartidor ?? "Repartidor",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (_ubicacionRepartidor != null)
            IconButton(
              icon: const Icon(Icons.my_location, color: Colors.white),
              onPressed: () {
                _mapController.move(_ubicacionRepartidor!, 15.0);
              },
              tooltip: 'Centrar en repartidor',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF4CAF50),
              ),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Color(0xFFDC2626),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFF666666),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _isLoading = true;
                            _error = null;
                          });
                          _cargarRepartidorId();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF50),
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : _ubicacionRepartidor == null
                  ? const Center(
                      child: Text(
                        'Esperando ubicación del repartidor...',
                        style: TextStyle(
                          fontSize: 16,
                          color: Color(0xFF666666),
                        ),
                      ),
                    )
                  : Stack(
                      children: [
                        FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: _ubicacionRepartidor!,
                            initialZoom: 15.0,
                            minZoom: 10.0,
                            maxZoom: 18.0,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.paqueteria.app',
                            ),
                            MarkerLayer(
                              markers: [
                                Marker(
                                  point: _ubicacionRepartidor!,
                                  width: 50,
                                  height: 50,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF2E7D32),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 3,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.3),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.local_shipping,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        // Indicador de actualización en tiempo real
                        Positioned(
                          top: 16,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF4CAF50),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'En tiempo real',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF2C2C2C),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Información de la orden
                        Positioned(
                          bottom: 16,
                          left: 16,
                          right: 16,
                          child: Card(
                            elevation: 4,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.info_outline,
                                        size: 20,
                                        color: Color(0xFF1976D2),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Orden #${widget.orden.numeroOrden}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF2C2C2C),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Destino: ${widget.orden.direccionDestino}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: Color(0xFF666666),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (widget.orden.receptor.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Para: ${widget.orden.receptor}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF666666),
                                      ),
                                    ),
                                  ],
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

