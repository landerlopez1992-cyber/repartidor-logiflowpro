import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/orden.dart';
import 'offline_storage_service.dart';

/// Servicio para cachear órdenes localmente
/// Permite trabajar offline y sincronizar cuando hay conexión
class OrdenCacheService {
  static const String _cacheKey = 'cached_orders';
  static const String _lastSyncKey = 'last_sync_timestamp';

  static bool _urlTieneFoto(String? url) =>
      url != null && url.trim().isNotEmpty;

  /// Guardar órdenes en caché local
  /// ✅ FIX CRÍTICO: Asegurar que TODOS los datos se guarden correctamente
  /// 🔒 OFFLINE-FIRST: NO sobrescribir órdenes con cambios de estado locales hasta que se sincronicen
  /// 🔒 OFFLINE-FIRST: Preservar foto/firma locales con subida pendiente
  /// RETORNA: La lista fusionada de órdenes (con cambios locales preservados si aplica)
  /// Evita vaciar la lista en pantalla cuando la red falla o el servidor devuelve 0 filas.
  static List<Orden> resolveOrdersForDisplay({
    required List<Orden> fused,
    required List<Orden> cached,
    required List<Orden> onScreen,
    int serverCount = -1,
  }) {
    if (fused.isNotEmpty) return fused;
    if (onScreen.isNotEmpty) {
      print('🔒 Pantalla: respuesta vacía — se mantienen ${onScreen.length} órdenes en UI');
      return onScreen;
    }
    if (cached.isNotEmpty) {
      print('🔒 Pantalla: respuesta vacía — se usan ${cached.length} órdenes del caché');
      return cached;
    }
    if (serverCount == 0) {
      print('🔒 Servidor y caché vacíos — lista vacía');
    }
    return fused;
  }

  static Future<List<Orden>> cacheOrders(List<Orden> ordenes, {bool preserveLocalChanges = true}) async {
    try {
      final ordenesServidor = List<Orden>.from(ordenes);

      // 🔒 OFFLINE-FIRST: Si preserveLocalChanges es true, fusionar con caché existente
      if (preserveLocalChanges) {
        final ordenesCached = await getCachedOrders();

        // Nunca persistir una respuesta vacía sobre un caché con órdenes (fallo de red / timeout parcial)
        if (ordenesServidor.isEmpty && ordenesCached.isNotEmpty) {
          print(
            '🔒 cacheOrders: servidor devolvió 0 órdenes — se preserva caché (${ordenesCached.length})',
          );
          return ordenesCached;
        }
        final ordenesCachedMap = {for (final orden in ordenesCached) orden.id: orden};
        
        // Obtener operaciones pendientes de sincronización para verificar qué órdenes tienen cambios locales
        // Leer desde SharedPreferences directamente (mismo lugar donde SyncService las guarda)
        final pendingOps = await _getPendingOperationsFromStorage();
        
        // Crear un mapa de IDs de órdenes con operaciones pendientes de actualización de estado
        final ordenesConCambiosPendientes = <String>{};
        final ordenesConFirmaPendiente = <String>{};
        final ordenesConFotoPendiente = <String>{};
        final ordenesConFotoEliminadaPendiente = <String>{};
        for (var op in pendingOps) {
          if (op['type'] == 'update_orden_estado' || op['type'] == 'mark_delivered') {
            final ordenId = op['orden_id'] as String? ?? op['orden_id']?.toString();
            if (ordenId != null) {
              ordenesConCambiosPendientes.add(ordenId);
            }
          } else if (op['type'] == 'upload_firma') {
            final ordenId = op['orden_id'] as String? ?? op['orden_id']?.toString();
            if (ordenId != null) {
              ordenesConFirmaPendiente.add(ordenId);
            }
          } else if (op['type'] == 'upload_photo') {
            final ordenId = op['orden_id'] as String? ?? op['orden_id']?.toString();
            if (ordenId != null) {
              ordenesConFotoPendiente.add(ordenId);
            }
          } else if (op['type'] == 'delete_foto_entrega') {
            final ordenId = op['orden_id'] as String? ?? op['orden_id']?.toString();
            if (ordenId != null) {
              ordenesConFotoEliminadaPendiente.add(ordenId);
            }
          }
        }
        
        print('🔒 Órdenes con cambios pendientes de sincronización: ${ordenesConCambiosPendientes.length}');
        
        // También revisar firmas/fotos pendientes guardadas en SQLite (offline)
        try {
          final offlineStorage = OfflineStorageService();
          final pendingSignatures = await offlineStorage.getPendingSignatures();
          for (final sig in pendingSignatures) {
            final ordenId = sig['orden_id']?.toString();
            if (ordenId != null && ordenId.isNotEmpty) {
              ordenesConFirmaPendiente.add(ordenId);
            }
          }
          final pendingPhotos = await offlineStorage.getPendingPhotos();
          for (final photo in pendingPhotos) {
            final ordenId = photo['orden_id']?.toString();
            if (ordenId != null && ordenId.isNotEmpty) {
              ordenesConFotoPendiente.add(ordenId);
            }
          }
        } catch (e) {
          print('⚠️ Error leyendo fotos/firmas pendientes: $e');
        }
        
        // Crear un mapa de órdenes modificadas localmente (cualquier cambio de estado)
        final ordenesModificadasLocal = <String, Orden>{};
        for (var orden in ordenesCached) {
          // Si la orden tiene cambios pendientes de sincronización, preservarla
          if (ordenesConCambiosPendientes.contains(orden.id)) {
            ordenesModificadasLocal[orden.id] = orden;
            print('🔒 Preservando orden con cambios locales pendientes: #${orden.numeroOrden} (estado: ${orden.estado})');
          }
        }
        
        // Fusionar: Para cada orden de Supabase
        final ordenesFusionadas = <Orden>[];
        final idsProcesados = <String>{};
        
        for (var ordenSupabase in ordenesServidor) {
          idsProcesados.add(ordenSupabase.id);
          
          // Si esta orden tiene cambios locales pendientes, usar la versión del caché
          if (ordenesModificadasLocal.containsKey(ordenSupabase.id)) {
            final ordenLocal = ordenesModificadasLocal[ordenSupabase.id]!;
            // Verificar si el estado en Supabase es diferente (aún no sincronizado)
            if (ordenSupabase.estado != ordenLocal.estado) {
              print('🔒 Preservando estado local para orden #${ordenLocal.numeroOrden} (BD: ${ordenSupabase.estado}, Local: ${ordenLocal.estado})');
              ordenesFusionadas.add(ordenLocal);
              continue;
            }
          }
          
          // Preservar firma/foto locales si hay subida pendiente
          final ordenLocal = ordenesCachedMap[ordenSupabase.id];
          final tieneFirmaLocal = ordenLocal?.firmaUrl != null &&
              ordenLocal!.firmaUrl!.isNotEmpty &&
              ordenLocal.firmaUrl!.startsWith('local://');
          final tieneFotoLocal = ordenLocal?.fotoEntrega != null &&
              ordenLocal!.fotoEntrega!.isNotEmpty &&
              ordenLocal.fotoEntrega!.startsWith('local://');
          final preservarFirma = tieneFirmaLocal && ordenesConFirmaPendiente.contains(ordenSupabase.id);
          final preservarFoto = tieneFotoLocal && ordenesConFotoPendiente.contains(ordenSupabase.id);
          final quitarFoto = ordenesConFotoEliminadaPendiente.contains(ordenSupabase.id) ||
              (ordenLocal != null &&
                  !_urlTieneFoto(ordenLocal.fotoEntrega) &&
                  _urlTieneFoto(ordenSupabase.fotoEntrega));
          
          if (preservarFirma || preservarFoto || quitarFoto) {
            final ordenJson = ordenSupabase.toJson();
            if (preservarFirma && ordenLocal != null) {
              ordenJson['firma_url'] = ordenLocal.firmaUrl;
            }
            if (preservarFoto && ordenLocal != null) {
              ordenJson['foto_entrega'] = ordenLocal.fotoEntrega;
            }
            if (quitarFoto && !preservarFoto) {
              ordenJson['foto_entrega'] = null;
            }
            final ordenFusionada = Orden.fromJson(ordenJson);
            print('🔒 Preservando firma/foto local para orden #${ordenFusionada.numeroOrden}');
            ordenesFusionadas.add(ordenFusionada);
            continue;
          }
          
          // Si no hay conflicto, usar la orden de Supabase
          ordenesFusionadas.add(ordenSupabase);
        }
        
        // Agregar órdenes modificadas localmente que no están en la respuesta de Supabase
        for (var ordenLocal in ordenesModificadasLocal.values) {
          if (!idsProcesados.contains(ordenLocal.id)) {
            print('🔒 Agregando orden modificada localmente que no está en Supabase: #${ordenLocal.numeroOrden} (estado: ${ordenLocal.estado})');
            ordenesFusionadas.add(ordenLocal);
          }
        }
        
        // Agregar órdenes con firma/foto local pendiente que no están en la respuesta
        for (var ordenLocal in ordenesCached) {
          if (idsProcesados.contains(ordenLocal.id)) continue;
          final tieneFirmaLocal = ordenLocal.firmaUrl != null &&
              ordenLocal.firmaUrl!.isNotEmpty &&
              ordenLocal.firmaUrl!.startsWith('local://');
          final tieneFotoLocal = ordenLocal.fotoEntrega != null &&
              ordenLocal.fotoEntrega!.isNotEmpty &&
              ordenLocal.fotoEntrega!.startsWith('local://');
          final preservarFirma = tieneFirmaLocal && ordenesConFirmaPendiente.contains(ordenLocal.id);
          final preservarFoto = tieneFotoLocal && ordenesConFotoPendiente.contains(ordenLocal.id);
          if (preservarFirma || preservarFoto) {
            print('🔒 Agregando orden con firma/foto local pendiente que no está en Supabase: #${ordenLocal.numeroOrden}');
            ordenesFusionadas.add(ordenLocal);
          }
        }
        
        ordenes = ordenesFusionadas;
      } else if (ordenesServidor.isEmpty) {
        final ordenesCached = await getCachedOrders();
        if (ordenesCached.isNotEmpty) {
          print(
            '🔒 cacheOrders (sin merge): servidor vacío — se preserva caché (${ordenesCached.length})',
          );
          return ordenesCached;
        }
      }

      // No guardar lista vacía si antes había datos (logout usa clearCache)
      if (ordenes.isEmpty) {
        final existente = await getCachedOrders();
        if (existente.isNotEmpty) {
          print('🔒 cacheOrders: no se sobrescribe caché con lista vacía');
          return existente;
        }
      }
      
      final prefs = await SharedPreferences.getInstance();
      
      // Convertir órdenes a JSON (el método toJson() mejorado ya incluye todos los campos)
      final ordenesJson = ordenes.map((orden) => orden.toJson()).toList();
      
      // Codificar a string JSON
      final ordenesString = jsonEncode(ordenesJson);
      
      // Guardar en SharedPreferences
      await prefs.setString(_cacheKey, ordenesString);
      await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
      
      print('💾 ✅ ${ordenes.length} órdenes guardadas en caché local con TODOS los datos');
      
      // Debug: Verificar primera orden para asegurar que se guardó correctamente
      if (ordenes.isNotEmpty) {
        final primeraOrden = ordenes.first;
        print('   📋 Primera orden cacheada:');
        print('      - ID: ${primeraOrden.id}');
        print('      - Número: ${primeraOrden.numeroOrden}');
        print('      - Emisor: ${primeraOrden.emisor}');
        print('      - Destinatario: ${primeraOrden.receptor}');
        print('      - Dirección: ${primeraOrden.direccionDestino}');
        print('      - Estado: ${primeraOrden.estado}');
      }
      
      // 🔒 CRÍTICO: Retornar la lista fusionada con cambios locales preservados
      return ordenes;
    } catch (e) {
      print('❌ Error guardando órdenes en caché: $e');
      print('❌ Stack trace: ${StackTrace.current}');
      return ordenes; // Retornar la lista original en caso de error
    }
  }

  /// Obtener órdenes desde caché local
  /// ✅ FIX CRÍTICO: Recuperar TODOS los datos correctamente
  static Future<List<Orden>> getCachedOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ordenesString = prefs.getString(_cacheKey);
      
      if (ordenesString == null || ordenesString.isEmpty) {
        print('⚠️ No hay órdenes en caché');
        return [];
      }
      
      // Decodificar JSON
      final ordenesJson = jsonDecode(ordenesString) as List;
      
      // Convertir a objetos Orden
      final ordenes = ordenesJson
          .map((json) => Orden.fromJson(json as Map<String, dynamic>))
          .toList();
      
      print('💾 ✅ ${ordenes.length} órdenes cargadas desde caché local con TODOS los datos');
      
      // Debug: Verificar primera orden para asegurar que se cargó correctamente
      if (ordenes.isNotEmpty) {
        final primeraOrden = ordenes.first;
        print('   📋 Primera orden recuperada del caché:');
        print('      - ID: ${primeraOrden.id}');
        print('      - Número: ${primeraOrden.numeroOrden}');
        print('      - Emisor: ${primeraOrden.emisor}');
        print('      - Destinatario: ${primeraOrden.receptor}');
        print('      - Dirección: ${primeraOrden.direccionDestino}');
        print('      - Estado: ${primeraOrden.estado}');
        print('      - ¿Es N/A? ${primeraOrden.numeroOrden == "N/A" ? "❌ SÍ - PROBLEMA" : "✅ NO - OK"}');
        print('      - ¿Es Sin emisor? ${primeraOrden.emisor == "Sin emisor" ? "❌ SÍ - PROBLEMA" : "✅ NO - OK"}');
      }
      
      return ordenes;
    } catch (e) {
      print('❌ Error cargando órdenes desde caché: $e');
      print('❌ Stack trace: ${StackTrace.current}');
      return [];
    }
  }

  /// Actualizar una orden específica en el caché
  /// 🔒 OFFLINE-FIRST: Preservar cambios locales cuando se actualiza
  static Future<Orden> updateCachedOrder(Orden orden, {bool preserveLocalChanges = false}) async {
    try {
      final ordenes = await getCachedOrders();
      
      // Buscar y actualizar la orden
      final index = ordenes.indexWhere((o) => o.id == orden.id);
      
      if (index != -1) {
        ordenes[index] = orden;
        // Al actualizar una orden individual, NO preservar cambios (ya estamos actualizando específicamente)
        await cacheOrders(ordenes, preserveLocalChanges: false);
        print('💾 Orden actualizada en caché: ${orden.numeroOrden} (estado: ${orden.estado})');
      } else {
        // Si no existe, agregarla
        ordenes.add(orden);
        await cacheOrders(ordenes, preserveLocalChanges: false);
        print('💾 Nueva orden agregada al caché: ${orden.numeroOrden}');
      }
      return orden;
    } catch (e) {
      print('❌ Error actualizando orden en caché: $e');
      return orden;
    }
  }

  /// Obtener timestamp de última sincronización
  static Future<DateTime?> getLastSyncTimestamp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestampString = prefs.getString(_lastSyncKey);
      
      if (timestampString != null) {
        return DateTime.parse(timestampString);
      }
    } catch (e) {
      print('❌ Error obteniendo timestamp de sincronización: $e');
    }
    
    return null;
  }

  /// Limpiar caché
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_lastSyncKey);
      print('🗑️ Caché de órdenes limpiado');
    } catch (e) {
      print('❌ Error limpiando caché: $e');
    }
  }

  /// Verificar si hay caché disponible
  static Future<bool> hasCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(_cacheKey);
    } catch (e) {
      return false;
    }
  }

  /// Obtener una orden específica por ID desde el caché
  static Future<Orden?> getCachedOrderById(String ordenId) async {
    try {
      final ordenes = await getCachedOrders();
      
      try {
        final orden = ordenes.firstWhere(
          (o) => o.id == ordenId,
        );
        
        print('💾 Orden cargada desde caché: ${orden.numeroOrden}');
        return orden;
      } catch (e) {
        // firstWhere lanza excepción si no encuentra, retornar null
        print('⚠️ Orden $ordenId no encontrada en caché');
        return null;
      }
    } catch (e) {
      print('❌ Error obteniendo orden desde caché: $e');
      return null;
    }
  }

  /// Obtener operaciones pendientes desde SharedPreferences
  /// (mismo lugar donde SyncService las guarda)
  static Future<List<Map<String, dynamic>>> _getPendingOperationsFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final operationsJson = prefs.getString('pending_sync_operations');
      
      if (operationsJson == null || operationsJson.isEmpty) {
        return [];
      }
      
      final operationsList = jsonDecode(operationsJson) as List;
      return operationsList.map((op) => Map<String, dynamic>.from(op)).toList();
    } catch (e) {
      print('⚠️ Error obteniendo operaciones pendientes: $e');
      return [];
    }
  }
}

