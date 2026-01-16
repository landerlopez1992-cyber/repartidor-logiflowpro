import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:convert';
import '../main.dart';
import '../models/orden.dart';
import '../services/email_service.dart';
import '../services/configuracion_service.dart';
import '../services/sync_service.dart';
import '../services/orden_cache_service.dart';
import '../services/offline_storage_service.dart';
import '../services/connectivity_assistant_service.dart';
import '../services/shorebird_service.dart';
import '../services/goodbarber_sync_service.dart';
import '../services/paises_service.dart';
import 'repartidor_perfil_screen.dart';
import 'chat_repartidor_lista_screen.dart';
import 'detalle_orden_screen.dart';
import 'notificaciones_repartidor_screen.dart';
import 'qr_scanner_fullscreen.dart';
import 'aviso_ubicacion_segundo_plano_screen.dart';
import 'aviso_ubicacion_destacado_screen.dart';
import 'ruta_optimizada_repartidor_screen.dart';
import '../config/app_colors.dart';

class RepartidorMobileScreen extends StatefulWidget {
  const RepartidorMobileScreen({super.key});

  @override
  State<RepartidorMobileScreen> createState() => _RepartidorMobileScreenState();
}

class _RepartidorMobileScreenState extends State<RepartidorMobileScreen> with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounceTimer; // Timer para debounce de búsqueda
  String _filtroEstado = 'ACTIVAS';
  String? _filtroRepartidor; // 'MÍAS' o null (todas) - solo para master
  List<Orden> _ordenes = [];
  bool _isLoading = true;
  String? _repartidorNombre;
  String? _fotoPerfilUrl;
  bool _fotoEntregaObligatoria = true; // Por defecto activado
  bool _esRepartidorMaster = false; // Indica si el repartidor es master
  String? _tipoRepartidor; // 'REPARTIDOR' o 'RECOLECTOR'
  bool _esRecolector = false; // Indica si es recolector
  int _mensajesNoLeidos = 0;
  RealtimeChannel? _channelNotificaciones;
  RealtimeChannel? _channelNotificacionesOrdenes;
  RealtimeChannel? _channelOrdenesNuevas;
  RealtimeChannel? _channelPagosAceptados;
  
  // Variables para notificaciones push
  FlutterLocalNotificationsPlugin? _localNotifications;
  int _notificacionesNoLeidas = 0;
  String? _repartidorId;
  Set<String> _notificacionesProcesadas = {}; // Trackear notificaciones ya procesadas
  Map<String, dynamic>? _notificacionGeneralBanner; // Notificación general para mostrar en banner
  
  // Variables para rastreo de ubicación
  StreamSubscription<Position>? _positionStreamSubscription;
  Timer? _timerUbicacion; // Timer para actualizar cada X segundos
  Timer? _timerVerificarNotificaciones; // Timer para verificar notificaciones periódicamente
  String? _tenantId;
  bool _rastreoTiempoReal = false;
  int _intervaloActualizacion = 30; // segundos
  String? _paisOperacion; // País de operación del tenant
  
  // Ubicación actual del repartidor para calcular distancias
  Position? _ubicacionActual;
  
  // Estado de conexión y sincronización
  bool _isOnline = true;
  int _operacionesPendientes = 0;
  
  // Configuración de recogida en sucursal
  bool _recogerEnSucursalSoloMaster = false; // Solo repartidores Master pueden ver órdenes de recogida en sucursal
  
  // Saldo del repartidor (pagos aceptados)
  double _saldo = 0.0;
  String _monedaSaldo = 'CUP';
  
  // Cache para órdenes filtradas (evitar recalcular en cada rebuild)
  List<Orden>? _ordenesFiltradasCache;
  String? _cacheKeyFiltradas; // Clave para invalidar caché cuando cambien las dependencias
  
  // Map para almacenar información de sucursales por orden ID
  Map<String, Map<String, dynamic>> _sucursalesInfo = {};
  
  // Verificar si hay órdenes que pueden mostrar ruta optimizada
  // Muestra el botón si hay 2+ órdenes en EN TRANSITO, EN REPARTO, ATRASADO
  // O remesas con recoger_en_sucursal = false en POR ENVIAR (entregas a domicilio)
  bool get _tieneRutaOptimizada {
    final ordenesOptimizables = _ordenesFiltradas.where((orden) {
      final estado = orden.estado.toUpperCase();
      
      // Excluir entregadas y canceladas
      if (estado == 'ENTREGADO' || estado == 'CANCELADA') {
        return false;
      }
      
      // Incluir órdenes en EN TRANSITO, EN REPARTO o ATRASADO
      if (estado == 'EN TRANSITO' || estado == 'EN REPARTO' || estado == 'ATRASADO') {
        return true;
      }
      
      // CRÍTICO: Incluir remesas con recoger_en_sucursal = false en POR ENVIAR
      // Estas remesas deben entregarse a domicilio y necesitan ruta optimizada
      if (orden.tieneRemesa && 
          estado == 'POR ENVIAR' && 
          orden.recogerEnSucursal == false) {
        return true;
      }
      
      // Incluir órdenes normales (no remesas) en POR ENVIAR
      // Estas órdenes también necesitan ruta optimizada si ya tienen repartidor asignado
      if (!orden.tieneRemesa && estado == 'POR ENVIAR') {
        return true;
      }
      
      return false;
    }).toList();
    
    final tieneRuta = ordenesOptimizables.length >= 2;
    
    print('🔍 Verificando ruta optimizada:');
    print('   - Total órdenes filtradas: ${_ordenesFiltradas.length}');
    print('   - Órdenes optimizables: ${ordenesOptimizables.length}');
    for (var orden in ordenesOptimizables) {
      print('     * Orden #${orden.numeroOrden}: estado=${orden.estado}, tieneRemesa=${orden.tieneRemesa}, recogerEnSucursal=${orden.recogerEnSucursal}');
    }
    print('   - Órdenes con orden_ruta: ${_ordenesFiltradas.where((o) => o.ordenRuta != null).length}');
    print('   - Mostrar botón: $tieneRuta');
    
    return tieneRuta;
  }

  // Mostrar pantalla de ruta optimizada
  void _mostrarRutaOptimizada() {
    // Obtener órdenes optimizables:
    // - EN TRANSITO, EN REPARTO o ATRASADO
    // - Remesas con recoger_en_sucursal = false en POR ENVIAR (entregas a domicilio)
    // - Órdenes normales en POR ENVIAR
    final ordenesOptimizables = _ordenesFiltradas.where((orden) {
      final estado = orden.estado.toUpperCase();
      
      // Excluir entregadas y canceladas
      if (estado == 'ENTREGADO' || estado == 'CANCELADA') {
        return false;
      }
      
      // Incluir órdenes en EN TRANSITO, EN REPARTO o ATRASADO
      if (estado == 'EN TRANSITO' || estado == 'EN REPARTO' || estado == 'ATRASADO') {
        return true;
      }
      
      // CRÍTICO: Incluir remesas con recoger_en_sucursal = false en POR ENVIAR
      // Estas remesas deben entregarse a domicilio y necesitan ruta optimizada
      if (orden.tieneRemesa && 
          estado == 'POR ENVIAR' && 
          orden.recogerEnSucursal == false) {
        return true;
      }
      
      // Incluir órdenes normales (no remesas) en POR ENVIAR
      // Estas órdenes también necesitan ruta optimizada si ya tienen repartidor asignado
      if (!orden.tieneRemesa && estado == 'POR ENVIAR') {
        return true;
      }
      
      return false;
    }).toList();
    
    if (ordenesOptimizables.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Se necesitan al menos 2 órdenes para mostrar la ruta optimizada')),
      );
      return;
    }
    
    // Si las órdenes no tienen orden_ruta, mantener el orden actual (ya ordenado por distancia)
    // Si tienen orden_ruta, ordenarlas por orden_ruta
    final ordenesOrdenadas = List<Orden>.from(ordenesOptimizables);
    ordenesOrdenadas.sort((a, b) {
      if (a.ordenRuta != null && b.ordenRuta != null) {
        return a.ordenRuta!.compareTo(b.ordenRuta!);
      }
      // Si no tienen orden_ruta, mantener el orden actual (ya ordenado por distancia)
      return 0;
    });
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RutaOptimizadaRepartidorScreen(
          ordenes: ordenesOrdenadas,
          repartidorNombre: _repartidorNombre ?? 'Repartidor',
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Usar listener con debounce para evitar que el teclado se cierre
    _searchController.addListener(_onSearchChanged);
    // Cargar datos de forma asíncrona sin bloquear el hilo principal
    Future.microtask(() async {
      await _obtenerNombreRepartidor();
      await _obtenerTenantId();
      await _cargarPaisOperacion(); // Cargar país de operación desde BD
      await _cargarConfiguracionFoto();
      await _cargarConfiguracionPrioridad(); // Cargar configuración de prioridad
      await _obtenerUbicacionActual(); // Obtener ubicación para ordenamiento por distancia
      await _cargarConfiguracionRastreo(); // Cargar configuración de rastreo
      await _cargarConfiguracionRecogidaSucursal(); // Cargar configuración de recogida en sucursal
      await _cargarOrdenes();
      await _cargarMensajesNoLeidos();
      await _inicializarNotificaciones();
      await _obtenerRepartidorId();
      await _cargarNotificacionesNoLeidas();
      await _cargarSaldo(); // Cargar saldo del repartidor
      _suscribirseANotificaciones();
      _suscribirseANotificacionesOrdenes();
      _suscribirseACambiosPagos(); // Suscribirse a cambios en solicitudes de pago
      _suscribirseAOrdenesNuevas(); // Suscribirse a órdenes nuevas asignadas
      _suscribirseAPagosAceptados(); // Suscribirse a pagos aceptados
      _iniciarVerificacionPeriodicaNotificaciones(); // Verificar notificaciones periódicamente como respaldo
      _verificarYActivarRastreo(); // CRÍTICO: Activar rastreo siempre que la app esté abierta (para indicador online/offline)
      _inicializarEstadoConexion(); // Inicializar estado de conexión
    });
  }
  
  // Inicializar estado de conexión y listeners
  void _inicializarEstadoConexion() async {
    print('🔄 ===== INICIALIZANDO ESTADO DE CONEXIÓN =====');
    final syncService = SyncService();
    
    // ✅ CRÍTICO: Inicializar SyncService si no está inicializado
    try {
      await syncService.initialize();
      print('✅ SyncService inicializado correctamente');
    } catch (e) {
      print('⚠️ Error inicializando SyncService: $e');
    }
    
    // Esperar a que SyncService se inicialice completamente
    await Future.delayed(const Duration(milliseconds: 1000));
    
    // Estado inicial
    _isOnline = syncService.isOnline;
    _operacionesPendientes = syncService.pendingOperationsCount;
    
    print('🔍 Estado inicial de conexión: ${_isOnline ? "Online" : "Offline"}');
    print('🔍 Operaciones pendientes: $_operacionesPendientes');
    
    // ⚠️ CRÍTICO: Si la app inicia offline, mostrar modal inmediatamente
    if (!_isOnline && mounted) {
      // Esperar un momento para que el UI se inicialice completamente
      await Future.delayed(const Duration(milliseconds: 2000));
      if (mounted) {
        print('⚠️ Asistente: App iniciada sin conexión - Mostrando modal offline');
        try {
          await ConnectivityAssistantService.showOfflineModal(context);
          print('✅ Modal offline mostrado correctamente');
        } catch (e) {
          print('❌ Error mostrando modal offline: $e');
        }
      }
    }
    
    // Variable para trackear el estado anterior
    bool wasOnline = _isOnline;
    
    // Escuchar cambios en conectividad
    print('👂 Agregando listener de conectividad...');
    syncService.addConnectivityListener((isOnline) async {
      print('📡 Listener activado - Estado: ${isOnline ? "Online" : "Offline"}');
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
        
        // Mostrar modal solo cuando hay un cambio de estado
        if (wasOnline != isOnline) {
          print('🔄 Cambio de estado detectado: ${wasOnline ? "Online" : "Offline"} → ${isOnline ? "Online" : "Offline"}');
          // Esperar un momento para que el UI se actualice
          await Future.delayed(const Duration(milliseconds: 800));
          
          if (!mounted) {
            print('⚠️ Widget no montado - No se mostrará modal');
            return;
          }
          
          if (isOnline) {
            // Se recuperó la conexión
            print('✅ Asistente: Conexión restaurada - Mostrando modal online');
            final pendingOps = syncService.pendingOperationsCount;
            print('📊 Operaciones pendientes: $pendingOps');
            
            // Crear función de sincronización REAL que se ejecutará en el modal
            Future<void> syncFunction() async {
              if (pendingOps > 0) {
                print('🔄 Iniciando sincronización REAL desde modal...');
                print('📊 Operaciones pendientes: $pendingOps');
                // ✅ SINCRONIZACIÓN REAL: Esperar a que termine realmente
                await syncService.syncPendingOperations();
                print('✅ Sincronización REAL completada');
              } else {
                // Esperar un momento para que el usuario vea el mensaje
                await Future.delayed(const Duration(milliseconds: 500));
              }
            }
            
            try {
              await ConnectivityAssistantService.showOnlineModal(
                context,
                pendingOps,
                onSyncComplete: syncFunction,
              );
              print('✅ Modal online mostrado correctamente');
            } catch (e) {
              print('❌ Error mostrando modal online: $e');
            }
            
            // Recargar órdenes después de cerrar el modal
            if (mounted) {
              _cargarOrdenes();
            }
          } else {
            // Se perdió la conexión
            print('⚠️ Asistente: Conexión perdida - Mostrando modal offline');
            try {
              await ConnectivityAssistantService.showOfflineModal(context);
              print('✅ Modal offline mostrado correctamente');
            } catch (e) {
              print('❌ Error mostrando modal offline: $e');
            }
          }
        }
        
        wasOnline = isOnline;
      }
    });
    
    // Verificar operaciones pendientes periódicamente
    Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final count = syncService.pendingOperationsCount;
      if (count != _operacionesPendientes) {
        setState(() {
          _operacionesPendientes = count;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchDebounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _channelNotificaciones?.unsubscribe();
    _channelNotificacionesOrdenes?.unsubscribe();
    _channelOrdenesNuevas?.unsubscribe();
    _channelPagosAceptados?.unsubscribe();
    _timerVerificarNotificaciones?.cancel();
    _positionStreamSubscription?.cancel();
    _timerUbicacion?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Recargar configuración, órdenes y notificaciones cuando la app vuelve a estar activa
      print('🔄 App resumida - Recargando configuración, órdenes y notificaciones...');
      _cargarConfiguracionPrioridad();
      _cargarOrdenes();
      _cargarMensajesNoLeidos();
      _cargarNotificacionesNoLeidas(); // CRÍTICO: Actualizar badge de notificaciones
      // CRÍTICO: Reactivar rastreo cuando la app vuelve a estar activa
      _verificarYActivarRastreo();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // NO detener el rastreo cuando la app está en segundo plano
      // Esto permite que el panel admin siga detectando que el repartidor está activo
      print('🔄 App en segundo plano - Rastreo GPS continuará');
    } else if (state == AppLifecycleState.detached) {
      // CRÍTICO: Detener INMEDIATAMENTE cuando la app está completamente cerrada
      // Esto permite que el panel admin detecte INSTANTÁNEAMENTE que el repartidor está offline
      print('🔄 App cerrada - Deteniendo rastreo GPS INMEDIATAMENTE');
      _detenerRastreoUbicacion();
    }
  }

  Future<void> _cargarConfiguracionFoto() async {
    try {
      final response = await supabase
          .from('configuracion_envios')
          .select('foto_entrega_obligatoria')
          .limit(1)
          .single();
      
      if (mounted) {
        setState(() {
          _fotoEntregaObligatoria = response['foto_entrega_obligatoria'] ?? true;
        });
      }
    } catch (e) {
      print('Error al cargar configuración de foto: $e');
      // Mantener el valor por defecto
    }
  }

  // Cargar país de operación desde la BD (sin hardcodear)
  Future<void> _cargarPaisOperacion() async {
    try {
      if (_tenantId != null) {
        final pais = await PaisesService.obtenerPaisOperacion(_tenantId!);
        if (mounted && pais != null && pais.isNotEmpty) {
          setState(() {
            _paisOperacion = pais;
          });
          print('🌍 País de operación cargado: $_paisOperacion');
        }
      } else {
        // Intentar obtener del usuario actual
        final paisActual = await PaisesService.obtenerPaisOperacionActual();
        if (mounted && paisActual != null && paisActual.isNotEmpty) {
          setState(() {
            _paisOperacion = paisActual;
          });
          print('🌍 País de operación cargado del usuario: $_paisOperacion');
        }
      }
    } catch (e) {
      print('⚠️ Error cargando país de operación: $e');
      // No usar fallback hardcodeado, dejar null
    }
  }

  // Obtener mensaje de orden bloqueada (sin hardcodear países)
  String _obtenerMensajeOrdenBloqueada() {
    final pais = _paisOperacion ?? 'el país de destino';
    return 'Orden bloqueada: Aún procesándose en la agencia, esperando ser enviada a $pais';
  }

  // Obtener mensaje de orden esperando recolección (sin hardcodear países)
  String _obtenerMensajeOrdenEsperandoRecoleccion(String? repartidorNombre) {
    final pais = _paisOperacion ?? 'el país de destino';
    final repartidor = repartidorNombre ?? 'repartidor asignado';
    return 'Orden esperando para ser recolectada por $repartidor cuando arriba a $pais';
  }


  Future<void> _obtenerNombreRepartidor() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        // ✅ FIX CRÍTICO OFFLINE: Intentar cargar desde caché primero
        try {
          final prefs = await SharedPreferences.getInstance();
          final cachedNombre = prefs.getString('cached_repartidor_nombre_${user.id}');
          final cachedMaster = prefs.getBool('cached_repartidor_master_${user.id}');
          final cachedTipo = prefs.getString('cached_repartidor_tipo_${user.id}');
          final cachedFoto = prefs.getString('cached_repartidor_foto_${user.id}');
          
          if (cachedNombre != null) {
            print('💾 Datos de repartidor cargados desde caché');
            setState(() {
              _repartidorNombre = cachedNombre;
              _fotoPerfilUrl = cachedFoto;
              _esRepartidorMaster = cachedMaster ?? false;
              _tipoRepartidor = cachedTipo ?? 'REPARTIDOR';
              _esRecolector = cachedTipo == 'RECOLECTOR';
            });
            
            // Verificar conexión para actualizar en segundo plano
            final syncService = SyncService();
            if (!syncService.isOnline) {
              print('📴 Sin conexión - Usando datos del caché');
              return; // Salir si no hay conexión
            }
            
            print('🔄 Actualizando datos en segundo plano...');
          }
        } catch (cacheError) {
          print('⚠️ Error cargando desde caché: $cacheError');
        }
        
        try {
          final response = await supabase
              .from('usuarios')
              .select('nombre, foto_perfil, repartidor_master, tipo_repartidor')
              .eq('auth_id', user.id)  // USAR auth_id en lugar de id
              .limit(1)
              .maybeSingle();
          
          if (response == null) {
            print('❌ No se encontró usuario con auth_id: ${user.id}');
            return;
          }
          
          final tipoRepartidor = response['tipo_repartidor'] as String? ?? 'REPARTIDOR';
          final nombre = response['nombre'] as String?;
          final foto = response['foto_perfil'] as String?;
          final esMaster = response['repartidor_master'] == true || 
                          response['repartidor_master'] == 'true' || 
                          response['repartidor_master'] == 1;
          
          // ✅ Guardar en caché para uso offline
          try {
            final prefs = await SharedPreferences.getInstance();
            if (nombre != null) await prefs.setString('cached_repartidor_nombre_${user.id}', nombre);
            await prefs.setBool('cached_repartidor_master_${user.id}', esMaster);
            await prefs.setString('cached_repartidor_tipo_${user.id}', tipoRepartidor);
            if (foto != null) await prefs.setString('cached_repartidor_foto_${user.id}', foto);
            print('💾 Datos de repartidor guardados en caché');
          } catch (cacheError) {
            print('⚠️ Error guardando en caché: $cacheError');
          }
          
          setState(() {
            _repartidorNombre = nombre;
            _fotoPerfilUrl = foto;
            _esRepartidorMaster = esMaster;
            _tipoRepartidor = tipoRepartidor;
            _esRecolector = tipoRepartidor == 'RECOLECTOR';
          });
          print('🔍 Repartidor Master: $_esRepartidorMaster');
          print('🔍 Tipo Repartidor: $_tipoRepartidor (Es Recolector: $_esRecolector)');
        } catch (e) {
          print('⚠️ Error obteniendo datos de Supabase: $e');
          // ✅ FIX CRÍTICO OFFLINE: Si falla y hay datos en caché, usarlos
          try {
            final prefs = await SharedPreferences.getInstance();
            final cachedNombre = prefs.getString('cached_repartidor_nombre_${user.id}');
            if (cachedNombre != null) {
              print('💾 Usando caché por error de conexión');
              final cachedMaster = prefs.getBool('cached_repartidor_master_${user.id}');
              final cachedTipo = prefs.getString('cached_repartidor_tipo_${user.id}');
              final cachedFoto = prefs.getString('cached_repartidor_foto_${user.id}');
              
              setState(() {
                _repartidorNombre = cachedNombre;
                _fotoPerfilUrl = cachedFoto;
                _esRepartidorMaster = cachedMaster ?? false;
                _tipoRepartidor = cachedTipo ?? 'REPARTIDOR';
                _esRecolector = cachedTipo == 'RECOLECTOR';
              });
              return;
            }
          } catch (cacheError) {
            print('❌ Error accediendo al caché: $cacheError');
          }
          
          // Si no encuentra por ID, intentar por email
          if (user.email != null) {
            try {
              final response = await supabase
                  .from('usuarios')
                  .select('nombre, foto_perfil, repartidor_master, tipo_repartidor')
                  .eq('email', user.email!)
                  .single();
              final tipoRepartidor = response['tipo_repartidor'] as String? ?? 'REPARTIDOR';
              setState(() {
                _repartidorNombre = response['nombre'];
                _fotoPerfilUrl = response['foto_perfil'];
                // Verificar si es repartidor master
                _esRepartidorMaster = response['repartidor_master'] == true || 
                                     response['repartidor_master'] == 'true' || 
                                     response['repartidor_master'] == 1;
                _tipoRepartidor = tipoRepartidor;
                _esRecolector = tipoRepartidor == 'RECOLECTOR';
              });
              print('🔍 Repartidor Master: $_esRepartidorMaster');
              print('🔍 Tipo Repartidor: $_tipoRepartidor (Es Recolector: $_esRecolector)');
            } catch (e2) {
            // Si tampoco encuentra por email, usar el email como nombre
            setState(() {
              _repartidorNombre = user.email?.split('@')[0] ?? 'Repartidor';
              _fotoPerfilUrl = null;
              _esRepartidorMaster = false;
              _tipoRepartidor = 'REPARTIDOR';
              _esRecolector = false;
            });
            }
          } else {
            // Si no hay email, usar nombre por defecto
            setState(() {
              _repartidorNombre = 'Repartidor';
              _fotoPerfilUrl = null;
              _esRepartidorMaster = false;
              _tipoRepartidor = 'REPARTIDOR';
              _esRecolector = false;
            });
          }
        }
      }
    } catch (e) {
      // print('Error al obtener nombre del repartidor: $e');
    }
  }

  Future<void> _cargarOrdenes({String? preservarOrdenId, String? preservarEstado}) async {
    try {
      print('');
      print('🔄 ========================================');
      print('🔄 INICIANDO CARGA DE ÓRDENES');
      print('🔄 ========================================');
      print('🔄 Es recolector: $_esRecolector');
      print('🔄 Es repartidor master: $_esRepartidorMaster');
      print('🔄 Tenant ID: $_tenantId');
      print('🔄 Repartidor nombre: $_repartidorNombre');
      
      // 🔍 DIAGNÓSTICO CRÍTICO: Verificar datos del repartidor desde la BD (solo si hay conexión)
      if (_esRepartidorMaster) {
        final syncService = SyncService();
        if (syncService.isOnline) {
          print('👑 [DIAGNÓSTICO MASTER] Repartidor marcado como MASTER - Verificando en BD...');
          try {
            final user = supabase.auth.currentUser;
            if (user != null) {
              final userData = await supabase
                  .from('usuarios')
                  .select('nombre, repartidor_master, tipo_repartidor, provincias_config')
                  .eq('auth_id', user.id)
                  .maybeSingle();
              
              if (userData != null) {
                final nombreBD = userData['nombre']?.toString() ?? 'N/A';
                final esMasterBD = userData['repartidor_master'] == true || 
                                  userData['repartidor_master'] == 'true' || 
                                  userData['repartidor_master'] == 1;
                final tipoBD = userData['tipo_repartidor']?.toString() ?? 'N/A';
                final provinciasConfig = userData['provincias_config'];
                
                print('   📋 Nombre en BD: $nombreBD');
                print('   📋 Es master en BD: $esMasterBD');
                print('   📋 Tipo en BD: $tipoBD');
                print('   📋 Provincias config: $provinciasConfig');
                
                if (esMasterBD != _esRepartidorMaster) {
                  print('   ⚠️ ⚠️ ⚠️ DISCREPANCIA: _esRepartidorMaster=$_esRepartidorMaster pero BD dice $esMasterBD ⚠️ ⚠️ ⚠️');
                  // Corregir el valor local
                  setState(() {
                    _esRepartidorMaster = esMasterBD;
                  });
                  print('   ✅ Corregido _esRepartidorMaster a $esMasterBD');
                }
              }
            }
          } catch (e) {
            final errorString = e.toString();
            // Solo mostrar error si no es un error de conexión
            if (!errorString.contains('Failed host lookup') && 
                !errorString.contains('SocketException') &&
                !errorString.contains('ClientException')) {
              print('   ❌ Error verificando datos del repartidor en BD: $e');
            } else {
              print('   📴 Sin conexión - Verificación de datos del repartidor omitida (modo offline)');
            }
          }
        } else {
          print('📴 Sin conexión - Verificación de datos del repartidor omitida (modo offline)');
        }
      }
      
      if (!mounted) return;
      
      // ✅ FIX CRÍTICO: Cargar INMEDIATAMENTE desde caché ANTES de mostrar loading
      // Esto asegura que si no hay internet, las tarjetas se muestren AL INSTANTE
      final syncService = SyncService();
      final ordenesCache = await OrdenCacheService.getCachedOrders();
      
      if (ordenesCache.isNotEmpty) {
        print('💾 ✅ Caché encontrado: ${ordenesCache.length} órdenes - Mostrando INMEDIATAMENTE');
        if (mounted) {
          setState(() {
            _ordenes = ordenesCache;
            _isLoading = false; // ✅ No mostrar loading si ya tenemos caché
            _ordenesFiltradasCache = null;
            _cacheKeyFiltradas = null;
          });
        }
        
        // Si hay conexión, intentar actualizar en segundo plano
        // Si NO hay conexión, simplemente usar el caché y terminar
        if (!syncService.isOnline) {
          print('📴 Sin conexión - Usando caché (${ordenesCache.length} órdenes)');
          return; // ✅ Salir temprano si no hay conexión
        }
        
        print('🔄 Hay conexión - Actualizando datos en segundo plano...');
        // Continuar con la carga desde Supabase pero SIN mostrar loading
        // porque ya tenemos datos en pantalla
      } else {
        // No hay caché, mostrar loading
        setState(() {
          _isLoading = true;
        });
      }

      final user = supabase.auth.currentUser;
      if (user == null) {
        print('❌ Usuario no autenticado');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // Obtener el nombre del repartidor (usar cache si ya lo tenemos)
      String? repartidorNombre = _repartidorNombre;
      
      if (repartidorNombre == null) {
        try {
          final repartidorResponse = await supabase
              .from('usuarios')
              .select('nombre')
              .eq('auth_id', user.id)  // USAR auth_id en lugar de id
              .limit(1)
              .maybeSingle();
          repartidorNombre = repartidorResponse?['nombre'] as String?;
        } catch (e) {
          // Si no encuentra el usuario por auth_id, intentar por email
          if (user.email != null) {
            try {
              final repartidorResponse = await supabase
                  .from('usuarios')
                  .select('nombre')
                  .eq('email', user.email!)
                  .single();
              repartidorNombre = repartidorResponse['nombre'] as String?;
            } catch (e2) {
              // Si tampoco encuentra por email, usar el email como nombre
              repartidorNombre = user.email?.split('@')[0] ?? 'Repartidor';
            }
          } else {
            // Si no hay email, usar nombre por defecto
            repartidorNombre = 'Repartidor';
          }
        }
      }

      if (repartidorNombre == null) {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // Verificar si el repartidor es master para decidir qué órdenes mostrar
      // Si es master: ver TODAS las órdenes del tenant
      // Si no es master: ver solo las órdenes asignadas a él
      
      // ✅ Ya verificamos conexión arriba, solo continuar si hay conexión
      // Si llegamos aquí y syncService.isOnline es true, actualizamos datos
      if (syncService.isOnline) {
        try {
          // 🔒 VALIDACIÓN CRÍTICA DE SEGURIDAD: Verificar que tenant_id existe
          // Si es null, NO cargar órdenes porque se mostrarían órdenes de TODOS los tenants
          if (_tenantId == null && (_esRepartidorMaster || _esRecolector)) {
            print('🚨 CRÍTICO: tenant_id es NULL - NO se pueden cargar órdenes sin filtro de tenant');
            print('🚨 Intentando obtener tenant_id nuevamente...');
            await _obtenerTenantId();
            
            if (_tenantId == null) {
              print('🚨 ERROR GRAVE: No se pudo obtener tenant_id - CANCELANDO carga de órdenes');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('⚠️ Error de seguridad: No se pudo verificar tu empresa. Por favor, cierra sesión e inicia sesión nuevamente.'),
                    backgroundColor: Color(0xFFDC2626),
                    duration: Duration(seconds: 5),
                  ),
                );
              }
              return; // NO continuar sin tenant_id
            }
          }
          
          // Limpiar información de sucursales anterior
          _sucursalesInfo.clear();
          
          // Incluir relación con destinatarios y sucursales para obtener provincias y municipios actualizados
          var query = supabase.from('ordenes').select('*, destinatarios!left(nombre, telefono, direccion, municipio, provincia, consejo_popular_batey), sucursales!left(nombre, direccion, municipio, provincia, pais, es_principal)');
          
          // Si es recolector, filtrar solo órdenes de tipo RECOGIDA
          if (_esRecolector) {
            print('📦 Recolector detectado - Cargando solo órdenes de RECOGIDA');
            query = query.eq('tipo_orden', 'RECOGIDA');
            query = query.eq('repartidor_nombre', repartidorNombre); // Filtro EXACTO
            
            // 🔒 OBLIGATORIO: Filtrar por tenant_id (ya validado arriba que no es null)
            query = query.eq('tenant_id', _tenantId!);
            
            print('📋 Filtro usado: tipo_orden = RECOGIDA, repartidor_nombre = "$repartidorNombre", tenant_id = "$_tenantId"');
          } else if (_esRepartidorMaster) {
            // Si es repartidor master (incluso si es local), mostrar TODAS las órdenes de ENVIO del tenant
            // IMPORTANTE: NO filtrar por tipo_orden porque las órdenes normales tienen tipo_orden = null
            // CRÍTICO: NO filtrar por repartidor_nombre - Masters ven TODAS las órdenes del tenant
            // CRÍTICO: INCLUIR remesas puras (tiene_remesa = true) explícitamente
            print('👑 Repartidor MASTER detectado (puede ser local) - Cargando TODAS las órdenes de ENVIO del tenant (incluyendo remesas puras)');
            print('👑 [MASTER] NO se filtra por repartidor_nombre - Masters ven TODAS las órdenes del tenant');
            
            // 🔒 OBLIGATORIO: Filtrar por tenant_id (ya validado arriba que no es null)
            query = query.eq('tenant_id', _tenantId!);
            
            print('📋 Filtro usado: tenant_id = "$_tenantId" (MASTER - todas las órdenes de envío y remesas puras, excluyendo RECOGIDA en código)');
            print('📋 IMPORTANTE: NO se filtra por repartidor_nombre para masters');
          } else {
            // Si NO es master ni recolector, filtrar solo por repartidor_nombre (comportamiento normal)
            // IMPORTANTE: También incluir órdenes "POR ENVIAR" con recoger_en_sucursal = true
            // porque estas órdenes deben mostrarse al repartidor para que pueda marcarlas como "LISTO PARA RECOGER"
            print('👤 Repartidor normal - Cargando órdenes de ENVIO asignadas y órdenes POR ENVIAR con recoger_en_sucursal');
            
            // Hacer dos consultas separadas y combinar los resultados
            List<dynamic> ordenesAsignadas = [];
            List<dynamic> ordenesPorEnviarRecogida = [];
            
            // 🔒 SEGURIDAD CRÍTICA: Para repartidores normales, tenant_id es OBLIGATORIO
            // NO se pueden mostrar órdenes sin filtro de tenant (riesgo de ver datos de otras empresas)
            if (_tenantId == null) {
              print('🚨 CRÍTICO: Repartidor normal sin tenant_id - CANCELANDO carga de órdenes por seguridad');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('⚠️ Error de seguridad: No se pudo verificar tu empresa. Por favor, cierra sesión e inicia sesión nuevamente.'),
                    backgroundColor: Color(0xFFDC2626),
                    duration: Duration(seconds: 5),
                  ),
                );
              }
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
              return; // NO continuar sin tenant_id
            }
            
            // Consulta 1: Órdenes asignadas al repartidor
            print('🔍 [CONSULTA 1] Buscando órdenes asignadas a: "$repartidorNombre"');
            print('🔍 [CONSULTA 1] Filtros: repartidor_nombre = "$repartidorNombre", tenant_id = "$_tenantId" (excluyendo RECOGIDA en código)');
            
            // IMPORTANTE: NO filtrar por tipo_orden porque las órdenes normales tienen tipo_orden = null
            // Cargar todas las órdenes asignadas y filtrar RECOGIDA después en código
            var queryAsignadas = supabase.from('ordenes')
                .select('*, destinatarios!left(nombre, telefono, direccion, municipio, provincia, consejo_popular_batey), sucursales!left(nombre, direccion, municipio, provincia, pais, es_principal)')
                .eq('repartidor_nombre', repartidorNombre);
            
            // 🔒 SEGURIDAD OBLIGATORIA: SIEMPRE filtrar por tenant_id para repartidores normales
            queryAsignadas = queryAsignadas.eq('tenant_id', _tenantId!);
            
            try {
              final todasOrdenesAsignadas = await queryAsignadas.limit(100);
              // Filtrar en código: excluir solo las de RECOGIDA (incluir null y ENVIO)
              // CRÍTICO: Filtrado según interruptor para órdenes de recogida en sucursal:
              // - Si interruptor ACTIVO: Solo Master puede verlas (repartidores normales NO)
              // - Si interruptor DESACTIVO: NADIE puede verlas (ni normales ni Master)
              ordenesAsignadas = todasOrdenesAsignadas.where((orden) {
                final tipoOrden = orden['tipo_orden']?.toString();
                final recogerEnSucursal = orden['recoger_en_sucursal'] == true;
                final repartidorOrden = orden['repartidor_nombre']?.toString();
                final tieneRepartidorAsignado = repartidorOrden != null && 
                                                repartidorOrden.isNotEmpty && 
                                                repartidorOrden != 'Sin asignar' &&
                                                repartidorOrden == repartidorNombre; // Esta orden está asignada a este repartidor
                
                // Excluir órdenes de RECOGIDA siempre
                if (tipoOrden == 'RECOGIDA') return false;
                
                // Si tiene recogida en sucursal, aplicar filtro según interruptor:
                if (recogerEnSucursal) {
                  // CRÍTICO: Si la orden tiene un repartidor asignado manualmente, ese repartidor SIEMPRE puede verla
                  // (independientemente del interruptor)
                  if (tieneRepartidorAsignado) {
                    return true; // El repartidor asignado manualmente puede verla
                  }
                  
                  // Si NO tiene repartidor asignado (está en "Ningún repartidor"):
                  if (!_recogerEnSucursalSoloMaster) {
                    // Interruptor DESACTIVO: NADIE ve estas órdenes (ni normales ni Master)
                    return false;
                  } else if (_recogerEnSucursalSoloMaster && !_esRepartidorMaster) {
                    // Interruptor ACTIVO pero repartidor NO es Master: No puede verla
                    return false;
                  }
                  // Interruptor ACTIVO y repartidor ES Master: Puede verla (continuar)
                }
                return true; // Incluir null y ENVIO (excepto recogida en sucursal según reglas anteriores)
              }).toList();
              print('📦 Órdenes asignadas cargadas: ${ordenesAsignadas.length} (excluyendo recogida en sucursal si interruptor activo: $_recogerEnSucursalSoloMaster)');
              if (ordenesAsignadas.isEmpty) {
                print('⚠️ [CONSULTA 1] No se encontraron órdenes. Verificando qué órdenes hay en la BD...');
                // DIAGNÓSTICO COMPLETO: Ver TODAS las órdenes del tenant primero
                try {
                  print('🔍 [DIAGNÓSTICO] Consulta 1: TODAS las órdenes del tenant (sin filtros)');
                  // 🔒 SEGURIDAD: tenant_id es OBLIGATORIO incluso en diagnósticos
                  if (_tenantId == null) {
                    print('⚠️ [DIAGNÓSTICO] tenant_id es null - Saltando diagnóstico por seguridad');
                  } else {
                    var queryTodas = supabase.from('ordenes').select('numero_orden, repartidor_nombre, tipo_orden, estado, tenant_id')
                        .eq('tenant_id', _tenantId!); // 🔒 OBLIGATORIO
                    final todasOrdenes = await queryTodas.limit(20);
                    print('   📊 Total de órdenes en el tenant: ${todasOrdenes.length}');
                    
                    if (todasOrdenes.isNotEmpty) {
                      print('   📋 Primeras órdenes encontradas:');
                      for (var ord in todasOrdenes) {
                        final numOrden = ord['numero_orden']?.toString() ?? 'N/A';
                        final tipoOrden = ord['tipo_orden']?.toString() ?? 'NULL';
                        final repNom = ord['repartidor_nombre']?.toString() ?? 'null';
                        final estado = ord['estado']?.toString() ?? 'N/A';
                        final tenantIdOrd = ord['tenant_id']?.toString() ?? 'N/A';
                        print('     - Orden #$numOrden: tipo_orden="$tipoOrden" (tipo: ${ord['tipo_orden'].runtimeType}), repartidor="$repNom", estado="$estado"');
                        
                        // Verificar si esta orden debería aparecer
                        final esEnvio = tipoOrden == 'ENVIO' || tipoOrden == 'NULL' || tipoOrden == 'N/A';
                        final nombreCoincide = repNom == repartidorNombre;
                        if (esEnvio && nombreCoincide) {
                          print('       ✅ Esta orden DEBERÍA aparecer (tipo_orden=$tipoOrden, nombre coincide)');
                        } else {
                          print('       ❌ Esta orden NO aparece porque:');
                          if (!esEnvio) print('         - tipo_orden="$tipoOrden" != "ENVIO"');
                          if (!nombreCoincide) print('         - repartidor_nombre="$repNom" != "$repartidorNombre"');
                        }
                      }
                    }
                    
                    // DIAGNÓSTICO 2: Buscar órdenes SIN filtro de tipo_orden para ver qué hay
                    print('🔍 [DIAGNÓSTICO] Consulta 2: Órdenes asignadas a "$repartidorNombre" SIN filtro de tipo_orden');
                    var querySinTipo = supabase.from('ordenes')
                        .select('numero_orden, repartidor_nombre, tipo_orden, estado, tenant_id')
                        .eq('repartidor_nombre', repartidorNombre)
                        .eq('tenant_id', _tenantId!); // 🔒 OBLIGATORIO
                    final ordenesSinTipo = await querySinTipo.limit(20);
                    print('   📊 Órdenes asignadas a "$repartidorNombre" (sin filtro tipo_orden): ${ordenesSinTipo.length}');
                    
                    if (ordenesSinTipo.isNotEmpty) {
                      print('   📋 Órdenes encontradas:');
                      for (var ord in ordenesSinTipo) {
                        final numOrden = ord['numero_orden']?.toString() ?? 'N/A';
                        final tipoOrden = ord['tipo_orden']?.toString() ?? 'NULL';
                        final estado = ord['estado']?.toString() ?? 'N/A';
                        print('     - Orden #$numOrden: tipo_orden="$tipoOrden", estado="$estado"');
                      }
                    }
                  }
                } catch (e) {
                  print('❌ [DEBUG] Error en diagnóstico: $e');
                }
              } else {
                for (var orden in ordenesAsignadas) {
                  print('   ✅ Orden #${orden['numero_orden']}: ${orden['id']}');
                }
              }
            } catch (e) {
              print('❌ [CONSULTA 1] Error: $e');
              ordenesAsignadas = [];
            }
            
            // Consulta 2: Órdenes "POR ENVIAR" con recoger_en_sucursal = true (del mismo tenant)
            // CRÍTICO: Visibilidad según interruptor:
            // - Si interruptor ON: Solo Master puede ver estas órdenes
            // - Si interruptor OFF: NADIE ve estas órdenes (ni normales ni Master)
            if (_tenantId != null) {
              // Solo buscar órdenes de recogida en sucursal si el interruptor está ACTIVO Y el repartidor es Master
              // Si el interruptor está DESACTIVO, nadie debe ver estas órdenes
              if (_recogerEnSucursalSoloMaster && _esRepartidorMaster) {
                print('🔍 [CONSULTA 2] Interruptor ACTIVO y repartidor es Master - Buscando órdenes POR ENVIAR con recoger_en_sucursal = true para tenant: $_tenantId');
                try {
                  // IMPORTANTE: NO filtrar por tipo_orden porque las órdenes normales tienen tipo_orden = null
                  var queryPorEnviar = supabase.from('ordenes')
                      .select('*, destinatarios!left(nombre, telefono, direccion, municipio, provincia, consejo_popular_batey), sucursales!left(nombre, direccion, municipio, provincia, pais, es_principal)')
                      .eq('tenant_id', _tenantId!)
                      .eq('estado', 'POR ENVIAR')
                      .eq('recoger_en_sucursal', true)
                      .limit(100);
                  final todasOrdenesPorEnviar = await queryPorEnviar;
                  // Filtrar en código: excluir solo las de RECOGIDA (incluir null y ENVIO)
                  // Y solo incluir órdenes sin repartidor asignado (repartidor_nombre = null o 'Sin asignar')
                  ordenesPorEnviarRecogida = todasOrdenesPorEnviar.where((orden) {
                    final tipoOrden = orden['tipo_orden']?.toString();
                    final repartidorNombre = orden['repartidor_nombre']?.toString();
                    // Excluir órdenes de RECOGIDA
                    if (tipoOrden == 'RECOGIDA') return false;
                    // Solo incluir órdenes sin repartidor asignado (en "Ningún repartidor")
                    if (repartidorNombre != null && repartidorNombre.isNotEmpty && repartidorNombre != 'Sin asignar') {
                      return false; // Esta orden tiene repartidor asignado, no debe aparecer
                    }
                    return true; // Incluir órdenes sin repartidor (null, vacío, o "Sin asignar")
                  }).toList();
                  print('📦 Órdenes POR ENVIAR con recoger_en_sucursal cargadas (solo Master): ${ordenesPorEnviarRecogida.length}');
                  if (ordenesPorEnviarRecogida.isEmpty) {
                    print('⚠️ [CONSULTA 2] No se encontraron órdenes POR ENVIAR con recoger_en_sucursal = true');
                  } else {
                    for (var orden in ordenesPorEnviarRecogida) {
                      print('   ✅ Orden #${orden['numero_orden']}: ${orden['id']}, estado: ${orden['estado']}, recoger_en_sucursal: ${orden['recoger_en_sucursal']}, repartidor_nombre: ${orden['repartidor_nombre']}');
                    }
                  }
                } catch (e) {
                  print('❌ [CONSULTA 2] Error: $e');
                  ordenesPorEnviarRecogida = [];
                }
              } else if (!_recogerEnSucursalSoloMaster) {
                // Interruptor DESACTIVO: NADIE ve las órdenes de recogida en sucursal (ni normales ni Master)
                print('⚠️ [CONSULTA 2] Interruptor "solo Master" está DESACTIVO - NADIE ve órdenes de recogida en sucursal (solo empleados/admin)');
                ordenesPorEnviarRecogida = [];
              } else {
                // Interruptor ACTIVO pero repartidor NO es Master: No puede ver órdenes de recogida en sucursal
                print('⚠️ [CONSULTA 2] Interruptor "solo Master" está ACTIVO pero repartidor NO es Master - NO puede ver órdenes de recogida en sucursal');
                ordenesPorEnviarRecogida = [];
              }
            } else {
              print('⚠️ No se puede buscar órdenes POR ENVIAR: tenant_id es null');
            }
            
            // Combinar ambas listas y eliminar duplicados (por ID)
            // IMPORTANTE: Convertir todos los IDs a String de manera consistente
            final Map<String, dynamic> ordenesUnicas = {};
            for (var orden in ordenesAsignadas) {
              final ordenId = orden['id']?.toString() ?? orden['id'].toString();
              ordenesUnicas[ordenId] = orden;
            }
            print('📦 Órdenes asignadas agregadas al mapa: ${ordenesUnicas.length}');
            for (var orden in ordenesPorEnviarRecogida) {
              final ordenId = orden['id']?.toString() ?? orden['id'];
              if (ordenesUnicas.containsKey(ordenId)) {
                print('⚠️ Orden ${orden['numero_orden']} (${ordenId}) ya existe en asignadas, se sobrescribe');
              }
              ordenesUnicas[ordenId] = orden; // Esto sobrescribirá si hay duplicado (mismo ID)
            }
            print('📦 Total de órdenes después de agregar POR ENVIAR: ${ordenesUnicas.length}');
            
            final response = ordenesUnicas.values.toList();
            print('📦 Total de órdenes únicas después de combinar: ${response.length}');
            
            final ordenesCargadas = response
                .map((ordenData) {
                  try {
                    // Extraer información de sucursal si existe
                    if (ordenData['sucursales'] != null && ordenData['sucursales'] is List && (ordenData['sucursales'] as List).isNotEmpty) {
                      final sucursalData = (ordenData['sucursales'] as List).first;
                      final ordenId = ordenData['id']?.toString() ?? '';
                      if (ordenId.isNotEmpty) {
                        _sucursalesInfo[ordenId] = sucursalData as Map<String, dynamic>;
                      }
                    }
                    
                    final orden = Orden.fromJson(ordenData);
                    
                    // 🔍 DETECTAR CAMBIOS: Si la orden está en "LISTO PARA RECOGER" pero ya no tiene recoger_en_sucursal = true,
                    // cambiar el estado de vuelta a "EN REPARTO" (esto sucede cuando el admin quita recoger_en_sucursal desde la web)
                    if (orden.estado == 'LISTO PARA RECOGER' && !orden.recogerEnSucursal) {
                      print('⚠️ DETECCIÓN DE CAMBIO: Orden #${orden.numeroOrden} está en "LISTO PARA RECOGER" pero recoger_en_sucursal es false');
                      print('   Cambiando estado de vuelta a "EN REPARTO"');
                      
                      // Actualizar en BD de forma asíncrona (no esperar para no bloquear la carga)
                      supabase
                          .from('ordenes')
                          .update({'estado': 'EN REPARTO'})
                          .eq('id', orden.id)
                          .then((_) async {
                            print('✅ Estado cambiado exitosamente a "EN REPARTO" para orden #${orden.numeroOrden}');
                            // Sincronizar con GoodBarber si la orden está vinculada
                            try {
                              await GoodBarberSyncService.sincronizarEstadoAGoodBarber(
                                supabase,
                                orden.id,
                                'EN REPARTO',
                              );
                            } catch (e) {
                              print('⚠️ Error sincronizando estado con GoodBarber: $e');
                            }
                          })
                          .catchError((e) {
                            print('❌ Error al cambiar estado para orden #${orden.numeroOrden}: $e');
                          });
                      
                      // Actualizar el estado localmente en el objeto orden
                      orden.estado = 'EN REPARTO';
                    }
                    
                    return orden;
                  } catch (e) {
                    print('❌ Error parseando orden: $e');
                    print('   Datos: $ordenData');
                    rethrow;
                  }
                })
                .where((orden) => !orden.pagada) // Filtrar órdenes pagadas (se ocultan del repartidor)
                .toList();
            
            print('📦 Órdenes cargadas (sin pagadas): ${ordenesCargadas.length}');
            for (var orden in ordenesCargadas) {
              print('   - Orden #${orden.numeroOrden}: estado=${orden.estado}, recogerEnSucursal=${orden.recogerEnSucursal}, tipoOrden=${orden.tipoOrden}');
            }
            
            // Continuar con el procesamiento de órdenes...
            if (preservarOrdenId != null && preservarEstado != null) {
              final index = ordenesCargadas.indexWhere((o) => o.id == preservarOrdenId);
              if (index != -1) {
                ordenesCargadas[index].estado = preservarEstado;
                print('✅ Estado preservado para orden $preservarOrdenId: $preservarEstado');
              }
            }
            
            // 🔒 CRÍTICO: Guardar en caché local Y usar la lista fusionada retornada
            final ordenesFusionadas = await OrdenCacheService.cacheOrders(ordenesCargadas);
            
            if (mounted) {
            setState(() {
              // 🔒 USAR la lista fusionada en lugar de la lista de Supabase directamente
              _ordenes = ordenesFusionadas;
              _isLoading = false;
              _ordenesFiltradasCache = null; // Invalidar caché cuando cambien las órdenes
              _cacheKeyFiltradas = null;
            });
            }
            return; // Salir temprano para este caso
          }
          
          // Para recolectores y repartidores master, continuar con la consulta original
          final response = await query
              .limit(100); // Aumentar límite para incluir entregadas

          // 🔍 DIAGNÓSTICO: Verificar remesas puras en la respuesta
          if (_esRepartidorMaster) {
            print('🔍 [DIAGNÓSTICO MASTER] Verificando remesas puras en la respuesta...');
            int remesasPurasEncontradas = 0;
            int remesasConPeso = 0;
            int remesasConItems = 0;
            
            // Buscar específicamente la orden #2152
            bool orden2152Encontrada = false;
            
            for (var ordenData in response) {
              final numeroOrden = ordenData['numero_orden']?.toString() ?? 'N/A';
              final numeroRemesa = ordenData['numero_remesa']?.toString() ?? ordenData['numero_orden']?.toString();
              
              // Buscar orden #2152 específicamente
              if (numeroOrden == '2152' || numeroRemesa == '2152' || numeroOrden.contains('2152') || (numeroRemesa != null && numeroRemesa.contains('2152'))) {
                orden2152Encontrada = true;
                print('🔍 [DIAGNÓSTICO] ⚠️ ORDEN #2152 ENCONTRADA EN RESPUESTA BD:');
                print('   - numero_orden: $numeroOrden');
                print('   - numero_remesa: $numeroRemesa');
                print('   - tiene_remesa: ${ordenData['tiene_remesa']}');
                print('   - estado: ${ordenData['estado']}');
                print('   - pagada: ${ordenData['pagada']}');
                print('   - tipo_orden: ${ordenData['tipo_orden']}');
                print('   - repartidor_nombre: ${ordenData['repartidor_nombre']}');
                print('   - tenant_id: ${ordenData['tenant_id']}');
              }
              
              final tieneRemesa = ordenData['tiene_remesa'] == true;
              if (tieneRemesa) {
                final peso = (ordenData['peso'] as num?)?.toDouble() ?? 0.0;
                final itemsAdicionales = ordenData['items_adicionales'];
                final tieneItemsAdicionales = itemsAdicionales != null && 
                                             itemsAdicionales is List && 
                                             (itemsAdicionales as List).isNotEmpty;
                final esRemesaPura = peso <= 0 && !tieneItemsAdicionales;
                final pagada = ordenData['pagada'] == true;
                
                if (esRemesaPura) {
                  remesasPurasEncontradas++;
                  print('   ✅ Remesa pura encontrada: #$numeroOrden (numeroRemesa: $numeroRemesa, peso=$peso, items=$tieneItemsAdicionales, pagada=$pagada, estado=${ordenData['estado']})');
                } else {
                  if (peso > 0) remesasConPeso++;
                  if (tieneItemsAdicionales) remesasConItems++;
                  print('   📦 Remesa con envío: #$numeroOrden (numeroRemesa: $numeroRemesa, peso=$peso, items=$tieneItemsAdicionales)');
                }
              }
            }
            
            if (!orden2152Encontrada) {
              print('⚠️ [DIAGNÓSTICO] Orden #2152 NO encontrada en la respuesta de la BD');
              print('   - Total registros en respuesta: ${response.length}');
              // Listar todos los números de orden para debugging
              final todosNumerosOrden = response.map((o) => o['numero_orden']?.toString() ?? 'N/A').toList();
              final numeros215x = todosNumerosOrden.where((n) => n.contains('215')).toList();
              print('   - Órdenes que contienen "215": $numeros215x');
              if (numeros215x.isEmpty) {
                print('   - Primeras 10 órdenes en respuesta: ${todosNumerosOrden.take(10).toList()}');
              }
            }
            
            print('📊 [DIAGNÓSTICO MASTER] Total remesas puras en BD: $remesasPurasEncontradas');
            print('📊 [DIAGNÓSTICO MASTER] Total remesas con peso: $remesasConPeso');
            print('📊 [DIAGNÓSTICO MASTER] Total remesas con items: $remesasConItems');
          }

          final ordenesCargadas = (response as List)
              .map((ordenData) {
                // Extraer información de sucursal si existe
                if (ordenData['sucursales'] != null && ordenData['sucursales'] is List && (ordenData['sucursales'] as List).isNotEmpty) {
                  final sucursalData = (ordenData['sucursales'] as List).first;
                  final ordenId = ordenData['id']?.toString() ?? '';
                  if (ordenId.isNotEmpty) {
                    _sucursalesInfo[ordenId] = sucursalData as Map<String, dynamic>;
                  }
                }
                
                final orden = Orden.fromJson(ordenData);
                
                // Debug: Verificar campos de ruta optimizada
                if (ordenData['orden_ruta'] != null) {
                  print('✅ Orden #${orden.numeroOrden} tiene orden_ruta: ${ordenData['orden_ruta']}, orden.ordenRuta: ${orden.ordenRuta}');
                }
                
                // 🔍 DETECTAR CAMBIOS: Si la orden está en "LISTO PARA RECOGER" pero ya no tiene recoger_en_sucursal = true,
                // cambiar el estado de vuelta a "EN REPARTO" (esto sucede cuando el admin quita recoger_en_sucursal desde la web)
                if (orden.estado == 'LISTO PARA RECOGER' && !orden.recogerEnSucursal) {
                  print('⚠️ DETECCIÓN DE CAMBIO: Orden #${orden.numeroOrden} está en "LISTO PARA RECOGER" pero recoger_en_sucursal es false');
                  print('   Cambiando estado de vuelta a "EN REPARTO"');
                  
                  // Actualizar en BD de forma asíncrona (no esperar para no bloquear la carga)
                  supabase
                      .from('ordenes')
                      .update({'estado': 'EN REPARTO'})
                      .eq('id', orden.id)
                      .then((_) async {
                        print('✅ Estado cambiado exitosamente a "EN REPARTO" para orden #${orden.numeroOrden}');
                        // Sincronizar con GoodBarber si la orden está vinculada
                        try {
                          await GoodBarberSyncService.sincronizarEstadoAGoodBarber(
                            supabase,
                            orden.id,
                            'EN REPARTO',
                          );
                        } catch (e) {
                          print('⚠️ Error sincronizando estado con GoodBarber: $e');
                        }
                      })
                      .catchError((e) {
                        print('❌ Error al cambiar estado para orden #${orden.numeroOrden}: $e');
                      });
                  
                  // Actualizar el estado localmente en el objeto orden
                  orden.estado = 'EN REPARTO';
                }
                
                return orden;
              })
              .where((orden) {
                // Para repartidores master, excluir órdenes de RECOGIDA (mantener null y ENVIO)
                if (_esRepartidorMaster && orden.tipoOrden == 'RECOGIDA') {
                  return false;
                }
                
                // CRÍTICO: Para repartidores master, INCLUIR explícitamente remesas puras
                // Remesa pura = tiene_remesa = true, peso = 0 o null, sin items adicionales
                if (_esRepartidorMaster && orden.tieneRemesa) {
                  final peso = orden.peso ?? 0.0;
                  final tieneItemsAdicionales = orden.itemsAdicionales != null && 
                                                orden.itemsAdicionales is List && 
                                                (orden.itemsAdicionales as List).isNotEmpty;
                  final esRemesaPura = peso <= 0 && !tieneItemsAdicionales;
                  
                  if (esRemesaPura) {
                    // Es remesa pura - SIEMPRE incluirla para masters (sin importar pagada)
                    print('✅ [FILTRO MASTER] Remesa pura detectada: #${orden.numeroOrden} - INCLUIDA');
                    return true;
                  }
                }
                
                // CRÍTICO: Filtrado de órdenes de recogida en sucursal según interruptor:
                // - Si interruptor ACTIVO: Master puede verlas
                // - Si interruptor DESACTIVO: NADIE puede verlas (ni Master)
                if (orden.recogerEnSucursal) {
                  if (!_recogerEnSucursalSoloMaster) {
                    // Interruptor DESACTIVO: NADIE ve estas órdenes (ni Master)
                    print('⚠️ [FILTRO MASTER] Orden #${orden.numeroOrden} con recoger_en_sucursal = true pero interruptor DESACTIVO - Excluyendo (NADIE la ve)');
                    return false;
                  }
                  // Interruptor ACTIVO: Master puede verla (continuar)
                }
                
                // Filtrar órdenes pagadas (se ocultan del repartidor)
                // EXCEPCIÓN: Para masters, las remesas puras SIEMPRE se muestran (ya procesadas arriba)
                return !orden.pagada;
              })
              .toList();
          
          print('📦 Órdenes cargadas: ${ordenesCargadas.length} (excluyendo ${(response as List).length - ordenesCargadas.length} pagadas)');
          
          // 🔍 DIAGNÓSTICO FINAL: Contar remesas puras incluidas
          if (_esRepartidorMaster) {
            final remesasPurasIncluidas = ordenesCargadas.where((orden) {
              if (!orden.tieneRemesa) return false;
              final peso = orden.peso ?? 0.0;
              final tieneItemsAdicionales = orden.itemsAdicionales != null && 
                                            orden.itemsAdicionales is List && 
                                            (orden.itemsAdicionales as List).isNotEmpty;
              return peso <= 0 && !tieneItemsAdicionales;
            }).toList();
            print('✅ [DIAGNÓSTICO MASTER] Remesas puras INCLUIDAS en la lista final: ${remesasPurasIncluidas.length}');
            for (var remesa in remesasPurasIncluidas) {
              final numeroRemesa = remesa.numeroRemesa ?? remesa.numeroOrden;
              print('   ✅ Remesa pura: #$numeroRemesa (numeroOrden: #${remesa.numeroOrden}) - estado: ${remesa.estado}, pagada: ${remesa.pagada}, repartidor: ${remesa.repartidor ?? "Sin asignar"}');
            }
            
            // Verificar específicamente la remesa #2152 si existe
            final remesa2152 = ordenesCargadas.where((orden) {
              final numOrden = orden.numeroOrden?.toString() ?? '';
              final numRemesa = orden.numeroRemesa?.toString() ?? '';
              return numOrden == '2152' || numRemesa == '2152';
            }).toList();
            
            if (remesa2152.isNotEmpty) {
              print('✅ [DIAGNÓSTICO] Remesa #2152 ENCONTRADA en ordenesCargadas:');
              for (var r in remesa2152) {
                print('   - numeroOrden: ${r.numeroOrden}');
                print('   - numeroRemesa: ${r.numeroRemesa ?? "null"}');
                print('   - tieneRemesa: ${r.tieneRemesa}');
                print('   - estado: ${r.estado}');
                print('   - pagada: ${r.pagada}');
                print('   - tipoOrden: ${r.tipoOrden}');
              }
            } else {
              print('⚠️ [DIAGNÓSTICO] Remesa #2152 NO ENCONTRADA en ordenesCargadas');
              print('   - Total órdenes cargadas: ${ordenesCargadas.length}');
              // Buscar todas las remesas que tienen 2152 en algún campo
              final todasRemesas = ordenesCargadas.where((o) => o.tieneRemesa).toList();
              print('   - Total remesas (con o sin envío): ${todasRemesas.length}');
              for (var r in todasRemesas) {
                print('     - Remesa: #${r.numeroRemesa ?? r.numeroOrden} (numeroOrden: ${r.numeroOrden})');
              }
            }
          }
          
            // Si estamos preservando el estado de una orden específica, actualizarla
          if (preservarOrdenId != null && preservarEstado != null) {
            final index = ordenesCargadas.indexWhere((o) => o.id == preservarOrdenId);
            if (index != -1) {
              // Simplemente actualizar el estado de la orden existente
              ordenesCargadas[index].estado = preservarEstado;
              print('✅ Estado preservado para orden $preservarOrdenId: $preservarEstado');
            }
          }
          
          // 🔒 CRÍTICO: Guardar en caché local Y usar la lista fusionada retornada
          // que ya tiene los cambios locales preservados
          final ordenesFusionadas = await OrdenCacheService.cacheOrders(ordenesCargadas);

          if (mounted) {
            setState(() {
              // 🔒 USAR la lista fusionada en lugar de la lista de Supabase directamente
              _ordenes = ordenesFusionadas;
              _isLoading = false;
              _ordenesFiltradasCache = null; // Invalidar caché cuando cambien las órdenes
              _cacheKeyFiltradas = null;
            });
            // Verificar y activar rastreo si hay órdenes en "EN REPARTO"
            _verificarYActivarRastreo();
          }

          print('✅ Órdenes cargadas desde Supabase: ${ordenesCargadas.length}');
        } catch (e) {
          print('⚠️ Error cargando desde Supabase: $e');
          // Si ya tenemos datos en caché (cargados al inicio), no hacer nada más
          // Si NO teníamos datos en caché, cargar ahora
          if (_ordenes.isEmpty) {
            print('📴 No había caché al inicio, cargando ahora...');
            final ordenesCache = await OrdenCacheService.getCachedOrders();
            if (mounted) {
              setState(() {
                _ordenes = ordenesCache;
                _isLoading = false;
              });
              // Verificar y activar rastreo si hay órdenes en "EN REPARTO"
              _verificarYActivarRastreo();
            }
            _mostrarMensaje('⚠️ Sin conexión - Mostrando órdenes en caché');
          } else {
            print('✅ Ya teníamos datos en caché, no es necesario recargar');
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          }
        }
      } else {
        // Sin conexión - Ya cargamos desde caché al inicio
        print('📴 Sin conexión - Datos ya mostrados desde caché');
        // No hacer nada más, ya tenemos los datos en pantalla
      }
    } catch (e) {
      print('❌ Error al cargar órdenes: $e');
      // Intentar cargar desde caché como último recurso
      try {
        final ordenesCache = await OrdenCacheService.getCachedOrders();
        if (mounted) {
          setState(() {
            _ordenes = ordenesCache;
            _isLoading = false;
          });
        }
      } catch (cacheError) {
        print('❌ Error cargando desde caché: $cacheError');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        _mostrarMensaje('Error al cargar órdenes: $e');
      }
    }
  }

  Future<void> _cargarMensajesNoLeidos() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      print('🔍 Cargando mensajes no leídos para repartidor...');

      // Obtener todos los mensajes no leídos
      final todosMensajes = await supabase
          .from('mensajes_soporte')
          .select('id, leido, remitente_auth_id')
          .neq('remitente_auth_id', user.id);

      // Contar mensajes no leídos con manejo robusto de booleanos
      int mensajesNoLeidos = 0;
      for (var mensaje in todosMensajes) {
        final leidoValue = mensaje['leido'];
        bool leido = false;
        if (leidoValue == null) {
          leido = false; // null significa no leído
        } else if (leidoValue is bool) {
          leido = leidoValue;
        } else if (leidoValue is String) {
          leido = leidoValue.toLowerCase() == 'true';
        } else if (leidoValue is int) {
          leido = leidoValue == 1;
        }
        
        if (!leido) {
          mensajesNoLeidos++;
        }
      }

      print('📊 Mensajes no leídos encontrados: $mensajesNoLeidos (de ${todosMensajes.length} totales)');

      if (mounted) {
        setState(() {
          _mensajesNoLeidos = mensajesNoLeidos;
        });
        print('✅ Contador actualizado: $_mensajesNoLeidos');
      }
    } catch (e) {
      print('❌ Error al cargar mensajes no leídos: $e');
    }
  }

  void _suscribirseANotificaciones() {
    _channelNotificaciones = supabase
        .channel('notificaciones_chat_repartidor')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'mensajes_soporte',
          callback: (payload) {
            print('🔔 Nuevo mensaje recibido en tiempo real');
            final user = supabase.auth.currentUser;
            if (user != null && payload.newRecord['remitente_auth_id'] != user.id) {
              print('📱 Actualizando notificaciones para repartidor');
              _cargarMensajesNoLeidos();
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'mensajes_soporte',
          callback: (payload) {
            print('🔄 Mensaje actualizado en tiempo real');
            _cargarMensajesNoLeidos();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversaciones_soporte',
          callback: (payload) {
            print('💬 Conversación actualizada en tiempo real');
            _cargarMensajesNoLeidos();
          },
        )
        .subscribe();
  }

  Future<void> _marcarMensajesComoLeidos() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // Marcar todos los mensajes no leídos como leídos (donde el repartidor no es el remitente)
      await supabase
          .from('mensajes_soporte')
          .update({'leido': true})
          .eq('leido', false)
          .neq('remitente_auth_id', user.id);

      // Actualizar contador
      _cargarMensajesNoLeidos();
    } catch (e) {
      print('Error al marcar mensajes como leídos: $e');
    }
  }

  // Obtener ID del repartidor
  Future<void> _obtenerRepartidorId() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final response = await supabase
          .from('usuarios')
          .select('id')
          .eq('auth_id', user.id)
          .eq('rol', 'REPARTIDOR')
          .maybeSingle();

      if (response != null && mounted) {
        setState(() {
          _repartidorId = response['id'].toString();
        });
        print('✅ Repartidor ID obtenido: $_repartidorId');
      }
    } catch (e) {
      // Solo imprimir error si el widget aún está montado
      if (mounted) {
        print('❌ Error obteniendo repartidor ID: $e');
      }
    }
  }

  // Cargar saldo del repartidor (último pago aceptado, o 0 si hay solicitud pendiente)
  Future<void> _cargarSaldo() async {
    if (_repartidorId == null) return;

    try {
      // Verificar si hay una solicitud pendiente
      final solicitudPendiente = await supabase
          .from('solicitudes_pago_repartidores')
          .select('id')
          .eq('repartidor_id', _repartidorId!)
          .eq('estado', 'PENDIENTE')
          .maybeSingle();

      // Si hay solicitud pendiente, resetear saldo a 0
      if (solicitudPendiente != null) {
        print('💰 Solicitud pendiente encontrada - Reseteando saldo a 0');
        if (mounted) {
          setState(() {
            _saldo = 0.0;
            _monedaSaldo = 'CUP';
          });
        }
        return;
      }

      // Si no hay solicitud pendiente, obtener el último pago aceptado
      final ultimoPagoAceptado = await supabase
          .from('solicitudes_pago_repartidores')
          .select('monto, moneda')
          .eq('repartidor_id', _repartidorId!)
          .eq('estado', 'ACEPTADO')
          .order('fecha_aceptacion', ascending: false)
          .limit(1)
          .maybeSingle();

      if (ultimoPagoAceptado != null) {
        final monto = (ultimoPagoAceptado['monto'] ?? 0.0).toDouble();
        final moneda = ultimoPagoAceptado['moneda']?.toString() ?? 'CUP';
        print('💰 Saldo cargado: $monto $moneda');
        if (mounted) {
          setState(() {
            _saldo = monto;
            _monedaSaldo = moneda;
          });
        }
      } else {
        print('💰 No hay pagos aceptados - Saldo: 0.00');
        if (mounted) {
          setState(() {
            _saldo = 0.0;
            _monedaSaldo = 'CUP';
          });
        }
      }
    } catch (e) {
      print('❌ Error cargando saldo: $e');
      if (mounted) {
        setState(() {
          _saldo = 0.0;
          _monedaSaldo = 'CUP';
        });
      }
    }
  }

  // Suscribirse a cambios en solicitudes de pago
  void _suscribirseACambiosPagos() {
    if (_repartidorId == null) return;

    try {
      print('💰 Suscribiéndose a cambios en solicitudes de pago para repartidor: $_repartidorId');
      
      supabase
          .channel('solicitudes_pago_repartidor_$_repartidorId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'solicitudes_pago_repartidores',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'repartidor_id',
              value: _repartidorId!,
            ),
            callback: (payload) {
              print('💰 Cambio detectado en solicitud de pago: ${payload.eventType}');
              _cargarSaldo(); // Recargar saldo cuando hay cambios
            },
          )
          .subscribe();
    } catch (e) {
      print('❌ Error suscribiéndose a cambios de pagos: $e');
    }
  }

  // Suscribirse a órdenes nuevas asignadas al repartidor
  void _suscribirseAOrdenesNuevas() {
    if (_repartidorId == null || _repartidorNombre == null) {
      print('⚠️ No se puede suscribir a órdenes nuevas: repartidor_id o nombre es null');
      return;
    }

    try {
      print('📦 Suscribiéndose a órdenes nuevas para repartidor: $_repartidorNombre');
      
      _channelOrdenesNuevas = supabase
          .channel('ordenes_nuevas_repartidor_$_repartidorId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'ordenes',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'repartidor_nombre',
              value: _repartidorNombre!,
            ),
            callback: (payload) {
              print('📦 Nueva orden asignada detectada en tiempo real');
              final orden = payload.newRecord;
              final estado = (orden['estado']?.toString() ?? '').trim().toUpperCase();
              final numeroOrden = orden['numero_orden']?.toString() ?? 'N/A';
              final ordenId = orden['id']?.toString() ?? '';
              
              // CRÍTICO: Solo crear notificación si la orden está activa (no ENTREGADA ni CANCELADA)
              // La función _crearNotificacionOrdenNueva verificará el estado y duplicados
              if (estado != 'ENTREGADO' && estado != 'CANCELADA') {
                print('📦 Orden #$numeroOrden asignada en estado "$estado" - Intentando crear notificación');
                _crearNotificacionOrdenNueva(ordenId, numeroOrden);
              } else {
                print('📦 Orden #$numeroOrden en estado "$estado" - No se crea notificación (orden finalizada)');
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'ordenes',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'repartidor_nombre',
              value: _repartidorNombre!,
            ),
            callback: (payload) {
              final orden = payload.newRecord;
              final ordenAnterior = payload.oldRecord;
              final repartidorAnterior = ordenAnterior['repartidor_nombre']?.toString();
              final repartidorNuevo = orden['repartidor_nombre']?.toString();
              final estado = (orden['estado']?.toString() ?? '').trim().toUpperCase();
              final estadoAnterior = (ordenAnterior['estado']?.toString() ?? '').trim().toUpperCase();
              
              // Solo crear notificación si:
              // 1. La orden fue asignada a este repartidor (antes no estaba asignada o estaba asignada a otro)
              // 2. La orden NO está ENTREGADA ni CANCELADA
              // 3. El cambio de estado es relevante (no todos los cambios requieren notificación)
              if (repartidorNuevo == _repartidorNombre && 
                  repartidorAnterior != _repartidorNombre &&
                  estado != 'ENTREGADO' && 
                  estado != 'CANCELADA') {
                print('📦 Orden reasignada a este repartidor (antes: $repartidorAnterior, ahora: $repartidorNuevo)');
                final numeroOrden = orden['numero_orden']?.toString() ?? 'N/A';
                final ordenId = orden['id']?.toString() ?? '';
                
                // La función _crearNotificacionOrdenNueva verificará el estado y duplicados
                print('📦 Orden #$numeroOrden actualizada a estado "$estado" - Intentando crear notificación');
                _crearNotificacionOrdenNueva(ordenId, numeroOrden);
              }
              
              // También notificar cuando cambia el estado de una orden asignada (solo estados relevantes)
              // pero NO si ya está ENTREGADA o CANCELADA
              // NOTA: Solo notificar cambios de estado si la orden ya estaba asignada a este repartidor
              if (repartidorNuevo == _repartidorNombre && 
                  repartidorAnterior == _repartidorNombre &&
                  estado != estadoAnterior &&
                  estado != 'ENTREGADO' && 
                  estado != 'CANCELADA' &&
                  estadoAnterior != 'ENTREGADO' &&
                  estadoAnterior != 'CANCELADA') {
                // Solo notificar cambios de estado relevantes (no todos los cambios)
                // Los cambios de estado importantes son: POR ENVIAR → EN TRANSITO → EN REPARTO
                final estadosRelevantes = ['POR ENVIAR', 'EN TRANSITO', 'EN REPARTO', 'LISTO PARA RECOGER'];
                if (estadosRelevantes.contains(estado) || estadosRelevantes.contains(estadoAnterior)) {
                  print('📦 Estado de orden #${orden['numero_orden']} cambió de "$estadoAnterior" a "$estado" - Verificando si crear notificación');
                  final numeroOrden = orden['numero_orden']?.toString() ?? 'N/A';
                  final ordenId = orden['id']?.toString() ?? '';
                  // Solo crear si no existe ya una notificación (la función lo verificará)
                  _crearNotificacionOrdenNueva(ordenId, numeroOrden);
                }
              }
            },
          )
          .subscribe((status, [error]) {
            if (status == RealtimeSubscribeStatus.subscribed) {
              print('✅ Suscrito a órdenes nuevas para repartidor: $_repartidorNombre');
            } else if (error != null) {
              // ✅ OFFLINE-FIRST: No mostrar error si está offline
              final errorString = error.toString();
              if (errorString.contains('Failed host lookup') || 
                  errorString.contains('SocketException') ||
                  errorString.contains('WebSocketChannelException')) {
                print('📴 Sin conexión - Error de suscripción ignorado (modo offline)');
              } else {
                print('❌ Error suscribiéndose a órdenes nuevas: $error');
              }
            }
          });
    } catch (e) {
      // ✅ OFFLINE-FIRST: Manejar errores de conexión silenciosamente
      final errorString = e.toString();
      if (errorString.contains('Failed host lookup') || 
          errorString.contains('SocketException') ||
          errorString.contains('WebSocketChannelException')) {
        print('📴 Sin conexión - Error de suscripción ignorado (modo offline)');
      } else {
        print('❌ Error suscribiéndose a órdenes nuevas: $e');
      }
    }
  }

  // Suscribirse a pagos aceptados
  void _suscribirseAPagosAceptados() {
    if (_repartidorId == null) {
      print('⚠️ No se puede suscribir a pagos aceptados: repartidor_id es null');
      return;
    }

    try {
      print('💰 Suscribiéndose a pagos aceptados para repartidor: $_repartidorId');
      
      _channelPagosAceptados = supabase
          .channel('pagos_aceptados_repartidor_$_repartidorId')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'solicitudes_pago_repartidores',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'repartidor_id',
              value: _repartidorId!,
            ),
            callback: (payload) {
              final pago = payload.newRecord;
              final pagoAnterior = payload.oldRecord;
              final estadoAnterior = pagoAnterior['estado']?.toString();
              final estadoNuevo = pago['estado']?.toString();
              
              // Si el estado cambió a ACEPTADO
              if (estadoAnterior != 'ACEPTADO' && estadoNuevo == 'ACEPTADO') {
                print('💰💰💰 Pago aceptado detectado en tiempo real');
                final monto = (pago['monto'] ?? 0.0).toDouble();
                final moneda = pago['moneda']?.toString() ?? 'CUP';
                final simbolo = moneda == 'USD' ? '\$' : 'CUP';
                final pagoId = pago['id']?.toString() ?? '';
                
                // Crear notificación
                _crearNotificacionPagoAceptado(pagoId, monto, moneda, simbolo);
              }
              
              // Si el estado cambió a CANCELADA
              if (estadoAnterior != 'CANCELADA' && estadoNuevo == 'CANCELADA') {
                print('🚫🚫🚫 Pago cancelado detectado en tiempo real');
                final monto = (pago['monto'] ?? 0.0).toDouble();
                final moneda = pago['moneda']?.toString() ?? 'CUP';
                final simbolo = moneda == 'USD' ? '\$' : 'CUP';
                final pagoId = pago['id']?.toString() ?? '';
                final motivoCancelacion = pago['motivo_cancelacion']?.toString() ?? '';
                
                // Crear notificación
                _crearNotificacionPagoCancelado(pagoId, monto, moneda, simbolo, motivoCancelacion);
              }
              
              // Si el estado cambió a RECHAZADO
              if (estadoAnterior != 'RECHAZADO' && estadoNuevo == 'RECHAZADO') {
                print('❌❌❌ Pago rechazado detectado en tiempo real');
                final monto = (pago['monto'] ?? 0.0).toDouble();
                final moneda = pago['moneda']?.toString() ?? 'CUP';
                final simbolo = moneda == 'USD' ? '\$' : 'CUP';
                final pagoId = pago['id']?.toString() ?? '';
                final motivoRechazo = pago['motivo_rechazo']?.toString() ?? '';
                
                // Crear notificación
                _crearNotificacionPagoRechazado(pagoId, monto, moneda, simbolo, motivoRechazo);
              }
            },
          )
          .subscribe((status, [error]) {
            if (status == RealtimeSubscribeStatus.subscribed) {
              print('✅ Suscrito a pagos aceptados para repartidor: $_repartidorId');
            } else if (error != null) {
              // ✅ OFFLINE-FIRST: No mostrar error si está offline
              final errorString = error.toString();
              if (errorString.contains('Failed host lookup') || 
                  errorString.contains('SocketException') ||
                  errorString.contains('WebSocketChannelException')) {
                print('📴 Sin conexión - Error de suscripción ignorado (modo offline)');
              } else {
                print('❌ Error suscribiéndose a pagos aceptados: $error');
              }
            }
          });
    } catch (e) {
      // ✅ OFFLINE-FIRST: Manejar errores de conexión silenciosamente
      final errorString = e.toString();
      if (errorString.contains('Failed host lookup') || 
          errorString.contains('SocketException') ||
          errorString.contains('WebSocketChannelException')) {
        print('📴 Sin conexión - Error de suscripción ignorado (modo offline)');
      } else {
        print('❌ Error suscribiéndose a pagos aceptados: $e');
      }
    }
  }

  // Crear notificación para orden nueva
  Future<void> _crearNotificacionOrdenNueva(String ordenId, String numeroOrden) async {
    if (!mounted) {
      print('⚠️ No se puede crear notificación: widget no está montado');
      return;
    }
    
    if (_repartidorId == null || _repartidorId!.isEmpty) {
      print('⚠️ No se puede crear notificación: repartidor_id es null o vacío');
      return;
    }

    try {
      // CRÍTICO: Verificar el estado de la orden ANTES de crear la notificación
      final ordenData = await supabase
          .from('ordenes')
          .select('estado')
          .eq('id', ordenId)
          .maybeSingle();

      if (ordenData == null) {
        print('⚠️ No se puede crear notificación: orden no encontrada (ID: $ordenId)');
        return;
      }

      final estadoOrden = (ordenData['estado']?.toString() ?? '').trim().toUpperCase();
      
      // NO crear notificaciones para órdenes ENTREGADAS o CANCELADAS
      if (estadoOrden == 'ENTREGADO' || estadoOrden == 'CANCELADA') {
        print('📦 Orden #$numeroOrden en estado "$estadoOrden" - No se crea notificación (orden finalizada)');
        return;
      }

      // Verificar si ya existe una notificación (leída o no leída) para esta orden
      // Esto evita duplicados incluso si el usuario leyó y cerró la app
      // CRÍTICO: Usar .limit(1) antes de .maybeSingle() para evitar error cuando hay múltiples filas
      // El error "multiple rows returned" ocurre cuando hay múltiples notificaciones con los mismos criterios
      Map<String, dynamic>? notificacionExistente;
      try {
        final notificacionExistenteResponse = await supabase
            .from('notificaciones_repartidores')
            .select('id, leida')
            .eq('repartidor_id', _repartidorId!)
            .eq('numero_orden', numeroOrden)
            .inFilter('tipo', ['ORDEN_NUEVA', 'nueva_orden'])
            .limit(1)
            .maybeSingle();
        
        notificacionExistente = notificacionExistenteResponse;
      } catch (e) {
        // Si hay múltiples filas, obtener solo la primera
        print('⚠️ Múltiples notificaciones encontradas, obteniendo la primera: $e');
        try {
          final notificacionesList = await supabase
              .from('notificaciones_repartidores')
              .select('id, leida')
              .eq('repartidor_id', _repartidorId!)
              .eq('numero_orden', numeroOrden)
              .inFilter('tipo', ['ORDEN_NUEVA', 'nueva_orden'])
              .limit(1);
          
          if (notificacionesList.isNotEmpty) {
            notificacionExistente = notificacionesList[0];
          }
        } catch (e2) {
          print('⚠️ Error al obtener notificación existente: $e2');
          notificacionExistente = null;
        }
      }

      if (notificacionExistente != null) {
        print('📦 Notificación ya existe para orden #$numeroOrden (ID: ${notificacionExistente['id']}, Leída: ${notificacionExistente['leida']})');
        return;
      }

      // Crear nueva notificación solo si la orden está activa
      await supabase.from('notificaciones_repartidores').insert({
        'repartidor_id': _repartidorId!,
        'tipo': 'ORDEN_NUEVA',
        'titulo': 'Nueva Orden Asignada',
        'mensaje': 'Tienes una nueva orden asignada: #$numeroOrden',
        'numero_orden': numeroOrden,
        'orden_id': ordenId,
        'leida': false,
      });

      print('✅ Notificación creada para orden #$numeroOrden (estado: $estadoOrden)');
      
      // Actualizar contador solo si el widget está montado
      if (mounted) {
        await _cargarNotificacionesNoLeidas();
      }
    } catch (e) {
      // Manejar específicamente errores de permisos de seguridad
      if (e.toString().contains('row-level security policy') || 
          e.toString().contains('42501') ||
          e.toString().contains('Forbidden')) {
        print('⚠️ Error de permisos al crear notificación (RLS): $e');
        print('⚠️ Esto puede ocurrir si el repartidor no tiene permisos para crear notificaciones');
        print('⚠️ Verificar políticas RLS en Supabase para la tabla notificaciones_repartidores');
      } else {
        print('❌ Error creando notificación de orden nueva: $e');
      }
    }
  }

  // Crear notificación para pago aceptado
  Future<void> _crearNotificacionPagoAceptado(String pagoId, double monto, String moneda, String simbolo) async {
    try {
      if (_repartidorId == null) return;

      // Verificar si ya existe una notificación no leída para este pago
      final notificacionExistente = await supabase
          .from('notificaciones_repartidores')
          .select('id')
          .eq('repartidor_id', _repartidorId!)
          .eq('pago_id', pagoId)
          .eq('leida', false)
          .maybeSingle();

      if (notificacionExistente != null) {
        print('💰 Notificación ya existe para pago $pagoId');
        return;
      }

      // Crear nueva notificación
      await supabase.from('notificaciones_repartidores').insert({
        'repartidor_id': _repartidorId!,
        'tipo': 'PAGO_ACEPTADO',
        'titulo': 'Pago Aceptado',
        'mensaje': 'Tu solicitud de pago de $simbolo${monto.toStringAsFixed(2)} ha sido aceptada',
        'pago_id': pagoId,
        'leida': false,
      });

      print('✅ Notificación creada para pago aceptado: $simbolo${monto.toStringAsFixed(2)}');
      
      // Actualizar contador
      await _cargarNotificacionesNoLeidas();
    } catch (e) {
      print('❌ Error creando notificación de pago aceptado: $e');
    }
  }

  // Crear notificación para pago cancelado
  Future<void> _crearNotificacionPagoCancelado(String pagoId, double monto, String moneda, String simbolo, String motivo) async {
    try {
      if (_repartidorId == null) return;

      // Verificar si ya existe una notificación no leída para este pago
      final notificacionExistente = await supabase
          .from('notificaciones_repartidores')
          .select('id')
          .eq('repartidor_id', _repartidorId!)
          .eq('pago_id', pagoId)
          .eq('tipo', 'PAGO_CANCELADO')
          .eq('leida', false)
          .maybeSingle();

      if (notificacionExistente != null) {
        print('🚫 Notificación ya existe para pago cancelado $pagoId');
        return;
      }

      // Crear nueva notificación
      final mensaje = motivo.isNotEmpty 
          ? 'Tu solicitud de pago de $simbolo${monto.toStringAsFixed(2)} ha sido cancelada. Motivo: $motivo'
          : 'Tu solicitud de pago de $simbolo${monto.toStringAsFixed(2)} ha sido cancelada';
      
      await supabase.from('notificaciones_repartidores').insert({
        'repartidor_id': _repartidorId!,
        'tipo': 'PAGO_CANCELADO',
        'titulo': 'Pago Cancelado',
        'mensaje': mensaje,
        'pago_id': pagoId,
        'leida': false,
      });

      print('✅ Notificación creada para pago cancelado: $simbolo${monto.toStringAsFixed(2)}');
      
      // Actualizar contador
      await _cargarNotificacionesNoLeidas();
    } catch (e) {
      print('❌ Error creando notificación de pago cancelado: $e');
    }
  }

  // Crear notificación para pago rechazado
  Future<void> _crearNotificacionPagoRechazado(String pagoId, double monto, String moneda, String simbolo, String motivo) async {
    try {
      if (_repartidorId == null) return;

      // Verificar si ya existe una notificación no leída para este pago
      final notificacionExistente = await supabase
          .from('notificaciones_repartidores')
          .select('id')
          .eq('repartidor_id', _repartidorId!)
          .eq('pago_id', pagoId)
          .eq('tipo', 'PAGO_RECHAZADO')
          .eq('leida', false)
          .maybeSingle();

      if (notificacionExistente != null) {
        print('❌ Notificación ya existe para pago rechazado $pagoId');
        return;
      }

      // Crear nueva notificación
      final mensaje = motivo.isNotEmpty 
          ? 'Tu solicitud de pago de $simbolo${monto.toStringAsFixed(2)} ha sido rechazada. Motivo: $motivo'
          : 'Tu solicitud de pago de $simbolo${monto.toStringAsFixed(2)} ha sido rechazada';
      
      await supabase.from('notificaciones_repartidores').insert({
        'repartidor_id': _repartidorId!,
        'tipo': 'PAGO_RECHAZADO',
        'titulo': 'Pago Rechazado',
        'mensaje': mensaje,
        'pago_id': pagoId,
        'leida': false,
      });

      print('✅ Notificación creada para pago rechazado: $simbolo${monto.toStringAsFixed(2)}');
      
      // Actualizar contador
      await _cargarNotificacionesNoLeidas();
    } catch (e) {
      print('❌ Error creando notificación de pago rechazado: $e');
    }
  }

  // Inicializar notificaciones locales
  Future<void> _inicializarNotificaciones() async {
    _localNotifications = FlutterLocalNotificationsPlugin();

    // Configuración para Android
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    
    // Configuración para iOS
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications!.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        print('📱 Notificación tocada: ${details.payload}');
        // Recargar órdenes cuando se toca la notificación
        _cargarOrdenes();
      },
    );

    // Solicitar permisos en Android 13+
    final androidImplementation = _localNotifications!.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidImplementation != null) {
      // Solicitar permisos
      await androidImplementation.requestNotificationsPermission();
      
      // Crear canal de notificaciones con alta importancia para que funcione en segundo plano
      const androidChannel = AndroidNotificationChannel(
        'ordenes_channel',
        'Órdenes',
        description: 'Notificaciones de nuevas órdenes asignadas',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      );
      
      await androidImplementation.createNotificationChannel(androidChannel);
      print('✅ Canal de notificaciones creado: ordenes_channel');
    }

    print('✅ Notificaciones locales inicializadas');
  }

  // Suscribirse a notificaciones de nuevas órdenes
  void _suscribirseANotificacionesOrdenes() {
    if (_repartidorId == null) {
      print('⚠️ No se puede suscribir a notificaciones: repartidor_id es null');
      return;
    }

    // CRÍTICO: Si es recolector, suscribirse a notificaciones_recolectores, si no, a notificaciones_repartidores
    final tablaNotificaciones = _esRecolector ? 'notificaciones_recolectores' : 'notificaciones_repartidores';
    final campoId = _esRecolector ? 'recolector_id' : 'repartidor_id';
    final tipoUsuario = _esRecolector ? 'recolector' : 'repartidor';

    print('🔔 Suscribiéndose a notificaciones de órdenes para $tipoUsuario: $_repartidorId');
    print('🔔 Tipo de repartidor_id: ${_repartidorId.runtimeType}');
    print('🔔 Repartidor_id como String: ${_repartidorId.toString()}');
    print('🔔 Tabla de notificaciones: $tablaNotificaciones');
    
    _channelNotificacionesOrdenes = supabase
        .channel('notificaciones_ordenes_${tipoUsuario}_$_repartidorId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: tablaNotificaciones,
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: campoId,
            value: _repartidorId.toString(),
          ),
          callback: (payload) {
            print('');
            print('🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔');
            print('🔔 NUEVA NOTIFICACIÓN DE ORDEN RECIBIDA VÍA REALTIME');
            print('🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔');
            print('📦 Payload completo: $payload');
            print('📦 newRecord: ${payload.newRecord}');
            print('📦 eventType: ${payload.eventType}');
            print('📦 table: ${payload.table}');
            
            final notificacion = payload.newRecord;
            final tipo = notificacion['tipo']?.toString() ?? '';
            final titulo = notificacion['titulo']?.toString() ?? 'Nueva Orden';
            final mensaje = notificacion['mensaje']?.toString() ?? 'Tienes una nueva orden asignada';
            final numeroOrden = notificacion['numero_orden']?.toString() ?? '';
            final idNotif = notificacion[campoId]?.toString() ?? '';
            final notificacionId = notificacion['id']?.toString() ?? '';
            
            print('📦 Tipo: $tipo');
            print('📦 Título: $titulo');
            print('📦 Mensaje: $mensaje');
            print('📦 Número orden: $numeroOrden');
            print('📦 $campoId en notificación: $idNotif');
            print('📦 $campoId esperado: ${_repartidorId.toString()}');
            print('📦 ¿Coinciden?: ${idNotif == _repartidorId.toString()}');
            
            // Verificar si las notificaciones están habilitadas
            _verificarYMostrarNotificacion(tipo, titulo, mensaje, numeroOrden, notificacionId: tipo == 'general' ? notificacionId : null);
          },
        )
        .subscribe((status, [error]) {
          print('🔔 Estado de suscripción Realtime: $status');
          if (error != null) {
            // ✅ OFFLINE-FIRST: No mostrar error si está offline
            final errorString = error.toString();
            if (errorString.contains('Failed host lookup') || 
                errorString.contains('SocketException') ||
                errorString.contains('WebSocketChannelException')) {
              print('📴 Sin conexión - Error de suscripción ignorado (modo offline)');
            } else {
              print('❌ Error en suscripción Realtime: $error');
            }
          }
          if (status == RealtimeSubscribeStatus.subscribed) {
            print('✅ ✅ ✅ SUSCRIPCIÓN REALTIME ACTIVA ✅ ✅ ✅');
            print('✅ Escuchando notificaciones para ${tipoUsuario}_id: $_repartidorId');
          }
        });
    
    print('✅ Suscrito a notificaciones de órdenes');
  }

  // Verificar configuración y mostrar notificación
  Future<void> _verificarYMostrarNotificacion(String tipo, String titulo, String mensaje, String numeroOrden, {String? notificacionId}) async {
    try {
      print('🔍 Verificando configuración de notificaciones...');
      print('   - Tipo: $tipo');
      print('   - Título: $titulo');
      print('   - Mensaje: $mensaje');
      
      // Verificar si las notificaciones para repartidores están habilitadas
      final configService = ConfiguracionService();
      final notificacionesHabilitadas = await configService.notificacionesHabilitadas('repartidores');
      
      print('🔍 Notificaciones habilitadas: $notificacionesHabilitadas');
      
      if (!notificacionesHabilitadas) {
        print('⚠️ Notificaciones para repartidores están deshabilitadas');
        return;
      }

      print('✅ Notificaciones habilitadas, mostrando notificación push...');
      
      // Si es notificación general, guardar para mostrar en banner
      if (tipo == 'general' && notificacionId != null) {
        // Obtener la notificación completa desde la BD
        try {
          final notifCompleta = await supabase
              .from('notificaciones_repartidores')
              .select('*')
              .eq('id', notificacionId)
              .maybeSingle();
          
          if (notifCompleta != null && mounted) {
            setState(() {
              _notificacionGeneralBanner = notifCompleta;
            });
            print('✅ Banner de notificación general configurado');
          }
        } catch (e) {
          print('⚠️ Error obteniendo notificación completa: $e');
        }
      }
      
      // Mostrar notificación
      await _mostrarNotificacionPush(titulo, mensaje, numeroOrden);
      
      print('✅ Notificación push mostrada, actualizando contador...');
      
      // CRÍTICO: Actualizar contador de notificaciones no leídas
      // Esto actualiza el badge de la campanita
      await _cargarNotificacionesNoLeidas();
      
      print('✅ ✅ ✅ PROCESO DE NOTIFICACIÓN COMPLETADO ✅ ✅ ✅');
    } catch (e, stackTrace) {
      print('❌ ❌ ❌ ERROR VERIFICANDO NOTIFICACIÓN ❌ ❌ ❌');
      print('❌ Error: $e');
      print('❌ Stack trace: $stackTrace');
    }
  }

  // Mostrar notificación push con vibración, sonido y badge
  Future<void> _mostrarNotificacionPush(String titulo, String mensaje, String numeroOrden) async {
    try {
      print('📱 Iniciando notificación push...');
      print('   - Título: $titulo');
      print('   - Mensaje: $mensaje');
      print('   - Número orden: $numeroOrden');
      
      // Vibración
      print('📳 Verificando vibrador...');
      if (await Vibration.hasVibrator() ?? false) {
        print('📳 Vibrador disponible, activando vibración...');
        await Vibration.vibrate(duration: 500);
        print('✅ Vibración activada');
      } else {
        print('⚠️ Vibrador no disponible');
      }

      // Mostrar notificación local
      final androidDetails = AndroidNotificationDetails(
        'ordenes_channel',
        'Órdenes',
        channelDescription: 'Notificaciones de nuevas órdenes asignadas',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
        showWhen: true,
        when: DateTime.now().millisecondsSinceEpoch,
        ongoing: false,
        autoCancel: true,
        visibility: NotificationVisibility.public,
        fullScreenIntent: false,
        category: AndroidNotificationCategory.message,
        styleInformation: BigTextStyleInformation(
          mensaje,
          contentTitle: titulo,
          summaryText: 'Nueva orden asignada',
        ),
        channelShowBadge: true,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications!.show(
        DateTime.now().millisecondsSinceEpoch % 100000,
        titulo,
        mensaje,
        notificationDetails,
        payload: numeroOrden,
      );

      print('✅ ✅ ✅ NOTIFICACIÓN LOCAL MOSTRADA EXITOSAMENTE ✅ ✅ ✅');
      print('✅ Título: $titulo');
      print('✅ Mensaje: $mensaje');
    } catch (e) {
      print('❌ Error mostrando notificación: $e');
    }
  }

  // Verificar notificaciones periódicamente (cada 5 segundos) como respaldo a Realtime
  void _iniciarVerificacionPeriodicaNotificaciones() {
    print('🔄 Iniciando verificación periódica de notificaciones (cada 5 segundos)...');
    _timerVerificarNotificaciones?.cancel();
    _timerVerificarNotificaciones = Timer.periodic(
      const Duration(seconds: 5),
      (timer) async {
        if (_repartidorId == null) {
          return;
        }
        
        try {
          // Verificar conectividad primero
          final connectivityResult = await Connectivity().checkConnectivity();
          if (connectivityResult == ConnectivityResult.none) {
            print('⚠️ Sin conexión a internet, saltando verificación de notificaciones');
            return;
          }
          
          // CRÍTICO: Si es recolector, verificar en notificaciones_recolectores, si no, en notificaciones_repartidores
          final tablaNotificaciones = _esRecolector ? 'notificaciones_recolectores' : 'notificaciones_repartidores';
          final campoId = _esRecolector ? 'recolector_id' : 'repartidor_id';
          
          print('🔄 Verificando notificaciones no leídas periódicamente...');
          print('🔄 Repartidor ID: $_repartidorId');
          
          // Obtener notificaciones no leídas con timeout
          final notificaciones = await supabase
              .from(tablaNotificaciones)
              .select('*')
              .eq(campoId, _repartidorId!)
              .eq('leida', false)
              .order('created_at', ascending: false)
              .limit(10)
              .timeout(const Duration(seconds: 10));
          
          print('📊 Notificaciones encontradas en BD: ${notificaciones.length}');
          
          if (notificaciones.isNotEmpty) {
            print('');
            print('🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔');
            print('🔔 NUEVAS NOTIFICACIONES ENCONTRADAS (verificación periódica)');
            print('🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔 🔔');
            print('📦 Total: ${notificaciones.length}');
            
            // Procesar solo notificaciones NUEVAS (no procesadas antes)
            int nuevasProcesadas = 0;
            for (var notif in notificaciones) {
              final notifId = notif['id']?.toString() ?? '';
              
              // CRÍTICO: Evitar procesar la misma notificación múltiples veces
              // Solo procesar si NO está en el set de procesadas
              if (_notificacionesProcesadas.contains(notifId)) {
                print('⏭️ Notificación $notifId ya procesada, saltando...');
                continue;
              }
              
              final tipo = notif['tipo']?.toString() ?? '';
              final titulo = notif['titulo']?.toString() ?? 'Nueva Orden';
              final mensaje = notif['mensaje']?.toString() ?? 'Tienes una nueva orden asignada';
              final numeroOrden = notif['numero_orden']?.toString() ?? '';
              final createdAt = notif['created_at']?.toString() ?? '';
              final leida = notif['leida'] ?? false;
              
              print('📦 Procesando notificación NUEVA:');
              print('   - ID: $notifId');
              print('   - Título: $titulo');
              print('   - Mensaje: $mensaje');
              print('   - Número orden: $numeroOrden');
              print('   - Creada: $createdAt');
              print('   - Leída: $leida');
              
              // Marcar como procesada ANTES de mostrar (para evitar duplicados)
              _notificacionesProcesadas.add(notifId);
              nuevasProcesadas++;
              
              // Verificar y mostrar notificación (pasar notificacionId para tipo 'general')
              await _verificarYMostrarNotificacion(tipo, titulo, mensaje, numeroOrden, notificacionId: tipo == 'general' ? notifId : null);
            }
            
            if (nuevasProcesadas > 0) {
              print('✅ Procesadas $nuevasProcesadas notificaciones nuevas');
              // Actualizar contador solo si hubo nuevas
              await _cargarNotificacionesNoLeidas();
            } else {
              print('📭 Todas las notificaciones ya fueron procesadas anteriormente');
            }
          } else {
            print('📭 No hay notificaciones nuevas');
          }
        } on TimeoutException {
          print('⏱️ Timeout al verificar notificaciones (sin conexión)');
        } catch (e) {
          // ✅ OFFLINE-FIRST: No mostrar errores de conexión al usuario cuando está offline
          final errorString = e.toString();
          if (errorString.contains('Failed host lookup') || 
              errorString.contains('SocketException') ||
              errorString.contains('WebSocketChannelException') ||
              errorString.contains('ClientException')) {
            // Solo registrar en consola para debugging, no mostrar al usuario
            print('📴 Sin conexión - Verificación periódica omitida (modo offline)');
          } else {
            print('⚠️ Error en verificación periódica: $e');
          }
        }
      },
    );
    print('✅ Verificación periódica iniciada (cada 5 segundos)');
  }

  // Cargar notificaciones no leídas y actualizar badge
  Future<void> _cargarNotificacionesNoLeidas() async {
    try {
      if (_repartidorId == null) {
        print('⚠️ No se puede cargar notificaciones: _repartidorId es null');
        return;
      }

      // Obtener auth_id como alternativa
      final user = supabase.auth.currentUser;
      final authId = user?.id;
      
      print('🔔 Cargando notificaciones no leídas...');
      print('   - Repartidor ID: $_repartidorId');
      print('   - Auth ID: $authId');

      // Cargar TODAS las notificaciones no leídas (sin filtrar por tipo)
      // Usar ambos IDs posibles: usuario.id y auth_id (por compatibilidad)
      final idsValidos = [_repartidorId, authId].whereType<String>().toList();
      
      print('   - IDs válidos para consulta: $idsValidos');
      print('   - Es recolector: $_esRecolector');
      
      // CRÍTICO: Si es recolector, cargar de notificaciones_recolectores, si no, de notificaciones_repartidores
      final tablaNotificaciones = _esRecolector ? 'notificaciones_recolectores' : 'notificaciones_repartidores';
      final campoId = _esRecolector ? 'recolector_id' : 'repartidor_id';
      
      // CRÍTICO: Solo cargar notificaciones que realmente están marcadas como no leídas en la BD
      // Intentar primero con los IDs válidos
      var response = await supabase
          .from(tablaNotificaciones)
          .select('id, tipo, $campoId, leida')
          .inFilter(campoId, idsValidos)
          .eq('leida', false); // CRÍTICO: Solo no leídas
      
      print('📊 Notificaciones NO LEÍDAS encontradas (con IDs válidos) en $tablaNotificaciones: ${response.length}');
      
      // Filtrar manualmente para asegurar que solo sean no leídas
      response = response.where((n) => (n['leida'] == false || n['leida'] == null)).toList();
      print('📊 Notificaciones después de filtrar leída=false: ${response.length}');
      
      // Si no se encontraron, intentar solo con repartidor_id/recolector_id
      if (response.isEmpty && _repartidorId != null) {
        print('⚠️ No se encontraron con IDs válidos, intentando solo con $_repartidorId...');
        try {
          final responseAlternativa = await supabase
              .from(tablaNotificaciones)
              .select('id, tipo, $campoId, leida')
              .eq(campoId, _repartidorId!)
              .eq('leida', false); // CRÍTICO: Solo no leídas
          
          print('📊 Notificaciones NO LEÍDAS encontradas (solo $_repartidorId): ${responseAlternativa.length}');
          if (responseAlternativa.isNotEmpty) {
            // Filtrar manualmente también aquí
            response = responseAlternativa.where((n) => (n['leida'] == false || n['leida'] == null)).toList();
            print('   - Primera notificación: ${responseAlternativa.first}');
          }
        } catch (e) {
          print('❌ Error en consulta alternativa: $e');
        }
      }

      // Contar todas las notificaciones no leídas
      int contadorValido = 0;
      int contadorGeneral = 0;
      int contadorOrdenes = 0;
      int contadorPagos = 0;
      
      for (var notificacion in response) {
        final tipo = notificacion['tipo']?.toString() ?? '';
        
        // Contar todas las notificaciones válidas:
        // - ORDEN_NUEVA, nueva_orden: órdenes nuevas asignadas
        // - PAGO_ACEPTADO: pagos aceptados (ya verificados al crearse)
        // - PAGO_CANCELADO: pagos cancelados (ya verificados al crearse)
        // - PAGO_RECHAZADO: pagos rechazados (ya verificados al crearse)
        // - general: notificaciones push desde Super Admin
        if (tipo == 'ORDEN_NUEVA' || tipo == 'nueva_orden') {
          contadorValido++;
          contadorOrdenes++;
        } else if (tipo == 'PAGO_ACEPTADO' || 
                   tipo == 'PAGO_CANCELADO' || 
                   tipo == 'PAGO_RECHAZADO') {
          contadorValido++;
          contadorPagos++;
        } else if (tipo == 'general') {
          contadorValido++;
          contadorGeneral++;
        }
      }

      final nuevoContador = contadorValido;
      
      print('📊 Desglose de notificaciones no leídas:');
      print('   - Total: $nuevoContador');
      print('   - Generales: $contadorGeneral');
      print('   - Órdenes: $contadorOrdenes');
      print('   - Pagos: $contadorPagos');
      
      // CRÍTICO: Sincronizar el set de procesadas con las notificaciones realmente no leídas
      // Solo mantener en el set las notificaciones que realmente existen y no están leídas
      final idsNoLeidas = response.map((n) => n['id']?.toString() ?? '').where((id) => id.isNotEmpty).toSet();
      // Mantener solo las IDs que están realmente en la BD como no leídas
      _notificacionesProcesadas.removeWhere((id) => !idsNoLeidas.contains(id));
      print('🔄 Sincronizado set de procesadas: ${_notificacionesProcesadas.length} IDs');
      
      if (mounted) {
        setState(() {
          _notificacionesNoLeidas = nuevoContador;
        });

        // Actualizar badge del icono de la app usando flutter_local_notifications
        try {
          // En Android, el badge se maneja automáticamente con las notificaciones activas
          print('✅ Badge actualizado: $nuevoContador (manejado por el sistema)');
        } catch (e) {
          print('⚠️ Error actualizando badge: $e');
        }

        print('✅ Contador de notificaciones actualizado en UI: $nuevoContador');
      }
    } catch (e) {
      print('❌ Error cargando notificaciones no leídas: $e');
      print('❌ Stack trace: ${StackTrace.current}');
    }
  }

  // Marcar notificaciones como leídas
  Future<void> _marcarNotificacionesComoLeidas() async {
    try {
      if (_repartidorId == null) return;

      await supabase
          .from('notificaciones_repartidores')
          .update({'leida': true})
          .eq('repartidor_id', _repartidorId!)
          .eq('leida', false);

      // Actualizar contador y badge
      await _cargarNotificacionesNoLeidas();
      print('✅ Notificaciones marcadas como leídas');
    } catch (e) {
      print('❌ Error marcando notificaciones como leídas: $e');
    }
  }

  // Listener con debounce para evitar que el teclado se cierre
  void _onSearchChanged() {
    // Cancelar timer anterior si existe
    _searchDebounceTimer?.cancel();
    
    // Crear nuevo timer con delay de 300ms
    _searchDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        // Invalidar caché sin perder el foco
        _ordenesFiltradasCache = null;
        _cacheKeyFiltradas = null;
        // Actualizar UI sin perder el foco del TextField
        setState(() {
          // La lógica de filtrado se maneja en el getter _ordenesFiltradas
        });
      }
    });
  }
  
  void _filtrarOrdenes() {
    // Mantener compatibilidad con llamadas directas
    _onSearchChanged();
  }

  // Variables para configuración de prioridad
  bool _prioridadUrgentes = true;
  bool _ordenarPorFecha = false;
  bool _ordenarPorDistancia = true;

  Future<void> _cargarConfiguracionPrioridad() async {
    try {
      final responseList = await supabase
          .from('configuracion_envios')
          .select('prioridad_urgentes, ordenar_por_fecha, ordenar_por_distancia')
          .limit(1);

      bool configCambio = false;
      
      if (responseList.isNotEmpty) {
        final config = responseList[0];
        final nuevaPrioridadUrgentes = config['prioridad_urgentes'] ?? true;
        final nuevaOrdenarPorFecha = config['ordenar_por_fecha'] ?? false;
        final nuevaOrdenarPorDistancia = config['ordenar_por_distancia'] ?? true;
        
        // Verificar si la configuración cambió
        configCambio = _prioridadUrgentes != nuevaPrioridadUrgentes ||
                       _ordenarPorFecha != nuevaOrdenarPorFecha ||
                       _ordenarPorDistancia != nuevaOrdenarPorDistancia;
        
        // CRÍTICO: Verificar mounted antes de setState para evitar errores después de dispose
        if (mounted) {
          setState(() {
            _prioridadUrgentes = nuevaPrioridadUrgentes;
            _ordenarPorFecha = nuevaOrdenarPorFecha;
            _ordenarPorDistancia = nuevaOrdenarPorDistancia;
          });
          print('✅ Configuración de prioridad cargada: urgentes=$_prioridadUrgentes, fecha=$_ordenarPorFecha, distancia=$_ordenarPorDistancia');
          
          // Si cambió la configuración o se activó ordenamiento por distancia, recargar órdenes
          if (configCambio || (_ordenarPorDistancia && _ubicacionActual == null)) {
            print('🔄 Recargando órdenes debido a cambio en configuración de prioridad...');
            await _cargarOrdenes();
            // Si se activó ordenamiento por distancia, obtener ubicación
            if (_ordenarPorDistancia && _ubicacionActual == null) {
              await _obtenerUbicacionActual();
              if (_ubicacionActual != null && mounted) {
                await _cargarOrdenes(); // Recargar para reordenar con distancia
              }
            }
          }
        }
      }
    } catch (e) {
      print('⚠️ Error cargando configuración de prioridad: $e');
      // Usar valores por defecto si hay error
    }
  }

  List<Orden> get _ordenesFiltradas {
    // Generar clave de caché basada en dependencias
    final nuevaCacheKey = '${_ordenes.length}_$_filtroEstado$_filtroRepartidor${_searchController.text}_$_esRecolector$_esRepartidorMaster';
    
    // Si la caché es válida, retornarla
    if (_ordenesFiltradasCache != null && _cacheKeyFiltradas == nuevaCacheKey) {
      return _ordenesFiltradasCache!;
    }
    
    // Recalcular solo si es necesario
    var filtradas = _ordenes;

    // Filtrar por estado (diferentes estados para recolectores vs repartidores)
    if (_esRecolector) {
      // Filtros específicos para recolectores
      switch (_filtroEstado) {
        case 'ACTIVAS':
          // Para recolectores: órdenes que no estén RECOGIDO
          filtradas = filtradas.where((orden) => 
              orden.estado != 'RECOGIDO' && 
              orden.estado != 'CANCELADA').toList();
          break;
        case 'POR RECOGER':
          filtradas = filtradas.where((orden) => orden.estado == 'POR RECOGER').toList();
          break;
        case 'EN CAMINO':
          filtradas = filtradas.where((orden) => orden.estado == 'EN CAMINO').toList();
          break;
        case 'RECOGIDO':
          filtradas = filtradas.where((orden) => orden.estado == 'RECOGIDO').toList();
          break;
      }
    } else {
      // Filtros para repartidores (estados normales de envío)
      switch (_filtroEstado) {
        case 'ACTIVAS':
          print('🔍 [FILTRO] Aplicando filtro ACTIVAS');
          // Para REPARTIDORES MASTER: Incluir ENTREGADO EN SUCURSAL (para que puedan completar el flujo)
          // Para repartidores normales: Excluir ENTREGADO, CANCELADA y ENTREGADO EN SUCURSAL
          if (_esRepartidorMaster) {
            // MASTER: Solo excluir ENTREGADO y CANCELADA, pero INCLUIR ENTREGADO EN SUCURSAL
            filtradas = filtradas.where((orden) => 
                orden.estado != 'ENTREGADO' && 
                orden.estado != 'CANCELADA').toList();
            print('👑 [FILTRO MASTER] Después de filtrar ACTIVAS (incluye ENTREGADO EN SUCURSAL): ${filtradas.length} órdenes');
          } else {
            // NORMAL: Excluir ENTREGADO, CANCELADA y ENTREGADO EN SUCURSAL
            filtradas = filtradas.where((orden) => 
                orden.estado != 'ENTREGADO' && 
                orden.estado != 'CANCELADA' &&
                orden.estado != 'ENTREGADO EN SUCURSAL').toList();
            print('🔍 [FILTRO NORMAL] Después de filtrar ACTIVAS: ${filtradas.length} órdenes');
          }
          for (var orden in filtradas) {
            print('   - Orden #${orden.numeroOrden}: estado=${orden.estado}, recogerEnSucursal=${orden.recogerEnSucursal}');
          }
          // Incluir órdenes en "EN REPARTO" como activas
          break;
        case 'ENTREGADAS':
          // Incluir tanto ENTREGADO como ENTREGADO EN SUCURSAL
          filtradas = filtradas.where((orden) => 
              orden.estado == 'ENTREGADO' || 
              orden.estado == 'ENTREGADO EN SUCURSAL').toList();
          print('🔍 [FILTRO] ENTREGADAS incluye ENTREGADO y ENTREGADO EN SUCURSAL: ${filtradas.length} órdenes');
          break;
        case 'URGENTES':
          filtradas = filtradas.where((orden) => orden.esUrgente).toList();
          break;
        case 'ATRASADAS':
          filtradas = filtradas.where((orden) => 
              orden.estado == 'ATRASADO' || 
              (orden.fechaEstimadaEntrega != null && orden.fechaEstimadaEntrega!.isBefore(DateTime.now()) && orden.estado != 'ENTREGADO')).toList();
          break;
      }
    }

    // Filtrar por repartidor (solo para master)
    if (_esRepartidorMaster && _filtroRepartidor == 'MÍAS') {
      filtradas = filtradas.where((orden) {
        return orden.repartidor == _repartidorNombre;
      }).toList();
    }

    // Filtrar por búsqueda
    final query = _searchController.text.toLowerCase();
    if (query.isNotEmpty) {
      filtradas = filtradas.where((orden) {
        // Extraer solo números de la búsqueda para búsqueda flexible
        final queryNumerico = query.replaceAll(RegExp(r'[^0-9]'), '');
        
        // Buscar en número de orden (texto completo y solo números)
        final numeroOrdenTexto = orden.numeroOrden?.toLowerCase() ?? '';
        final numeroOrdenMatch = numeroOrdenTexto.contains(query);
        final numeroOrdenNumerico = numeroOrdenTexto.replaceAll(RegExp(r'[^0-9]'), '');
        final numeroOrdenMatchNumerico = queryNumerico.isNotEmpty && numeroOrdenNumerico.contains(queryNumerico);
        
        // CRÍTICO: Buscar también en número de remesa (para remesas puras)
        final numeroRemesaTexto = (orden.numeroRemesa ?? '').toLowerCase();
        final numeroRemesaMatch = numeroRemesaTexto.isNotEmpty && numeroRemesaTexto.contains(query);
        final numeroRemesaNumerico = numeroRemesaTexto.replaceAll(RegExp(r'[^0-9]'), '');
        final numeroRemesaMatchNumerico = queryNumerico.isNotEmpty && numeroRemesaNumerico.isNotEmpty && numeroRemesaNumerico.contains(queryNumerico);
        
        // Buscar en otros campos
        final emisorMatch = orden.emisor.toLowerCase().contains(query);
        final receptorMatch = orden.receptor.toLowerCase().contains(query);
        final direccionMatch = orden.direccionDestino.toLowerCase().contains(query);
        
        final resultado = numeroOrdenMatch || numeroRemesaMatch || numeroOrdenMatchNumerico || numeroRemesaMatchNumerico || emisorMatch || receptorMatch || direccionMatch;
        
        // Log para debugging de remesas (solo si contiene parte de la búsqueda o si buscamos específicamente)
        final queryNumericoLog = query.replaceAll(RegExp(r'[^0-9]'), ''); // Extraer solo números
        final numeroOrdenNumericoLog = orden.numeroOrden?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
        final numeroRemesaNumericoLog = (orden.numeroRemesa ?? '').replaceAll(RegExp(r'[^0-9]'), '');
        
        // Log si es remesa y contiene la búsqueda en números o si buscamos "2152"
        if (orden.tieneRemesa && (queryNumericoLog.isNotEmpty && (numeroOrdenNumericoLog.contains(queryNumericoLog) || numeroRemesaNumericoLog.contains(queryNumericoLog)) || query == '2152')) {
          print('🔍 [BÚSQUEDA] Remesa #${orden.numeroRemesa ?? orden.numeroOrden}: numeroOrden="${orden.numeroOrden}" numeroRemesa="${orden.numeroRemesa}", numeroOrdenMatch=$numeroOrdenMatch, numeroRemesaMatch=$numeroRemesaMatch, query="$query", queryNumerico="$queryNumericoLog"');
        }
        
        return resultado;
      }).toList();
      
      // Log final de búsqueda
      if (query.isNotEmpty && _esRepartidorMaster) {
        final remesasEnResultados = filtradas.where((o) => o.tieneRemesa).toList();
        print('🔍 [BÚSQUEDA MASTER] Query: "$query" - Resultados: ${filtradas.length} totales, ${remesasEnResultados.length} remesas');
        for (var remesa in remesasEnResultados) {
          print('   ✅ Remesa encontrada: #${remesa.numeroRemesa ?? remesa.numeroOrden}');
        }
      }
    }

    // Aplicar ordenamiento según configuración
    filtradas = _aplicarOrdenamiento(filtradas);

    // Guardar en caché
    _ordenesFiltradasCache = filtradas;
    _cacheKeyFiltradas = nuevaCacheKey;
    
    // Log solo cuando se recalcula (no en cada acceso)
    print('🔍 [FILTRO] Recalculado: ${filtradas.length} órdenes filtradas (filtro: $_filtroEstado)');

    return filtradas;
  }

  List<Orden> _aplicarOrdenamiento(List<Orden> ordenes) {
    // Separar órdenes bloqueadas (POR ENVIAR) de las activas
    final ordenesActivas = ordenes.where((orden) => 
      orden.estado.trim().toUpperCase() != 'POR ENVIAR'
    ).toList();
    
    final ordenesBloqueadas = ordenes.where((orden) => 
      orden.estado.trim().toUpperCase() == 'POR ENVIAR'
    ).toList();
    
    // Crear una copia para no modificar la lista original
    var ordenadasActivas = List<Orden>.from(ordenesActivas);
    var ordenadasBloqueadas = List<Orden>.from(ordenesBloqueadas);

    // Si hay que ordenar por distancia, necesitamos calcular las distancias primero
    Map<String, double>? distancias;
    if (_ordenarPorDistancia && _ubicacionActual != null) {
      distancias = _calcularDistancias(ordenadasActivas);
    }

    // Función de ordenamiento para órdenes activas
    void ordenarLista(List<Orden> lista) {
      lista.sort((a, b) {
      int comparacion = 0;

      // 0. PRIORIDAD ABSOLUTA: Si hay ruta optimizada, ordenar por orden_ruta primero
      if (a.ordenRuta != null && b.ordenRuta != null) {
        comparacion = a.ordenRuta!.compareTo(b.ordenRuta!);
        if (comparacion != 0) return comparacion;
      } else if (a.ordenRuta != null && b.ordenRuta == null) {
        return -1; // a tiene orden_ruta, b no -> a primero
      } else if (a.ordenRuta == null && b.ordenRuta != null) {
        return 1; // b tiene orden_ruta, a no -> b primero
      }

      // 1. PRIORIDAD: Órdenes urgentes primero (si está activado)
      if (_prioridadUrgentes) {
        if (a.esUrgente && !b.esUrgente) return -1; // a es urgente, b no -> a primero
        if (!a.esUrgente && b.esUrgente) return 1;  // b es urgente, a no -> b primero
        // Si ambas son urgentes o ambas no son urgentes, continuar con otros criterios
      }

      // 2. ORDENAR POR DISTANCIA: Las más cercanas primero (si está activado y hay ubicación)
      if (_ordenarPorDistancia && distancias != null) {
        final distanciaA = distancias[a.id] ?? double.infinity;
        final distanciaB = distancias[b.id] ?? double.infinity;
        comparacion = distanciaA.compareTo(distanciaB); // Ascendente (más cercanas primero)
        if (comparacion != 0) return comparacion;
      }

      // 3. ORDENAR POR FECHA: Las más antiguas primero (si está activado)
      if (_ordenarPorFecha) {
        final fechaA = a.fechaCreacion;
        final fechaB = b.fechaCreacion;
        comparacion = fechaA.compareTo(fechaB); // Ascendente (más antiguas primero)
        if (comparacion != 0) return comparacion;
      }

      // Si ninguna opción está activada o no hay diferencia, usar fecha descendente por defecto
      if (comparacion == 0) {
        final fechaA = a.fechaCreacion;
        final fechaB = b.fechaCreacion;
        comparacion = fechaB.compareTo(fechaA); // Descendente por defecto (más recientes primero)
      }

      return comparacion;
    });
    }
    
    // Ordenar órdenes activas
    ordenarLista(ordenadasActivas);
    
    // Ordenar órdenes bloqueadas solo por fecha (más recientes primero)
    ordenadasBloqueadas.sort((a, b) {
      return b.fechaCreacion.compareTo(a.fechaCreacion);
    });

    // Combinar: primero las activas, luego las bloqueadas
    return [...ordenadasActivas, ...ordenadasBloqueadas];
  }

  // Calcular distancias desde la ubicación actual a cada orden
  Map<String, double> _calcularDistancias(List<Orden> ordenes) {
    final distancias = <String, double>{};
    
    if (_ubicacionActual == null) return distancias;

    for (var orden in ordenes) {
      double distancia = double.infinity;
      
      // Intentar obtener coordenadas de la orden desde la base de datos
      // Si la orden tiene latitud/longitud en la BD, usarlas
      // Por ahora, como las órdenes no tienen coordenadas GPS almacenadas,
      // usamos un ordenamiento aproximado basado en provincia/municipio
      // o simplemente ordenamos por fecha como fallback
      
      // TODO: Cuando se agreguen coordenadas GPS a las órdenes, calcular distancia real:
      // if (orden.latitudDestino != null && orden.longitudDestino != null) {
      //   distancia = Geolocator.distanceBetween(
      //     _ubicacionActual!.latitude,
      //     _ubicacionActual!.longitude,
      //     orden.latitudDestino!,
      //     orden.longitudDestino!,
      //   );
      // }
      
      // Por ahora, usar un valor basado en la fecha de creación como proxy
      // (órdenes más recientes = más cercanas en tiempo, no en espacio)
      // Esto es un placeholder hasta que se agreguen coordenadas GPS
      final diasDesdeCreacion = DateTime.now().difference(orden.fechaCreacion).inDays;
      distancia = diasDesdeCreacion * 1000.0; // Convertir días a "metros" aproximados
      
      distancias[orden.id] = distancia;
    }

    return distancias;
  }

  // Obtener ubicación actual del repartidor
  Future<void> _obtenerUbicacionActual() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      if (mounted) {
        setState(() {
          _ubicacionActual = position;
        });
        print('📍 Ubicación actual obtenida: ${position.latitude}, ${position.longitude}');
      }
    } catch (e) {
      print('⚠️ Error al obtener ubicación actual: $e');
      // No es crítico, el ordenamiento funcionará sin distancia
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fondoGeneral,
      appBar: AppBar(
        backgroundColor: AppColors.header,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            // Foto de perfil circular
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFFF9800),
                shape: BoxShape.circle,
              ),
              child: ClipOval(
                child: _fotoPerfilUrl != null && _fotoPerfilUrl!.isNotEmpty
                    ? Image.network(
                        _fotoPerfilUrl!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Text(
                              _repartidorNombre != null && _repartidorNombre!.isNotEmpty
                                  ? _repartidorNombre![0].toUpperCase()
                                  : 'R',
                              style: const TextStyle(
                                color: Color(0xFFFFFFFF),
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      )
                    : Center(
                        child: Text(
                          _repartidorNombre != null && _repartidorNombre!.isNotEmpty
                              ? _repartidorNombre![0].toUpperCase()
                              : 'R',
                          style: const TextStyle(
                            color: Color(0xFFFFFFFF),
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 8),
            // Nombre del repartidor - Usar Expanded para evitar overflow
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Repartidor',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_repartidorNombre != null)
                    Text(
                      _repartidorNombre!,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                ],
              ),
            ),
            // Indicador de estado de conexión - Más compacto
            const SizedBox(width: 4),
            Icon(
              _isOnline ? Icons.cloud_done : Icons.cloud_off,
              color: _isOnline ? const Color(0xFF4CAF50) : const Color(0xFFFF9800),
              size: 18,
            ),
            if (_operacionesPendientes > 0) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: () async {
                  // Botón para sincronizar manualmente
                  final syncService = SyncService();
                  
                  // Verificar conexión antes de sincronizar
                  if (!_isOnline) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('📴 Sin conexión a internet. Conecta a una red para sincronizar.'),
                          backgroundColor: Colors.orange,
                          duration: Duration(seconds: 3),
                        ),
                      );
                    }
                    return;
                  }
                  
                  // Mostrar diálogo de sincronización
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (context) => AlertDialog(
                      title: const Text('Sincronización'),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text('Verificando conexión y sincronizando $_operacionesPendientes operación${_operacionesPendientes > 1 ? "es" : ""} pendiente${_operacionesPendientes > 1 ? "s" : ""}...'),
                        ],
                      ),
                    ),
                  );
                  
                  // Intentar sincronizar (verifica conexión a Supabase internamente)
                  final success = await syncService.syncPendingOperations();
                  
                  // Cerrar diálogo
                  if (mounted) Navigator.of(context).pop();
                  
                  // Mostrar resultado
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          success 
                            ? '✅ Sincronización exitosa. Base de datos actualizada.' 
                            : '⚠️ No se pudo conectar a la base de datos. Se reintentará automáticamente cuando haya conexión.',
                        ),
                        backgroundColor: success ? Colors.green : Colors.orange,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                    
                    // Recargar órdenes después de sincronizar (siempre, para reflejar cambios)
                    _cargarOrdenes();
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9800),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Center(
                    child: Text(
                      '$_operacionesPendientes',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          // Icono de notificaciones de órdenes
          IconButton(
            onPressed: () {
              // Navegar a la pantalla de notificaciones
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const NotificacionesRepartidorScreen(),
                ),
              ).then((_) {
                // Recargar órdenes y actualizar contador de notificaciones al regresar
              _cargarOrdenes();
                _cargarNotificacionesNoLeidas();
              });
            },
            icon: Stack(
              children: [
                const Icon(
                  Icons.notifications,
                  color: Colors.white,
                  size: 24,
                ),
                if (_notificacionesNoLeidas > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9800),
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        _notificacionesNoLeidas > 99 ? '99+' : '${_notificacionesNoLeidas}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () async {
              // Actualizar contador antes de navegar para mostrar el badge correcto
              await _cargarMensajesNoLeidos();
              // NO marcar mensajes como leídos aquí - solo se marcarán cuando se entre a una conversación específica
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ChatRepartidorListaScreen(),
                ),
              );
              // Actualizar contador al volver del chat
              await _cargarMensajesNoLeidos();
            },
            icon: Stack(
              children: [
                const Icon(
                  Icons.chat_bubble,
                  color: Colors.white,
                  size: 24,
                ),
                if (_mensajesNoLeidos > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        _mensajesNoLeidos > 99 ? '99+' : _mensajesNoLeidos.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: 'Chat de Soporte',
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => QRScannerFullscreen(
                    repartidorNombre: _repartidorNombre,
                    esRepartidorMaster: _esRepartidorMaster,
                  ),
                ),
              );
            },
            icon: const Icon(
              Icons.qr_code_scanner,
              color: Colors.white,
              size: 28,
            ),
            tooltip: 'Escanear Orden',
          ),
          IconButton(
            onPressed: () async {
              final resultado = await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const RepartidorPerfilScreen(),
                ),
              );
              // Si se solicitó un pago, recargar el saldo (se reseteará a 0)
              if (resultado == true) {
                await _cargarSaldo();
              }
            },
            icon: const Icon(
              Icons.person,
              color: Colors.white,
              size: 28,
            ),
            tooltip: 'Mi Perfil',
          ),
          IconButton(
            onPressed: () async {
              print('🔄 Botón actualizar presionado...');
              await _cargarOrdenes();
              await _cargarMensajesNoLeidos();
              _mostrarMensaje('Datos actualizados');
            },
            icon: const Icon(
              Icons.refresh,
              color: Colors.white,
              size: 24,
            ),
            tooltip: 'Cerrar Sesión',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          print('🔄 Pull-to-refresh activado...');
          
          // 🔒 CRÍTICO: Sincronizar cambios pendientes ANTES de recargar órdenes
          final syncService = SyncService();
          if (syncService.hasPendingOperations) {
            print('🔄 Sincronizando ${syncService.pendingOperationsCount} operación${syncService.pendingOperationsCount > 1 ? "es" : ""} pendiente${syncService.pendingOperationsCount > 1 ? "s" : ""}...');
            
            // Verificar conexión antes de sincronizar
            if (_isOnline) {
              await syncService.syncPendingOperations();
            } else {
              print('📴 Sin conexión - No se puede sincronizar');
            }
          }
          
          await _cargarOrdenes();
          await _cargarMensajesNoLeidos();
        },
        child: Column(
        children: [
          // Banner de notificación general (si existe y no está leída)
          if (_notificacionGeneralBanner != null && !(_notificacionGeneralBanner!['leida'] ?? false))
            _buildBannerNotificacion(),
          
          // ✅ BANNER "REPARTIDOR MASTER" - Solo visible para repartidores master
          if (_esRepartidorMaster)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFF9800),
                    const Color(0xFFFFB74D),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF9800).withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.workspace_premium,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Repartidor Master',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          
          // ✅ INDICADOR DE MODO OFFLINE
          if (!_isOnline)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.orange.shade100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_off, color: Colors.orange.shade900, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Sin conexión - Mostrando datos guardados',
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  if (_operacionesPendientes > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade700,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_operacionesPendientes pendiente${_operacionesPendientes > 1 ? "s" : ""}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          
          // Barra de búsqueda
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              key: const ValueKey('search_field'), // Key para mantener estado
              controller: _searchController,
              focusNode: _searchFocusNode, // FocusNode para mantener el foco
              decoration: InputDecoration(
                hintText: 'Buscar órdenes...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF1976D2)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: const BorderSide(color: Color(0xFF1976D2), width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                filled: true,
                fillColor: const Color(0xFFF8F9FA),
              ),
            ),
          ),

          // Botón "Ver Ruta Optimizada" si hay órdenes con orden_ruta
          if (_tieneRutaOptimizada)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.white,
              child: Center(
                child: ElevatedButton.icon(
                  onPressed: () => _mostrarRutaOptimizada(),
                  icon: const Icon(Icons.route, size: 20),
                  label: const Text(
                    'Ver Ruta Optimizada',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
            ),

          // Filtros de estado (diferentes según tipo de usuario)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (_esRecolector) ...[
                    // Filtros específicos para recolectores
                    _buildFiltroChip('ACTIVAS', _filtroEstado == 'ACTIVAS'),
                    const SizedBox(width: 8),
                    _buildFiltroChip('POR RECOGER', _filtroEstado == 'POR RECOGER'),
                    const SizedBox(width: 8),
                    _buildFiltroChip('EN CAMINO', _filtroEstado == 'EN CAMINO'),
                    const SizedBox(width: 8),
                    _buildFiltroChip('RECOGIDO', _filtroEstado == 'RECOGIDO'),
                  ] else ...[
                    // Filtros para repartidores (estados normales)
                    _buildFiltroChip('ACTIVAS', _filtroEstado == 'ACTIVAS'),
                    // Filtro adicional para repartidores master (mostrar de primero después de ACTIVAS)
                    if (_esRepartidorMaster) ...[
                      const SizedBox(width: 8),
                      _buildFiltroRepartidorChip('MÍAS', _filtroRepartidor == 'MÍAS'),
                      const SizedBox(width: 8),
                      _buildFiltroRepartidorChip('TODAS', _filtroRepartidor == null),
                    ],
                    const SizedBox(width: 8),
                    _buildFiltroChip('URGENTES', _filtroEstado == 'URGENTES'),
                    const SizedBox(width: 8),
                    _buildFiltroChip('ATRASADAS', _filtroEstado == 'ATRASADAS'),
                    const SizedBox(width: 8),
                    _buildFiltroChip('ENTREGADAS', _filtroEstado == 'ENTREGADAS'),
                  ],
                ],
              ),
            ),
          ),

          // Contador de resultados
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_ordenesFiltradas.length} órdenes encontradas',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF666666),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_filtroEstado == 'URGENTES' && _ordenesFiltradas.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'URGENTE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Lista de órdenes
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF1976D2),
                    ),
                  )
                : _ordenesFiltradas.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: () async {
                          print('🔄 Pull-to-refresh en lista activado...');
                          
                          // 🔒 CRÍTICO: Sincronizar cambios pendientes ANTES de recargar órdenes
                          final syncService = SyncService();
                          if (syncService.hasPendingOperations) {
                            print('🔄 Sincronizando ${syncService.pendingOperationsCount} operación${syncService.pendingOperationsCount > 1 ? "es" : ""} pendiente${syncService.pendingOperationsCount > 1 ? "s" : ""}...');
                            
                            // Verificar conexión antes de sincronizar
                            if (_isOnline) {
                              await syncService.syncPendingOperations();
                            } else {
                              print('📴 Sin conexión - No se puede sincronizar');
                            }
                          }
                          
                          await _cargarConfiguracionPrioridad(); // Recargar configuración de prioridad
                          await _cargarOrdenes();
                          await _cargarMensajesNoLeidos();
                        },
                        color: const Color(0xFF1976D2),
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 100), // Padding extra al final para que la última orden sea visible
                          itemCount: _ordenesFiltradas.length,
                          itemBuilder: (context, index) {
                            final orden = _ordenesFiltradas[index];
                            return _buildOrdenCard(orden);
                          },
                        ),
                      ),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildFiltroChip(String label, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _filtroEstado = label;
          _ordenesFiltradasCache = null; // Invalidar caché cuando cambie el filtro
          _cacheKeyFiltradas = null;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1976D2) : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[700],
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildFiltroRepartidorChip(String label, bool isSelected) {
    // Color verde para "MÍAS", naranja para "TODAS"
    final bool esMias = label == 'MÍAS';
    final Color colorSeleccionado = esMias ? const Color(0xFF4CAF50) : const Color(0xFFFF9800);
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _filtroRepartidor = label == 'MÍAS' ? 'MÍAS' : null;
          _ordenesFiltradasCache = null; // Invalidar caché cuando cambie el filtro
          _cacheKeyFiltradas = null;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? colorSeleccionado : Colors.grey[200],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? colorSeleccionado : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (esMias)
              const Icon(
                Icons.person,
                color: Colors.white,
                size: 14,
              ),
            if (esMias) const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No hay órdenes',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No tienes órdenes asignadas en este momento',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // Detectar si es una remesa pura (no una orden con remesa)
  bool _esRemesaPura(Orden orden) {
    // Verificar que tenga remesa
    if (!orden.tieneRemesa) {
      return false;
    }
    
    // Verificar peso (debe ser 0 o null)
    final peso = orden.peso ?? 0.0;
    if (peso > 0) {
      return false;
    }
    
    // Verificar items adicionales (debe ser null o vacío)
    final tieneItemsAdicionales = orden.itemsAdicionales != null && 
                                  orden.itemsAdicionales is List && 
                                  (orden.itemsAdicionales as List).isNotEmpty;
    if (tieneItemsAdicionales) {
      return false;
    }
    
    // Si tiene remesa, peso = 0 y sin items adicionales, es remesa pura
    // NO verificar descripción porque puede variar o estar vacía
    
    // Log para debugging (solo primera vez o si hay problema)
    final numeroRemesaLog = orden.numeroRemesa ?? orden.numeroOrden ?? 'N/A';
    print('✅ [DETECCIÓN REMESA PURA] Remesa pura detectada: #$numeroRemesaLog');
    print('   - tieneRemesa: ${orden.tieneRemesa}');
    print('   - peso: $peso');
    print('   - tieneItems: $tieneItemsAdicionales');
    print('   - descripcion: "${orden.descripcion}" (no se verifica)');
    
    return true; // Es remesa pura
  }

  // Tarjeta especial para remesas (estilo dorado/amarillo como en web)
  Widget _buildRemesaCard(Orden orden) {
    // ✅ Obtener número desde BD, usar ID como fallback si no hay número
    final numeroRemesa = orden.numeroRemesa?.isNotEmpty == true 
        ? orden.numeroRemesa 
        : (orden.numeroOrden.isNotEmpty 
            ? orden.numeroOrden 
            : (orden.id.length > 8 ? orden.id.substring(0, 8) : orden.id)); // Usar primeros 8 caracteres del ID como fallback
    final cantidadRemesa = orden.cantidadRemesa ?? 0.0;
    // Estados: POR ENVIAR, ENTREGADO EN SUCURSAL (solo si recoger_en_sucursal), ENTREGADO
    final estado = orden.estado == 'ENTREGADO' 
        ? 'ENTREGADO' 
        : orden.estado == 'ENTREGADO EN SUCURSAL'
            ? 'ENTREGADO EN SUCURSAL'
            : 'POR ENVIAR';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFFD700).withOpacity(0.2), // Dorado claro
            const Color(0xFFFFA500).withOpacity(0.15), // Naranja claro
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFFFD700).withOpacity(0.8),
          width: 2,
        ),
      ),
      child: InkWell(
        onTap: () => _mostrarDetallesOrden(orden),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header con número de remesa y estado
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      // Badge de REMESA
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                          ),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFFD700).withOpacity(0.5),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.attach_money, color: Colors.white, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              'REMESA',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Número de remesa
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '#${numeroRemesa ?? (orden.id.length > 8 ? orden.id.substring(0, 8) : orden.id)}',
                          style: const TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Chip de estado (solo POR ENVIAR o ENTREGADO)
                  _buildRemesaStatusChip(estado),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Cantidad a cobrar destacada
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFFFD700).withOpacity(0.3),
                      const Color(0xFFFFA500).withOpacity(0.2),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFFFD700),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.monetization_on, color: Color(0xFFFFD700), size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Cantidad: \$${cantidadRemesa.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 12),
              
              // Información del emisor y destinatario
              _buildInfoRow(Icons.person, 'Emisor:', orden.emisor),
              const SizedBox(height: 4),
              _buildInfoRow(Icons.person_outline, 'Destinatario:', orden.receptor),
              const SizedBox(height: 4),
              
              // Mostrar dirección según recoger_en_sucursal
              if (orden.recogerEnSucursal && _sucursalesInfo.containsKey(orden.id)) ...[
                // Si es recogida en sucursal: mostrar información de sucursal
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF4CAF50), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.store, color: const Color(0xFF4CAF50), size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Recoger en Sucursal: ${_sucursalesInfo[orden.id]!['nombre'] ?? 'Sin nombre'}',
                              style: const TextStyle(
                                color: Color(0xFF4CAF50),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _buildInfoRow(
                        Icons.location_on,
                        'Dirección Sucursal:',
                        _formatearDireccionSucursal(_sucursalesInfo[orden.id]!),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ] else if (orden.direccionDestino.isNotEmpty) ...[
                // Si NO es recogida en sucursal: mostrar dirección del destinatario
                _buildInfoRow(
                  Icons.location_on, 
                  'Dirección:', 
                  _formatearDireccionCompleta(orden),
                ),
                const SizedBox(height: 4),
              ],
              
              // Botón de acción según el estado
              if (estado == 'POR ENVIAR') ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (orden.recogerEnSucursal) {
                        // Si es recogida en sucursal: botón "Entregado en Sucursal"
                        _marcarRemesaEntregadaEnSucursal(orden);
                      } else {
                        // Si NO es recogida en sucursal: navegar a detalles para flujo completo
                        _mostrarDetallesOrden(orden);
                      }
                    },
                    icon: Icon(
                      orden.recogerEnSucursal ? Icons.store : Icons.check_circle,
                      size: 18,
                    ),
                    label: Text(
                      orden.recogerEnSucursal 
                          ? 'Entregado en Sucursal'
                          : 'Entregar Remesa',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: orden.recogerEnSucursal 
                          ? const Color(0xFFFF9800) 
                          : const Color(0xFFFFD700),
                      foregroundColor: const Color(0xFF1A1A1A),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
              
              // 👑 BOTÓN para MASTERS: Si está ENTREGADO EN SUCURSAL, permitir completar la entrega
              if (estado == 'ENTREGADO EN SUCURSAL' && _esRepartidorMaster) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9800).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFFF9800), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline, color: const Color(0xFFFF9800), size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'La remesa está en sucursal. Como Master, puedes completar la entrega.',
                              style: TextStyle(
                                color: const Color(0xFF666666),
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _marcarRemesaComoEntregada(orden),
                          icon: const Icon(Icons.check_circle, size: 18),
                          label: const Text('Marcar como Entregado'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4CAF50),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
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
    );
  }

  // Chip de estado especial para remesas (POR ENVIAR, ENTREGADO EN SUCURSAL, ENTREGADO)
  Widget _buildRemesaStatusChip(String estado) {
    Color color;
    IconData icon;
    if (estado == 'ENTREGADO') {
      color = const Color(0xFF4CAF50); // Verde para entregado
      icon = Icons.check_circle;
    } else if (estado == 'ENTREGADO EN SUCURSAL') {
      color = const Color(0xFFFF9800); // Naranja para entregado en sucursal
      icon = Icons.store;
    } else {
      color = const Color(0xFF9E9E9E); // Gris para por enviar
      icon = Icons.schedule;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text(
            estado,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdenCard(Orden orden) {
    // Si es remesa pura, usar tarjeta especial
    if (_esRemesaPura(orden)) {
      return _buildRemesaCard(orden);
    }
    
    final esUrgente = orden.esUrgente;
    final esAtrasada = orden.fechaEstimadaEntrega != null && 
                      orden.fechaEstimadaEntrega!.isBefore(DateTime.now()) && 
                      orden.estado != 'ENTREGADO';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: esUrgente ? const Color(0xFFFFEBEE) : const Color(0xFFE0E0E0),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
        border: esUrgente 
            ? Border.all(color: const Color(0xFFDC2626), width: 2)
            : Border.all(color: Colors.black, width: 2),
      ),
      child: InkWell(
        onTap: () => _mostrarDetallesOrden(orden),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header con número y estado
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1976D2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '#${orden.numeroOrden.isNotEmpty ? orden.numeroOrden : (orden.id.length > 8 ? orden.id.substring(0, 8) : orden.id)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (esUrgente) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.warning, color: Colors.white, size: 10),
                              SizedBox(width: 1),
                              Text(
                                'URGENTE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  // Iconos indicadores en la esquina superior derecha
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Icono de firma requerida
                      if (orden.requiereFirma)
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF9C27B0).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFF9C27B0),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.edit,
                            color: Color(0xFF9C27B0),
                            size: 14,
                          ),
                        ),
                      // Icono de remesa
                      if (orden.tieneRemesa)
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2196F3).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFF2196F3),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.attach_money,
                            color: Color(0xFF2196F3),
                            size: 14,
                          ),
                        ),
                      // Icono de cobrar dinero contra entrega
                      if (orden.requierePago && !orden.pagado)
                        Container(
                          margin: const EdgeInsets.only(right: 4),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF9800).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFFFF9800),
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(
                            Icons.payment,
                            color: Color(0xFFFF9800),
                            size: 14,
                          ),
                        ),
                      // Chip de estado
                      _buildStatusChip(orden.estado, esAtrasada),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Información del repartidor asignado (solo para master)
              if (_esRepartidorMaster && orden.repartidor != null && orden.repartidor!.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: orden.repartidor == _repartidorNombre 
                          ? const Color(0xFF4CAF50).withOpacity(0.1)
                          : const Color(0xFFFF9800).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: orden.repartidor == _repartidorNombre 
                            ? const Color(0xFF4CAF50)
                            : const Color(0xFFFF9800),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          orden.repartidor == _repartidorNombre 
                              ? Icons.person
                              : Icons.person_outline,
                          color: orden.repartidor == _repartidorNombre 
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFFF9800),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            orden.repartidor == _repartidorNombre 
                                ? 'MI ORDEN'
                                : 'Asignada a: ${orden.repartidor}',
                            style: TextStyle(
                              color: orden.repartidor == _repartidorNombre 
                                  ? const Color(0xFF4CAF50)
                                  : const Color(0xFFFF9800),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Información del emisor y destinatario/cliente (según tipo de orden)
              if (orden.tipoOrden == 'RECOGIDA') ...[
                // Para órdenes de recogida: mostrar información completa del cliente
                // Badge indicador de tipo RECOGIDA
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9800).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFFF9800), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_shipping, color: const Color(0xFFFF9800), size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'ORDEN DE RECOGIDA',
                        style: TextStyle(
                          color: const Color(0xFFFF9800),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // Información del cliente
                _buildInfoRow(Icons.person, 'Cliente:', orden.emisor),
                // Teléfono del cliente si está disponible
                if (orden.telefonoDestinatario != null && orden.telefonoDestinatario!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _buildInfoRow(Icons.phone, 'Teléfono:', orden.telefonoDestinatario!),
                ],
                const SizedBox(height: 4),
                // Dirección de recogida completa
                _buildInfoRow(
                  Icons.location_on, 
                  'Dirección de Recogida:', 
                  _formatearDireccionCompleta(orden),
                ),
              ] else ...[
                // Para órdenes de envío: mostrar emisor y destinatario
                _buildInfoRow(Icons.person, 'De:', orden.emisor),
                const SizedBox(height: 4),
                _buildInfoRow(Icons.person_outline, 'Para:', orden.receptor),
                const SizedBox(height: 4),
                
                // Si recoger_en_sucursal está activo, mostrar información de sucursal en recuadro resaltado
                if (orden.recogerEnSucursal && _sucursalesInfo.containsKey(orden.id)) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9), // Fondo verde claro más llamativo
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF4CAF50), width: 2),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.store, color: const Color(0xFF4CAF50), size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Recogida en Sucursal',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF2E7D32),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildInfoRow(
                          Icons.store,
                          'Sucursal:',
                          _sucursalesInfo[orden.id]!['nombre'] ?? 'Sin nombre',
                        ),
                        const SizedBox(height: 4),
                        _buildInfoRow(
                          Icons.location_on,
                          'Dirección:',
                          _formatearDireccionSucursal(_sucursalesInfo[orden.id]!),
                        ),
                        if (_sucursalesInfo[orden.id]!['es_principal'] == true) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star, color: Colors.white, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  'Sucursal Principal',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ] else ...[
                  // Mostrar dirección normal si no es recogida en sucursal
                  _buildInfoRow(
                    Icons.location_on, 
                    'Dirección:', 
                    _formatearDireccionCompleta(orden),
                  ),
                ],
              ],
              const SizedBox(height: 4),
              _buildInfoRow(Icons.inventory_2, 'Bultos:', orden.cantidadBultos.toString()),
              
              // Mostrar fecha de creación si es orden de GoodBarber
              if (orden.goodbarberOrderId != null) ...[
                const SizedBox(height: 4),
                _buildInfoRow(
                  Icons.calendar_today, 
                  'Creada (GoodBarber):', 
                  '${orden.fechaCreacion.day}/${orden.fechaCreacion.month}/${orden.fechaCreacion.year} ${orden.fechaCreacion.hour.toString().padLeft(2, '0')}:${orden.fechaCreacion.minute.toString().padLeft(2, '0')}',
                ),
              ],
              
              // Mostrar shipping_amount si está en items_adicionales (GoodBarber)
              if (orden.itemsAdicionales != null && orden.itemsAdicionales!.isNotEmpty) ...[
                const SizedBox(height: 4),
                ...orden.itemsAdicionales!.where((item) => 
                  item['nombre']?.toString().contains('Costo de Envío (GoodBarber)') == true
                ).map((item) {
                  final precio = (item['precio'] ?? 0.0).toDouble();
                  final moneda = orden.monedaPrecioTotalEnvio ?? orden.moneda;
                  return _buildInfoRow(
                    Icons.local_shipping,
                    'Costo Envío (GoodBarber):',
                    '${moneda == 'USD' ? '\$' : '\$'} ${precio.toStringAsFixed(2)} $moneda',
                  );
                }),
              ],

              if (orden.requierePago) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF4CAF50)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.attach_money, color: Color(0xFF4CAF50), size: 14),
                      const SizedBox(width: 4),
                      Text(
                        'Cobrar: ${orden.moneda == 'USD' ? '\$' : '\$'} ${orden.montoCobrar.toStringAsFixed(2)} ${orden.moneda}',
                        style: const TextStyle(
                          color: Color(0xFF4CAF50),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 8),

              // Fecha de entrega - En rectángulo destacado
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: orden.recogerEnSucursal
                      ? const Color(0xFFFFEBEE) // Fondo rojo claro para "Entregar en Sucursal"
                      : esAtrasada 
                          ? const Color(0xFFFFEBEE) 
                          : const Color(0xFFE3F2FD),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: orden.recogerEnSucursal
                        ? const Color(0xFFDC2626) // Borde rojo fuerte para "Entregar en Sucursal"
                        : esAtrasada 
                            ? const Color(0xFFDC2626) 
                            : const Color(0xFF1976D2),
                    width: orden.recogerEnSucursal ? 2.5 : 1.5, // Borde más grueso para "Entregar en Sucursal"
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                children: [
                    Icon(
                      orden.recogerEnSucursal ? Icons.store : Icons.schedule, 
                      color: orden.recogerEnSucursal
                          ? const Color(0xFFDC2626) // Icono rojo fuerte para "Entregar en Sucursal"
                          : esAtrasada 
                              ? const Color(0xFFDC2626) 
                              : const Color(0xFF1976D2), 
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                  Text(
                      orden.recogerEnSucursal
                          ? 'Entregar en Sucursal'
                          : orden.tipoOrden == 'RECOGIDA'
                              ? 'Recoger orden a más tardar ${_formatearFecha(orden.fechaEntrega)}'
                              : 'Entregar orden a más tardar ${_formatearFecha(orden.fechaEntrega)}',
                    style: TextStyle(
                        color: orden.recogerEnSucursal
                            ? const Color(0xFFDC2626) // Texto rojo fuerte para "Entregar en Sucursal"
                            : esAtrasada 
                                ? const Color(0xFFDC2626) 
                                : const Color(0xFF1976D2),
                      fontSize: 11,
                        fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                ),
              ),

              // Mostrar botón de acción si no está en estado final
              if (_esRecolector) ...[
                // Para recolectores: mostrar botón si no está RECOGIDO o CANCELADA
                if (orden.estado != 'RECOGIDO' && orden.estado != 'CANCELADA') ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: _buildBotonAccion(orden),
                  ),
                ],
              ] else ...[
                // Para repartidores: mostrar botón si no está ENTREGADO o CANCELADA
                if (orden.estado != 'ENTREGADO' && orden.estado != 'CANCELADA') ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: _buildBotonAccion(orden),
                  ),
                ],
              ],
              
              // Mensaje de bloqueo si está en POR ENVIAR (solo para órdenes de envío)
              if (orden.estado == 'POR ENVIAR' && orden.tipoOrden != 'RECOGIDA') ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFF9800), width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lock_outline, color: const Color(0xFFFF9800), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _obtenerMensajeOrdenBloqueada(),
                          style: TextStyle(
                            color: const Color(0xFFE65100),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
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
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF666666), size: 14),
        const SizedBox(width: 4),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                color: Color(0xFF666666),
                fontSize: 11,
              ),
              children: [
                TextSpan(
                  text: '$label ',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String estado, bool esAtrasada) {
    final estadoReal = esAtrasada ? 'ATRASADO' : estado;
    final color = _getStatusColor(estadoReal);
    final icon = _getStatusIcon(estadoReal);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text(
            estadoReal,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String estado) {
    switch (estado) {
      case 'ENTREGADO':
        return const Color(0xFF4CAF50);
      case 'RECOGIDO':
        return const Color(0xFF4CAF50); // Verde para "RECOGIDO" (similar a ENTREGADO)
      case 'LISTO PARA RECOGER':
        return const Color(0xFFFF9800); // Naranja para "LISTO PARA RECOGER"
      case 'EN REPARTO':
        return const Color(0xFFFF9800); // Naranja para "EN REPARTO"
      case 'EN CAMINO':
        return const Color(0xFFFF9800); // Naranja para "EN CAMINO" (similar a EN REPARTO)
      case 'EN TRANSITO':
        return const Color(0xFF2196F3);
      case 'POR ENVIAR':
        return const Color(0xFF9E9E9E); // Gris para "POR ENVIAR"
      case 'POR RECOGER':
        return const Color(0xFF9E9E9E); // Gris para "POR RECOGER"
      case 'CANCELADA':
        return const Color(0xFF9E9E9E);
      case 'ATRASADO':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  IconData _getStatusIcon(String estado) {
    switch (estado) {
      case 'ENTREGADO':
        return Icons.check_circle;
      case 'RECOGIDO':
        return Icons.check_circle; // Icono de check para "RECOGIDO"
      case 'LISTO PARA RECOGER':
        return Icons.store_mall_directory; // Icono de tienda para "LISTO PARA RECOGER"
      case 'EN REPARTO':
        return Icons.delivery_dining; // Icono de reparto
      case 'EN CAMINO':
        return Icons.directions_car; // Icono de carro para "EN CAMINO"
      case 'EN TRANSITO':
        return Icons.local_shipping;
      case 'POR ENVIAR':
        return Icons.schedule;
      case 'POR RECOGER':
        return Icons.schedule; // Icono de reloj para "POR RECOGER"
      case 'CANCELADA':
        return Icons.cancel;
      case 'ATRASADO':
        return Icons.warning;
      default:
        return Icons.help;
    }
  }

  String _formatearFecha(DateTime? fecha) {
    if (fecha == null) return 'No definida';
    return '${fecha.day}/${fecha.month}/${fecha.year}';
  }

  String _formatearDireccionCompleta(Orden orden) {
    final List<String> partes = [];
    
    if (orden.direccionDestino.isNotEmpty) {
      partes.add(orden.direccionDestino);
    }
    
    if (orden.municipioDestino != null && orden.municipioDestino!.isNotEmpty) {
      partes.add(orden.municipioDestino!);
    }
    
    if (orden.provinciaDestino != null && orden.provinciaDestino!.isNotEmpty) {
      partes.add(orden.provinciaDestino!);
    }
    
    if (partes.isEmpty) {
      return 'Dirección no especificada';
    }
    
    return partes.join(', ');
  }
  
  String _formatearDireccionSucursal(Map<String, dynamic> sucursal) {
    final direccion = sucursal['direccion'] ?? '';
    final municipio = sucursal['municipio'] ?? '';
    final provincia = sucursal['provincia'] ?? '';
    final pais = sucursal['pais'] ?? '';
    
    final partes = <String>[];
    if (direccion.isNotEmpty) partes.add(direccion);
    if (municipio.isNotEmpty) partes.add(municipio);
    if (provincia.isNotEmpty) partes.add(provincia);
    if (pais.isNotEmpty) partes.add(pais);
    
    return partes.isNotEmpty ? partes.join(', ') : 'Dirección no especificada';
  }

  // Marcar remesa como entregada en sucursal (solo para recoger_en_sucursal = true)
  Future<void> _marcarRemesaEntregadaEnSucursal(Orden orden) async {
    if (orden.estado == 'ENTREGADO' || orden.estado == 'ENTREGADO EN SUCURSAL') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta remesa ya está entregada'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
      return;
    }
    
    // Obtener nombre de sucursal
    String nombreSucursal = 'la sucursal';
    if (_sucursalesInfo.containsKey(orden.id)) {
      nombreSucursal = _sucursalesInfo[orden.id]!['nombre'] ?? 'la sucursal';
    }
    
    // Modal de confirmación
    final confirmado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.store, color: Color(0xFFFF9800), size: 28),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Entregar en Sucursal',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C2C2C),
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '¿Estás afirmando que la remesa #${orden.numeroRemesa ?? orden.numeroOrden} la estás entregando en $nombreSucursal?',
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF2C2C2C),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9800).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFF9800)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFFFF9800), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'La remesa quedará en $nombreSucursal esperando que la sucursal la entregue al destinatario final.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF666666),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9800),
              foregroundColor: Colors.white,
            ),
            child: const Text('Sí'),
          ),
        ],
      ),
    );
    
    if (confirmado != true) return;
    
    // Verificar conexión antes de intentar actualizar
    final syncService = SyncService();
    final isOnline = syncService.isOnline;
    
    // Actualizar estado localmente INMEDIATAMENTE para que la UI se actualice
    // Esto asegura que la orden siga visible para masters en el filtro ACTIVAS
    if (mounted) {
      setState(() {
        final index = _ordenes.indexWhere((o) => o.id == orden.id);
        if (index != -1) {
          // Actualizar el estado directamente (el campo estado es mutable)
          _ordenes[index].estado = 'ENTREGADO EN SUCURSAL';
          // Invalidar caché para que se recalcule el filtro
          _ordenesFiltradasCache = null;
          _cacheKeyFiltradas = null;
        }
      });
    }
    
    // Actualizar caché local de órdenes
    try {
      // Crear una nueva instancia de Orden con el estado actualizado
      final ordenJson = orden.toJson();
      ordenJson['estado'] = 'ENTREGADO EN SUCURSAL';
      final ordenActualizada = Orden.fromJson(ordenJson);
      await OrdenCacheService.updateCachedOrder(ordenActualizada);
      print('✅ Estado actualizado en caché local: ENTREGADO EN SUCURSAL');
    } catch (e) {
      print('⚠️ Error actualizando caché local: $e');
    }
    
    try {
      if (isOnline) {
        // Si hay conexión, actualizar directamente en Supabase
        print('🌐 Online - Actualizando estado en Supabase...');
        await supabase
            .from('ordenes')
            .update({
              'estado': 'ENTREGADO EN SUCURSAL',
            })
            .eq('id', orden.id);
        
        print('✅ Estado actualizado exitosamente en Supabase');
      } else {
        // Si NO hay conexión, agregar a cola de sincronización
        print('📴 Offline - Agregando operación a cola de sincronización...');
        await syncService.addOperation(
          type: 'update_orden_estado',
          ordenId: orden.id,
          data: {
            'estado': 'ENTREGADO EN SUCURSAL',
          },
        );
        print('✅ Operación agregada a cola de sincronización');
      }
      
      // Sincronizar con GoodBarber y enviar email solo si hay conexión
      if (isOnline) {
        // Sincronizar con GoodBarber si la orden está vinculada
        try {
          await GoodBarberSyncService.sincronizarEstadoAGoodBarber(
            supabase,
            orden.id,
            'ENTREGADO EN SUCURSAL',
          );
        } catch (e) {
          print('⚠️ Error sincronizando estado con GoodBarber: $e');
        }
        
        // Obtener datos actualizados de la orden para enviar email
        try {
          final ordenData = await supabase
              .from('ordenes')
              .select('*')
              .eq('id', orden.id)
              .single();
          
          final ordenActualizada = Orden.fromJson(ordenData);
          final tenantId = ordenData['tenant_id']?.toString() ?? ordenActualizada.tenantId;
          
          // Obtener email del emisor y enviar email
          String? emailEmisor;
          final emisorNombre = ordenData['emisor']?.toString() ?? ordenActualizada.emisor;
          
          if (emisorNombre.isNotEmpty && emisorNombre != 'Sin emisor') {
            try {
              final emisorData = await supabase
                  .from('emisores')
                  .select('email')
                  .eq('nombre', emisorNombre)
                  .eq('tenant_id', tenantId ?? '')
                  .maybeSingle();
              
              emailEmisor = emisorData?['email']?.toString();
            } catch (e) {
              print('⚠️ Error obteniendo email del emisor: $e');
            }
          }
          
          // Enviar email si está habilitado
          if (emailEmisor != null && emailEmisor.isNotEmpty) {
            final configService = ConfiguracionService();
            final notificacionesHabilitadas = await configService.notificacionesHabilitadas('emisores');
            
            if (notificacionesHabilitadas) {
              try {
                // Usar el mismo servicio de email que para órdenes entregadas
                final enviado = await EmailService.enviarEmailOrdenEntregada(ordenActualizada, emailEmisor, tenantId: tenantId);
                if (enviado) {
                  print('✅ Email de remesa entregada en sucursal enviado exitosamente');
                }
              } catch (e) {
                print('❌ Error enviando email de remesa entregada en sucursal: $e');
              }
            }
          }
        } catch (e) {
          print('⚠️ Error obteniendo datos para email: $e');
        }
      } else {
        print('📴 Offline - Email y sincronización con GoodBarber se realizarán cuando haya conexión');
      }
      
      // Mostrar mensaje de éxito apropiado según el estado de conexión
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isOnline
                  ? '✅ Remesa marcada como entregada en $nombreSucursal. Puedes continuar con la entrega final.'
                  : '✅ Remesa marcada como entregada en $nombreSucursal (guardado localmente). Se sincronizará cuando haya conexión. Puedes continuar con la entrega final.',
            ),
            backgroundColor: const Color(0xFFFF9800),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      
      // Solo recargar órdenes si hay conexión (para obtener datos actualizados)
      // Si está offline, el estado local ya está actualizado
      if (isOnline) {
        // Invalidar caché de órdenes filtradas antes de recargar
        if (mounted) {
          setState(() {
            _ordenesFiltradasCache = null;
            _cacheKeyFiltradas = null;
          });
        }
        
        // Recargar órdenes
        // NOTA: Para MASTERS, las órdenes con estado "ENTREGADO EN SUCURSAL" seguirán visibles
        // en el filtro ACTIVAS para que puedan completar la entrega
        await _cargarOrdenes();
        
        // Asegurar que el caché se invalide después de recargar
        if (mounted) {
          setState(() {
            _ordenesFiltradasCache = null;
            _cacheKeyFiltradas = null;
          });
        }
      } else {
        print('📴 Offline - No se recargan órdenes, usando estado local actualizado');
      }
    } catch (e) {
      print('❌ Error marcando remesa como entregada en sucursal: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  // Método específico para marcar remesa como entregada (con validaciones de firma y foto)
  Future<void> _marcarRemesaComoEntregada(Orden orden) async {
    if (orden.estado == 'ENTREGADO') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta remesa ya está entregada'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
      return;
    }
    
    // 🔒 CRÍTICO: Cargar orden desde caché para obtener URLs locales actualizadas
    // Esto es importante para validar firmas y fotos que se guardaron localmente en modo offline
    Orden ordenActualizada = orden;
    try {
      final ordenDesdeCache = await OrdenCacheService.getCachedOrderById(orden.id);
      if (ordenDesdeCache != null) {
        ordenActualizada = ordenDesdeCache;
        print('✅ Orden actualizada desde caché para validación');
        print('   - Firma URL: ${ordenActualizada.firmaUrl}');
        print('   - Foto URL: ${ordenActualizada.fotoEntrega}');
      }
    } catch (e) {
      print('⚠️ Error cargando orden desde caché: $e');
      // Continuar con la orden original si falla
    }
    
    // 🔍 VALIDACIÓN: Verificar si requiere firma o foto
    List<String> errores = [];
    
    print('🔍 DEBUG - Remesa #${ordenActualizada.numeroRemesa ?? ordenActualizada.numeroOrden}');
    print('🔍 DEBUG - Requiere firma: ${ordenActualizada.requiereFirma}');
    print('🔍 DEBUG - Tiene firma: ${ordenActualizada.firmaUrl != null && ordenActualizada.firmaUrl!.isNotEmpty}');
    print('🔍 DEBUG - URL firma: ${ordenActualizada.firmaUrl}');
    print('🔍 DEBUG - Foto obligatoria configuración: $_fotoEntregaObligatoria');
    print('🔍 DEBUG - Tiene foto: ${ordenActualizada.fotoEntrega != null && ordenActualizada.fotoEntrega!.isNotEmpty}');
    print('🔍 DEBUG - URL foto: ${ordenActualizada.fotoEntrega}');
    
    // 1. Validar firma obligatoria (si requiere firma)
    // Aceptar firmas locales (local://) que están pendientes de sincronización
    final tieneFirma = ordenActualizada.firmaUrl != null && ordenActualizada.firmaUrl!.isNotEmpty;
    if (ordenActualizada.requiereFirma && !tieneFirma) {
      errores.add('✍️ Falta obtener la firma del destinatario (obligatorio)');
    }
    
    // 2. Validar foto obligatoria (si está activa) - Para remesas es opcional pero si está configurado debe pedirse
    // Si _fotoEntregaObligatoria está activo, pedir foto también para remesas
    // Aceptar fotos locales (local://) que están pendientes de sincronización
    final tieneFoto = ordenActualizada.fotoEntrega != null && ordenActualizada.fotoEntrega!.isNotEmpty;
    if (_fotoEntregaObligatoria && !tieneFoto) {
      errores.add('📷 Falta tomar la foto de entrega');
    }
    
    print('🔍 DEBUG - Errores encontrados: ${errores.length}');
    
    // Si hay errores, mostrar diálogo
    if (errores.isNotEmpty) {
      print('❌ Mostrando diálogo de errores: $errores');
      _mostrarDialogoErroresEntrega(orden, errores);
      return;
    }
    
    // Confirmación
    final confirmado = await _mostrarConfirmacion(
      'Confirmar Entrega de Remesa',
      '¿Estás seguro de que quieres marcar esta remesa como entregada?\n\nCantidad: \$${(orden.cantidadRemesa ?? 0.0).toStringAsFixed(2)}',
    );
    
    if (!confirmado) return;
    
    try {
      // Actualizar estado a ENTREGADO
      await supabase
          .from('ordenes')
          .update({
            'estado': 'ENTREGADO',
            'fecha_entrega': DateTime.now().toIso8601String(),
          })
          .eq('id', orden.id);
      
      // Sincronizar con GoodBarber si la orden está vinculada
      try {
        await GoodBarberSyncService.sincronizarEstadoAGoodBarber(
          supabase,
          orden.id,
          'ENTREGADO',
        );
      } catch (e) {
        print('⚠️ Error sincronizando estado con GoodBarber: $e');
      }
      
      // Obtener datos actualizados de la orden para enviar email
      try {
        final ordenData = await supabase
            .from('ordenes')
            .select('*')
            .eq('id', orden.id)
            .single();
        
        final ordenActualizada = Orden.fromJson(ordenData);
        final tenantId = ordenData['tenant_id']?.toString() ?? ordenActualizada.tenantId;
        
        // Obtener email del emisor y enviar email (mismo proceso que en _marcarComoEntregado)
        String? emailEmisor;
        final emisorNombre = ordenData['emisor']?.toString() ?? ordenActualizada.emisor;
        
        if (emisorNombre.isNotEmpty && emisorNombre != 'Sin emisor') {
          try {
            final emisorData = await supabase
                .from('emisores')
                .select('email')
                .eq('nombre', emisorNombre)
                .eq('tenant_id', tenantId ?? '')
                .maybeSingle();
            
            emailEmisor = emisorData?['email']?.toString();
          } catch (e) {
            print('⚠️ Error obteniendo email del emisor: $e');
          }
        }
        
        // Enviar email si está habilitado
        if (emailEmisor != null && emailEmisor.isNotEmpty) {
          final configService = ConfiguracionService();
          final notificacionesHabilitadas = await configService.notificacionesHabilitadas('emisores');
          
          if (notificacionesHabilitadas) {
            try {
              final enviado = await EmailService.enviarEmailOrdenEntregada(ordenActualizada, emailEmisor, tenantId: tenantId);
              if (enviado) {
                print('✅ Email de remesa entregada enviado exitosamente');
              }
            } catch (e) {
              print('❌ Error enviando email de remesa entregada: $e');
            }
          }
        }
      } catch (e) {
        print('⚠️ Error obteniendo datos para email: $e');
      }
      
      // Recargar órdenes
      await _cargarOrdenes();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Remesa marcada como entregada'),
            backgroundColor: Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      print('❌ Error marcando remesa como entregada: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  void _mostrarDetallesOrden(Orden orden, {bool abrirModalFirma = false}) async {
    // Marcar notificación como leída si existe una notificación no leída para esta orden
    try {
      if (_repartidorId != null && orden.numeroOrden != null) {
        // Buscar notificación no leída para esta orden
        final notificacion = await supabase
            .from('notificaciones_repartidores')
            .select('id')
            .eq('repartidor_id', _repartidorId!)
            .eq('numero_orden', orden.numeroOrden!)
            .inFilter('tipo', ['nueva_orden', 'ORDEN_NUEVA'])
            .eq('leida', false)
            .maybeSingle();
        
        if (notificacion != null) {
          // Marcar como leída
          await supabase
              .from('notificaciones_repartidores')
              .update({'leida': true})
              .eq('id', notificacion['id']);
          
          print('✅ Notificación de orden #${orden.numeroOrden} marcada como leída desde pantalla principal');
          
          // Actualizar contador de notificaciones
          await _cargarNotificacionesNoLeidas();
        }
      }
    } catch (e) {
      print('⚠️ Error marcando notificación como leída: $e');
    }
    
    final resultado = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DetalleOrdenScreen(
          orden: orden,
          abrirModalFirmaAutomatico: abrirModalFirma,
        ),
      ),
    );
    
    // Si se actualizó la orden, recargar la lista
    if (resultado == true) {
      _cargarOrdenes();
    }
  }

  Widget _buildBotonAccion(Orden orden) {
    // Botones específicos para recolectores
    if (_esRecolector) {
      switch (orden.estado) {
        case 'POR RECOGER':
          // El recolector puede cambiar de "POR RECOGER" a "EN CAMINO"
          return ElevatedButton.icon(
            onPressed: () => _marcarComoEnCamino(orden),
            icon: const Icon(Icons.directions_car, size: 18),
            label: const Text('En Camino'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9800),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        
        case 'EN CAMINO':
          // El recolector puede cambiar de "EN CAMINO" a "RECOGIDO"
          return ElevatedButton.icon(
            onPressed: () => _marcarComoRecogido(orden),
            icon: const Icon(Icons.check_circle, size: 18),
            label: const Text('Marcar Recogido'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        
        case 'RECOGIDO':
          // Ya recogido, no hay acción disponible
          return Container();
        
        default:
          return Container();
      }
    }
    
    // Botones para repartidores (estados normales de envío)
    switch (orden.estado) {
      case 'POR ENVIAR':
        // El repartidor NO puede cambiar órdenes de "POR ENVIAR" a "EN TRANSITO"
        // Solo el admin o el sistema pueden hacerlo
        // Esta orden está BLOQUEADA hasta que esté "EN TRANSITO"
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock, color: const Color(0xFF666666), size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _obtenerMensajeOrdenEsperandoRecoleccion(orden.repartidor),
                  style: const TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        );
      
      case 'EN TRANSITO':
        // El repartidor puede cambiar de "EN TRANSITO" a "EN REPARTO"
        return ElevatedButton.icon(
          onPressed: () => _marcarComoEnReparto(orden),
          icon: const Icon(Icons.local_shipping, size: 18),
          label: const Text('Iniciar Reparto'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF9800),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      
      case 'EN REPARTO':
        // Si es recogida en sucursal, mostrar "Listo para recoger" en lugar de "Marcar Entregado"
        if (orden.recogerEnSucursal) {
          return ElevatedButton.icon(
            onPressed: () => _marcarComoListoParaRecoger(orden),
            icon: const Icon(Icons.store, size: 18),
            label: const Text('Listo para recoger'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9800), // Naranja para "Listo para recoger"
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }
        // El repartidor puede cambiar de "EN REPARTO" a "ENTREGADO" (orden normal)
        return ElevatedButton.icon(
          onPressed: () => _marcarComoEntregado(orden),
          icon: const Icon(Icons.check_circle, size: 18),
          label: const Text('Marcar Entregado'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4CAF50),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      
      case 'LISTO PARA RECOGER':
        // Después de "LISTO PARA RECOGER", se puede marcar como "ENTREGADO"
        return ElevatedButton.icon(
          onPressed: () => _marcarComoEntregado(orden),
          icon: const Icon(Icons.check_circle, size: 18),
          label: const Text('Marcar Entregado'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4CAF50),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      
      case 'ATRASADO':
        // Si está atrasado pero está en "EN TRANSITO", puede iniciar reparto
        return ElevatedButton.icon(
          onPressed: () => _marcarComoEnReparto(orden),
          icon: const Icon(Icons.local_shipping, size: 18),
          label: const Text('Iniciar Reparto'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF9800),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );
      
      default:
        return Container();
    }
  }

  Future<void> _marcarComoEntregado(Orden orden) async {
    // 🔍 VALIDACIÓN COMPLETA ANTES DE ENTREGAR
    List<String> errores = [];
    
    // DEBUG: Ver cantidad de bultos
    print('🔍 DEBUG - Orden #${orden.numeroOrden}');
    print('🔍 DEBUG - Cantidad de bultos: ${orden.cantidadBultos}');
    print('🔍 DEBUG - Foto obligatoria: $_fotoEntregaObligatoria');
    print('🔍 DEBUG - Tiene foto: ${orden.fotoEntrega != null && orden.fotoEntrega!.isNotEmpty}');
    print('🔍 DEBUG - Requiere pago: ${orden.requierePago}');
    print('🔍 DEBUG - Pagado: ${orden.pagado}');
    print('🔍 DEBUG - Requiere firma: ${orden.requiereFirma}');
    print('🔍 DEBUG - Tiene firma: ${orden.firmaUrl != null && orden.firmaUrl!.isNotEmpty}');
    print('🔍 DEBUG - Tiene remesa: ${orden.tieneRemesa}');
    
    // 1. Validar remesa (si tiene remesa, debe entregarse)
    if (orden.tieneRemesa) {
      final cantidadRemesa = orden.cantidadRemesa ?? 0.0;
      errores.add('📦 Debes entregar remesa de \$${cantidadRemesa.toStringAsFixed(2)}');
    }

    // 2. Validar pago pendiente (si requiere pago)
    if (orden.requierePago && !orden.pagado) {
      final simbolo = orden.moneda == 'USD' ? '\$' : '\$';
      errores.add('💰 Falta cobrar ${simbolo}${orden.montoCobrar.toStringAsFixed(2)} ${orden.moneda}');
    }

    // 3. Validar firma obligatoria (si requiere firma)
    if (orden.requiereFirma && (orden.firmaUrl == null || orden.firmaUrl!.isEmpty)) {
      errores.add('✍️ Falta obtener la firma del cliente (obligatorio)');
    }

    // 4. Validar foto obligatoria (si está activa) - EXCLUIR remesas puras
    // Para remesas, la foto es opcional (no bloqueante)
    if (!_esRemesaPura(orden) && _fotoEntregaObligatoria && (orden.fotoEntrega == null || orden.fotoEntrega!.isEmpty)) {
      errores.add('📷 Falta tomar la foto de entrega');
    }

    print('🔍 DEBUG - Errores encontrados: ${errores.length}');
    print('🔍 DEBUG - ¿Debe preguntar por bultos? ${orden.cantidadBultos > 1}');

    // 3. Mostrar diálogo de confirmación de bultos (solo si hay más de 1)
    if (errores.isEmpty) {
      // Solo preguntar por bultos si hay 2 o más
      if (orden.cantidadBultos > 1) {
        print('✅ Mostrando diálogo de confirmación de bultos');
        final confirmado = await _mostrarDialogoConfirmacionBultos(orden);
        if (!confirmado) {
          return; // Usuario canceló
        }
      }
    } else {
      // Hay errores - mostrar diálogo de errores
      print('❌ Mostrando diálogo de errores: $errores');
      _mostrarDialogoErroresEntrega(orden, errores);
      return;
    }

    // Todo validado - proceder con la entrega
    final confirmadoFinal = await _mostrarConfirmacion(
      'Confirmar Entrega',
      '¿Estás seguro de que quieres marcar esta orden como entregada?',
    );
    
    if (confirmadoFinal) {
      print('✅ Usuario confirmó la entrega de la orden #${orden.numeroOrden}');
      try {
        print('📡 Actualizando estado de orden en BD a ENTREGADO...');
        await supabase
            .from('ordenes')
            .update({
              'estado': 'ENTREGADO',
              'fecha_entrega': DateTime.now().toIso8601String(),
            })
            .eq('id', orden.id);
        
        print('✅ Estado actualizado en BD: ENTREGADO');
        
        // Sincronizar con GoodBarber si la orden está vinculada
        try {
          await GoodBarberSyncService.sincronizarEstadoAGoodBarber(
            supabase,
            orden.id,
            'ENTREGADO',
          );
        } catch (e) {
          print('⚠️ Error sincronizando estado con GoodBarber: $e');
        }

        // Obtener email del EMISOR y enviar email
        print('📧 ===== INICIANDO PROCESO DE EMAIL ENTREGADO =====');
        print('📧 Orden ID: ${orden.id}');
        print('📧 Orden número: ${orden.numeroOrden}');
        
        try {
          print('📧 Paso 1: Obteniendo datos de la orden...');
        final ordenData = await supabase
            .from('ordenes')
              .select('*')
            .eq('id', orden.id)
            .single();
          
          print('📧 Paso 2: Datos obtenidos exitosamente');
          print('   - tenant_id: ${ordenData['tenant_id']}');
          print('   - emisor: ${ordenData['emisor']}');
          
          final ordenActualizada = Orden.fromJson(ordenData);
          final tenantId = ordenData['tenant_id']?.toString() ?? ordenActualizada.tenantId;
          
          // Actualizar la orden en la lista local inmediatamente para que el botón cambie
          if (mounted) {
            setState(() {
              final index = _ordenes.indexWhere((o) => o.id == orden.id);
              if (index != -1) {
                _ordenes[index] = ordenActualizada;
                print('✅ Orden actualizada en lista local: estado = ${_ordenes[index].estado}');
              }
            });
          }
          
          // Obtener email del emisor por nombre (como lo hace la web app)
          String? emailEmisor;
          final emisorNombre = ordenData['emisor']?.toString() ?? ordenActualizada.emisor;
          
          if (emisorNombre.isNotEmpty && emisorNombre != 'Sin emisor') {
            print('📧 Paso 3: Buscando email del emisor por nombre: $emisorNombre');
            try {
              final emisorData = await supabase
                  .from('emisores')
                  .select('email')
                  .eq('nombre', emisorNombre)
                  .eq('tenant_id', tenantId ?? '')
                  .maybeSingle();
              
              emailEmisor = emisorData?['email']?.toString();
              print('   - Email encontrado: ${emailEmisor ?? "NO ENCONTRADO"}');
            } catch (e) {
              print('⚠️ Error obteniendo email del emisor por nombre: $e');
              print('❌ Stack trace: ${StackTrace.current}');
            }
          } else {
            print('⚠️ El emisor está vacío o es "Sin emisor"');
          }
          
          print('📧 Paso 4: Email final del emisor: ${emailEmisor ?? "NO ENCONTRADO"}');
          
          if (emailEmisor != null && emailEmisor.isNotEmpty) {
            print('📧 Paso 5: Verificando configuración de notificaciones...');
            final configService = ConfiguracionService();
            final notificacionesHabilitadas = await configService.notificacionesHabilitadas('emisores');
            print('   - Notificaciones habilitadas: $notificacionesHabilitadas');
            
            if (notificacionesHabilitadas) {
              print('📧 Paso 6: ENVIANDO EMAIL ENTREGADO...');
              print('   - Email: $emailEmisor');
              print('   - Tenant ID: $tenantId');
              print('   - Foto entrega: ${ordenActualizada.fotoEntrega ?? "NO DISPONIBLE"}');
              print('   - Firma URL: ${ordenActualizada.firmaUrl ?? "NO DISPONIBLE"}');
              
              try {
                final enviado = await EmailService.enviarEmailOrdenEntregada(ordenActualizada, emailEmisor, tenantId: tenantId);
                if (enviado) {
                  print('✅ ✅ ✅ Email de orden entregada ENVIADO EXITOSAMENTE al emisor: $emailEmisor ✅ ✅ ✅');
                } else {
                  print('⚠️ ⚠️ ⚠️ No se pudo enviar el email al emisor ⚠️ ⚠️ ⚠️');
                }
              } catch (emailError) {
                print('❌ ❌ ❌ ERROR ENVIANDO EMAIL: $emailError ❌ ❌ ❌');
                print('❌ Stack trace: ${StackTrace.current}');
              }
            } else {
              print('⚠️ ⚠️ ⚠️ Notificaciones para emisores están DESHABILITADAS ⚠️ ⚠️ ⚠️');
            }
          } else {
            print('⚠️ ⚠️ ⚠️ NO se encontró email del emisor ⚠️ ⚠️ ⚠️');
          }
        } catch (e) {
          print('❌ ❌ ❌ ERROR CRÍTICO al obtener datos para email: $e ❌ ❌ ❌');
          print('❌ Stack trace: ${StackTrace.current}');
        }
        
        print('📧 ===== FIN PROCESO EMAIL ENTREGADO =====');

        _mostrarMensaje('✅ Orden entregada exitosamente');
        
        // Recargar órdenes desde la BD pero preservando el estado de esta orden
        // Usar un pequeño delay para asegurar que la BD tenga el estado actualizado
        await Future.delayed(const Duration(milliseconds: 1000));
        await _cargarOrdenes(preservarOrdenId: orden.id, preservarEstado: 'ENTREGADO');
        
        // Detener rastreo GPS si no hay más órdenes en "EN REPARTO"
        _verificarYActivarRastreo();
      } catch (e) {
        _mostrarMensaje('Error al marcar como entregada: $e');
      }
    }
  }

  Future<void> _marcarComoEnCamino(Orden orden) async {
    // Verificar que la orden esté en "POR RECOGER"
    if (orden.estado != 'POR RECOGER') {
      _mostrarMensaje('Solo puedes marcar "En Camino" desde órdenes en "POR RECOGER"');
      return;
    }
    
    final confirmado = await _mostrarConfirmacion(
      'Marcar En Camino',
      '¿Estás seguro de que quieres marcar esta orden como "En Camino"?',
    );
    
    if (confirmado) {
      try {
        await supabase
            .from('ordenes')
            .update({
              'estado': 'EN CAMINO',
            })
            .eq('id', orden.id);
        
        _mostrarMensaje('✅ Orden marcada como "En Camino"');
        await _cargarOrdenes(preservarOrdenId: orden.id, preservarEstado: 'EN CAMINO');
      } catch (e) {
        _mostrarMensaje('Error al marcar como "En Camino": $e');
      }
    }
  }

  Future<void> _marcarComoRecogido(Orden orden) async {
    // Verificar que la orden esté en "EN CAMINO"
    if (orden.estado != 'EN CAMINO') {
      _mostrarMensaje('Solo puedes marcar como "Recogido" desde órdenes en "EN CAMINO"');
      return;
    }
    
    final confirmado = await _mostrarConfirmacion(
      'Marcar Recogido',
      '¿Estás seguro de que quieres marcar esta orden como "Recogido"?',
    );
    
    if (confirmado) {
      try {
        await supabase
            .from('ordenes')
            .update({
              'estado': 'RECOGIDO',
              'fecha_entrega': DateTime.now().toIso8601String(), // Usar fecha_entrega para consistencia
            })
            .eq('id', orden.id);
        
        _mostrarMensaje('✅ Orden marcada como "Recogido"');
        await _cargarOrdenes(preservarOrdenId: orden.id, preservarEstado: 'RECOGIDO');
      } catch (e) {
        _mostrarMensaje('Error al marcar como "Recogido": $e');
      }
    }
  }

  Future<void> _marcarComoListoParaRecoger(Orden orden) async {
    // Verificar que la orden esté en "EN REPARTO" y que sea recogida en sucursal
    if (orden.estado != 'EN REPARTO') {
      _mostrarMensaje('Solo puedes marcar como "Listo para recoger" desde órdenes en "EN REPARTO"');
      return;
    }
    
    if (!orden.recogerEnSucursal) {
      _mostrarMensaje('Esta orden no es para recogida en sucursal');
      return;
    }
    
    // Mostrar diálogo personalizado con el nombre del destinatario
    if (!mounted) return;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: Row(
          children: [
            Icon(
              Icons.store,
              color: const Color(0xFFFF9800),
              size: 24,
            ),
            const SizedBox(width: 8),
            const Text(
              'Listo para recoger',
              style: TextStyle(
                color: Color(0xFF2C2C2C),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'La orden está lista para que el destinatario ${orden.receptor} pase a recogerla en la sucursal. ¿Seguro?',
          style: const TextStyle(
            color: Color(0xFF2C2C2C),
            fontSize: 15,
          ),
        ),
        actions: [
          // Botón Denegar
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF666666),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text(
              'Denegar',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Botón Aceptar
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9800),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Aceptar',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    
    if (confirmado == true) {
      final syncService = SyncService();
      final updateData = <String, dynamic>{'estado': 'LISTO PARA RECOGER'};

      bool actualizadoExitosamente = false;

      // ✅ OFFLINE-FIRST: actualizar local inmediato (cache + lista)
      try {
        orden.estado = 'LISTO PARA RECOGER';
        await OrdenCacheService.updateCachedOrder(orden);
        if (mounted) {
          setState(() {
            final index = _ordenes.indexWhere((o) => o.id == orden.id);
            if (index != -1) _ordenes[index] = orden;
          });
        }
      } catch (e) {
        print('⚠️ Error actualizando caché/lista local a LISTO PARA RECOGER: $e');
      }

      // Intentar BD solo si hay conectividad (si falla DNS, se encola)
      Orden? ordenActualizadaParaEmail;
      if (syncService.isOnline) {
        try {
          print('📡 Actualizando estado de orden en BD a LISTO PARA RECOGER...');
          await supabase.from('ordenes').update(updateData).eq('id', orden.id);
          actualizadoExitosamente = true;
          print('✅ Estado actualizado en BD: LISTO PARA RECOGER');

          // Intentar leer la orden ya actualizada (no bloquear si falla)
          try {
            final ordenData = await supabase.from('ordenes').select('*').eq('id', orden.id).single();
            final o = Orden.fromJson(ordenData);
            o.estado = 'LISTO PARA RECOGER';
            ordenActualizadaParaEmail = o;
            await OrdenCacheService.updateCachedOrder(o);
          } catch (e) {
            print('⚠️ No se pudo recargar orden para email/UI: $e');
          }
        } catch (e) {
          final errorString = e.toString();
          if (errorString.contains('Failed host lookup') ||
              errorString.contains('SocketException') ||
              errorString.contains('ClientException')) {
            print('📴 Error de conexión real a Supabase - Encolando LISTO PARA RECOGER');
            actualizadoExitosamente = false;
          } else {
            print('❌ Error NO de red marcando LISTO PARA RECOGER: $e');
            _mostrarMensaje('Error al marcar como "Listo para recoger": $e');
            return;
          }
        }
      }

      if (!actualizadoExitosamente) {
        try {
          await syncService.addOperation(
            type: 'update_orden_estado',
            ordenId: orden.id,
            data: updateData,
          );
        } catch (e) {
          print('⚠️ Error encolando LISTO PARA RECOGER: $e');
        }
      }

      // Email solo si BD se actualizó de verdad
      if (actualizadoExitosamente) {
        print('📧 ===== INICIANDO PROCESO DE EMAIL LISTO PARA RECOGER =====');
        try {
          final ordenParaEmail = ordenActualizadaParaEmail ?? orden;
          final tenantId = ordenParaEmail.tenantId ?? _tenantId;

          String? emailEmisor;
          try {
            final emisorData = await supabase
                .from('emisores')
                .select('email')
                .eq('nombre', ordenParaEmail.emisor)
                .eq('tenant_id', tenantId ?? '')
                .maybeSingle();
            if (emisorData != null && emisorData['email'] != null) {
              emailEmisor = emisorData['email'] as String;
            }
          } catch (e) {
            print('⚠️ Error obteniendo email del emisor: $e');
          }

          if (emailEmisor != null && emailEmisor.isNotEmpty && tenantId != null) {
            EmailService.enviarEmailOrdenListaParaRecoger(ordenParaEmail, emailEmisor, tenantId: tenantId);
          }
        } catch (e) {
          print('❌ Error en proceso de email LISTO PARA RECOGER: $e');
        }
      }

      _mostrarMensaje(
        actualizadoExitosamente
            ? '✅ Orden marcada como "Listo para recoger"'
            : '✅ Orden marcada como "Listo para recoger" (se sincronizará cuando haya conexión)',
      );
      await _cargarOrdenes(preservarOrdenId: orden.id, preservarEstado: 'LISTO PARA RECOGER');
    }
  }

  Future<void> _marcarComoEnReparto(Orden orden) async {
    // Verificar que la orden esté en "EN TRANSITO" o "ATRASADO"
    if (orden.estado != 'EN TRANSITO' && orden.estado != 'ATRASADO') {
      _mostrarMensaje('Solo puedes iniciar reparto desde órdenes en "EN TRANSITO"');
      return;
    }
    
    try {
      // Actualizar estado localmente primero
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
        estado: 'EN REPARTO', // Nuevo estado
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
      );
      await OrdenCacheService.updateCachedOrder(ordenActualizada);
      
      final syncService = SyncService();
      final updateData = {
        'estado': 'EN REPARTO',
      };
      
      // Intentar actualizar en BD si hay conexión
      bool actualizadoExitosamente = false;
      
      print('📡 Actualizando estado de orden en BD...');
      
        try {
          await supabase
              .from('ordenes')
              .update(updateData)
              .eq('id', orden.id);
          
        print('✅ Estado actualizado en BD: EN REPARTO');
          actualizadoExitosamente = true;
          
          // Sincronizar con GoodBarber si la orden está vinculada
          try {
            await GoodBarberSyncService.sincronizarEstadoAGoodBarber(
              supabase,
              orden.id,
              'EN REPARTO',
            );
          } catch (e) {
            print('⚠️ Error sincronizando estado con GoodBarber: $e');
          }
        
        // Actualizar la orden en la lista local inmediatamente para que el botón cambie
        if (mounted) {
          setState(() {
            final index = _ordenes.indexWhere((o) => o.id == orden.id);
            if (index != -1) {
              _ordenes[index] = ordenActualizada;
              print('✅ Orden actualizada en lista local: estado = ${_ordenes[index].estado}');
            }
          });
        }
          
          // Iniciar rastreo GPS cuando se marca como "EN REPARTO"
          _iniciarRastreoUbicacion();
          
        // Obtener email del EMISOR y enviar email (SIEMPRE intentar, no depender de syncService.isOnline)
        print('📧 ===== INICIANDO PROCESO DE EMAIL EN REPARTO =====');
        print('📧 Orden ID: ${orden.id}');
        print('📧 Orden número: ${orden.numeroOrden}');
        print('📧 Emisor nombre: ${orden.emisor}');
        
          try {
          // Obtener tenant_id de la orden
          print('📧 Paso 1: Obteniendo tenant_id de la orden...');
            final ordenData = await supabase
                .from('ordenes')
              .select('tenant_id')
                .eq('id', orden.id)
                .single();
            
            final tenantId = ordenData['tenant_id']?.toString() ?? orden.tenantId;
          print('📧 Paso 2: Tenant ID obtenido: $tenantId');
            
            String? emailEmisor;
            
          // Buscar el email del emisor por nombre (como lo hace la web app)
          if (orden.emisor.isNotEmpty && orden.emisor != 'Sin emisor') {
            print('📧 Paso 3: Buscando email del emisor por nombre: ${orden.emisor}');
              try {
                final emisorData = await supabase
                    .from('emisores')
                    .select('email')
                    .eq('nombre', orden.emisor)
                  .eq('tenant_id', tenantId ?? '')
                    .maybeSingle();
                
                emailEmisor = emisorData?['email']?.toString();
              print('📧 Email obtenido: ${emailEmisor ?? "NO ENCONTRADO"}');
              } catch (e) {
                print('⚠️ Error obteniendo email del emisor por nombre: $e');
              print('❌ Stack trace: ${StackTrace.current}');
              }
          } else {
            print('⚠️ El emisor está vacío o es "Sin emisor"');
            }
          
          print('📧 Paso 4: Email final del emisor: ${emailEmisor ?? "NO ENCONTRADO"}');
            
            if (emailEmisor != null && emailEmisor.isNotEmpty) {
            print('📧 Paso 5: Verificando configuración de notificaciones...');
              final configService = ConfiguracionService();
              final notificacionesHabilitadas = await configService.notificacionesHabilitadas('emisores');
            print('   - Notificaciones habilitadas: $notificacionesHabilitadas');
              
              if (notificacionesHabilitadas) {
              print('📧 Paso 6: ENVIANDO EMAIL EN REPARTO...');
              print('   - Email: $emailEmisor');
              print('   - Tenant ID: $tenantId');
              print('   - Estado de ordenActualizada: ${ordenActualizada.estado}');
              
                try {
                  final enviado = await EmailService.enviarEmailOrdenEnReparto(ordenActualizada, emailEmisor, tenantId: tenantId);
                  if (enviado) {
                  print('✅ ✅ ✅ Email de orden en reparto ENVIADO EXITOSAMENTE al emisor: $emailEmisor ✅ ✅ ✅');
                  _mostrarMensaje('✅ Email de notificación enviado');
                  } else {
                  print('⚠️ ⚠️ ⚠️ No se pudo enviar el email al emisor ⚠️ ⚠️ ⚠️');
                  }
                } catch (e) {
                print('❌ ❌ ❌ ERROR ENVIANDO EMAIL: $e ❌ ❌ ❌');
                print('❌ Stack trace: ${StackTrace.current}');
                }
              } else {
              print('⚠️ ⚠️ ⚠️ Notificaciones para emisores están DESHABILITADAS ⚠️ ⚠️ ⚠️');
              }
            } else {
            print('⚠️ ⚠️ ⚠️ NO se encontró email del emisor para la orden ${orden.numeroOrden} ⚠️ ⚠️ ⚠️');
            }
          } catch (e) {
          print('❌ ❌ ❌ ERROR CRÍTICO al obtener datos para email: $e ❌ ❌ ❌');
          print('❌ Stack trace: ${StackTrace.current}');
          }
        
        print('📧 ===== FIN PROCESO EMAIL EN REPARTO =====');
        } catch (e) {
          print('⚠️ Error actualizando en BD: $e');
          actualizadoExitosamente = false;
      }
      
      // Si no se actualizó exitosamente, agregar a cola de sincronización
      if (!actualizadoExitosamente) {
        try {
          await syncService.addOperation(
            type: 'update_orden_estado',
            ordenId: orden.id,
            data: updateData,
          );
          print('📴 Operación agregada a cola de sincronización');
        } catch (e) {
          print('❌ Error agregando a cola: $e');
        }
      }

      _mostrarMensaje('✅ Reparto iniciado - Rastreo GPS activado');
      
      // Recargar órdenes desde la BD pero preservando el estado de esta orden
      // Usar un pequeño delay para asegurar que la BD tenga el estado actualizado
      await Future.delayed(const Duration(milliseconds: 1000));
      await _cargarOrdenes(preservarOrdenId: orden.id, preservarEstado: 'EN REPARTO');
      
      // Verificar y activar rastreo después de actualizar
      _verificarYActivarRastreo();
    } catch (e) {
      _mostrarMensaje('Error al iniciar reparto: $e');
    }
  }

  void _mostrarDialogoPermisoSegundoPlano() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            'Permiso de Ubicación en Segundo Plano',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C2C2C),
            ),
          ),
          content: const Text(
            'Para rastrear tu ubicación mientras manejas (con el teléfono en el bolsillo), necesitas cambiar el permiso de ubicación a "Permitir todo el tiempo".\n\n'
            '¿Quieres ir a Configuración ahora para cambiar este permiso?',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF666666),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Cancelar',
                style: TextStyle(color: Color(0xFF666666)),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                // Abrir configuración de la app
                await openAppSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                foregroundColor: Colors.white,
              ),
              child: const Text('Ir a Configuración'),
            ),
          ],
        );
      },
    );
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: const Color(0xFF1976D2),
        duration: const Duration(seconds: 2),
      ),
    );
  }


  Future<bool> _mostrarConfirmacion(String titulo, String mensaje) async {
    if (!mounted) return false;
    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        title: Text(
          titulo,
          style: const TextStyle(
            color: Color(0xFF2C2C2C),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          mensaje,
          style: const TextStyle(
            color: Color(0xFF666666),
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Color(0xFF666666)),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
            ),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return resultado ?? false;
  }

  void _mostrarErrorFotoObligatoria(Orden orden) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(Icons.camera_alt, color: Color(0xFFDC2626), size: 24),
            SizedBox(width: 12),
            Text(
              'Foto Obligatoria',
              style: TextStyle(
                color: Color(0xFF2C2C2C),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: const Text(
          '❌ Error: Debes tomar una foto de la entrega primero para poder realizar la entrega exitosamente.',
          style: TextStyle(
            color: Color(0xFF666666),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF666666),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text(
              'Cancelar',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _mostrarDetallesOrden(orden);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1976D2),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 2,
            ),
            child: const Text(
              'Tomar Foto',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarDialogoCobroObligatorio(Orden orden) {
    final monto = orden.montoCobrar;
    final moneda = orden.moneda;
    final simbolo = moneda == 'USD' ? '\$' : '\$';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(Icons.attach_money, color: Color(0xFF4CAF50), size: 24),
            SizedBox(width: 12),
            Text(
              'Cobro Obligatorio',
              style: TextStyle(
                color: Color(0xFF2C2C2C),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '💰 El cliente debe pagar:',
              style: const TextStyle(
                color: Color(0xFF2C2C2C),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF4CAF50)),
              ),
              child: Text(
                '$simbolo ${monto.toStringAsFixed(2)} $moneda',
                style: const TextStyle(
                  color: Color(0xFF4CAF50),
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '❌ Error: Debes cobrar al cliente antes de entregar la orden.',
              style: TextStyle(
                color: Color(0xFF666666),
                fontSize: 14,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF666666),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text(
              'Cancelar',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _marcarDineroCobrado(orden);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 2,
            ),
            child: const Text(
              'Dinero Cobrado',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _marcarDineroCobrado(Orden orden) async {
    final confirmado = await _mostrarConfirmacion(
      'Confirmar Cobro',
      '¿Confirmas que el cliente ya pagó ${orden.moneda == 'USD' ? '\$' : '\$'} ${orden.montoCobrar.toStringAsFixed(2)} ${orden.moneda}?',
    );
    
    if (confirmado) {
      try {
        await supabase
            .from('ordenes')
            .update({
              'pagado': true,
              'fecha_pago': DateTime.now().toIso8601String(),
            })
            .eq('id', orden.id);
        
        _mostrarMensaje('✅ Dinero cobrado registrado. Ahora puedes entregar la orden.');
        _cargarOrdenes();
        
      } catch (e) {
        _mostrarMensaje('Error al registrar el cobro: $e');
      }
    }
  }

  // 🔍 NUEVO: Diálogo de confirmación de bultos
  Future<bool> _mostrarDialogoConfirmacionBultos(Orden orden) async {
    if (!mounted) return false;
    final resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // No se puede cerrar tocando afuera
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(Icons.inventory_2, color: Color(0xFF1976D2), size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Text(
              'Verificar Bultos',
              style: TextStyle(
                color: Color(0xFF2C2C2C),
                fontSize: 18,
                fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📦 Antes de marcar como entregada, verifica:',
              style: TextStyle(
                color: Color(0xFF2C2C2C),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1976D2).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF1976D2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Cantidad de Bultos:',
                    style: TextStyle(
                      color: Color(0xFF666666),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${orden.cantidadBultos} ${orden.cantidadBultos == 1 ? 'bulto' : 'bultos'}',
                    style: const TextStyle(
                      color: Color(0xFF1976D2),
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '¿Entregaste todos los bultos correctamente?',
                      style: TextStyle(
                        color: Color(0xFF2C2C2C),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF666666),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text(
              'Cancelar',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 2,
            ),
            child: const Text(
              'Sí, Todos Entregados',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    return resultado ?? false;
  }

  // 🚨 NUEVO: Diálogo de errores antes de entregar
  void _mostrarDialogoErroresEntrega(Orden orden, List<String> errores) {
    if (!mounted) return;
    
    // Determinar el título según los errores
    String titulo = 'Completar entrega';
    IconData iconoTitulo = Icons.check_circle_outline;
    Color colorTitulo = const Color(0xFF1976D2);
    String textoBoton = 'Completar';
    IconData iconoBoton = Icons.check_circle;
    
    // Si requiere foto, priorizar foto
    if (errores.any((e) => e.contains('foto') || e.contains('Foto') || e.contains('📷'))) {
      titulo = 'Tomar foto de entrega';
      iconoTitulo = Icons.camera_alt;
      colorTitulo = const Color(0xFF1976D2);
      textoBoton = 'Tomar foto';
      iconoBoton = Icons.camera_alt;
    } 
    // Si requiere firma, priorizar firma
    else if (errores.any((e) => e.contains('firma') || e.contains('Firma') || e.contains('✍️'))) {
      titulo = 'Capturar firma';
      iconoTitulo = Icons.edit;
      colorTitulo = const Color(0xFF9C27B0);
      textoBoton = 'Capturar firma';
      iconoBoton = Icons.edit;
    }
    // Si requiere cobro
    else if (errores.any((e) => e.contains('cobrar') || e.contains('Cobrar') || e.contains('💰'))) {
      titulo = 'Registrar cobro';
      iconoTitulo = Icons.payment;
      colorTitulo = const Color(0xFFFF9800);
      textoBoton = 'Registrar cobro';
      iconoBoton = Icons.payment;
    }
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Icon(iconoTitulo, color: colorTitulo, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                titulo,
                style: TextStyle(
                  color: colorTitulo,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '⚠️ Debes completar lo siguiente:',
              style: TextStyle(
                color: Color(0xFF2C2C2C),
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            ...errores.map((error) {
              // Determinar icono y color según el tipo de error
              IconData icono;
              Color colorIcono;
              
              if (error.contains('remesa') || error.contains('Remesa')) {
                icono = Icons.attach_money;
                colorIcono = const Color(0xFF2196F3);
              } else if (error.contains('cobrar') || error.contains('Cobrar') || error.contains('💰')) {
                icono = Icons.payment;
                colorIcono = const Color(0xFFFF9800);
              } else if (error.contains('firma') || error.contains('Firma') || error.contains('✍️')) {
                icono = Icons.edit;
                colorIcono = const Color(0xFF9C27B0);
              } else if (error.contains('foto') || error.contains('Foto') || error.contains('📷')) {
                icono = Icons.camera_alt;
                colorIcono = const Color(0xFF1976D2);
              } else {
                icono = Icons.warning;
                colorIcono = const Color(0xFFDC2626);
              }
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorIcono.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colorIcono.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(icono, color: colorIcono, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          error.replaceAll(RegExp(r'[📦💰✍️📷]'), '').trim(),
                          style: TextStyle(
                            color: const Color(0xFF2C2C2C),
                            fontSize: 13,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1976D2).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF1976D2), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Completa los pendientes antes de marcar como entregada',
                      style: TextStyle(
                        color: Color(0xFF1976D2),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          ),
        ),
        actions: [
          // Botón para cerrar
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF666666),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: const Text(
              'Cerrar',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // Botón principal para completar entrega (ir directamente a foto/firma/cobro)
          ElevatedButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              // Si el error es de foto, abrir selector de cámara/galería directamente
              if (errores.any((e) => e.contains('foto') || e.contains('Foto') || e.contains('📷'))) {
                await _tomarFotoDesdeModal(orden);
              } 
              // Si el error es de firma, abrir detalles con modal de firma automático
              else if (errores.any((e) => e.contains('firma') || e.contains('Firma') || e.contains('✍️'))) {
                // Abrir pantalla de detalle con modal de firma automático
                _mostrarDetallesOrden(orden, abrirModalFirma: true);
              }
              else {
                // Para otros casos (cobro), abrir detalles
                _mostrarDetallesOrden(orden);
              }
            },
            icon: Icon(iconoBoton, size: 18),
            label: Text(textoBoton),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorTitulo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========== MÉTODOS DE FOTO DE ENTREGA ==========
  
  // Tomar/seleccionar foto desde el modal de errores
  Future<void> _tomarFotoDesdeModal(Orden orden) async {
    if (!mounted) return;
    
    try {
      // Mostrar opciones: Cámara o Galería
      final opcion = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Seleccionar foto de entrega',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C2C2C),
                      ),
                    ),
                    const SizedBox(height: 20),
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1976D2).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.camera_alt, color: Color(0xFF1976D2), size: 24),
                      ),
                      title: const Text(
                        'Tomar foto',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2C2C2C),
                        ),
                      ),
                      subtitle: const Text(
                        'Usar la cámara para tomar una nueva foto',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF666666),
                        ),
                      ),
                      onTap: () => Navigator.pop(context, 'camara'),
                    ),
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.photo_library, color: Color(0xFF4CAF50), size: 24),
                      ),
                      title: const Text(
                        'Elegir de galería',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2C2C2C),
                        ),
                      ),
                      subtitle: const Text(
                        'Seleccionar una foto de tu galería',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF666666),
                        ),
                      ),
                      onTap: () => Navigator.pop(context, 'galeria'),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

      if (opcion == null) return;

      final ImagePicker picker = ImagePicker();
      final ImageSource source = opcion == 'camara' 
          ? ImageSource.camera 
          : ImageSource.gallery;

      final XFile? image = await picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (image != null && mounted) {
        // Mostrar indicador de carga
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );

        try {
          final fileBytes = await image.readAsBytes();
          final photoBase64 = base64Encode(fileBytes);
          
          // Guardar foto localmente
          await OfflineStorageService().savePendingPhoto(
            ordenId: orden.id,
            filePath: image.path,
          );
          
          final syncService = SyncService();
          
          // Intentar subir si hay conexión
          if (syncService.isOnline) {
            try {
              final fileName = 'entrega_${orden.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
              const String bucketName = 'fotos-perfil';
              
              await supabase.storage
                  .from(bucketName)
                  .uploadBinary(fileName, fileBytes);

              final imageUrl = supabase.storage
                  .from(bucketName)
                  .getPublicUrl(fileName);

              await supabase
                  .from('ordenes')
                  .update({
                    'foto_entrega': imageUrl,
                  })
                  .eq('id', orden.id);

              print('✅ Foto subida exitosamente desde modal (online)');
              
              if (mounted) {
                Navigator.of(context).pop(); // Cerrar diálogo de carga
                _cargarOrdenes(); // Recargar órdenes para actualizar la lista
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Foto subida exitosamente'),
                    backgroundColor: Color(0xFF4CAF50),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            } catch (uploadError) {
              print('⚠️ Error subiendo foto, agregando a cola: $uploadError');
              // Si falla, agregar a cola de sincronización
              await syncService.addOperation(
                type: 'upload_photo',
                ordenId: orden.id,
                data: {
                  'photo_base64': photoBase64,
                  'file_path': image.path, // 🔒 CRÍTICO: Incluir ruta del archivo para sincronización
                },
              );
              
              // 🔒 CRÍTICO: Actualizar caché local de la orden con la foto local
              try {
                final ordenCached = await OrdenCacheService.getCachedOrderById(orden.id);
                if (ordenCached != null) {
                  final ordenJson = ordenCached.toJson();
                  ordenJson['foto_entrega'] = 'local://${image.path}';
                  final ordenActualizada = Orden.fromJson(ordenJson);
                  await OrdenCacheService.updateCachedOrder(ordenActualizada);
                  print('💾 Orden actualizada en caché local con foto: ${image.path}');
                }
              } catch (e) {
                print('⚠️ Error actualizando caché local con foto: $e');
              }
              
              if (mounted) {
                Navigator.of(context).pop(); // Cerrar diálogo de carga
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('✅ Foto guardada - Puedes continuar con la entrega (se sincronizará cuando haya conexión)'),
                    backgroundColor: Color(0xFF2196F3),
                    duration: Duration(seconds: 3),
                  ),
                );
              }
            }
          } else {
            // Sin conexión, agregar a cola directamente
            print('📴 Sin conexión - Agregando foto a cola de sincronización');
            await syncService.addOperation(
              type: 'upload_photo',
              ordenId: orden.id,
              data: {
                'photo_base64': photoBase64,
                'file_path': image.path, // 🔒 CRÍTICO: Incluir ruta del archivo para sincronización
              },
            );
            
            // 🔒 CRÍTICO: Actualizar caché local de la orden con la foto local
            try {
              final ordenCached = await OrdenCacheService.getCachedOrderById(orden.id);
              if (ordenCached != null) {
                final ordenJson = ordenCached.toJson();
                ordenJson['foto_entrega'] = 'local://${image.path}';
                final ordenActualizada = Orden.fromJson(ordenJson);
                await OrdenCacheService.updateCachedOrder(ordenActualizada);
                print('💾 Orden actualizada en caché local con foto: ${image.path}');
              }
            } catch (e) {
              print('⚠️ Error actualizando caché local con foto: $e');
            }
            
            if (mounted) {
              Navigator.of(context).pop(); // Cerrar diálogo de carga
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Foto guardada - Puedes continuar con la entrega (modo offline)'),
                  backgroundColor: Color(0xFF2196F3),
                  duration: Duration(seconds: 3),
                ),
              );
            }
          }
        } catch (e) {
          print('❌ Error procesando foto: $e');
          if (mounted) {
            Navigator.of(context).pop(); // Cerrar diálogo de carga
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ Error al procesar la foto: $e'),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
    } catch (e) {
      print('❌ Error al seleccionar foto: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error al seleccionar foto: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // ========== MÉTODOS DE RASTREO DE UBICACIÓN ==========
  
  Future<void> _obtenerTenantId() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        // 🔒 CRÍTICO: Intentar cargar desde cached_user_data primero (es la fuente principal)
        try {
          final prefs = await SharedPreferences.getInstance();
          final cachedUserData = prefs.getString('cached_user_data_${user.id}');
          
          if (cachedUserData != null) {
            final userData = jsonDecode(cachedUserData) as Map<String, dynamic>;
            final tenantId = userData['tenant_id'] as String?;
            
            if (tenantId != null) {
              setState(() {
                _tenantId = tenantId;
              });
              print('💾 Tenant ID cargado desde cached_user_data: $_tenantId');
              
              // También guardar en cached_tenant_id para consistencia
              await prefs.setString('cached_tenant_id_${user.id}', tenantId);
            }
          } else {
            // Si no hay cached_user_data, intentar cached_tenant_id
            final cachedTenantId = prefs.getString('cached_tenant_id_${user.id}');
            if (cachedTenantId != null) {
              setState(() {
                _tenantId = cachedTenantId;
              });
              print('💾 Tenant ID cargado desde cached_tenant_id: $_tenantId');
            }
          }
        } catch (cacheError) {
          print('⚠️ Error leyendo caché de tenant_id: $cacheError');
        }
        
        // Intentar actualizar desde BD en segundo plano
        try {
          final userData = await supabase
              .from('usuarios')
              .select('tenant_id, auth_id')
              .eq('auth_id', user.id)
              .single();
          
          final tenantIdFromDB = userData['tenant_id'] as String?;
          final authIdFromDB = userData['auth_id'] as String?;
          
          // 🔒 VALIDACIÓN DE SEGURIDAD: Verificar que el auth_id coincide
          if (authIdFromDB != user.id) {
            print('🚨 CRÍTICO: auth_id no coincide! DB: $authIdFromDB, Usuario: ${user.id}');
            // Esto NO debería pasar nunca, pero si pasa, limpiar todo
            _tenantId = null;
            return;
          }
          
          if (tenantIdFromDB != null) {
            // 🔒 CRÍTICO: Guardar en caché
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('cached_tenant_id_${user.id}', tenantIdFromDB);
              print('💾 Tenant ID guardado en caché');
            } catch (cacheError) {
              print('⚠️ Error guardando tenant_id en caché: $cacheError');
            }
            
            // 🔒 VALIDACIÓN: Si el tenant_id cambió, es un problema grave
            if (_tenantId != null && _tenantId != tenantIdFromDB) {
              print('🚨 ADVERTENCIA: Tenant ID cambió de $_tenantId a $tenantIdFromDB - Recargando órdenes...');
              setState(() {
                _tenantId = tenantIdFromDB;
              });
              // Recargar órdenes con el tenant_id correcto
              await _cargarOrdenes();
            } else {
              setState(() {
                _tenantId = tenantIdFromDB;
              });
              print('✅ Tenant ID obtenido: $_tenantId');
            }
          }
        } catch (e) {
          print('⚠️ Error obteniendo tenant_id desde BD: $e');
          // Si falla y no hay caché, esto es un problema grave
          if (_tenantId == null) {
            print('🚨 CRÍTICO: No se pudo obtener tenant_id ni desde BD ni desde caché');
          }
        }
      }
    } catch (e) {
      print('❌ Error obteniendo tenant_id: $e');
    }
  }

  Future<void> _cargarConfiguracionRastreo() async {
    try {
      final response = await supabase
          .from('configuracion_envios')
          .select('rastreo_tiempo_real, intervalo_actualizacion')
          .limit(1)
          .maybeSingle();
      
      if (response != null && mounted) {
        setState(() {
          _rastreoTiempoReal = response['rastreo_tiempo_real'] ?? false;
          _intervaloActualizacion = response['intervalo_actualizacion'] ?? 30;
        });
        print('✅ Configuración de rastreo cargada: activo=$_rastreoTiempoReal, intervalo=${_intervaloActualizacion}s');
      }
    } catch (e) {
      print('⚠️ Error al cargar configuración de rastreo: $e');
    }
  }
  
  Future<void> _cargarConfiguracionRecogidaSucursal() async {
    try {
      final response = await supabase
          .from('configuracion_envios')
          .select('recoger_en_sucursal_solo_master')
          .limit(1)
          .maybeSingle();
      
      if (response != null && mounted) {
        setState(() {
          _recogerEnSucursalSoloMaster = response['recoger_en_sucursal_solo_master'] ?? false;
        });
        print('✅ Configuración de recogida en sucursal cargada: solo_master=$_recogerEnSucursalSoloMaster');
      }
    } catch (e) {
      print('⚠️ Error al cargar configuración de recogida en sucursal: $e');
    }
  }

  // Verificar y activar rastreo GPS
  // CRÍTICO: Ahora siempre activa el rastreo cuando la app está abierta para que el panel admin
  // pueda detectar que el repartidor está online, independientemente de si tiene órdenes en "EN REPARTO"
  Future<void> _verificarYActivarRastreo() async {
    // Verificar si hay órdenes en estado "EN REPARTO"
    final ordenesEnReparto = _ordenes.where((orden) => orden.estado == 'EN REPARTO').toList();
    
    // CRÍTICO: Siempre activar rastreo si la app está abierta (para mostrar LED verde en panel admin)
    // Esto permite que el panel admin detecte que el repartidor está activo, incluso sin órdenes en "EN REPARTO"
    if (_timerUbicacion == null || !_timerUbicacion!.isActive) {
      print('📍 App abierta - Activando rastreo GPS para indicador online/offline');
      print('📍 Órdenes en "EN REPARTO": ${ordenesEnReparto.length}');
      await _iniciarRastreoUbicacion();
    } else {
      print('📍 Rastreo GPS ya está activo');
      if (ordenesEnReparto.isNotEmpty) {
        print('📍 Hay ${ordenesEnReparto.length} orden(es) en "EN REPARTO" - Rastreo continuará');
      } else {
        print('📍 No hay órdenes en "EN REPARTO" - Rastreo continuará para indicador online');
      }
    }
  }

  bool _iniciandoRastreo = false; // Bandera para evitar múltiples llamadas simultáneas
  
  Future<void> _iniciarRastreoUbicacion() async {
    // Evitar múltiples llamadas simultáneas
    if (_iniciandoRastreo) {
      print('⚠️ Rastreo ya está en proceso, ignorando llamada duplicada');
      return;
    }
    
    _iniciandoRastreo = true;
    
    try {
      // Solo iniciar rastreo si hay órdenes en "EN REPARTO"
      print('📍 ========================================');
      print('📍 INICIANDO RASTREO DE UBICACIÓN');
      print('📍 ========================================');
    
      // CRÍTICO: REQUERIDO por Google Play - Mostrar TODOS los avisos ANTES de verificar o solicitar cualquier permiso del sistema
      // NO debemos llamar a Geolocator.checkPermission() o requestPermission() ANTES de mostrar los avisos
      final prefs = await SharedPreferences.getInstance();
      final avisoDestacadoVisto = prefs.getBool('aviso_ubicacion_destacado_visto') ?? false;
      final avisoSegundoPlanoVisto = prefs.getBool('aviso_ubicacion_segundo_plano_visto') ?? false;
      
      // CRÍTICO: Esperar un momento para asegurar que la pantalla esté completamente cargada
      // Esto previene que el diálogo del sistema aparezca antes de nuestros avisos
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) {
        _iniciandoRastreo = false;
        return;
      }
      
      // PASO 0: Verificar servicios de ubicación (esto NO activa diálogos)
      // PERO lo hacemos DESPUÉS de mostrar los avisos para estar seguros
      // Por ahora solo verificamos si los avisos se han mostrado
      
      // PASO 1: Mostrar aviso destacado si no se ha visto (ANTES de cualquier solicitud del sistema)
      if (!avisoDestacadoVisto) {
        print('⚠️ Mostrando aviso destacado ANTES de solicitar permiso del sistema...');
        if (!mounted) {
          _iniciandoRastreo = false;
          return;
        }
        
        // Esperar un momento para asegurar que no hay otros diálogos abiertos
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) {
          _iniciandoRastreo = false;
          return;
        }
        
        bool? usuarioAceptaAviso;
        try {
          usuarioAceptaAviso = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (context) => AvisoUbicacionDestacadoScreen(
                onContinuar: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop(true);
                  }
                },
              ),
              fullscreenDialog: true,
            ),
          );
        } catch (e) {
          print('❌ Error mostrando aviso destacado: $e');
          _iniciandoRastreo = false;
          return;
        }
        
        if (usuarioAceptaAviso != true) {
          print('❌ Usuario rechazó el aviso - No se puede continuar sin permiso');
          _iniciandoRastreo = false;
          return;
        }
        
        // Guardar que ya se mostró
        await prefs.setBool('aviso_ubicacion_destacado_visto', true);
        print('✅ Usuario aceptó el aviso destacado');
        
        // Esperar un momento antes de continuar
        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted) {
          _iniciandoRastreo = false;
          return;
        }
      }
      
      // PASO 2: Mostrar aviso de segundo plano si no se ha visto (ANTES de solicitar permiso básico)
      // Esto es CRÍTICO: Google Play requiere que el aviso aparezca ANTES del diálogo del sistema
      if (!avisoSegundoPlanoVisto) {
        print('📍 Mostrando aviso de segundo plano ANTES de solicitar permiso del sistema...');
        if (!mounted) {
          _iniciandoRastreo = false;
          return;
        }
        
        // Esperar un momento para asegurar que no hay otros diálogos abiertos
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) {
          _iniciandoRastreo = false;
          return;
        }
        
        bool? usuarioAceptaAviso;
        try {
          usuarioAceptaAviso = await AvisoUbicacionSegundoPlanoScreen.mostrarSiNecesario(context);
        } catch (e) {
          print('❌ Error mostrando aviso de segundo plano: $e');
          usuarioAceptaAviso = false;
        }
        
        if (usuarioAceptaAviso == false) {
          print('⚠️ Usuario rechazó el aviso de segundo plano');
          print('⚠️ El rastreo funcionará solo cuando la app esté abierta');
          // Continuar sin permiso de segundo plano, pero al menos solicitar permiso básico
        } else {
          print('✅ Usuario aceptó el aviso de segundo plano');
        }
        
        // Esperar un momento antes de continuar
        await Future.delayed(const Duration(milliseconds: 200));
        if (!mounted) {
          _iniciandoRastreo = false;
          return;
        }
      }
      
      // PASO 2.5: Verificar servicios de ubicación (DESPUÉS de mostrar avisos, ANTES de solicitar permisos)
      print('📍 Paso 2.5: Verificando servicios de ubicación (después de mostrar avisos)...');
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ Servicios de ubicación deshabilitados en el dispositivo');
        _iniciandoRastreo = false;
        return;
      }
      print('✅ Servicios de ubicación habilitados');
      
      // Esperar un momento adicional antes de solicitar permisos
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) {
        _iniciandoRastreo = false;
        return;
      }
      
      // PASO 3: SOLO AHORA verificar y solicitar permiso básico del sistema (después de mostrar todos los avisos)
      print('📍 Paso 3: Verificando permisos (DESPUÉS de mostrar avisos)...');
      LocationPermission permission = await Geolocator.checkPermission();
      print('📍 Estado actual de permisos: $permission');
      
      if (permission == LocationPermission.denied) {
        print('📍 Solicitando permisos de ubicación básicos (después de mostrar avisos)...');
        permission = await Geolocator.requestPermission();
        print('📍 Respuesta del usuario: $permission');
        
        if (permission == LocationPermission.denied) {
          print('❌ Permisos de ubicación denegados por el usuario');
          _iniciandoRastreo = false;
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('❌ Permisos de ubicación denegados permanentemente');
        print('❌ El usuario debe habilitarlos manualmente en Configuración');
        _iniciandoRastreo = false;
        return;
      }

      print('✅ Permisos de ubicación básicos concedidos: $permission');

      // PASO 4: Solicitar permiso de ubicación en segundo plano (si el usuario aceptó el aviso)
      if (permission == LocationPermission.whileInUse) {
        print('📍 El usuario solo concedió "mientras está en uso"');
        
        // Solo solicitar permiso de segundo plano si el usuario aceptó el aviso
        final avisoSegundoPlanoAceptado = prefs.getBool('aviso_ubicacion_segundo_plano_visto') ?? false;
        
        if (avisoSegundoPlanoAceptado) {
          print('📍 Usuario aceptó el aviso - Solicitando permiso "Permitir todo el tiempo"...');
          
          if (!mounted) {
            _iniciandoRastreo = false;
            return;
          }
          
          try {
            // Usar permission_handler para solicitar permiso de segundo plano
            final backgroundStatus = await Permission.locationAlways.request();
          
            if (backgroundStatus.isGranted) {
              print('✅ Permiso de ubicación en segundo plano concedido');
              // Verificar nuevamente con Geolocator
              final updatedPermission = await Geolocator.checkPermission();
              if (updatedPermission == LocationPermission.always) {
                print('✅ Confirmado: Permiso "Permitir todo el tiempo" activo');
              }
            } else if (backgroundStatus.isPermanentlyDenied) {
              print('⚠️ Permiso de segundo plano denegado permanentemente');
              // Mostrar diálogo para ir a configuración
              if (mounted) {
                _mostrarDialogoPermisoSegundoPlano();
              }
            } else {
              print('⚠️ El usuario solo concedió "mientras está en uso"');
              print('⚠️ El rastreo funcionará solo cuando la app esté abierta');
              // Mostrar mensaje al usuario
              if (mounted) {
                _mostrarDialogoPermisoSegundoPlano();
              }
            }
          } catch (e) {
            print('⚠️ Error al solicitar permiso de segundo plano: $e');
            // Continuar de todas formas, al menos tendrá rastreo mientras la app está abierta
          }
        } else {
          print('⚠️ Usuario no aceptó el aviso de segundo plano - Rastreo solo cuando app está abierta');
        }
      } else if (permission == LocationPermission.always) {
        print('✅ Ya tiene permiso de ubicación en segundo plano (Permitir todo el tiempo)');
      }

      // Obtener ID del repartidor
      print('📍 Paso 3: Obteniendo datos del repartidor...');
      final user = supabase.auth.currentUser;
      if (user == null) {
        print('❌ No hay usuario autenticado');
        return;
      }
      print('✅ Usuario autenticado: ${user.id}');

      if (_tenantId == null) {
        print('❌ No hay tenant_id, esperando...');
        await Future.delayed(const Duration(seconds: 2));
        if (_tenantId == null) {
          print('❌ Tenant_id aún no disponible');
          return;
        }
      }
      print('✅ Tenant ID: $_tenantId');

      final repartidorData = await supabase
          .from('usuarios')
          .select('id')
          .eq('auth_id', user.id)
          .single();

      final repartidorId = repartidorData['id'];
      print('✅ Repartidor ID para rastreo: $repartidorId');

      // Iniciar actualización periódica de ubicación
      print('📍 Paso 4: Iniciando actualización periódica de ubicación...');
      print('📍 Configuración: intervalo=${_intervaloActualizacion}s, precisión=alta');
      
      // Función para obtener y guardar ubicación
      Future<void> obtenerYGuardarUbicacion() async {
        try {
          print('📍 Obteniendo ubicación actual...');
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
          );
          
          // Guardar ubicación actual para ordenamiento por distancia
          if (mounted) {
            setState(() {
              _ubicacionActual = position;
            });
            // La UI se actualizará automáticamente porque _ordenesFiltradas
            // usa _aplicarOrdenamiento que considera _ubicacionActual
          }
          
          print('');
          print('📍 ========================================');
          print('📍 NUEVA UBICACIÓN DETECTADA');
          print('📍 ========================================');
          print('📍 Latitud: ${position.latitude}');
          print('📍 Longitud: ${position.longitude}');
          print('📍 Precisión: ${position.accuracy}m');
          print('📍 Velocidad: ${position.speed}m/s');
          print('📍 Dirección: ${position.heading}°');
          print('📍 Timestamp: ${DateTime.now()}');
          
          print('📍 Guardando en base de datos...');
          print('📍 Datos a insertar:');
          print('   - repartidor_id: $repartidorId (tipo: ${repartidorId.runtimeType})');
          print('   - tenant_id: $_tenantId (tipo: ${_tenantId.runtimeType})');
          print('   - latitude: ${position.latitude}');
          print('   - longitude: ${position.longitude}');
          print('   - accuracy: ${position.accuracy}');
          print('   - heading: ${position.heading}');
          print('   - speed: ${position.speed}');
          
          // Guardar ubicación en Supabase
          final result = await supabase.from('ubicaciones_repartidores').insert({
            'repartidor_id': repartidorId.toString(),
            'tenant_id': _tenantId.toString(),
            'latitude': position.latitude,
            'longitude': position.longitude,
            'accuracy': position.accuracy,
            'heading': position.heading,
            'speed': position.speed,
          }).select();
          
          print('✅ ✅ ✅ UBICACIÓN GUARDADA EXITOSAMENTE ✅ ✅ ✅');
          print('✅ Registros insertados: ${result.length}');
          print('✅ Repartidor ID: $repartidorId');
          print('✅ Tenant ID: $_tenantId');
          print('📍 ========================================');
          print('');
        } catch (e, stackTrace) {
          // Forzar impresión del error completo
          print('');
          print('❌ ❌ ❌ ERROR GUARDANDO UBICACIÓN ❌ ❌ ❌');
          print('❌ ========================================');
          print('❌ Tipo de error: ${e.runtimeType}');
          print('❌ Mensaje de error: $e');
          print('❌ ========================================');
          print('❌ Stack trace completo:');
          print(stackTrace.toString());
          print('❌ ========================================');
          print('');
          
          // Intentar obtener más detalles del error
          final errorString = e.toString();
          print('❌ Análisis del error:');
          if (errorString.contains('PostgrestException') || errorString.contains('Postgrest')) {
            print('❌ ⚠️ ERROR DE SUPABASE/POSTGREST DETECTADO');
          }
          if (errorString.contains('RLS') || errorString.contains('policy') || errorString.contains('row-level security')) {
            print('❌ ⚠️ ⚠️ ⚠️ PROBLEMA CON POLÍTICAS RLS ⚠️ ⚠️ ⚠️');
            print('❌ El repartidor no tiene permiso para insertar en ubicaciones_repartidores');
            print('❌ Verifica las políticas RLS en Supabase para la tabla ubicaciones_repartidores');
          }
          if (errorString.contains('null') || errorString.contains('NULL')) {
            print('❌ ⚠️ PROBLEMA CON VALORES NULL');
          }
          if (errorString.contains('permission') || errorString.contains('denied')) {
            print('❌ ⚠️ PROBLEMA DE PERMISOS');
          }
          print('');
        }
      }
      
      // Obtener ubicación inmediatamente
      await obtenerYGuardarUbicacion();
      
      // Configurar timer para actualizar cada X segundos según la configuración
      // CRÍTICO: Usar intervalo corto (30 segundos) para detección INSTANTÁNEA de online/offline
      // Esto asegura que el panel admin detecte INMEDIATAMENTE cuando el repartidor está activo o se cierra
      final intervaloIndicador = 30; // 30 segundos para detección instantánea
      _timerUbicacion = Timer.periodic(
        Duration(seconds: intervaloIndicador),
        (timer) {
          obtenerYGuardarUbicacion();
        },
      );
      
      print('📍 Timer configurado: actualización cada $intervaloIndicador segundos para detección INSTANTÁNEA online/offline');

      print('✅ ✅ ✅ RASTREO DE UBICACIÓN INICIADO CORRECTAMENTE ✅ ✅ ✅');
      print('📍 El stream está activo y escuchando ubicaciones...');
      print('📍 ========================================');
      print('');
    } catch (e) {
      print('❌ Error iniciando rastreo: $e');
    } finally {
      _iniciandoRastreo = false; // Liberar la bandera siempre, incluso si hay error
    }
  }

  // Detener rastreo de ubicación
  void _detenerRastreoUbicacion() {
    print('📍 Deteniendo rastreo de ubicación...');
    _positionStreamSubscription?.cancel();
    _timerUbicacion?.cancel();
    _positionStreamSubscription = null;
    _timerUbicacion = null;
    print('✅ Rastreo de ubicación detenido');
  }

  // Construir banner de notificación general
  Widget _buildBannerNotificacion() {
    if (_notificacionGeneralBanner == null) return const SizedBox.shrink();
    
    final titulo = _notificacionGeneralBanner!['titulo']?.toString() ?? 'Notificación';
    final mensaje = _notificacionGeneralBanner!['mensaje']?.toString() ?? '';
    
    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _mostrarDetalleNotificacionBanner(context, _notificacionGeneralBanner!),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(
                  Icons.notifications_active,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        mensaje,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  onPressed: () {
                    setState(() {
                      _notificacionGeneralBanner = null;
                    });
                  },
                  tooltip: 'Cerrar',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Mostrar detalle de notificación desde el banner
  Future<void> _mostrarDetalleNotificacionBanner(BuildContext context, Map<String, dynamic> notif) async {
    final id = notif['id']?.toString() ?? '';
    final titulo = notif['titulo']?.toString() ?? 'Notificación';
    final mensaje = notif['mensaje']?.toString() ?? '';
    final fecha = notif['created_at']?.toString();
    final leida = notif['leida'] ?? false;

    // CRÍTICO: Marcar como leída cuando el usuario abre el detalle
    // Una vez leída, NO debe volver a aparecer nunca más
    if (!leida && id.isNotEmpty) {
      try {
        print('📖 Marcando notificación del banner como leída: $id');
        
        final resultado = await supabase
            .from('notificaciones_repartidores')
            .update({'leida': true})
            .eq('id', id)
            .select();
        
        if (resultado.isNotEmpty) {
          print('✅ Notificación del banner marcada como leída exitosamente');
          print('   - ID: ${resultado.first['id']}');
          print('   - Leída: ${resultado.first['leida']}');
        } else {
          print('⚠️ No se pudo actualizar la notificación del banner');
        }
        
        // Actualizar el estado local
        setState(() {
          _notificacionGeneralBanner = null; // Ocultar banner
        });
        
        // Actualizar contador
        await _cargarNotificacionesNoLeidas();
      } catch (e) {
        print('❌ Error marcando notificación del banner como leída: $e');
      }
    }

    // Mostrar modal con el contenido completo
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9800).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.notifications,
                      color: Color(0xFFFF9800),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2C2C2C),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatearFechaString(fecha),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF666666)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(height: 1),
              const SizedBox(height: 24),
              // Contenido completo
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    mensaje,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF2C2C2C),
                      height: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Botón de adjunto (si existe)
              if (notif['tiene_adjunto'] == true) ...[
                if (notif['tipo_adjunto'] == 'url')
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final url = notif['url_adjunto']?.toString();
                        if (url != null && url.isNotEmpty) {
                          try {
                            final uri = Uri.parse(url);
                            // CRÍTICO: Abrir en navegador externo
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                            print('✅ URL abierta externamente: $url');
                          } catch (e) {
                            print('❌ Error abriendo URL: $e');
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error al abrir enlace: $e')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.link, size: 20),
                      label: const Text(
                        'Ver Enlace',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  )
                else if (notif['tipo_adjunto'] == 'archivo')
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final url = notif['archivo_url']?.toString();
                        if (url != null && url.isNotEmpty) {
                          try {
                            final uri = Uri.parse(url);
                            // CRÍTICO: Abrir/descargar en navegador externo
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                            print('✅ Archivo abierto/descargado externamente: $url');
                          } catch (e) {
                            print('❌ Error descargando archivo: $e');
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error al descargar archivo: $e')),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.download, size: 20),
                      label: Text(
                        'Descargar ${notif['archivo_nombre'] ?? 'Archivo'}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              // Botón de cerrar/aceptar
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // El banner ya se ocultó cuando se marcó como leída
                    // Actualizar contador de notificaciones no leídas
                    _cargarNotificacionesNoLeidas();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF9800),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    notif['tiene_adjunto'] == true ? 'Cerrar' : 'Aceptar',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatearFechaString(String? fecha) {
    if (fecha == null) return 'Fecha no disponible';
    
    try {
      final fechaDateTime = DateTime.parse(fecha);
      final ahora = DateTime.now();
      final diferencia = ahora.difference(fechaDateTime);
      
      if (diferencia.inDays == 0) {
        if (diferencia.inHours == 0) {
          if (diferencia.inMinutes == 0) {
            return 'Hace unos momentos';
          }
          return 'Hace ${diferencia.inMinutes} min';
        }
        return 'Hace ${diferencia.inHours} h';
      } else if (diferencia.inDays == 1) {
        return 'Ayer';
      } else if (diferencia.inDays < 7) {
        return 'Hace ${diferencia.inDays} días';
      } else {
        return '${fechaDateTime.day}/${fechaDateTime.month}/${fechaDateTime.year}';
      }
    } catch (e) {
      return 'Fecha no disponible';
    }
  }
}
