import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../config/app_colors.dart';
import '../services/repartidor_chat_soporte_service.dart';
import 'chat_soporte_filtrado_screen.dart';

class ChatRepartidorListaScreen extends StatefulWidget {
  const ChatRepartidorListaScreen({super.key});

  @override
  State<ChatRepartidorListaScreen> createState() => _ChatRepartidorListaScreenState();
}

class _ChatRepartidorListaScreenState extends State<ChatRepartidorListaScreen> {
  List<Map<String, dynamic>> _conversaciones = [];
  bool _cargando = true;
  String? _conversacionId;
  String? _tenantId;
  RealtimeChannel? _channelMensajes;
  Map<String, bool> _nuevosMensajes = {}; // Trackear conversaciones con nuevos mensajes

  bool _esMensajeNoLeidoConContenido(
    Map<String, dynamic> m,
    String remitenteId,
  ) {
    if (m['remitente_auth_id'] != remitenteId) return false;
    final leidoValue = m['leido'];
    if (leidoValue == true) return false;
    if (leidoValue is String && leidoValue.toLowerCase() == 'true') {
      return false;
    }
    if (leidoValue is int && leidoValue == 1) return false;
    return RepartidorChatSoporteService.tieneContenidoVisible(m);
  }

  int _contarNoLeidosRemitente(
    List<dynamic> mensajes,
    String remitenteId,
  ) {
    var n = 0;
    for (final raw in mensajes) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      if (_esMensajeNoLeidoConContenido(m, remitenteId)) n++;
    }
    return n;
  }

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _channelMensajes?.unsubscribe();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      setState(() => _cargando = false);
      return;
    }

    try {
      // Obtener tenant_id del repartidor
      final userData = await supabase
          .from('usuarios')
          .select('tenant_id')
          .eq('auth_id', user.id)
          .single();
      
      _tenantId = userData['tenant_id'];
      
      // Buscar conversación del repartidor
      var query = supabase
          .from('conversaciones_soporte')
          .select('id')
          .eq('repartidor_auth_id', user.id)
          .eq('estado', 'ABIERTA');
      
      if (_tenantId != null) {
        query = query.eq('tenant_id', _tenantId!);
      }
      
      final conversaciones = await query.limit(1);
      
      if (conversaciones.isNotEmpty) {
        _conversacionId = conversaciones[0]['id'];
        await _cargarConversaciones();
        _suscribirseAMensajes();
      } else {
        setState(() => _cargando = false);
      }
    } catch (e) {
      print('❌ Error cargando datos: $e');
      setState(() => _cargando = false);
    }
  }

  Future<void> _cargarConversaciones() async {
    if (_conversacionId == null) {
      setState(() => _cargando = false);
      return;
    }

    try {
      // Obtener todos los mensajes de la conversación
      final mensajes = await supabase
          .from('mensajes_soporte')
          .select('*')
          .eq('conversacion_id', _conversacionId!)
          .order('created_at', ascending: false);

      // Agrupar mensajes por remitente (admin o empleado)
      final Map<String, Map<String, dynamic>> conversacionesMap = {};
      final user = supabase.auth.currentUser;

      for (var mensaje in mensajes) {
        final remitenteId = mensaje['remitente_auth_id'];
        
        // Saltar mensajes del propio repartidor
        if (remitenteId == user?.id) continue;

        // Si ya tenemos esta conversación, actualizar último mensaje si es más reciente
        if (conversacionesMap.containsKey(remitenteId)) {
          final fechaActual = DateTime.parse(conversacionesMap[remitenteId]!['ultimo_mensaje_fecha']);
          final fechaNueva = DateTime.parse(mensaje['created_at']);
          if (fechaNueva.isAfter(fechaActual)) {
            conversacionesMap[remitenteId]!['ultimo_mensaje'] =
                RepartidorChatSoporteService.textoPreview(mensaje);
            conversacionesMap[remitenteId]!['ultimo_mensaje_fecha'] = mensaje['created_at'];
          }
          conversacionesMap[remitenteId]!['mensajes_no_leidos'] =
              _contarNoLeidosRemitente(mensajes, remitenteId);
        } else {
          // Obtener información del remitente
          try {
            final remitenteData = await supabase
                .from('usuarios')
                .select('nombre, rol, foto_perfil, email')
                .eq('auth_id', remitenteId)
                .maybeSingle();

            if (remitenteData != null) {
              final preview =
                  RepartidorChatSoporteService.textoPreview(mensaje);
              if (preview.isEmpty) continue;

              conversacionesMap[remitenteId] = {
                'remitente_auth_id': remitenteId,
                'remitente_nombre': remitenteData['nombre'] ?? 'Usuario',
                'remitente_rol': remitenteData['rol'] ?? 'EMPLEADO',
                'remitente_foto': remitenteData['foto_perfil'],
                'remitente_email': remitenteData['email'],
                'ultimo_mensaje': preview,
                'ultimo_mensaje_fecha': mensaje['created_at'],
                'mensajes_no_leidos':
                    _contarNoLeidosRemitente(mensajes, remitenteId),
                'conversacion_id': _conversacionId,
              };
            }
          } catch (e) {
            print('⚠️ Error obteniendo datos del remitente $remitenteId: $e');
          }
        }
      }

      // Convertir a lista y ordenar por fecha
      final conversacionesList = conversacionesMap.values.toList();
      conversacionesList.sort((a, b) {
        final fechaA = DateTime.parse(a['ultimo_mensaje_fecha']);
        final fechaB = DateTime.parse(b['ultimo_mensaje_fecha']);
        return fechaB.compareTo(fechaA);
      });

      setState(() {
        _conversaciones = conversacionesList;
        _cargando = false;
      });
    } catch (e) {
      print('❌ Error cargando conversaciones: $e');
      setState(() => _cargando = false);
    }
  }

  void _suscribirseAMensajes() {
    if (_conversacionId == null) return;

    print('🔔 Suscribiéndose a mensajes en tiempo real para lista de conversaciones...');
    
    _channelMensajes = supabase
        .channel('mensajes_lista_conversaciones_$_conversacionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'mensajes_soporte',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversacion_id',
            value: _conversacionId,
          ),
          callback: (payload) async {
            print('🔔 Nuevo mensaje recibido en lista de conversaciones!');
            final nuevoMensaje = payload.newRecord;
            final user = supabase.auth.currentUser;
            
            // Solo procesar si el mensaje NO es del repartidor
            if (nuevoMensaje['remitente_auth_id'] != user?.id) {
              final record = Map<String, dynamic>.from(nuevoMensaje);
              if (!RepartidorChatSoporteService.tieneContenidoVisible(record)) {
                return;
              }
              final remitenteId = nuevoMensaje['remitente_auth_id'];
              
              setState(() {
                _nuevosMensajes[remitenteId] = true;
              });
              
              await _actualizarConversacionConNuevoMensaje(remitenteId, record);
              _mostrarNotificacionNuevoMensaje(remitenteId);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'mensajes_soporte',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversacion_id',
            value: _conversacionId,
          ),
          callback: (payload) {
            // Si se marca como leído, actualizar contador
            _cargarConversaciones();
          },
        )
        .subscribe((status, error) {
      print('📡 Estado de suscripción lista conversaciones: $status');
      if (error != null) {
        print('❌ Error en suscripción: $error');
      }
      if (status == RealtimeSubscribeStatus.subscribed) {
        print('✅ Suscripción CONFIRMADA para lista de conversaciones');
      }
    });
  }

  Future<void> _actualizarConversacionConNuevoMensaje(
    String remitenteId,
    Map<String, dynamic> nuevoMensaje,
  ) async {
    try {
      // Obtener información del remitente si no la tenemos
      Map<String, dynamic>? remitenteData;
      final conversacionExistente = _conversaciones.firstWhere(
        (c) => c['remitente_auth_id'] == remitenteId,
        orElse: () => {},
      );

      if (conversacionExistente.isEmpty) {
        // Es un nuevo remitente, obtener sus datos
        try {
          final data = await supabase
              .from('usuarios')
              .select('nombre, rol, foto_perfil, email')
              .eq('auth_id', remitenteId)
              .maybeSingle();
          
          if (data != null) {
            remitenteData = {
              'remitente_auth_id': remitenteId,
              'remitente_nombre': data['nombre'] ?? 'Usuario',
              'remitente_rol': data['rol'] ?? 'EMPLEADO',
              'remitente_foto': data['foto_perfil'],
              'remitente_email': data['email'],
            };
          }
        } catch (e) {
          print('⚠️ Error obteniendo datos del remitente: $e');
        }
      }

      setState(() {
        // Buscar si ya existe la conversación
        final index = _conversaciones.indexWhere(
          (c) => c['remitente_auth_id'] == remitenteId,
        );

        if (index != -1) {
          // Actualizar conversación existente
          _conversaciones[index]['ultimo_mensaje'] =
              RepartidorChatSoporteService.textoPreview(nuevoMensaje);
          _conversaciones[index]['ultimo_mensaje_fecha'] = nuevoMensaje['created_at'];
          _conversaciones[index]['mensajes_no_leidos'] = 
              (_conversaciones[index]['mensajes_no_leidos'] as int? ?? 0) + 1;
        } else if (remitenteData != null) {
          // Agregar nueva conversación
          _conversaciones.insert(0, {
            ...remitenteData,
            'ultimo_mensaje':
                RepartidorChatSoporteService.textoPreview(nuevoMensaje),
            'ultimo_mensaje_fecha': nuevoMensaje['created_at'],
            'mensajes_no_leidos': 1,
            'conversacion_id': _conversacionId,
          });
        }

        // Reordenar por fecha (más reciente primero)
        _conversaciones.sort((a, b) {
          final fechaA = DateTime.parse(a['ultimo_mensaje_fecha']);
          final fechaB = DateTime.parse(b['ultimo_mensaje_fecha']);
          return fechaB.compareTo(fechaA);
        });
      });
    } catch (e) {
      print('❌ Error actualizando conversación: $e');
      // Recargar todas las conversaciones como fallback
      _cargarConversaciones();
    }
  }

  void _mostrarNotificacionNuevoMensaje(String remitenteId) {
    // Buscar el nombre del remitente
    final conversacion = _conversaciones.firstWhere(
      (c) => c['remitente_auth_id'] == remitenteId,
      orElse: () => {'remitente_nombre': 'Alguien', 'remitente_rol': 'EMPLEADO'},
    );
    
    final nombreRemitente = conversacion['remitente_rol'] == 'ADMINISTRADOR'
        ? 'Administrador'
        : conversacion['remitente_nombre'] ?? 'Alguien';
    
    // Mostrar snackbar con notificación
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              Icons.chat_bubble,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Nuevo mensaje de $nombreRemitente',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fondoGeneral,
      appBar: AppBar(
        backgroundColor: AppColors.header,
        title: const Text(
          'Chat de Soporte',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _conversaciones.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 80,
                        color: AppColors.textoSecundario.withOpacity(0.3),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No hay conversaciones',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textoPrincipal,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Cuando recibas mensajes de soporte,\naparecerán aquí',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textoSecundario,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargarConversaciones,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _conversaciones.length,
                    itemBuilder: (context, index) {
                      final conversacion = _conversaciones[index];
                      final esAdmin = conversacion['remitente_rol'] == 'ADMINISTRADOR';
                      final esEmpleado = conversacion['remitente_rol'] == 'EMPLEADO';
                      final mensajesNoLeidos = conversacion['mensajes_no_leidos'] as int? ?? 0;
                      
                      final tieneNuevoMensaje = _nuevosMensajes[conversacion['remitente_auth_id']] == true;
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: tieneNuevoMensaje ? 4 : 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: tieneNuevoMensaje
                              ? BorderSide(
                                  color: AppColors.primary.withOpacity(0.3),
                                  width: 2,
                                )
                              : BorderSide.none,
                        ),
                        color: tieneNuevoMensaje
                            ? AppColors.primary.withOpacity(0.05)
                            : Colors.white,
                        child: InkWell(
                          onTap: () {
                            // Limpiar indicador de nuevo mensaje
                            setState(() {
                              _nuevosMensajes.remove(conversacion['remitente_auth_id']);
                            });
                            
                            // Navegar a la pantalla de chat con filtro por remitente
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ChatSoporteFiltradoScreen(
                                  conversacionId: conversacion['conversacion_id'],
                                  remitenteAuthId: conversacion['remitente_auth_id'],
                                  nombreRemitente: conversacion['remitente_nombre'],
                                  rolRemitente: conversacion['remitente_rol'],
                                  fotoRemitente: conversacion['remitente_foto'],
                                ),
                              ),
                            ).then((_) {
                              // Recargar conversaciones al volver para actualizar contadores
                              _cargarConversaciones();
                            });
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                // Avatar
                                Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    CircleAvatar(
                                      radius: 28,
                                      backgroundColor: esAdmin
                                          ? const Color(0xFF4CAF50)
                                          : esEmpleado
                                              ? const Color(0xFFFF9800)
                                              : AppColors.primary,
                                      backgroundImage: conversacion['remitente_foto'] != null &&
                                              conversacion['remitente_foto'].toString().isNotEmpty
                                          ? NetworkImage(conversacion['remitente_foto'])
                                          : null,
                                      child: conversacion['remitente_foto'] == null ||
                                              conversacion['remitente_foto'].toString().isEmpty
                                          ? Icon(
                                              esAdmin
                                                  ? Icons.admin_panel_settings
                                                  : Icons.person,
                                              size: 28,
                                              color: Colors.white,
                                            )
                                          : null,
                                    ),
                                    if (esAdmin)
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF4CAF50),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.verified,
                                            size: 12,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    // Indicador de nuevo mensaje (punto naranja)
                                    if (_nuevosMensajes[conversacion['remitente_auth_id']] == true)
                                      Positioned(
                                        right: -2,
                                        top: -2,
                                        child: Container(
                                          width: 16,
                                          height: 16,
                                          decoration: BoxDecoration(
                                            color: AppColors.primary,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2.5,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppColors.primary.withOpacity(0.5),
                                                blurRadius: 4,
                                                spreadRadius: 1,
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.circle,
                                            size: 8,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(width: 16),
                                // Información
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              esAdmin
                                                  ? 'Administrador'
                                                  : conversacion['remitente_nombre'],
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: esAdmin
                                                    ? const Color(0xFF4CAF50)
                                                    : esEmpleado
                                                        ? const Color(0xFFFF9800)
                                                        : AppColors.textoPrincipal,
                                              ),
                                            ),
                                          ),
                                          if (mensajesNoLeidos > 0)
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                mensajesNoLeidos > 99 ? '99+' : '$mensajesNoLeidos',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        () {
                                          final t = conversacion['ultimo_mensaje']
                                              ?.toString()
                                              .trim();
                                          if (t != null && t.isNotEmpty) {
                                            return t;
                                          }
                                          return 'Sin mensajes';
                                        }(),
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: AppColors.textoSecundario,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatearFecha(DateTime.parse(
                                            conversacion['ultimo_mensaje_fecha'])),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textoSecundario,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  color: AppColors.textoSecundario,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  String _formatearFecha(DateTime fecha) {
    final ahora = DateTime.now();
    final diferencia = ahora.difference(fecha);

    if (diferencia.inDays == 0) {
      final hora = fecha.hour.toString().padLeft(2, '0');
      final minuto = fecha.minute.toString().padLeft(2, '0');
      return 'Hoy $hora:$minuto';
    } else if (diferencia.inDays == 1) {
      return 'Ayer';
    } else if (diferencia.inDays < 7) {
      return '${diferencia.inDays} días';
    } else {
      return '${fecha.day}/${fecha.month}/${fecha.year}';
    }
  }
}

