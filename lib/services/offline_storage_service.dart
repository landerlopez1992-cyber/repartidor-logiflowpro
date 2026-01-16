import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

/// Servicio de almacenamiento local para datos offline
/// Guarda órdenes, fotos y firmas localmente cuando no hay internet
class OfflineStorageService {
  static final OfflineStorageService _instance = OfflineStorageService._internal();
  factory OfflineStorageService() => _instance;
  OfflineStorageService._internal();

  Database? _database;

  /// Inicializar base de datos local
  Future<void> initialize() async {
    // SQLite no funciona en web, solo en móviles
    if (kIsWeb) {
      print('⚠️ Modo web detectado - SQLite no disponible');
      return;
    }
    
    if (_database != null) return;

    print('💾 Inicializando base de datos local...');
    
    try {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final path = join(documentsDirectory.path, 'offline_data.db');

      _database = await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
        // Tabla para operaciones pendientes
        await db.execute('''
          CREATE TABLE pending_operations (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            orden_id TEXT NOT NULL,
            data TEXT NOT NULL,
            timestamp TEXT NOT NULL,
            retries INTEGER DEFAULT 0
          )
        ''');

        // Tabla para órdenes en caché (para trabajar offline)
        await db.execute('''
          CREATE TABLE cached_orders (
            id TEXT PRIMARY KEY,
            data TEXT NOT NULL,
            last_updated TEXT NOT NULL
          )
        ''');

        // Tabla para fotos pendientes de subir
        await db.execute('''
          CREATE TABLE pending_photos (
            id TEXT PRIMARY KEY,
            orden_id TEXT NOT NULL,
            file_path TEXT NOT NULL,
            timestamp TEXT NOT NULL
          )
        ''');

        // Tabla para firmas pendientes de subir
        await db.execute('''
          CREATE TABLE pending_signatures (
            id TEXT PRIMARY KEY,
            orden_id TEXT NOT NULL,
            file_path TEXT NOT NULL,
            timestamp TEXT NOT NULL
          )
        ''');

        print('✅ Tablas de base de datos local creadas');
      },
    );

      print('✅ Base de datos local inicializada');
    } catch (e) {
      print('❌ Error inicializando base de datos local: $e');
      // Continuar sin base de datos local si falla
    }
  }

  /// Guardar operación pendiente
  Future<void> savePendingOperation({
    required String type,
    required String ordenId,
    required Map<String, dynamic> data,
  }) async {
    if (kIsWeb || _database == null) return;
    await initialize();

    final operation = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'type': type,
      'orden_id': ordenId,
      'data': jsonEncode(data),
      'timestamp': DateTime.now().toIso8601String(),
      'retries': 0,
    };

    await _database!.insert(
      'pending_operations',
      operation,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    print('💾 Operación guardada localmente: $type para orden $ordenId');
  }

  /// Obtener todas las operaciones pendientes
  Future<List<Map<String, dynamic>>> getPendingOperations() async {
    if (kIsWeb || _database == null) return [];
    await initialize();

    final operations = await _database!.query(
      'pending_operations',
      orderBy: 'timestamp ASC',
    );

    return operations.map((op) {
      return {
        'id': op['id'],
        'type': op['type'],
        'orden_id': op['orden_id'],
        'data': jsonDecode(op['data'] as String),
        'timestamp': op['timestamp'],
        'retries': op['retries'],
      };
    }).toList();
  }

  /// Eliminar operación pendiente
  Future<void> deletePendingOperation(String operationId) async {
    await initialize();

    await _database!.delete(
      'pending_operations',
      where: 'id = ?',
      whereArgs: [operationId],
    );

    print('🗑️ Operación eliminada: $operationId');
  }

  /// Incrementar contador de reintentos
  Future<void> incrementRetries(String operationId) async {
    await initialize();

    await _database!.rawUpdate(
      'UPDATE pending_operations SET retries = retries + 1 WHERE id = ?',
      [operationId],
    );
  }

  /// Guardar orden en caché
  Future<void> cacheOrder(String ordenId, Map<String, dynamic> orderData) async {
    await initialize();

    await _database!.insert(
      'cached_orders',
      {
        'id': ordenId,
        'data': jsonEncode(orderData),
        'last_updated': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    print('💾 Orden guardada en caché: $ordenId');
  }

  /// Obtener orden desde caché
  Future<Map<String, dynamic>?> getCachedOrder(String ordenId) async {
    await initialize();

    final results = await _database!.query(
      'cached_orders',
      where: 'id = ?',
      whereArgs: [ordenId],
    );

    if (results.isNotEmpty) {
      return jsonDecode(results.first['data'] as String);
    }

    return null;
  }

  /// Guardar foto pendiente
  Future<void> savePendingPhoto({
    required String ordenId,
    required String filePath,
  }) async {
    await initialize();

    // 🔒 OFFLINE-FIRST: Solo 1 foto pendiente por orden (evita duplicados)
    await _database!.delete(
      'pending_photos',
      where: 'orden_id = ?',
      whereArgs: [ordenId],
    );

    await _database!.insert(
      'pending_photos',
      {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'orden_id': ordenId,
        'file_path': filePath,
        'timestamp': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    print('💾 Foto guardada localmente: $filePath');
  }

  /// Obtener fotos pendientes
  Future<List<Map<String, dynamic>>> getPendingPhotos() async {
    await initialize();

    return await _database!.query('pending_photos', orderBy: 'timestamp ASC');
  }

  /// Eliminar foto pendiente
  Future<void> deletePendingPhoto(String photoId) async {
    await initialize();

    await _database!.delete(
      'pending_photos',
      where: 'id = ?',
      whereArgs: [photoId],
    );
  }

  /// Guardar firma pendiente
  Future<void> savePendingSignature({
    required String ordenId,
    required String filePath,
  }) async {
    await initialize();

    // 🔒 OFFLINE-FIRST: Solo 1 firma pendiente por orden (evita duplicados)
    await _database!.delete(
      'pending_signatures',
      where: 'orden_id = ?',
      whereArgs: [ordenId],
    );

    await _database!.insert(
      'pending_signatures',
      {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'orden_id': ordenId,
        'file_path': filePath,
        'timestamp': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    print('💾 Firma guardada localmente: $filePath');
  }

  /// Obtener firmas pendientes
  Future<List<Map<String, dynamic>>> getPendingSignatures() async {
    await initialize();

    return await _database!.query('pending_signatures', orderBy: 'timestamp ASC');
  }

  /// Eliminar firma pendiente
  Future<void> deletePendingSignature(String signatureId) async {
    await initialize();

    await _database!.delete(
      'pending_signatures',
      where: 'id = ?',
      whereArgs: [signatureId],
    );
  }

  /// Limpiar todas las tablas (usar con precaución)
  Future<void> clearAll() async {
    await initialize();

    await _database!.delete('pending_operations');
    await _database!.delete('cached_orders');
    await _database!.delete('pending_photos');
    await _database!.delete('pending_signatures');

    print('🗑️ Todas las tablas locales limpiadas');
  }

  /// Cerrar base de datos
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }
}

