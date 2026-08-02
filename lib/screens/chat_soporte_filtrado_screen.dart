import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../main.dart';
import '../services/chat_audio_cache_service.dart';
import '../services/network_timeout.dart';
import '../services/repartidor_chat_mensaje_sonido_service.dart';
import '../services/repartidor_pantallas_offline_service.dart';
import '../services/sync_service.dart';
import '../utils/entrega_foto_util.dart';
import '../utils/mensaje_error_operacion.dart';
import '../widgets/chat_nota_voz_player.dart';

/// Pantalla de chat filtrado que muestra solo mensajes de un remitente específico
/// o, en [modoConversacionCompleta], todo el hilo con la empresa.
class ChatSoporteFiltradoScreen extends StatefulWidget {
  final String conversacionId;
  final String remitenteAuthId;
  final String nombreRemitente;
  final String rolRemitente;
  final String? fotoRemitente;
  /// Si true: muestra todos los mensajes de la conversación (inicio por el repartidor).
  final bool modoConversacionCompleta;

  const ChatSoporteFiltradoScreen({
    super.key,
    required this.conversacionId,
    required this.remitenteAuthId,
    required this.nombreRemitente,
    required this.rolRemitente,
    this.fotoRemitente,
    this.modoConversacionCompleta = false,
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
  final AudioRecorder _recorder = AudioRecorder();
  bool _grabandoVoz = false;
  bool _enviandoVoz = false;
  DateTime? _grabacionInicio;
  Timer? _timerGrabacion;
  int _segundosGrabacion = 0;

  @override
  void initState() {
    super.initState();
    RepartidorChatMensajeSonidoService.conversacionActivaId =
        widget.conversacionId;
    _mensajeController.addListener(() {
      if (mounted) setState(() {});
    });
    _inicializarChat();
  }

  @override
  void dispose() {
    if (RepartidorChatMensajeSonidoService.conversacionActivaId ==
        widget.conversacionId) {
      RepartidorChatMensajeSonidoService.conversacionActivaId = null;
    }
    _timerGrabacion?.cancel();
    unawaited(_recorder.dispose());
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

  bool _listaContiene(List<Map<String, dynamic>> lista, Map<String, dynamic> m) {
    final clave = _claveMensaje(m);
    if (clave != null) {
      return lista.any((x) => _claveMensaje(x) == clave);
    }
    final rem = m['remitente_auth_id']?.toString() ?? '';
    final foto = m['foto_url']?.toString() ?? '';
    final texto = m['mensaje']?.toString() ?? '';
    final created = m['created_at']?.toString() ?? '';
    if (rem.isEmpty) return false;
    return lista.any((x) {
      if (x['remitente_auth_id']?.toString() != rem) return false;
      if ((x['foto_url']?.toString() ?? '') != foto) return false;
      if ((x['mensaje']?.toString() ?? '') != texto) return false;
      if (created.isNotEmpty &&
          (x['created_at']?.toString() ?? '') == created) {
        return true;
      }
      return false;
    });
  }

  Future<void> _fusionarMensajesLocales() async {
    final user = supabase.auth.currentUser;
    var lista = <Map<String, dynamic>>[];

    final cached =
        await RepartidorPantallasOfflineService.cargarMensajesChat(widget.conversacionId);
    if (cached != null) {
      lista = cached.map(_enriquecerMensaje).toList();
    }

    if (user != null) {
      final pendientes =
          await RepartidorPantallasOfflineService.mensajesPendientesParaConversacion(
        conversacionId: widget.conversacionId,
        repartidorAuthId: user.id,
        nombreRepartidor: _nombreRepartidor,
      );
      for (final p in pendientes) {
        final enriq = _enriquecerMensaje(p);
        if (!_listaContiene(lista, enriq)) {
          lista.add(enriq);
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
      
      // Filtrar: un agente concreto, o toda la conversación con la empresa.
      final mensajesFiltrados = todosMensajes.where((mensaje) {
        final remitenteId = mensaje['remitente_auth_id'];
        if (widget.modoConversacionCompleta) return true;
        return remitenteId == widget.remitenteAuthId || remitenteId == user?.id;
      }).toList();

      // Enriquecer mensajes con información del remitente
      final mensajesEnriquecidos = <Map<String, dynamic>>[];
      
      for (var mensaje in mensajesFiltrados) {
        final mensajeEnriquecido = Map<String, dynamic>.from(mensaje);
        
        if (mensaje['remitente_auth_id'] == user?.id) {
          mensajeEnriquecido['remitente_nombre'] = _nombreRepartidor;
          mensajeEnriquecido['remitente_rol'] = 'REPARTIDOR';
        } else if (widget.modoConversacionCompleta) {
          final rid = mensaje['remitente_auth_id']?.toString() ?? '';
          Map<String, dynamic>? data;
          if (rid.isNotEmpty) {
            data = await RepartidorPantallasOfflineService.cargarRemitenteChat(rid);
            if (data == null && SyncService().isOnline) {
              try {
                final remote = await ejecutarConTimeout(
                  supabase
                      .from('usuarios')
                      .select('nombre, rol, foto_perfil')
                      .eq('auth_id', rid)
                      .maybeSingle(),
                  timeout: const Duration(seconds: 5),
                );
                if (remote != null) {
                  data = remote;
                  await RepartidorPantallasOfflineService.guardarRemitenteChat(
                    rid,
                    nombre: remote['nombre']?.toString() ?? 'Empresa',
                    rol: remote['rol']?.toString() ?? 'EMPLEADO',
                    foto: remote['foto_perfil']?.toString(),
                  );
                }
              } catch (_) {}
            }
          }
          mensajeEnriquecido['remitente_nombre'] =
              data?['nombre'] ?? widget.nombreRemitente;
          mensajeEnriquecido['remitente_rol'] =
              data?['rol'] ?? widget.rolRemitente;
          mensajeEnriquecido['remitente_foto'] =
              data?['foto_perfil'] ?? widget.fotoRemitente;
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

      // Prefetch notas de voz a disco (reproducir luego sin internet).
      for (final m in mensajesEnriquecidos) {
        final a = m['audio_url']?.toString().trim();
        if (a != null && a.isNotEmpty && a.startsWith('http')) {
          unawaited(ChatAudioCache.prefetch(a));
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
            if (!widget.modoConversacionCompleta &&
                remitenteId != widget.remitenteAuthId &&
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
              final audioIn = nuevoMensaje['audio_url']?.toString().trim();
              if (audioIn != null &&
                  audioIn.isNotEmpty &&
                  audioIn.startsWith('http')) {
                unawaited(ChatAudioCache.prefetch(audioIn));
              }
              unawaited(_persistirMensajesEnCache());
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
      
      var q = supabase
          .from('mensajes_soporte')
          .update({'leido': true})
          .eq('conversacion_id', widget.conversacionId)
          .neq('remitente_auth_id', user.id)
          .eq('leido', false);
      if (!widget.modoConversacionCompleta &&
          widget.remitenteAuthId.isNotEmpty) {
        q = q.eq('remitente_auth_id', widget.remitenteAuthId);
      }
      await q;
      
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
            content: Text(mensajeErrorOperacion(e, contexto: 'imagen')),
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

  Future<void> _toggleGrabacionVoz() async {
    if (_enviandoVoz || _enviandoFoto || _enviandoMensaje) return;
    if (_grabandoVoz) {
      await _detenerYEnviarVoz();
      return;
    }
    await _iniciarGrabacionVoz();
  }

  Future<void> _iniciarGrabacionVoz() async {
    try {
      final mic = await Permission.microphone.request();
      if (!mic.isGranted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Necesitas permiso de micrófono para notas de voz.'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
        return;
      }
      if (!await _recorder.hasPermission()) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo acceder al micrófono.'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
        return;
      }

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/chat_voz_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
        ),
        path: path,
      );
      _grabacionInicio = DateTime.now();
      _segundosGrabacion = 0;
      _timerGrabacion?.cancel();
      _timerGrabacion = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || !_grabandoVoz) return;
        setState(() => _segundosGrabacion++);
      });
      if (mounted) setState(() => _grabandoVoz = true);
    } catch (e) {
      print('❌ Iniciar grabación voz: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mensajeErrorOperacion(e, contexto: 'chat')),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _cancelarGrabacionVoz() async {
    try {
      if (await _recorder.isRecording()) {
        final path = await _recorder.stop();
        if (path != null) {
          try {
            await File(path).delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
    _timerGrabacion?.cancel();
    _timerGrabacion = null;
    _grabacionInicio = null;
    if (mounted) {
      setState(() {
        _grabandoVoz = false;
        _segundosGrabacion = 0;
      });
    }
  }

  Future<void> _detenerYEnviarVoz() async {
    if (!_grabandoVoz) return;
    _timerGrabacion?.cancel();
    _timerGrabacion = null;
    String? path;
    try {
      path = await _recorder.stop();
    } catch (e) {
      print('❌ Stop grabación: $e');
    }
    if (mounted) {
      setState(() {
        _grabandoVoz = false;
        _enviandoVoz = true;
      });
    }
    final dur = _grabacionInicio == null
        ? _segundosGrabacion
        : DateTime.now().difference(_grabacionInicio!).inSeconds;
    _grabacionInicio = null;
    _segundosGrabacion = 0;

    if (path == null || path.isEmpty || !File(path).existsSync()) {
      if (mounted) setState(() => _enviandoVoz = false);
      return;
    }
    if (dur < 1) {
      try {
        await File(path).delete();
      } catch (_) {}
      if (mounted) {
        setState(() => _enviandoVoz = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('La nota de voz es demasiado corta.'),
            backgroundColor: Color(0xFFFF9800),
          ),
        );
      }
      return;
    }

    try {
      await _enviarAudioArchivo(path);
    } finally {
      try {
        await File(path).delete();
      } catch (_) {}
      if (mounted) setState(() => _enviandoVoz = false);
    }
  }

  Future<void> _enviarAudioArchivo(String pathLocal) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    if (!SyncService().isOnline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Necesitas conexión para enviar notas de voz.'),
            backgroundColor: Color(0xFFFF9800),
          ),
        );
      }
      return;
    }

    String? tenantId =
        await RepartidorPantallasOfflineService.cargarTenantIdRepartidor(user.id);
    if (tenantId == null) {
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
      } catch (_) {}
    }

    final file = File(pathLocal);
    final fileName =
        'chat_audio/${tenantId ?? 'sin_tenant'}/${user.id}_${DateTime.now().millisecondsSinceEpoch}.m4a';
    const bucket = 'fotos-perfil';
    await ejecutarConTimeout(
      supabase.storage.from(bucket).upload(
            fileName,
            file,
            fileOptions: const FileOptions(
              contentType: 'audio/mp4',
              upsert: false,
            ),
          ),
      timeout: const Duration(seconds: 45),
    );
    final publicUrl = supabase.storage.from(bucket).getPublicUrl(fileName);
    // Guardar en caché local antes de borrar el temporal (offline playback).
    try {
      await ChatAudioCache.saveFromFile(publicUrl, pathLocal);
    } catch (_) {}

    final datosMensaje = <String, dynamic>{
      'conversacion_id': widget.conversacionId,
      'remitente_auth_id': user.id,
      'mensaje': '🎤 Nota de voz',
      'audio_url': publicUrl,
      'leido': false,
    };
    if (tenantId != null) datosMensaje['tenant_id'] = tenantId;

    await supabase.from('mensajes_soporte').insert(datosMensaje);
    await _cargarMensajes();
    _scrollToBottom();
  }

  Future<void> _enviarMensaje() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (_enviandoFoto || _enviandoMensaje || _enviandoVoz || _grabandoVoz) {
      return;
    }

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
            content: Text(mensajeErrorOperacion(e, contexto: 'chat')),
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
                            final fotoUrl = mensaje['foto_url']?.toString();
                            final audioUrlRaw =
                                mensaje['audio_url']?.toString().trim();
                            final audioUrl =
                                (audioUrlRaw != null && audioUrlRaw.isNotEmpty)
                                    ? audioUrlRaw
                                    : null;

                            final fechaMsg = DateTime.tryParse(
                                  mensaje['created_at']?.toString() ?? '',
                                ) ??
                                DateTime.now();
                            final pendienteEnvio =
                                mensaje['pending_local'] == true;

                            return KeyedSubtree(
                              key: ValueKey('msg_$msgKey'),
                              child: _buildMensajeBurbuja(
                                mensaje['mensaje']?.toString() ?? '',
                                esMio,
                                nombreRemitente,
                                esAdminMsg,
                                esEmpleadoMsg,
                                fotoRemitente,
                                fechaMsg,
                                fotoUrl,
                                audioUrl: audioUrl,
                                pendienteEnvio: pendienteEnvio,
                              ),
                            );
                          },
                        ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.darkSurface,
                    border: const Border(
                      top: BorderSide(color: AppColors.darkBorder, width: 0.5),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
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
                        if (_grabandoVoz)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFFDC2626).withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.fiber_manual_record,
                                  color: Color(0xFFDC2626),
                                  size: 14,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Grabando… ${_segundosGrabacion}s  ·  toca ✓ para enviar',
                                    style: const TextStyle(
                                      color: AppColors.darkText,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _cancelarGrabacionVoz,
                                  child: const Text(
                                    'Cancelar',
                                    style: TextStyle(
                                      color: Color(0xFF9CA3AF),
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _ChatBarIconButton(
                              icon: Icons.photo_camera_outlined,
                              tooltip: 'Foto',
                              color: const Color(0xFF4CAF50),
                              onTap: (_enviandoFoto ||
                                      _enviandoMensaje ||
                                      _grabandoVoz ||
                                      _enviandoVoz)
                                  ? null
                                  : _seleccionarFoto,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _mensajeController,
                                enabled: !_grabandoVoz && !_enviandoVoz,
                                style: const TextStyle(
                                  color: AppColors.darkText,
                                  fontSize: 14,
                                ),
                                decoration: InputDecoration(
                                  hintText: _fotoSeleccionada != null
                                      ? 'Mensaje (opcional)…'
                                      : 'Escribe un mensaje…',
                                  hintStyle: const TextStyle(
                                    color: AppColors.darkTextMuted,
                                    fontSize: 13,
                                  ),
                                  filled: true,
                                  fillColor: AppColors.darkElevated,
                                  isDense: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: BorderSide(
                                      color: AppColors.darkBorder,
                                    ),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: BorderSide(
                                      color: AppColors.darkBorder,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    borderSide: const BorderSide(
                                      color: Color(0xFF37474F),
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                ),
                                maxLines: 4,
                                minLines: 1,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                onSubmitted: (_enviandoFoto ||
                                        _enviandoMensaje ||
                                        _grabandoVoz)
                                    ? null
                                    : (_) => _enviarMensaje(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_enviandoFoto || _enviandoVoz)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 4),
                                child: SizedBox(
                                  width: 34,
                                  height: 34,
                                  child: Padding(
                                    padding: EdgeInsets.all(7),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFFFF9800),
                                    ),
                                  ),
                                ),
                              )
                            else if (_grabandoVoz)
                              _ChatBarIconButton(
                                icon: Icons.check_rounded,
                                tooltip: 'Enviar nota de voz',
                                color: const Color(0xFF4CAF50),
                                onTap: _detenerYEnviarVoz,
                              )
                            else if (_mensajeController.text.trim().isEmpty &&
                                _fotoSeleccionada == null)
                              _ChatBarIconButton(
                                icon: Icons.mic_none_rounded,
                                tooltip: 'Nota de voz',
                                color: const Color(0xFF37474F),
                                onTap: _toggleGrabacionVoz,
                              )
                            else
                              _ChatBarIconButton(
                                icon: Icons.send_rounded,
                                tooltip: 'Enviar',
                                color: AppColors.primary,
                                onTap: (_enviandoMensaje || _enviandoFoto)
                                    ? null
                                    : _enviarMensaje,
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
      color: AppColors.darkBorder,
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
    String? audioUrl,
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

    final tieneFoto = fotoUrl != null && fotoUrl.isNotEmpty;
    final captionOculto = tieneFoto &&
        (mensaje.isEmpty ||
            mensaje == '📷 Foto' ||
            mensaje == '📷 foto');
    final soloImagen = tieneFoto &&
        captionOculto &&
        (audioUrl == null || audioUrl.isEmpty);

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
                  // Foto sola: marco fino (2px). Texto/mezcla: padding normal.
                  padding: soloImagen
                      ? const EdgeInsets.all(2)
                      : tieneFoto
                          ? const EdgeInsets.fromLTRB(4, 4, 4, 8)
                          : const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                  decoration: BoxDecoration(
                    // Fondo oscuro siempre: texto claro (#ECEFF1) legible.
                    // Antes: blanco / verde claro + darkText → texto casi invisible.
                    color: esMio
                        ? AppColors.primary
                        : AppColors.darkElevated,
                    border: !esMio
                        ? Border.all(
                            color: esAdmin
                                ? const Color(0xFF4CAF50).withValues(alpha: 0.55)
                                : esEmpleado
                                    ? const Color(0xFFFF9800)
                                        .withValues(alpha: 0.55)
                                    : AppColors.darkBorder,
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
                      if (tieneFoto) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(
                            soloImagen ? 14 : 8,
                          ),
                          child: _imagenMensajeChat(
                            fotoUrl!,
                            pendienteEnvio: pendienteEnvio,
                          ),
                        ),
                        if (!captionOculto ||
                            (audioUrl != null && audioUrl.isNotEmpty))
                          const SizedBox(height: 8),
                      ],
                      if (audioUrl != null && audioUrl.isNotEmpty) ...[
                        ChatNotaVozPlayer(
                          url: audioUrl,
                          onDarkBubble: esMio,
                        ),
                        const SizedBox(height: 4),
                      ],
                      // Texto: omitir placeholder si ya hay imagen o audio
                      if (mensaje.isNotEmpty &&
                          !captionOculto &&
                          !(audioUrl != null &&
                              audioUrl.isNotEmpty &&
                              (mensaje == '🎤 Nota de voz' ||
                                  mensaje == 'Nota de voz')))
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

/// Botón compacto de la barra de chat (cámara / mic / enviar).
class _ChatBarIconButton extends StatelessWidget {
  const _ChatBarIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: onTap == null ? color.withValues(alpha: 0.45) : color,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
    if (tooltip == null || tooltip!.isEmpty) return btn;
    return Tooltip(message: tooltip!, child: btn);
  }
}

