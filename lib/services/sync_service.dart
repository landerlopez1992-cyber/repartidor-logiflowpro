import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import 'goodbarber_sync_service.dart';
import 'offline_storage_service.dart';
import 'ubicacion_offline_service.dart';
import 'repartidor_pantallas_offline_service.dart';
// (imports limpiados por lints)

/// Servicio de sincronización offline/online
/// Maneja operaciones cuando no hay internet y las sincroniza cuando regresa la conexión
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOnline = true;
  bool _isSyncing = false;
  
  // Callbacks para notificar cambios de conectividad
  final List<Function(bool)> _connectivityListeners = [];
  
  // Cola de operaciones pendientes
  final List<Map<String, dynamic>> _pendingOperations = [];
  
  // Timer para reintentos automáticos de sincronización
  Timer? _retryTimer;
  int _retryAttempts = 0;

  /// Inicializar servicio de sincronización
  Future<void> initialize() async {
    print('🔄 Inicializando SyncService...');
    
    // Verificar estado inicial de conectividad
    await _checkConnectivity();
    
    // Cargar operaciones pendientes desde almacenamiento local
    await _loadPendingOperations();
    
    // Escuchar cambios en la conectividad
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((results) {
      _onConnectivityChanged(results);
    });
    
    print('✅ SyncService inicializado');
  }

  /// Verificar estado actual de conectividad
  Future<void> _checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _updateConnectivityStatus(results);
    } catch (e) {
      print('❌ Error verificando conectividad: $e');
      _isOnline = false;
    }
  }

  /// Cuando cambia la conectividad
  void _onConnectivityChanged(List<ConnectivityResult> results) async {
    print('');
    print('📡 ========================================');
    print('📡 CAMBIO EN CONECTIVIDAD DETECTADO');
    print('📡 ========================================');
    print('📡 Resultados: $results');
    
    _updateConnectivityStatus(results);
    
    print('📡 Estado online: $_isOnline');
    print('📡 Operaciones pendientes: ${_pendingOperations.length}');
    print('📡 Sincronización en progreso: $_isSyncing');
    
    if (_isOnline && !_isSyncing) {
      print('🔄 Conexión restaurada - Verificando conexión a Supabase...');
      if (_pendingOperations.isNotEmpty) {
        print('📊 Operaciones pendientes a sincronizar:');
        for (var i = 0; i < _pendingOperations.length; i++) {
          final op = _pendingOperations[i];
          print(
            '   ${i + 1}. Tipo: ${op['type']}, Orden: ${op['orden_id']}, Reintentos: ${op['retries'] ?? 0}',
          );
        }
      }

      _cancelRetryTimer();
      _retryAttempts = 0;

      print('⏱️ Esperando 2 segundos para que la conexión se estabilice...');
      await Future.delayed(const Duration(seconds: 2));

      final hasRealConnection = await _verifySupabaseConnection();

      if (hasRealConnection) {
        print('✅ Conexión a Supabase verificada - Sincronizando colas...');
        await RepartidorPantallasOfflineService.sincronizarMensajesSoporte();
        if (_pendingOperations.isNotEmpty) {
          await syncPendingOperations();
        }
      } else {
        print('⚠️ No hay conexión real a Supabase - Iniciando reintentos automáticos...');
        _startRetryTimer();
      }
    } else {
      if (!_isOnline) {
        print('📴 Sin conexión - No se puede sincronizar');
        _cancelRetryTimer();
      } else if (_isSyncing) {
        print('⚠️ Ya hay una sincronización en progreso');
      }
    }
    print('📡 ========================================');
    print('');
  }

  /// Verificar si hay conexión REAL a Supabase (no solo wifi/mobile)
  Future<bool> _verifySupabaseConnection() async {
    try {
      print('🔍 Intentando conectar a Supabase...');
      
      // Intentar hacer una consulta simple a Supabase con timeout corto
      final response = await supabase
          .from('ordenes')
          .select('id')
          .limit(1)
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              print('⏱️ Timeout verificando conexión a Supabase');
              throw TimeoutException('Timeout verificando conexión');
            },
          );
      
      print('✅ Conexión a Supabase verificada exitosamente');
      print('📊 Respuesta: ${response.toString().substring(0, response.toString().length > 100 ? 100 : response.toString().length)}...');
      
      return true;
    } catch (e) {
      print('❌ Error verificando conexión a Supabase:');
      print('   Tipo de error: ${e.runtimeType}');
      print('   Mensaje: $e');
      return false;
    }
  }

  /// Actualizar estado de conectividad
  void _updateConnectivityStatus(List<ConnectivityResult> results) {
    final wasOnline = _isOnline;
    
    // Verificar si hay conexión real (no solo wifi/mobile, sino internet real)
    _isOnline = results.isNotEmpty && 
                !results.contains(ConnectivityResult.none);
    
    if (_isOnline != wasOnline) {
      print(_isOnline ? '✅ Conectado a internet (wifi/mobile)' : '❌ Sin conexión a internet');
      
      // Notificar a los listeners
      for (var listener in _connectivityListeners) {
        listener(_isOnline);
      }
    }
  }

  /// Agregar listener para cambios de conectividad
  void addConnectivityListener(Function(bool) listener) {
    _connectivityListeners.add(listener);
  }

  /// Remover listener
  void removeConnectivityListener(Function(bool) listener) {
    _connectivityListeners.remove(listener);
  }

  /// Verificar si hay conexión a internet
  bool get isOnline => _isOnline;

  /// Verificar si hay operaciones pendientes
  bool get hasPendingOperations => _pendingOperations.isNotEmpty;

  /// Cantidad de operaciones pendientes
  int get pendingOperationsCount => _pendingOperations.length;

  /// Copia de la cola (p. ej. saldo pendiente offline sin doble conteo tras sync).
  List<Map<String, dynamic>> get pendingOperationsSnapshot =>
      List<Map<String, dynamic>>.from(_pendingOperations);

  final List<void Function()> _syncCompleteListeners = [];

  void addSyncCompleteListener(void Function() listener) {
    if (!_syncCompleteListeners.contains(listener)) {
      _syncCompleteListeners.add(listener);
    }
  }

  void removeSyncCompleteListener(void Function() listener) {
    _syncCompleteListeners.remove(listener);
  }

  void _notifySyncComplete() {
    for (final listener in List<void Function()>.from(_syncCompleteListeners)) {
      try {
        listener();
      } catch (e) {
        print('⚠️ syncCompleteListener: $e');
      }
    }
  }

  /// Agregar operación a la cola de sincronización
  Future<void> addOperation({
    required String type, // 'update_orden', 'upload_photo', 'upload_firma', etc.
    required String ordenId,
    required Map<String, dynamic> data,
  }) async {
    print('');
    print('📝 ========================================');
    print('📝 AGREGANDO OPERACIÓN A LA COLA');
    print('📝 ========================================');
    print('📝 Tipo: $type');
    print('📝 Orden ID: $ordenId');
    print('📝 Datos: $data');
    
    // 🔒 OFFLINE-FIRST: Deduplicar por (type + orden_id).
    // Si ya existe una operación del mismo tipo para la misma orden, la reemplazamos
    // (mantiene la cola limpia y evita duplicados de firma/foto/estado).
    final existingIndex = _pendingOperations.indexWhere(
      (op) => op['type'] == type && op['orden_id'] == ordenId,
    );

    if (existingIndex != -1) {
      final existing = _pendingOperations[existingIndex];
      _pendingOperations[existingIndex] = {
        ...existing,
        'data': data,
        'timestamp': DateTime.now().toIso8601String(),
        // reset de retries porque es una intención nueva/actualizada del usuario
        'retries': 0,
      };
      print('♻️ Operación existente actualizada (dedupe): $type - Orden: $ordenId');
    } else {
      final operation = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'type': type,
        'orden_id': ordenId,
        'data': data,
        'timestamp': DateTime.now().toIso8601String(),
        'retries': 0,
      };
      _pendingOperations.add(operation);
    }
    await _savePendingOperations();
    
    print('✅ Operación agregada a la cola exitosamente');
    print('📊 Total de operaciones pendientes: ${_pendingOperations.length}');
    print('📊 Estado de conexión: ${_isOnline ? "Online" : "Offline"}');
    print('📊 Sincronización en progreso: $_isSyncing');
    
    // Notificar a los listeners sobre cambio en operaciones pendientes
    for (var listener in _connectivityListeners) {
      listener(_isOnline);
    }
    
    // Si hay conexión, verificar conexión real e intentar sincronizar inmediatamente
    if (_isOnline && !_isSyncing) {
      print('🔄 Hay conexión wifi/mobile - Verificando conexión a Supabase antes de sincronizar...');
      
      // Verificar conexión real a Supabase
      final hasRealConnection = await _verifySupabaseConnection();
      
      if (hasRealConnection) {
        print('✅ Conexión verificada - Sincronizando inmediatamente...');
        _retryAttempts = 0; // Resetear contador de reintentos
        _cancelRetryTimer(); // Cancelar timer de reintentos si existe
        syncPendingOperations();
      } else {
        print('⚠️ No hay conexión real a Supabase - La operación quedará pendiente');
        print('⚠️ Iniciando reintentos automáticos...');
        _startRetryTimer(); // Iniciar timer de reintentos
      }
    } else if (!_isOnline) {
      print('📴 Sin conexión wifi/mobile - La operación quedará pendiente');
      print('📴 Se sincronizará automáticamente cuando regrese la conexión');
      _cancelRetryTimer(); // Cancelar reintentos si no hay wifi/mobile
    } else if (_isSyncing) {
      print('⚠️ Ya hay una sincronización en progreso');
      print('⚠️ La operación se sincronizará en el próximo ciclo');
    }
    print('📝 ========================================');
    print('');
  }

  /// Indica si hay una operación pendiente de un tipo para una orden.
  bool hasPendingOperation(String type, String ordenId) {
    return _pendingOperations.any(
      (op) => op['type'] == type && op['orden_id']?.toString() == ordenId,
    );
  }

  /// Elimina operaciones en cola de un tipo y orden (p. ej. quitar foto antes de entregar).
  Future<void> removePendingOperationsForOrden({
    required String type,
    required String ordenId,
  }) async {
    final antes = _pendingOperations.length;
    _pendingOperations.removeWhere(
      (op) => op['type'] == type && op['orden_id'] == ordenId,
    );
    if (_pendingOperations.length != antes) {
      await _savePendingOperations();
      print('🗑️ Cola sync: eliminadas operaciones $type para orden $ordenId');
    }
  }
  
  /// Iniciar timer de reintentos para sincronización
  void _startRetryTimer() {
    _cancelRetryTimer(); // Cancelar timer existente
    
    if (_pendingOperations.isEmpty) {
      print('📊 No hay operaciones pendientes - No se inicia timer de reintentos');
      return;
    }
    
    // Calcular intervalo de reintento (exponencial backoff)
    // 5s, 10s, 20s, 30s, 60s, después cada 60s
    int intervalSeconds;
    if (_retryAttempts == 0) {
      intervalSeconds = 5;
    } else if (_retryAttempts == 1) {
      intervalSeconds = 10;
    } else if (_retryAttempts == 2) {
      intervalSeconds = 20;
    } else if (_retryAttempts == 3) {
      intervalSeconds = 30;
    } else {
      intervalSeconds = 60;
    }
    
    print('⏱️ Timer de reintentos iniciado: intento ${_retryAttempts + 1}, próximo reintento en ${intervalSeconds}s');
    
    _retryTimer = Timer(Duration(seconds: intervalSeconds), () async {
      _retryAttempts++;
      print('');
      print('🔄 ========================================');
      print('🔄 REINTENTO AUTOMÁTICO DE SINCRONIZACIÓN');
      print('🔄 ========================================');
      print('🔄 Intento: $_retryAttempts');
      print('🔄 Operaciones pendientes: ${_pendingOperations.length}');
      
      if (_isOnline && _pendingOperations.isNotEmpty && !_isSyncing) {
        print('🔍 Verificando conexión a Supabase...');
        final hasConnection = await _verifySupabaseConnection();
        
        if (hasConnection) {
          print('✅ Conexión restaurada - Sincronizando...');
          _retryAttempts = 0; // Resetear contador
          await syncPendingOperations();
        } else {
          print('⚠️ Aún sin conexión a Supabase - Reintentando más tarde...');
          _startRetryTimer(); // Programar siguiente reintento
        }
      } else {
        if (!_isOnline) {
          print('📴 Sin conexión wifi/mobile - Cancelando reintentos');
          _cancelRetryTimer();
        } else if (_pendingOperations.isEmpty) {
          print('✅ No hay operaciones pendientes - Cancelando reintentos');
          _cancelRetryTimer();
        }
      }
      print('🔄 ========================================');
      print('');
    });
  }
  
  /// Cancelar timer de reintentos
  void _cancelRetryTimer() {
    if (_retryTimer != null && _retryTimer!.isActive) {
      print('🛑 Cancelando timer de reintentos');
      _retryTimer?.cancel();
      _retryTimer = null;
    }
  }

  /// Sincronizar fotos y firmas pendientes desde archivos locales
  Future<void> syncPendingPhotosAndSignatures() async {
    if (!_isOnline) return;
    
    try {
      final offlineStorage = OfflineStorageService();
      
      // Sincronizar fotos pendientes
      final pendingPhotos = await offlineStorage.getPendingPhotos();
      print('📸 Sincronizando ${pendingPhotos.length} fotos pendientes...');
      
      for (var photo in pendingPhotos) {
        try {
          final ordenId = photo['orden_id'] as String;
          final filePath = photo['file_path'] as String;
          final photoId = photo['id'].toString();
          
          final file = File(filePath);
          if (await file.exists()) {
            final photoBytes = await file.readAsBytes();
            final photoBase64 = base64Encode(photoBytes);
            
            await addOperation(
              type: 'upload_photo',
              ordenId: ordenId,
              data: {
                'file_path': filePath,
                'photo_base64': photoBase64,
              },
            );
            
            // 🔒 CRÍTICO: Eliminar la foto de pending_photos INMEDIATAMENTE después de agregarla a la cola
            // para evitar duplicados en futuras sincronizaciones
            await offlineStorage.deletePendingPhoto(photoId);
            print('🗑️ Foto eliminada de pending_photos (ya está en la cola): $photoId');
          } else {
            print('⚠️ Foto local no encontrada: $filePath');
            // Eliminar de la lista si el archivo no existe
            await offlineStorage.deletePendingPhoto(photoId);
          }
        } catch (e) {
          print('❌ Error sincronizando foto ${photo['id']}: $e');
        }
      }
      
      // Sincronizar firmas pendientes
      final pendingSignatures = await offlineStorage.getPendingSignatures();
      print('✍️ Sincronizando ${pendingSignatures.length} firmas pendientes...');
      
      for (var signature in pendingSignatures) {
        try {
          final ordenId = signature['orden_id'] as String;
          final filePath = signature['file_path'] as String;
          final signatureId = signature['id'].toString();
          
          final file = File(filePath);
          if (await file.exists()) {
            final firmaBytes = await file.readAsBytes();
            final firmaBase64 = base64Encode(firmaBytes);
            
            await addOperation(
              type: 'upload_firma',
              ordenId: ordenId,
              data: {
                'file_path': filePath,
                'firma_base64': firmaBase64,
              },
            );
            
            // 🔒 CRÍTICO: Eliminar la firma de pending_signatures INMEDIATAMENTE después de agregarla a la cola
            // para evitar duplicados en futuras sincronizaciones
            await offlineStorage.deletePendingSignature(signatureId);
            print('🗑️ Firma eliminada de pending_signatures (ya está en la cola): $signatureId');
          } else {
            print('⚠️ Firma local no encontrada: $filePath');
            // Eliminar de la lista si el archivo no existe
            await offlineStorage.deletePendingSignature(signatureId);
          }
        } catch (e) {
          print('❌ Error sincronizando firma ${signature['id']}: $e');
        }
      }
    } catch (e) {
      print('❌ Error sincronizando fotos/firmas pendientes: $e');
    }
  }

  /// Sincronizar todas las operaciones pendientes
  Future<bool> syncPendingOperations() async {
    if (_isSyncing) {
      print('⚠️ Ya hay una sincronización en progreso');
      return false;
    }
    
    if (!_isOnline) {
      print('❌ Sin conexión wifi/mobile - No se puede sincronizar');
      return false;
    }
    
    // 🔒 CRÍTICO: Verificar conexión REAL a Supabase antes de sincronizar
    print('🔍 Verificando conexión real a Supabase antes de sincronizar...');
    final hasRealConnection = await _verifySupabaseConnection();
    
    if (!hasRealConnection) {
      print('❌ No hay conexión real a Supabase - Sincronización cancelada');
      print('📊 Operaciones pendientes: ${_pendingOperations.length} (esperando conexión)');
      return false;
    }
    
    print('✅ Conexión a Supabase verificada - Procediendo con sincronización');
    
    // GPS pendiente y luego fotos/firmas antes de estados de orden
    await UbicacionOfflineService.sincronizarPendientes();
    await RepartidorPantallasOfflineService.sincronizarMensajesSoporte();
    await syncPendingPhotosAndSignatures();
    
    if (_pendingOperations.isEmpty) {
      print('✅ No hay operaciones pendientes');
      // Notificar a listeners que se completó la sincronización
      for (var listener in _connectivityListeners) {
        listener(_isOnline);
      }
      return true;
    }
    
    _isSyncing = true;
    print('');
    print('🔄 ========================================');
    print('🔄 INICIANDO SINCRONIZACIÓN');
    print('🔄 ========================================');
    print('🔄 Operaciones pendientes: ${_pendingOperations.length}');
    
    final operationsToSync = List<Map<String, dynamic>>.from(_pendingOperations);
    operationsToSync.sort((a, b) {
      int prio(String t) {
        switch (t) {
          case 'upload_photo':
            return 0;
          case 'delete_foto_entrega':
            return 1;
          case 'upload_firma':
            return 2;
          case 'update_orden_estado':
            return 3;
          case 'mark_delivered':
            return 4;
          default:
            return 5;
        }
      }
      return prio(a['type']?.toString() ?? '').compareTo(prio(b['type']?.toString() ?? ''));
    });
    final successfulOperations = <String>[];
    final failedOperations = <Map<String, dynamic>>[];
    
    for (var operation in operationsToSync) {
      // 🔒 Verificar conexión antes de cada operación
      if (!_isOnline) {
        print('📴 Sin conexión - Deteniendo sincronización');
        break; // Salir del loop si se perdió la conexión
      }
      
      try {
        print('🔄 Sincronizando: ${operation['type']} para orden ${operation['orden_id']} (intento ${(operation['retries'] ?? 0) + 1}/3)');
        
        final success = await _executeOperation(operation);
        
        if (success) {
          successfulOperations.add(operation['id']);
          print('✅ Operación sincronizada exitosamente');
        } else {
          // Incrementar contador de reintentos
          operation['retries'] = (operation['retries'] ?? 0) + 1;
          
          // Mantener en cola: nunca descartar cambios de reparto (se reintenta al reconectar)
          failedOperations.add(operation);
          if (operation['retries'] >= 3) {
            print(
              '❌ Operación sigue en cola tras ${operation['retries']} intentos: '
              '${operation['type']} orden ${operation['orden_id']}',
            );
          } else {
            print('⚠️ Operación falló - Se reintentará (${operation['retries']}/3)');
          }
        }
      } catch (e) {
        print('❌ Error sincronizando operación ${operation['type']}: $e');
        
        operation['retries'] = (operation['retries'] ?? 0) + 1;
        
        failedOperations.add(operation);
        print(
          operation['retries'] >= 3
              ? '❌ Operación permanece en cola tras ${operation['retries']} intentos'
              : '⚠️ Se reintentará más tarde (${operation['retries']}/3)',
        );
      }
    }
    
    // Eliminar operaciones exitosas
    _pendingOperations.removeWhere((op) => successfulOperations.contains(op['id']));
    
    // Guardar operaciones fallidas para reintentar después
    await _savePendingOperations();
    
    print('');
    print('🔄 ========================================');
    print('🔄 SINCRONIZACIÓN COMPLETADA');
    print('🔄 ========================================');
    print('✅ Exitosas: ${successfulOperations.length}');
    print('❌ Fallidas: ${failedOperations.length}');
    print('📊 Pendientes restantes: ${_pendingOperations.length}');
    print('');
    
    _isSyncing = false;

    _notifySyncComplete();
    
    // Notificar a listeners que se completó la sincronización
    for (var listener in _connectivityListeners) {
      listener(_isOnline);
    }
    
    // Si aún hay operaciones pendientes, usar sistema de reintentos automáticos
    if (_pendingOperations.isNotEmpty && _isOnline) {
      print('⏱️ Hay operaciones pendientes - Iniciando sistema de reintentos automáticos...');
      _startRetryTimer();
    } else {
      // Si no hay operaciones pendientes, cancelar timer
      _cancelRetryTimer();
      _retryAttempts = 0;
    }
    
    return failedOperations.isEmpty;
  }

  /// Ejecutar una operación específica
  Future<bool> _executeOperation(Map<String, dynamic> operation) async {
    // 🔒 CRÍTICO: NO ejecutar si está offline
    if (!_isOnline) {
      return false; // Silenciosamente retornar false
    }
    
    final type = operation['type'];
    final ordenId = operation['orden_id'];
    final data = operation['data'] as Map<String, dynamic>;
    
    try {
      switch (type) {
        case 'update_orden_estado':
          // Verificar nuevamente conexión antes de continuar
          if (!_isOnline) return false;
          // Actualizar estado de orden en Supabase
          await supabase
              .from('ordenes')
              .update(data)
              .eq('id', ordenId);
          
          await _syncGoodBarberSiAplica(ordenId, data);
          print('✅ Estado sincronizado exitosamente en Supabase para orden $ordenId');
          
          return true;
          
        case 'upload_photo':
          // Subir foto de entrega - Intentar desde archivo local primero
          Uint8List photoBytes;
          
          // Intentar leer desde archivo local si existe
          if (data['file_path'] != null) {
            try {
              final filePath = data['file_path'] as String;
              final file = File(filePath);
              if (await file.exists()) {
                photoBytes = Uint8List.fromList(await file.readAsBytes());
                print('📸 Leyendo foto desde archivo local: $filePath');
              } else {
                // Si no existe el archivo, usar base64
                final photoBase64 = data['photo_base64'] as String? ?? '';
                if (photoBase64.isEmpty) {
                  print('❌ No hay foto disponible (ni archivo ni base64)');
                  return false;
                }
                photoBytes = base64Decode(photoBase64);
              }
            } catch (e) {
              print('⚠️ Error leyendo archivo local, usando base64: $e');
              // Fallback a base64
              final photoBase64 = data['photo_base64'] as String? ?? '';
              if (photoBase64.isEmpty) {
                return false;
              }
              photoBytes = base64Decode(photoBase64);
            }
          } else {
            // Usar base64 directamente
            final photoBase64 = data['photo_base64'] as String? ?? '';
            if (photoBase64.isEmpty) {
              return false;
            }
            photoBytes = base64Decode(photoBase64);
          }
          
          final fileName = 'entrega_${ordenId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
          const String bucketName = 'fotos-perfil';
          
          await supabase.storage
              .from(bucketName)
              .uploadBinary(fileName, photoBytes);
          
          final photoUrl = supabase.storage
              .from(bucketName)
              .getPublicUrl(fileName);
          
          await supabase
              .from('ordenes')
              .update({'foto_entrega': photoUrl})
              .eq('id', ordenId);
          
          // Eliminar foto pendiente del almacenamiento local
          final offlineStorage = OfflineStorageService();
          final pendingPhotos = await offlineStorage.getPendingPhotos();
          for (var photo in pendingPhotos) {
            if (photo['orden_id'] == ordenId) {
              await offlineStorage.deletePendingPhoto(photo['id'].toString());
            }
          }
          
          return true;

        case 'delete_foto_entrega':
          if (!_isOnline) return false;
          await supabase
              .from('ordenes')
              .update({'foto_entrega': null})
              .eq('id', ordenId);
          print('✅ Foto de entrega eliminada en BD para orden $ordenId');
          return true;
          
        case 'upload_firma':
          // Subir firma - Intentar desde archivo local primero
          Uint8List firmaBytes;
          
          // Intentar leer desde archivo local si existe
          if (data['file_path'] != null) {
            try {
              final filePath = data['file_path'] as String;
              final file = File(filePath);
              if (await file.exists()) {
                firmaBytes = Uint8List.fromList(await file.readAsBytes());
                print('✍️ Leyendo firma desde archivo local: $filePath');
              } else {
                // Si no existe el archivo, usar base64
                final firmaBase64 = data['firma_base64'] as String? ?? '';
                if (firmaBase64.isEmpty) {
                  print('❌ No hay firma disponible (ni archivo ni base64)');
                  return false;
                }
                firmaBytes = base64Decode(firmaBase64);
              }
            } catch (e) {
              print('⚠️ Error leyendo archivo local, usando base64: $e');
              // Fallback a base64
              final firmaBase64 = data['firma_base64'] as String? ?? '';
              if (firmaBase64.isEmpty) {
                return false;
              }
              firmaBytes = base64Decode(firmaBase64);
            }
          } else {
            // Usar base64 directamente
            final firmaBase64 = data['firma_base64'] as String? ?? '';
            if (firmaBase64.isEmpty) {
              return false;
            }
            firmaBytes = base64Decode(firmaBase64);
          }
          
          final fileName = 'firma_${ordenId}_${DateTime.now().millisecondsSinceEpoch}.png';
          
          await supabase.storage
              .from('firmas')
              .uploadBinary(fileName, firmaBytes);
          
          final firmaUrl = supabase.storage
              .from('firmas')
              .getPublicUrl(fileName);
          
          await supabase
              .from('ordenes')
              .update({'firma_url': firmaUrl})
              .eq('id', ordenId);
          
          // Eliminar firma pendiente del almacenamiento local
          final offlineStorage = OfflineStorageService();
          final pendingSignatures = await offlineStorage.getPendingSignatures();
          for (var signature in pendingSignatures) {
            if (signature['orden_id'] == ordenId) {
              await offlineStorage.deletePendingSignature(signature['id'].toString());
            }
          }
          
          return true;
          
        case 'mark_delivered':
          // Marcar como entregado - Log detallado
          print('📦 Marcando orden $ordenId como entregada en Supabase...');
          print('📝 Datos a actualizar: $data');
          
          final response = await supabase
              .from('ordenes')
              .update(data)
              .eq('id', ordenId)
              .select();
          
          print('✅ Respuesta de Supabase: $response');
          print('✅ Orden $ordenId marcada como entregada en Supabase exitosamente');
          
          await _syncGoodBarberSiAplica(ordenId, data);
          return true;

        case 'rpc_iniciar_recolecta':
          if (!_isOnline) return false;
          final ordenRpc = data['p_orden_id']?.toString() ?? ordenId;
          final res = await supabase.rpc(
            'repartidor_iniciar_recolecta_colaborador',
            params: {'p_orden_id': ordenRpc},
          );
          final payload = res as Map<String, dynamic>? ?? {};
          return payload['ok'] == true;
          
        default:
          print('⚠️ Tipo de operación desconocido: $type');
          return false;
      }
    } catch (e, stackTrace) {
      // 🔍 SIEMPRE imprimir errores para diagnóstico
      print('❌ ========================================');
      print('❌ ERROR EJECUTANDO OPERACIÓN');
      print('❌ ========================================');
      print('❌ Tipo: $type');
      print('❌ Orden ID: $ordenId');
      print('❌ Datos: $data');
      print('❌ Error: $e');
      print('❌ Stack trace: ${stackTrace.toString().split('\n').take(5).join('\n')}');
      print('❌ ========================================');
      
      // Retornar false para reintentar
      return false;
    }
  }

  Future<void> _syncGoodBarberSiAplica(String ordenId, Map<String, dynamic> data) async {
    final est = data['estado']?.toString().trim();
    if (est == null || est.isEmpty) return;
    try {
      await GoodBarberSyncService.sincronizarEstadoAGoodBarber(
        supabase,
        ordenId,
        est,
      );
    } catch (e) {
      print('⚠️ GoodBarber tras sync cola: $e');
    }
  }

  /// Guardar operaciones pendientes en almacenamiento local
  Future<void> _savePendingOperations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final operationsJson = jsonEncode(_pendingOperations);
      await prefs.setString('pending_sync_operations', operationsJson);
      
      print('💾 ========================================');
      print('💾 OPERACIONES GUARDADAS EN STORAGE');
      print('💾 ========================================');
      print('💾 Total: ${_pendingOperations.length}');
      
      if (_pendingOperations.isNotEmpty) {
        print('💾 Detalles:');
        for (var i = 0; i < _pendingOperations.length; i++) {
          final op = _pendingOperations[i];
          print('   ${i + 1}. ${op['type']} - Orden: ${op['orden_id']} - Reintentos: ${op['retries'] ?? 0}');
        }
      }
      
      print('💾 ========================================');
    } catch (e) {
      print('❌ Error guardando operaciones pendientes: $e');
    }
  }

  /// Cargar operaciones pendientes desde almacenamiento local
  Future<void> _loadPendingOperations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final operationsJson = prefs.getString('pending_sync_operations');
      
      if (operationsJson != null && operationsJson.isNotEmpty) {
        final operationsList = jsonDecode(operationsJson) as List;
        _pendingOperations.clear();
        _pendingOperations.addAll(
          operationsList.map((op) => Map<String, dynamic>.from(op)).toList()
        );
        
        print('📥 ========================================');
        print('📥 OPERACIONES CARGADAS DESDE STORAGE');
        print('📥 ========================================');
        print('📥 Total: ${_pendingOperations.length}');
        
        if (_pendingOperations.isNotEmpty) {
          print('📥 Detalles:');
          for (var i = 0; i < _pendingOperations.length; i++) {
            final op = _pendingOperations[i];
            print('   ${i + 1}. ${op['type']} - Orden: ${op['orden_id']} - Reintentos: ${op['retries'] ?? 0}');
          }
        }
        
        print('📥 Estado de conexión: ${_isOnline ? "Online" : "Offline"}');
        print('📥 ========================================');
        
        // Si hay conexión, intentar sincronizar
        if (_isOnline) {
          print('🔄 Hay conexión - Intentando sincronizar operaciones cargadas...');
          syncPendingOperations();
        } else {
          print('📴 Sin conexión - Las operaciones se sincronizarán cuando regrese la conexión');
        }
      } else {
        print('📥 No hay operaciones pendientes en storage');
      }
    } catch (e) {
      print('❌ Error cargando operaciones pendientes: $e');
    }
  }

  /// Limpiar todas las operaciones pendientes (usar con precaución)
  Future<void> clearPendingOperations() async {
    _pendingOperations.clear();
    await _savePendingOperations();
    print('🗑️ Operaciones pendientes eliminadas');
  }

  /// Dispose
  void dispose() {
    _connectivitySubscription?.cancel();
    _cancelRetryTimer();
  }
}

