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
import '../services/repartidor_saldo_offline_service.dart';
import '../services/repartidor_solicitud_pago_service.dart';
import '../widgets/repartidor_solicitud_pago_dialogs.dart';
import '../services/repartidor_historial_pago_service.dart';
import '../widgets/historial_pago_detalle_card.dart';
import '../utils/repartidor_master_util.dart';
import '../widgets/repartidor_master_badge.dart';

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
  
  List<HistorialNominaItem> _historialNomina = [];
  bool _cargandoHistorial = false;
  
  double _saldo = 0.0;
  double _saldoServidor = 0.0;
  double _saldoPendienteSync = 0.0;
  String _monedaSaldo = 'USD';
  String _metodoPago = 'por_orden';
  RepartidorSolicitudPreview? _previewPago;
  RealtimeChannel? _channelPagos;
  
  // Estado de conexión
  bool _isOnline = true;
  
  // Tipo de repartidor
  bool _esRecolector = false;
  bool _esRepartidorMaster = false;
  
  final ImagePicker _picker = ImagePicker();
  late final void Function() _refrescarSaldoTrasSync;

  @override
  void initState() {
    super.initState();
    _refrescarSaldoTrasSync = () {
      if (mounted && _repartidorId != null) {
        _cargarSaldo();
      }
    };
    SyncService().addSyncCompleteListener(_refrescarSaldoTrasSync);
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
    SyncService().removeSyncCompleteListener(_refrescarSaldoTrasSync);
    super.dispose();
  }

  void _aplicarSaldoCargado(RepartidorSaldoCargado r) {
    _saldo = r.saldo;
    _saldoServidor = r.saldoServidor;
    _saldoPendienteSync = r.saldoPendienteSync;
    _monedaSaldo = r.moneda;
  }

  Future<void> _persistirMasterFlag(bool esMaster) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await RepartidorMasterUtil.saveCached(user.id, esMaster);
    final cache = await RepartidorPerfilCacheService.getCachedPerfilData();
    if (cache != null) {
      await RepartidorPerfilCacheService.cachePerfilData({
        ...cache,
        'repartidor_master': esMaster,
      });
    }
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
          final esMaster = RepartidorMasterUtil.parseFlag(response['repartidor_master']);
          await _persistirMasterFlag(esMaster);

          // Guardar en caché
          await RepartidorPerfilCacheService.cachePerfilData({
            'id': response['id'],
            'tenant_id': response['tenant_id'],
            'nombre': response['nombre'] ?? '',
            'telefono': response['telefono'] ?? '',
            'email': response['email'] ?? '',
            'foto_perfil': response['foto_perfil'],
            'repartidor_metodo_pago': response['repartidor_metodo_pago'],
            'repartidor_tarifa': response['repartidor_tarifa'],
            'repartidor_saldo_moneda': response['repartidor_saldo_moneda'],
            'repartidor_master': esMaster,
          });

          setState(() {
            _repartidorId = response['id'];
            _tenantId = response['tenant_id'];
            _nombreController.text = response['nombre'] ?? '';
            _telefonoController.text = response['telefono'] ?? '';
            _emailController.text = response['email'] ?? '';
            _fotoPerfilUrl = response['foto_perfil'];
            _esRecolector = esRecolector;
            _esRepartidorMaster = esMaster;
            _isLoading = false;
          });

          if (!_esRecolector) {
            await _cargarEstadisticasSemanales();
          }
          await _cargarHistorialPagos();
          await _cargarSaldo();
          await _cargarPreviewPago();
          _suscribirseACambiosPagos();
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
              final esMaster = RepartidorMasterUtil.parseFlag(response['repartidor_master']);
              await _persistirMasterFlag(esMaster);

              // Guardar en caché
              await RepartidorPerfilCacheService.cachePerfilData({
                'id': response['id'],
                'tenant_id': response['tenant_id'],
                'nombre': response['nombre'] ?? '',
                'telefono': response['telefono'] ?? '',
                'email': response['email'] ?? '',
                'foto_perfil': response['foto_perfil'],
                'repartidor_metodo_pago': response['repartidor_metodo_pago'],
                'repartidor_tarifa': response['repartidor_tarifa'],
                'repartidor_saldo_moneda': response['repartidor_saldo_moneda'],
                'repartidor_master': esMaster,
              });

              setState(() {
                _repartidorId = response['id'];
                _tenantId = response['tenant_id'];
                _nombreController.text = response['nombre'] ?? '';
                _telefonoController.text = response['telefono'] ?? '';
                _emailController.text = response['email'] ?? '';
                _fotoPerfilUrl = response['foto_perfil'];
                _esRecolector = esRecolector;
                _esRepartidorMaster = esMaster;
                _isLoading = false;
              });

              if (!_esRecolector) {
                await _cargarEstadisticasSemanales();
              }
              await _cargarHistorialPagos();
              await _cargarSaldo();
              await _cargarPreviewPago();
              _suscribirseACambiosPagos();
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
        var esMaster = RepartidorMasterUtil.parseFlag(perfilCache['repartidor_master']);
        final user = supabase.auth.currentUser;
        if (user != null) {
          final cached = await RepartidorMasterUtil.loadCached(user.id);
          if (cached != null) esMaster = cached;
        }
        setState(() {
          _repartidorId = perfilCache['id']?.toString();
          _tenantId = perfilCache['tenant_id']?.toString();
          _nombreController.text = perfilCache['nombre'] ?? '';
          _telefonoController.text = perfilCache['telefono'] ?? '';
          _emailController.text = perfilCache['email'] ?? '';
          _fotoPerfilUrl = perfilCache['foto_perfil'];
          _esRepartidorMaster = esMaster;
          _isLoading = false;
        });
        print('💾 Datos de perfil cargados desde caché (master=$esMaster)');
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
        _historialNomina =
            historialCache.map((s) => HistorialNominaItem(solicitud: s)).toList();
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
      final pendienteCola =
          await RepartidorSaldoOfflineService.totalPendienteEnCola();
      if (saldoCache != null) {
        final raw = saldoCache['saldo'];
        final saldoServidor =
            raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0.0;
        final solicitudPendiente = saldoCache['solicitud_pendiente'] == true;
        final moneda = saldoCache['moneda']?.toString() ?? 'USD';
        setState(() {
          _aplicarSaldoCargado((
            saldo: RepartidorSaldoOfflineService.combinarSaldoVisible(
              saldoServidor: saldoServidor,
              pendienteEnCola: pendienteCola,
              solicitudPendiente: solicitudPendiente,
            ),
            saldoServidor: saldoServidor,
            saldoPendienteSync: pendienteCola,
            moneda: moneda,
            solicitudPendiente: solicitudPendiente,
          ));
        });
        print(
          '💾 Saldo caché: \$${saldoServidor.toStringAsFixed(2)} '
          '+ pendiente cola \$${pendienteCola.toStringAsFixed(2)} = '
          '\$${_saldo.toStringAsFixed(2)} $moneda',
        );
      } else if (pendienteCola > 0) {
        setState(() {
          _saldo = pendienteCola;
          _saldoServidor = 0;
          _saldoPendienteSync = pendienteCola;
        });
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
      backgroundColor: AppColors.darkBg,
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
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    16 +
                        MediaQuery.paddingOf(context).bottom +
                        (_isEditing ? 120 : 100),
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        // Foto de perfil
                        _buildFotoPerfil(),
                        const SizedBox(height: 24),

                        if (!_esRecolector) ...[
                          _buildEstadisticas(),
                          const SizedBox(height: 24),
                        ],
                        _buildBotonSolicitarPago(),
                        const SizedBox(height: 24),
                        _buildHistorialPagos(),
                        const SizedBox(height: 24),

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
                color: _esRepartidorMaster
                    ? AppColors.botonPrincipal
                    : const Color(0xFF4CAF50),
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
          if (_esRepartidorMaster)
            const Positioned(
              right: 4,
              top: 4,
              child: RepartidorMasterBadgeOverlay(
                size: 20,
                iconSize: 11,
                borderColor: AppColors.darkBg,
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
        if (_esRepartidorMaster) ...[
          const SizedBox(height: 10),
          _buildInsigniaMasterChip(),
        ],
        const SizedBox(height: 12),
        _buildResumenPagoChip(),
      ],
    );
  }

  Widget _buildInsigniaMasterChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.botonPrincipal.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppColors.botonPrincipal.withOpacity(0.45),
          width: 0.5,
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RepartidorMasterBadgeOverlay(size: 16, iconSize: 10),
          SizedBox(width: 6),
          Text(
            'Repartidor Master',
            style: TextStyle(
              color: Color(0xFFFFCC80),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstadisticas() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
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
                  color: AppColors.darkText,
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
              color: AppColors.darkTextMuted,
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
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Información Personal',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.darkText,
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
              prefixIcon: const Icon(Icons.email, color: AppColors.darkTextMuted),
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
          child: OutlinedButton(
            onPressed: () {
              setState(() {
                _isEditing = false;
                _cargarDatosPerfil();
              });
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.darkText,
              side: const BorderSide(color: AppColors.darkBorder, width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Cancelar',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton(
            onPressed: _guardarCambios,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.exito,
              foregroundColor: AppColors.onAccentButton,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Guardar',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.onAccentButton,
              ),
            ),
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
          foregroundColor: AppColors.botonPrincipal,
          side: const BorderSide(color: AppColors.botonPrincipal, width: 1.5),
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
              Icon(Icons.lock, color: AppColors.botonPrincipal, size: 24),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Cambiar Contraseña',
                  style: TextStyle(
                    color: AppColors.textOnLight,
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
                      prefixIcon: const Icon(Icons.lock_outline, color: AppColors.botonPrincipal),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _mostrandoContrasena ? Icons.visibility : Icons.visibility_off,
                          color: AppColors.textMutedOnLight,
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
                        borderSide: const BorderSide(color: AppColors.botonPrincipal),
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
                      prefixIcon: const Icon(Icons.lock, color: AppColors.botonPrincipal),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _mostrandoNuevaContrasena ? Icons.visibility : Icons.visibility_off,
                          color: AppColors.textMutedOnLight,
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
                        borderSide: const BorderSide(color: AppColors.botonPrincipal),
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
                      prefixIcon: const Icon(Icons.lock_reset, color: AppColors.botonPrincipal),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _mostrandoConfirmarContrasena ? Icons.visibility : Icons.visibility_off,
                          color: AppColors.textMutedOnLight,
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
                        borderSide: const BorderSide(color: AppColors.botonPrincipal),
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
                foregroundColor: AppColors.textMutedOnLight,
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
                backgroundColor: AppColors.botonPrincipal,
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
                color: AppColors.textOnLight,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: const Text(
          '¿Estás seguro de que quieres cerrar sesión?',
          style: TextStyle(
            color: AppColors.textMutedOnLight,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(
              'Cancelar',
              style: TextStyle(
                color: AppColors.textMutedOnLight,
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
        final items = await RepartidorHistorialPagoService.cargarHistorial(_repartidorId!);
        await RepartidorPerfilCacheService.cacheHistorialPagos(
          items.map((n) => n.solicitud).toList(),
        );

        setState(() {
          _historialNomina = items;
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

  Widget _buildResumenPagoChip() {
    final p = _previewPago;
    String texto;
    Color color = const Color(0xFF4CAF50);
    if (p?.esPorDistancia == true) {
      final u = p!.unidadEsMilla ? 'milla' : 'km';
      texto = 'Pago por recorrido · ${p.tarifa.toStringAsFixed(2)} ${p.moneda}/$u';
      color = const Color(0xFFFF9800);
    } else if (p?.esPorDia == true) {
      final lab = p!.diasLaborablesEtiqueta;
      texto = lab.isNotEmpty
          ? '${p.diasDesdeUltimaNomina} días laborables ($lab)'
          : '${p.diasDesdeUltimaNomina} días laborables';
      color = const Color(0xFFFF9800);
    } else {
      texto = 'Saldo ${_saldo.toStringAsFixed(2)} $_monedaSaldo';
      if (_saldoPendienteSync > 0) {
        texto +=
            ' (+${_saldoPendienteSync.toStringAsFixed(2)} por sincronizar)';
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(
        texto,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Future<void> _cargarPreviewPago() async {
    if (_repartidorId == null || !_isOnline) return;
    try {
      final p = await RepartidorSolicitudPagoService.cargarPreview(_repartidorId!);
      if (!mounted || p == null) return;
      final pendienteCola = p.esPorOrden
          ? await RepartidorSaldoOfflineService.totalPendienteEnCola()
          : 0.0;
      setState(() {
        _previewPago = p;
        _metodoPago = p.metodoPago;
        if (p.esPorOrden) {
          _saldoServidor = p.saldoAcumulado;
          _saldoPendienteSync = pendienteCola;
          _saldo = RepartidorSaldoOfflineService.combinarSaldoVisible(
            saldoServidor: p.saldoAcumulado,
            pendienteEnCola: pendienteCola,
            solicitudPendiente: false,
          );
          _monedaSaldo = p.moneda;
        }
      });
    } catch (e) {
      print('⚠️ Preview solicitud pago: $e');
    }
  }

  Widget _buildBotonSolicitarPago() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.darkBorder),
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

  Future<List<String>> _obtenerOrdenesIdsParaSolicitud() async {
    final nombre = _nombreController.text.trim();
    final estadoObjetivo = _esRecolector ? 'RECOGIDO' : 'ENTREGADO';

    final todas = await supabase
        .from('ordenes')
        .select('id, pagada, estado, fecha_entrega, tipo_orden')
        .eq('repartidor_nombre', nombre)
        .eq('estado', estadoObjetivo)
        .not('fecha_entrega', 'is', null)
        .or('pagada.is.null,pagada.eq.false');

    final solicitudesAceptadas = await supabase
        .from('solicitudes_pago_repartidores')
        .select('ordenes_incluidas')
        .eq('repartidor_id', _repartidorId!)
        .eq('estado', 'ACEPTADO');

    final enPagos = <String>{};
    for (final s in solicitudesAceptadas) {
      final ids = s['ordenes_incluidas'] as List<dynamic>?;
      if (ids != null) {
        for (final id in ids) {
          enPagos.add(id.toString());
        }
      }
    }

    final out = <String>[];
    for (final orden in todas) {
      final id = orden['id']?.toString() ?? '';
      if (id.isEmpty || orden['pagada'] == true) continue;
      if (_esRecolector && (orden['tipo_orden']?.toString().toUpperCase() != 'RECOGIDA')) continue;
      if (enPagos.contains(id)) continue;
      out.add(id);
    }
    return out;
  }

  Future<void> _enviarSolicitudPago({
    double? monto,
    String? moneda,
    List<String> ordenesIds = const [],
    double? kilometros,
    int? diasTrabajados,
  }) async {
    if (_repartidorId == null || _tenantId == null) return;

    setState(() => _isLoading = true);
    try {
      final map = await RepartidorSolicitudPagoService.crearSolicitud(
        repartidorId: _repartidorId!,
        tenantId: _tenantId!,
        repartidorNombre: _nombreController.text.trim(),
        moneda: moneda ?? _monedaSaldo,
        monto: monto,
        totalOrdenes: ordenesIds.length,
        ordenesIds: ordenesIds,
        kilometrosRecorridos: kilometros,
        diasTrabajados: diasTrabajados,
      );

      if (map['ok'] != true) {
        final err = map['error']?.toString() ?? 'error';
        if (err == 'saldo_insuficiente') {
          final s = map['saldo'];
          final disp = s is num ? s.toDouble() : _saldo;
          _mostrarMensaje('Saldo insuficiente. Disponible: ${disp.toStringAsFixed(2)}', Colors.red);
        } else if (err == 'solicitud_pendiente_existe') {
          _mostrarMensaje('Ya tienes una solicitud pendiente', Colors.orange);
        } else if (err == 'kilometros_requeridos') {
          _mostrarMensaje('Debes indicar el recorrido total', Colors.red);
        } else if (err == 'sin_dias_trabajados') {
          _mostrarMensaje('No hay días nuevos desde la última nómina', Colors.orange);
        } else if (err == 'tarifa_no_configurada') {
          _mostrarMensaje('Tu empresa debe configurar la tarifa de pago', Colors.red);
        } else {
          _mostrarMensaje('No se pudo enviar la solicitud', Colors.red);
        }
        return;
      }

      _mostrarMensaje('Solicitud de pago enviada correctamente', Colors.green);
      await _cargarSaldo();
      await _cargarPreviewPago();
      await _cargarHistorialPagos();
    } catch (e) {
      _mostrarMensaje('Error al solicitar pago', Colors.red);
      print('❌ Solicitud pago: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _mostrarModalSolicitarPago() async {
    if (!_isOnline) {
      _mostrarMensaje('Necesitas conexión para solicitar el pago', Colors.orange);
      return;
    }
    if (_repartidorId == null) return;

    await _cargarPreviewPago();
    final preview = _previewPago;
    if (preview == null) {
      _mostrarMensaje('No se pudo cargar la configuración de pago', Colors.red);
      return;
    }
    if (preview.solicitudPendiente) {
      _mostrarMensaje('Ya tienes una solicitud de pago pendiente', Colors.orange);
      return;
    }
    if (preview.tarifa <= 0) {
      _mostrarMensaje('Tu empresa aún no configuró la tarifa de pago', Colors.red);
      return;
    }

    if (preview.esPorDistancia) {
      final r = await RepartidorSolicitudPagoDialogs.modalPorDistancia(context, preview);
      if (r == null || !mounted) return;
      await _enviarSolicitudPago(
        moneda: preview.moneda,
        kilometros: r.distancia,
      );
      return;
    }

    if (preview.esPorDia) {
      final ok = await RepartidorSolicitudPagoDialogs.modalPorDia(context, preview);
      if (ok != true || !mounted) return;
      await _enviarSolicitudPago(
        moneda: preview.moneda,
        diasTrabajados: preview.diasDesdeUltimaNomina,
      );
      return;
    }

    final ordenesIds = await _obtenerOrdenesIdsParaSolicitud();
    if (_saldoPendienteSync > 0) {
      _mostrarMensaje(
        'Hay entregas pendientes de sincronizar. Conéctate y espera a que se suban antes de solicitar el pago.',
        Colors.orange,
      );
      return;
    }
    if (_saldoServidor <= 0 && ordenesIds.isEmpty) {
      _mostrarMensaje('No tienes saldo ni órdenes pendientes de cobro', Colors.orange);
      return;
    }

    final r = await RepartidorSolicitudPagoDialogs.modalPorOrden(
      context,
      saldo: _saldoServidor,
      moneda: _monedaSaldo,
      totalOrdenes: ordenesIds.length,
    );
    if (r == null || !mounted) return;
    await _enviarSolicitudPago(
      monto: r.monto,
      moneda: r.moneda,
      ordenesIds: ordenesIds,
    );
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
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.darkBorder),
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
                    color: AppColors.darkText,
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: AppColors.darkTextMuted,
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
            else if (_historialNomina.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'Sin nóminas registradas. Al solicitar y cobrar un pago verás el detalle aquí.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.darkTextMuted,
                    ),
                  ),
                ),
              )
            else
              ..._historialNomina
                  .take(2)
                  .map((item) => HistorialPagoDetalleCard(item: item, expanded: false)),
            if (_historialNomina.length > 2)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Center(
                  child: Text(
                    'Ver historial completo (${_historialNomina.length} registros)',
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

  Future<void> _cargarSaldo() async {
    if (_repartidorId == null) {
      await _cargarSaldoDesdeCache();
      return;
    }

    try {
      final r = await RepartidorSaldoService.cargarSaldo(_repartidorId!);
      if (mounted) {
        setState(() => _aplicarSaldoCargado(r));
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
