import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../main.dart';
import '../config/app_colors.dart';

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

  @override
  void initState() {
    super.initState();
    _inicializarChat();
  }

  @override
  void dispose() {
    _mensajeController.dispose();
    _scrollController.dispose();
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _inicializarChat() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    try {
      // Obtener nombre del repartidor
      final userData = await supabase
          .from('usuarios')
          .select('nombre')
          .eq('auth_id', user.id)
          .single();
      
      setState(() {
        _nombreRepartidor = userData['nombre'] ?? 'Repartidor';
      });

      // Cargar mensajes filtrados
      await _cargarMensajes();

      // Suscribirse a nuevos mensajes
      _suscribirseAMensajes();

      setState(() {
        _cargando = false;
      });

      Future.delayed(const Duration(milliseconds: 300), () {
        _scrollToBottom();
      });
    } catch (e) {
      print('❌ Error al inicializar chat: $e');
      setState(() {
        _cargando = false;
      });
    }
  }

  Future<void> _cargarMensajes() async {
    try {
      // Cargar todos los mensajes de la conversación
      final todosMensajes = await supabase
          .from('mensajes_soporte')
          .select('*')
          .eq('conversacion_id', widget.conversacionId)
          .order('created_at', ascending: true);

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

      await _marcarComoLeidos();
    } catch (e) {
      print('❌ Error al cargar mensajes: $e');
    }
  }

  void _suscribirseAMensajes() {
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
            
            // Solo agregar si es del remitente seleccionado o del repartidor
            if (nuevoMensaje['remitente_auth_id'] == widget.remitenteAuthId ||
                nuevoMensaje['remitente_auth_id'] == user?.id) {
              
              if (nuevoMensaje['remitente_auth_id'] == user?.id) {
                nuevoMensaje['remitente_nombre'] = _nombreRepartidor;
                nuevoMensaje['remitente_rol'] = 'REPARTIDOR';
              } else {
                nuevoMensaje['remitente_nombre'] = widget.nombreRemitente;
                nuevoMensaje['remitente_rol'] = widget.rolRemitente;
                nuevoMensaje['remitente_foto'] = widget.fotoRemitente;
              }

              if (mounted) {
                setState(() {
                  _mensajes.add(nuevoMensaje);
                });
                Future.delayed(const Duration(milliseconds: 100), () {
                  _scrollToBottom();
                });
                if (user != null && nuevoMensaje['remitente_auth_id'] != user.id) {
                  _marcarComoLeidos();
                }
              }
            }
          },
        )
        .subscribe();

    print('✅ Suscripción a realtime iniciada (filtrado)');
  }

  Future<void> _marcarComoLeidos() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

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

  Future<void> _enviarFoto(XFile imagen) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // Evitar envíos dobles
    if (_enviandoFoto) {
      print('⚠️ Ya se está enviando una foto, ignorando...');
      return;
    }

    setState(() {
      _enviandoFoto = true;
    });

    try {
      // Mostrar indicador de carga
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

      // Subir imagen a Supabase Storage
      final file = File(imagen.path);
      final fileName = 'chat_${DateTime.now().millisecondsSinceEpoch}_${user.id}.jpg';
      final bucket = 'fotos-perfil'; // Usar bucket existente que ya está configurado

      await supabase.storage.from(bucket).upload(fileName, file);

      // Obtener URL pública
      final publicUrl = supabase.storage.from(bucket).getPublicUrl(fileName);

      // Obtener tenant_id
      String? tenantId;
      try {
        final conversacion = await supabase
            .from('conversaciones_soporte')
            .select('tenant_id')
            .eq('id', widget.conversacionId)
            .single();
        tenantId = conversacion['tenant_id'];
      } catch (e) {
        try {
          final userData = await supabase
              .from('usuarios')
              .select('tenant_id')
              .eq('auth_id', user.id)
              .single();
          tenantId = userData['tenant_id'];
        } catch (e2) {
          print('⚠️ No se pudo obtener tenant_id: $e2');
        }
      }

      // Enviar mensaje con la foto (incluir texto si hay)
      final textoMensaje = _mensajeController.text.trim().isNotEmpty 
          ? _mensajeController.text.trim() 
          : '📷 Foto';
      
      final datosMensaje = {
        'conversacion_id': widget.conversacionId,
        'remitente_auth_id': user.id,
        'mensaje': textoMensaje,
        'foto_url': publicUrl, // Campo para la URL de la foto
        'leido': false,
      };

      if (tenantId != null) {
        datosMensaje['tenant_id'] = tenantId;
      }

      await supabase.from('mensajes_soporte').insert(datosMensaje);
      
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        // Limpiar foto y texto después de enviar exitosamente
        setState(() {
          _fotoSeleccionada = null;
          _enviandoFoto = false;
        });
        _mensajeController.clear();
        await _cargarMensajes();
        _scrollToBottom();
      }
    } catch (e) {
      print('❌ Error al enviar foto: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar foto: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      // Resetear flag de envío
      if (mounted) {
        setState(() {
          _enviandoFoto = false;
        });
      }
    }
  }

  Future<void> _enviarMensaje() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // Si hay foto seleccionada, enviarla primero
    if (_fotoSeleccionada != null) {
      await _enviarFoto(_fotoSeleccionada!);
      // La foto y el texto ya se limpian dentro de _enviarFoto
      return; // Salir después de enviar la foto
    }

    // Si no hay foto, enviar mensaje de texto normal
    if (_mensajeController.text.trim().isEmpty) return;

    final mensaje = _mensajeController.text.trim();
    _mensajeController.clear();

    try {
      // Obtener tenant_id
      String? tenantId;
      try {
        final conversacion = await supabase
            .from('conversaciones_soporte')
            .select('tenant_id')
            .eq('id', widget.conversacionId)
            .single();
        tenantId = conversacion['tenant_id'];
      } catch (e) {
        try {
          final userData = await supabase
              .from('usuarios')
              .select('tenant_id')
              .eq('auth_id', user.id)
              .single();
          tenantId = userData['tenant_id'];
        } catch (e2) {
          print('⚠️ No se pudo obtener tenant_id: $e2');
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

      await supabase.from('mensajes_soporte').insert(datosMensaje);
      await _cargarMensajes();
      _scrollToBottom();
    } catch (e) {
      print('❌ Error al enviar mensaje: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Error: ${e.toString()}'),
          backgroundColor: Colors.orange,
        ),
      );
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
      backgroundColor: AppColors.fondoGeneral,
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
                                color: AppColors.textoSecundario.withOpacity(0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Conversación con ${esAdmin ? "Administrador" : widget.nombreRemitente}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textoPrincipal,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Escribe un mensaje para comenzar',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textoSecundario,
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

                            return _buildMensajeBurbuja(
                              mensaje['mensaje'],
                              esMio,
                              nombreRemitente,
                              esAdminMsg,
                              esEmpleadoMsg,
                              fotoRemitente,
                              DateTime.parse(mensaje['created_at']),
                              fotoUrl,
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
                              color: AppColors.fondoGeneral,
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
                                          color: AppColors.textoPrincipal,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Presiona enviar para subirla',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textoSecundario,
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
                                    color: AppColors.textoSecundario,
                                    fontSize: 14,
                                  ),
                                  filled: true,
                                  fillColor: AppColors.fondoGeneral,
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
                                onSubmitted: (_) => _enviarMensaje(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Material(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(24),
                              child: InkWell(
                                onTap: _enviarMensaje,
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

  Widget _buildMensajeBurbuja(
    String mensaje,
    bool esMio,
    String nombreRemitente,
    bool esAdmin,
    bool esEmpleado,
    String? fotoRemitente,
    DateTime fecha,
    String? fotoUrl,
  ) {
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
                                    : AppColors.textoSecundario,
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
                      // Mostrar foto si existe
                      if (fotoUrl != null && fotoUrl.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            fotoUrl,
                            width: 200,
                            height: 200,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                width: 200,
                                height: 200,
                                color: Colors.grey[300],
                                child: Center(
                                  child: CircularProgressIndicator(
                                    value: loadingProgress.expectedTotalBytes != null
                                        ? loadingProgress.cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                        : null,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                width: 200,
                                height: 200,
                                color: Colors.grey[300],
                                child: const Icon(Icons.error, color: Colors.red),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      // Mostrar texto del mensaje
                      if (mensaje.isNotEmpty)
                        Text(
                          mensaje,
                          style: TextStyle(
                            fontSize: 14,
                            color: esMio ? Colors.white : AppColors.textoPrincipal,
                            height: 1.4,
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 12, right: 12),
                  child: Text(
                    _formatearHora(fecha),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textoSecundario,
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

