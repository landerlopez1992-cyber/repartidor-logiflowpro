import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:latlong2/latlong.dart';

import '../main.dart';
import 'map_tile_disk_cache.dart';
import 'offline_storage_service.dart';
import 'orden_cache_service.dart';
import 'repartidor_ordenes_boot_fetch_service.dart';
import 'repartidor_pantallas_offline_service.dart';
import 'sync_service.dart';
import 'taxi_tarifas_chofer_service.dart';
import 'tenant_mapa_offline_service.dart';

/// Resultado de branding de empresa para splash / loading.
class RepartidorEmpresaBootInfo {
  final String? nombre;
  final String? logoUrl;
  final String? logoLocalPath;

  const RepartidorEmpresaBootInfo({
    this.nombre,
    this.logoUrl,
    this.logoLocalPath,
  });
}

/// Precarga y caché offline al arrancar (estilo app móvil):
/// empresa, logo en disco, órdenes cacheadas, storage offline y sync.
class RepartidorBootCacheService {
  RepartidorBootCacheService._();
  static final RepartidorBootCacheService instance =
      RepartidorBootCacheService._();

  static const _empresaKeyPrefix = 'cached_empresa_boot_';

  /// Lee branding guardado (funciona sin internet).
  Future<RepartidorEmpresaBootInfo?> loadEmpresaCached(String authUserId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_empresaKeyPrefix$authUserId');
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final local = m['logoLocalPath']?.toString();
      final localOk = local != null &&
          local.isNotEmpty &&
          !kIsWeb &&
          File(local).existsSync();
      return RepartidorEmpresaBootInfo(
        nombre: m['nombre']?.toString(),
        logoUrl: m['logoUrl']?.toString(),
        logoLocalPath: localOk ? local : null,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveEmpresa({
    required String authUserId,
    String? nombre,
    String? logoUrl,
    String? logoLocalPath,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_empresaKeyPrefix$authUserId',
        jsonEncode({
          'nombre': nombre,
          'logoUrl': logoUrl,
          'logoLocalPath': logoLocalPath,
          'saved_at': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      print('⚠️ saveEmpresa boot: $e');
    }
  }

  /// Descarga el logo a disco para mostrarlo offline en la pantalla de carga.
  Future<String?> cacheLogoToDisk(String logoUrl, String authUserId) async {
    if (kIsWeb || logoUrl.trim().isEmpty) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/empresa_logo_$authUserId.bin');
      final res = await http.get(Uri.parse(logoUrl)).timeout(
            const Duration(seconds: 12),
          );
      if (res.statusCode >= 200 && res.statusCode < 300 && res.bodyBytes.isNotEmpty) {
        await file.writeAsBytes(res.bodyBytes, flush: true);
        return file.path;
      }
    } catch (e) {
      print('⚠️ cacheLogoToDisk: $e');
    }
    return null;
  }

  /// Hidrata empresa: disco → red (si hay) → guarda.
  Future<RepartidorEmpresaBootInfo> resolveEmpresa({
    required String authUserId,
  }) async {
    final cached = await loadEmpresaCached(authUserId);
    final sync = SyncService();

    if (!sync.isOnline) {
      return cached ?? const RepartidorEmpresaBootInfo();
    }

    try {
      final usuarioData = await supabase
          .from('usuarios')
          .select('tenant_id')
          .eq('auth_id', authUserId)
          .maybeSingle();
      final tenantId = usuarioData?['tenant_id'] as String?;
      if (tenantId == null || tenantId.isEmpty) {
        return cached ?? const RepartidorEmpresaBootInfo();
      }

      final tenantData = await supabase
          .from('tenants')
          .select('nombre, logo_url')
          .eq('id', tenantId)
          .maybeSingle();

      final nombre = tenantData?['nombre']?.toString();
      final logoUrl = tenantData?['logo_url']?.toString();
      String? localPath = cached?.logoLocalPath;
      if (logoUrl != null && logoUrl.isNotEmpty) {
        if (localPath == null || cached?.logoUrl != logoUrl) {
          localPath = await cacheLogoToDisk(logoUrl, authUserId) ?? localPath;
        }
      }

      await saveEmpresa(
        authUserId: authUserId,
        nombre: nombre,
        logoUrl: logoUrl,
        logoLocalPath: localPath,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_tenant_id_$authUserId', tenantId);
      if (nombre != null && nombre.isNotEmpty) {
        await prefs.setString('cached_tenant_nombre_$authUserId', nombre);
      }

      return RepartidorEmpresaBootInfo(
        nombre: nombre ?? cached?.nombre,
        logoUrl: logoUrl ?? cached?.logoUrl,
        logoLocalPath: localPath,
      );
    } catch (e) {
      print('⚠️ resolveEmpresa online falló, usando caché: $e');
      return cached ?? const RepartidorEmpresaBootInfo();
    }
  }

  /// Pipeline de carga al entrar (login o sesión restaurada).
  Future<void> runBootLoad({
    required void Function(double progress, String message) updateProgress,
  }) async {
    final syncService = SyncService();

    updateProgress(0.05, 'Inicializando sistema...');
    await syncService.initialize();
    await OfflineStorageService().initialize();

    updateProgress(0.15, 'Verificando sesión...');
    var user = supabase.auth.currentUser;
    if (user == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final lastId = prefs.getString('last_repartidor_auth_id');
        if (lastId != null && lastId.isNotEmpty) {
          // Sesión offline: no hay currentUser pero sí caché del repartidor.
          updateProgress(0.28, 'Cargando desde caché (sin internet)…');
          await _bootOfflineConAuthId(lastId, updateProgress);
          return;
        }
      } catch (_) {}
      updateProgress(1.0, 'Sin sesión');
      return;
    }

    updateProgress(0.28, 'Cargando empresa...');
    final empresa = await resolveEmpresa(authUserId: user.id);
    if (empresa.nombre != null || empresa.logoUrl != null) {
      print(
        '🏢 Boot empresa: ${empresa.nombre} '
        '(logo local: ${empresa.logoLocalPath != null})',
      );
    }

    updateProgress(0.40, 'Cargando órdenes…');
    final nOrdenes =
        await RepartidorOrdenesBootFetchService.instance.fetchAndCacheForBoot(
      onStatus: (msg) {
        // Mantener progreso en zona de órdenes mientras descarga.
        updateProgress(0.55, msg);
      },
    );
    updateProgress(
      0.65,
      nOrdenes > 0
          ? '$nOrdenes órdenes en caché'
          : (syncService.isOnline
              ? 'Sin órdenes asignadas'
              : 'Sin internet · sin órdenes en caché'),
    );

    updateProgress(0.72, 'Preparando mapa offline…');
    await _precargarMapaOffline(userId: user.id, online: syncService.isOnline);

    updateProgress(0.78, 'Preparando chat de soporte…');
    if (syncService.isOnline) {
      try {
        await RepartidorPantallasOfflineService.prefetchChatSoporteAlAbrirApp(
          user.id,
        );
      } catch (e) {
        print('⚠️ Boot chat (no crítico): $e');
      }
      try {
        await RepartidorPantallasOfflineService.prefetchComisionMiDeudaAlAbrirApp(
          user.id,
        );
      } catch (e) {
        print('⚠️ Boot comisión (no crítico): $e');
      }
      try {
        await TaxiTarifasChoferService.instance.prefetchAlAbrirApp();
      } catch (e) {
        print('⚠️ Boot tarifa taxi (no crítico): $e');
      }
      try {
        await RepartidorPantallasOfflineService.prefetchMetodoCobroAlAbrirApp(
          user.id,
        );
      } catch (e) {
        print('⚠️ Boot método cobro (no crítico): $e');
      }
    } else {
      try {
        final meta =
            await RepartidorPantallasOfflineService.cargarMetaChat(user.id);
        final convId = meta?.conversacionId;
        if (convId != null && convId.isNotEmpty) {
          final msgs =
              await RepartidorPantallasOfflineService.cargarMensajesChat(convId);
          print(
            '💬 Sin internet · chat en caché: ${msgs?.length ?? 0} mensajes',
          );
        }
      } catch (_) {}
      try {
        await RepartidorPantallasOfflineService.cargarComisionMiDeuda(user.id);
      } catch (_) {}
    }

    updateProgress(0.84, 'Preparando notificaciones...');
    try {
      final notif =
          await RepartidorPantallasOfflineService.cargarNotificaciones(user.id);
      if (notif != null) {
        print(
          '🔔 Notificaciones en caché: '
          '${notif.ordenes.length + notif.pagos.length + notif.generales.length}',
        );
      }
    } catch (_) {}

    updateProgress(0.90, 'Sincronizando pendientes…');
    if (syncService.isOnline) {
      try {
        unawaited(() async {
          try {
            await syncService.syncPendingOperations();
            await RepartidorPantallasOfflineService.sincronizarMensajesSoporte();
            print('✅ Sync boot completada');
          } catch (e) {
            print('⚠️ Sync boot (no crítico): $e');
          }
        }());
      } catch (e) {
        print('⚠️ Error iniciando sync boot: $e');
      }
    } else {
      updateProgress(0.94, 'Sin internet · datos, chat y mapa locales listos');
    }

    updateProgress(
      1.0,
      nOrdenes > 0 ? 'Listo · $nOrdenes órdenes en caché' : 'Listo',
    );
  }

  /// Arranque sin `currentUser` (token vencido / sin red): solo disco.
  Future<void> _bootOfflineConAuthId(
    String userId,
    void Function(double progress, String message) updateProgress,
  ) async {
    updateProgress(0.35, 'Cargando empresa (caché)…');
    final empresa = await loadEmpresaCached(userId);
    if (empresa != null) {
      print('🏢 Boot offline empresa: ${empresa.nombre}');
    }

    updateProgress(0.55, 'Cargando órdenes en caché…');
    final ordenes = await OrdenCacheService.getCachedOrders();
    final nOrdenes = ordenes.length;

    updateProgress(0.75, 'Preparando mapa offline…');
    await _precargarMapaOffline(userId: userId, online: false);

    updateProgress(0.88, 'Preparando chat / notificaciones…');
    try {
      final meta =
          await RepartidorPantallasOfflineService.cargarMetaChat(userId);
      final convId = meta?.conversacionId;
      if (convId != null && convId.isNotEmpty) {
        await RepartidorPantallasOfflineService.cargarMensajesChat(convId);
      }
    } catch (_) {}
    try {
      await RepartidorPantallasOfflineService.cargarNotificaciones(userId);
    } catch (_) {}

    updateProgress(
      1.0,
      nOrdenes > 0
          ? 'Listo offline · $nOrdenes órdenes en caché'
          : 'Listo offline · sin internet',
    );
  }

  /// MBTiles del tenant + teselas alrededor de las entregas (sin Google Maps).
  Future<void> _precargarMapaOffline({
    required String userId,
    required bool online,
  }) async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      var tenantId = prefs.getString('cached_tenant_id_$userId');
      tenantId ??= await TenantMapaOfflineService.instance.tenantIdChofer();

      if (tenantId != null && tenantId.isNotEmpty) {
        if (online) {
          final path = await TenantMapaOfflineService.instance
              .ensureLocalMbtiles(tenantId)
              .timeout(const Duration(seconds: 95), onTimeout: () => null);
          if (path != null) {
            print('🗺️ Mapa offline (MBTiles) listo: $path');
          } else {
            print('⚠️ Sin MBTiles de zona; se usará caché de teselas');
          }
        } else {
          final local = await TenantMapaOfflineService.instance
              .localMbtilesPathIfReady(tenantId);
          print(
            local != null
                ? '🗺️ Offline: MBTiles local disponible'
                : '📴 Offline: sin MBTiles local (usa teselas ya cacheadas)',
          );
        }
      }

      if (!online) return;

      final ordenes = await OrdenCacheService.getCachedOrders();
      final points = <LatLng>[];
      for (final o in ordenes) {
        if (o.latitudEntrega != null && o.longitudEntrega != null) {
          points.add(LatLng(o.latitudEntrega!, o.longitudEntrega!));
        }
        if (points.length >= 40) break;
      }
      if (points.isEmpty) return;

      final n = await MapTileDiskCache.instance
          .prefetchAroundPoints(points)
          .timeout(const Duration(seconds: 45), onTimeout: () => 0);
      print('🗺️ Teselas precargadas para entregas: $n');
    } catch (e) {
      print('⚠️ Precarga mapa offline (no crítico): $e');
    }
  }
}
