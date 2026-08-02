import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';
import '../models/orden.dart';
import '../utils/entrega_vendedor_filtro.dart';
import '../utils/repartidor_master_util.dart';
import 'orden_cache_service.dart';
import 'productos_orden_tienda_service.dart';
import 'sync_service.dart';

/// Precarga de órdenes al boot (pantalla de carga) → [OrdenCacheService].
/// Misma idea que home offline-first: con internet llena el caché; sin internet
/// deja lo ya guardado para tarjetas y cambios de estado locales.
class RepartidorOrdenesBootFetchService {
  RepartidorOrdenesBootFetchService._();
  static final RepartidorOrdenesBootFetchService instance =
      RepartidorOrdenesBootFetchService._();

  static const _selectOrdenes =
      '*, destinatarios!left(nombre, telefono, direccion, municipio, provincia, consejo_popular_batey), sucursales!left(nombre, direccion, municipio, provincia, pais, es_principal)';

  /// Descarga órdenes del repartidor (si hay red) y las guarda en caché.
  /// Retorna el conteo final en caché.
  Future<int> fetchAndCacheForBoot({
    void Function(String message)? onStatus,
  }) async {
    final sync = SyncService();
    final cached = await OrdenCacheService.getCachedOrders();

    if (!sync.isOnline) {
      onStatus?.call(
        cached.isEmpty
            ? 'Sin internet · sin órdenes en caché aún'
            : 'Modo offline · ${cached.length} órdenes guardadas',
      );
      return cached.length;
    }

    final prefsBoot = await SharedPreferences.getInstance();
    final user = supabase.auth.currentUser;
    final authId = user?.id ??
        supabase.auth.currentSession?.user.id ??
        prefsBoot.getString('last_repartidor_auth_id');
    if (authId == null || authId.isEmpty) return cached.length;

    onStatus?.call('Obteniendo perfil…');
    final profile = await _resolveProfile(authId, user?.email);
    final tenantId = profile.tenantId;
    final nombre = profile.nombre;
    final esMaster = profile.esMaster;
    final esRecolector = profile.esRecolector;

    if (tenantId == null || tenantId.isEmpty) {
      print('⚠️ Boot fetch: sin tenant_id — no se descargan órdenes');
      onStatus?.call(
        cached.isNotEmpty
            ? 'Usando ${cached.length} órdenes en caché'
            : 'Sin empresa en caché',
      );
      return cached.length;
    }
    if (nombre == null || nombre.trim().isEmpty) {
      print('⚠️ Boot fetch: sin nombre de repartidor');
      return cached.length;
    }

    onStatus?.call(
      esMaster
          ? 'Descargando todas las órdenes…'
          : 'Descargando tus órdenes…',
    );

    try {
      final rows = await _fetchRows(
        tenantId: tenantId,
        repartidorNombre: nombre.trim(),
        esMaster: esMaster,
        esRecolector: esRecolector,
      );

      final ordenes = <Orden>[];
      for (final row in rows) {
        try {
          if (!EntregaVendedorFiltro.incluirFila(row)) continue;
          final tipo = row['tipo_orden']?.toString();
          if (!esRecolector && tipo == 'RECOGIDA') continue;
          if (esRecolector && tipo != 'RECOGIDA') continue;
          ordenes.add(Orden.fromJson(row));
        } catch (e) {
          print('⚠️ Boot parse orden: $e');
        }
      }

      if (ordenes.isEmpty && cached.isNotEmpty) {
        // No vaciar caché si la red devolvió 0 (timeout / filtro).
        onStatus?.call('Conservando ${cached.length} órdenes en caché');
        return cached.length;
      }

      final fused = await OrdenCacheService.cacheOrders(ordenes);
      print('💾 Boot: ${fused.length} órdenes en caché (descargadas ${ordenes.length})');
      onStatus?.call('${fused.length} órdenes listas en caché');
      // Precarga productos+fotos de compras tienda para verlos sin internet.
      // ignore: unawaited_futures
      ProductosOrdenTiendaPrecarga.desdeOrdenes(fused);
      return fused.length;
    } catch (e) {
      print('⚠️ Boot fetch órdenes falló, se usa caché: $e');
      onStatus?.call(
        cached.isNotEmpty
            ? 'Error de red · ${cached.length} órdenes en caché'
            : 'No se pudieron descargar órdenes',
      );
      return cached.length;
    }
  }

  Future<_BootProfile> _resolveProfile(String authId, String? email) async {
    final prefs = await SharedPreferences.getInstance();
    String? tenantId = prefs.getString('cached_tenant_id_$authId');
    String? nombre = prefs.getString('cached_repartidor_nombre_$authId');
    bool? esMaster = await RepartidorMasterUtil.loadCached(authId);
    String? tipo = prefs.getString('cached_repartidor_tipo_$authId');

    final rawUser = prefs.getString('cached_user_data_$authId');
    if (rawUser != null && rawUser.isNotEmpty) {
      try {
        final m = jsonDecode(rawUser) as Map<String, dynamic>;
        tenantId ??= m['tenant_id']?.toString();
        nombre ??= m['nombre']?.toString();
        esMaster ??= RepartidorMasterUtil.parseFlag(m['repartidor_master']);
        tipo ??= m['tipo_repartidor']?.toString();
      } catch (_) {}
    }

    try {
      var userData = await supabase
          .from('usuarios')
          .select(
            'nombre, tenant_id, repartidor_master, tipo_repartidor',
          )
          .eq('auth_id', authId)
          .maybeSingle();
      if (userData == null && email != null) {
        userData = await supabase
            .from('usuarios')
            .select(
              'nombre, tenant_id, repartidor_master, tipo_repartidor',
            )
            .eq('email', email)
            .maybeSingle();
      }
      if (userData != null) {
        tenantId = userData['tenant_id']?.toString() ?? tenantId;
        nombre = userData['nombre']?.toString() ?? nombre;
        esMaster = RepartidorMasterUtil.parseFlag(userData['repartidor_master']);
        tipo = userData['tipo_repartidor']?.toString() ?? tipo;
        await prefs.setString('cached_user_data_$authId', jsonEncode(userData));
        if (tenantId != null && tenantId.isNotEmpty) {
          await prefs.setString('cached_tenant_id_$authId', tenantId);
        }
        if (nombre != null && nombre.isNotEmpty) {
          await prefs.setString('cached_repartidor_nombre_$authId', nombre);
        }
        await RepartidorMasterUtil.saveCached(authId, esMaster);
        if (tipo != null && tipo.isNotEmpty) {
          await prefs.setString('cached_repartidor_tipo_$authId', tipo);
        }
      }
    } catch (e) {
      print('⚠️ Boot profile online: $e — usando prefs');
    }

    final esRecolector =
        (tipo ?? '').toUpperCase().contains('RECOLECTOR') ||
        (tipo ?? '').toUpperCase() == 'RECOGIDA';

    return _BootProfile(
      tenantId: tenantId,
      nombre: nombre,
      esMaster: esMaster ?? false,
      esRecolector: esRecolector,
    );
  }

  Future<List<Map<String, dynamic>>> _fetchRows({
    required String tenantId,
    required String repartidorNombre,
    required bool esMaster,
    required bool esRecolector,
  }) async {
    if (esRecolector) {
      var q = supabase
          .from('ordenes')
          .select(_selectOrdenes)
          .eq('tenant_id', tenantId)
          .eq('tipo_orden', 'RECOGIDA')
          .eq('repartidor_nombre', repartidorNombre);
      q = EntregaVendedorFiltro.excluirEnConsulta(q);
      final res = await q.limit(200);
      return _asMapList(res);
    }

    if (esMaster) {
      var q = supabase
          .from('ordenes')
          .select(_selectOrdenes)
          .eq('tenant_id', tenantId);
      q = EntregaVendedorFiltro.excluirEnConsulta(q);
      final res = await q.limit(500);
      return _asMapList(res);
    }

    // Repartidor normal: asignadas a su nombre.
    var q = supabase
        .from('ordenes')
        .select(_selectOrdenes)
        .eq('tenant_id', tenantId)
        .eq('repartidor_nombre', repartidorNombre);
    q = EntregaVendedorFiltro.excluirEnConsulta(q);
    final res = await q.limit(200);
    return _asMapList(res);
  }

  List<Map<String, dynamic>> _asMapList(dynamic res) {
    if (res is! List) return [];
    return res
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}

class _BootProfile {
  final String? tenantId;
  final String? nombre;
  final bool esMaster;
  final bool esRecolector;

  const _BootProfile({
    required this.tenantId,
    required this.nombre,
    required this.esMaster,
    required this.esRecolector,
  });
}
