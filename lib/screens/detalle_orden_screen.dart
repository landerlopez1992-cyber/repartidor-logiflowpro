import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:signature/signature.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';
import '../models/orden.dart';
import '../services/email_service.dart';
import '../services/configuracion_service.dart';
import '../services/sync_service.dart';
import '../services/orden_estado_sync_helper.dart';
import '../services/offline_storage_service.dart';
import '../services/orden_cache_service.dart';
import '../services/paises_service.dart';
import '../services/goodbarber_sync_service.dart';
import '../main.dart';
import '../utils/orden_recogida_colaborador_ui.dart';
import '../utils/remesa_pura_entrega_ui.dart';
import '../config/app_colors.dart';
import '../widgets/volonex_dialog.dart';

class DetalleOrdenScreen extends StatefulWidget {
  final Orden orden;
  final bool abrirModalFirmaAutomatico;

  const DetalleOrdenScreen({
    Key? key,
    required this.orden,
    this.abrirModalFirmaAutomatico = false,
  }) : super(key: key);

  @override
  State<DetalleOrdenScreen> createState() => _DetalleOrdenScreenState();
}

class _DetalleOrdenScreenState extends State<DetalleOrdenScreen> {
  bool _isLoading = false;
  bool _fotoEntregaObligatoria = true; // Por defecto activado
  String? _fotoEntregaUrl; // URL de la foto tomada localmente
  String? _firmaUrl; // URL de la firma almacenada
  late Orden _ordenActual; // Orden que se actualiza localmente
  Map<String, dynamic>? _sucursalInfo; // Información de la sucursal para recogida
  RealtimeChannel? _ordenChannel; // Canal de Realtime para escuchar cambios en la orden
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 2,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  @override
  void initState() {
    super.initState();
    _ordenActual = widget.orden; // Copiar la orden inicial
    _fotoEntregaUrl = widget.orden.fotoEntrega; // Inicializar con la foto existente
    _firmaUrl = widget.orden.firmaUrl; // Inicializar con la firma existente
    _cargarConfiguracionFoto();
    
    // Debug: verificar estado inicial de la orden pasada como parámetro
    print('🔍 [DETALLE ORDEN] initState() - Orden inicial:');
    print('   - recogerEnSucursal (widget.orden): ${widget.orden.recogerEnSucursal}');
    print('   - sucursalId (widget.orden): ${widget.orden.sucursalId}');
    print('   - goodbarberOrderId (widget.orden): ${widget.orden.goodbarberOrderId}');
    print('   - direccionDestino (widget.orden): "${widget.orden.direccionDestino}"');
    print('   - direccionDestino isEmpty: ${widget.orden.direccionDestino.isEmpty}');
    
    // 🔥 SOLUCIÓN DIRECTA: Cargar orden desde BD INMEDIATAMENTE si es orden de GoodBarber
    // Esto asegura que tenemos los datos más recientes antes de que se renderice la UI
    // Verificar si es orden de GoodBarber (tiene goodbarberOrderId) o si es recoger en sucursal
    if (widget.orden.goodbarberOrderId != null || 
        (widget.orden.recogerEnSucursal && widget.orden.sucursalId == null)) {
      print('🔥 [INIT] Orden de GoodBarber o recoger en sucursal, cargando datos desde BD INMEDIATAMENTE...');
      print('   - widget.orden.goodbarberOrderId: ${widget.orden.goodbarberOrderId}');
      print('   - widget.orden.recogerEnSucursal: ${widget.orden.recogerEnSucursal}');
      print('   - widget.orden.sucursalId: ${widget.orden.sucursalId}');
      print('   - widget.orden.direccionDestino: "${widget.orden.direccionDestino}"');
      _cargarOrdenDesdeBDInmediatamente();
    } else {
      // Si no es orden de GoodBarber, usar el flujo normal
      print('🔄 [INIT] Llamando _recargarOrden() para obtener datos actualizados de la BD...');
      _recargarOrden();
    }
    
    // 🔥 SUSCRIBIRSE A CAMBIOS EN TIEMPO REAL para esta orden específica
    _suscribirseACambiosOrden();
  }
  
  // Suscribirse a cambios en tiempo real de la orden actual
  void _suscribirseACambiosOrden() {
    // ✅ OFFLINE-FIRST: Solo suscribirse si hay conexión
    final syncService = SyncService();
    if (!syncService.isOnline) {
      print('📴 [REALTIME] Sin conexión - No se suscribirá a cambios en tiempo real (modo offline)');
      return;
    }
    
    try {
      print('📡 [REALTIME] Suscribiéndose a cambios de la orden #${_ordenActual.numeroOrden} (ID: ${_ordenActual.id})');
      
      _ordenChannel = supabase
          .channel('detalle_orden_${_ordenActual.id}')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'ordenes',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: _ordenActual.id,
            ),
            callback: (payload) {
              print('🔄 🔄 🔄 [REALTIME] CAMBIO DETECTADO EN ORDEN #${_ordenActual.numeroOrden} 🔄 🔄 🔄');
              print('📋 Evento: ${payload.eventType}');
              
              final newRecord = payload.newRecord;
              final nuevaDireccion = newRecord['direccion_destino']?.toString() ?? '';
              final nuevoRecogerEnSucursal = newRecord['recoger_en_sucursal'] as bool? ?? false;
              final nuevoEstado = newRecord['estado']?.toString() ?? '';
              final nuevoGoodbarberOrderId = newRecord['goodbarber_order_id']?.toString();
              
              print('   📍 Nueva dirección: "$nuevaDireccion"');
              print('   🏪 Nuevo recoger_en_sucursal: $nuevoRecogerEnSucursal');
              print('   📦 Nuevo estado: $nuevoEstado');
              print('   🔗 Nuevo goodbarber_order_id: $nuevoGoodbarberOrderId');
              
              // 🔥 SIEMPRE recargar la orden cuando hay un cambio, especialmente para órdenes de GoodBarber
              // Esto asegura que _ordenActual se actualice con los datos más recientes
              print('✅ ✅ ✅ CAMBIO DETECTADO: Recargando orden desde Realtime...');
              
              // 🔥 FORZAR RECARGA INMEDIATA: Recargar la orden para obtener todos los datos actualizados
              // NO omitir recarga durante sincronización de GoodBarber - necesitamos actualizar la UI
              if (mounted) {
                // Usar Future.microtask para asegurar que setState se ejecute después del frame actual
                Future.microtask(() {
                  if (mounted) {
                    _recargarOrden();
                  }
                });
              } else {
                print('⚠️ Widget no está montado, no se puede recargar orden');
              }
            },
          )
          .subscribe((status, [error]) {
            if (status == RealtimeSubscribeStatus.subscribed) {
              print('✅ [REALTIME] Suscrito exitosamente a cambios de la orden #${_ordenActual.numeroOrden}');
            } else if (status == RealtimeSubscribeStatus.channelError) {
              // ✅ OFFLINE-FIRST: No mostrar error si está offline (solo en consola para debugging)
              final errorString = error?.toString() ?? '';
              if (errorString.contains('Failed host lookup') || 
                  errorString.contains('SocketException') ||
                  errorString.contains('WebSocketChannelException')) {
                print('📴 [REALTIME] Sin conexión - Error de suscripción ignorado (modo offline)');
              } else {
                print('❌ [REALTIME] Error al suscribirse a cambios de la orden: $error');
              }
            }
          });
    } catch (e) {
      // ✅ OFFLINE-FIRST: Manejar errores de conexión silenciosamente
      final errorString = e.toString();
      if (errorString.contains('Failed host lookup') || 
          errorString.contains('SocketException') ||
          errorString.contains('WebSocketChannelException')) {
        print('📴 [REALTIME] Sin conexión - Error de suscripción ignorado (modo offline)');
      } else {
        print('❌ [REALTIME] Error configurando suscripción: $e');
      }
    }
  }
  
  // 🔥 Cargar orden desde BD inmediatamente (para recoger en sucursal)
  Future<void> _cargarOrdenDesdeBDInmediatamente() async {
    // ✅ OFFLINE-FIRST: Solo intentar cargar desde BD si hay conexión
    final syncService = SyncService();
    if (!syncService.isOnline) {
      print('📴 [INIT] Sin conexión - Cargando desde caché');
      await _recargarOrden();
      return;
    }
    
    try {
      print('🔥 [INIT] Cargando orden #${widget.orden.numeroOrden} desde BD INMEDIATAMENTE...');
      
      final response = await supabase
          .from('ordenes')
          .select('*')
          .eq('id', widget.orden.id)
          .maybeSingle();
      
      if (response != null) {
        final ordenActualizada = Orden.fromJson(response);
        print('✅ [INIT] Orden cargada desde BD:');
        print('   - direccionDestino: "${ordenActualizada.direccionDestino}"');
        print('   - recogerEnSucursal: ${ordenActualizada.recogerEnSucursal}');
        print('   - direccionDestino isEmpty: ${ordenActualizada.direccionDestino.isEmpty}');
        
        if (mounted) {
          setState(() {
            _ordenActual = ordenActualizada;
          });
          
          // Si tiene direccionDestino, crear _sucursalInfo INMEDIATAMENTE
          if (ordenActualizada.recogerEnSucursal && 
              ordenActualizada.sucursalId == null && 
              ordenActualizada.direccionDestino.isNotEmpty) {
            print('✅ [INIT] Creando _sucursalInfo INMEDIATAMENTE con dirección desde BD...');
            setState(() {
              _sucursalInfo = {
                'nombre': 'Sucursal GoodBarber',
                'direccion': ordenActualizada.direccionDestino,
                'municipio': ordenActualizada.municipioDestino ?? '',
                'provincia': ordenActualizada.provinciaDestino ?? '',
                'pais': 'CU',
                'es_principal': false,
              };
            });
            print('✅ [INIT] _sucursalInfo creada: ${_sucursalInfo!['direccion']}');
          }
        }
      } else {
        print('⚠️ [INIT] No se encontró la orden en BD, usando datos de widget.orden');
      }
      
      // También llamar _recargarOrden() para obtener datos completos de destinatarios
      _recargarOrden();
    } catch (e) {
      // ✅ OFFLINE-FIRST: Manejar errores de conexión silenciosamente
      final errorString = e.toString();
      if (errorString.contains('Failed host lookup') || 
          errorString.contains('SocketException') ||
          errorString.contains('WebSocketChannelException') ||
          errorString.contains('ClientException')) {
        print('📴 [INIT] Sin conexión - Error ignorado (modo offline): $e');
        // NO mostrar error al usuario cuando está offline
      } else {
        print('❌ [INIT] Error cargando orden desde BD: $e');
      }
      // Si falla, usar el flujo normal (que cargará desde caché)
      _recargarOrden();
    }
  }
  
  // Cargar información de la sucursal
  Future<void> _cargarSucursalInfo() async {
    print('🔍 [DETALLE ORDEN] _cargarSucursalInfo() llamado');
    print('   - _ordenActual.recogerEnSucursal: ${_ordenActual.recogerEnSucursal}');
    print('   - _ordenActual.sucursalId: ${_ordenActual.sucursalId}');
    print('   - _ordenActual.direccionDestino: "${_ordenActual.direccionDestino}"');
    print('   - _ordenActual.goodbarberOrderId: ${_ordenActual.goodbarberOrderId}');
    print('   - _ordenActual.numeroOrden: ${_ordenActual.numeroOrden}');
    print('   - _sucursalInfo actual: ${_sucursalInfo != null}');
    
    // 🔥 CRÍTICO: Para órdenes de GoodBarber con pickup, NUNCA crear _sucursalInfo
    // Las órdenes de GoodBarber se muestran como órdenes normales, sin tarjeta especial
    if (_ordenActual.goodbarberOrderId != null) {
      print('✅✅✅ [SUCURSAL] Orden de GoodBarber - NO se carga _sucursalInfo (se muestra como orden normal) ✅✅✅');
      // Asegurar que _sucursalInfo es null para GoodBarber
      if (_sucursalInfo != null && mounted) {
        setState(() {
          _sucursalInfo = null;
        });
      }
      return;
    }
    
    // 🔥 OPTIMIZACIÓN: Si _sucursalInfo ya existe y tiene dirección válida, y _ordenActual.direccionDestino
    // es igual, no necesitamos recrearla
    if (_sucursalInfo != null && 
        _sucursalInfo!['direccion'] != null && 
        _sucursalInfo!['direccion'].toString().isNotEmpty &&
        _ordenActual.direccionDestino.isNotEmpty &&
        _sucursalInfo!['direccion'] == _ordenActual.direccionDestino) {
      print('✅ [SUCURSAL] _sucursalInfo ya existe con la misma dirección, no es necesario recrearla');
      return;
    }
    
    // IMPORTANTE: En VolonexPro+ normal, cuando recoger_en_sucursal = true, SIEMPRE hay sucursal_id
    // Solo GoodBarber puede tener recoger_en_sucursal = true con sucursal_id = null
    // Para órdenes normales de VolonexPro+ con recoger_en_sucursal pero sin sucursal_id, crear sucursal virtual
    if (_ordenActual.recogerEnSucursal && _ordenActual.sucursalId == null) {
      print('ℹ️ Orden normal de VolonexPro+ con recoger_en_sucursal pero sin sucursal_id');
      print('   Usando dirección desde direccion_destino: ${_ordenActual.direccionDestino}');
      print('   Municipio: ${_ordenActual.municipioDestino}');
      print('   Provincia: ${_ordenActual.provinciaDestino}');
      
      // Construir dirección completa - usar direccionDestino directamente o construir desde municipio/provincia
      String direccionFinal = _ordenActual.direccionDestino.isNotEmpty 
          ? _ordenActual.direccionDestino 
          : '';
      
      // Si direccionDestino está vacía, intentar construir desde municipio/provincia
      if (direccionFinal.isEmpty) {
        final partes = <String>[];
        if (_ordenActual.municipioDestino != null && _ordenActual.municipioDestino!.isNotEmpty) {
          partes.add(_ordenActual.municipioDestino!);
        }
        if (_ordenActual.provinciaDestino != null && _ordenActual.provinciaDestino!.isNotEmpty) {
          partes.add(_ordenActual.provinciaDestino!);
        }
        if (partes.isNotEmpty) {
          direccionFinal = partes.join(', ');
          print('   ⚠️ direccionDestino vacía, construyendo desde municipio/provincia: $direccionFinal');
        }
      }
      
      // Crear la sucursal virtual para órdenes normales de VolonexPro+
      if (mounted) {
        setState(() {
          _sucursalInfo = {
            'nombre': 'Sucursal de Recogida',
            'direccion': direccionFinal.isNotEmpty 
                ? direccionFinal 
                : 'Dirección no especificada',
            'municipio': _ordenActual.municipioDestino ?? '',
            'provincia': _ordenActual.provinciaDestino ?? '',
            'pais': 'CU',
            'es_principal': false,
          };
        });
        print('✅ ✅ ✅ Información de sucursal creada para orden normal de VolonexPro+:');
        print('   - Nombre: ${_sucursalInfo!['nombre']}');
        print('   - Dirección: ${_sucursalInfo!['direccion']}');
        print('   - FIN _cargarSucursalInfo (virtual)');
      } else {
        print('⚠️ Widget no está montado, no se puede actualizar estado');
      }
      return;
    }
    
    if (_ordenActual.sucursalId == null) {
      print('⚠️ No se puede cargar sucursal: sucursalId es null y no es recoger_en_sucursal');
      return;
    }
    
    print('🔍 Cargando información de sucursal desde BD: ${_ordenActual.sucursalId}');
    
    // ✅ OFFLINE-FIRST: Solo intentar cargar desde BD si hay conexión
    final syncService = SyncService();
    if (!syncService.isOnline) {
      print('📴 Sin conexión - No se cargará información de sucursal desde BD (modo offline)');
      return;
    }
    
    try {
      final response = await supabase
          .from('sucursales')
          .select('*')
          .eq('id', _ordenActual.sucursalId!)
          .single();
      
      print('✅ Sucursal cargada exitosamente:');
      print('   - Nombre: ${response['nombre']}');
      print('   - Dirección: ${response['direccion']}');
      print('   - Es Principal: ${response['es_principal']}');
      
      if (mounted) {
        setState(() {
          _sucursalInfo = response;
        });
        print('✅ Estado actualizado con información de sucursal');
        print('   - FIN _cargarSucursalInfo (desde BD)');
      }
    } catch (e) {
      // ✅ OFFLINE-FIRST: Manejar errores de conexión silenciosamente
      final errorString = e.toString();
      if (errorString.contains('Failed host lookup') || 
          errorString.contains('SocketException') ||
          errorString.contains('WebSocketChannelException') ||
          errorString.contains('ClientException')) {
        print('📴 Sin conexión - Error cargando sucursal ignorado (modo offline): $e');
        // NO mostrar error al usuario cuando está offline
      } else {
        print('❌ Error cargando información de sucursal: $e');
      }
      if (mounted) {
        setState(() {
          _sucursalInfo = null;
        });
      }
      print('   - FIN _cargarSucursalInfo (error)');
    }
  }
  
  @override
  void dispose() {
    // Desuscribirse del canal de Realtime
    if (_ordenChannel != null) {
      print('🔌 [REALTIME] Desconectando canal de Realtime para orden #${_ordenActual.numeroOrden}');
      _ordenChannel?.unsubscribe();
      _ordenChannel = null;
    }
    _signatureController.dispose();
    super.dispose();
  }
  
  // Recargar la orden desde Supabase o caché
  Future<void> _recargarOrden() async {
    try {
      print('🔄 🔄 🔄 [DETALLE ORDEN] _recargarOrden() INICIADO 🔄 🔄 🔄');
      print('🔄 Recargando orden #${_ordenActual.numeroOrden} con datos de destinatarios...');
      print('   - Orden ID: ${_ordenActual.id}');
      print('   - direccionDestino ANTES de recargar: "${_ordenActual.direccionDestino}"');
      print('   - recogerEnSucursal ANTES: ${_ordenActual.recogerEnSucursal}');
      
      // Verificar conexión
      final syncService = SyncService();
      final isOnline = syncService.isOnline;
      print('   - isOnline: $isOnline');
      
      if (isOnline) {
        // Intentar cargar desde Supabase si hay conexión
        try {
          final response = await supabase
              .from('ordenes')
              .select('*, destinatarios!left(nombre, telefono, direccion, municipio, provincia, consejo_popular_batey)')
              .eq('id', _ordenActual.id)
              .single();
          
          // Debug: verificar datos
          print('🔍 DEBUG - Datos recibidos:');
          print('  - municipio_destino: ${response['municipio_destino']}');
          print('  - provincia_destino: ${response['provincia_destino']}');
          print('  - tiene_remesa: ${response['tiene_remesa']}');
          print('  - cantidad_remesa: ${response['cantidad_remesa']}');
          print('  - recoger_en_sucursal: ${response['recoger_en_sucursal']}');
          print('  - sucursal_id: ${response['sucursal_id']}');
          print('  - goodbarber_order_id: ${response['goodbarber_order_id']}');
          print('  - goodbarber_app_id: ${response['goodbarber_app_id']}');
          print('  - direccion_destino: ${response['direccion_destino']}');
          
          final ordenRecargada = Orden.fromJson(response);
          
          // 🔍 DETECTAR CAMBIOS: Si la orden está en "LISTO PARA RECOGER" pero ya no tiene recoger_en_sucursal = true,
          // cambiar el estado de vuelta a "EN REPARTO"
          if (ordenRecargada.estado == 'LISTO PARA RECOGER' && !ordenRecargada.recogerEnSucursal) {
            print('⚠️ DETECCIÓN DE CAMBIO: La orden está en "LISTO PARA RECOGER" pero recoger_en_sucursal es false');
            print('   Cambiando estado de vuelta a "EN REPARTO"');
            
            try {
              await supabase
                  .from('ordenes')
                  .update({'estado': 'EN REPARTO'})
                  .eq('id', _ordenActual.id);
              
              // Sincronizar con GoodBarber si la orden está vinculada
              try {
                await GoodBarberSyncService.sincronizarEstadoAGoodBarber(
                  supabase,
                  _ordenActual.id,
                  'EN REPARTO',
                );
              } catch (e) {
                print('⚠️ Error sincronizando estado con GoodBarber: $e');
              }
              
              // Actualizar el estado en la orden recargada
              ordenRecargada.estado = 'EN REPARTO';
              print('✅ Estado cambiado exitosamente a "EN REPARTO"');
            } catch (e) {
              print('❌ Error al cambiar estado: $e');
              // Continuar con la orden recargada aunque el cambio de estado falle
            }
          }
          
          print('✅ Orden parseada:');
          print('  - Municipio: ${ordenRecargada.municipioDestino ?? "null"}');
          print('  - Provincia: ${ordenRecargada.provinciaDestino ?? "null"}');
          print('  - Estado: ${ordenRecargada.estado}');
          print('  - recogerEnSucursal: ${ordenRecargada.recogerEnSucursal}');
          print('  - Tiene Remesa: ${ordenRecargada.tieneRemesa}');
          print('  - Cantidad Remesa: ${ordenRecargada.cantidadRemesa}');
          print('  - Recoger en Sucursal: ${ordenRecargada.recogerEnSucursal}');
          print('  - Sucursal ID: ${ordenRecargada.sucursalId ?? "null"}');
          print('  - 🔥 direccionDestino (parseada): "${ordenRecargada.direccionDestino}"');
          print('  - 🔥 direccionDestino (desde BD raw): "${response['direccion_destino']}"');
          print('  - 🔥 direccionDestino isEmpty: ${ordenRecargada.direccionDestino.isEmpty}');
          print('  - 🔥 direccionDestino length: ${ordenRecargada.direccionDestino.length}');
          print('  - 🔥 recoger_en_sucursal (desde BD): ${response['recoger_en_sucursal']}');
          print('  - 🔥 recogerEnSucursal (parseada): ${ordenRecargada.recogerEnSucursal}');
          
          // Actualizar caché con los datos completos
          await OrdenCacheService.updateCachedOrder(ordenRecargada);
          
          print('✅ ✅ ✅ [DETALLE ORDEN] ANTES DE setState:');
          print('   - direccionDestino en ordenRecargada: "${ordenRecargada.direccionDestino}"');
          print('   - recogerEnSucursal en ordenRecargada: ${ordenRecargada.recogerEnSucursal}');
          
          if (mounted) {
            setState(() {
              _ordenActual = ordenRecargada;
              print('✅ ✅ ✅ [DETALLE ORDEN] DENTRO DE setState:');
              print('   - direccionDestino en _ordenActual: "${_ordenActual.direccionDestino}"');
              print('   - recogerEnSucursal en _ordenActual: ${_ordenActual.recogerEnSucursal}');
              // 🔒 CRÍTICO: Preservar foto local si existe (offline-first)
              // Si hay una foto local (local://), NO sobrescribirla con datos de BD
              // Solo actualizar si la BD tiene una foto real (no local) y es diferente
              final fotoLocalAntes = _fotoEntregaUrl;
              final tieneFotoLocal = fotoLocalAntes != null && 
                                     fotoLocalAntes.isNotEmpty && 
                                     fotoLocalAntes.startsWith('local://');
              
              if (tieneFotoLocal) {
                // 🔒 PRESERVAR foto local - no sobrescribir con datos de BD
                print('🔒 Preservando foto local: $fotoLocalAntes');
                _fotoEntregaUrl = fotoLocalAntes;
                // No modificar _ordenActual directamente (es inmutable)
              } else if (_ordenActual.fotoEntrega != null && 
                         _ordenActual.fotoEntrega!.isNotEmpty &&
                         !_ordenActual.fotoEntrega!.startsWith('local://')) {
                // Solo actualizar si la BD tiene una foto real (no local) y es diferente
                if (_ordenActual.fotoEntrega != _fotoEntregaUrl) {
                  print('✅ Actualizando foto desde BD: ${_ordenActual.fotoEntrega}');
                  _fotoEntregaUrl = _ordenActual.fotoEntrega;
                }
              } else if (_fotoEntregaUrl == null || _fotoEntregaUrl!.isEmpty) {
                // Si no hay foto local ni en BD, verificar si hay foto pendiente en storage
                // Hacer esto de forma asíncrona después del setState
                Future.microtask(() async {
                  try {
                    final offlineStorage = OfflineStorageService();
                    final pendingPhotos = await offlineStorage.getPendingPhotos();
                    final fotoPendiente = pendingPhotos.firstWhere(
                      (photo) => photo['orden_id'] == _ordenActual.id,
                      orElse: () => <String, dynamic>{},
                    );
                    
                    if (fotoPendiente.isNotEmpty && fotoPendiente['file_path'] != null) {
                      final filePath = fotoPendiente['file_path'] as String;
                      final file = File(filePath);
                      if (await file.exists()) {
                        print('🔒 Restaurando foto local desde storage: $filePath');
                        final fotoLocalUrl = 'local://$filePath';
                        if (mounted) {
                          setState(() {
                            _fotoEntregaUrl = fotoLocalUrl;
                            
                            // 🔒 CRÍTICO: Actualizar también _ordenActual
                            try {
                              final ordenJson = _ordenActual.toJson();
                              ordenJson['foto_entrega'] = fotoLocalUrl;
                              _ordenActual = Orden.fromJson(ordenJson);
                              print('✅ _ordenActual actualizada con foto restaurada: $fotoLocalUrl');
                            } catch (e) {
                              print('⚠️ Error actualizando _ordenActual con foto restaurada: $e');
                            }
                          });
                        }
                      }
                    }
                  } catch (e) {
                    print('⚠️ Error verificando fotos pendientes: $e');
                  }
                });
              }
              // Similar para la firma
              if (_firmaUrl == null || 
                  _firmaUrl!.isEmpty || 
                  _firmaUrl!.startsWith('local://') ||
                  (_ordenActual.firmaUrl != null && _ordenActual.firmaUrl!.isNotEmpty)) {
                if (_ordenActual.firmaUrl != null && 
                    _ordenActual.firmaUrl!.isNotEmpty &&
                    _ordenActual.firmaUrl != _firmaUrl) {
                  _firmaUrl = _ordenActual.firmaUrl;
                }
              }
            });
            
            print('✅ ✅ ✅ [DETALLE ORDEN] DESPUÉS DE setState:');
            print('   - direccionDestino en _ordenActual: "${_ordenActual.direccionDestino}"');
            print('   - recogerEnSucursal en _ordenActual: ${_ordenActual.recogerEnSucursal}');
            print('   - direccionDestino isEmpty: ${_ordenActual.direccionDestino.isEmpty}');
            print('   - direccionDestino length: ${_ordenActual.direccionDestino.length}');
            
            // 🔥 CRÍTICO: Cargar información de sucursal INMEDIATAMENTE después de setState
            // IMPORTANTE: En VolonexPro+ normal, cuando recoger_en_sucursal = true, SIEMPRE hay sucursal_id
            // Solo GoodBarber puede tener recoger_en_sucursal = true con sucursal_id = null
            // 🔥 NO cargar _sucursalInfo para órdenes de GoodBarber (no es necesario)
            if (ordenRecargada.recogerEnSucursal && ordenRecargada.goodbarberOrderId == null) {
              print('✅ [DETALLE ORDEN] Llamando _cargarSucursalInfo() después de actualizar orden (orden normal de VolonexPro+)');
              print('   - recogerEnSucursal: ${ordenRecargada.recogerEnSucursal}');
              print('   - sucursalId: ${ordenRecargada.sucursalId}');
              print('   - goodbarberOrderId: ${ordenRecargada.goodbarberOrderId} (debe ser null)');
              print('   - direccionDestino (ordenRecargada): "${ordenRecargada.direccionDestino}"');
              
              // 🔥 EJECUTAR INMEDIATAMENTE: No usar Future.microtask, ejecutar directamente
              // Esto asegura que _sucursalInfo se cree inmediatamente con los datos actualizados
              if (mounted) {
                // Llamar directamente, no en un microtask
                print('🔥 [DETALLE ORDEN] Ejecutando _cargarSucursalInfo() INMEDIATAMENTE...');
                _cargarSucursalInfo();
              } else {
                print('⚠️ [DETALLE ORDEN] Widget no está montado, no se puede llamar _cargarSucursalInfo()');
              }
            } else if (ordenRecargada.recogerEnSucursal && ordenRecargada.goodbarberOrderId != null) {
              print('✅ [DETALLE ORDEN] Orden de GoodBarber con pickup - NO se carga _sucursalInfo (no es necesario)');
            } else {
              print('ℹ️ [DETALLE ORDEN] No es recoger en sucursal, no se carga información de sucursal');
            }
          }
        } catch (e) {
          // ✅ OFFLINE-FIRST: Manejar errores de conexión silenciosamente
          final errorString = e.toString();
          if (errorString.contains('Failed host lookup') || 
              errorString.contains('SocketException') ||
              errorString.contains('WebSocketChannelException') ||
              errorString.contains('ClientException')) {
            print('📴 Sin conexión - Cargando desde caché (modo offline)');
          } else {
            print('⚠️ Error cargando desde Supabase, usando caché: $e');
          }
          // Si falla, cargar desde caché
          await _cargarDesdeCache();
          // Asegurar que se carga info de sucursal incluso si hay error (solo para órdenes normales de VolonexPro+)
          if (mounted && _ordenActual.recogerEnSucursal && _ordenActual.goodbarberOrderId == null) {
            print('⚠️ [ERROR] Llamando _cargarSucursalInfo() después de error en _recargarOrden()');
            _cargarSucursalInfo();
          }
        }
      } else {
        // Sin conexión, cargar desde caché
        print('📴 Sin conexión - Cargando orden desde caché local');
        await _cargarDesdeCache();
        // Asegurar que se carga info de sucursal incluso sin conexión (solo para órdenes normales de VolonexPro+)
        if (mounted && _ordenActual.recogerEnSucursal && _ordenActual.goodbarberOrderId == null) {
          print('📴 [OFFLINE] Llamando _cargarSucursalInfo() después de cargar desde caché (offline)');
          _cargarSucursalInfo();
        }
      }
    } catch (e) {
      // ✅ OFFLINE-FIRST: Manejar errores de conexión silenciosamente
      final errorString = e.toString();
      if (errorString.contains('Failed host lookup') || 
          errorString.contains('SocketException') ||
          errorString.contains('WebSocketChannelException') ||
          errorString.contains('ClientException')) {
        print('📴 Sin conexión - Cargando desde caché (modo offline)');
      } else {
        print('❌ Error al recargar orden: $e');
      }
      // Intentar cargar desde caché como último recurso
      await _cargarDesdeCache();
      // Asegurar que se carga info de sucursal incluso si todo falla (solo para órdenes normales de VolonexPro+)
      if (mounted && _ordenActual.recogerEnSucursal && _ordenActual.goodbarberOrderId == null) {
        print('❌ [ERROR CRÍTICO] Llamando _cargarSucursalInfo() después de error crítico en _recargarOrden()');
        _cargarSucursalInfo();
      }
    }
    
    // 🔒 CRÍTICO: Si se solicitó abrir modal de firma automáticamente, hacerlo después de cargar
    if (widget.abrirModalFirmaAutomatico && mounted) {
      print('✍️ Abriendo modal de firma automáticamente después de cargar orden...');
      // Esperar un frame para que la UI se renderice completamente
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            RemesaPuraEntregaUi.exigeFirmaEntrega(_ordenActual) &&
            (_firmaUrl == null || _firmaUrl!.isEmpty)) {
          print('✍️ Llamando _mostrarModalFirma() automáticamente...');
          _mostrarModalFirma();
        } else {
          print('ℹ️ No se abre modal de firma automáticamente: requiereFirma=${_ordenActual.requiereFirma}, firmaUrl=$_firmaUrl');
        }
      });
    }
  }

  // Cargar orden desde caché local
  Future<void> _cargarDesdeCache() async {
    try {
      final ordenCache = await OrdenCacheService.getCachedOrderById(_ordenActual.id);
      
      if (ordenCache != null) {
        print('💾 Orden cargada desde caché: ${ordenCache.numeroOrden}');
        print('   - recogerEnSucursal: ${ordenCache.recogerEnSucursal}');
        print('   - sucursalId: ${ordenCache.sucursalId}');
        if (mounted) {
          setState(() {
            _ordenActual = ordenCache;
            // Preservar foto y firma locales si existen
            if (_fotoEntregaUrl == null || _fotoEntregaUrl!.isEmpty) {
              _fotoEntregaUrl = ordenCache.fotoEntrega;
            }
            if (_firmaUrl == null || _firmaUrl!.isEmpty) {
              _firmaUrl = ordenCache.firmaUrl;
            }
          });
          // IMPORTANTE: En VolonexPro+ normal, cuando recoger_en_sucursal = true, SIEMPRE hay sucursal_id
          // Solo GoodBarber puede tener recoger_en_sucursal = true con sucursal_id = null
          // 🔥 NO cargar _sucursalInfo para órdenes de GoodBarber (no es necesario)
          if (_ordenActual.recogerEnSucursal && _ordenActual.goodbarberOrderId == null) {
            print('✅ [CACHÉ] Llamando _cargarSucursalInfo() después de cargar desde caché (orden normal de VolonexPro+)');
            print('   - recogerEnSucursal: ${_ordenActual.recogerEnSucursal}');
            print('   - sucursalId: ${_ordenActual.sucursalId}');
            print('   - goodbarberOrderId: ${_ordenActual.goodbarberOrderId} (debe ser null)');
            print('   - direccionDestino: ${_ordenActual.direccionDestino}');
            _cargarSucursalInfo();
          } else if (_ordenActual.recogerEnSucursal && _ordenActual.goodbarberOrderId != null) {
            print('✅ [CACHÉ] Orden de GoodBarber con pickup - NO se carga _sucursalInfo (no es necesario)');
          }
        }
        _mostrarMensaje('📴 Modo offline - Mostrando datos en caché');
      } else {
        print('⚠️ Orden no encontrada en caché, usando datos iniciales');
        // Mantener los datos que ya tenemos (widget.orden)
        if (mounted) {
          setState(() {
            // No hacer nada, mantener _ordenActual como está
          });
        }
        _mostrarMensaje('⚠️ Sin conexión - Usando datos disponibles');
      }
    } catch (e) {
      print('❌ Error cargando desde caché: $e');
      // Mantener los datos que ya tenemos
      if (mounted) {
        _mostrarMensaje('⚠️ Error cargando datos - Usando información disponible');
      }
    }
  }

  Future<void> _cargarConfiguracionFoto() async {
    try {
      // Verificar conexión
      final syncService = SyncService();
      final isOnline = syncService.isOnline;
      
      if (isOnline) {
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
          print('⚠️ Error cargando configuración desde Supabase: $e');
          // Usar valor por defecto si falla
          if (mounted) {
            setState(() {
              _fotoEntregaObligatoria = true; // Valor por defecto
            });
          }
        }
      } else {
        // Sin conexión, usar valor por defecto
        print('📴 Sin conexión - Usando configuración por defecto');
        if (mounted) {
          setState(() {
            _fotoEntregaObligatoria = true; // Valor por defecto
          });
        }
      }
    } catch (e) {
      print('Error al cargar configuración de foto: $e');
      // Mantener el valor por defecto
      if (mounted) {
        setState(() {
          _fotoEntregaObligatoria = true;
        });
      }
    }
  }

  String _textoListoEnColaborador(dynamic raw) {
    if (raw == null) return '';
    final s = raw.toString();
    final d = DateTime.tryParse(s);
    if (d != null) {
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
          '${d.hour}:${d.minute.toString().padLeft(2, '0')}';
    }
    return s;
  }

  /// Avisos de colaboradores: parte lista para recogida (no implica cambio de estado de la orden).
  Widget _buildAvisosRecogidaColaboradoresBanner() {
    final list = _ordenActual.avisosRecogidaVendedor;
    if (list == null || list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF4CAF50), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notifications_active, color: Colors.green[800], size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Avisos de recogida (colaboradores)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[900],
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...list.map((a) {
              final nombre = (a['nombre_vendedor'] ?? 'Colaborador').toString();
              final cuando = _textoListoEnColaborador(a['listo_en']);
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '· $nombre: indica que su parte está lista para recogida${cuando.isNotEmpty ? ' ($cuando)' : ''}.',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF1B5E20), height: 1.35),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  bool _esRemesaPura() => RemesaPuraEntregaUi.esRemesaPura(_ordenActual);

  @override
  Widget build(BuildContext context) {
    // Si es remesa pura, mostrar UI especializada
    if (_esRemesaPura()) {
      return _buildRemesaDetalleView();
    }
    
    // Debug en cada build para asegurarnos de que los flags están correctos
    print('🧭 [BUILD DETALLE] recogerEnSucursal=${_ordenActual.recogerEnSucursal}, sucursalId=${_ordenActual.sucursalId}, sucursalInfo=${_sucursalInfo != null}');
    print('🧭 [BUILD DETALLE] direccionDestino="${_ordenActual.direccionDestino}"');
    print('🧭 [BUILD DETALLE] goodbarberOrderId=${_ordenActual.goodbarberOrderId}');

    // 🔥 REGLA: Para órdenes de GoodBarber con pickup, NO cargar _sucursalInfo (se muestran como órdenes normales)
    // Para órdenes normales de VolonexPro+ con recoger_en_sucursal, SÍ cargar _sucursalInfo (para mostrar tarjeta verde)
    final esPickupGoodBarber = _ordenActual.recogerEnSucursal == true && 
                                _ordenActual.goodbarberOrderId != null;
    
    if (esPickupGoodBarber) {
      print('✅✅✅ [BUILD] Orden de GoodBarber con pickup - NO se carga _sucursalInfo (se muestra como orden normal) ✅✅✅');
      // Asegurar que _sucursalInfo es null para órdenes de GoodBarber (no se necesita)
      if (_sucursalInfo != null) {
        print('⚠️ [BUILD] Limpiando _sucursalInfo para orden de GoodBarber (no se necesita)');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _sucursalInfo = null;
            });
          }
        });
      }
    } else if (_ordenActual.recogerEnSucursal && 
               _ordenActual.sucursalId == null && 
               _sucursalInfo == null &&
               _ordenActual.goodbarberOrderId == null) { // 🔥 SOLO si NO es GoodBarber
      print('⚠️ [BUILD] Detectado recoger_en_sucursal sin sucursalInfo (orden normal de VolonexPro+), cargando...');
      print('   - recogerEnSucursal: ${_ordenActual.recogerEnSucursal}');
      print('   - sucursalId: ${_ordenActual.sucursalId}');
      print('   - goodbarberOrderId: ${_ordenActual.goodbarberOrderId} (debe ser null)');
      print('   - direccionDestino: ${_ordenActual.direccionDestino}');
      // Usar un microtask para evitar llamar setState durante build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _cargarSucursalInfo();
        }
      });
    }
    
    // 🔥 KEY ÚNICO: Forzar reconstrucción completa cuando cambian los valores críticos
    final pickupKey = 'pickup_${_ordenActual.recogerEnSucursal}_${_ordenActual.goodbarberOrderId}_${_ordenActual.id}';
    
    return Scaffold(
      key: ValueKey('scaffold_$pickupKey'),
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text('Orden #${widget.orden.numeroOrden.isNotEmpty ? widget.orden.numeroOrden : (widget.orden.id.length > 8 ? widget.orden.id.substring(0, 8) : widget.orden.id)}'),
        backgroundColor: const Color(0xFF2C3E50),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (widget.orden.estado != 'ENTREGADO' && widget.orden.estado != 'CANCELADA')
            IconButton(
              onPressed: _mostrarOpciones,
              icon: const Icon(Icons.more_vert),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), // Más padding inferior
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card principal con información básica
            _buildInfoCard(),
            _buildAvisosRecogidaColaboradoresBanner(),
            const SizedBox(height: 12),
            
            // 🔥 REGLA: Para órdenes de GoodBarber con pickup, mostrar como orden normal (sin tarjeta especial)
            // Para órdenes normales de VolonexPro+ con recoger_en_sucursal, mostrar tarjeta verde de recogida
            // SIEMPRE mostrar _buildContactCard() - este método maneja internamente si es pickup de VolonexPro+ normal
            _buildContactCard(),
            const SizedBox(height: 12),
            
            if (OrdenRecogidaColaboradorUi.enFaseRecogidaColaborador(_ordenActual) &&
                OrdenRecogidaColaboradorUi.tieneDatosColaborador(_ordenActual)) ...[
              _buildColaboradorRecogidaCard(),
              const SizedBox(height: 12),
            ],

            // Card de detalles de entrega (ocultar destino mientras no se recoge en colaborador)
            if (widget.orden.tipoOrden != 'RECOGIDA' &&
                !_ordenActual.recogerEnSucursal &&
                !OrdenRecogidaColaboradorUi.enFaseRecogidaColaborador(_ordenActual)) ...[
              _buildDeliveryCard(),
              const SizedBox(height: 12),
            ],
            
            // Card de pago (si aplica)
            if (widget.orden.requierePago) ...[
              _buildPaymentCard(),
              const SizedBox(height: 12),
            ],
            
            // Card de remesa (si aplica)
            if (_ordenActual.tieneRemesa) ...[
              _buildRemesaCard(),
              const SizedBox(height: 12),
            ],
            
            // Card de historial de estados
            _buildStatusHistoryCard(),
            const SizedBox(height: 12),

            if (!OrdenRecogidaColaboradorUi.enFaseRecogidaColaborador(_ordenActual) &&
                !_ordenActual.entregaPorVendedor &&
                (_ordenActual.vendedorContactoNombre != null ||
                    (_ordenActual.vendedorContactoTelefono != null &&
                        _ordenActual.vendedorContactoTelefono!.trim().isNotEmpty) ||
                    (_ordenActual.vendedorContactoEmail != null &&
                        _ordenActual.vendedorContactoEmail!.trim().isNotEmpty))) ...[
              _buildColaboradorRecogidaCard(),
              const SizedBox(height: 12),
            ],
            
            // 🔥 RECUADRO INFORMATIVO ESPECIAL: Proceso de recogida en sucursal (solo para órdenes normales de VolonexPro+)
            if (_ordenActual.goodbarberOrderId == null && 
                _ordenActual.recogerEnSucursal && 
                _sucursalInfo != null) ...[
              _buildProcesoRecogidaSucursalCard(),
              const SizedBox(height: 12),
            ],
            
            const SizedBox(height: 20), // Más espacio antes de los botones
            
            // Botones de acción
          // Mostrar botones de acción solo si NO está entregada, cancelada, o bloqueada (POR ENVIAR)
          if (widget.orden.estado != 'ENTREGADO' && widget.orden.estado != 'CANCELADA')
            _buildActionButtons(),
              
            // Espacio extra al final para evitar que se obstruyan los botones
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // Vista completa especializada para remesas puras
  Widget _buildRemesaDetalleView() {
    // Cargar información de sucursal si está activo recoger_en_sucursal
    if (_ordenActual.recogerEnSucursal && _ordenActual.sucursalId != null && _sucursalInfo == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _cargarSucursalInfo();
        }
      });
    }
    
    final numeroRemesa = _ordenActual.numeroRemesa ?? _ordenActual.numeroOrden;
    final cantidadRemesa = _ordenActual.cantidadRemesa ?? 0.0;
    // Estados: POR ENVIAR, ENTREGADO EN SUCURSAL (solo si recoger_en_sucursal), ENTREGADO
    final estado = _ordenActual.estado == 'ENTREGADO' 
        ? 'ENTREGADO' 
        : _ordenActual.estado == 'ENTREGADO EN SUCURSAL'
            ? 'ENTREGADO EN SUCURSAL'
            : 'POR ENVIAR';
    
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E6), // Fondo dorado muy claro
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.attach_money, color: Color(0xFFFFD700), size: 20),
            const SizedBox(width: 8),
            Text('Remesa #$numeroRemesa'),
          ],
        ),
        backgroundColor: const Color(0xFFFFD700),
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card principal con información de remesa (estilo dorado)
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFFD700).withOpacity(0.3),
                    const Color(0xFFFFA500).withOpacity(0.2),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFFD700).withOpacity(0.8),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD700).withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header con badge REMESA y estado
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.attach_money, color: Colors.white, size: 18),
                              SizedBox(width: 6),
                              Text(
                                'REMESA',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildRemesaDetalleStatusChip(estado),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // Cantidad a pagar destacada
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFFFD700).withOpacity(0.4),
                            const Color(0xFFFFA500).withOpacity(0.3),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFFFD700),
                          width: 2,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Cantidad a Pagar',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF666666),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '\$${cantidadRemesa.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 36,
                              color: Color(0xFF1A1A1A),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Información de la remesa
                    _buildRemesaDetalleInfoRow(Icons.confirmation_number, 'Número de Remesa', '#$numeroRemesa'),
                    const SizedBox(height: 12),
                    _buildRemesaDetalleInfoRow(Icons.person, 'Emisor', _ordenActual.emisor),
                    const SizedBox(height: 12),
                    _buildRemesaDetalleInfoRow(Icons.person_outline, 'Destinatario', _ordenActual.receptor),
                    const SizedBox(height: 12),
                    // Mostrar dirección de sucursal si recoger_en_sucursal está activo, sino mostrar dirección del destinatario
                    if (_ordenActual.recogerEnSucursal && _sucursalInfo != null) ...[
                      _buildRemesaDetalleInfoRow(Icons.store, 'Recoger en Sucursal', _sucursalInfo!['nombre'] ?? 'Sin nombre'),
                      const SizedBox(height: 12),
                      _buildRemesaDetalleInfoRow(Icons.location_on, 'Dirección de Sucursal', _formatearDireccionSucursalRemesa()),
                      const SizedBox(height: 12),
                    ] else if (_ordenActual.direccionDestino.isNotEmpty) ...[
                      _buildRemesaDetalleInfoRow(Icons.location_on, 'Dirección', _formatearDireccionCompletaRemesa()),
                      const SizedBox(height: 12),
                    ],
                    _buildRemesaDetalleInfoRow(Icons.schedule, 'Fecha de Creación', _formatearFecha(_ordenActual.fechaCreacion)),
                    if (_ordenActual.fechaEntrega != null) ...[
                      const SizedBox(height: 12),
                      _buildRemesaDetalleInfoRow(Icons.check_circle, 'Fecha de Entrega', _formatearFecha(_ordenActual.fechaEntrega)),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            // Botones de contacto (WhatsApp, GPS, SMS, Llamada) - Solo si recoger_en_sucursal = false
            if (!_ordenActual.recogerEnSucursal && _ordenActual.direccionDestino.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFFFFD700).withOpacity(0.2),
                      const Color(0xFFFFA500).withOpacity(0.15),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFFFD700).withOpacity(0.4),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.contact_phone, color: Color(0xFFFFD700), size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Contacto del Destinatario',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Dirección con botón GPS
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Color(0xFF1976D2), size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Dirección de Entrega',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF666666),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatearDireccionCompletaRemesa(),
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF1A1A1A),
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Botón de GPS
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: IconButton(
                            onPressed: () => _abrirGPSConDireccion(),
                            icon: const Icon(Icons.navigation, color: Colors.white, size: 20),
                            style: IconButton.styleFrom(
                              padding: const EdgeInsets.all(12),
                            ),
                            tooltip: 'Abrir GPS con dirección',
                          ),
                        ),
                      ],
                    ),
                    // Botones de contacto si hay teléfono
                    if (_ordenActual.telefonoDestinatario != null && _ordenActual.telefonoDestinatario!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(Icons.phone, color: Color(0xFF1976D2), size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Teléfono del Destinatario',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF666666),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  _ordenActual.telefonoDestinatario!,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Color(0xFF1A1A1A),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Botón de llamar
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF4CAF50),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: IconButton(
                              onPressed: () => _llamarDestinatario(_ordenActual.telefonoDestinatario!),
                              icon: const Icon(Icons.call, color: Colors.white, size: 20),
                              style: IconButton.styleFrom(
                                padding: const EdgeInsets.all(12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Botón de mensaje
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF1976D2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: IconButton(
                              onPressed: () => _enviarMensajeDestinatario(_ordenActual.telefonoDestinatario!),
                              icon: const Icon(Icons.message, color: Colors.white, size: 20),
                              style: IconButton.styleFrom(
                                padding: const EdgeInsets.all(12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Botón de WhatsApp
                          Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF25D366),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: IconButton(
                              onPressed: () => _enviarWhatsAppDestinatario(_ordenActual.telefonoDestinatario!),
                              icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Colors.white, size: 20),
                              style: IconButton.styleFrom(
                                padding: const EdgeInsets.all(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            if (estado == 'POR ENVIAR' || estado == 'ENTREGADO EN SUCURSAL') ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.6)),
                ),
                child: Text(
                  _ordenActual.recogerEnSucursal
                      ? (estado == 'ENTREGADO EN SUCURSAL'
                          ? 'Completa la entrega al destinatario (número de remesa e identificación). Sin firma ni foto.'
                          : 'En sucursal: puedes dejarla para que la entregue la sucursal, o entregarla tú al destinatario si está contigo. Sin firma ni foto.')
                      : 'Esta remesa no requiere firma ni foto. Confirma el número de remesa y la identificación del destinatario.',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF5D4037), height: 1.35),
                ),
              ),
              const SizedBox(height: 12),
            ],

            if (estado == 'POR ENVIAR' && _ordenActual.recogerEnSucursal) ...[
              VolonexActionButton(
                label: 'Solo dejar en sucursal',
                icon: Icons.store,
                outlined: true,
                foregroundColor: AppColors.botonPrincipal,
                onPressed: () => _marcarRemesaDetalleComoEntregada(soloDejarEnSucursal: true),
              ),
              const SizedBox(height: 10),
              VolonexActionButton(
                label: 'Entregar al destinatario',
                icon: Icons.check_circle,
                backgroundColor: AppColors.exito,
                onPressed: () => _marcarRemesaDetalleComoEntregada(entregarADestinatario: true),
              ),
            ] else if (estado == 'POR ENVIAR') ...[
              VolonexActionButton(
                label: 'Marcar Remesa como Entregada',
                icon: Icons.check_circle,
                backgroundColor: const Color(0xFFFFD700),
                foregroundColor: const Color(0xFF1A1A1A),
                onPressed: () => _marcarRemesaDetalleComoEntregada(entregarADestinatario: true),
              ),
            ] else if (estado == 'ENTREGADO EN SUCURSAL') ...[
              VolonexActionButton(
                label: 'Entregar al destinatario',
                icon: Icons.check_circle,
                backgroundColor: AppColors.exito,
                onPressed: () => _marcarRemesaDetalleComoEntregada(entregarADestinatario: true),
              ),
            ],
            
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
  
  // Helper para mostrar información de remesa
  Widget _buildRemesaDetalleInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF666666), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF666666),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF1A1A1A),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  // Chip de estado especial para remesas (POR ENVIAR, ENTREGADO EN SUCURSAL, ENTREGADO)
  Widget _buildRemesaDetalleStatusChip(String estado) {
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            estado,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  String _formatearDireccionCompletaRemesa() {
    final List<String> partes = [];
    if (_ordenActual.direccionDestino.isNotEmpty) {
      partes.add(_ordenActual.direccionDestino);
    }
    if (_ordenActual.municipioDestino != null && _ordenActual.municipioDestino!.isNotEmpty) {
      partes.add(_ordenActual.municipioDestino!);
    }
    if (_ordenActual.provinciaDestino != null && _ordenActual.provinciaDestino!.isNotEmpty) {
      partes.add(_ordenActual.provinciaDestino!);
    }
    return partes.isEmpty ? 'Dirección no especificada' : partes.join(', ');
  }
  
  String _formatearDireccionSucursalRemesa() {
    if (_sucursalInfo == null) return 'Dirección no especificada';
    final List<String> partes = [];
    if (_sucursalInfo!['direccion'] != null && _sucursalInfo!['direccion'].toString().isNotEmpty) {
      partes.add(_sucursalInfo!['direccion'].toString());
    }
    if (_sucursalInfo!['municipio'] != null && _sucursalInfo!['municipio'].toString().isNotEmpty) {
      partes.add(_sucursalInfo!['municipio'].toString());
    }
    if (_sucursalInfo!['provincia'] != null && _sucursalInfo!['provincia'].toString().isNotEmpty) {
      partes.add(_sucursalInfo!['provincia'].toString());
    }
    if (_sucursalInfo!['pais'] != null && _sucursalInfo!['pais'].toString().isNotEmpty) {
      partes.add(_sucursalInfo!['pais'].toString());
    }
    return partes.isEmpty ? 'Dirección no especificada' : partes.join(', ');
  }
  
  /// [soloDejarEnSucursal]: deja la remesa en la sucursal (estado intermedio).
  /// [entregarADestinatario]: entrega final al destinatario (ENTREGADO), también si estás en sucursal.
  Future<void> _marcarRemesaDetalleComoEntregada({
    bool soloDejarEnSucursal = false,
    bool entregarADestinatario = false,
  }) async {
    if (_ordenActual.estado == 'ENTREGADO') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Esta remesa ya está entregada'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
      return;
    }

    final estRemesa = _ordenActual.estado.trim().toUpperCase();
    final esPorEnviar = estRemesa.isEmpty || estRemesa == 'POR ENVIAR';

    // Dejar en sucursal (estado intermedio; luego otro repartidor o tú puedes completar)
    if (soloDejarEnSucursal) {
      if (!_ordenActual.recogerEnSucursal || !esPorEnviar) return;
      final confirmado = await showVolonexConfirmDialog(
        context,
        title: 'Entregar en Sucursal',
        message:
            '¿Confirmas que dejaste la remesa #${_ordenActual.numeroRemesa ?? _ordenActual.numeroOrden} en la sucursal?\n\nLa sucursal se encargará de entregarla al destinatario.',
        confirmColor: AppColors.botonPrincipal,
        icon: Icons.store,
        iconColor: AppColors.botonPrincipal,
      );
      
      if (confirmado != true) return;
      
      // ✅ OFFLINE-FIRST: Guardar en caché PRIMERO, luego sincronizar
      final syncService = SyncService();
      
      // Actualizar estado localmente INMEDIATAMENTE
      if (mounted) {
        setState(() {
          _ordenActual = Orden(
              id: _ordenActual.id,
              numeroOrden: _ordenActual.numeroOrden,
              numeroRemesa: _ordenActual.numeroRemesa,
              tenantId: _ordenActual.tenantId,
              emisor: _ordenActual.emisor,
              receptor: _ordenActual.receptor,
              direccionDestino: _ordenActual.direccionDestino,
              municipioDestino: _ordenActual.municipioDestino,
              provinciaDestino: _ordenActual.provinciaDestino,
              estado: 'ENTREGADO EN SUCURSAL',
              fechaCreacion: _ordenActual.fechaCreacion,
              fechaEntrega: _ordenActual.fechaEntrega,
              descripcion: _ordenActual.descripcion,
              cantidadBultos: _ordenActual.cantidadBultos,
              peso: _ordenActual.peso,
              largo: _ordenActual.largo,
              ancho: _ordenActual.ancho,
              alto: _ordenActual.alto,
              tieneRemesa: _ordenActual.tieneRemesa,
              cantidadRemesa: _ordenActual.cantidadRemesa,
              recogerEnSucursal: _ordenActual.recogerEnSucursal,
              sucursalId: _ordenActual.sucursalId,
              requierePago: _ordenActual.requierePago,
              montoCobrar: _ordenActual.montoCobrar,
              pagado: _ordenActual.pagado,
              moneda: _ordenActual.moneda,
              tipoOrden: _ordenActual.tipoOrden,
              repartidor: _ordenActual.repartidor,
              fotoEntrega: _ordenActual.fotoEntrega,
              requiereFirma: _ordenActual.requiereFirma,
              firmaUrl: _ordenActual.firmaUrl,
              notas: _ordenActual.notas,
              itemsAdicionales: _ordenActual.itemsAdicionales,
              goodbarberOrderId: _ordenActual.goodbarberOrderId,
              monedaPrecioTotalEnvio: _ordenActual.monedaPrecioTotalEnvio,
              precioTotalEnvio: _ordenActual.precioTotalEnvio,
            );
        });
      }
      
      // Guardar en caché local INMEDIATAMENTE
      await OrdenCacheService.updateCachedOrder(_ordenActual);
      print('💾 Remesa marcada como ENTREGADO EN SUCURSAL en caché local');
      
      // Preparar datos para sincronizar
      final updateData = {
        'estado': 'ENTREGADO EN SUCURSAL',
      };
      
      // Intentar actualizar en BD si hay conexión, si no, agregar a cola de sincronización
      if (syncService.isOnline) {
        try {
          await supabase
              .from('ordenes')
              .update(updateData)
              .eq('id', _ordenActual.id);
          
          print('✅ Remesa marcada como ENTREGADO EN SUCURSAL en BD (online)');
        } catch (e) {
          // Si falla, agregar a cola de sincronización
          final errorString = e.toString();
          if (errorString.contains('Failed host lookup') || 
              errorString.contains('SocketException') ||
              errorString.contains('ClientException')) {
            print('📴 Error de conexión - Agregando a cola de sincronización');
            await syncService.addOperation(
              type: 'update_orden_estado',
              ordenId: _ordenActual.id,
              data: updateData,
            );
          } else {
            // Error no relacionado con conexión
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Error: $e'),
                  backgroundColor: const Color(0xFFDC2626),
                ),
              );
            }
            return;
          }
        }
      } else {
        // Sin conexión - Agregar a cola de sincronización
        print('📴 Sin conexión - Agregando a cola de sincronización');
        await syncService.addOperation(
          type: 'update_orden_estado',
          ordenId: _ordenActual.id,
          data: updateData,
        );
      }
      
      // Mostrar mensaje de éxito y cerrar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Remesa marcada como entregada en sucursal'),
            backgroundColor: Color(0xFFFF9800),
          ),
        );
        Navigator.pop(context, true); // Retornar true para recargar lista
      }
      return;
    }

    if (!entregarADestinatario) return;

    // Entrega final al destinatario (domicilio o en sucursal): RMSA e ID, sin firma ni foto
    final numeroRemesa = _ordenActual.numeroRemesa ?? _ordenActual.numeroOrden;
    final nombreDestinatario = _ordenActual.receptor;
    
    // Primero mostrar modal explicativo con el número RMSA
    final continuarValidacion = await _mostrarModalValidacionRemesa(numeroRemesa, nombreDestinatario);
    if (continuarValidacion != true) return;
    
    // Pedir número RMSA del destinatario
    final rmsaValidado = await _pedirNumeroRMSA(numeroRemesa);
    if (rmsaValidado != true) return;
    
    // Verificar ID/carné del destinatario
    final idVerificado = await _verificarIDDestinatario(nombreDestinatario);
    if (idVerificado != true) return;
    
    // Firma: solo órdenes que no son remesa pura
    if (RemesaPuraEntregaUi.exigeFirmaEntrega(_ordenActual) &&
        (_firmaUrl == null || _firmaUrl!.isEmpty)) {
      print('✍️ Abriendo modal de firma para remesa...');
      final firmaObtenida = await _mostrarModalFirma();
      if (!firmaObtenida) {
        print('❌ Usuario canceló la firma');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Se requiere la firma del destinatario'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
        return;
      }
      print('✅ Firma capturada exitosamente para remesa: $_firmaUrl');
      
      // 🔒 CRÍTICO: Actualizar _ordenActual con la firma capturada
      // NO recargar desde BD porque puede sobrescribir la firma local
      try {
        final ordenJson = _ordenActual.toJson();
        ordenJson['firma_url'] = _firmaUrl;
        _ordenActual = Orden.fromJson(ordenJson);
        print('✅ _ordenActual actualizada con firma: $_firmaUrl');
      } catch (e) {
        print('⚠️ Error actualizando _ordenActual con firma: $e');
      }
      
      // Verificar que la firma se guardó correctamente
      print('');
      print('🔍 ========================================');
      print('🔍 VERIFICANDO FIRMA DESPUÉS DE CAPTURA');
      print('🔍 ========================================');
      print('🔍 _firmaUrl: $_firmaUrl');
      print('🔍 _ordenActual.firmaUrl: ${_ordenActual.firmaUrl}');
      print('🔍 _firmaUrl == null: ${_firmaUrl == null}');
      print('🔍 _firmaUrl.isEmpty: ${_firmaUrl?.isEmpty ?? "null"}');
      print('🔍 ========================================');
      print('');
      
      if (_firmaUrl == null || _firmaUrl!.isEmpty) {
        print('❌ Error: La firma no se guardó en _firmaUrl');
        print('❌ _ordenActual.firmaUrl: ${_ordenActual.firmaUrl}');
        
        // 🔒 CRÍTICO: Intentar recuperar firma desde _ordenActual
        if (_ordenActual.firmaUrl != null && _ordenActual.firmaUrl!.isNotEmpty) {
          print('✅ Recuperando firma desde _ordenActual.firmaUrl: ${_ordenActual.firmaUrl}');
          setState(() {
            _firmaUrl = _ordenActual.firmaUrl;
          });
          print('✅ _firmaUrl recuperada: $_firmaUrl');
        } else {
          // Si aún no hay firma, intentar recuperar desde caché
          try {
            final ordenCache = await OrdenCacheService.getCachedOrderById(_ordenActual.id);
            if (ordenCache != null && ordenCache.firmaUrl != null && ordenCache.firmaUrl!.isNotEmpty) {
              print('✅ Recuperando firma desde caché: ${ordenCache.firmaUrl}');
              setState(() {
                _firmaUrl = ordenCache.firmaUrl;
              });
              try {
                final ordenJson = _ordenActual.toJson();
                ordenJson['firma_url'] = ordenCache.firmaUrl;
                _ordenActual = Orden.fromJson(ordenJson);
                print('✅ _ordenActual actualizada con firma desde caché');
              } catch (e) {
                print('⚠️ Error actualizando _ordenActual: $e');
              }
              print('✅ _firmaUrl recuperada desde caché: $_firmaUrl');
            } else {
              print('❌ No se encontró firma en caché tampoco');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('❌ Error: La firma no se guardó correctamente. Intenta de nuevo.'),
                  backgroundColor: Color(0xFFDC2626),
                ),
              );
              return;
            }
          } catch (e) {
            print('❌ Error recuperando firma desde caché: $e');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('❌ Error: La firma no se guardó correctamente. Intenta de nuevo.'),
                backgroundColor: Color(0xFFDC2626),
              ),
            );
            return;
          }
        }
      }
    }
    
    // Foto de entrega: no aplica a remesas puras
    if (RemesaPuraEntregaUi.exigeFotoEntrega(_ordenActual, _fotoEntregaObligatoria) &&
        (_fotoEntregaUrl == null || _fotoEntregaUrl!.isEmpty)) {
      print('📷 PASO 4: Foto obligatoria pero no tomada');
      
      // Usar el método existente que maneja todo el flujo de foto
      await _tomarFotoEntregaConSelector();
      
      // Verificar que la foto se capturó correctamente
      if (_fotoEntregaUrl == null || _fotoEntregaUrl!.isEmpty) {
        print('❌ Error: La foto no se capturó correctamente');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ No se pudo obtener la foto. Intenta de nuevo.'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
        return;
      }
      
      // 🔒 CRÍTICO: Actualizar _ordenActual con la foto capturada
      // NO recargar desde BD porque puede sobrescribir la foto local
      try {
        final ordenJson = _ordenActual.toJson();
        ordenJson['foto_entrega'] = _fotoEntregaUrl;
        _ordenActual = Orden.fromJson(ordenJson);
        print('✅ _ordenActual actualizada con foto: $_fotoEntregaUrl');
      } catch (e) {
        print('⚠️ Error actualizando _ordenActual con foto: $e');
      }
      
      print('✅ Foto capturada exitosamente para remesa: $_fotoEntregaUrl');
    }
    
    // Confirmación final
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Entrega de Remesa'),
        content: Text('¿Confirmas que entregaste la remesa #$numeroRemesa correctamente al destinatario?\n\nCantidad: \$${(_ordenActual.cantidadRemesa ?? 0.0).toStringAsFixed(2)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: const Color(0xFF1A1A1A),
            ),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    
    if (confirmado != true) return;
    
    // ✅ OFFLINE-FIRST: Guardar fotos y firmas en caché PRIMERO, luego sincronizar
    final fechaEntrega = DateTime.now();
    final syncService = SyncService();
    final offlineStorage = OfflineStorageService();
    
    // 🔒 CRÍTICO: Guardar foto en caché local SI EXISTE
    if (_fotoEntregaUrl != null && _fotoEntregaUrl!.isNotEmpty) {
      // Si la foto es local (empieza con local://), extraer la ruta
      String? photoPath;
      if (_fotoEntregaUrl!.startsWith('local://')) {
        photoPath = _fotoEntregaUrl!.substring(8); // Remover "local://"
      } else if (_fotoEntregaUrl!.startsWith('file://')) {
        photoPath = _fotoEntregaUrl!.substring(7); // Remover "file://"
      } else {
        // Si es una URL de Supabase, intentar obtener la ruta local si existe
        // Por ahora, si no es local, no la guardamos en pending_photos
        print('⚠️ Foto es URL remota, no se guarda en pending_photos');
      }
      
      if (photoPath != null) {
        try {
          await offlineStorage.savePendingPhoto(
            ordenId: _ordenActual.id,
            filePath: photoPath,
          );
          print('💾 Foto guardada en caché local: $photoPath');
        } catch (e) {
          print('⚠️ Error guardando foto en caché: $e');
        }
      }
    }
    
    // 🔒 CRÍTICO: Guardar firma en caché local SI EXISTE
    if (_firmaUrl != null && _firmaUrl!.isNotEmpty) {
      // Si la firma es local (empieza con local://), extraer la ruta
      String? signaturePath;
      if (_firmaUrl!.startsWith('local://')) {
        signaturePath = _firmaUrl!.substring(8); // Remover "local://"
      } else if (_firmaUrl!.startsWith('file://')) {
        signaturePath = _firmaUrl!.substring(7); // Remover "file://"
      } else {
        // Si es una URL de Supabase, intentar obtener la ruta local si existe
        print('⚠️ Firma es URL remota, no se guarda en pending_signatures');
      }
      
      if (signaturePath != null) {
        try {
          await offlineStorage.savePendingSignature(
            ordenId: _ordenActual.id,
            filePath: signaturePath,
          );
          print('💾 Firma guardada en caché local: $signaturePath');
        } catch (e) {
          print('⚠️ Error guardando firma en caché: $e');
        }
      }
    }
    
    // Actualizar estado localmente INMEDIATAMENTE
    if (mounted) {
      setState(() {
        _ordenActual.estado = 'ENTREGADO';
        _ordenActual.fechaEntrega = fechaEntrega;
      });
    }
    
    // Guardar en caché local INMEDIATAMENTE
    await OrdenCacheService.updateCachedOrder(_ordenActual);
    print('💾 Remesa marcada como ENTREGADA en caché local');
    
    // Preparar datos para sincronizar
    final updateData = <String, dynamic>{
      'estado': 'ENTREGADO',
      'fecha_entrega': fechaEntrega.toIso8601String(),
    };
    
    if (!_esRemesaPura()) {
      if (_firmaUrl != null && _firmaUrl!.isNotEmpty) {
        updateData['firma_url'] = _firmaUrl;
      }
      if (_fotoEntregaUrl != null && _fotoEntregaUrl!.isNotEmpty) {
        updateData['foto_entrega'] = _fotoEntregaUrl;
      }
    }
    
    // Intentar actualizar en BD si hay conexión, si no, agregar a cola de sincronización
    if (syncService.isOnline) {
      try {
        await supabase
            .from('ordenes')
            .update(updateData)
            .eq('id', _ordenActual.id);
        
        print('✅ Remesa marcada como ENTREGADA en BD (online)');
      } catch (e) {
        // Si falla, agregar a cola de sincronización
        final errorString = e.toString();
        if (errorString.contains('Failed host lookup') || 
            errorString.contains('SocketException') ||
            errorString.contains('ClientException')) {
          print('📴 Error de conexión - Agregando a cola de sincronización');
          await syncService.addOperation(
            type: 'update_orden_estado',
            ordenId: _ordenActual.id,
            data: updateData,
          );
        } else {
          // Error no relacionado con conexión, mostrar al usuario
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: $e'),
                backgroundColor: const Color(0xFFDC2626),
              ),
            );
          }
          return;
        }
      }
    } else {
      // Sin conexión - Agregar a cola de sincronización
      print('📴 Sin conexión - Agregando a cola de sincronización');
      await syncService.addOperation(
        type: 'update_orden_estado',
        ordenId: _ordenActual.id,
        data: updateData,
      );
    }
    
    // Cerrar pantalla y volver a la lista
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Remesa marcada como entregada'),
          backgroundColor: Color(0xFF4CAF50),
        ),
      );
      Navigator.pop(context, true); // Retornar true para recargar lista
    }
  }
  
  // Modal explicativo para validación de remesa
  Future<bool?> _mostrarModalValidacionRemesa(String numeroRemesa, String nombreDestinatario) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.security, color: Color(0xFFFFD700), size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Validación de Remesa',
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
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFFD700).withOpacity(0.2),
                    const Color(0xFFFFA500).withOpacity(0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD700), width: 2),
              ),
              child: Column(
                children: [
                  const Text(
                    'Número de Remesa',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF666666),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '#$numeroRemesa',
                    style: const TextStyle(
                      fontSize: 32,
                      color: Color(0xFF1A1A1A),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Instrucciones de Seguridad:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C2C2C),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '1. Pregunta al destinatario por el número de remesa: #$numeroRemesa',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF666666),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '2. Verifica el ID/carné de identidad del destinatario',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF666666),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '   Nombre completo: $nombreDestinatario',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF999999),
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '3. Confirma que el nombre y apellido del ID coinciden con el destinatario de la remesa',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF666666),
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: const Color(0xFF1A1A1A),
            ),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }
  
  // Verificar número RMSA - Solo confirmación visual, sin campo de texto
  Future<bool?> _pedirNumeroRMSA(String numeroRemesaEsperado) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.verified_user, color: Color(0xFFFFD700), size: 24),
            SizedBox(width: 12),
            Expanded(
              child: Text('Verificar Número RMSA'),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Por favor, verifica que el cliente conoce el número de remesa:',
              style: TextStyle(
                fontSize: 15,
                color: Color(0xFF333333),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD700).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD700), width: 2),
              ),
              child: Column(
                children: [
                  const Text(
                    'Número de Remesa:',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF666666),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '#$numeroRemesaEsperado',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                      letterSpacing: 1.2,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1976D2), width: 1),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFF1976D2), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Pregunta al cliente por el número y verifica que lo conoce correctamente.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Color(0xFF1976D2),
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
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF666666),
            ),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              // Confirmar que el repartidor verificó el número
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: const Color(0xFF1A1A1A),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, size: 20),
                SizedBox(width: 8),
                Text(
                  'Verificar',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  // Verificar ID/carné del destinatario
  Future<bool?> _verificarIDDestinatario(String nombreDestinatarioEsperado) async {
    final controller = TextEditingController();
    
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.credit_card, color: Color(0xFFFFD700), size: 24),
            SizedBox(width: 12),
            Text('Verificar ID/Carné'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Verifica el ID/carné de identidad del destinatario:',
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF666666),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nombre esperado:',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF666666),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    nombreDestinatarioEsperado,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1976D2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Nombre completo del ID/Carné',
                hintText: 'Escribe el nombre tal como aparece en el ID',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3E0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFFF9800), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Confirma que el nombre y apellido coinciden exactamente con el destinatario',
                      style: TextStyle(
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
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              final nombreID = controller.text.trim().toUpperCase();
              final nombreEsperado = nombreDestinatarioEsperado.toUpperCase();
              
              // Verificar que el nombre del ID contenga palabras clave del nombre esperado
              final palabrasEsperadas = nombreEsperado.split(' ');
              final coincide = palabrasEsperadas.any((palabra) => 
                palabra.isNotEmpty && nombreID.contains(palabra)
              ) || nombreID.contains(nombreEsperado);
              
              if (coincide || nombreID == nombreEsperado) {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('⚠️ Verifica que el nombre del ID coincida con el destinatario'),
                    backgroundColor: Color(0xFFFF9800),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: const Color(0xFF1A1A1A),
            ),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  /// Recogida con empresa: datos del colaborador para coordinar la recolección del pedido.
  Widget _buildColaboradorRecogidaCard() {
    final nombre = _ordenActual.vendedorContactoNombre?.trim();
    final tel = _ordenActual.vendedorContactoTelefono?.trim();
    final email = _ordenActual.vendedorContactoEmail?.trim();
    return Card(
      elevation: 3,
      color: const Color(0xFFE8F5E9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF4CAF50), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.storefront, color: Color(0xFF2E7D32), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Contacto del colaborador (recogida)',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2C2C2C),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              OrdenRecogidaColaboradorUi.enFaseRecogidaColaborador(_ordenActual)
                  ? 'Recoge el pedido solo en el punto del colaborador. La dirección del cliente se mostrará después de confirmar la recogida.'
                  : 'Coordina con el colaborador para recoger el pedido en el punto acordado.',
              style: TextStyle(fontSize: 13, color: const Color(0xFF666666)),
            ),
            if (nombre != null && nombre.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildInfoRow(Icons.badge_outlined, 'Nombre', nombre),
            ],
            if (tel != null && tel.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildInfoRow(Icons.phone, 'Teléfono', tel),
            ],
            if (email != null && email.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildInfoRow(Icons.email_outlined, 'Correo', email),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      elevation: 3,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'Información de la Orden',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C2C2C),
                    ),
                  ),
                ),
                Flexible(
                  child: _buildStatusChip(
                    OrdenRecogidaColaboradorUi.estadoVisibleRepartidor(_ordenActual),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            _buildInfoRow(
              Icons.confirmation_number, 
              'Número de Orden', 
              '#${widget.orden.numeroOrden.isNotEmpty ? widget.orden.numeroOrden : (widget.orden.id.length > 8 ? widget.orden.id.substring(0, 8) : widget.orden.id)}'
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.person, 
              'Emisor', 
              widget.orden.emisor.isNotEmpty ? widget.orden.emisor : 'No especificado'
            ),
            const SizedBox(height: 8),
            _buildInfoRow(Icons.schedule, 'Fecha de Creación', _formatearFecha(widget.orden.fechaCreacion)),
            if (widget.orden.fechaEntrega != null) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                Icons.local_shipping, 
                widget.orden.tipoOrden == 'RECOGIDA' ? 'Fecha de Recogida' : 'Fecha de Entrega', 
                _formatearFecha(widget.orden.fechaEntrega)
              ),
            ],
            const SizedBox(height: 8),
            _buildInfoRow(Icons.description, 'Descripción', widget.orden.descripcion),
            if (widget.orden.notas != null && widget.orden.notas!.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildInfoRow(Icons.note, 'Notas Adicionales', widget.orden.notas!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard() {
    if (OrdenRecogidaColaboradorUi.enFaseRecogidaColaborador(_ordenActual)) {
      return const SizedBox.shrink();
    }

    final bool esRecogida = _ordenActual.tipoOrden == 'RECOGIDA';
    final bool esPickupGoodBarber = _ordenActual.recogerEnSucursal == true && 
                                    _ordenActual.goodbarberOrderId != null;
    
    // 🔥 REGLA: Para órdenes de GoodBarber con pickup, mostrar como orden normal (sin tarjeta especial)
    // Para órdenes normales de VolonexPro+ con recoger_en_sucursal, mostrar tarjeta verde de recogida
    print('✅✅✅ [DETALLE ORDEN] _buildContactCard() - Mostrando información del Destinatario ✅✅✅');
    print('   - recogerEnSucursal: ${_ordenActual.recogerEnSucursal}');
    print('   - recogerEnSucursal (tipo): ${_ordenActual.recogerEnSucursal.runtimeType}');
    print('   - goodbarberOrderId: ${_ordenActual.goodbarberOrderId}');
    print('   - esPickupGoodBarber: $esPickupGoodBarber (si es true, mostrar como orden normal)');
    print('   - direccionDestino: "${_ordenActual.direccionDestino}"');
    print('   - municipioDestino: ${_ordenActual.municipioDestino}');
    print('   - provinciaDestino: ${_ordenActual.provinciaDestino}');
    
    return Card(
      elevation: 3,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              esRecogida ? 'Información del Cliente' : 'Información del Destinatario',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C2C2C),
              ),
            ),
            const SizedBox(height: 16),
            
            // Nombre del cliente/destinatario
            _buildInfoRow(
              Icons.person_outline, 
              'Nombre', 
              esRecogida ? _ordenActual.emisor : _ordenActual.receptor
            ),
            const SizedBox(height: 12),
            
            // Dirección completa de recogida/entrega con botón de GPS
            Row(
              children: [
                const Icon(Icons.location_on, color: Color(0xFF1976D2), size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        esRecogida ? 'Dirección de Recogida' : 'Dirección de Entrega',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF666666),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Mostrar dirección completa con todas las partes
                      Text(
                        _formatearDireccionCompleta(),
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFF2C2C2C),
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                // Botón de GPS
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50), // Verde para GPS
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    onPressed: () => _abrirGPSConDireccion(),
                    icon: const Icon(Icons.navigation, color: Colors.white, size: 20),
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(12),
                    ),
                    tooltip: 'Abrir GPS con dirección completa',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            
            // País - Solo para órdenes de recogida
            if (esRecogida) ...[
              FutureBuilder<String?>(
                future: _obtenerPaisOperacion(),
                builder: (context, snapshot) {
                  final pais = snapshot.data ?? 'N/A';
                  return _buildInfoRow(
                    Icons.public, 
                    'País', 
                    pais
                  );
                },
              ),
              const SizedBox(height: 12),
            ],
            
            // 🔥 TARJETA AZUL DE "ENTREGAR EN SUCURSAL": Solo para órdenes de GoodBarber con pickup activo
            // Esta tarjeta muestra la información de la tienda/sucursal donde el cliente debe recoger su pedido
            Builder(
              builder: (context) {
                final esGoodBarber = _ordenActual.goodbarberOrderId != null;
                final tienePickup = _ordenActual.recogerEnSucursal == true;
                
                print('🔵 [TARJETA AZUL] Verificando condiciones para mostrar "Entregar en Sucursal":');
                print('   - goodbarberOrderId: ${_ordenActual.goodbarberOrderId}');
                print('   - esGoodBarber: $esGoodBarber');
                print('   - recogerEnSucursal: ${_ordenActual.recogerEnSucursal}');
                print('   - tienePickup: $tienePickup');
                print('   - Condición completa: ${esGoodBarber && tienePickup}');
                
                if (esGoodBarber && tienePickup) {
                  return Column(
                    children: [
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F2FD), // Fondo azul claro
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFF2196F3), // Borde azul
                            width: 2,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2196F3).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.store,
                                    color: Color(0xFF2196F3),
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Entregar en Sucursal',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1565C0),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildInfoRow(
                              Icons.location_on,
                              'Dirección de la Tienda',
                              _ordenActual.direccionDestino.isNotEmpty
                                  ? _ordenActual.direccionDestino
                                  : 'Dirección no disponible',
                            ),
                            if (_ordenActual.municipioDestino != null && _ordenActual.municipioDestino!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _buildInfoRow(
                                Icons.location_city,
                                'Municipio',
                                _ordenActual.municipioDestino!,
                              ),
                            ],
                            if (_ordenActual.provinciaDestino != null && _ordenActual.provinciaDestino!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _buildInfoRow(
                                Icons.map,
                                'Provincia',
                                _ordenActual.provinciaDestino!,
                              ),
                            ],
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2196F3),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.shopping_bag, color: Colors.white, size: 16),
                                  SizedBox(width: 6),
                                  Text(
                                    'Recogida desde GoodBarber',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            
            // 🔥 TARJETA VERDE DE RECOGIDA EN SUCURSAL: Solo para órdenes NORMALES de VolonexPro+ (sin GoodBarber)
            // Para órdenes de GoodBarber con pickup, NO se muestra esta tarjeta - se muestran como órdenes normales
            // 🔥 VERIFICACIÓN ABSOLUTA: Si es GoodBarber, NUNCA mostrar esta sección, sin importar el estado
            if (_ordenActual.goodbarberOrderId == null && 
                _ordenActual.recogerEnSucursal && 
                _sucursalInfo != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9), // Fondo verde claro más llamativo
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF4CAF50), // Borde verde
                    width: 2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.store,
                            color: Color(0xFF4CAF50),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Recogida en Sucursal',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2E7D32),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow(
                      Icons.store,
                      'Sucursal',
                      _sucursalInfo!['nombre'] ?? 'Sin nombre',
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow(
                      Icons.location_on,
                      'Dirección de Recogida',
                      _formatearDireccionSucursal(_sucursalInfo!),
                    ),
                    if (_sucursalInfo!['es_principal'] == true) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star, color: Colors.white, size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Sucursal Principal',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
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
              const SizedBox(height: 20), // Más margen después del recuadro de Recogida en Sucursal
            ],
            
            // Teléfono del cliente/destinatario
            if (_ordenActual.telefonoDestinatario != null && _ordenActual.telefonoDestinatario!.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.phone, color: Color(0xFF1976D2), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          esRecogida ? 'Teléfono del Cliente' : 'Teléfono del Destinatario',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF666666),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          _ordenActual.telefonoDestinatario!,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Color(0xFF2C2C2C),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Botón de llamar
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      onPressed: () => _llamarDestinatario(_ordenActual.telefonoDestinatario!),
                      icon: const Icon(Icons.call, color: Colors.white, size: 20),
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Botón de mensaje
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1976D2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      onPressed: () => _enviarMensajeDestinatario(_ordenActual.telefonoDestinatario!),
                      icon: const Icon(Icons.message, color: Colors.white, size: 20),
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Botón de WhatsApp
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF25D366), // Color verde de WhatsApp
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      onPressed: () => _enviarWhatsAppDestinatario(_ordenActual.telefonoDestinatario!),
                      icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Colors.white, size: 20),
                      style: IconButton.styleFrom(
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const Row(
                children: [
                  Icon(Icons.phone_disabled, color: Color(0xFF999999), size: 20),
                  SizedBox(width: 12),
                  Text(
                    'No hay teléfono disponible',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF999999),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryCard() {
    return Card(
      elevation: 3,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Detalles del Paquete',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C2C2C),
              ),
            ),
            const SizedBox(height: 16),
            
            _buildInfoRow(Icons.inventory_2, 'Cantidad de Bultos', '${_ordenActual.cantidadBultos} ${_ordenActual.cantidadBultos == 1 ? 'bulto' : 'bultos'}'),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.scale, 
              'Peso', 
              (_ordenActual.peso != null && _ordenActual.peso! > 0) 
                  ? '${_ordenActual.peso} lb' 
                  : 'No especificado'
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.straighten, 
              'Dimensiones', 
              (_ordenActual.largo != null && _ordenActual.largo! > 0 && 
               _ordenActual.ancho != null && _ordenActual.ancho! > 0 && 
               _ordenActual.alto != null && _ordenActual.alto! > 0)
                  ? '${_ordenActual.largo} x ${_ordenActual.ancho} x ${_ordenActual.alto} cm'
                  : 'No especificadas'
            ),
            // Mostrar remesa si existe (siempre mostrar si tiene_remesa es true, incluso si cantidad es null)
            if (_ordenActual.tieneRemesa) ...[
              const SizedBox(height: 8),
              _buildInfoRow(
                Icons.attach_money, 
                'Remesa', 
                _ordenActual.cantidadRemesa != null 
                    ? '\$${_ordenActual.cantidadRemesa!.toStringAsFixed(2)}'
                    : 'No especificada',
              ),
            ],
          ],
        ),
      ),
    );
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

  Widget _buildPaymentCard() {
    return Card(
      elevation: 3,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Información de Pago',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C2C2C),
              ),
            ),
            const SizedBox(height: 16),
            
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF4CAF50)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.attach_money, color: Color(0xFF4CAF50), size: 24),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Monto a Cobrar',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF666666),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '${widget.orden.moneda == 'USD' ? '\$' : '\$'} ${widget.orden.montoCobrar.toStringAsFixed(2)} ${widget.orden.moneda}',
                        style: const TextStyle(
                          fontSize: 20,
                          color: Color(0xFF4CAF50),
                          fontWeight: FontWeight.bold,
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
    );
  }

  Widget _buildRemesaCard() {
    final cantidadRemesa = _ordenActual.cantidadRemesa ?? 0.0;
    
    return Card(
      elevation: 3,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Información de Remesa',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C2C2C),
              ),
            ),
            const SizedBox(height: 16),
            
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2196F3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.attach_money, color: Color(0xFF2196F3), size: 24),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Remesa a Entregar',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF666666),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '\$${cantidadRemesa.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 20,
                          color: Color(0xFF2196F3),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9800).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFF9800).withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Color(0xFFFF9800), size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Debes entregar esta remesa al cliente al momento de la entrega',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF666666),
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
    );
  }

  Widget _buildStatusHistoryCard() {
    return Card(
      elevation: 3,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Historial de Estados',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C2C2C),
              ),
            ),
            const SizedBox(height: 16),
            
            _buildStatusTimeline(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildProcesoRecogidaSucursalCard() {
    final direccionSucursal = _formatearDireccionSucursal(_sucursalInfo!);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9), // Fondo verde claro
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF4CAF50), // Borde verde
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.info_outline,
                  color: Color(0xFF4CAF50),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Proceso de Recogida en Sucursal',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2E7D32),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Instrucciones importantes:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2E7D32),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '1. Después de marcar esta orden como "EN TRANSITO", debes llevarla a la sucursal indicada.\n\n'
            '2. Dirección de la sucursal:\n$direccionSucursal\n\n'
            '3. Una vez que llegues a la sucursal, marca la orden como "EN REPARTO" y luego como "Listo para recoger".\n\n'
            '4. La orden quedará disponible en la sucursal para que el cliente la recoja.',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF2C2C2C),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTimeline() {
    final bool esRecogida = _ordenActual.tipoOrden == 'RECOGIDA';
    final bool esRecogColab = OrdenRecogidaColaboradorUi.esRecogidaColaborador(_ordenActual);
    final List<String> estados;
    final int indiceActual;

    if (esRecogColab) {
      estados = OrdenRecogidaColaboradorUi.estadosTimeline;
      indiceActual = OrdenRecogidaColaboradorUi.indiceEstadoTimeline(_ordenActual);
    } else if (esRecogida) {
      estados = ['POR RECOGER', 'EN CAMINO', 'RECOGIDO'];
      final estadoActual = _ordenActual.estado.trim().toUpperCase();
      indiceActual = estados.indexOf(estadoActual);
    } else {
      if (_ordenActual.recogerEnSucursal) {
        estados = ['POR ENVIAR', 'EN TRANSITO', 'EN REPARTO', 'LISTO PARA RECOGER', 'ENTREGADO'];
      } else {
        estados = ['POR ENVIAR', 'EN TRANSITO', 'EN REPARTO', 'ENTREGADO'];
      }
      final estadoActual = _ordenActual.estado.trim().toUpperCase();
      indiceActual = estados.indexOf(estadoActual);
    }
    
    return Column(
      children: estados.asMap().entries.map((entry) {
        final index = entry.key;
        final estado = entry.value;
        final isCompleted = index <= indiceActual;
        final isCurrent = index == indiceActual;
        
        return Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isCompleted ? const Color(0xFF4CAF50) : Colors.grey[300],
                shape: BoxShape.circle,
                border: isCurrent ? Border.all(color: const Color(0xFF1976D2), width: 3) : null,
              ),
              child: isCompleted
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    estado,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                      color: isCompleted ? const Color(0xFF2C2C2C) : Colors.grey[600],
                    ),
                  ),
                  if (isCurrent)
                    const Text(
                      'Estado actual',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF1976D2),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildActionButtons() {
    return Card(
      elevation: 3,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Acciones',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2C2C2C),
              ),
            ),
            const SizedBox(height: 16),
            
            // Botón único progresivo (igual que pantalla principal)
            SizedBox(
              width: double.infinity,
              child: _buildBotonAccionProgresivo(),
            ),
          ],
        ),
      ),
    );
  }

  /// Formatea la dirección completa incluyendo calle, municipio, provincia, etc.
  String _formatearDireccionCompleta() {
    final List<String> partes = [];
    
    // 1. Dirección principal (calle)
    if (_ordenActual.direccionDestino.isNotEmpty) {
      partes.add(_ordenActual.direccionDestino);
    }
    
    // 2. Municipio
    if (_ordenActual.municipioDestino != null && _ordenActual.municipioDestino!.isNotEmpty) {
      partes.add(_ordenActual.municipioDestino!);
    }
    
    // 3. Provincia
    if (_ordenActual.provinciaDestino != null && _ordenActual.provinciaDestino!.isNotEmpty) {
      partes.add(_ordenActual.provinciaDestino!);
    }
    
    // Si no hay ninguna parte, mostrar mensaje
    if (partes.isEmpty) {
      return 'Dirección no especificada';
    }
    
    // Unir todas las partes con comas
    return partes.join(', ');
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF666666), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF666666),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF2C2C2C),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String estado) {
    Color color;
    IconData icon;
    
    // Texto a mostrar (puede ser abreviado si es muy largo)
    String textoMostrar = estado;
    if (estado == 'LISTO PARA RECOGER') {
      textoMostrar = 'LISTO PARA REC.';
    } else if (estado == 'EN REPARTO') {
      textoMostrar = 'EN REPARTO';
    }
    
    switch (estado) {
      case 'POR RECOLECTAR':
        color = const Color(0xFFE65100);
        icon = Icons.storefront;
        break;
      case 'LISTO PARA RECOGIDA':
        color = const Color(0xFF2E7D32);
        icon = Icons.inventory_2;
        break;
      case 'EN CAMINO A RECOGER':
        color = const Color(0xFF1976D2);
        icon = Icons.directions_car;
        break;
      case 'POR ENVIAR':
        color = const Color(0xFFFF9800);
        icon = Icons.schedule;
        break;
      case 'EN TRANSITO':
        color = const Color(0xFF2196F3);
        icon = Icons.local_shipping;
        break;
      case 'EN REPARTO':
        color = const Color(0xFFFF9800);
        icon = Icons.delivery_dining;
        break;
      case 'LISTO PARA RECOGER':
        color = const Color(0xFFFF9800);
        icon = Icons.store;
        break;
      case 'ENTREGADO':
        color = const Color(0xFF4CAF50);
        icon = Icons.check_circle;
        break;
      case 'CANCELADA':
        color = const Color(0xFFF44336);
        icon = Icons.cancel;
        break;
      default:
        color = const Color(0xFF666666);
        icon = Icons.help;
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              textoMostrar,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  String _formatearFecha(DateTime? fecha) {
    if (fecha == null) return 'No especificada';
    return '${fecha.day}/${fecha.month}/${fecha.year}';
  }

  void _llamarDestinatario(String telefono) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: telefono);
    
    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        _mostrarMensaje('No se puede realizar la llamada');
      }
    } catch (e) {
      _mostrarMensaje('Error al realizar la llamada: $e');
    }
  }

  void _enviarMensajeDestinatario(String telefono) async {
    final Uri smsUri = Uri(scheme: 'sms', path: telefono);
    
    try {
      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri);
      } else {
        _mostrarMensaje('No se puede enviar mensaje');
      }
    } catch (e) {
      _mostrarMensaje('Error al enviar mensaje: $e');
    }
  }

  void _enviarWhatsAppDestinatario(String telefono) async {
    // Limpiar el teléfono de caracteres especiales (solo números)
    String telefonoLimpio = telefono.replaceAll(RegExp(r'[^\d+]'), '');
    
    // Si tiene +, mantenerlo y limpiar solo espacios y guiones
    if (telefono.contains('+')) {
      telefonoLimpio = telefono.replaceAll(RegExp(r'[^\d+]'), '');
    } else {
      telefonoLimpio = telefono.replaceAll(RegExp(r'[^\d]'), '');
    }
    
    // Remover el + para construir la URL (WhatsApp no lo necesita en la URL)
    final telefonoSinMas = telefonoLimpio.replaceAll('+', '');
    
    if (telefonoSinMas.isEmpty) {
      _mostrarMensaje('Número de teléfono inválido');
      return;
    }
    
    // Construir URL de WhatsApp (formato estándar)
    final String whatsappUrl = 'https://wa.me/$telefonoSinMas';
    
    try {
      final Uri uri = Uri.parse(whatsappUrl);
      // Intentar abrir directamente sin verificar primero
      await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      // Si falla, intentar con el formato alternativo
      try {
        final Uri uriAlt = Uri.parse('https://api.whatsapp.com/send?phone=$telefonoSinMas');
        await launchUrl(
          uriAlt,
          mode: LaunchMode.externalApplication,
        );
      } catch (e2) {
        _mostrarMensaje('No se puede abrir WhatsApp. Verifica que esté instalado.');
      }
    }
  }

  Future<String?> _obtenerPaisOperacion() async {
    try {
      if (_ordenActual.tenantId != null) {
        final pais = await PaisesService.obtenerPaisOperacion(_ordenActual.tenantId!);
        if (pais != null && pais.isNotEmpty) {
          return pais;
        }
      }
      // Si no hay tenantId, intentar obtener del usuario actual
      final paisActual = await PaisesService.obtenerPaisOperacionActual();
      return paisActual ?? 'N/A';
    } catch (e) {
      print('❌ Error obteniendo país: $e');
      return 'N/A';
    }
  }

  void _abrirGPSConDireccion() async {
    // ✅ FIX: Construir dirección LIMPIA sin datos codificados innecesarios
    final List<String> partesDireccion = [];
    
    // Agregar dirección principal
    if (_ordenActual.direccionDestino.isNotEmpty) {
      partesDireccion.add(_ordenActual.direccionDestino);
    }
    
    // Agregar municipio si existe
    if (_ordenActual.municipioDestino != null && 
        _ordenActual.municipioDestino!.isNotEmpty &&
        _ordenActual.municipioDestino != 'N/A') {
      partesDireccion.add(_ordenActual.municipioDestino!);
    }
    
    // Agregar provincia si existe
    if (_ordenActual.provinciaDestino != null && 
        _ordenActual.provinciaDestino!.isNotEmpty &&
        _ordenActual.provinciaDestino != 'N/A') {
      partesDireccion.add(_ordenActual.provinciaDestino!);
    }
    
    // ✅ NO agregar país automáticamente - solo dirección limpia
    
    // Construir dirección completa
    final direccionCompleta = partesDireccion.join(', ');
    
    if (direccionCompleta.isEmpty) {
      _mostrarMensaje('No hay dirección disponible para abrir en el GPS');
      return;
    }
    
    print('🗺️ Abriendo GPS con dirección: $direccionCompleta');
    
    // ✅ Codificar SOLO para URL, no para mostrar al usuario
    final direccionEncoded = Uri.encodeComponent(direccionCompleta);
    
    // Intentar abrir Google Maps (el más compatible)
    try {
      // Intentar Google Maps app primero (Android/iOS)
      final Uri googleMapsApp = Uri.parse('comgooglemaps://?q=$direccionEncoded');
      if (await canLaunchUrl(googleMapsApp)) {
        await launchUrl(googleMapsApp, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (e) {
      print('⚠️ Google Maps app no disponible, intentando web...');
    }
    
    // Si no se pudo abrir la app, intentar la versión web
    try {
      final Uri googleMapsWeb = Uri.parse('https://www.google.com/maps/search/?api=1&query=$direccionEncoded');
      await launchUrl(googleMapsWeb, mode: LaunchMode.externalApplication);
      return;
    } catch (e) {
      print('⚠️ Error abriendo Google Maps web: $e');
    }
    
    // Último intento: Android Maps genérico
    try {
      final Uri androidMaps = Uri.parse('geo:0,0?q=$direccionEncoded');
      await launchUrl(androidMaps, mode: LaunchMode.externalApplication);
      return;
    } catch (e) {
      print('⚠️ Error abriendo Android Maps: $e');
    }
    
    // Si nada funciona, mostrar mensaje con la dirección limpia
    _mostrarMensaje('No se pudo abrir el GPS.\n\nDirección: $direccionCompleta');
  }

  void _mostrarOpciones() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40), // Más padding inferior
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            
            // Opciones
            _buildOptionTile(
              icon: Icons.phone,
              title: 'Llamar al Destinatario',
              color: const Color(0xFF4CAF50),
              onTap: () {
                Navigator.pop(context);
                if (widget.orden.telefonoDestinatario != null && widget.orden.telefonoDestinatario!.isNotEmpty) {
                  _llamarDestinatario(widget.orden.telefonoDestinatario!);
                } else {
                  _mostrarMensaje('No hay teléfono disponible');
                }
              },
            ),
            const SizedBox(height: 30), // Más espacio al final
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 16),
          ],
        ),
      ),
    );
  }


  // Botón único progresivo (igual que pantalla principal)
  Widget _buildBotonAccionProgresivo() {
    switch (_ordenActual.estado) {
      case 'POR ENVIAR':
        if (OrdenRecogidaColaboradorUi.puedeIniciarRecolecta(_ordenActual)) {
          return ElevatedButton.icon(
            onPressed: _isLoading ? null : () => _iniciarRecolectaColaborador(),
            icon: const Icon(Icons.directions_car, size: 20),
            label: const Text('Iniciar recolecta'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1976D2),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
        if (OrdenRecogidaColaboradorUi.puedeConfirmarRecogida(_ordenActual)) {
          return ElevatedButton.icon(
            onPressed: _isLoading ? null : () => _confirmarRecogidaEnColaborador(),
            icon: const Icon(Icons.check_circle_outline, size: 20),
            label: const Text('Confirmar recogida en colaborador'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
        if (OrdenRecogidaColaboradorUi.enFaseRecogidaColaborador(_ordenActual)) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              OrdenRecogidaColaboradorUi.mensajeInfoTarjeta(_ordenActual),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF666666), fontSize: 13),
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFF9800), width: 1.5),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, color: const Color(0xFFE65100), size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Orden Bloqueada',
                      style: TextStyle(
                        color: Color(0xFFE65100),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Esta orden aún está en la bodega de la empresa.\nSolo se activará cuando el sistema la cambie a "EN TRANSITO".',
                style: TextStyle(
                  color: Color(0xFFE65100),
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      
      case 'EN TRANSITO':
        // El repartidor puede cambiar de "EN TRANSITO" a "EN REPARTO"
        return ElevatedButton.icon(
          onPressed: _isLoading ? null : () => _marcarComoEnReparto(),
          icon: const Icon(Icons.local_shipping, size: 18),
          label: const Text('Iniciar Reparto'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF9800),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 2,
          ),
        );
      
      case 'EN REPARTO':
        // Si es recogida en sucursal, mostrar "Listo para recoger" en lugar de "Marcar Entregado"
        if (_ordenActual.recogerEnSucursal) {
          return ElevatedButton.icon(
            onPressed: _isLoading ? null : () => _marcarComoListoParaRecoger(),
            icon: const Icon(Icons.store, size: 18),
            label: const Text('Listo para recoger'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9800), // Naranja para "Listo para recoger"
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 2,
            ),
          );
        }
        // El repartidor puede cambiar de "EN REPARTO" a "ENTREGADO" (orden normal)
        return ElevatedButton.icon(
          onPressed: _isLoading ? null : () => _marcarComoEntregado(),
          icon: const Icon(Icons.check_circle, size: 18),
          label: const Text('Marcar Entregado'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4CAF50),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 2,
          ),
        );
      
      case 'LISTO PARA RECOGER':
        // Después de "LISTO PARA RECOGER", se puede marcar como "ENTREGADO"
        return ElevatedButton.icon(
          onPressed: _isLoading ? null : () => _marcarComoEntregado(),
          icon: const Icon(Icons.check_circle, size: 18),
          label: const Text('Marcar Entregado'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4CAF50),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            elevation: 2,
          ),
        );
      
      case 'ATRASADO':
        // Si está atrasado pero está en "EN TRANSITO", puede iniciar reparto
        if (_ordenActual.estado == 'ATRASADO') {
          return ElevatedButton.icon(
            onPressed: _isLoading ? null : () => _marcarComoEnReparto(),
            icon: const Icon(Icons.local_shipping, size: 18),
            label: const Text('Iniciar Reparto'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9800),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 2,
            ),
          );
        }
        return Container();
      
      default:
        return Container();
    }
  }

  void _marcarComoEntregado() async {
    // Verificar que el widget esté montado antes de continuar
    if (!mounted) return;
    
    print('🔍 ====== INICIO MARCAR COMO ENTREGADO ======');
    
    // Mostrar indicador de carga mientras se recarga la orden
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }
    
    // Guardar la foto y firma actuales antes de recargar
    final fotoAntesDeRecargar = _fotoEntregaUrl;
    final firmaAntesDeRecargar = _firmaUrl;
    
    // Recargar orden para tener datos más recientes CON TIMEOUT Y MANEJO DE ERRORES DE RED
    try {
      print('🔄 Recargando orden con timeout de 8 segundos...');
      await _recargarOrden().timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          print('⏱️ Timeout alcanzado');
          throw Exception('Tiempo de espera agotado');
        },
      );
      print('✅ Orden recargada exitosamente');
    } on SocketException catch (e) {
      // ✅ OFFLINE-FIRST: Manejar error de conexión silenciosamente
      print('📴 Sin conexión - Error de red (modo offline): $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        // Mostrar diálogo con opciones
        final continuar = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFFFFFFFF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.wifi_off, color: Color(0xFFDC2626), size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Sin Conexión',
                    style: TextStyle(
                      color: Color(0xFF2C2C2C),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: const SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No se pudo conectar con el servidor. Verifica tu conexión a internet.',
                    style: TextStyle(
                      color: Color(0xFF666666),
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    '¿Deseas continuar sin actualizar los datos?',
                    style: TextStyle(
                      color: Color(0xFF2C2C2C),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
                  backgroundColor: const Color(0xFFFF9800),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Continuar'),
              ),
            ],
          ),
        );
        
        if (continuar != true) {
          print('❌ Usuario canceló por falta de conexión');
          return;
        }
        print('✅ Usuario decidió continuar sin conexión');
      } else {
        return;
      }
    } catch (e) {
      // Otros errores
      print('❌ Error al recargar orden: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        
        // Mostrar diálogo con opciones
        final continuar = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFFFFFFFF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Error al Cargar',
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
                    'No se pudieron cargar los datos actualizados de la orden.',
                    style: TextStyle(
                      color: Color(0xFF666666),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Error: ${e.toString()}',
                    style: const TextStyle(
                      color: Color(0xFF999999),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '¿Deseas continuar de todos modos?',
                    style: TextStyle(
                      color: Color(0xFF2C2C2C),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
                  backgroundColor: const Color(0xFFFF9800),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Continuar'),
              ),
            ],
          ),
        );
        
        if (continuar != true) {
          print('❌ Usuario canceló por error');
          return;
      }
        print('✅ Usuario decidió continuar a pesar del error');
      } else {
      return;
      }
    }
    
    // Ocultar indicador de carga
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
    
    // Verificar nuevamente que el widget esté montado después de recargar
    if (!mounted) return;
    
    // 🔒 CRÍTICO: Restaurar la foto y firma que se subieron localmente
    // Preservar fotos locales (local://) - son críticas para el flujo offline
    if (fotoAntesDeRecargar != null && fotoAntesDeRecargar.isNotEmpty) {
      // Si es foto local, SIEMPRE preservarla
      if (fotoAntesDeRecargar.startsWith('local://')) {
        print('🔒 Preservando foto local después de recargar: $fotoAntesDeRecargar');
        _fotoEntregaUrl = fotoAntesDeRecargar;
        // No modificar _ordenActual directamente (es inmutable)
      } else {
        // Si es foto de BD, solo actualizar si no hay foto local actual
        if (_fotoEntregaUrl == null || 
            _fotoEntregaUrl!.isEmpty || 
            !_fotoEntregaUrl!.startsWith('local://')) {
          _fotoEntregaUrl = fotoAntesDeRecargar;
        }
      }
    }
    
    // Similar para la firma
    if (firmaAntesDeRecargar != null && firmaAntesDeRecargar.isNotEmpty) {
      if (firmaAntesDeRecargar.startsWith('local://')) {
        print('🔒 Preservando firma local después de recargar: $firmaAntesDeRecargar');
        _firmaUrl = firmaAntesDeRecargar;
        // No modificar _ordenActual directamente (es inmutable)
      } else {
        if (_firmaUrl == null || 
            _firmaUrl!.isEmpty || 
            !_firmaUrl!.startsWith('local://')) {
          _firmaUrl = firmaAntesDeRecargar;
        }
      }
    }
    
    // 🔒 CRÍTICO: Si no hay foto local pero debería haberla (foto pendiente en storage)
    if ((_fotoEntregaUrl == null || _fotoEntregaUrl!.isEmpty || !_fotoEntregaUrl!.startsWith('local://')) &&
        (_ordenActual.fotoEntrega == null || _ordenActual.fotoEntrega!.isEmpty || !_ordenActual.fotoEntrega!.startsWith('local://'))) {
      try {
        final offlineStorage = OfflineStorageService();
        final pendingPhotos = await offlineStorage.getPendingPhotos();
        final fotoPendiente = pendingPhotos.firstWhere(
          (photo) => photo['orden_id'] == _ordenActual.id,
          orElse: () => <String, dynamic>{},
        );
        
        if (fotoPendiente.isNotEmpty && fotoPendiente['file_path'] != null) {
          final filePath = fotoPendiente['file_path'] as String;
          final file = File(filePath);
          if (await file.exists()) {
            print('🔒 Restaurando foto local desde storage después de recargar: $filePath');
            final fotoLocalUrl = 'local://$filePath';
            _fotoEntregaUrl = fotoLocalUrl;
            
            // 🔒 CRÍTICO: Actualizar también _ordenActual
            try {
              final ordenJson = _ordenActual.toJson();
              ordenJson['foto_entrega'] = fotoLocalUrl;
              _ordenActual = Orden.fromJson(ordenJson);
              print('✅ _ordenActual actualizada con foto restaurada: $fotoLocalUrl');
            } catch (e) {
              print('⚠️ Error actualizando _ordenActual con foto restaurada: $e');
            }
          }
        }
      } catch (e) {
        print('⚠️ Error verificando fotos pendientes después de recargar: $e');
      }
    }
    
    print('🔍 ========================================');
    print('🔍 INICIANDO FLUJO DE ENTREGA');
    print('🔍 ========================================');
    print('🔍 DEBUG - Estado actual: ${_ordenActual.estado}');
    print('🔍 DEBUG - Cantidad de bultos: ${_ordenActual.cantidadBultos}');
    print('🔍 DEBUG - Tiene remesa: ${_ordenActual.tieneRemesa}');
    print('🔍 DEBUG - Requiere pago: ${_ordenActual.requierePago}');
    print('🔍 DEBUG - Pagado: ${_ordenActual.pagado}');
    print('🔍 DEBUG - Requiere firma: ${_ordenActual.requiereFirma}');
    print('🔍 DEBUG - Tiene firma: ${_firmaUrl != null && _firmaUrl!.isNotEmpty}');
    print('🔍 DEBUG - Foto obligatoria: $_fotoEntregaObligatoria');
    print('🔍 DEBUG - Tiene foto: ${_fotoEntregaUrl != null && _fotoEntregaUrl!.isNotEmpty}');
    
    // 🔄 FLUJO SECUENCIAL DE VALIDACIÓN Y ACCIONES
    
    // PASO 1: Validar y entregar REMESA (si tiene)
    if (_ordenActual.tieneRemesa) {
      print('📦 PASO 1: Validando remesa...');
      final remesaEntregada = await _validarYEntregarRemesa();
      if (!remesaEntregada) {
        print('❌ Remesa no entregada, cancelando entrega');
        return; // Usuario canceló o no entregó la remesa
      }
      print('✅ Remesa validada y entregada');
    }
    
    // PASO 2: Validar y cobrar PAGO (si requiere)
    if (_ordenActual.requierePago && !_ordenActual.pagado) {
      print('💰 PASO 2: Validando pago...');
      
      // 🔒 CRÍTICO: Preservar foto y firma antes de recargar
      final fotoAntesDePago = _fotoEntregaUrl;
      final firmaAntesDePago = _firmaUrl;
      
      final pagoCobrado = await _validarYCobrarPago();
      if (!pagoCobrado) {
        print('❌ Pago no cobrado, cancelando entrega');
        return; // Usuario canceló o no cobró el pago
      }
      
      // Recargar orden para actualizar estado de pago
      await _recargarOrden();
      
      // 🔒 CRÍTICO: Restaurar foto y firma después de recargar
      if (fotoAntesDePago != null && fotoAntesDePago.isNotEmpty) {
        _fotoEntregaUrl = fotoAntesDePago;
        try {
          final ordenJson = _ordenActual.toJson();
          ordenJson['foto_entrega'] = fotoAntesDePago;
          _ordenActual = Orden.fromJson(ordenJson);
          print('✅ Foto preservada después de recargar por pago: $fotoAntesDePago');
        } catch (e) {
          print('⚠️ Error preservando foto después de recargar: $e');
        }
      }
      
      if (firmaAntesDePago != null && firmaAntesDePago.isNotEmpty) {
        _firmaUrl = firmaAntesDePago;
        try {
          final ordenJson = _ordenActual.toJson();
          ordenJson['firma_url'] = firmaAntesDePago;
          _ordenActual = Orden.fromJson(ordenJson);
          print('✅ Firma preservada después de recargar por pago: $firmaAntesDePago');
        } catch (e) {
          print('⚠️ Error preservando firma después de recargar: $e');
        }
      }
      
      print('✅ Pago validado y cobrado');
    }
    
    // PASO 3: Obtener FOTO (si es obligatoria) - PRIMERO LA FOTO, LUEGO LA FIRMA
    // 🔒 CRÍTICO: Verificar tanto _fotoEntregaUrl como _ordenActual.fotoEntrega
    // porque pueden estar desincronizados después de recargas
    // También verificar en caché y pending_photos si no está en estado local
    bool tieneFoto = (_fotoEntregaUrl != null && _fotoEntregaUrl!.isNotEmpty) ||
                      (_ordenActual.fotoEntrega != null && _ordenActual.fotoEntrega!.isNotEmpty);
    
    // Si no tiene foto en estado local, verificar en caché y pending_photos
    if (!tieneFoto) {
      try {
        // Verificar en caché
        final ordenCache = await OrdenCacheService.getCachedOrderById(_ordenActual.id);
        if (ordenCache != null && ordenCache.fotoEntrega != null && ordenCache.fotoEntrega!.isNotEmpty) {
          // Sincronizar desde caché
          _fotoEntregaUrl = ordenCache.fotoEntrega;
          try {
            final ordenJson = _ordenActual.toJson();
            ordenJson['foto_entrega'] = ordenCache.fotoEntrega;
            _ordenActual = Orden.fromJson(ordenJson);
            tieneFoto = true;
            print('✅ Foto encontrada en caché y sincronizada: ${ordenCache.fotoEntrega}');
          } catch (e) {
            print('⚠️ Error sincronizando foto desde caché: $e');
          }
        }
        
        // Si aún no tiene foto, verificar en pending_photos
        if (!tieneFoto) {
          final offlineStorage = OfflineStorageService();
          final pendingPhotos = await offlineStorage.getPendingPhotos();
          final fotoPendiente = pendingPhotos.firstWhere(
            (photo) => photo['orden_id'] == _ordenActual.id,
            orElse: () => <String, dynamic>{},
          );
          
          if (fotoPendiente.isNotEmpty && fotoPendiente['file_path'] != null) {
            final filePath = fotoPendiente['file_path'] as String;
            final file = File(filePath);
            if (await file.exists()) {
              final fotoLocalUrl = 'local://$filePath';
              _fotoEntregaUrl = fotoLocalUrl;
              try {
                final ordenJson = _ordenActual.toJson();
                ordenJson['foto_entrega'] = fotoLocalUrl;
                _ordenActual = Orden.fromJson(ordenJson);
                tieneFoto = true;
                print('✅ Foto encontrada en pending_photos y sincronizada: $fotoLocalUrl');
              } catch (e) {
                print('⚠️ Error sincronizando foto desde pending_photos: $e');
              }
            }
          }
        }
      } catch (e) {
        print('⚠️ Error verificando foto en caché/pending_photos: $e');
      }
    }
    
    if (_fotoEntregaObligatoria && !tieneFoto) {
      print('📷 PASO 3: Foto obligatoria pero no tomada, pidiendo foto directamente...');
      print('📷 DEBUG - _fotoEntregaUrl: $_fotoEntregaUrl');
      print('📷 DEBUG - _ordenActual.fotoEntrega: ${_ordenActual.fotoEntrega}');
      
      // 🔒 CRÍTICO: Pedir foto directamente en el flujo, no mostrar error
      await _tomarFotoEntregaConSelector();
      
      // 🔒 CRÍTICO: Sincronizar _fotoEntregaUrl y _ordenActual después de tomar foto
      // Verificar nuevamente después de tomar la foto
      final fotoDespues = (_fotoEntregaUrl != null && _fotoEntregaUrl!.isNotEmpty) ||
                          (_ordenActual.fotoEntrega != null && _ordenActual.fotoEntrega!.isNotEmpty);
      
      if (!fotoDespues) {
        print('❌ Error: La foto no se capturó correctamente');
        _mostrarMensaje('❌ No se pudo obtener la foto. Intenta de nuevo.');
        return;
      }
      
      // 🔒 CRÍTICO: Sincronizar ambos valores
      if (_fotoEntregaUrl != null && _fotoEntregaUrl!.isNotEmpty) {
        // Si _fotoEntregaUrl tiene valor, actualizar _ordenActual
        try {
          final ordenJson = _ordenActual.toJson();
          ordenJson['foto_entrega'] = _fotoEntregaUrl;
          _ordenActual = Orden.fromJson(ordenJson);
          print('✅ _ordenActual actualizada con foto desde _fotoEntregaUrl: $_fotoEntregaUrl');
        } catch (e) {
          print('⚠️ Error actualizando _ordenActual con foto: $e');
        }
      } else if (_ordenActual.fotoEntrega != null && _ordenActual.fotoEntrega!.isNotEmpty) {
        // Si _ordenActual tiene valor, actualizar _fotoEntregaUrl
        _fotoEntregaUrl = _ordenActual.fotoEntrega;
        print('✅ _fotoEntregaUrl actualizada desde _ordenActual: $_fotoEntregaUrl');
      }
      
      print('✅ Foto capturada exitosamente: $_fotoEntregaUrl');
    } else {
      print('✅ Foto validada (ya existe o no es obligatoria)');
      print('📷 DEBUG - _fotoEntregaUrl: $_fotoEntregaUrl');
      print('📷 DEBUG - _ordenActual.fotoEntrega: ${_ordenActual.fotoEntrega}');
    }
    
    // PASO 4: Obtener FIRMA (si requiere) - DESPUÉS DE LA FOTO
    // 🔒 CRÍTICO: Verificar tanto _firmaUrl como _ordenActual.firmaUrl
    // porque pueden estar desincronizados después de recargas
    // También verificar en caché y pending_signatures si no está en estado local
    bool tieneFirma = (_firmaUrl != null && _firmaUrl!.isNotEmpty) ||
                       (_ordenActual.firmaUrl != null && _ordenActual.firmaUrl!.isNotEmpty);
    
    // Si no tiene firma en estado local, verificar en caché y pending_signatures
    if (!tieneFirma) {
      try {
        // Verificar en caché
        final ordenCache = await OrdenCacheService.getCachedOrderById(_ordenActual.id);
        if (ordenCache != null && ordenCache.firmaUrl != null && ordenCache.firmaUrl!.isNotEmpty) {
          // Sincronizar desde caché
          _firmaUrl = ordenCache.firmaUrl;
          try {
            final ordenJson = _ordenActual.toJson();
            ordenJson['firma_url'] = ordenCache.firmaUrl;
            _ordenActual = Orden.fromJson(ordenJson);
            tieneFirma = true;
            print('✅ Firma encontrada en caché y sincronizada: ${ordenCache.firmaUrl}');
          } catch (e) {
            print('⚠️ Error sincronizando firma desde caché: $e');
          }
        }
        
        // Si aún no tiene firma, verificar en pending_signatures
        if (!tieneFirma) {
          final offlineStorage = OfflineStorageService();
          final pendingSignatures = await offlineStorage.getPendingSignatures();
          final firmaPendiente = pendingSignatures.firstWhere(
            (sig) => sig['orden_id'] == _ordenActual.id,
            orElse: () => <String, dynamic>{},
          );
          
          if (firmaPendiente.isNotEmpty && firmaPendiente['file_path'] != null) {
            final filePath = firmaPendiente['file_path'] as String;
            final file = File(filePath);
            if (await file.exists()) {
              final firmaLocalUrl = 'local://$filePath';
              _firmaUrl = firmaLocalUrl;
              try {
                final ordenJson = _ordenActual.toJson();
                ordenJson['firma_url'] = firmaLocalUrl;
                _ordenActual = Orden.fromJson(ordenJson);
                tieneFirma = true;
                print('✅ Firma encontrada en pending_signatures y sincronizada: $firmaLocalUrl');
              } catch (e) {
                print('⚠️ Error sincronizando firma desde pending_signatures: $e');
              }
            }
          }
        }
      } catch (e) {
        print('⚠️ Error verificando firma en caché/pending_signatures: $e');
      }
    }
    
    if (_ordenActual.requiereFirma && !tieneFirma) {
      print('✍️ PASO 4: Firma requerida pero no obtenida, mostrando modal...');
      print('✍️ DEBUG - _firmaUrl: $_firmaUrl');
      print('✍️ DEBUG - _ordenActual.firmaUrl: ${_ordenActual.firmaUrl}');
      
      final firmaObtenida = await _mostrarModalFirma();
      if (!firmaObtenida) {
        _mostrarMensaje('❌ No se puede entregar sin la firma del cliente');
        return; // Usuario canceló o no obtuvo la firma - OBLIGATORIO
      }
      
      // 🔒 CRÍTICO: Sincronizar _firmaUrl y _ordenActual después de capturar firma
      // Verificar nuevamente después de capturar la firma
      final firmaDespues = (_firmaUrl != null && _firmaUrl!.isNotEmpty) ||
                           (_ordenActual.firmaUrl != null && _ordenActual.firmaUrl!.isNotEmpty);
      
      if (!firmaDespues) {
        print('❌ Error: La firma no se guardó correctamente');
        _mostrarMensaje('❌ Error: La firma no se guardó correctamente. Intenta de nuevo.');
        return;
      }
      
      // 🔒 CRÍTICO: Sincronizar ambos valores
      if (_firmaUrl != null && _firmaUrl!.isNotEmpty) {
        // Si _firmaUrl tiene valor, actualizar _ordenActual
        try {
          final ordenJson = _ordenActual.toJson();
          ordenJson['firma_url'] = _firmaUrl;
          _ordenActual = Orden.fromJson(ordenJson);
          print('✅ _ordenActual actualizada con firma desde _firmaUrl: $_firmaUrl');
        } catch (e) {
          print('⚠️ Error actualizando _ordenActual con firma: $e');
        }
      } else if (_ordenActual.firmaUrl != null && _ordenActual.firmaUrl!.isNotEmpty) {
        // Si _ordenActual tiene valor, actualizar _firmaUrl
        _firmaUrl = _ordenActual.firmaUrl;
        print('✅ _firmaUrl actualizada desde _ordenActual: $_firmaUrl');
      }
      
      print('✅ Firma capturada exitosamente: $_firmaUrl');
    } else {
      print('✅ Firma validada (ya existe o no es obligatoria)');
      print('✍️ DEBUG - _firmaUrl: $_firmaUrl');
      print('✍️ DEBUG - _ordenActual.firmaUrl: ${_ordenActual.firmaUrl}');
    }
    
    // PASO 5: Confirmación de bultos (solo si hay más de 1)
    if (_ordenActual.cantidadBultos > 1) {
      print('📦 PASO 5: Confirmando cantidad de bultos...');
      final confirmado = await _mostrarDialogoConfirmacionBultos();
      if (!confirmado) {
        return; // Usuario canceló
      }
      print('✅ Bultos confirmados');
    }

    // Verificar que el widget esté montado antes de mostrar el diálogo final
    if (!mounted) return;

    // Todo validado - proceder con la entrega
    final confirmadoFinal = await _mostrarConfirmacion(
      'Confirmar Entrega',
      '¿Estás seguro de que quieres marcar esta orden como entregada?',
    );
    
    // Verificar nuevamente después del diálogo
    if (!mounted) return;
    
    if (confirmadoFinal) {
      setState(() {
        _isLoading = true;
      });
      
      // 🔒 NOTA: Las fotos y firmas ya están en la cola de operaciones (se agregaron al tomarlas)
      // NO es necesario guardarlas nuevamente en pending_photos/pending_signatures
      // Esto evita duplicados en la cola de sincronización
      
      // Actualizar estado localmente
      _ordenActual.estado = 'ENTREGADO';
      _ordenActual.fechaEntrega = DateTime.now();
      await OrdenCacheService.updateCachedOrder(_ordenActual);
      
      // Obtener nombre del repartidor actual que está entregando
      String? nombreRepartidorActual;
      try {
        final user = supabase.auth.currentUser;
        if (user != null) {
          final userData = await supabase
              .from('usuarios')
              .select('nombre')
              .eq('auth_id', user.id)
              .maybeSingle();
          nombreRepartidorActual = userData?['nombre']?.toString();
          print('📦 Repartidor que entrega: $nombreRepartidorActual');
          print('📦 Repartidor asignado originalmente: ${_ordenActual.repartidor}');
        }
      } catch (e) {
        print('⚠️ Error obteniendo nombre del repartidor: $e');
      }
      
      final syncService = SyncService();
      final updateData = {
        'estado': 'ENTREGADO',
        'fecha_entrega': DateTime.now().toIso8601String(),
        // Guardar quién entregó la orden (puede ser diferente del asignado si es master)
        if (nombreRepartidorActual != null && nombreRepartidorActual.isNotEmpty)
          'entregado_por': nombreRepartidorActual,
        // Incluir foto de entrega si existe (usar la foto que se subió, no la de la BD)
        if (_fotoEntregaUrl != null && 
            _fotoEntregaUrl!.isNotEmpty && 
            !_fotoEntregaUrl!.startsWith('local://')) 
          'foto_entrega': _fotoEntregaUrl,
        // Incluir firma si existe
        if (_firmaUrl != null && 
            _firmaUrl!.isNotEmpty && 
            !_firmaUrl!.startsWith('local://')) 
          'firma_url': _firmaUrl,
      };
      
      print('📸 DEBUG - Foto que se enviará: $_fotoEntregaUrl');
      print('✍️ DEBUG - Firma que se enviará: $_firmaUrl');
      
      // Intentar actualizar en BD si hay conexión
      bool actualizadoExitosamente = false;
      
      if (syncService.isOnline) {
        try {
          await supabase
              .from('ordenes')
              .update(updateData)
              .eq('id', widget.orden.id);
          
          print('✅ Orden marcada como entregada en BD (online)');
          actualizadoExitosamente = true;
          
          // Sincronizar con GoodBarber si la orden está vinculada
          try {
            await GoodBarberSyncService.sincronizarEstadoAGoodBarber(
              supabase,
              widget.orden.id,
              'ENTREGADO',
            );
          } catch (e) {
            print('⚠️ Error sincronizando estado con GoodBarber: $e');
          }
          
          // Esperar un momento para asegurar que la actualización se haya propagado
          await Future.delayed(const Duration(milliseconds: 500));
          
          // Enviar email de confirmación
          try {
            print('📧 ===== INICIANDO PROCESO DE EMAIL ENTREGADO (detalle_orden) =====');
            final ordenData = await supabase
                .from('ordenes')
                .select('*')
                .eq('id', widget.orden.id)
                .single();
            
            print('✍️ DEBUG - Firma en BD después de actualizar: ${ordenData['firma_url'] ?? 'NO DISPONIBLE'}');
            print('📸 DEBUG - Foto en BD después de actualizar: ${ordenData['foto_entrega'] ?? 'NO DISPONIBLE'}');
            
            final ordenActualizada = Orden.fromJson(ordenData);
            
            // CRÍTICO: Verificar que la firma se haya parseado correctamente
            print('✍️ DEBUG - Firma en objeto Orden después de fromJson: ${ordenActualizada.firmaUrl ?? 'NO DISPONIBLE'}');
            
            // CRÍTICO: Si la firma existe en la BD pero no se parseó, usar directamente de la BD
            if (ordenData['firma_url'] != null && 
                ordenData['firma_url'].toString().isNotEmpty && 
                (ordenActualizada.firmaUrl == null || ordenActualizada.firmaUrl!.isEmpty)) {
              print('⚠️ ADVERTENCIA: Firma existe en BD pero no se parseó correctamente, usando directamente de BD');
              // Forzar la inclusión de la firma en el objeto Orden usando un workaround
              // Como Orden es inmutable, necesitamos crear un nuevo objeto con la firma
              final ordenConFirma = Orden(
                id: ordenActualizada.id,
                numeroOrden: ordenActualizada.numeroOrden,
                emisor: ordenActualizada.emisor,
                receptor: ordenActualizada.receptor,
                descripcion: ordenActualizada.descripcion,
                direccionDestino: ordenActualizada.direccionDestino,
                telefonoDestinatario: ordenActualizada.telefonoDestinatario,
                ciudadDestino: ordenActualizada.ciudadDestino,
                provinciaDestino: ordenActualizada.provinciaDestino,
                municipioDestino: ordenActualizada.municipioDestino,
                consejoPopularBatey: ordenActualizada.consejoPopularBatey,
                peso: ordenActualizada.peso,
                largo: ordenActualizada.largo,
                ancho: ordenActualizada.ancho,
                alto: ordenActualizada.alto,
                estado: ordenActualizada.estado,
                fechaCreacion: ordenActualizada.fechaCreacion,
                fechaEntrega: ordenActualizada.fechaEntrega,
                fechaEstimadaEntrega: ordenActualizada.fechaEstimadaEntrega,
                notas: ordenActualizada.notas,
                repartidor: ordenActualizada.repartidor,
                entregadoPor: nombreRepartidorActual,
                esUrgente: ordenActualizada.esUrgente,
                fotoEntrega: ordenActualizada.fotoEntrega,
                creadoPorNombre: ordenActualizada.creadoPorNombre,
                creadoPorEmail: ordenActualizada.creadoPorEmail,
                cantidadBultos: ordenActualizada.cantidadBultos,
                requierePago: ordenActualizada.requierePago,
                montoCobrar: ordenActualizada.montoCobrar,
                moneda: ordenActualizada.moneda,
                precioTotalEnvio: ordenActualizada.precioTotalEnvio,
                monedaPrecioTotalEnvio: ordenActualizada.monedaPrecioTotalEnvio,
                pagado: ordenActualizada.pagado,
                fechaPago: ordenActualizada.fechaPago,
                notasPago: ordenActualizada.notasPago,
                pagada: ordenActualizada.pagada,
                tieneRemesa: ordenActualizada.tieneRemesa,
                cantidadRemesa: ordenActualizada.cantidadRemesa,
                requiereFirma: ordenActualizada.requiereFirma,
                firmaUrl: ordenData['firma_url']?.toString(), // CRÍTICO: Usar firma directamente de BD
                itemsAdicionales: ordenActualizada.itemsAdicionales,
                tenantId: ordenActualizada.tenantId,
              );
              
              // Usar la orden con firma corregida
              final ordenParaEmail = ordenConFirma;
              final tenantId = ordenData['tenant_id']?.toString() ?? ordenParaEmail.tenantId;
              final emisorNombre = ordenData['emisor_nombre']?.toString() ?? ordenParaEmail.emisor;
              
              print('✍️ ✅ Orden corregida con firma: ${ordenParaEmail.firmaUrl ?? 'NO DISPONIBLE'}');
              
              // Buscar email del emisor y enviar
              String? emailEmisor;
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
              
              if (emailEmisor != null && emailEmisor.isNotEmpty) {
                final configService = ConfiguracionService();
                final notificacionesHabilitadas = await configService.notificacionesHabilitadas('emisores', tenantId: tenantId);
                
                if (notificacionesHabilitadas) {
                  print('📧 ENVIANDO EMAIL ENTREGADO CON FIRMA CORREGIDA...');
                  final enviado = await EmailService.enviarEmailOrdenEntregada(ordenParaEmail, emailEmisor, tenantId: tenantId);
                  if (enviado) {
                    print('✅ ✅ ✅ Email de orden entregada ENVIADO EXITOSAMENTE ✅ ✅ ✅');
                  } else {
                    print('⚠️ ⚠️ ⚠️ No se pudo enviar el email al emisor ⚠️ ⚠️ ⚠️');
                  }
                } else {
                  print('⚠️ ⚠️ ⚠️ Notificaciones para emisores están DESHABILITADAS ⚠️ ⚠️ ⚠️');
                }
              } else {
                print('⚠️ ⚠️ ⚠️ NO se encontró email del emisor ⚠️ ⚠️ ⚠️');
              }
              
              return; // Salir temprano ya que procesamos el email con la orden corregida
            }
            // Asegurar que entregado_por esté en la orden para el email
            if (nombreRepartidorActual != null && nombreRepartidorActual.isNotEmpty) {
              ordenActualizada.entregadoPor = nombreRepartidorActual;
            }
            final tenantId = ordenData['tenant_id']?.toString() ?? ordenActualizada.tenantId;
            final emisorNombre = ordenData['emisor']?.toString() ?? ordenActualizada.emisor;
            
            print('📧 Emisor nombre: $emisorNombre');
            print('📧 Tenant ID: $tenantId');
            print('📧 Repartidor que entregó: $nombreRepartidorActual');
            print('📧 Repartidor asignado: ${ordenActualizada.repartidor}');
            
            // Buscar email del emisor por nombre (como lo hace la web app)
            String? emailEmisor;
            if (emisorNombre.isNotEmpty && emisorNombre != 'Sin emisor') {
              print('📧 Buscando email del emisor por nombre: $emisorNombre');
              try {
                final emisorData = await supabase
                    .from('emisores')
                    .select('email')
                    .eq('nombre', emisorNombre)
                    .eq('tenant_id', tenantId ?? '')
                    .maybeSingle();
                
                emailEmisor = emisorData?['email']?.toString();
                print('📧 Email encontrado: ${emailEmisor ?? "NO ENCONTRADO"}');
              } catch (e) {
                print('⚠️ Error obteniendo email del emisor por nombre: $e');
              }
            } else {
              print('⚠️ El emisor está vacío o es "Sin emisor"');
            }
            
            if (emailEmisor != null && emailEmisor.isNotEmpty) {
              final configService = ConfiguracionService();
              final notificacionesHabilitadas = await configService.notificacionesHabilitadas('emisores', tenantId: tenantId);
              
              if (notificacionesHabilitadas) {
                print('📧 ENVIANDO EMAIL ENTREGADO...');
                final enviado = await EmailService.enviarEmailOrdenEntregada(ordenActualizada, emailEmisor, tenantId: tenantId);
                if (enviado) {
                  print('✅ ✅ ✅ Email de orden entregada ENVIADO EXITOSAMENTE ✅ ✅ ✅');
                } else {
                  print('⚠️ ⚠️ ⚠️ No se pudo enviar el email al emisor ⚠️ ⚠️ ⚠️');
                }
              } else {
                print('⚠️ ⚠️ ⚠️ Notificaciones para emisores están DESHABILITADAS ⚠️ ⚠️ ⚠️');
              }
            } else {
              print('⚠️ ⚠️ ⚠️ NO se encontró email del emisor ⚠️ ⚠️ ⚠️');
            }
          } catch (e) {
            print('⚠️ Error al enviar email de entrega: $e');
            print('❌ Stack trace: ${StackTrace.current}');
            // No es crítico, la orden ya se actualizó
          }
          
          if (mounted) {
            _mostrarMensaje('✅ Orden entregada exitosamente');
            Navigator.pop(context, true);
          }
        } catch (e) {
          print('⚠️ Error actualizando en BD (posible falta de conexión real): $e');
          print('📴 Agregando a cola de sincronización...');
          actualizadoExitosamente = false;
        }
      }
      
      // Si no se actualizó exitosamente (sin conexión o error), agregar a cola
      if (!actualizadoExitosamente) {
        try {
          // 🔒 CRÍTICO: Actualizar caché local ANTES de agregar a cola
          // Preservar foto local si existe
          try {
            final ordenJson = _ordenActual.toJson();
            ordenJson['estado'] = 'ENTREGADO';
            ordenJson['fecha_entrega'] = DateTime.now().toIso8601String();
            
            // 🔒 PRESERVAR foto local si existe
            if (_fotoEntregaUrl != null && 
                _fotoEntregaUrl!.isNotEmpty && 
                _fotoEntregaUrl!.startsWith('local://')) {
              ordenJson['foto_entrega'] = _fotoEntregaUrl;
              print('🔒 Preservando foto local en caché: $_fotoEntregaUrl');
            }
            
            // 🔒 PRESERVAR firma local si existe
            if (_firmaUrl != null && 
                _firmaUrl!.isNotEmpty && 
                _firmaUrl!.startsWith('local://')) {
              ordenJson['firma_url'] = _firmaUrl;
              print('🔒 Preservando firma local en caché: $_firmaUrl');
            }
            
            final ordenParaCache = Orden.fromJson(ordenJson);
            await OrdenCacheService.updateCachedOrder(ordenParaCache);
            print('💾 Orden actualizada en caché local como ENTREGADA (con foto/firma local preservadas)');
          } catch (e) {
            print('⚠️ Error actualizando caché local: $e');
          }
          
          await syncService.addOperation(
            type: 'mark_delivered',
            ordenId: widget.orden.id,
            data: updateData,
          );
          
          if (mounted) {
            _mostrarMensaje('✅ Orden entregada (se sincronizará cuando haya conexión)');
            Navigator.pop(context, true);
          }
        } catch (e) {
          print('❌ Error agregando a cola de sincronización: $e');
          if (mounted) {
            _mostrarMensaje('✅ Orden entregada localmente (se sincronizará cuando haya conexión)');
            Navigator.pop(context, true);
          }
        }
      } else {
        // 🔒 CRÍTICO: También actualizar caché cuando se actualiza exitosamente online
        // para asegurar que la foto local se preserve si existe
        try {
          final ordenJson = _ordenActual.toJson();
          ordenJson['estado'] = 'ENTREGADO';
          ordenJson['fecha_entrega'] = DateTime.now().toIso8601String();
          
          // Si hay foto local, preservarla en caché
          if (_fotoEntregaUrl != null && 
              _fotoEntregaUrl!.isNotEmpty && 
              _fotoEntregaUrl!.startsWith('local://')) {
            ordenJson['foto_entrega'] = _fotoEntregaUrl;
            print('🔒 Preservando foto local en caché después de marcar como entregada: $_fotoEntregaUrl');
          }
          
          if (_firmaUrl != null && 
              _firmaUrl!.isNotEmpty && 
              _firmaUrl!.startsWith('local://')) {
            ordenJson['firma_url'] = _firmaUrl;
            print('🔒 Preservando firma local en caché después de marcar como entregada: $_firmaUrl');
          }
          
          final ordenParaCache = Orden.fromJson(ordenJson);
          await OrdenCacheService.updateCachedOrder(ordenParaCache);
          print('💾 Orden actualizada en caché local como ENTREGADA (online)');
        } catch (e) {
          print('⚠️ Error actualizando caché local después de entregar: $e');
        }
      }
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _marcarComoListoParaRecoger() async {
    // Verificar que la orden esté en "EN REPARTO" y que sea recogida en sucursal
    if (_ordenActual.estado != 'EN REPARTO') {
      _mostrarMensaje('Solo puedes marcar como "Listo para recoger" desde órdenes en "EN REPARTO"');
      return;
    }
    
    if (!_ordenActual.recogerEnSucursal) {
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
          'La orden está lista para que el destinatario ${_ordenActual.receptor} pase a recogerla en la sucursal. ¿Seguro?',
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
      setState(() {
        _isLoading = true;
      });
      
      final syncService = SyncService();
      final updateData = <String, dynamic>{
        'estado': 'LISTO PARA RECOGER',
      };

      bool actualizadoExitosamente = false;

      // ✅ OFFLINE-FIRST: Actualizar estado local INMEDIATAMENTE (para no bloquear el flujo)
      try {
        _ordenActual.estado = 'LISTO PARA RECOGER';
        await OrdenCacheService.updateCachedOrder(_ordenActual);
        print('💾 Estado actualizado en caché: LISTO PARA RECOGER');
      } catch (e) {
        print('⚠️ Error actualizando caché local a LISTO PARA RECOGER: $e');
      }

      // Intentar actualizar en BD SOLO si hay conexión (y si falla, encolar)
      if (syncService.isOnline) {
        try {
          print('📡 Actualizando estado de orden en BD a LISTO PARA RECOGER...');
          await supabase
              .from('ordenes')
              .update(updateData)
              .eq('id', widget.orden.id);
          actualizadoExitosamente = true;
          print('✅ Estado actualizado en BD: LISTO PARA RECOGER');
        } catch (e) {
          final errorString = e.toString();
          // Si es error de red/DNS, caer a modo offline (encolar) sin bloquear
          if (errorString.contains('Failed host lookup') ||
              errorString.contains('SocketException') ||
              errorString.contains('ClientException')) {
            print('📴 Error de conexión real a Supabase - Encolando LISTO PARA RECOGER');
            actualizadoExitosamente = false;
          } else {
            // Error no relacionado con conexión: mostrarlo (pero NO revertir estado local)
            print('❌ Error NO de red marcando LISTO PARA RECOGER: $e');
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
              _mostrarMensaje('Error al marcar como "Listo para recoger": $e');
            }
            return;
          }
        }
      }

      // Si no se actualizó exitosamente (sin conexión o DNS), encolar operación
      if (!actualizadoExitosamente) {
        try {
          await syncService.addOperation(
            type: 'update_orden_estado',
            ordenId: widget.orden.id,
            data: updateData,
          );
          print('📝 Operación LISTO PARA RECOGER agregada a la cola');
        } catch (e) {
          print('⚠️ Error agregando LISTO PARA RECOGER a la cola: $e');
        }
      }

      // Recargar y enviar email SOLO si realmente se actualizó en BD
      if (actualizadoExitosamente) {
        // Recargar la orden para obtener datos actualizados
        try {
          await _recargarOrden();
        } catch (e) {
          print('⚠️ Error recargando orden tras LISTO PARA RECOGER: $e');
        }

        // Enviar email al emisor cuando la orden está lista para recoger
        print('📧 ===== INICIANDO PROCESO DE EMAIL LISTO PARA RECOGER =====');
        try {
          // Obtener tenant_id de la orden
          final tenantId = _ordenActual.tenantId;

          // Obtener email del emisor desde la tabla emisores
          String? emailEmisor;
          try {
            final emisorData = await supabase
                .from('emisores')
                .select('email')
                .eq('nombre', _ordenActual.emisor)
                .eq('tenant_id', tenantId ?? '')
                .maybeSingle();

            if (emisorData != null && emisorData['email'] != null) {
              emailEmisor = emisorData['email'] as String;
              print('📧 Email del emisor obtenido: $emailEmisor');
            } else {
              print('⚠️ No se encontró email del emisor en la tabla emisores');
            }
          } catch (e) {
            print('⚠️ Error obteniendo email del emisor: $e');
          }

          // Enviar email si tenemos el email del emisor
          if (emailEmisor != null && emailEmisor.isNotEmpty && tenantId != null) {
            EmailService.enviarEmailOrdenListaParaRecoger(_ordenActual, emailEmisor, tenantId: tenantId)
                .then((enviado) {
              print(enviado
                  ? '✅ ✅ ✅ Email LISTO PARA RECOGER enviado EXITOSAMENTE ✅ ✅ ✅'
                  : '⚠️ ⚠️ ⚠️ Email LISTO PARA RECOGER falló ⚠️ ⚠️ ⚠️');
            }).catchError((e) {
              print('❌ ❌ ❌ ERROR CRÍTICO enviando email LISTO PARA RECOGER ❌ ❌ ❌');
              print('❌ Error: $e');
            });
          } else {
            print(
                '⚠️ No se puede enviar email: emailEmisor=${emailEmisor != null ? "disponible" : "null"}, tenantId=${tenantId != null ? "disponible" : "null"}');
          }
        } catch (e) {
          print('❌ Error en proceso de email LISTO PARA RECOGER: $e');
        }
      } else {
        print('📴 Modo offline: email y recarga omitidos (se hará cuando sincronice)');
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _mostrarMensaje(
          actualizadoExitosamente
              ? '✅ Orden marcada como "Listo para recoger"'
              : '✅ Orden marcada como "Listo para recoger" (se sincronizará cuando haya conexión)',
        );
      }
    }
  }

  Future<void> _iniciarRecolectaColaborador() async {
    if (!OrdenRecogidaColaboradorUi.puedeIniciarRecolecta(_ordenActual)) {
      _mostrarMensaje('El colaborador debe indicar que está listo antes de iniciar la recolecta.');
      return;
    }
    final confirmado = await _mostrarConfirmacion(
      'Iniciar recolecta',
      '¿Confirmas que vas en camino al colaborador para recoger el pedido?\n\nEl colaborador será notificado.',
    );
    if (!confirmado) return;

    setState(() => _isLoading = true);
    try {
      final res = await supabase.rpc(
        'repartidor_iniciar_recolecta_colaborador',
        params: {'p_orden_id': widget.orden.id},
      );
      final payload = res as Map<String, dynamic>? ?? {};
      if (payload['ok'] != true) {
        _mostrarMensaje('No se pudo registrar el inicio de recolecta.');
        return;
      }
      await _recargarOrden();
      _mostrarMensaje('El colaborador verá que vas en camino.');
    } catch (e) {
      print('❌ iniciar recolecta: $e');
      _mostrarMensaje('Error al iniciar la recolecta.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmarRecogidaEnColaborador() async {
    if (!OrdenRecogidaColaboradorUi.puedeConfirmarRecogida(_ordenActual)) {
      _mostrarMensaje('Primero inicia la recolecta cuando salgas hacia el colaborador.');
      return;
    }

    final confirmado = await _mostrarConfirmacion(
      'Confirmar recogida',
      '¿Confirmas que ya recogiste el pedido en el colaborador?\n\nDespués podrás ver la dirección del cliente y entregar.',
    );
    if (!confirmado) return;

    setState(() => _isLoading = true);
    const nuevoEstado = 'EN REPARTO';
    _ordenActual.estado = nuevoEstado;

    final syncResult = await OrdenEstadoSyncHelper.persistirCambioEstado(
      ordenId: widget.orden.id,
      ordenEnCache: _ordenActual,
      updateData: {'estado': nuevoEstado},
    );

    if (mounted) {
      setState(() => _isLoading = false);
      _mostrarMensaje(
        syncResult.persistedToDb
            ? '✅ Recogida confirmada. Ya puedes entregar al cliente.'
            : '✅ Recogida guardada localmente (sincroniza al reconectar).',
      );
    }
  }

  void _marcarComoEnReparto() async {
    // Verificar que la orden esté en "EN TRANSITO"
    if (_ordenActual.estado != 'EN TRANSITO' && _ordenActual.estado != 'ATRASADO') {
      _mostrarMensaje('Solo puedes iniciar reparto desde órdenes en "EN TRANSITO"');
      return;
    }
    
    final confirmado = await _mostrarConfirmacion(
      'Iniciar Reparto',
      '¿Estás seguro de que quieres iniciar el reparto de esta orden?\n\nEsto activará el rastreo GPS de tu ubicación.',
    );
    
    if (confirmado) {
      setState(() {
        _isLoading = true;
      });
      
      // Actualizar estado localmente
      _ordenActual.estado = 'EN REPARTO';
      await OrdenCacheService.updateCachedOrder(_ordenActual);
      
      final syncService = SyncService();
      final updateData = {
        'estado': 'EN REPARTO',
      };
      
      // Intentar actualizar en BD si hay conexión
      bool actualizadoExitosamente = false;
      
      if (syncService.isOnline) {
        try {
          await supabase
              .from('ordenes')
              .update(updateData)
              .eq('id', widget.orden.id);
          
          print('✅ Estado actualizado en BD (online)');
          actualizadoExitosamente = true;
          
          // Obtener email del EMISOR y enviar email
          try {
            // Primero obtener el emisor_id de la orden
            final ordenData = await supabase
                .from('ordenes')
                .select('emisor_id, tenant_id, emisor_nombre')
                .eq('id', widget.orden.id)
                .single();
            
            final emisorId = ordenData['emisor_id']?.toString();
            final tenantId = ordenData['tenant_id']?.toString() ?? _ordenActual.tenantId;
            
            String? emailEmisor;
            
            // Si tenemos emisor_id, obtener el email del emisor
            if (emisorId != null && emisorId.isNotEmpty) {
              try {
                final emisorData = await supabase
                    .from('emisores')
                    .select('email')
                    .eq('id', emisorId)
                    .maybeSingle();
                
                emailEmisor = emisorData?['email']?.toString();
                print('📧 Email del emisor obtenido: $emailEmisor');
              } catch (e) {
                print('⚠️ Error obteniendo email del emisor: $e');
              }
            }
            
            // Si no tenemos email por emisor_id, intentar obtenerlo del nombre del emisor
            if ((emailEmisor == null || emailEmisor.isEmpty) && _ordenActual.emisor.isNotEmpty) {
              try {
                final emisorData = await supabase
                    .from('emisores')
                    .select('email')
                    .eq('nombre', _ordenActual.emisor)
                    .maybeSingle();
                
                emailEmisor = emisorData?['email']?.toString();
                print('📧 Email del emisor obtenido por nombre: $emailEmisor');
              } catch (e) {
                print('⚠️ Error obteniendo email del emisor por nombre: $e');
              }
            }
            
            if (emailEmisor != null && emailEmisor.isNotEmpty) {
              final configService = ConfiguracionService();
              final notificacionesHabilitadas = await configService.notificacionesHabilitadas('emisores', tenantId: tenantId);
              
              if (notificacionesHabilitadas) {
                try {
                  final enviado = await EmailService.enviarEmailOrdenEnReparto(_ordenActual, emailEmisor, tenantId: tenantId);
                  if (enviado) {
                    print('✅ Email de orden en reparto enviado al emisor: $emailEmisor');
                    if (mounted) {
                      _mostrarMensaje('✅ Email de notificación enviado');
                    }
                  } else {
                    print('⚠️ No se pudo enviar el email al emisor');
                  }
                } catch (e) {
                  print('❌ Error enviando email: $e');
                }
              } else {
                print('⚠️ Notificaciones para emisores están deshabilitadas');
              }
            } else {
              print('⚠️ No se encontró email del emisor para la orden ${_ordenActual.numeroOrden}');
            }
          } catch (e) {
            print('⚠️ Error al obtener datos para email: $e');
            print('Stack trace: ${StackTrace.current}');
            // No es crítico, la orden ya se actualizó
          }
          
          if (mounted) {
            // Recargar la orden para mostrar los detalles actualizados
            await _recargarOrden();
            _mostrarMensaje('✅ Reparto iniciado - Rastreo GPS activado');
            Navigator.pop(context, true);
          }
        } catch (e) {
          print('⚠️ Error actualizando en BD (posible falta de conexión real): $e');
          print('📴 Agregando a cola de sincronización...');
          actualizadoExitosamente = false;
        }
      }
      
      // Si no se actualizó exitosamente (sin conexión o error), agregar a cola
      if (!actualizadoExitosamente) {
        try {
          await syncService.addOperation(
            type: 'update_orden_estado',
            ordenId: widget.orden.id,
            data: updateData,
          );
          
          if (mounted) {
            _mostrarMensaje('✅ Reparto iniciado (se sincronizará cuando haya conexión)');
            Navigator.pop(context, true);
          }
        } catch (e) {
          print('❌ Error agregando a cola de sincronización: $e');
          if (mounted) {
            _mostrarMensaje('✅ Reparto iniciado localmente (se sincronizará cuando haya conexión)');
            Navigator.pop(context, true);
          }
        }
      }
      
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _mostrarConfirmacion(String titulo, String mensaje, {Color? colorIcono, IconData? icono}) async {
    if (!mounted) return false;
    
    final iconColor = colorIcono ?? const Color(0xFFFF9800);
    final iconData = icono ?? Icons.check_circle_outline;
    
    final resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => VolonexDialog(
        title: titulo,
        leading: Icon(iconData, color: iconColor, size: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Antes de continuar, verifica:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: iconColor),
              ),
              child: Text(
                mensaje,
                style: TextStyle(
                  color: iconColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: AppColors.exito, size: 16),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '¿Confirmas que esta información es correcta?',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.darkTextMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: iconColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return resultado ?? false;
  }

  void _mostrarMensaje(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: const Color(0xFF1976D2),
      ),
    );
  }

  // Validar y entregar remesa
  Future<bool> _validarYEntregarRemesa() async {
    if (!_ordenActual.tieneRemesa) {
      return true; // No tiene remesa, continuar
    }
    
    final cantidadRemesa = _ordenActual.cantidadRemesa ?? 0.0;
    final resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(Icons.attach_money, color: Color(0xFF1976D2), size: 24),
            SizedBox(width: 12),
            Text(
              'Confirmar Entrega de Remesa',
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
            const Text(
              '💰 Antes de continuar, verifica:',
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
                    'Cantidad de Remesa:',
                    style: TextStyle(
                      color: Color(0xFF666666),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\$${cantidadRemesa.toStringAsFixed(2)}',
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
                      '¿Entregaste la remesa correctamente al cliente?',
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
        actionsOverflowButtonSpacing: 12,
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF666666),
                    side: const BorderSide(color: Color(0xFFE0E0E0), width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Sí, Confirmar',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    
    if (resultado == true) {
      // La remesa es solo una validación antes de entregar
      // No necesitamos actualizar ningún campo en la BD
      // Solo retornamos true para indicar que la validación pasó
      print('✅ Remesa confirmada por el repartidor');
      return true;
    }
    
    return false;
  }
  
  // Validar y cobrar pago
  Future<bool> _validarYCobrarPago() async {
    if (!_ordenActual.requierePago || _ordenActual.pagado) {
      return true; // No requiere pago o ya está pagado, continuar
    }
    
    final simbolo = _ordenActual.moneda == 'USD' ? '\$' : '\$';
    final monto = _ordenActual.montoCobrar.toStringAsFixed(2);
    
    final resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(Icons.payment, color: Color(0xFFFF9800), size: 24),
            SizedBox(width: 12),
            Text(
              'Confirmar Cobro',
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
            const Text(
              '💵 Antes de continuar, verifica:',
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
                color: const Color(0xFFFF9800).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFF9800)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Monto a Cobrar:',
                    style: TextStyle(
                      color: Color(0xFF666666),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$simbolo$monto ${_ordenActual.moneda}',
                    style: const TextStyle(
                      color: Color(0xFFFF9800),
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
                      '¿El cliente ya pagó este monto?',
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
        actionsOverflowButtonSpacing: 12,
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF666666),
                    side: const BorderSide(color: Color(0xFFE0E0E0), width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Sí, Confirmar',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    
    if (resultado == true) {
      setState(() {
        _isLoading = true;
      });
      
      // ✅ OFFLINE-FIRST: Actualizar estado local INMEDIATAMENTE
      try {
        // Actualizar estado local
        final ordenJson = _ordenActual.toJson();
        ordenJson['pagado'] = true;
        ordenJson['fecha_pago'] = DateTime.now().toIso8601String();
        _ordenActual = Orden.fromJson(ordenJson);
        
        // Guardar en caché local INMEDIATAMENTE
        await OrdenCacheService.updateCachedOrder(_ordenActual);
        print('💾 Pago registrado en caché local');
        
        final syncService = SyncService();
        final updateData = {
          'pagado': true,
          'fecha_pago': DateTime.now().toIso8601String(),
        };
        
        // Intentar actualizar en BD si hay conexión
        if (syncService.isOnline) {
          try {
            await supabase
                .from('ordenes')
                .update(updateData)
                .eq('id', widget.orden.id);
            
            print('✅ Pago registrado en BD (online)');
          } catch (e) {
            // Si falla, agregar a cola de sincronización
            final errorString = e.toString();
            if (errorString.contains('Failed host lookup') || 
                errorString.contains('SocketException') ||
                errorString.contains('ClientException')) {
              print('📴 Error de conexión - Agregando a cola de sincronización');
              await syncService.addOperation(
                type: 'update_orden_estado',
                ordenId: widget.orden.id,
                data: updateData,
              );
            } else {
              // Error no relacionado con conexión
              _mostrarMensaje('Error al registrar el cobro: $e');
              if (mounted) {
                setState(() {
                  _isLoading = false;
                });
              }
              return false;
            }
          }
        } else {
          // Sin conexión - Agregar a cola de sincronización
          print('📴 Sin conexión - Agregando a cola de sincronización');
          await syncService.addOperation(
            type: 'update_orden_estado',
            ordenId: widget.orden.id,
            data: updateData,
          );
        }
        
        // NO recargar orden después de registrar pago porque puede sobrescribir foto/firma locales
        // El estado local ya está actualizado
        
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        
        return true;
      } catch (e) {
        print('❌ Error al registrar el cobro: $e');
        _mostrarMensaje('Error al registrar el cobro: $e');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return false;
      }
    }
    
    return false;
  }

  void _marcarDineroCobrado() async {
    final simbolo = widget.orden.moneda == 'USD' ? '\$' : '\$';
    final monto = widget.orden.montoCobrar.toStringAsFixed(2);
    
    final resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(Icons.payment, color: Color(0xFFFF9800), size: 24),
            SizedBox(width: 12),
            Text(
              'Confirmar Cobro',
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
            const Text(
              '💵 Antes de continuar, verifica:',
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
                color: const Color(0xFFFF9800).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFF9800)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Monto a Cobrar:',
                    style: TextStyle(
                      color: Color(0xFF666666),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$simbolo$monto ${widget.orden.moneda}',
                    style: const TextStyle(
                      color: Color(0xFFFF9800),
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
                      '¿El cliente ya pagó este monto?',
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
        actions: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF666666),
                side: const BorderSide(color: Color(0xFFE0E0E0), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Cancelar',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Sí, Confirmar',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    
    if (resultado == true) {
      setState(() {
        _isLoading = true;
      });
      
      try {
        await supabase
            .from('ordenes')
            .update({
              'pagado': true,
              'fecha_pago': DateTime.now().toIso8601String(),
            })
            .eq('id', widget.orden.id);
        
        // Recargar la orden para reflejar el cambio
        await _recargarOrden();
        
        _mostrarMensaje('✅ Dinero cobrado registrado. Ahora puedes entregar la orden.');
        
      } catch (e) {
        _mostrarMensaje('Error al registrar el cobro: $e');
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  // ignore: unused_element
  Future<void> _tomarFotoEntrega() async {
    if (!mounted) return;
    
    // 🔒 Validación: Permitir tomar foto cuando el estado es "EN REPARTO" 
    // o cuando es "LISTO PARA RECOGER" para órdenes con recoger_en_sucursal
    if (_esRemesaPura()) {
      _mostrarMensaje('Las remesas no requieren foto de entrega.');
      return;
    }

    final estadoValido = _ordenActual.estado == 'EN REPARTO' ||
        (_ordenActual.estado == 'LISTO PARA RECOGER' && _ordenActual.recogerEnSucursal);
    
    if (!estadoValido) {
      _mostrarMensaje('⚠️ Solo puedes tomar la foto cuando la orden está en "EN REPARTO" o "LISTO PARA RECOGER" (recogida en sucursal)');
      return;
    }
    
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1024,
        maxHeight: 1024,
      );

      if (image != null && mounted) {
        if (mounted) {
          setState(() {
            _isLoading = true;
          });
        }

        try {
          final fileBytes = await image.readAsBytes();
          final photoBase64 = base64Encode(fileBytes);
          
          // Guardar foto localmente
          await OfflineStorageService().savePendingPhoto(
            ordenId: widget.orden.id,
            filePath: image.path,
          );
          
          final syncService = SyncService();
          
          // Intentar subir si hay conexión
          if (syncService.isOnline) {
            try {
              final fileName = 'entrega_${widget.orden.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
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
                  .eq('id', widget.orden.id);

              print('✅ Foto subida exitosamente (online)');
              
              if (mounted) {
                // 🔒 CRÍTICO: Actualizar tanto _fotoEntregaUrl como _ordenActual
                try {
                  final ordenJson = _ordenActual.toJson();
                  ordenJson['foto_entrega'] = imageUrl;
                  final ordenActualizada = Orden.fromJson(ordenJson);
                  
                  setState(() {
                    _fotoEntregaUrl = imageUrl;
                    _ordenActual = ordenActualizada; // 🔒 Sincronizar _ordenActual
                    _isLoading = false;
                  });
                  
                  // Actualizar caché también
                  await OrdenCacheService.updateCachedOrder(ordenActualizada);
                  print('✅ _ordenActual y caché actualizados con foto: $imageUrl');
                } catch (e) {
                  print('⚠️ Error actualizando _ordenActual con foto: $e');
                  setState(() {
                    _fotoEntregaUrl = imageUrl;
                    _isLoading = false;
                  });
                }
                
                _mostrarMensaje('✅ Foto subida exitosamente');
              }
            } catch (uploadError) {
              print('⚠️ Error subiendo foto, agregando a cola: $uploadError');
              // Si falla, agregar a cola de sincronización
              await syncService.addOperation(
                type: 'upload_photo',
                ordenId: widget.orden.id,
                data: {
                  'photo_base64': photoBase64,
                  'file_path': image.path, // 🔒 CRÍTICO: Incluir ruta del archivo para sincronización
                },
              );
              
              // 🔒 CRÍTICO: Actualizar caché local de la orden con la foto local
              try {
                final ordenJson = _ordenActual.toJson();
                ordenJson['foto_entrega'] = 'local://${image.path}';
                final ordenActualizada = Orden.fromJson(ordenJson);
                await OrdenCacheService.updateCachedOrder(ordenActualizada);
                print('💾 Orden actualizada en caché local con foto: ${image.path}');
              } catch (e) {
                print('⚠️ Error actualizando caché local con foto: $e');
              }
              
              // 🔒 CRÍTICO: Actualizar _ordenActual también
              final fotoLocalUrl = 'local://${image.path}';
              try {
                final ordenJson = _ordenActual.toJson();
                ordenJson['foto_entrega'] = fotoLocalUrl;
                final ordenActualizada = Orden.fromJson(ordenJson);
                
                if (mounted) {
                  setState(() {
                    _fotoEntregaUrl = fotoLocalUrl;
                    _ordenActual = ordenActualizada; // 🔒 Sincronizar _ordenActual
                    _isLoading = false;
                  });
                  print('✅ _ordenActual y _fotoEntregaUrl actualizados con foto local: $fotoLocalUrl');
                }
              } catch (e) {
                print('⚠️ Error actualizando _ordenActual con foto: $e');
                if (mounted) {
                  setState(() {
                    _fotoEntregaUrl = fotoLocalUrl;
                    _isLoading = false;
                  });
                }
              }
              
              if (mounted) {
                _mostrarMensaje('✅ Foto guardada (se sincronizará cuando haya conexión) - Puedes continuar con la entrega');
              }
            }
          } else {
            // Sin conexión, agregar a cola directamente
            print('📴 Sin conexión - Agregando foto a cola de sincronización');
            await syncService.addOperation(
              type: 'upload_photo',
              ordenId: widget.orden.id,
              data: {
                'photo_base64': photoBase64,
                'file_path': image.path, // 🔒 CRÍTICO: Incluir ruta del archivo para sincronización
              },
            );
            
            // 🔒 CRÍTICO: Actualizar caché local de la orden con la foto local
            try {
              final ordenJson = _ordenActual.toJson();
              ordenJson['foto_entrega'] = 'local://${image.path}';
              final ordenActualizada = Orden.fromJson(ordenJson);
              await OrdenCacheService.updateCachedOrder(ordenActualizada);
              print('💾 Orden actualizada en caché local con foto: ${image.path}');
            } catch (e) {
              print('⚠️ Error actualizando caché local con foto: $e');
            }
            
            // 🔒 CRÍTICO: Actualizar _ordenActual también
            final fotoLocalUrl = 'local://${image.path}';
            try {
              final ordenJson = _ordenActual.toJson();
              ordenJson['foto_entrega'] = fotoLocalUrl;
              final ordenActualizada = Orden.fromJson(ordenJson);
              
              if (mounted) {
                setState(() {
                  _fotoEntregaUrl = fotoLocalUrl;
                  _ordenActual = ordenActualizada; // 🔒 Sincronizar _ordenActual
                  _isLoading = false;
                });
                print('✅ _ordenActual y _fotoEntregaUrl actualizados con foto local (offline): $fotoLocalUrl');
              }
            } catch (e) {
              print('⚠️ Error actualizando _ordenActual con foto: $e');
              if (mounted) {
                setState(() {
                  _fotoEntregaUrl = fotoLocalUrl;
                  _isLoading = false;
                });
              }
            }
            
            if (mounted) {
              _mostrarMensaje('✅ Foto guardada (modo offline) - Puedes continuar con la entrega');
            }
          }
        } catch (e) {
          print('❌ Error procesando foto: $e');
          if (mounted) {
            _mostrarMensaje('❌ Error al procesar la foto: $e');
            setState(() {
              _isLoading = false;
            });
          }
        }
      }
    } catch (e) {
      print('❌ Error al tomar la foto: $e');
      if (mounted) {
        _mostrarMensaje('❌ Error al tomar la foto: $e');
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Tomar/seleccionar foto con selector de cámara/galería
  Future<void> _tomarFotoEntregaConSelector() async {
    if (!mounted) return;

    if (_esRemesaPura()) {
      _mostrarMensaje('Las remesas no requieren foto de entrega.');
      return;
    }

    final estadoValido = _ordenActual.estado == 'EN REPARTO' ||
        (_ordenActual.estado == 'LISTO PARA RECOGER' && _ordenActual.recogerEnSucursal);
    
    if (!estadoValido) {
      _mostrarMensaje('⚠️ Solo puedes tomar la foto cuando la orden está en "EN REPARTO" o "LISTO PARA RECOGER" (recogida en sucursal)');
      return;
    }
    
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
        if (mounted) {
          setState(() {
            _isLoading = true;
          });
        }

        try {
          final fileBytes = await image.readAsBytes();
          final photoBase64 = base64Encode(fileBytes);
          
          // Guardar foto localmente
          await OfflineStorageService().savePendingPhoto(
            ordenId: widget.orden.id,
            filePath: image.path,
          );
          
          final syncService = SyncService();
          
          // Intentar subir si hay conexión
          if (syncService.isOnline) {
            try {
              final fileName = 'entrega_${widget.orden.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
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
                  .eq('id', widget.orden.id);

              print('✅ Foto subida exitosamente (online)');
              
              if (mounted) {
                // 🔒 CRÍTICO: Actualizar tanto _fotoEntregaUrl como _ordenActual
                try {
                  final ordenJson = _ordenActual.toJson();
                  ordenJson['foto_entrega'] = imageUrl;
                  final ordenActualizada = Orden.fromJson(ordenJson);
                  
                  setState(() {
                    _fotoEntregaUrl = imageUrl;
                    _ordenActual = ordenActualizada; // 🔒 Sincronizar _ordenActual
                    _isLoading = false;
                  });
                  
                  // Actualizar caché también
                  await OrdenCacheService.updateCachedOrder(ordenActualizada);
                  print('✅ _ordenActual y caché actualizados con foto: $imageUrl');
                } catch (e) {
                  print('⚠️ Error actualizando _ordenActual con foto: $e');
                  setState(() {
                    _fotoEntregaUrl = imageUrl;
                    _isLoading = false;
                  });
                }
                
                _mostrarMensaje('✅ Foto subida exitosamente');
              }
            } catch (uploadError) {
              print('⚠️ Error subiendo foto, agregando a cola: $uploadError');
              // Si falla, agregar a cola de sincronización
              await syncService.addOperation(
                type: 'upload_photo',
                ordenId: widget.orden.id,
                data: {
                  'photo_base64': photoBase64,
                  'file_path': image.path, // 🔒 CRÍTICO: Incluir ruta del archivo para sincronización
                },
              );
              
              // 🔒 CRÍTICO: Actualizar caché local de la orden con la foto local
              try {
                final ordenJson = _ordenActual.toJson();
                ordenJson['foto_entrega'] = 'local://${image.path}';
                final ordenActualizada = Orden.fromJson(ordenJson);
                await OrdenCacheService.updateCachedOrder(ordenActualizada);
                print('💾 Orden actualizada en caché local con foto: ${image.path}');
              } catch (e) {
                print('⚠️ Error actualizando caché local con foto: $e');
              }
              
              // 🔒 CRÍTICO: Actualizar _ordenActual también
              final fotoLocalUrl = 'local://${image.path}';
              try {
                final ordenJson = _ordenActual.toJson();
                ordenJson['foto_entrega'] = fotoLocalUrl;
                final ordenActualizada = Orden.fromJson(ordenJson);
                
                if (mounted) {
                  setState(() {
                    _fotoEntregaUrl = fotoLocalUrl;
                    _ordenActual = ordenActualizada; // 🔒 Sincronizar _ordenActual
                    _isLoading = false;
                  });
                  print('✅ _ordenActual y _fotoEntregaUrl actualizados con foto local: $fotoLocalUrl');
                }
              } catch (e) {
                print('⚠️ Error actualizando _ordenActual con foto: $e');
                if (mounted) {
                  setState(() {
                    _fotoEntregaUrl = fotoLocalUrl;
                    _isLoading = false;
                  });
                }
              }
              
              if (mounted) {
                _mostrarMensaje('✅ Foto guardada (se sincronizará cuando haya conexión) - Puedes continuar con la entrega');
              }
            }
          } else {
            // Sin conexión, agregar a cola directamente
            print('📴 Sin conexión - Agregando foto a cola de sincronización');
            await syncService.addOperation(
              type: 'upload_photo',
              ordenId: widget.orden.id,
              data: {
                'photo_base64': photoBase64,
                'file_path': image.path, // 🔒 CRÍTICO: Incluir ruta del archivo para sincronización
              },
            );
            
            // 🔒 CRÍTICO: Actualizar caché local de la orden con la foto local
            try {
              final ordenJson = _ordenActual.toJson();
              ordenJson['foto_entrega'] = 'local://${image.path}';
              final ordenActualizada = Orden.fromJson(ordenJson);
              await OrdenCacheService.updateCachedOrder(ordenActualizada);
              print('💾 Orden actualizada en caché local con foto: ${image.path}');
            } catch (e) {
              print('⚠️ Error actualizando caché local con foto: $e');
            }
            
            // 🔒 CRÍTICO: Actualizar _ordenActual también
            final fotoLocalUrl = 'local://${image.path}';
            try {
              final ordenJson = _ordenActual.toJson();
              ordenJson['foto_entrega'] = fotoLocalUrl;
              final ordenActualizada = Orden.fromJson(ordenJson);
              
              if (mounted) {
                setState(() {
                  _fotoEntregaUrl = fotoLocalUrl;
                  _ordenActual = ordenActualizada; // 🔒 Sincronizar _ordenActual
                  _isLoading = false;
                });
                print('✅ _ordenActual y _fotoEntregaUrl actualizados con foto local (offline): $fotoLocalUrl');
              }
            } catch (e) {
              print('⚠️ Error actualizando _ordenActual con foto: $e');
              if (mounted) {
                setState(() {
                  _fotoEntregaUrl = fotoLocalUrl;
                  _isLoading = false;
                });
              }
            }
            
            if (mounted) {
              _mostrarMensaje('✅ Foto guardada (modo offline) - Puedes continuar con la entrega');
            }
          }
        } catch (e) {
          print('❌ Error procesando foto: $e');
          if (mounted) {
            _mostrarMensaje('❌ Error al procesar la foto: $e');
            setState(() {
              _isLoading = false;
            });
          }
        }
      }
    } catch (e) {
      print('❌ Error al seleccionar foto: $e');
      if (mounted) {
        _mostrarMensaje('❌ Error al seleccionar foto: $e');
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 🔍 NUEVO: Diálogo de confirmación de bultos
  Future<bool> _mostrarDialogoConfirmacionBultos() async {
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
            Text(
              'Verificar Bultos',
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
                    '${widget.orden.cantidadBultos} ${widget.orden.cantidadBultos == 1 ? 'bulto' : 'bultos'}',
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
        actions: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF666666),
                side: const BorderSide(color: Color(0xFFE0E0E0), width: 1.5),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Cancelar',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                'Sí, Confirmar',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return resultado ?? false;
  }

  // Subir firma a Supabase Storage (con soporte offline)
  Future<String?> _subirFirmaASupabase(Uint8List firmaBytes, String ordenId) async {
    print('');
    print('☁️ ========================================');
    print('☁️ _subirFirmaASupabase() INICIADO');
    print('☁️ ========================================');
    print('☁️ Orden ID: $ordenId');
    print('☁️ Firma bytes: ${firmaBytes.length} bytes');
    print('☁️ ========================================');
    
    try {
      final firmaBase64 = base64Encode(firmaBytes);
      final syncService = SyncService();
      print('☁️ Estado online: ${syncService.isOnline}');
      
      // 🔒 CRÍTICO: Verificar si ya existe una operación upload_firma pendiente para esta orden
      // Verificar en pending_signatures de OfflineStorageService
      final offlineStorage = OfflineStorageService();
      final pendingSignatures = await offlineStorage.getPendingSignatures();
      final tieneFirmaPendiente = pendingSignatures.any((sig) => sig['orden_id'] == ordenId);
      print('☁️ Firma pendiente existente: $tieneFirmaPendiente');
      
      if (tieneFirmaPendiente) {
        print('⚠️ Ya existe una operación upload_firma pendiente para esta orden - No se agregará otra');
        // Retornar la URL local existente si hay una
        final offlineStorage = OfflineStorageService();
        final pendingSignatures = await offlineStorage.getPendingSignatures();
        final existingSignature = pendingSignatures.firstWhere(
          (sig) => sig['orden_id'] == ordenId,
          orElse: () => <String, dynamic>{},
        );
        if (existingSignature.isNotEmpty) {
          final localUrl = 'local://${existingSignature['file_path']}';
          print('✅ Retornando URL local existente: $localUrl');
          return localUrl;
        }
      }
      
      // Guardar firma localmente en almacenamiento PERSISTENTE (no code_cache)
      print('💾 Guardando firma localmente...');
      final appSupportDir = await getApplicationSupportDirectory();
      final firmasDir = Directory('${appSupportDir.path}/firmas_entrega');
      await firmasDir.create(recursive: true);
      final tempFile = File('${firmasDir.path}/firma_${ordenId}_${DateTime.now().millisecondsSinceEpoch}.png');
      await tempFile.writeAsBytes(firmaBytes);
      print('💾 Firma guardada en: ${tempFile.path}');
      
      print('💾 Guardando en pending_signatures...');
      await OfflineStorageService().savePendingSignature(
        ordenId: ordenId,
        filePath: tempFile.path,
      );
      print('✅ Firma agregada a pending_signatures');
      
      // Intentar subir si hay conexión
      if (syncService.isOnline) {
        print('🌐 Hay conexión - Intentando subir a Supabase...');
        try {
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final fileName = 'firma_${ordenId}_$timestamp.png';
          
          // 🔒 Usar el bucket 'firmas' que existe en Supabase
          await supabase.storage.from('firmas').uploadBinary(
            fileName,
            firmaBytes,
          );
          
          final urlResponse = supabase.storage.from('firmas').getPublicUrl(fileName);
          print('✅ Firma subida exitosamente (online)');
          
          // 🔒 CRÍTICO: Eliminar de pending_signatures después de subir exitosamente
          try {
            final offlineStorage = OfflineStorageService();
            final pendingSignatures = await offlineStorage.getPendingSignatures();
            for (final sig in pendingSignatures) {
              if (sig['orden_id'] == ordenId) {
                await offlineStorage.deletePendingSignature(sig['id'].toString());
                print('🗑️ Firma eliminada de pending_signatures (ya subida): ${sig['id']}');
              }
            }
          } catch (e) {
            print('⚠️ Error eliminando firma de pending_signatures: $e');
          }
          
          return urlResponse;
        } catch (e) {
          print('⚠️ Error subiendo firma, agregando a cola: $e');
          // Si falla, agregar a cola de sincronización
          await syncService.addOperation(
            type: 'upload_firma',
            ordenId: ordenId,
            data: {
              'firma_base64': firmaBase64,
              'file_path': tempFile.path, // 🔒 CRÍTICO: Incluir ruta del archivo
            },
          );
          
          // 🔒 CRÍTICO: Eliminar de pending_signatures inmediatamente después de agregar a la cola
          // (similar a como se hace con las fotos)
          try {
            final offlineStorage = OfflineStorageService();
            final pendingSignatures = await offlineStorage.getPendingSignatures();
            for (final sig in pendingSignatures) {
              if (sig['orden_id'] == ordenId && sig['file_path'] == tempFile.path) {
                await offlineStorage.deletePendingSignature(sig['id'].toString());
                print('🗑️ Firma eliminada de pending_signatures (ya está en la cola): ${sig['id']}');
              }
            }
          } catch (e) {
            print('⚠️ Error eliminando firma de pending_signatures: $e');
          }
          
          return 'local://${tempFile.path}'; // URL temporal local
        }
      } else {
        // Sin conexión, agregar a cola directamente
        print('📴 ========================================');
        print('📴 SIN CONEXIÓN - Modo offline');
        print('📴 ========================================');
        print('📴 Agregando firma a cola de sincronización...');
        
        await syncService.addOperation(
          type: 'upload_firma',
          ordenId: ordenId,
          data: {
            'firma_base64': firmaBase64,
            'file_path': tempFile.path, // 🔒 CRÍTICO: Incluir ruta del archivo
          },
        );
        print('✅ Firma agregada a cola de sincronización');
        
        // 🔒 CRÍTICO: Eliminar de pending_signatures inmediatamente después de agregar a la cola
        try {
          final offlineStorage = OfflineStorageService();
          final pendingSignatures = await offlineStorage.getPendingSignatures();
          print('📴 Limpiando pending_signatures (${pendingSignatures.length} firmas pendientes)...');
          
          for (final sig in pendingSignatures) {
            if (sig['orden_id'] == ordenId && sig['file_path'] == tempFile.path) {
              await offlineStorage.deletePendingSignature(sig['id'].toString());
              print('🗑️ Firma eliminada de pending_signatures (ya está en la cola): ${sig['id']}');
            }
          }
        } catch (e) {
          print('⚠️ Error eliminando firma de pending_signatures: $e');
        }
        
        final localUrl = 'local://${tempFile.path}';
        print('✅ Retornando URL local (offline): $localUrl');
        print('📴 ========================================');
        print('');
        return localUrl; // URL temporal local
      }
    } catch (e) {
      print('');
      print('❌ ========================================');
      print('❌ ERROR CRÍTICO AL PROCESAR FIRMA');
      print('❌ ========================================');
      print('❌ Error: $e');
      print('❌ Tipo de error: ${e.runtimeType}');
      print('❌ ========================================');
      print('');
      return null;
    }
  }

  // ignore: unused_element
  void _mostrarDialogoErroresEntrega(List<String> errores) {
    if (!mounted) return;
    
    // Determinar el título según los errores
    String titulo = 'Completar entrega';
    IconData iconoTitulo = Icons.check_circle_outline;
    Color colorTitulo = const Color(0xFF1976D2);
    
    // Si requiere foto, priorizar foto
    if (errores.any((e) => e.contains('foto') || e.contains('Foto') || e.contains('📷'))) {
      titulo = 'Tomar foto de entrega';
      iconoTitulo = Icons.camera_alt;
      colorTitulo = const Color(0xFF1976D2);
    } 
    // Si requiere firma, priorizar firma
    else if (errores.any((e) => e.contains('firma') || e.contains('Firma') || e.contains('✍️'))) {
      titulo = 'Capturar firma';
      iconoTitulo = Icons.edit;
      colorTitulo = const Color(0xFF9C27B0);
    }
    // Si requiere cobro
    else if (errores.any((e) => e.contains('cobrar') || e.contains('Cobrar') || e.contains('💰'))) {
      titulo = 'Registrar cobro';
      iconoTitulo = Icons.payment;
      colorTitulo = const Color(0xFFFF9800);
    }
    
    showDialog(
      context: context,
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1976D2).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1976D2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2, color: Color(0xFF1976D2), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Esta orden tiene ${_ordenActual.cantidadBultos} ${_ordenActual.cantidadBultos == 1 ? 'bulto' : 'bultos'}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1976D2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
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
                          style: const TextStyle(
                            color: Color(0xFF2C2C2C),
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
        actionsPadding: const EdgeInsets.all(20),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (errores.any((e) => e.contains('foto')) || errores.any((e) => e.contains('cobrar')))
                Row(
                  children: [
                    if (errores.any((e) => e.contains('foto')))
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _tomarFotoEntregaConSelector();
                          },
                          icon: const Icon(Icons.camera_alt, size: 18),
                          label: const Text('Tomar foto'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1976D2),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    if (errores.any((e) => e.contains('foto')) && errores.any((e) => e.contains('cobrar')))
                      const SizedBox(width: 8),
                    if (errores.any((e) => e.contains('cobrar')))
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).pop();
                            _marcarDineroCobrado();
                          },
                          icon: const Icon(Icons.attach_money, size: 18),
                          label: const Text('Cobrar'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4CAF50),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                  ],
                ),
              if (errores.any((e) => e.contains('foto')) || errores.any((e) => e.contains('cobrar')))
                const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF666666),
                    side: const BorderSide(color: Color(0xFFE0E0E0), width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Cerrar',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Mostrar modal de firma
  Future<bool> _mostrarModalFirma() async {
    if (_esRemesaPura()) {
      return true;
    }

    print('');
    print('✍️ ========================================');
    print('✍️ ABRIENDO MODAL DE FIRMA');
    print('✍️ ========================================');
    print('✍️ Mounted: $mounted');
    print('✍️ Firma actual (_firmaUrl): $_firmaUrl');
    print('✍️ Firma en _ordenActual: ${_ordenActual.firmaUrl}');
    print('✍️ Orden ID: ${widget.orden.id}');
    print('✍️ ========================================');
    
    if (!mounted) {
      print('❌ Widget no está montado, cancelando modal de firma');
      return false;
    }
    
    try {
      _signatureController.clear();
      print('✅ SignatureController limpiado');
    } catch (e) {
      print('⚠️ Error al limpiar signature controller: $e');
    }
    
    print('📱 Mostrando diálogo de firma...');
    final resultado = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // 🔒 NO permitir cerrar tocando fuera
      builder: (dialogContext) => _FirmaDialogWidget(
        signatureController: _signatureController,
        ordenId: widget.orden.id,
        tieneFirmaAnterior: _firmaUrl != null,
        subirFirma: _subirFirmaASupabase,
        onFirmaGuardada: (firmaUrl) async {
          print('');
          print('✅ ========================================');
          print('✅ CALLBACK onFirmaGuardada EJECUTADO');
          print('✅ ========================================');
          print('✅ Firma URL recibida: $firmaUrl');
          print('✅ Widget mounted: $mounted');
          print('✅ ========================================');
          
          if (mounted) {
            setState(() {
              _firmaUrl = firmaUrl;
              print('✅ _firmaUrl actualizada en setState: $_firmaUrl');
            });
            
            // 🔒 CRÍTICO: Actualizar _ordenActual con la firma para que las validaciones la vean
            try {
              final ordenJson = _ordenActual.toJson();
              ordenJson['firma_url'] = firmaUrl;
              final ordenActualizada = Orden.fromJson(ordenJson);
              
              setState(() {
                _ordenActual = ordenActualizada;
                print('✅ _ordenActual actualizada en setState: ${_ordenActual.firmaUrl}');
              });
              
              // Actualizar caché local
              await OrdenCacheService.updateCachedOrder(ordenActualizada);
              print('💾 ✅ ✅ ✅ CACHÉ ACTUALIZADO CON FIRMA: $firmaUrl');
              print('💾 Orden en caché: ${ordenActualizada.numeroOrden}');
              print('💾 Estado en caché: ${ordenActualizada.estado}');
              print('💾 Firma en caché: ${ordenActualizada.firmaUrl}');
            } catch (e) {
              print('❌ Error actualizando _ordenActual y caché con firma: $e');
            }
            
            // 🔒 NO recargar orden después de guardar firma local
            // Esto evita que se sobrescriba la firma local con datos de BD
            print('✅ Firma guardada exitosamente - NO se recargará desde BD');
            print('✅ ========================================');
            print('');
          } else {
            print('⚠️ Widget no está montado, no se puede actualizar estado');
          }
        },
      ),
    );
    
    print('');
    print('✍️ ========================================');
    print('✍️ MODAL DE FIRMA CERRADO');
    print('✍️ ========================================');
    print('✍️ Resultado: $resultado');
    print('✍️ Firma actual (_firmaUrl): $_firmaUrl');
    print('✍️ Firma en _ordenActual: ${_ordenActual.firmaUrl}');
    print('✍️ ========================================');
    print('');
    
    return resultado ?? false;
  }
}

// Widget separado para el diálogo de firma
class _FirmaDialogWidget extends StatefulWidget {
  final SignatureController signatureController;
  final String ordenId;
  final bool tieneFirmaAnterior;
  final Function(String) onFirmaGuardada;
  final Future<String?> Function(Uint8List, String) subirFirma;

  const _FirmaDialogWidget({
    required this.signatureController,
    required this.ordenId,
    required this.tieneFirmaAnterior,
    required this.onFirmaGuardada,
    required this.subirFirma,
  });

  @override
  State<_FirmaDialogWidget> createState() => _FirmaDialogWidgetState();
}

class _FirmaDialogWidgetState extends State<_FirmaDialogWidget> {
  bool _isProcessing = false;

  Future<void> _guardarFirma() async {
    print('');
    print('💾 ========================================');
    print('💾 _guardarFirma() INICIADO');
    print('💾 ========================================');
    print('💾 _isProcessing: $_isProcessing');
    
    if (_isProcessing) {
      print('⚠️ Ya se está procesando, ignorando');
      return;
    }

    // Verificar si hay puntos en la firma
    final points = widget.signatureController.points;
    print('💾 Puntos en firma: ${points.length}');
    
    if (points.isEmpty) {
      print('⚠️ Firma vacía - mostrando mensaje');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Por favor, solicite al cliente que firme'),
            backgroundColor: Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    print('✅ Firma tiene puntos, comenzando procesamiento...');
    setState(() {
      _isProcessing = true;
    });

    try {
      // Exportar firma como imagen
      print('🎨 Exportando firma a PNG...');
      final signatureBytes = await widget.signatureController.toPngBytes();
      print('✅ Firma exportada: ${signatureBytes != null ? "${signatureBytes.length} bytes" : "null"}');
      
      if (signatureBytes == null || !mounted) {
        print('❌ Error: signatureBytes es null o widget no está montado');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudo generar la firma. Intenta nuevamente.'),
              backgroundColor: Color(0xFFDC2626),
              behavior: SnackBarBehavior.floating,
            ),
          );
          setState(() {
            _isProcessing = false;
          });
        }
        return;
      }

      // Subir firma a Supabase Storage
      print('☁️ Subiendo firma a Supabase Storage...');
      final firmaUrl = await widget.subirFirma(signatureBytes, widget.ordenId);
      print('✅ Firma subida - URL: $firmaUrl');
      
      if (firmaUrl != null && mounted) {
        final isLocal = firmaUrl.startsWith('local://');
        
        if (isLocal) {
          // 🔒 CRÍTICO: Firma local (offline) - NO intentar actualizar BD directamente
          // Solo actualizar caché local y llamar callback
          print('📴 Firma guardada localmente (offline) - Se sincronizará cuando haya conexión');
          
          // 🔒 CRÍTICO: Actualizar caché local de la orden con la firma local
          try {
            print('📝 Actualizando caché con firma local...');
            final ordenCached = await OrdenCacheService.getCachedOrderById(widget.ordenId);
            print('📝 Orden cargada desde caché: ${ordenCached != null ? "SI" : "NO"}');
            
            if (ordenCached != null) {
              final ordenJson = ordenCached.toJson();
              ordenJson['firma_url'] = firmaUrl;
              final ordenActualizada = Orden.fromJson(ordenJson);
              await OrdenCacheService.updateCachedOrder(ordenActualizada);
              print('💾 ✅ ✅ ✅ Orden actualizada en caché local con firma: ${firmaUrl}');
              print('💾 Verificación: firma_url en orden actualizada = ${ordenActualizada.firmaUrl}');
            } else {
              print('⚠️ No se encontró orden en caché para actualizar');
            }
          } catch (e) {
            print('❌ Error actualizando caché local con firma: $e');
          }
          
          // Llamar callback para actualizar el estado del padre
          print('📞 Llamando callback onFirmaGuardada con URL: $firmaUrl');
          // 🔒 CRÍTICO: Esperar a que el callback termine ANTES de cerrar el modal
          // Esto asegura que _firmaUrl esté actualizado cuando el flujo continúe
          await widget.onFirmaGuardada(firmaUrl);
          print('✅ Callback onFirmaGuardada ejecutado y completado');
          
          // 🔒 CRÍTICO: Esperar un pequeño delay para asegurar que setState se complete
          await Future.delayed(const Duration(milliseconds: 100));
          print('✅ Delay completado - estado padre debe estar actualizado');
          
          if (mounted) {
            print('✅ Mostrando SnackBar y cerrando modal');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('✅ Firma guardada (modo offline) - Puedes continuar con la entrega'),
                backgroundColor: Color(0xFF4CAF50),
              ),
            );

            print('✅ Cerrando modal con resultado: true');
            Navigator.of(context).pop(true);
          }
        } else {
          // Firma subida exitosamente (online) - Actualizar BD
          print('🌐 Firma subida exitosamente (online) - Actualizando BD...');
          try {
            await supabase
                .from('ordenes')
                .update({
                  'firma_url': firmaUrl,
                })
                .eq('id', widget.ordenId);
            print('✅ BD actualizada con firma exitosamente');

            // Llamar callback para actualizar el estado del padre
            print('📞 Llamando callback onFirmaGuardada con URL (online): $firmaUrl');
            // 🔒 CRÍTICO: Esperar a que el callback termine ANTES de cerrar el modal
            await widget.onFirmaGuardada(firmaUrl);
            print('✅ Callback onFirmaGuardada ejecutado y completado (online)');

            if (mounted) {
              print('✅ Mostrando SnackBar y cerrando modal (online)');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Firma guardada exitosamente'),
                  backgroundColor: Color(0xFF4CAF50),
                ),
              );

              print('✅ Cerrando modal con resultado: true (online)');
              Navigator.of(context).pop(true);
            }
          } catch (e) {
            print('❌ Error actualizando BD con firma: $e');
            // Aún así, llamar callback para actualizar estado local
            print('📞 Llamando callback onFirmaGuardada (error BD): $firmaUrl');
            // 🔒 CRÍTICO: Esperar a que el callback termine ANTES de cerrar el modal
            await widget.onFirmaGuardada(firmaUrl);
            print('✅ Callback ejecutado y completado a pesar del error');
            
            if (mounted) {
              print('✅ Mostrando SnackBar y cerrando modal (error BD)');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Firma guardada (se sincronizará cuando haya conexión)'),
                  backgroundColor: Color(0xFF4CAF50),
                ),
              );

              print('✅ Cerrando modal con resultado: true (error BD)');
              Navigator.of(context).pop(true);
            }
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error al guardar la firma'),
              backgroundColor: Color(0xFFDC2626),
            ),
          );
          setState(() {
            _isProcessing = false;
          });
        }
      }
    } catch (e) {
      print('❌ Error al guardar firma: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE0E0E0), width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF9C27B0).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.edit,
                      color: Color(0xFF9C27B0),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Firma del Cliente',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C2C2C),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Por favor, solicite al cliente que firme en el área de abajo:',
                    style: TextStyle(
                      fontSize: 14,
                      color: Color(0xFF666666),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE0E0E0), width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Signature(
                          controller: widget.signatureController,
                          height: 200,
                          width: double.infinity,
                          backgroundColor: const Color(0xFFF5F5F5),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _isProcessing ? null : () {
                          widget.signatureController.clear();
                        },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Limpiar'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF666666),
                          side: const BorderSide(color: Color(0xFFE0E0E0), width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      if (widget.tieneFirmaAnterior)
                        OutlinedButton.icon(
                          onPressed: _isProcessing ? null : () {
                            Navigator.of(context).pop(false);
                          },
                          icon: const Icon(Icons.history, size: 18),
                          label: const Text('Usar Anterior'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF1976D2),
                            side: const BorderSide(color: Color(0xFF1976D2), width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // Actions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: Color(0xFFE0E0E0), width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isProcessing ? null : () => Navigator.of(context).pop(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF666666),
                        side: const BorderSide(color: Color(0xFFE0E0E0), width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
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
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isProcessing ? null : _guardarFirma,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF9C27B0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isProcessing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Guardar Firma',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
