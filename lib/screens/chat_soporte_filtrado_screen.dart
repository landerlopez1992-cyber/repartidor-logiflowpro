import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../main.dart';
import '../config/app_colors.dart';
import '../services/repartidor_pantallas_offline_service.dart';
import '../services/sync_service.dart';
import '../services/network_timeout.dart';
import '../services/repartidor_chat_mensaje_sonido_service.dart';
import '../utils/entrega_foto_util.dart';

/// Pantalla de chat filtrado que muestra solo mensajes de un remitente específico
class ChatSoporteFiltradoScreen extends StatefulWidget {
  final String conversacionId;
  final String remitenteAuthId;
  final String nombreRemitente;
  final String rolRemitente;
  final String? fotoRemitente;

  const ChatSoporteFiltradoScreen({
    super.key,
    required this.conversacionId,
    required this.remitenteAuthId,
    required this.nombreRemitente,
    required this.rolRemitente,
    this.fotoRemitente,
  });

  @override
  State<ChatSoporteFiltradoScreen> createState() => _ChatSoporteFiltradoScreenState();
}

class _ChatSoporteFiltradoScreenState extends State<ChatSoporteFiltradoScreen> {
  final TextEditingController _mensajeController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  List<Map<String, dynamic>> _mensajes = [];
  bool _cargando = true;
  String _nombreRepartidor = '';
  RealtimeChannel? _channel;
  XFile? _fotoSeleccionada; // Foto seleccionada pero no enviada aún
  bool _enviandoFoto = false; // Flag para evitar envíos dobles
  bool _enviandoMensaje = false; // Evita doble envío (botón + Enter)

  @override
  void initState() {
    super.initState();
    RepartidorChatMensajeSonidoService.conversacionActivaId =
        widget.conversacionId;
    _inicializarChat();
  }

  @override
  void dispose() {
    if (RepartidorChatMensajeSonidoService.conversacionActivaId ==
        widget.conversacionId) {
      RepartidorChatMensajeSonidoService.conversacionActivaId = null;
    }
    _mensajeController.dispose();
    _scrollController.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _inicializarChat() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _cargando = false);
      return;
    }

    _nombreRepartidor =
        await RepartidorPantallasOfflineService.cargarNombreRepartidor(user.id) ??
            'Repartidor';

    await RepartidorPantallasOfflineService.upsertConversacionEnCache(
      user.id,
      conversacionId: widget.conversacionId,
      remitenteAuthId: widget.remitenteAuthId,
      remitenteNombre: widget.nombreRemitente,
      remitenteRol: widget.rolRemitente,
      remitenteFoto: widget.fotoRemitente,
    );

    await _fusionarMensajesLocales();

    if (mounted) {
      setState(() => _cargando = false);
      Future.delayed(const Duration(milliseconds: 300), _scrollToBottom);
    }

    if (!SyncService().isOnline) return;

    try {
      final userData = await ejecutarConTimeout(
        supabase
            .from('usuarios')
            .select('nombre')
            .eq('auth_id', user.id)
            .maybeSingle(),
        timeout: const Duration(seconds: 8),
      );
      if (userData != null) {
        final nombre = userData['nombre']?.toString();
        if (nombre != null && nombre.isNotEmpty) {
          _nombreRepartidor = nombre;
          if (mounted) setState(() {});
        }
      }

      await _cargarMensajes();
      _suscribirseAMensajes();
    } catch (e) {
      print('❌ Error al inicializar chat (red): $e');
      await _fusionarMensajesLocales();
    }
  }

  String? _claveMensaje(Map<String, dynamic> m) {
    final id = m['id']?.toString();
    if (id != null && id.isNotEmpty) return 'id:$id';
    final localId = m['local_id']?.toString();
    if (localId != null && localId.isNotEmpty) return 'local:$localId';
    return null;
  }

  bool _listaYaTieneMensaje(Map<String, dynamic> m) {
    final clave = _claveMensaje(m);
    if (clave != null) {
      return _mensajes.any((x) => _claveMensaje(x) == clave);
    }
    final rem = m['remitente_auth_id']?.toString() ?? '';
    final foto = m['foto_url']?.toString() ?? '';
    final texto = m['mensaje']?.toString() ?? '';
    final created = m['created_at']?.toString() ?? '';
    if (rem.isEmpty) return false;
    return _mensajes.any((x) {
      if (x['remitente_auth_id']?.toString() != rem) return false;
      if ((x['foto_url']?.toString() ?? '') != foto) return false;
      if ((x['mensaje']?.toString() ?? '') != texto) return false;
      if (created.isNotEmpty &&
          (x['created_at']?.toString() ?? '') == created) {
        return true;
      }
      return foto.isNotEmpty &&
          texto.isNotEmpty &&
          (x['mensaje']?.toString() ?? '') == texto &&
          (x['foto_url']?.toString() ?? '') == foto;
    });
  }

  Map<String, dynamic> _enriquecerMensaje(Map<String, dynamic> mensaje) {
    final user = supabase.auth.currentUser;
    final copia = Map<String, dynamic>.from(mensaje);
    if (mensaje['remitente_auth_id'] == user?.id) {
      copia['remitente_nombre'] = _nombreRepartidor;
      copia['remitente_rol'] = 'REPARTIDOR';
    } else {
      copia['remitente_nombre'] = widget.nombreRemitente;
      copia['remitente_rol'] = widget.rolRemitente;
      copia['remitente_foto'] = widget.fotoRemitente;
    }
    return copia;
  }

  void _agregarMensajeSiNoExiste(Map<String, dynamic> mensaje) {
    if (!mounted || _listaYaTieneMensaje(mensaje)) return;
    setState(() {
      _mensajes = [..._mensajes, _enriquecerMensaje(mensaje)];
    });
  }

  Future<void> _fusionarMensajesLocales() async {
    final user = supabase.auth.currentUser;
    var lista = <Map<String, dynamic>>[];

    final cached =
        await RepartidorPantallasOfflineService.cargarMensajesChat(widget.conversacionId);
    if (cached != null) {
      lista = List<Map<String, dynamic>>.from(cached);
    }

    if (user != null) {
      final pendientes =
          await RepartidorPantallasOfflineService.mensajesPendientesParaConversacion(
        conversacionId: widget.conversacionId,
        repartidorAuthId: user.id,
        nombreRepartidor: _nombreRepartidor,
      );
      for (final p in pendientes) {
        if (!_listaYaTieneMensaje(p)) {
          lista.add(_enriquecerMensaje(p));
        }
      }
    }

    lista.sort((a, b) {
      final fa = DateTime.tryParse(a['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final fb = DateTime.tryParse(b['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return fa.compareTo(fb);
    });

    if (mounted) {
      setState(() => _mensajes = lista);
    }
  }

  Future<void> _persistirMensajesEnCache() async {
    await RepartidorPantallasOfflineService.guardarMensajesChat(
      widget.conversacionId,
      _mensajes,
    );
    final user = supabase.auth.currentUser;
    if (user == null || _mensajes.isEmpty) return;

    Map<String, dynamic>? ultimo;
    for (var i = _mensajes.length - 1; i >= 0; i--) {
      final m = _mensajes[i];
      final texto = m['mensaje']?.toString().trim() ?? '';
      final foto = m['foto_url']?.toString().trim() ?? '';
      if (texto.isNotEmpty || foto.isNotEmpty) {
        ultimo = m;
        break;
      }
    }
    if (ultimo == null) return;

    final textoUltimo = ultimo['mensaje']?.toString().trim() ?? '';
    final preview = textoUltimo.isNotEmpty ? textoUltimo : '📷 Foto';

    await RepartidorPantallasOfflineService.upsertConversacionEnCache(
      user.id,
      conversacionId: widget.conversacionId,
      remitenteAuthId: widget.remitenteAuthId,
      remitenteNombre: widget.nombreRemitente,
      remitenteRol: widget.rolRemitente,
      remitenteFoto: widget.fotoRemitente,
      ultimoMensaje: preview,
      ultimoMensajeFecha: ultimo['created_at']?.toString(),
    );
  }

  Future<void> _cargarMensajes() async {
    await _fusionarMensajesLocales();

    if (!SyncService().isOnline) {
      if (mounted) setState(() => _cargando = false);
      return;
    }

    try {
      final todosMensajesRaw = await ejecutarConTimeout(
        supabase
            .from('mensajes_soporte')
            .select('*')
            .eq('conversacion_id', widget.conversacionId)
            .order('created_at', ascending: true),
      );
      if (todosMensajesRaw == null) return;
      final todosMensajes = todosMensajesRaw as List;

      final user = supabase.auth.currentUser;
      
      // Filtrar solo mensajes del remitente seleccionado o del repartidor
      final mensajesFiltrados = todosMensajes.where((mensaje) {
        final remitenteId = mensaje['remitente_auth_id'];
        return remitenteId == widget.remitenteAuthId || remitenteId == user?.id;
      }).toList();

      // Enriquecer mensajes con información del remitente
      final mensajesEnriquecidos = <Map<String, dynamic>>[];
      
      for (var mensaje in mensajesFiltrados) {
        final mensajeEnriquecido = Map<String, dynamic>.from(mensaje);
        
        if (mensaje['remitente_auth_id'] == user?.id) {
          mensajeEnriquecido['remitente_nombre'] = _nombreRepartidor;
          mensajeEnriquecido['remitente_rol'] = 'REPARTIDOR';
        } else {
          mensajeEnriquecido['remitente_nombre'] = widget.nombreRemitente;
          mensajeEnriquecido['remitente_rol'] = widget.rolRemitente;
          mensajeEnriquecido['remitente_foto'] = widget.fotoRemitente;
        }
        
        mensajesEnriquecidos.add(mensajeEnriquecido);
      }

      setState(() {
        _mensajes = mensajesEnriquecidos;
      });

      if (user != null) {
        final pendientes =
            await RepartidorPantallasOfflineService.mensajesPendientesParaConversacion(
          conversacionId: widget.conversacionId,
          repartidorAuthId: user.id,
          nombreRepartidor: _nombreRepartidor,
        );
        for (final p in pendientes) {
          _agregarMensajeSiNoExiste(_enriquecerMensaje(p));
        }
      }

      await _persistirMensajesEnCache();
      await _marcarComoLeidos();
    } catch (e) {
      print('❌ Error al cargar mensajes: $e');
      await _fusionarMensajesLocales();
    }
  }

  void _suscribirseAMensajes() {
    if (!SyncService().isOnline) return;

    _channel = supabase
        .channel('mensajes_soporte_filtrado_${widget.conversacionId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'mensajes_soporte',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversacion_id',
            value: widget.conversacionId,
          ),
          callback: (payload) async {
            final nuevoMensaje = Map<String, dynamic>.from(payload.newRecord);
            final user = supabase.auth.currentUser;

            final remitenteId = nuevoMensaje['remitente_auth_id']?.toString();
            if (remitenteId != widget.remitenteAuthId &&
                remitenteId != user?.id) {
              return;
            }

            // Los envíos propios ya se reflejan con insert + _cargarMensajes (evita duplicado)
            if (user != null && remitenteId == user.id) {
              return;
            }

            if (_listaYaTieneMensaje(nuevoMensaje)) {
              return;
            }

            if (mounted) {
              _agregarMensajeSiNoExiste(nuevoMensaje);
              Future.delayed(const Duration(milliseconds: 100), () {
                _scrollToBottom();
              });
              _marcarComoLeidos();
            }
          },
        )
        .subscribe();

    print('✅ Suscripción a realtime iniciada (filtrado)');
  }

  Future<void> _marcarComoLeidos() async {
    final user = supabase.auth.currentUser;
    if (user == null || !SyncService().isOnline) return;

    try {
      print('✅ Marcando mensajes como leídos para conversación: ${widget.conversacionId}, remitente: ${widget.remitenteAuthId}');
      
      await supabase
          .from('mensajes_soporte')
          .update({'leido': true})
          .eq('conversacion_id', widget.conversacionId)
          .eq('remitente_auth_id', widget.remitenteAuthId)
          .neq('remitente_auth_id', user.id)
          .eq('leido', false);
      
      print('✅ Mensajes marcados como leídos');
      
      // Forzar actualización del contador global después de un pequeño delay
      Future.delayed(const Duration(milliseconds: 500), () {
        print('🔄 Contador global debería actualizarse automáticamente');
      });
    } catch (e) {
      print('❌ Error al marcar mensajes como leídos: $e');
    }
  }

  Future<void> _seleccionarFoto() async {
    try {
      // Mostrar opciones: Cámara o Galería
      final opcion = await showModalBottomSheet<String>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF4CAF50)),
                title: const Text('Tomar foto'),
                onTap: () => Navigator.pop(context, 'camara'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Color(0xFF4CAF50)),
                title: const Text('Elegir de galería'),
                onTap: () => Navigator.pop(context, 'galeria'),
              ),
              ListTile(
                leading: const Icon(Icons.cancel, color: Colors.red),
                title: const Text('Cancelar'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      );

      if (opcion == null) return;

      final ImageSource source = opcion == 'camara' 
          ? ImageSource.camera 
          : ImageSource.gallery;

      final XFile? imagen = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (imagen != null) {
        // Solo guardar la foto seleccionada, no enviarla aún
        setState(() {
          _fotoSeleccionada = imagen;
        });
      }
    } catch (e) {
      print('❌ Error al seleccionar foto: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al seleccionar foto: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _enviarFotoOfflineEncolada({
    required Map<String, dynamic> datosMensaje,
    required String pathPersistido,
    required String textoMensaje,
  }) async {
    await RepartidorPantallasOfflineService.encolarMensajeSoporte({
      ...datosMensaje,
      'foto_local_path': pathPersistido,
    });

    final localId = DateTime.now().millisecondsSinceEpoch.toString();
    final localMsg = {
      ...datosMensaje,
      'local_id': localId,
      'foto_url': 'local://$pathPersistido',
      'remitente_nombre': _nombreRepartidor,
      'remitente_rol': 'REPARTIDOR',
      'mensaje': textoMensaje,
      'created_at': DateTime.now().toIso8601String(),
      'pending_local': true,
    };

    if (mounted) {
      _agregarMensajeSiNoExiste(localMsg);
      await _persistirMensajesEnCache();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      setState(() => _fotoSeleccionada = null);
      _mensajeController.clear();
      _scrollToBottom();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Foto guardada. Se enviará cuando vuelva la conexión.',
          ),
          backgroundColor: Color(0xFFFF9800),
        ),
      );
    }
  }

  Future<void> _enviarFoto(XFile imagen) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (_enviandoFoto || _enviandoMensaje) {
      print('⚠️ Ya hay un envío en curso, ignorando foto duplicada...');
      return;
    }

    _enviandoFoto = true;
    if (mounted) setState(() {});

    final textoMensaje = _mensajeController.text.trim().isNotEmpty
        ? _mensajeController.text.trim()
        : '📷 Foto';

    String? tenantId =
        await RepartidorPantallasOfflineService.cargarTenantIdRepartidor(user.id);

    final datosMensaje = <String, dynamic>{
      'conversacion_id': widget.conversacionId,
      'remitente_auth_id': user.id,
      'mensaje': textoMensaje,
      'leido': false,
    };
    if (tenantId != null) {
      datosMensaje['tenant_id'] = tenantId;
    }

    try {
      if (!SyncService().isOnline) {
        final path = await RepartidorPantallasOfflineService.persistirFotoChatPendiente(
          imagen.path,
        );
        if (path == null) {
          throw Exception('No se pudo guardar la foto en el dispositivo');
        }
        await _enviarFotoOfflineEncolada(
          datosMensaje: datosMensaje,
          pathPersistido: path,
          textoMensaje: textoMensaje,
        );
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 12),
                Text('Subiendo foto...'),
              ],
            ),
            duration: Duration(seconds: 30),
          ),
        );
      }

      if (tenantId == null) {
        final conversacion = await ejecutarConTimeout(
          supabase
              .from('conversaciones_soporte')
              .select('tenant_id')
              .eq('id', widget.conversacionId)
              .maybeSingle(),
          timeout: const Duration(seconds: 6),
        );
        tenantId = conversacion?['tenant_id']?.toString();
        if (tenantId != null) {
          datosMensaje['tenant_id'] = tenantId;
        }
      }

      final file = File(imagen.path);
      final fileName =
          'chat_${DateTime.now().millisecondsSinceEpoch}_${user.id}.jpg';
      const bucket = 'fotos-perfil';

      final subidaOk = await ejecutarConTimeout(
        supabase.storage.from(bucket).upload(fileName, file),
        timeout: const Duration(seconds: 25),
      );
      if (subidaOk == null) {
        throw const SocketException('Timeout subiendo foto');
      }

      final publicUrl = supabase.storage.from(bucket).getPublicUrl(fileName);
      datosMensaje['foto_url'] = publicUrl;

      await ejecutarConTimeout(
        supabase.from('mensajes_soporte').insert(datosMensaje),
        timeout: const Duration(seconds: 12),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        setState(() => _fotoSeleccionada = null);
        _mensajeController.clear();
        await _cargarMensajes();
        _scrollToBottom();
      }
    } catch (e) {
      print('❌ Error al enviar foto: $e');
      if (RepartidorPantallasOfflineService.esErrorDeRed(e) ||
          !SyncService().isOnline) {
        final path = await RepartidorPantallasOfflineService.persistirFotoChatPendiente(
          imagen.path,
        );
        if (path != null) {
          await _enviarFotoOfflineEncolada(
            datosMensaje: datosMensaje,
            pathPersistido: path,
            textoMensaje: textoMensaje,
          );
          return;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo enviar la foto. Comprueba la conexión o inténtalo de nuevo.',
            ),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _enviandoFoto = false);
      }
    }
  }

  Future<void> _enviarMensaje() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (_enviandoFoto || _enviandoMensaje) return;

    // Si hay foto seleccionada, enviarla primero
    if (_fotoSeleccionada != null) {
      await _enviarFoto(_fotoSeleccionada!);
      return;
    }

    if (_mensajeController.text.trim().isEmpty) return;

    final mensaje = _mensajeController.text.trim();
    _mensajeController.clear();

    _enviandoMensaje = true;
    if (mounted) setState(() {});

    try {
      String? tenantId =
          await RepartidorPantallasOfflineService.cargarTenantIdRepartidor(user.id);

      if (SyncService().isOnline && tenantId == null) {
        try {
          final conversacion = await ejecutarConTimeout(
            supabase
                .from('conversaciones_soporte')
                .select('tenant_id')
                .eq('id', widget.conversacionId)
                .maybeSingle(),
            timeout: const Duration(seconds: 6),
          );
          tenantId = conversacion?['tenant_id']?.toString();
        } catch (e) {
          print('⚠️ tenant_id conversación: $e');
        }
      }

      final datosMensaje = {
        'conversacion_id': widget.conversacionId,
        'remitente_auth_id': user.id,
        'mensaje': mensaje,
        'leido': false,
      };

      if (tenantId != null) {
        datosMensaje['tenant_id'] = tenantId;
      }

      final localId = DateTime.now().millisecondsSinceEpoch.toString();
      final localMsg = {
        ...datosMensaje,
        'local_id': localId,
        'remitente_nombre': _nombreRepartidor,
        'remitente_rol': 'REPARTIDOR',
        'created_at': DateTime.now().toIso8601String(),
        'pending_local': true,
      };

      if (!SyncService().isOnline) {
        await RepartidorPantallasOfflineService.encolarMensajeSoporte(datosMensaje);
        if (mounted) {
          _agregarMensajeSiNoExiste(localMsg);
          await _persistirMensajesEnCache();
          _scrollToBottom();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Mensaje guardado. Se enviará al reconectar.'),
              backgroundColor: Color(0xFFFF9800),
            ),
          );
        }
        return;
      }

      try {
        await supabase.from('mensajes_soporte').insert(datosMensaje);
      } catch (e) {
        if (RepartidorPantallasOfflineService.esErrorDeRed(e)) {
          await RepartidorPantallasOfflineService.encolarMensajeSoporte(datosMensaje);
          if (mounted) {
            _agregarMensajeSiNoExiste(localMsg);
            await _persistirMensajesEnCache();
            _scrollToBottom();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sin conexión: mensaje en cola.'),
                backgroundColor: Color(0xFFFF9800),
              ),
            );
          }
          return;
        }
        rethrow;
      }
      await _cargarMensajes();
      _scrollToBottom();
    } catch (e) {
      print('❌ Error al enviar mensaje: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Error: ${e.toString()}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _enviandoMensaje = false);
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final esAdmin = widget.rolRemitente == 'ADMINISTRADOR';
    final esEmpleado = widget.rolRemitente == 'EMPLEADO';

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.header,
        title: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: esAdmin
                  ? const Color(0xFF4CAF50)
                  : esEmpleado
                      ? const Color(0xFFFF9800)
                      : AppColors.primary,
              backgroundImage: widget.fotoRemitente != null &&
                      widget.fotoRemitente!.isNotEmpty
                  ? NetworkImage(widget.fotoRemitente!)
                  : null,
              child: widget.fotoRemitente == null ||
                      widget.fotoRemitente!.isEmpty
                  ? Icon(
                      esAdmin ? Icons.admin_panel_settings : Icons.person,
                      size: 16,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        esAdmin
                            ? 'Administrador'
                            : widget.nombreRemitente,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (esAdmin) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.verified,
                          size: 16,
                          color: Colors.white,
                        ),
                      ],
                    ],
                  ),
                  if (esEmpleado)
                    const Text(
                      'Empleado',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _mensajes.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 80,
                                color: AppColors.darkTextMuted.withOpacity(0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Conversación con ${esAdmin ? "Administrador" : widget.nombreRemitente}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.darkText,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Escribe un mensaje para comenzar',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.darkTextMuted,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _mensajes.length,
                          itemBuilder: (context, index) {
                            final mensaje = _mensajes[index];
                            final msgKey = mensaje['id']?.toString() ??
                                'idx_$index';
                            final user = supabase.auth.currentUser;
                            final esMio = mensaje['remitente_auth_id'] == user?.id;
                            final nombreRemitente = mensaje['remitente_nombre'] ?? 
                                (esMio ? _nombreRepartidor : widget.nombreRemitente);
                            final rolRemitente = mensaje['remitente_rol'] ?? 
                                (esMio ? 'REPARTIDOR' : widget.rolRemitente);
                            final esAdminMsg = rolRemitente == 'ADMINISTRADOR';
                            final esEmpleadoMsg = rolRemitente == 'EMPLEADO';
                            final fotoRemitente = mensaje['remitente_foto'];
                            final fotoUrl = mensaje['foto_url'];

                            final fechaMsg = DateTime.tryParse(
                                  mensaje['created_at']?.toString() ?? '',
                                ) ??
                                DateTime.now();
                            final pendienteEnvio =
                                mensaje['pending_local'] == true;

                            return KeyedSubtree(
                              key: ValueKey('msg_$msgKey'),
                              child: _buildMensajeBurbuja(
                                mensaje['mensaje'],
                                esMio,
                                nombreRemitente,
                                esAdminMsg,
                                esEmpleadoMsg,
                                fotoRemitente,
                                fechaMsg,
                                fotoUrl,
                                pendienteEnvio: pendienteEnvio,
                              ),
                            );
                          },
                        ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Preview de foto seleccionada
                        if (_fotoSeleccionada != null) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.darkElevated,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(_fotoSeleccionada!.path),
                                    width: 60,
                                    height: 60,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Foto seleccionada',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.darkText,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Presiona enviar para subirla',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.darkTextMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 20),
                                  color: Colors.red,
                                  onPressed: () {
                                    setState(() {
                                      _fotoSeleccionada = null;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                        Row(
                          children: [
                            // Botón para tomar/subir foto
                            Material(
                              color: const Color(0xFF4CAF50),
                              borderRadius: BorderRadius.circular(24),
                              child: InkWell(
                                onTap: _seleccionarFoto,
                                borderRadius: BorderRadius.circular(24),
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _mensajeController,
                                decoration: InputDecoration(
                                  hintText: _fotoSeleccionada != null 
                                      ? 'Agregar mensaje (opcional)...'
                                      : 'Escribe un mensaje...',
                                  hintStyle: const TextStyle(
                                    color: AppColors.darkTextMuted,
                                    fontSize: 14,
                                  ),
                                  filled: true,
                                  fillColor: AppColors.darkElevated,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(24),
                                    borderSide: BorderSide.none,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                ),
                                maxLines: null,
                                textCapitalization: TextCapitalization.sentences,
                                onSubmitted: (_enviandoFoto || _enviandoMensaje)
                                    ? null
                                    : (_) => _enviarMensaje(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Material(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(24),
                              child: InkWell(
                                onTap: (_enviandoFoto || _enviandoMensaje)
                                    ? null
                                    : _enviarMensaje,
                                borderRadius: BorderRadius.circular(24),
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  alignment: Alignment.center,
                                  child: _enviandoFoto
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        )
                                      : const Icon(
                                          Icons.send,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _imagenMensajeChat(String fotoUrl, {bool pendienteEnvio = false}) {
    final rutaLocal = EntregaFotoUtil.rutaArchivoLocal(fotoUrl);
    if (rutaLocal != null) {
      final file = File(rutaLocal);
      return Image.file(
        file,
        width: 200,
        height: 200,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholderImagenChat(
          pendienteEnvio: pendienteEnvio,
          error: true,
        ),
      );
    }

    if (fotoUrl.startsWith('http')) {
      return Image.network(
        fotoUrl,
        width: 200,
        height: 200,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return _placeholderImagenChat(cargando: true);
        },
        errorBuilder: (_, __, ___) =>
            _placeholderImagenChat(pendienteEnvio: pendienteEnvio, error: true),
      );
    }

    return _placeholderImagenChat(pendienteEnvio: pendienteEnvio);
  }

  Widget _placeholderImagenChat({
    bool cargando = false,
    bool error = false,
    bool pendienteEnvio = false,
  }) {
    return Container(
      width: 200,
      height: 200,
      color: Colors.grey[300],
      child: Center(
        child: cargando
            ? const CircularProgressIndicator(strokeWidth: 2)
            : Icon(
                error
                    ? Icons.broken_image_outlined
                    : (pendienteEnvio ? Icons.schedule : Icons.image),
                color: error
                    ? const Color(0xFFDC2626)
                    : const Color(0xFFFF9800),
                size: 40,
              ),
      ),
    );
  }

  Widget _buildMensajeBurbuja(
    String mensaje,
    bool esMio,
    String nombreRemitente,
    bool esAdmin,
    bool esEmpleado,
    String? fotoRemitente,
    DateTime fecha,
    String? fotoUrl, {
    bool pendienteEnvio = false,
  }) {
    Color colorAvatar;
    IconData iconoAvatar;
    String etiquetaRemitente;

    if (esMio) {
      colorAvatar = AppColors.accent;
      iconoAvatar = Icons.delivery_dining;
      etiquetaRemitente = nombreRemitente;
    } else if (esAdmin) {
      colorAvatar = const Color(0xFF4CAF50);
      iconoAvatar = Icons.admin_panel_settings;
      etiquetaRemitente = 'Administrador';
    } else if (esEmpleado) {
      colorAvatar = const Color(0xFFFF9800);
      iconoAvatar = Icons.person;
      etiquetaRemitente = nombreRemitente;
    } else {
      colorAvatar = AppColors.primary;
      iconoAvatar = Icons.person;
      etiquetaRemitente = nombreRemitente;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: esMio ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!esMio) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: colorAvatar,
              backgroundImage: fotoRemitente != null && fotoRemitente.isNotEmpty
                  ? NetworkImage(fotoRemitente)
                  : null,
              child: fotoRemitente == null || fotoRemitente.isEmpty
                  ? Icon(
                      iconoAvatar,
                      size: 18,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  esMio ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!esMio)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, bottom: 4),
                    child: Row(
                      children: [
                        Text(
                          etiquetaRemitente,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: esAdmin
                                ? const Color(0xFF4CAF50)
                                : esEmpleado
                                    ? const Color(0xFFFF9800)
                                    : AppColors.darkTextMuted,
                          ),
                        ),
                        if (esAdmin) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.verified,
                            size: 12,
                            color: const Color(0xFF4CAF50),
                          ),
                        ],
                      ],
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: esMio
                        ? AppColors.primary
                        : esAdmin
                            ? const Color(0xFF4CAF50).withOpacity(0.1)
                            : esEmpleado
                                ? const Color(0xFFFF9800).withOpacity(0.1)
                                : Colors.white,
                    border: !esMio && (esAdmin || esEmpleado)
                        ? Border.all(
                            color: esAdmin
                                ? const Color(0xFF4CAF50).withOpacity(0.3)
                                : const Color(0xFFFF9800).withOpacity(0.3),
                            width: 1,
                          )
                        : null,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(esMio ? 16 : 4),
                      bottomRight: Radius.circular(esMio ? 4 : 16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (fotoUrl != null && fotoUrl.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _imagenMensajeChat(
                            fotoUrl,
                            pendienteEnvio: pendienteEnvio,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      // Texto: omitir placeholder si ya hay imagen
                      if (mensaje.isNotEmpty &&
                          !(fotoUrl != null &&
                              fotoUrl.isNotEmpty &&
                              (mensaje == '📷 Foto' || mensaje == '📷 foto')))
                        Text(
                          mensaje,
                          style: TextStyle(
                            fontSize: 14,
                            color: esMio ? Colors.white : AppColors.darkText,
                            height: 1.4,
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 12, right: 12),
                  child: Text(
                    pendienteEnvio
                        ? '${_formatearHora(fecha)} · Pendiente de envío'
                        : _formatearHora(fecha),
                    style: TextStyle(
                      fontSize: 11,
                      color: pendienteEnvio
                          ? const Color(0xFFFF9800)
                          : AppColors.darkTextMuted,
                      fontWeight:
                          pendienteEnvio ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (esMio) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: AppColors.accent,
              child: const Icon(
                Icons.delivery_dining,
                size: 18,
                color: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatearHora(DateTime fecha) {
    final ahora = DateTime.now();
    final diferencia = ahora.difference(fecha);

    if (diferencia.inDays == 0) {
      final hora = fecha.hour.toString().padLeft(2, '0');
      final minuto = fecha.minute.toString().padLeft(2, '0');
      return '$hora:$minuto';
    } else if (diferencia.inDays == 1) {
      return 'Ayer';
    } else if (diferencia.inDays < 7) {
      return '${diferencia.inDays} días';
    } else {
      return '${fecha.day}/${fecha.month}/${fecha.year}';
    }
  }
}

