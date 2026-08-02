import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/orden.dart';
import '../utils/productos_orden_tienda_util.dart';
import 'productos_orden_tienda_cache.dart';

class ProductosOrdenTiendaResultado {
  const ProductosOrdenTiendaResultado({
    required this.ok,
    required this.lineas,
    required this.totalArticulos,
    this.numeroOrden,
    this.error,
    this.compradorNombre,
    this.compradorAvatarUrl,
    this.destinatarioNombre,
    this.destinatarioAvatarUrl,
    this.desdeCache = false,
  });

  final bool ok;
  final List<ProductoOrdenTiendaLinea> lineas;
  final int totalArticulos;
  final String? numeroOrden;
  final String? error;
  final String? compradorNombre;
  final String? compradorAvatarUrl;
  final String? destinatarioNombre;
  final String? destinatarioAvatarUrl;
  final bool desdeCache;
}

class ProductosOrdenTiendaService {
  ProductosOrdenTiendaService([SupabaseClient? client])
      : _c = client ?? Supabase.instance.client;

  final SupabaseClient _c;

  /// Offline-first: caché → red → fallback [orden.itemsAdicionales].
  Future<ProductosOrdenTiendaResultado> cargar(
    String ordenId, {
    Orden? orden,
    bool forzarRed = false,
  }) async {
    final id = ordenId.trim();
    if (id.isEmpty) {
      return const ProductosOrdenTiendaResultado(
        ok: false,
        lineas: [],
        totalArticulos: 0,
        error: 'Orden no válida.',
      );
    }

    ProductosOrdenTiendaResultado? cached;
    if (!forzarRed) {
      cached = await ProductosOrdenTiendaCache.load(id);
      if (cached != null && cached.ok && cached.lineas.isNotEmpty) {
        // Refresco en segundo plano; el caller ya puede pintar caché.
        // Aquí devolvemos caché si pedimos solo lectura rápida vía [cargarSoloCache].
      }
    }

    try {
      final res = await _c
          .rpc(
            'repartidor_productos_orden_tienda',
            params: {'p_orden_id': id},
          )
          .timeout(const Duration(seconds: 18));
      if (res is! Map) {
        return await _fallbackOffline(
          id,
          orden: orden,
          cached: cached,
          error: 'No se pudieron cargar los productos.',
        );
      }
      final m = Map<String, dynamic>.from(res);
      if (m['ok'] != true) {
        return await _fallbackOffline(
          id,
          orden: orden,
          cached: cached,
          error: m['error']?.toString() ?? 'No se pudieron cargar los productos.',
        );
      }
      final raw = m['productos'];
      final list = raw is List ? raw : <dynamic>[];
      final lineas = ProductosOrdenTiendaUtil.parsearProductos(list);
      final totalRpc = m['total_articulos'];
      final total = totalRpc is num
          ? totalRpc.toInt()
          : ProductosOrdenTiendaUtil.totalArticulos(lineas);
      var resultado = ProductosOrdenTiendaResultado(
        ok: true,
        lineas: lineas,
        totalArticulos: total,
        numeroOrden: m['numero_orden']?.toString(),
        compradorNombre: m['comprador_nombre']?.toString(),
        compradorAvatarUrl: m['comprador_avatar_url']?.toString(),
        destinatarioNombre: m['destinatario_nombre']?.toString(),
        destinatarioAvatarUrl: m['destinatario_avatar_url']?.toString(),
      );
      await ProductosOrdenTiendaCache.save(id, resultado);
      resultado =
          await ProductosOrdenTiendaCache.enrichWithLocalImages(id, resultado);
      return resultado;
    } catch (_) {
      return await _fallbackOffline(
        id,
        orden: orden,
        cached: cached,
        error: 'Sin conexión. Mostrando datos guardados.',
      );
    }
  }

  /// Solo lee disco/prefs (sin red). Útil para pintar al instante.
  Future<ProductosOrdenTiendaResultado?> cargarSoloCache(
    String ordenId, {
    Orden? orden,
  }) async {
    final id = ordenId.trim();
    if (id.isEmpty) return null;
    final cached = await ProductosOrdenTiendaCache.load(id);
    if (cached != null && cached.ok && cached.lineas.isNotEmpty) {
      return cached;
    }
    return _desdeItemsOrden(orden);
  }

  /// Precarga en segundo plano (tras ver órdenes con red).
  Future<void> precargarEnBackground(Orden orden) async {
    if (!orden.esCompraTienda) return;
    final id = orden.id.trim();
    if (id.isEmpty) return;
    try {
      await cargar(id, orden: orden, forzarRed: true);
    } catch (_) {}
  }

  Future<ProductosOrdenTiendaResultado> _fallbackOffline(
    String id, {
    Orden? orden,
    ProductosOrdenTiendaResultado? cached,
    String? error,
  }) async {
    if (cached != null && cached.ok && cached.lineas.isNotEmpty) {
      return ProductosOrdenTiendaResultado(
        ok: true,
        lineas: cached.lineas,
        totalArticulos: cached.totalArticulos,
        numeroOrden: cached.numeroOrden,
        compradorNombre: cached.compradorNombre,
        compradorAvatarUrl: cached.compradorAvatarUrl,
        destinatarioNombre: cached.destinatarioNombre,
        destinatarioAvatarUrl: cached.destinatarioAvatarUrl,
        desdeCache: true,
        error: error,
      );
    }
    final fromOrden = _desdeItemsOrden(orden);
    if (fromOrden != null) {
      await ProductosOrdenTiendaCache.save(id, fromOrden);
      final enriched =
          await ProductosOrdenTiendaCache.enrichWithLocalImages(id, fromOrden);
      return ProductosOrdenTiendaResultado(
        ok: true,
        lineas: enriched.lineas,
        totalArticulos: enriched.totalArticulos,
        numeroOrden: enriched.numeroOrden ?? orden?.numeroOrden,
        compradorNombre: enriched.compradorNombre ?? orden?.emisor,
        destinatarioNombre: enriched.destinatarioNombre ?? orden?.receptor,
        desdeCache: true,
        error: error,
      );
    }
    final reloaded = await ProductosOrdenTiendaCache.load(id);
    if (reloaded != null && reloaded.ok && reloaded.lineas.isNotEmpty) {
      return reloaded;
    }
    return ProductosOrdenTiendaResultado(
      ok: false,
      lineas: const [],
      totalArticulos: 0,
      error: error ??
          'Sin conexión y no hay productos guardados para esta orden. '
              'Ábrela una vez con internet para guardarlos.',
      desdeCache: true,
    );
  }

  ProductosOrdenTiendaResultado? _desdeItemsOrden(Orden? orden) {
    if (orden == null) return null;
    final items = orden.itemsAdicionales;
    if (items == null || items.isEmpty) return null;
    final lineas = ProductosOrdenTiendaUtil.parsearProductos(items);
    if (lineas.isEmpty) return null;
    return ProductosOrdenTiendaResultado(
      ok: true,
      lineas: lineas,
      totalArticulos: ProductosOrdenTiendaUtil.totalArticulos(lineas),
      numeroOrden: orden.numeroOrden,
      compradorNombre: orden.emisor,
      destinatarioNombre: orden.receptor,
      desdeCache: true,
    );
  }
}

/// Precarga productos+fotos de compras tienda (máx. N) para uso offline.
class ProductosOrdenTiendaPrecarga {
  ProductosOrdenTiendaPrecarga._();

  static bool _running = false;

  static Future<void> desdeOrdenes(
    List<Orden> ordenes, {
    int maxOrdenes = 12,
  }) async {
    if (_running) return;
    final tienda = ordenes.where((o) => o.esCompraTienda).take(maxOrdenes).toList();
    if (tienda.isEmpty) return;
    _running = true;
    final svc = ProductosOrdenTiendaService();
    try {
      for (final o in tienda) {
        try {
          await svc.cargar(o.id, orden: o, forzarRed: true);
        } catch (_) {}
      }
    } finally {
      _running = false;
    }
  }
}
