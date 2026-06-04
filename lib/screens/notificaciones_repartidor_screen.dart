import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';
import '../models/orden.dart';
import '../constants/repartidor_notificacion_tipos.dart';
import '../services/repartidor_notificaciones_push_service.dart';
import '../services/repartidor_pantallas_offline_service.dart';
import '../services/sync_service.dart';
import '../services/network_timeout.dart';
import 'detalle_orden_screen.dart';
import '../config/app_colors.dart';

class NotificacionesRepartidorScreen extends StatefulWidget {
  const NotificacionesRepartidorScreen({super.key});

  @override
  State<NotificacionesRepartidorScreen> createState() => _NotificacionesRepartidorScreenState();
}

class _NotificacionesRepartidorScreenState extends State<NotificacionesRepartidorScreen> with WidgetsBindingObserver {
  bool _isLoading = true;
  String? _repartidorId; // id de tabla usuarios
  String? _authId; // id de auth (supabase.auth.currentUser?.id)
  String? _repartidorNombre;
  bool _esRecolector = false; // Indica si es recolector
  
  // Listas de notificaciones
  List<Map<String, dynamic>> _notificacionesOrdenes = [];
  List<Map<String, dynamic>> _notificacionesPagos = [];
  List<Map<String, dynamic>> _notificacionesGenerales = [];
  
  // Tabs
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
      WidgetsBinding.instance.addObserver(this);
      _obtenerRepartidorId();
      // NO marcar notificaciones como leídas automáticamente
      // Solo se marcarán cuando el usuario las lea explícitamente
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Recargar notificaciones cuando la app vuelve a primer plano
    if (state == AppLifecycleState.resumed && _repartidorId != null) {
      _cargarNotificaciones();
    }
  }

  Future<void> _marcarNotificacionesComoLeidas() async {
    try {
      if (_repartidorId == null) return;

      // CRÍTICO: Si es recolector, actualizar en notificaciones_recolectores, si no, en notificaciones_repartidores
      final tablaNotificaciones = _esRecolector ? 'notificaciones_recolectores' : 'notificaciones_repartidores';
      final campoId = _esRecolector ? 'recolector_id' : 'repartidor_id';

      await supabase
          .from(tablaNotificaciones)
          .update({'leida': true})
          .eq(campoId, _repartidorId!)
          .eq('leida', false);

      print('✅ Notificaciones marcadas como leídas');
    } catch (e) {
      print('❌ Error marcando notificaciones como leídas: $e');
    }
  }

  Future<void> _obtenerRepartidorId() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      _authId = user.id;

      String? repartidorNombre;
      // Buscar por auth_id (correcto para obtener el id de usuarios)
      try {
        final response = await supabase
            .from('usuarios')
            .select('id, nombre, tipo_repartidor')
            .eq('auth_id', user.id)
            .maybeSingle();

        if (response != null) {
          // CRÍTICO: Convertir a String para consistencia con repartidor_mobile_screen
          _repartidorId = response['id']?.toString();
          repartidorNombre = response['nombre'];
          final tipoRepartidor = response['tipo_repartidor']?.toString();
          _esRecolector = tipoRepartidor == 'RECOLECTOR';
          print('✅ Repartidor ID obtenido: $_repartidorId (tipo: ${_repartidorId.runtimeType})');
          print('✅ Es recolector: $_esRecolector');
        }
      } catch (e) {
        print('❌ Error obteniendo repartidor por auth_id: $e');
      }

      // Fallback por email
      if (_repartidorId == null && user.email != null) {
        try {
          final response = await supabase
              .from('usuarios')
              .select('id, nombre')
              .eq('email', user.email!)
              .maybeSingle();

          if (response != null) {
            // CRÍTICO: Convertir a String para consistencia
            _repartidorId = response['id']?.toString();
            repartidorNombre = response['nombre'];
            print('✅ Repartidor ID obtenido (fallback email): $_repartidorId');
          }
        } catch (e2) {
          print('❌ Error obteniendo repartidor por email: $e2');
        }
      }

      if (_repartidorId != null && repartidorNombre != null) {
        if (mounted) {
          setState(() {
            _repartidorNombre = repartidorNombre;
          });
        }
        await _cargarNotificaciones();
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      print('❌ Error al obtener ID del repartidor: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cargarNotificaciones() async {
    if (_repartidorId == null || _repartidorNombre == null || _repartidorNombre!.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    final cached = await RepartidorPantallasOfflineService.cargarNotificaciones(_repartidorId!);
    if (cached != null && mounted) {
      setState(() {
        _notificacionesOrdenes = cached.ordenes;
        _notificacionesPagos = cached.pagos;
        _notificacionesGenerales = cached.generales;
        _isLoading = false;
      });
    }

    final syncService = SyncService();
    if (!syncService.isOnline) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      if (cached == null) {
        setState(() => _isLoading = true);
      }

      // CRÍTICO: Si es recolector, cargar de notificaciones_recolectores, si no, de notificaciones_repartidores
      final tablaNotificaciones = _esRecolector ? 'notificaciones_recolectores' : 'notificaciones_repartidores';
      final campoId = _esRecolector ? 'recolector_id' : 'repartidor_id';
      
      // Cargar notificaciones de órdenes desde la tabla correspondiente
      // Tipos alineados con VolonexPro+ (canónico: nueva_orden)
      // CRÍTICO: Solo cargar NOTIFICACIONES NO LEÍDAS
      // Las leídas se QUITAN de la pantalla para evitar que se lean de nuevo
      print('🔍 Cargando notificaciones de órdenes (solo no leídas)...');
      print('   - Repartidor ID (tabla usuarios): $_repartidorId');
      print('   - Es recolector: $_esRecolector');
      print('   - Tabla: $tablaNotificaciones');
      
      final ordenesResponseRaw = await ejecutarConTimeout(
        supabase
            .from(tablaNotificaciones)
            .select('id, tipo, titulo, mensaje, created_at, leida, orden_id, numero_orden')
            .eq(campoId, _repartidorId!)
            .inFilter('tipo', RepartidorNotificacionTipos.tiposOrdenNueva)
            .eq('leida', false)
            .order('created_at', ascending: false)
            .limit(100),
      );
      if (ordenesResponseRaw == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final ordenesResponse = List<Map<String, dynamic>>.from(ordenesResponseRaw as List);
      
      print('📊 Notificaciones de órdenes NO LEÍDAS encontradas: ${ordenesResponse.length}');
      
      // Para cada notificación, obtener los datos completos de la orden
      final List<Map<String, dynamic>> ordenesConDatos = [];
      for (var notif in ordenesResponse) {
        try {
          if (notif['orden_id'] != null) {
            final ordenData = await supabase
                .from('ordenes')
                .select('id, numero_orden, descripcion, direccion_destino, provincia_destino, municipio_destino, estado, fecha_creacion, fecha_envio, emisor_nombre, destinatario_nombre')
                .eq('id', notif['orden_id'])
                .maybeSingle();
            
            if (ordenData != null) {
              // Combinar datos de la notificación con datos de la orden
              ordenesConDatos.add({
                ...ordenData,
                'notificacion_id': notif['id'],
                'notificacion_leida': notif['leida'],
                'notificacion_created_at': notif['created_at'],
              });
            }
          }
        } catch (e) {
          print('⚠️ Error obteniendo datos de orden ${notif['orden_id']}: $e');
        }
      }

      // Cargar notificaciones de pagos desde la tabla correspondiente
      // Tipos: PAGO_ACEPTADO, PAGO_RECHAZADO, PAGO_CANCELADO
      // CRÍTICO: Usar solo _repartidorId (id de tabla usuarios), NO _authId
      // porque las notificaciones se guardan con el id de usuarios, no con auth_id
      if (_repartidorId == null) {
        print('❌ ERROR: _repartidorId es null, no se pueden cargar notificaciones');
        if (mounted) {
          setState(() {
            _notificacionesPagos = [];
            _notificacionesGenerales = [];
            _isLoading = false;
          });
        }
        return;
      }

      // Cargar notificaciones de pagos — solo no leídas (desaparecen al leer)
      final pagosResponse = await supabase
          .from(tablaNotificaciones)
          .select('id, tipo, titulo, mensaje, created_at, leida')
          .eq(campoId, _repartidorId!)
          .inFilter('tipo', ['PAGO_ACEPTADO', 'PAGO_RECHAZADO', 'PAGO_CANCELADO'])
          .eq('leida', false)
          .order('created_at', ascending: false) // Más recientes primero
          .limit(100); // Aumentar límite para mostrar más notificaciones
      
      print('📊 Notificaciones de pagos NO LEÍDAS: ${pagosResponse.length}');

      // Cargar notificaciones generales (mensajes de la empresa) — solo no leídas
      print('🔍 Cargando notificaciones generales (solo no leídas)...');
      print('   - Repartidor ID (tabla usuarios): $_repartidorId');
      print('   - Tipo de _repartidorId: ${_repartidorId.runtimeType}');
      print('   - Es recolector: $_esRecolector');
      
      var generalesResponse = await supabase
          .from(tablaNotificaciones)
          .select('id, tipo, titulo, mensaje, created_at, leida, $campoId, tiene_adjunto, tipo_adjunto, url_adjunto, archivo_url, archivo_nombre')
          .eq(campoId, _repartidorId!)
          .eq('tipo', 'general')
          .eq('leida', false)
          .order('created_at', ascending: false) // Más recientes primero
          .limit(100); // Aumentar límite para mostrar más notificaciones
      
      print('📊 Notificaciones generales NO LEÍDAS: ${generalesResponse.length}');
      
      if (generalesResponse.isNotEmpty) {
        print('✅ Notificaciones generales encontradas:');
        for (var notif in generalesResponse.take(3)) {
          print('   - ID: ${notif['id']}, Título: ${notif['titulo']}, Leída: ${notif['leida']}');
        }
      } else {
        print('ℹ️ No hay notificaciones generales para este repartidor_id');
      }

      if (mounted) {
        setState(() {
          _notificacionesOrdenes = ordenesConDatos;
          _notificacionesPagos = List<Map<String, dynamic>>.from(pagosResponse);
          _notificacionesGenerales = List<Map<String, dynamic>>.from(generalesResponse);
          _isLoading = false;
        });

        await RepartidorPantallasOfflineService.guardarNotificaciones(
          _repartidorId!,
          ordenes: ordenesConDatos,
          pagos: List<Map<String, dynamic>>.from(pagosResponse),
          generales: List<Map<String, dynamic>>.from(generalesResponse),
        );
        
        print('✅ Notificaciones cargadas:');
        print('   - Órdenes: ${_notificacionesOrdenes.length}');
        print('   - Pagos: ${_notificacionesPagos.length}');
        print('   - Generales: ${_notificacionesGenerales.length}');
      }
    } catch (e) {
      print('❌ Error al cargar notificaciones: $e');
      if (mounted) {
        setState(() {
          if (cached != null) {
            _notificacionesOrdenes = cached.ordenes;
            _notificacionesPagos = cached.pagos;
            _notificacionesGenerales = cached.generales;
          }
          _isLoading = false;
        });
      }
    }
  }

  String _obtenerTituloOrden(Map<String, dynamic> orden) {
    final numeroOrden = orden['numero_orden']?.toString() ?? 'N/A';
    final estado = orden['estado']?.toString() ?? '';
    
    if (estado == 'POR ENVIAR') {
      return 'Nueva orden asignada: #$numeroOrden';
    } else if (estado == 'EN TRANSITO') {
      return 'Orden en tránsito: #$numeroOrden';
    }
    return 'Orden: #$numeroOrden';
  }


  Color _obtenerColorEstado(String estado) {
    switch (estado) {
      case 'ACEPTADO':
        return const Color(0xFF4CAF50); // Verde
      case 'RECHAZADO':
      case 'CANCELADA':
        return const Color(0xFFDC2626); // Rojo
      case 'POR ENVIAR':
        return const Color(0xFFFF9800); // Naranja
      case 'EN TRANSITO':
        return const Color(0xFF2196F3); // Azul
      default:
        return const Color(0xFF666666); // Gris
    }
  }

  IconData _obtenerIconoEstado(String estado) {
    switch (estado) {
      case 'ACEPTADO':
        return Icons.check_circle;
      case 'RECHAZADO':
      case 'CANCELADA':
        return Icons.cancel;
      case 'POR ENVIAR':
      case 'EN TRANSITO':
        return Icons.local_shipping;
      default:
        return Icons.info;
    }
  }

  String _formatearFecha(dynamic fecha) {
    if (fecha == null) return 'Fecha no disponible';
    
    try {
      final fechaDateTime = fecha is String ? DateTime.parse(fecha) : fecha as DateTime;
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

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: _tabIndex,
      child: Scaffold(
        backgroundColor: AppColors.darkBg,
        appBar: AppBar(
          backgroundColor: const Color(0xFF37474F),
          title: const Text(
            'Notificaciones',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: TabBar(
            indicatorColor: const Color(0xFFFF9800),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(
                icon: () {
                  // Contar solo las NO LEÍDAS para el badge
                  final noLeidas = _notificacionesOrdenes.where((n) => n['notificacion_leida'] == false).length;
                  if (noLeidas == 0) {
                    return const Icon(Icons.local_shipping, size: 20);
                  }
                  return Badge(
                    label: Text('$noLeidas'),
                    backgroundColor: const Color(0xFFFF9800),
                    textColor: Colors.white,
                    child: const Icon(Icons.local_shipping, size: 20),
                  );
                }(),
                text: 'Órdenes',
              ),
              Tab(
                icon: () {
                  // Contar solo las NO LEÍDAS para el badge
                  final noLeidas = _notificacionesPagos.where((n) => n['leida'] == false).length;
                  if (noLeidas == 0) {
                    return const Icon(Icons.payment, size: 20);
                  }
                  return Badge(
                    label: Text('$noLeidas'),
                    backgroundColor: const Color(0xFFFF9800),
                    textColor: Colors.white,
                    child: const Icon(Icons.payment, size: 20),
                  );
                }(),
                text: 'Pagos',
              ),
              Tab(
                icon: () {
                  // Contar solo las NO LEÍDAS para el badge
                  final noLeidas = _notificacionesGenerales.where((n) => n['leida'] == false).length;
                  if (noLeidas == 0) {
                    return const Icon(Icons.notifications, size: 20);
                  }
                  return Badge(
                    label: Text('$noLeidas'),
                    backgroundColor: const Color(0xFFFF9800),
                    textColor: Colors.white,
                    child: const Icon(Icons.notifications, size: 20),
                  );
                }(),
                text: 'General',
              ),
            ],
            onTap: (index) {
              setState(() {
                _tabIndex = index;
              });
            },
          ),
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFFF9800),
                ),
              )
            : TabBarView(
                children: [
                  RefreshIndicator(
                    onRefresh: _cargarNotificaciones,
                    color: const Color(0xFFFF9800),
                    child: _buildListaOrdenes(),
                  ),
                  RefreshIndicator(
                    onRefresh: _cargarNotificaciones,
                    color: const Color(0xFFFF9800),
                    child: _buildListaPagos(),
                  ),
                  RefreshIndicator(
                    onRefresh: _cargarNotificaciones,
                    color: const Color(0xFFFF9800),
                    child: _buildListaGenerales(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildListaOrdenes() {
    if (_notificacionesOrdenes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.local_shipping_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No hay órdenes nuevas',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Las nuevas órdenes asignadas aparecerán aquí',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _notificacionesOrdenes.length,
      itemBuilder: (context, index) {
        final orden = _notificacionesOrdenes[index];
        final estado = orden['estado']?.toString() ?? '';
        final fechaCreacion = orden['fecha_creacion'];
        
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: Colors.white,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: InkWell(
                onTap: () async {
                  // CRÍTICO: Guardar referencia al contexto antes de operaciones asíncronas
                  if (!mounted) return;
                  final currentContext = context;
                  
                  // CRÍTICO: Marcar notificación como leída ANTES de abrir la orden
                  // Esto hará que desaparezca de la lista al recargar
                  final notificacionId = orden['notificacion_id'];
                  if (notificacionId != null) {
                    try {
                      print('🔔 Marcando notificación de orden como leída (ID: $notificacionId)...');
                      final tablaNotificaciones = _esRecolector ? 'notificaciones_recolectores' : 'notificaciones_repartidores';
                      
                      // CRÍTICO: Asegurar que la actualización se guarde correctamente
                      final updateResult = await supabase
                          .from(tablaNotificaciones)
                          .update({'leida': true})
                          .eq('id', notificacionId)
                          .select()
                          .maybeSingle();
                      
                      if (updateResult != null && updateResult['leida'] == true) {
                        print('✅ Notificación de orden marcada como leída - desaparecerá de la lista');
                        await RepartidorNotificacionesPushService.instance
                            .marcarPushMostrado(notificacionId.toString());
                        // NO recargar inmediatamente aquí porque vamos a navegar y puede causar problemas
                        // Se recargará después de volver de la navegación
                      } else {
                        print('⚠️ Advertencia: No se pudo verificar que la notificación se marcó como leída');
                      }
                    } catch (e) {
                      print('❌ Error marcando notificación como leída: $e');
                    }
                  }
                  
                  // Cargar la orden completa desde Supabase
                  if (!mounted) return;
                  
                  try {
                    final ordenCompleta = await supabase
                        .from('ordenes')
                        .select('*')
                        .eq('id', orden['id'])
                        .single();
                    
                    if (!mounted) return;
                    final ordenObj = Orden.fromJson(ordenCompleta);
                    
                    if (!mounted) return;
                    
                    // Navegar a la pantalla de detalles de la orden
                    await Navigator.of(currentContext).push(
                      MaterialPageRoute(
                        builder: (context) => DetalleOrdenScreen(
                          orden: ordenObj,
                        ),
                      ),
                    );
                    
                    // CRÍTICO: Recargar notificaciones después de volver
                    // La notificación leída ya no aparecerá porque solo cargamos no leídas
                    if (mounted) {
                      print('🔄 Recargando notificaciones después de ver orden...');
                      await _cargarNotificaciones();
                    }
                  } catch (e) {
                    print('❌ Error al cargar o navegar a la orden: $e');
                    if (!mounted) return;
                    ScaffoldMessenger.of(currentContext).showSnackBar(
                      SnackBar(
                        content: Text('Error al cargar la orden: $e'),
                        backgroundColor: const Color(0xFFDC2626),
                      ),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icono de estado con indicador de no leída
                      Stack(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: _obtenerColorEstado(estado).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _obtenerIconoEstado(estado),
                              color: _obtenerColorEstado(estado),
                              size: 24,
                            ),
                          ),
                          // Indicador de no leída
                          if (orden['notificacion_leida'] == false)
                            Positioned(
                              right: 0,
                              top: 0,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFF9800),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(width: 16),
                      // Contenido
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _obtenerTituloOrden(orden),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: orden['notificacion_leida'] == false 
                                          ? FontWeight.bold 
                                          : FontWeight.w600,
                                      color: const Color(0xFF2C2C2C),
                                    ),
                                  ),
                                ),
                                // Indicador de no leída
                                if (orden['notificacion_leida'] == false)
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFF9800),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // Mostrar provincia y municipio de entrega
                            if (orden['provincia_destino'] != null || orden['municipio_destino'] != null)
                              Row(
                                children: [
                                  Icon(
                                    Icons.location_on,
                                    size: 14,
                                    color: Colors.grey[600],
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      [
                                        if (orden['provincia_destino'] != null) orden['provincia_destino'].toString(),
                                        if (orden['municipio_destino'] != null) orden['municipio_destino'].toString(),
                                      ].where((s) => s.isNotEmpty).join(', '),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[700],
                                        fontWeight: FontWeight.w500,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _obtenerColorEstado(estado).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    estado,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: _obtenerColorEstado(estado),
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  _formatearFecha(fechaCreacion),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildListaPagos() {
    if (_notificacionesPagos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.payment_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No hay notificaciones de pagos',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Las notificaciones de pagos aceptados, rechazados o cancelados aparecerán aquí',
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

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _notificacionesPagos.length,
      itemBuilder: (context, index) {
        final notif = _notificacionesPagos[index];
        final tipo = notif['tipo']?.toString() ?? '';
        final titulo = notif['titulo']?.toString() ?? 'Notificación de pago';
        final mensaje = notif['mensaje']?.toString() ?? '';
        final fecha = notif['created_at']?.toString();
        final leida = notif['leida'] ?? false;

        // Mapear tipo a estado visual
        String estado;
        Color colorEstado;
        if (tipo == 'PAGO_ACEPTADO') {
          estado = 'ACEPTADO';
          colorEstado = const Color(0xFF4CAF50); // Verde
        } else if (tipo == 'PAGO_RECHAZADO') {
          estado = 'RECHAZADO';
          colorEstado = const Color(0xFFDC2626); // Rojo
        } else if (tipo == 'PAGO_CANCELADO') {
          estado = 'CANCELADA';
          colorEstado = const Color(0xFFDC2626); // Rojo
        } else {
          estado = 'INFO';
          colorEstado = const Color(0xFF666666); // Gris
        }

        // Extraer cantidad del mensaje si es posible
        String cantidadTexto = '';
        try {
          // El mensaje tiene formato: "Tu solicitud de pago de $50.00 ha sido aceptada"
          final regex = RegExp(r'[\$CUP]?([\d,]+\.?\d*)');
          final match = regex.firstMatch(mensaje);
          if (match != null) {
            cantidadTexto = match.group(1) ?? '';
            // Detectar moneda
            if (mensaje.contains('\$') || mensaje.contains('USD')) {
              cantidadTexto = '\$$cantidadTexto USD';
            } else {
              cantidadTexto = '$cantidadTexto CUP';
            }
          }
        } catch (e) {
          // Si no se puede extraer, usar el mensaje completo
        }

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: leida ? AppColors.darkSurface : AppColors.darkElevated,
              elevation: leida ? 2 : 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: leida 
                    ? BorderSide.none
                    : BorderSide(color: colorEstado, width: 2),
              ),
              child: InkWell(
                onTap: () => _mostrarDetalleNotificacionPago(context, notif),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icono de estado
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: colorEstado.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _obtenerIconoEstado(estado),
                          color: colorEstado,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Contenido
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    titulo,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: leida ? FontWeight.normal : FontWeight.bold,
                                      color: leida ? const Color(0xFF666666) : const Color(0xFF2C2C2C),
                                    ),
                                  ),
                                ),
                                if (!leida)
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: colorEstado,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            // Mostrar cantidad destacada si está disponible
                            if (cantidadTexto.isNotEmpty)
                              Text(
                                cantidadTexto,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: colorEstado,
                                ),
                              ),
                            if (cantidadTexto.isNotEmpty) const SizedBox(height: 4),
                            Text(
                              mensaje,
                              style: TextStyle(
                                fontSize: 14,
                                color: leida ? const Color(0xFF999999) : const Color(0xFF666666),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _formatearFecha(fecha),
                              style: TextStyle(
                                fontSize: 12,
                                color: leida ? Colors.grey[500] : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Estado y fecha
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: colorEstado.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              estado,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: colorEstado,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildListaGenerales() {
    if (_notificacionesGenerales.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No hay notificaciones generales',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Las notificaciones push enviadas desde el administrador aparecerán aquí',
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

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _notificacionesGenerales.length,
      itemBuilder: (context, index) {
        final notif = _notificacionesGenerales[index];
        final id = notif['id']?.toString() ?? '';
        final titulo = notif['titulo']?.toString() ?? 'Notificación';
        final mensaje = notif['mensaje']?.toString() ?? '';
        final fecha = notif['created_at']?.toString();
        final leida = notif['leida'] ?? false;

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Card(
              margin: const EdgeInsets.only(bottom: 12),
              color: leida ? AppColors.darkSurface : AppColors.darkElevated,
              elevation: leida ? 2 : 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: leida 
                    ? BorderSide.none
                    : const BorderSide(color: Color(0xFFFF9800), width: 2),
              ),
              child: InkWell(
                onTap: () => _mostrarDetalleNotificacion(context, notif),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Icono de notificación
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: leida 
                              ? const Color(0xFF37474F).withOpacity(0.1)
                              : const Color(0xFFFF9800).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          leida ? Icons.notifications_none : Icons.notifications_active,
                          color: leida ? const Color(0xFF37474F) : const Color(0xFFFF9800),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Contenido
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    titulo,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: leida ? FontWeight.normal : FontWeight.bold,
                                      color: leida ? const Color(0xFF666666) : const Color(0xFF2C2C2C),
                                    ),
                                  ),
                                ),
                                if (!leida)
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFFF9800),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              mensaje,
                              style: TextStyle(
                                fontSize: 14,
                                color: leida ? const Color(0xFF999999) : const Color(0xFF666666),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _formatearFecha(fecha),
                              style: TextStyle(
                                fontSize: 12,
                                color: leida ? Colors.grey[500] : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Icono de flecha
                      Icon(
                        Icons.chevron_right,
                        color: leida ? Colors.grey[300] : Colors.grey[400],
                        size: 24,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _mostrarDetalleNotificacion(BuildContext context, Map<String, dynamic> notif) async {
    final id = notif['id']?.toString() ?? '';
    final titulo = notif['titulo']?.toString() ?? 'Notificación';
    final mensaje = notif['mensaje']?.toString() ?? '';
    final fecha = notif['created_at']?.toString();
    final leida = notif['leida'] ?? false;

    // Mostrar modal con el contenido completo PRIMERO
    if (!mounted) return;
    
    await showDialog(
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
                          _formatearFecha(fecha),
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
                            // CRÍTICO: Abrir en navegador externo, no dentro de la app
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                            print('✅ URL abierta externamente: $url');
                          } catch (e) {
                            print('❌ Error abriendo URL: $e');
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error al abrir enlace: $e')),
                              );
                            }
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
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Error al descargar archivo: $e')),
                              );
                            }
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
                  onPressed: () => Navigator.of(context).pop(),
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

    // DESPUÉS de cerrar el modal, marcar como leída y recargar
    if (!mounted) return;
    
    if (!leida && id.isNotEmpty) {
      try {
        print('📖 Marcando notificación como leída: $id');
        final tablaNotificaciones = _esRecolector ? 'notificaciones_recolectores' : 'notificaciones_repartidores';
        
        await supabase
            .from(tablaNotificaciones)
            .update({'leida': true})
            .eq('id', id);
        
        print('✅ Notificación marcada como leída exitosamente');
        await RepartidorNotificacionesPushService.instance.marcarPushMostrado(id);
        
        // Recargar notificaciones para que la leída desaparezca de la lista
        if (mounted) {
          await _cargarNotificaciones();
        }
      } catch (e) {
        print('❌ Error marcando notificación como leída: $e');
      }
    }
  }

  // Mostrar detalle de notificación de pago
  Future<void> _mostrarDetalleNotificacionPago(BuildContext context, Map<String, dynamic> notif) async {
    final id = notif['id']?.toString() ?? '';
    final titulo = notif['titulo']?.toString() ?? 'Notificación de Pago';
    final mensaje = notif['mensaje']?.toString() ?? '';
    final fecha = notif['created_at']?.toString();
    final leida = notif['leida'] ?? false;
    final tipo = notif['tipo']?.toString() ?? '';

    // Determinar color según tipo
    Color colorEstado;
    if (tipo == 'PAGO_ACEPTADO') {
      colorEstado = const Color(0xFF4CAF50);
    } else if (tipo == 'PAGO_RECHAZADO' || tipo == 'PAGO_CANCELADO') {
      colorEstado = const Color(0xFFDC2626);
    } else {
      colorEstado = const Color(0xFF666666);
    }

    // Mostrar modal con el contenido completo PRIMERO
    if (!mounted) return;
    
    await showDialog(
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
                      color: colorEstado.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _obtenerIconoEstado(tipo == 'PAGO_ACEPTADO' ? 'ACEPTADO' : tipo == 'PAGO_RECHAZADO' ? 'RECHAZADO' : 'CANCELADA'),
                      color: colorEstado,
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
                          _formatearFecha(fecha),
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
              // Botón de cerrar
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorEstado,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Cerrar',
                    style: TextStyle(
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

    // DESPUÉS de cerrar el modal, marcar como leída y recargar
    if (!mounted) return;
    
    if (!leida && id.isNotEmpty) {
      try {
        print('📖 Marcando notificación de pago como leída: $id');
        final tablaNotificaciones = _esRecolector ? 'notificaciones_recolectores' : 'notificaciones_repartidores';
        
        await supabase
            .from(tablaNotificaciones)
            .update({'leida': true})
            .eq('id', id);
        
        print('✅ Notificación de pago marcada como leída exitosamente');
        await RepartidorNotificacionesPushService.instance.marcarPushMostrado(id);
        
        // Recargar notificaciones para actualizar el badge
        if (mounted) {
          await _cargarNotificaciones();
        }
      } catch (e) {
        print('❌ Error marcando notificación de pago como leída: $e');
      }
    }
  }
}

