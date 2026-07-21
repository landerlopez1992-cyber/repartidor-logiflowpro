import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../config/app_colors.dart';
import '../services/repartidor_chat_soporte_service.dart';
import '../services/repartidor_pantallas_offline_service.dart';
import '../services/sync_service.dart';
import '../services/network_timeout.dart';
import '../utils/mensaje_error_operacion.dart';
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
  final Map<String, bool> _nuevosMensajes = {};

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

  Future<void> _aplicarConversacionesLocales(String authId) async {
    var lista =
        await RepartidorPantallasOfflineService.cargarConversacionesChat(authId);

    if ((lista == null || lista.isEmpty) &&
        _conversacionId != null &&
        _conversacionId!.isNotEmpty) {
      lista = await RepartidorPantallasOfflineService
          .conversacionesDesdeMensajesCache(
        conversacionId: _conversacionId!,
        repartidorAuthId: authId,
      );
      if (lista.isNotEmpty) {
        await RepartidorPantallasOfflineService.guardarConversacionesChat(
          authId,
          lista,
        );
      }
    }

    if (lista != null && lista!.isNotEmpty && mounted) {
      setState(() {
        _conversaciones = List<Map<String, dynamic>>.from(lista!);
        _cargando = false;
      });
    }
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

    final meta = await RepartidorPantallasOfflineService.cargarMetaChat(user.id);
    if (meta != null) {
      _conversacionId = meta.conversacionId;
      _tenantId = meta.tenantId;
    }

    _tenantId ??=
        await RepartidorPantallasOfflineService.cargarTenantIdRepartidor(user.id);

    await _aplicarConversacionesLocales(user.id);

    if (_conversacionId != null && SyncService().isOnline) {
      _suscribirseAMensajes();
    }

    if (!SyncService().isOnline) {
      if (mounted) setState(() => _cargando = false);
      return;
    }

    try {
      _tenantId ??= await RepartidorPantallasOfflineService.cargarTenantIdRepartidor(
        user.id,
      );

      if (_tenantId == null) {
        final userData = await ejecutarConTimeout(
          supabase
              .from('usuarios')
              .select('tenant_id')
              .eq('auth_id', user.id)
              .maybeSingle(),
          timeout: const Duration(seconds: 8),
        );
        _tenantId = userData?['tenant_id']?.toString();
      }

      var query = supabase
          .from('conversaciones_soporte')
          .select('id')
          .eq('repartidor_auth_id', user.id)
          .eq('estado', 'ABIERTA');

      if (_tenantId != null && _tenantId!.isNotEmpty) {
        query = query.eq('tenant_id', _tenantId!);
      }

      final conversaciones = await ejecutarConTimeout(
        query.limit(1),
        timeout: const Duration(seconds: 10),
      );

      if (conversaciones != null && conversaciones.isNotEmpty) {
        _conversacionId = conversaciones[0]['id']?.toString();
        await RepartidorPantallasOfflineService.guardarMetaChat(
          user.id,
          conversacionId: _conversacionId,
          tenantId: _tenantId,
        );
        await _cargarConversaciones();
        if (_channelMensajes == null && SyncService().isOnline) {
          _suscribirseAMensajes();
        }
      } else if (mounted) {
        setState(() => _cargando = false);
      }
    } catch (e) {
      print('❌ Error cargando datos: $e');
      await _aplicarConversacionesLocales(user.id);
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarConversaciones() async {
    if (_conversacionId == null) {
      setState(() => _cargando = false);
      return;
    }

    final user = supabase.auth.currentUser;
    if (user != null) {
      await _aplicarConversacionesLocales(user.id);
    }

    if (!SyncService().isOnline) {
      if (mounted) setState(() => _cargando = false);
      return;
    }

    final conversacionesAnteriores = List<Map<String, dynamic>>.from(_conversaciones);
    final authId = user?.id;

    try {
      final mensajesRaw = await ejecutarConTimeout(
        supabase
            .from('mensajes_soporte')
            .select('*')
            .eq('conversacion_id', _conversacionId!)
            .order('created_at', ascending: false),
      );
      if (mensajesRaw == null) {
        if (mounted) setState(() => _cargando = false);
        return;
      }
      final mensajes = mensajesRaw as List;

      final Map<String, Map<String, dynamic>> conversacionesMap = {};
      final user = supabase.auth.currentUser;

      for (var mensaje in mensajes) {
        final remitenteId = mensaje['remitente_auth_id'];

        if (remitenteId == user?.id) continue;

        if (conversacionesMap.containsKey(remitenteId)) {
          final fechaActual =
              DateTime.parse(conversacionesMap[remitenteId]!['ultimo_mensaje_fecha']);
          final fechaNueva = DateTime.parse(mensaje['created_at']);
          if (fechaNueva.isAfter(fechaActual)) {
            conversacionesMap[remitenteId]!['ultimo_mensaje'] =
                RepartidorChatSoporteService.textoPreview(mensaje);
            conversacionesMap[remitenteId]!['ultimo_mensaje_fecha'] =
                mensaje['created_at'];
          }
          conversacionesMap[remitenteId]!['mensajes_no_leidos'] =
              _contarNoLeidosRemitente(mensajes, remitenteId);
        } else {
          Map<String, dynamic>? remitenteData =
              await RepartidorPantallasOfflineService.cargarRemitenteChat(
            remitenteId.toString(),
          );

          if (remitenteData == null && SyncService().isOnline) {
            try {
              final data = await ejecutarConTimeout(
                supabase
                    .from('usuarios')
                    .select('nombre, rol, foto_perfil, email')
                    .eq('auth_id', remitenteId)
                    .maybeSingle(),
                timeout: const Duration(seconds: 6),
              );
              if (data != null) {
                remitenteData = data;
                await RepartidorPantallasOfflineService.guardarRemitenteChat(
                  remitenteId.toString(),
                  nombre: data['nombre']?.toString() ?? 'Usuario',
                  rol: data['rol']?.toString() ?? 'EMPLEADO',
                  foto: data['foto_perfil']?.toString(),
                  email: data['email']?.toString(),
                );
              }
            } catch (e) {
              print('⚠️ Error obteniendo datos del remitente $remitenteId: $e');
            }
          }

          remitenteData ??= {
            'nombre': 'Soporte',
            'rol': 'EMPLEADO',
          };

          final preview = RepartidorChatSoporteService.textoPreview(mensaje);
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
      }

      final conversacionesList = conversacionesMap.values.toList();
      conversacionesList.sort((a, b) {
        final fechaA = DateTime.parse(a['ultimo_mensaje_fecha']);
        final fechaB = DateTime.parse(b['ultimo_mensaje_fecha']);
        return fechaB.compareTo(fechaA);
      });

      if (conversacionesList.isNotEmpty) {
        setState(() {
          _conversaciones = conversacionesList;
          _cargando = false;
        });
        if (user != null) {
          await RepartidorPantallasOfflineService.guardarMensajesChat(
            _conversacionId!,
            mensajes.map((e) => Map<String, dynamic>.from(e as Map)).toList(),
          );
          await RepartidorPantallasOfflineService.guardarConversacionesChat(
            user.id,
            conversacionesList,
          );
        }
      } else if (conversacionesAnteriores.isNotEmpty) {
        if (mounted) setState(() => _cargando = false);
      } else {
        // Hilo iniciado por el repartidor (aún sin respuesta de la empresa).
        final List<Map<String, dynamic>> sintetico = [];
        if (_conversacionId != null && user != null) {
          String preview = 'Toca para escribir a tu empresa';
          String fecha = DateTime.now().toIso8601String();
          for (final raw in mensajes) {
            if (raw is! Map) continue;
            final m = Map<String, dynamic>.from(raw);
            if (m['remitente_auth_id'] != user.id) continue;
            final p = RepartidorChatSoporteService.textoPreview(m);
            if (p.isEmpty) continue;
            preview = p;
            fecha = m['created_at']?.toString() ?? fecha;
            break; // mensajes vienen desc: el primero del user es el más reciente
          }
          sintetico.add({
            'remitente_auth_id': '',
            'remitente_nombre': 'Mi empresa',
            'remitente_rol': 'ADMINISTRADOR',
            'remitente_foto': null,
            'ultimo_mensaje': preview,
            'ultimo_mensaje_fecha': fecha,
            'mensajes_no_leidos': 0,
            'conversacion_id': _conversacionId,
            'modo_completo': true,
          });
        }
        setState(() {
          _conversaciones = sintetico;
          _cargando = false;
        });
        if (sintetico.isNotEmpty && user != null) {
          await RepartidorPantallasOfflineService.guardarConversacionesChat(
            user.id,
            sintetico,
          );
        }
      }
    } catch (e) {
      print('❌ Error cargando conversaciones: $e');
      if (conversacionesAnteriores.isNotEmpty && mounted) {
        setState(() {
          _conversaciones = conversacionesAnteriores;
          _cargando = false;
        });
      } else if (authId != null) {
        await _aplicarConversacionesLocales(authId);
        if (mounted) setState(() => _cargando = false);
      } else if (mounted) {
        setState(() => _cargando = false);
      }
    }
  }

  void _suscribirseAMensajes() {
    if (_conversacionId == null || !SyncService().isOnline) return;

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
            if (SyncService().isOnline) {
              _cargarConversaciones();
            }
          },
        )
        .subscribe((status, error) {
      print('📡 Estado de suscripción lista conversaciones: $status');
      if (error != null && SyncService().isOnline) {
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
      Map<String, dynamic>? remitenteData;
      final conversacionExistente = _conversaciones.firstWhere(
        (c) => c['remitente_auth_id'] == remitenteId,
        orElse: () => {},
      );

      if (conversacionExistente.isEmpty) {
        remitenteData =
            await RepartidorPantallasOfflineService.cargarRemitenteChat(remitenteId);
        if (remitenteData == null && SyncService().isOnline) {
          try {
            final data = await ejecutarConTimeout(
              supabase
                  .from('usuarios')
                  .select('nombre, rol, foto_perfil, email')
                  .eq('auth_id', remitenteId)
                  .maybeSingle(),
              timeout: const Duration(seconds: 6),
            );

            if (data != null) {
              remitenteData = {
                'remitente_auth_id': remitenteId,
                'remitente_nombre': data['nombre'] ?? 'Usuario',
                'remitente_rol': data['rol'] ?? 'EMPLEADO',
                'remitente_foto': data['foto_perfil'],
                'remitente_email': data['email'],
              };
              await RepartidorPantallasOfflineService.guardarRemitenteChat(
                remitenteId,
                nombre: data['nombre']?.toString() ?? 'Usuario',
                rol: data['rol']?.toString() ?? 'EMPLEADO',
                foto: data['foto_perfil']?.toString(),
                email: data['email']?.toString(),
              );
            }
          } catch (e) {
            print('⚠️ Error obteniendo datos del remitente: $e');
          }
        } else if (remitenteData != null) {
          remitenteData = {
            'remitente_auth_id': remitenteId,
            'remitente_nombre': remitenteData['nombre'] ?? 'Usuario',
            'remitente_rol': remitenteData['rol'] ?? 'EMPLEADO',
            'remitente_foto': remitenteData['foto_perfil'],
            'remitente_email': remitenteData['email'],
          };
        }
      }

      setState(() {
        final index = _conversaciones.indexWhere(
          (c) => c['remitente_auth_id'] == remitenteId,
        );

        if (index != -1) {
          _conversaciones[index]['ultimo_mensaje'] =
              RepartidorChatSoporteService.textoPreview(nuevoMensaje);
          _conversaciones[index]['ultimo_mensaje_fecha'] =
              nuevoMensaje['created_at'];
          _conversaciones[index]['mensajes_no_leidos'] =
              (_conversaciones[index]['mensajes_no_leidos'] as int? ?? 0) + 1;
        } else if (remitenteData != null) {
          _conversaciones.insert(0, {
            ...remitenteData,
            'ultimo_mensaje':
                RepartidorChatSoporteService.textoPreview(nuevoMensaje),
            'ultimo_mensaje_fecha': nuevoMensaje['created_at'],
            'mensajes_no_leidos': 1,
            'conversacion_id': _conversacionId,
          });
        }

        _conversaciones.sort((a, b) {
          final fechaA = DateTime.parse(a['ultimo_mensaje_fecha']);
          final fechaB = DateTime.parse(b['ultimo_mensaje_fecha']);
          return fechaB.compareTo(fechaA);
        });
      });

      final user = supabase.auth.currentUser;
      if (user != null) {
        await RepartidorPantallasOfflineService.guardarConversacionesChat(
          user.id,
          _conversaciones,
        );
      }
    } catch (e) {
      print('❌ Error actualizando conversación: $e');
      if (SyncService().isOnline) {
        _cargarConversaciones();
      }
    }
  }

  void _mostrarNotificacionNuevoMensaje(String remitenteId) {
    final conversacion = _conversaciones.firstWhere(
      (c) => c['remitente_auth_id'] == remitenteId,
      orElse: () => {'remitente_nombre': 'Alguien', 'remitente_rol': 'EMPLEADO'},
    );

    final nombreRemitente = conversacion['remitente_rol'] == 'ADMINISTRADOR'
        ? 'Administrador'
        : conversacion['remitente_nombre'] ?? 'Alguien';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
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

  Future<void> _iniciarChatConEmpresa() async {
    if (!SyncService().isOnline) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Necesitas conexión a internet para iniciar una conversación con tu empresa.',
          ),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    final user = supabase.auth.currentUser;
    if (user == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF9800)),
      ),
    );

    try {
      final convId =
          await RepartidorChatSoporteService.obtenerOCrearConversacionEmpresa();
      _conversacionId = convId;
      _tenantId ??=
          await RepartidorPantallasOfflineService.cargarTenantIdRepartidor(
        user.id,
      );
      await RepartidorPantallasOfflineService.guardarMetaChat(
        user.id,
        conversacionId: convId,
        tenantId: _tenantId,
      );
      if (_channelMensajes == null) {
        _suscribirseAMensajes();
      }

      if (!mounted) return;
      Navigator.of(context).pop(); // loading

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatSoporteFiltradoScreen(
            conversacionId: convId,
            remitenteAuthId: '',
            nombreRemitente: 'Mi empresa',
            rolRemitente: 'ADMINISTRADOR',
            modoConversacionCompleta: true,
          ),
        ),
      );
      if (mounted) {
        await _cargarDatos();
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No se pudo iniciar el chat: ${mensajeErrorOperacion(e)}',
            ),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
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
        actions: [
          IconButton(
            tooltip: 'Escribir a mi empresa',
            onPressed: _cargando ? null : _iniciarChatConEmpresa,
            icon: const Icon(Icons.edit, color: Colors.white),
          ),
        ],
      ),
      floatingActionButton: _cargando
          ? null
          : FloatingActionButton.extended(
              onPressed: _iniciarChatConEmpresa,
              backgroundColor: const Color(0xFFFF9800),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.chat),
              label: const Text('Escribir a mi empresa'),
            ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : _conversaciones.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 80,
                          color: AppColors.darkTextMuted.withOpacity(0.3),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Sin mensajes aún',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.darkText,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          SyncService().isOnline
                              ? 'Si tienes una duda, escribe a tu empresa.\nUn agente te responderá por aquí.'
                              : 'Sin conexión: abre el chat con internet al menos una vez\npara guardar conversaciones en el teléfono.',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.darkTextMuted,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        if (SyncService().isOnline) ...[
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _iniciarChatConEmpresa,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF9800),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                            ),
                            icon: const Icon(Icons.support_agent),
                            label: const Text('Escribir a mi empresa'),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargarConversaciones,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                    itemCount: _conversaciones.length +
                        (SyncService().isOnline ? 0 : 1),
                    itemBuilder: (context, index) {
                      if (!SyncService().isOnline && index == 0) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFF9800)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.wifi_off, color: Color(0xFFFF9800), size: 20),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Modo sin conexión: conversaciones y mensajes guardados en el dispositivo. Los envíos nuevos se sincronizan al reconectar.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.darkText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                      final convIndex =
                          SyncService().isOnline ? index : index - 1;
                      final conversacion = _conversaciones[convIndex];
                      final esAdmin = conversacion['remitente_rol'] == 'ADMINISTRADOR';
                      final mensajesNoLeidos =
                          conversacion['mensajes_no_leidos'] as int? ?? 0;
                      final modoCompleto =
                          conversacion['modo_completo'] == true;

                      final tieneNuevoMensaje =
                          _nuevosMensajes[conversacion['remitente_auth_id']] == true;

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
                        color: AppColors.darkSurface,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          onTap: () async {
                            _nuevosMensajes.remove(conversacion['remitente_auth_id']);
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatSoporteFiltradoScreen(
                                  conversacionId: conversacion['conversacion_id'],
                                  remitenteAuthId:
                                      conversacion['remitente_auth_id'] ?? '',
                                  nombreRemitente:
                                      conversacion['remitente_nombre'] ??
                                          'Mi empresa',
                                  rolRemitente:
                                      conversacion['remitente_rol'] ??
                                          'ADMINISTRADOR',
                                  fotoRemitente: conversacion['remitente_foto'],
                                  modoConversacionCompleta: modoCompleto,
                                ),
                              ),
                            );
                            if (mounted) await _cargarConversaciones();
                          },
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFFFF9800),
                            backgroundImage: !modoCompleto &&
                                    conversacion['remitente_foto'] != null &&
                                    conversacion['remitente_foto']
                                        .toString()
                                        .isNotEmpty
                                ? NetworkImage(conversacion['remitente_foto'])
                                : null,
                            child: modoCompleto ||
                                    conversacion['remitente_foto'] == null ||
                                    conversacion['remitente_foto']
                                        .toString()
                                        .isEmpty
                                ? Icon(
                                    modoCompleto
                                        ? Icons.business
                                        : (esAdmin
                                            ? Icons.admin_panel_settings
                                            : Icons.person),
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                          title: Text(
                            modoCompleto
                                ? 'Mi empresa'
                                : (esAdmin
                                    ? 'Administración'
                                    : conversacion['remitente_nombre']),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AppColors.darkText,
                            ),
                          ),
                          subtitle: Text(
                            conversacion['ultimo_mensaje']?.toString() ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.darkTextMuted,
                              fontSize: 13,
                            ),
                          ),
                          trailing: mensajesNoLeidos > 0
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDC2626),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '$mensajesNoLeidos',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              : const Icon(
                                  Icons.chevron_right,
                                  color: AppColors.darkTextMuted,
                                ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
