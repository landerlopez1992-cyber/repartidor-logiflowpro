import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:convert';
import '../main.dart';
import '../config/app_colors.dart';
import 'login_repartidor_screen.dart';
import 'historial_pagos_completo_screen.dart';
import 'repartidor_ayuda_screen.dart';
import '../services/sync_service.dart';
import '../services/repartidor_perfil_cache_service.dart';
import '../services/sesion_offline_cleanup.dart';
import '../services/auth_error_handler.dart';
import '../services/repartidor_notificaciones_push_service.dart';
import '../services/repartidor_saldo_service.dart';

class RepartidorPerfilScreen extends StatefulWidget {
  const RepartidorPerfilScreen({super.key});

  @override
  State<RepartidorPerfilScreen> createState() => _RepartidorPerfilScreenState();
}

class _RepartidorPerfilScreenState extends State<RepartidorPerfilScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _telefonoController = TextEditingController();
  final _emailController = TextEditingController();
  
  bool _isLoading = true;
  bool _isEditing = false;
  String? _fotoPerfilUrl;
  String? _repartidorId;
  String? _tenantId;
  
  // Estadísticas semanales
  int _ordenesEntregadas = 0;
  int _ordenesPendientes = 0;
  int _cantidadRemesasEntregadas = 0;
  double _totalDineroRemesas = 0.0;
  int _totalOrdenesCobradas = 0;
  
  // Historial de pagos
  List<Map<String, dynamic>> _historialPagos = [];
  bool _cargandoHistorial = false;
  
  // Saldo del repartidor (pagos aceptados)
  double _saldo = 0.0;
  String _monedaSaldo = 'CUP';
  RealtimeChannel? _channelPagos;
  
  // Estado de conexión
  bool _isOnline = true;
  
  // Tipo de repartidor
  bool _esRecolector = false;
  
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _inicializarEstadoConexion();
    _cargarDatosPerfil();
  }

  // Inicializar estado de conexión
  void _inicializarEstadoConexion() {
    final syncService = SyncService();
    _isOnline = syncService.isOnline;
    
    // Escuchar cambios en conectividad
    syncService.addConnectivityListener((isOnline) {
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
        });
        // Si se recupera la conexión, recargar datos
        if (isOnline) {
          _cargarDatosPerfil();
        }
      }
    });
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _telefonoController.dispose();
    _emailController.dispose();
    _channelPagos?.unsubscribe();
    super.dispose();
  }

  Future<void> _cargarDatosPerfil() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        await _cargarDesdeCache();
        return;
      }

      // Verificar conexión
      final syncService = SyncService();
      final isOnline = syncService.isOnline;
      _isOnline = isOnline;

      if (isOnline) {
        try {
          // Obtener datos del repartidor usando auth_id
          final response = await supabase
              .from('usuarios')
              .select('*')
              .eq('auth_id', user.id)
              .limit(1)
              .maybeSingle();

          if (response == null) {
            print('❌ No se encontró usuario con auth_id: ${user.id}');
            setState(() {
              _isLoading = false;
            });
            return;
          }

          final tipoRepartidor = response['tipo_repartidor'] as String? ?? 'REPARTIDOR';
          final esRecolector = tipoRepartidor == 'RECOLECTOR';

          // Guardar en caché
          await RepartidorPerfilCacheService.cachePerfilData({
            'id': response['id'],
            'tenant_id': response['tenant_id'],
            'nombre': response['nombre'] ?? '',
            'telefono': response['telefono'] ?? '',
            'email': response['email'] ?? '',
            'foto_perfil': response['foto_perfil'],
          });

          setState(() {
            _repartidorId = response['id'];
            _tenantId = response['tenant_id'];
            _nombreController.text = response['nombre'] ?? '';
            _telefonoController.text = response['telefono'] ?? '';
            _emailController.text = response['email'] ?? '';
            _fotoPerfilUrl = response['foto_perfil'];
            _esRecolector = esRecolector;
            _isLoading = false;
          });

          // Solo cargar estadísticas, historial y saldo si NO es recolector
          if (!_esRecolector) {
            // Cargar estadísticas semanales
            await _cargarEstadisticasSemanales();
            
            // Cargar historial de pagos
            await _cargarHistorialPagos();
            
            // Cargar saldo del repartidor
            await _cargarSaldo();
            
            // Suscribirse a cambios en solicitudes de pago
            _suscribirseACambiosPagos();
          }
        } catch (e) {
          // Si no encuentra por auth_id, intentar por email
          if (user.email != null) {
            try {
              final response = await supabase
                  .from('usuarios')
                  .select('*')
                  .eq('email', user.email!)
                  .single();

              final tipoRepartidor = response['tipo_repartidor'] as String? ?? 'REPARTIDOR';
              final esRecolector = tipoRepartidor == 'RECOLECTOR';

              // Guardar en caché
              await RepartidorPerfilCacheService.cachePerfilData({
                'id': response['id'],
                'tenant_id': response['tenant_id'],
                'nombre': response['nombre'] ?? '',
                'telefono': response['telefono'] ?? '',
                'email': response['email'] ?? '',
                'foto_perfil': response['foto_perfil'],
              });

              setState(() {
                _repartidorId = response['id'];
                _tenantId = response['tenant_id'];
                _nombreController.text = response['nombre'] ?? '';
                _telefonoController.text = response['telefono'] ?? '';
                _emailController.text = response['email'] ?? '';
                _fotoPerfilUrl = response['foto_perfil'];
                _esRecolector = esRecolector;
                _isLoading = false;
              });

              // Solo cargar estadísticas, historial y saldo si NO es recolector
              if (!_esRecolector) {
                await _cargarEstadisticasSemanales();
                await _cargarHistorialPagos();
                await _cargarSaldo();
                _suscribirseACambiosPagos();
              }
            } catch (e2) {
              print('⚠️ Error cargando desde Supabase, usando caché: $e2');
              await _cargarDesdeCache();
            }
          } else {
            await _cargarDesdeCache();
          }
        }
      } else {
        // Sin conexión, cargar desde caché
        print('📴 Sin conexión - Cargando datos desde caché');
        await _cargarDesdeCache();
      }
    } catch (e) {
      print('❌ Error al cargar datos del perfil: $e');
      await _cargarDesdeCache();
    }
  }

  // Cargar datos desde caché local
  Future<void> _cargarDesdeCache() async {
    try {
      // Cargar datos del perfil
      final perfilCache = await RepartidorPerfilCacheService.getCachedPerfilData();
      if (perfilCache != null) {
        setState(() {
          _repartidorId = perfilCache['id']?.toString();
          _tenantId = perfilCache['tenant_id']?.toString();
          _nombreController.text = perfilCache['nombre'] ?? '';
          _telefonoController.text = perfilCache['telefono'] ?? '';
          _emailController.text = perfilCache['email'] ?? '';
          _fotoPerfilUrl = perfilCache['foto_perfil'];
          _isLoading = false;
        });
        print('💾 Datos de perfil cargados desde caché');
      } else {
        setState(() {
          _isLoading = false;
        });
      }

      // Cargar estadísticas desde caché
      await _cargarEstadisticasDesdeCache();
      
      // Cargar historial desde caché
      await _cargarHistorialDesdeCache();
      
      // Cargar saldo desde caché
      await _cargarSaldoDesdeCache();
    } catch (e) {
      print('❌ Error cargando desde caché: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Cargar estadísticas desde caché
  Future<void> _cargarEstadisticasDesdeCache() async {
    try {
      final estadisticasCache = await RepartidorPerfilCacheService.getCachedEstadisticas();
      if (estadisticasCache != null) {
        setState(() {
          _ordenesPendientes = estadisticasCache['ordenes_pendientes'] ?? 0;
          _ordenesEntregadas = estadisticasCache['ordenes_entregadas'] ?? 0;
          _cantidadRemesasEntregadas = estadisticasCache['cantidad_remesas_entregadas'] ?? 0;
          _totalDineroRemesas = (estadisticasCache['total_dinero_remesas'] ?? 0.0).toDouble();
          _totalOrdenesCobradas = estadisticasCache['total_ordenes_cobradas'] ?? 0;
        });
        print('💾 Estadísticas cargadas desde caché');
      }
    } catch (e) {
      print('❌ Error cargando estadísticas desde caché: $e');
    }
  }

  // Cargar historial desde caché
  Future<void> _cargarHistorialDesdeCache() async {
    try {
      final historialCache = await RepartidorPerfilCacheService.getCachedHistorialPagos();
      setState(() {
        _historialPagos = historialCache;
        _cargandoHistorial = false;
      });
      print('💾 Historial de pagos cargado desde caché: ${historialCache.length} registros');
    } catch (e) {
      print('❌ Error cargando historial desde caché: $e');
      setState(() {
        _cargandoHistorial = false;
      });
    }
  }

  // Cargar saldo desde caché
  Future<void> _cargarSaldoDesdeCache() async {
    try {
      final saldoCache = await RepartidorPerfilCacheService.getCachedSaldo();
      if (saldoCache != null) {
        setState(() {
          _saldo = (saldoCache['saldo'] ?? 0.0).toDouble();
          _monedaSaldo = saldoCache['moneda'] ?? 'CUP';
        });
        print('💾 Saldo cargado desde caché: \$${_saldo.toStringAsFixed(2)} $_monedaSaldo');
      }
    } catch (e) {
      print('❌ Error cargando saldo desde caché: $e');
    }
  }

  Future<void> _cargarEstadisticasSemanales() async {
    try {
      if (_repartidorId == null) return;

      print('📊 Cargando estadísticas semanales para repartidor: $_repartidorId');

      // Calcular inicio de la semana actual (lunes)
      final now = DateTime.now();
      final inicioSemana = now.subtract(Duration(days: now.weekday - 1));
      final inicioSemanaFormatted = DateTime(inicioSemana.year, inicioSemana.month, inicioSemana.day);

      print('📅 Inicio de semana: $inicioSemanaFormatted');

      // Intentar obtener estadísticas existentes de la semana actual
      final estadisticasResponse = await supabase
          .from('estadisticas_repartidor')
          .select('*')
          .eq('repartidor_id', _repartidorId!)
          .gte('inicio_semana', inicioSemanaFormatted.toIso8601String())
          .maybeSingle();

      if (estadisticasResponse != null) {
        // Usar estadísticas existentes
        print('✅ Estadísticas encontradas en BD');
        final estadisticas = {
          'ordenes_pendientes': estadisticasResponse['ordenes_pendientes'] ?? 0,
          'ordenes_entregadas': estadisticasResponse['ordenes_entregadas'] ?? 0,
          'cantidad_remesas_entregadas': estadisticasResponse['cantidad_remesas_entregadas'] ?? 0,
          'total_dinero_remesas': (estadisticasResponse['total_dinero_remesas'] ?? 0.0).toDouble(),
          'total_ordenes_cobradas': estadisticasResponse['total_ordenes_cobradas'] ?? 0,
        };
        
        // Guardar en caché
        await RepartidorPerfilCacheService.cacheEstadisticas(estadisticas);
        
        setState(() {
          _ordenesPendientes = estadisticas['ordenes_pendientes'] as int;
          _ordenesEntregadas = estadisticas['ordenes_entregadas'] as int;
          _cantidadRemesasEntregadas = estadisticas['cantidad_remesas_entregadas'] as int;
          _totalDineroRemesas = estadisticas['total_dinero_remesas'] as double;
          _totalOrdenesCobradas = estadisticas['total_ordenes_cobradas'] as int;
        });
      } else {
        // Crear nuevas estadísticas calculándolas desde las órdenes
        print('⚠️ No hay estadísticas, calculando desde órdenes...');
        await _calcularYCrearEstadisticas(inicioSemanaFormatted);
      }
    } catch (e) {
      print('❌ Error al cargar estadísticas semanales: $e');
      // Si hay error, intentar cargar desde caché
      await _cargarEstadisticasDesdeCache();
    }
  }

  Future<void> _calcularYCrearEstadisticas(DateTime inicioSemana) async {
    try {
      final finSemana = inicioSemana.add(const Duration(days: 7));

      // Órdenes pendientes (todas las asignadas que no están entregadas)
      // IMPORTANTE: Las órdenes usan repartidor_nombre, no repartidor_id
      final nombreRepartidor = _nombreController.text;
      final pendientesResponse = await supabase
          .from('ordenes')
          .select('id')
          .eq('repartidor_nombre', nombreRepartidor)
          .inFilter('estado', ['POR ENVIAR', 'EN TRANSITO']);

      // Órdenes entregadas en la semana (solo NO pagadas)
      final entregadasResponse = await supabase
          .from('ordenes')
          .select('id, tiene_remesa, cantidad_remesa, requiere_pago, pagado, monto_cobrar')
          .eq('repartidor_nombre', nombreRepartidor)
          .eq('estado', 'ENTREGADO')
          .or('pagada.is.null,pagada.eq.false') // Solo órdenes NO pagadas
          .gte('fecha_entrega', inicioSemana.toIso8601String())
          .lt('fecha_entrega', finSemana.toIso8601String());

      final ordenesPendientes = (pendientesResponse as List).length;
      final ordenesEntregadas = (entregadasResponse as List).length;

      int cantidadRemesas = 0;
      double totalRemesas = 0.0;
      int ordenesCobradas = 0;
      double totalCobrado = 0.0;

      for (var orden in entregadasResponse) {
        // Contar remesas
        if (orden['tiene_remesa'] == true) {
          cantidadRemesas++;
          if (orden['cantidad_remesa'] != null) {
            totalRemesas += (orden['cantidad_remesa'] as num).toDouble();
          }
        }

        // Contar cobros
        if (orden['requiere_pago'] == true && orden['pagado'] == true) {
          ordenesCobradas++;
          if (orden['monto_cobrar'] != null) {
            totalCobrado += (orden['monto_cobrar'] as num).toDouble();
          }
        }
      }

      final salario = ordenesEntregadas * 5.0;

      // Crear registro de estadísticas
      await supabase.from('estadisticas_repartidor').insert({
        'repartidor_id': _repartidorId,
        'tenant_id': _tenantId,
        'inicio_semana': inicioSemana.toIso8601String(),
        'fin_semana': finSemana.toIso8601String(),
        'ordenes_pendientes': ordenesPendientes,
        'ordenes_entregadas': ordenesEntregadas,
        'cantidad_remesas_entregadas': cantidadRemesas,
        'total_dinero_remesas': totalRemesas,
        'total_ordenes_cobradas': ordenesCobradas,
        'total_dinero_cobrado': totalCobrado,
        'salario_ganado': salario,
      });

      setState(() {
        _ordenesPendientes = ordenesPendientes;
        _ordenesEntregadas = ordenesEntregadas;
        _cantidadRemesasEntregadas = cantidadRemesas;
        _totalDineroRemesas = totalRemesas;
        _totalOrdenesCobradas = ordenesCobradas;
      });

      print('✅ Estadísticas creadas y guardadas');
    } catch (e) {
      print('❌ Error al calcular y crear estadísticas: $e');
    }
  }

  Future<void> _calcularEstadisticasManualmente() async {
    try {
      if (_repartidorId == null) return;

      final now = DateTime.now();
      final inicioSemana = now.subtract(Duration(days: now.weekday - 1));
      final inicioSemanaFormatted = DateTime(inicioSemana.year, inicioSemana.month, inicioSemana.day);
      final finSemana = inicioSemanaFormatted.add(const Duration(days: 7));

      // Órdenes pendientes
      final nombreRepartidor = _nombreController.text;
      final pendientesResponse = await supabase
          .from('ordenes')
          .select('id')
          .eq('repartidor_nombre', nombreRepartidor)
          .inFilter('estado', ['POR ENVIAR', 'EN TRANSITO']);

      // Órdenes entregadas en la semana (solo NO pagadas)
      final entregadasResponse = await supabase
          .from('ordenes')
          .select('id, tiene_remesa, cantidad_remesa, requiere_pago, pagado, monto_cobrar')
          .eq('repartidor_nombre', nombreRepartidor)
          .eq('estado', 'ENTREGADO')
          .or('pagada.is.null,pagada.eq.false') // Solo órdenes NO pagadas
          .gte('fecha_entrega', inicioSemanaFormatted.toIso8601String())
          .lt('fecha_entrega', finSemana.toIso8601String());

      final ordenesPendientes = (pendientesResponse as List).length;
      final ordenesEntregadas = (entregadasResponse as List).length;

      int cantidadRemesas = 0;
      double totalRemesas = 0.0;
      int ordenesCobradas = 0;

      for (var orden in entregadasResponse) {
        if (orden['tiene_remesa'] == true) {
          cantidadRemesas++;
          if (orden['cantidad_remesa'] != null) {
            totalRemesas += (orden['cantidad_remesa'] as num).toDouble();
          }
        }

        if (orden['requiere_pago'] == true && orden['pagado'] == true) {
          ordenesCobradas++;
        }
      }

      setState(() {
        _ordenesPendientes = ordenesPendientes;
        _ordenesEntregadas = ordenesEntregadas;
        _cantidadRemesasEntregadas = cantidadRemesas;
        _totalDineroRemesas = totalRemesas;
        _totalOrdenesCobradas = ordenesCobradas;
      });
    } catch (e) {
      print('❌ Error al calcular estadísticas manualmente: $e');
    }
  }

  Future<void> _seleccionarFoto() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (image != null) {
        // Subir imagen a Supabase Storage
        final file = File(image.path);
        final fileName = '${_repartidorId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        
        await supabase.storage
            .from('fotos-perfil')
            .upload(fileName, file);

        // Obtener URL pública
        final publicUrl = supabase.storage
            .from('fotos-perfil')
            .getPublicUrl(fileName);

        setState(() {
          _fotoPerfilUrl = publicUrl;
        });

        // Actualizar en la base de datos
        await supabase
            .from('usuarios')
            .update({'foto_perfil': publicUrl})
            .eq('id', _repartidorId!);

        _mostrarMensaje('Foto actualizada correctamente', Colors.green);
      }
    } catch (e) {
      _mostrarMensaje('Error al actualizar foto: $e', Colors.red);
    }
  }

  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      await supabase
          .from('usuarios')
          .update({
            'nombre': _nombreController.text.trim(),
            'telefono': _telefonoController.text.trim(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', _repartidorId!);

      setState(() {
        _isEditing = false;
      });

      _mostrarMensaje('Perfil actualizado correctamente', Colors.green);
    } catch (e) {
      _mostrarMensaje('Error al actualizar perfil: $e', Colors.red);
    }
  }

  void _mostrarMensaje(String mensaje, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: color,
        duration: const Duration(seconds: 3),
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
          'Mi Perfil',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (!_isEditing) ...[
            IconButton(
              icon: const Icon(Icons.help_outline, color: Colors.white),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const RepartidorAyudaScreen(),
                  ),
                );
              },
              tooltip: 'Ayuda',
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white),
              onPressed: () {
                setState(() {
                  _isEditing = true;
                });
              },
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        // Foto de perfil
                        _buildFotoPerfil(),
                        const SizedBox(height: 24),

                        // Solo mostrar estadísticas, pagos y saldo si NO es recolector
                        if (!_esRecolector) ...[
                          // Estadísticas
                          _buildEstadisticas(),
                          const SizedBox(height: 24),

                          // Botón Solicitar Pago
                          _buildBotonSolicitarPago(),
                          const SizedBox(height: 24),

                          // Historial de Pagos
                          _buildHistorialPagos(),
                          const SizedBox(height: 24),
                        ],

                        // Información personal (siempre visible)
                        _buildInformacionPersonal(),
                        const SizedBox(height: 24),

                        // Botones de acción
                        if (_isEditing) _buildBotonesAccion(),
                        
                        // Botón de cambiar contraseña
                        if (!_isEditing) ...[
                          const SizedBox(height: 16),
                          _buildBotonCambiarContrasena(),
                        ],
                        
                        // Botón de cerrar sesión
                        if (!_isEditing) ...[
                          const SizedBox(height: 16),
                          _buildBotonCerrarSesion(),
                          const SizedBox(height: 100), // Espacio adicional al final para scroll
                        ],
                      ],
                    ),
                  ),
                ),
                // Indicador de modo offline
                if (!_isOnline)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: const BoxDecoration(
                        color: Color(0xFF1976D2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.cloud_off,
                            color: Color(0xFFFF9800),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Sin conexión a internet - Mostrando datos en caché',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildFotoPerfil() {
    return Column(
      children: [
        Center(
      child: Stack(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF4CAF50),
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: CircleAvatar(
              radius: 60,
              backgroundColor: const Color(0xFF4CAF50),
              backgroundImage: _fotoPerfilUrl != null
                  ? NetworkImage(_fotoPerfilUrl!)
                  : null,
              child: _fotoPerfilUrl == null
                  ? const Icon(
                      Icons.person,
                      size: 60,
                      color: Colors.white,
                    )
                  : null,
            ),
          ),
          if (_isEditing)
            Positioned(
              bottom: 0,
              right: 0,
              child: GestureDetector(
                onTap: _seleccionarFoto,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF9800),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
        ],
      ),
        ),
        const SizedBox(height: 12),
        // Saldo del repartidor
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF4CAF50),
              width: 1.5,
            ),
          ),
          child: Text(
            'Saldo ${_saldo.toStringAsFixed(2)} $_monedaSaldo',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF4CAF50),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEstadisticas() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Estadísticas Semanales',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textoPrincipal,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Esta semana',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF4CAF50),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Lista compacta de estadísticas
          _buildStatRow(
            'Órdenes Entregadas',
            _ordenesEntregadas.toString(),
            Icons.check_circle,
            const Color(0xFF2196F3),
          ),
          const Divider(height: 16, thickness: 1, color: Color(0xFFF0F0F0)),
          
          _buildStatRow(
            'Órdenes Pendientes',
            _ordenesPendientes.toString(),
            Icons.pending_actions,
            const Color(0xFFFF9800),
          ),
          const Divider(height: 16, thickness: 1, color: Color(0xFFF0F0F0)),
          
          _buildStatRow(
            'Remesas Entregadas',
            _cantidadRemesasEntregadas.toString(),
            Icons.card_giftcard,
            const Color(0xFF9C27B0),
          ),
          const Divider(height: 16, thickness: 1, color: Color(0xFFF0F0F0)),
          
          _buildStatRow(
            'Total Remesas',
            '\$${_totalDineroRemesas.toStringAsFixed(2)}',
            Icons.monetization_on,
            const Color(0xFF1976D2),
          ),
          const Divider(height: 16, thickness: 1, color: Color(0xFFF0F0F0)),
          
          _buildStatRow(
            'Cobros Realizados',
            _totalOrdenesCobradas.toString(),
            Icons.payment,
            const Color(0xFFE91E63),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value, IconData icon, Color color) {
    return Row(
      children: [
        // Icono simple sin contenedor
        Icon(
          icon,
          color: color,
          size: 24,
        ),
        const SizedBox(width: 12),
        // Etiqueta
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF666666),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        // Valor
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildInformacionPersonal() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Información Personal',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF2C2C2C),
            ),
          ),
          const SizedBox(height: 16),
          
          // Nombre
          TextFormField(
            controller: _nombreController,
            enabled: _isEditing,
            decoration: InputDecoration(
              labelText: 'Nombre completo',
              prefixIcon: const Icon(Icons.person, color: Color(0xFF4CAF50)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF4CAF50)),
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'El nombre es requerido';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Teléfono
          TextFormField(
            controller: _telefonoController,
            enabled: _isEditing,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Teléfono',
              prefixIcon: const Icon(Icons.phone, color: Color(0xFF4CAF50)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF4CAF50)),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Email (solo lectura)
          TextFormField(
            controller: _emailController,
            enabled: false,
            decoration: InputDecoration(
              labelText: 'Email',
              prefixIcon: const Icon(Icons.email, color: Color(0xFF666666)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBotonesAccion() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () {
              setState(() {
                _isEditing = false;
                _cargarDatosPerfil(); // Recargar datos originales
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF666666),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Cancelar'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton(
            onPressed: _guardarCambios,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Guardar'),
          ),
        ),
      ],
    );
  }

  Widget _buildBotonCambiarContrasena() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: OutlinedButton.icon(
        onPressed: _mostrarDialogoCambiarContrasena,
        icon: const Icon(Icons.lock, size: 20),
        label: const Text(
          'Cambiar Contraseña',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF37474F),
          side: const BorderSide(color: Color(0xFF37474F), width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildBotonCerrarSesion() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ElevatedButton.icon(
        onPressed: _mostrarConfirmacionLogout,
        icon: const Icon(Icons.logout, size: 20),
        label: const Text(
          'Cerrar Sesión',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFDC2626),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
      ),
    );
  }

  Future<void> _mostrarDialogoCambiarContrasena() async {
    final contrasenaActualController = TextEditingController();
    final nuevaContrasenaController = TextEditingController();
    final confirmarContrasenaController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool _mostrandoContrasena = false;
    bool _mostrandoNuevaContrasena = false;
    bool _mostrandoConfirmarContrasena = false;
    bool _isLoading = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: const Color(0xFFFFFFFF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.lock, color: Color(0xFF37474F), size: 24),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Cambiar Contraseña',
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
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Contraseña actual
                  TextFormField(
                    controller: contrasenaActualController,
                    obscureText: !_mostrandoContrasena,
                    decoration: InputDecoration(
                      labelText: 'Contraseña Actual',
                      prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF37474F)),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _mostrandoContrasena ? Icons.visibility : Icons.visibility_off,
                          color: const Color(0xFF666666),
                        ),
                        onPressed: () {
                          setStateDialog(() {
                            _mostrandoContrasena = !_mostrandoContrasena;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF37474F)),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'La contraseña actual es requerida';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Nueva contraseña
                  TextFormField(
                    controller: nuevaContrasenaController,
                    obscureText: !_mostrandoNuevaContrasena,
                    decoration: InputDecoration(
                      labelText: 'Nueva Contraseña',
                      prefixIcon: const Icon(Icons.lock, color: Color(0xFF37474F)),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _mostrandoNuevaContrasena ? Icons.visibility : Icons.visibility_off,
                          color: const Color(0xFF666666),
                        ),
                        onPressed: () {
                          setStateDialog(() {
                            _mostrandoNuevaContrasena = !_mostrandoNuevaContrasena;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF37474F)),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'La nueva contraseña es requerida';
                      }
                      if (value.length < 6) {
                        return 'La contraseña debe tener al menos 6 caracteres';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Confirmar nueva contraseña
                  TextFormField(
                    controller: confirmarContrasenaController,
                    obscureText: !_mostrandoConfirmarContrasena,
                    decoration: InputDecoration(
                      labelText: 'Confirmar Nueva Contraseña',
                      prefixIcon: const Icon(Icons.lock_reset, color: Color(0xFF37474F)),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _mostrandoConfirmarContrasena ? Icons.visibility : Icons.visibility_off,
                          color: const Color(0xFF666666),
                        ),
                        onPressed: () {
                          setStateDialog(() {
                            _mostrandoConfirmarContrasena = !_mostrandoConfirmarContrasena;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: Color(0xFF37474F)),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor confirma la nueva contraseña';
                      }
                      if (value != nuevaContrasenaController.text) {
                        return 'Las contraseñas no coinciden';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: _isLoading ? null : () {
                Navigator.of(context).pop();
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF666666),
                side: const BorderSide(color: Color(0xFFE0E0E0), width: 1.5),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Cancelar',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: _isLoading ? null : () async {
                if (!formKey.currentState!.validate()) return;
                
                setStateDialog(() {
                  _isLoading = true;
                });
                
                try {
                  // Verificar contraseña actual reautenticando
                  final user = supabase.auth.currentUser;
                  if (user == null) {
                    throw Exception('No hay usuario autenticado');
                  }
                  
                  // Reautenticar con la contraseña actual
                  await supabase.auth.signInWithPassword(
                    email: user.email!,
                    password: contrasenaActualController.text,
                  );
                  
                  // Actualizar contraseña
                  await supabase.auth.updateUser(
                    UserAttributes(
                      password: nuevaContrasenaController.text,
                    ),
                  );
                  
                  if (context.mounted) {
                    Navigator.of(context).pop();
                    _mostrarMensaje('Contraseña actualizada exitosamente', Colors.green);
                  }
                } catch (e) {
                  print('❌ Error técnico al cambiar contraseña: $e');
                  if (context.mounted) {
                    // Usar el manejador de errores para obtener mensajes amigables
                    String mensajeError = AuthErrorHandler.getFriendlyErrorMessage(e);
                    
                    // Mensajes específicos para cambio de contraseña
                    final errorString = e.toString().toLowerCase();
                    if (errorString.contains('invalid login credentials') ||
                        errorString.contains('invalid_credentials')) {
                      mensajeError = 'La contraseña actual es incorrecta. Por favor, verifica e intenta nuevamente.';
                    } else if (errorString.contains('password should be at least') ||
                               errorString.contains('weak password')) {
                      mensajeError = 'La nueva contraseña debe tener al menos 6 caracteres.';
                    } else if (errorString.contains('same password') ||
                               errorString.contains('new password same')) {
                      mensajeError = 'La nueva contraseña debe ser diferente a la contraseña actual.';
                    }
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(mensajeError),
                        backgroundColor: const Color(0xFFDC2626),
                        duration: const Duration(seconds: 4),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    );
                  }
                } finally {
                  if (context.mounted) {
                    setStateDialog(() {
                      _isLoading = false;
                    });
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF37474F),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Cambiar Contraseña',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _mostrarConfirmacionLogout() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Color(0xFFDC2626), size: 24),
            SizedBox(width: 12),
            Text(
              'Cerrar Sesión',
              style: TextStyle(
                color: Color(0xFF2C2C2C),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: const Text(
          '¿Estás seguro de que quieres cerrar sesión?',
          style: TextStyle(
            color: Color(0xFF666666),
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancelar',
              style: TextStyle(
                color: Color(0xFF666666),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Cerrar Sesión',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      try {
        print('🚪 Cerrando sesión...');
        
        // 🔒 CRÍTICO: Limpiar TODOS los cachés del usuario antes de cerrar sesión
        // Esto previene que el próximo usuario vea datos del anterior
        final user = supabase.auth.currentUser;
        if (user != null) {
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('cached_repartidor_nombre_${user.id}');
            await prefs.remove('cached_repartidor_master_${user.id}');
            await prefs.remove('cached_repartidor_tipo_${user.id}');
            await prefs.remove('cached_repartidor_foto_${user.id}');
            await prefs.remove('cached_tenant_id_${user.id}'); // 🔒 CRÍTICO: Limpiar tenant_id
            await prefs.remove('cached_user_data_${user.id}');
            
            // 🔒 Cola de sync, medios pendientes y órdenes en caché
            await SesionOfflineCleanup.limpiarTodo();
            
            print('🧹 Caché del usuario limpiado correctamente');
          } catch (cacheError) {
            print('⚠️ Error limpiando caché: $cacheError');
          }
        }

        await RepartidorNotificacionesPushService.instance.limpiarAlCerrarSesion();
        
        await supabase.auth.signOut();
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => const LoginRepartidorScreen(),
            ),
            (route) => false,
          );
        }
      } catch (e) {
        print('❌ Error al cerrar sesión: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al cerrar sesión: $e'),
              backgroundColor: const Color(0xFFDC2626),
            ),
          );
        }
      }
    }
  }

  Future<void> _cargarHistorialPagos() async {
    if (_repartidorId == null) return;

    setState(() {
      _cargandoHistorial = true;
    });

    // Verificar conexión
    final syncService = SyncService();
    final isOnline = syncService.isOnline;

    if (isOnline) {
      try {
        final response = await supabase
            .from('solicitudes_pago_repartidores')
            .select('*')
            .eq('repartidor_id', _repartidorId!)
            .order('fecha_solicitud', ascending: false);

        final historial = List<Map<String, dynamic>>.from(response);
        
        // Guardar en caché
        await RepartidorPerfilCacheService.cacheHistorialPagos(historial);

        setState(() {
          _historialPagos = historial;
          _cargandoHistorial = false;
        });
      } catch (e) {
        print('⚠️ Error cargando historial desde Supabase, usando caché: $e');
        await _cargarHistorialDesdeCache();
      }
    } else {
      // Sin conexión, cargar desde caché
      print('📴 Sin conexión - Cargando historial desde caché');
      await _cargarHistorialDesdeCache();
    }
  }

  Widget _buildBotonSolicitarPago() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: _mostrarModalSolicitarPago,
          icon: const Icon(Icons.payment, size: 24),
          label: const Text(
            'Solicitar Pago',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF9800),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
        ),
      ),
    );
  }

  Future<void> _mostrarModalSolicitarPago() async {
    final montoController = TextEditingController(
      text: _saldo > 0 ? _saldo.toStringAsFixed(2) : '',
    );
    final kilometrosController = TextEditingController();
    String monedaSeleccionada = _monedaSaldo;
    
    // Obtener órdenes entregadas NO pagadas en tiempo real
    List<Map<String, dynamic>> ordenesEntregadas = [];
    int totalOrdenes = 0;
    
    try {
      final nombreRepartidor = _nombreController.text.trim();
      
      // IMPORTANTE: Solo contar órdenes ENTREGADAS (no pendientes) y NO pagadas
      // Esto previene que el repartidor cobre 2 veces por las mismas órdenes
      
      print('🔍 Buscando órdenes ENTREGADAS y NO pagadas para: $nombreRepartidor');
      print('🔍 Repartidor ID: $_repartidorId');
      
      // Obtener SOLO órdenes realmente ENTREGADAS (excluir ATRASADO, CANCELADA, etc.)
      // IMPORTANTE: Solo contar órdenes con estado = 'ENTREGADO' y que tengan fecha_entrega
      // CRÍTICO: Filtrar órdenes NO pagadas directamente en la consulta
      // NOTA: Hacer JOIN con emisores para obtener el nombre del emisor
      final todasLasOrdenes = await supabase
          .from('ordenes')
          .select('id, numero_orden, emisor_id, receptor, fecha_entrega, pagada, solicitud_pago_id, estado, fecha_estimada_entrega, emisores!left(nombre)')
          .eq('repartidor_nombre', nombreRepartidor)
          .eq('estado', 'ENTREGADO') // SOLO órdenes realmente ENTREGADAS (no ATRASADO, no CANCELADA)
          .not('fecha_entrega', 'is', null) // Debe tener fecha_entrega (confirmación de entrega real)
          .or('pagada.is.null,pagada.eq.false') // SOLO órdenes NO pagadas (null o false)
          .order('fecha_entrega', ascending: false);
      
      print('📦 Total de órdenes ENTREGADAS encontradas (sin filtrar): ${todasLasOrdenes.length}');
      
      // PRIMERO: Obtener todas las solicitudes ACEPTADAS del repartidor para excluir sus órdenes
      final solicitudesAceptadas = await supabase
          .from('solicitudes_pago_repartidores')
          .select('ordenes_incluidas')
          .eq('repartidor_id', _repartidorId!)
          .eq('estado', 'ACEPTADO');
      
      print('🔍 Solicitudes ACEPTADAS encontradas: ${solicitudesAceptadas.length}');
      
      // Extraer todos los IDs de órdenes que están en solicitudes ACEPTADAS
      final Set<String> ordenesEnPagosAceptados = {};
      for (var solicitud in solicitudesAceptadas) {
        final ordenesIncluidas = solicitud['ordenes_incluidas'] as List<dynamic>?;
        if (ordenesIncluidas != null) {
          for (var ordenId in ordenesIncluidas) {
            ordenesEnPagosAceptados.add(ordenId.toString());
          }
        }
      }
      
      print('🔍 Órdenes en pagos ACEPTADOS: ${ordenesEnPagosAceptados.length}');
      if (ordenesEnPagosAceptados.isNotEmpty) {
        print('🔍 IDs de órdenes excluidas: $ordenesEnPagosAceptados');
      }
      
      // SEGUNDO: Filtrar órdenes que NO estén pagadas Y NO estén en solicitudes ACEPTADAS
      // También verificar que NO sea una orden atrasada (fecha_estimada_entrega pasada pero no entregada)
      final ordenesFiltradas = <Map<String, dynamic>>[];
      
      for (var orden in todasLasOrdenes) {
        final ordenId = orden['id']?.toString() ?? '';
        final pagada = orden['pagada'] == true;
        final solicitudPagoId = orden['solicitud_pago_id']?.toString();
        final estado = orden['estado']?.toString() ?? '';
        final fechaEntrega = orden['fecha_entrega'];
        print('🔍 Orden ${orden['numero_orden']} (ID: $ordenId): estado=$estado, pagada=$pagada, solicitud_pago_id=$solicitudPagoId');
        
        // Verificar que el estado sea realmente ENTREGADO (doble verificación)
        if (estado != 'ENTREGADO') {
          print('⚠️ Orden ${orden['numero_orden']} excluida: estado=$estado (no es ENTREGADO)');
          continue;
        }
        
        // Verificar que tenga fecha_entrega (confirmación de entrega real)
        if (fechaEntrega == null) {
          print('⚠️ Orden ${orden['numero_orden']} excluida: no tiene fecha_entrega');
          continue;
        }
        
        // Si la orden está marcada como pagada, NO incluirla
        if (pagada) {
          print('⚠️ Orden ${orden['numero_orden']} excluida: está marcada como pagada');
          continue;
        }
        
        // Si la orden está en una solicitud ACEPTADA, NO incluirla
        if (ordenesEnPagosAceptados.contains(ordenId)) {
          print('⚠️ Orden ${orden['numero_orden']} excluida: está en solicitud ACEPTADA');
          continue;
        }
        
        // Si llegamos aquí, la orden es válida
        ordenesFiltradas.add(orden);
        print('✅ Orden ${orden['numero_orden']} incluida');
      }
      
      ordenesEntregadas = ordenesFiltradas;
      totalOrdenes = ordenesEntregadas.length;
      print('📦 Total de órdenes entregadas encontradas (después de filtrar): $totalOrdenes');
    } catch (e) {
      print('❌ Error obteniendo órdenes entregadas: $e');
      totalOrdenes = _ordenesEntregadas; // Usar el valor cacheado como fallback
      print('📦 Usando valor cacheado: $totalOrdenes');
    }

    final resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: const Color(0xFFFFFFFF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.payment, color: Color(0xFFFF9800), size: 28),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Solicitar Pago',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2C2C2C),
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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF4CAF50)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet, color: Color(0xFF4CAF50), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Saldo disponible: \$${_saldo.toStringAsFixed(2)} $_monedaSaldo',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2E7D32),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1976D2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Color(0xFF1976D2), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          totalOrdenes == 0 
                            ? 'Total de órdenes entregadas: 0 (puedes solicitar pago por kilómetros recorridos)'
                            : 'Total de órdenes entregadas: $totalOrdenes',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1976D2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (ordenesEntregadas.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Órdenes incluidas en esta solicitud:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF2C2C2C),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: ordenesEntregadas.length,
                      itemBuilder: (context, index) {
                        final orden = ordenesEntregadas[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4CAF50),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Orden #${orden['numero_orden'] ?? orden['id']}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF2C2C2C),
                                      ),
                                    ),
                                    Text(
                                      '${(orden['emisores'] as Map<String, dynamic>?)?['nombre'] ?? 'Sin emisor'} → ${orden['receptor'] ?? ''}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF666666),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Text(
                      'Monto a solicitar:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2C2C2C),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      '*',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: montoController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: 'Ej: 30.00',
                    prefixIcon: const Icon(Icons.attach_money, color: Color(0xFFFF9800)),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFFF9800)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Text(
                      'Kilómetros recorridos:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2C2C2C),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      '*',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: kilometrosController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: 'Ej: 150.5',
                    prefixIcon: const Icon(Icons.directions_car, color: Color(0xFFFF9800)),
                    suffixText: 'km',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFFF9800)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Moneda:',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2C2C2C),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('CUP'),
                        selected: monedaSeleccionada == 'CUP',
                        onSelected: (selected) {
                          if (selected) {
                            setStateDialog(() {
                              monedaSeleccionada = 'CUP';
                            });
                          }
                        },
                        selectedColor: const Color(0xFFFF9800),
                        labelStyle: TextStyle(
                          color: monedaSeleccionada == 'CUP' ? Colors.white : const Color(0xFF666666),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('USD'),
                        selected: monedaSeleccionada == 'USD',
                        onSelected: (selected) {
                          if (selected) {
                            setStateDialog(() {
                              monedaSeleccionada = 'USD';
                            });
                          }
                        },
                        selectedColor: const Color(0xFFFF9800),
                        labelStyle: TextStyle(
                          color: monedaSeleccionada == 'USD' ? Colors.white : const Color(0xFF666666),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                // Cerrar el modal de forma segura
                try {
                  Navigator.of(context).pop(false);
                } catch (e) {
                  print('❌ Error cerrando modal: $e');
                }
              },
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF666666),
              ),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                final monto = double.tryParse(montoController.text.trim());
                final kilometros = double.tryParse(kilometrosController.text.trim());
                
                if (monto == null || monto <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Por favor ingresa un monto válido'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                if (monto > _saldo + 0.001) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'El monto no puede superar tu saldo (\$${_saldo.toStringAsFixed(2)} $_monedaSaldo)',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                
                // Validar kilómetros (obligatorio)
                if (kilometros == null || kilometros <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Por favor ingresa los kilómetros recorridos'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                
                Navigator.of(context).pop(true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF9800),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Solicitar Pago'),
            ),
          ],
        ),
      ),
    );

    // Hacer dispose de los controllers de forma segura
    try {
      if (resultado == true) {
        // Leer los valores antes de hacer dispose
        final montoTexto = montoController.text.trim();
        final kilometrosTexto = kilometrosController.text.trim();
        
        // Solo procesar si ambos campos tienen contenido
        if (montoTexto.isNotEmpty && kilometrosTexto.isNotEmpty) {
          final monto = double.tryParse(montoTexto);
          final kilometros = double.tryParse(kilometrosTexto);
          // Validar que ambos campos estén completos (ya se validaron en el modal, pero verificamos de nuevo)
          if (monto != null && monto > 0 && kilometros != null && kilometros > 0 && _repartidorId != null && _tenantId != null) {
            await _solicitarPago(monto, monedaSeleccionada, kilometros);
          } else {
            if (mounted) {
              _mostrarMensaje('Error: Todos los campos son obligatorios', Colors.red);
            }
          }
        }
      }
    } catch (e) {
      print('❌ Error procesando solicitud de pago: $e');
    } finally {
      // Siempre hacer dispose de los controllers de forma segura
      try {
        montoController.dispose();
      } catch (e) {
        print('⚠️ Error haciendo dispose de montoController: $e');
      }
      try {
        kilometrosController.dispose();
      } catch (e) {
        print('⚠️ Error haciendo dispose de kilometrosController: $e');
      }
    }
  }

  Future<void> _solicitarPago(double monto, String moneda, double kilometros) async {
    if (_repartidorId == null || _tenantId == null) {
      _mostrarMensaje('Error: No se pudo obtener información del repartidor', Colors.red);
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      final nombreRepartidor = _nombreController.text.trim();
      
      // IMPORTANTE: Obtener SOLO órdenes ENTREGADAS (no pendientes) y NO pagadas
      // Esto previene que el repartidor cobre 2 veces por las mismas órdenes
      
      print('🔍 Obteniendo IDs de órdenes ENTREGADAS y NO pagadas para solicitud de pago');
      print('🔍 Repartidor: $nombreRepartidor, ID: $_repartidorId');
      
      // Obtener SOLO órdenes realmente ENTREGADAS (excluir ATRASADO, CANCELADA, etc.)
      // IMPORTANTE: Solo contar órdenes con estado = 'ENTREGADO' y que tengan fecha_entrega
      // CRÍTICO: Filtrar órdenes NO pagadas directamente en la consulta
      final todasLasOrdenes = await supabase
          .from('ordenes')
          .select('id, pagada, estado, fecha_entrega')
          .eq('repartidor_nombre', nombreRepartidor)
          .eq('estado', 'ENTREGADO') // SOLO órdenes realmente ENTREGADAS (no ATRASADO, no CANCELADA)
          .not('fecha_entrega', 'is', null) // Debe tener fecha_entrega (confirmación de entrega real)
          .or('pagada.is.null,pagada.eq.false'); // SOLO órdenes NO pagadas (null o false)
      
      print('📦 Total de órdenes ENTREGADAS encontradas (sin filtrar): ${todasLasOrdenes.length}');
      
      // PRIMERO: Obtener todas las solicitudes ACEPTADAS del repartidor para excluir sus órdenes
      final solicitudesAceptadas = await supabase
          .from('solicitudes_pago_repartidores')
          .select('ordenes_incluidas')
          .eq('repartidor_id', _repartidorId!)
          .eq('estado', 'ACEPTADO');
      
      print('🔍 Solicitudes ACEPTADAS encontradas: ${solicitudesAceptadas.length}');
      
      // Extraer todos los IDs de órdenes que están en solicitudes ACEPTADAS
      final Set<String> ordenesEnPagosAceptados = {};
      for (var solicitud in solicitudesAceptadas) {
        final ordenesIncluidas = solicitud['ordenes_incluidas'] as List<dynamic>?;
        if (ordenesIncluidas != null) {
          for (var ordenId in ordenesIncluidas) {
            ordenesEnPagosAceptados.add(ordenId.toString());
          }
        }
      }
      
      print('🔍 Órdenes en pagos ACEPTADOS: ${ordenesEnPagosAceptados.length}');
      
      // SEGUNDO: Filtrar órdenes que NO estén pagadas Y NO estén en solicitudes ACEPTADAS
      // También verificar que NO sea una orden atrasada
      List<String> ordenesIds = [];
      for (var orden in todasLasOrdenes) {
        final ordenId = orden['id']?.toString() ?? '';
        final pagada = orden['pagada'] == true;
        final estado = orden['estado']?.toString() ?? '';
        final fechaEntrega = orden['fecha_entrega'];
        
        // Verificar que el estado sea realmente ENTREGADO (doble verificación)
        if (estado != 'ENTREGADO') {
          print('⚠️ Orden $ordenId excluida: estado=$estado (no es ENTREGADO)');
          continue;
        }
        
        // Verificar que tenga fecha_entrega (confirmación de entrega real)
        if (fechaEntrega == null) {
          print('⚠️ Orden $ordenId excluida: no tiene fecha_entrega');
          continue;
        }
        
        // Si la orden está marcada como pagada, NO incluirla
        if (pagada) {
          print('⚠️ Orden $ordenId excluida: está marcada como pagada');
          continue;
        }
        
        // Si la orden está en una solicitud ACEPTADA, NO incluirla
        if (ordenesEnPagosAceptados.contains(ordenId)) {
          print('⚠️ Orden $ordenId excluida: está en solicitud ACEPTADA');
          continue;
        }
        
        // Si llegamos aquí, la orden es válida
        ordenesIds.add(ordenId);
        print('✅ Orden $ordenId incluida');
      }
      
      print('📦 Total de órdenes válidas para solicitud: ${ordenesIds.length}');

      print('📦 Órdenes incluidas en la solicitud: ${ordenesIds.length}');
      print('📦 IDs: $ordenesIds');
      print('🚗 Kilómetros recorridos: $kilometros');

      final insertData = {
        'repartidor_id': _repartidorId,
        'repartidor_nombre': nombreRepartidor,
        'tenant_id': _tenantId,
        'monto': monto,
        'moneda': moneda,
        'estado': 'PENDIENTE',
        'total_ordenes_entregadas': ordenesIds.length,
        'ordenes_incluidas': ordenesIds, // Guardar array de IDs
        'kilometros_recorridos': kilometros, // Kilómetros son obligatorios
      };

      if (monto > _saldo + 0.001) {
        _mostrarMensaje(
          'El monto no puede ser mayor que tu saldo (\$${_saldo.toStringAsFixed(2)} $_monedaSaldo)',
          Colors.red,
        );
        return;
      }

      final rpc = await supabase.rpc(
        'repartidor_crear_solicitud_pago',
        params: {
          'p_repartidor_id': _repartidorId,
          'p_monto': monto,
          'p_moneda': moneda,
          'p_total_ordenes': ordenesIds.length,
          'p_ordenes_incluidas': ordenesIds,
          'p_kilometros_recorridos': kilometros,
          'p_repartidor_nombre': nombreRepartidor,
          'p_tenant_id': _tenantId,
        },
      );

      final map = rpc is Map ? Map<String, dynamic>.from(rpc) : <String, dynamic>{};
      if (map['ok'] != true) {
        final err = map['error']?.toString() ?? 'error';
        if (err == 'saldo_insuficiente') {
          final disp = map['saldo'];
          final s = disp is num ? disp.toDouble() : _saldo;
          _mostrarMensaje(
            'Saldo insuficiente. Disponible: \$${s.toStringAsFixed(2)} $moneda',
            Colors.red,
          );
        } else {
          _mostrarMensaje('No se pudo crear la solicitud ($err)', Colors.red);
        }
        return;
      }

      _mostrarMensaje('Solicitud de pago enviada correctamente por ${ordenesIds.length} órdenes', Colors.green);
      await _cargarSaldo();
      await _cargarHistorialPagos();
      
      // No cerrar la pantalla, solo mostrar mensaje
      // El saldo se actualizará automáticamente vía suscripción Realtime
    } catch (e) {
      print('❌ Error solicitando pago: $e');
      _mostrarMensaje('Error al solicitar pago: $e', Colors.red);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Widget _buildHistorialPagos() {
    return InkWell(
      onTap: () {
        if (_repartidorId != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => HistorialPagosCompletoScreen(
                repartidorId: _repartidorId!,
                repartidorNombre: _nombreController.text.trim(),
              ),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Historial de Pagos',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textoPrincipal,
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Color(0xFF666666),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_cargandoHistorial)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_historialPagos.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'No hay solicitudes de pago',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF666666),
                    ),
                  ),
                ),
              )
            else
              ..._historialPagos.take(2).map((pago) => _buildItemHistorialPago(pago)),
            if (_historialPagos.length > 2)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Center(
                  child: Text(
                    'Toca cualquier tarjeta para ver más (${_historialPagos.length} total)',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFFF9800),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemHistorialPago(Map<String, dynamic> pago) {
    final estado = pago['estado']?.toString() ?? 'PENDIENTE';
    final monto = pago['monto']?.toDouble() ?? 0.0;
    final moneda = pago['moneda']?.toString() ?? 'CUP';
    final fechaSolicitud = pago['fecha_solicitud'] != null
        ? DateTime.parse(pago['fecha_solicitud'])
        : null;
    final fechaAceptacion = pago['fecha_aceptacion'] != null
        ? DateTime.parse(pago['fecha_aceptacion'])
        : null;

    Color colorEstado;
    IconData iconoEstado;
    String textoEstado;

    switch (estado) {
      case 'PENDIENTE':
        colorEstado = const Color(0xFFFF9800);
        iconoEstado = Icons.pending;
        textoEstado = 'Pendiente';
        break;
      case 'ACEPTADO':
        colorEstado = const Color(0xFF4CAF50);
        iconoEstado = Icons.check_circle;
        textoEstado = 'Aceptado';
        break;
      case 'RECHAZADO':
        colorEstado = const Color(0xFFDC2626);
        iconoEstado = Icons.cancel;
        textoEstado = 'Rechazado';
        break;
      case 'CANCELADA':
        colorEstado = const Color(0xFFDC2626);
        iconoEstado = Icons.cancel_outlined;
        textoEstado = 'Cancelada';
        break;
      default:
        colorEstado = const Color(0xFF666666);
        iconoEstado = Icons.help;
        textoEstado = estado;
    }

    return InkWell(
      onTap: () {
        if (_repartidorId != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => HistorialPagosCompletoScreen(
                repartidorId: _repartidorId!,
                repartidorNombre: _nombreController.text.trim(),
              ),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorEstado.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorEstado.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(iconoEstado, color: colorEstado, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      textoEstado,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colorEstado,
                      ),
                    ),
                  ],
                ),
                Text(
                  '\$${monto.toStringAsFixed(2)} $moneda',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colorEstado,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (fechaSolicitud != null)
              Text(
                'Solicitado: ${_formatearFecha(fechaSolicitud)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF666666),
                ),
              ),
            if (fechaAceptacion != null && estado == 'ACEPTADO')
              Text(
                'Aceptado: ${_formatearFecha(fechaAceptacion)}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF666666),
                ),
              ),
            if (pago['aceptado_por_nombre'] != null && estado == 'ACEPTADO')
              Text(
                'Por: ${pago['aceptado_por_nombre']}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF666666),
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatearFecha(DateTime fecha) {
    return '${fecha.day}/${fecha.month}/${fecha.year} ${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _cargarSaldo() async {
    if (_repartidorId == null) {
      await _cargarSaldoDesdeCache();
      return;
    }

    try {
      final r = await RepartidorSaldoService.cargarSaldo(_repartidorId!);
      if (mounted) {
        setState(() {
          _saldo = r.saldo;
          _monedaSaldo = r.moneda;
        });
      }
    } catch (e) {
      print('❌ Error cargando saldo: $e');
      await _cargarSaldoDesdeCache();
    }
  }

  // Suscribirse a cambios en solicitudes de pago
  void _suscribirseACambiosPagos() {
    if (_repartidorId == null) return;

    try {
      print('💰 Suscribiéndose a cambios en solicitudes de pago para repartidor: $_repartidorId');
      
      _channelPagos = supabase
          .channel('saldo_repartidor_$_repartidorId')
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
              print('💰 Cambio en solicitud de pago: ${payload.eventType}');
              _cargarSaldo();
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'usuarios',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: _repartidorId!,
            ),
            callback: (payload) {
              print('💰 Saldo actualizado en usuarios (entrega/acreditación)');
              _cargarSaldo();
            },
          )
          .subscribe();
    } catch (e) {
      print('❌ Error suscribiéndose a cambios de pagos: $e');
    }
  }
}
