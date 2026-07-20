import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/productos_orden_tienda_util.dart';

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
}

class ProductosOrdenTiendaService {
  ProductosOrdenTiendaService([SupabaseClient? client])
      : _c = client ?? Supabase.instance.client;

  final SupabaseClient _c;

  Future<ProductosOrdenTiendaResultado> cargar(String ordenId) async {
    try {
      final res = await _c.rpc(
        'repartidor_productos_orden_tienda',
        params: {'p_orden_id': ordenId},
      );
      if (res is! Map) {
        return const ProductosOrdenTiendaResultado(
          ok: false,
          lineas: [],
          totalArticulos: 0,
          error: 'No se pudieron cargar los productos.',
        );
      }
      final m = Map<String, dynamic>.from(res);
      if (m['ok'] != true) {
        return ProductosOrdenTiendaResultado(
          ok: false,
          lineas: const [],
          totalArticulos: 0,
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
      return ProductosOrdenTiendaResultado(
        ok: true,
        lineas: lineas,
        totalArticulos: total,
        numeroOrden: m['numero_orden']?.toString(),
        compradorNombre: m['comprador_nombre']?.toString(),
        compradorAvatarUrl: m['comprador_avatar_url']?.toString(),
        destinatarioNombre: m['destinatario_nombre']?.toString(),
        destinatarioAvatarUrl: m['destinatario_avatar_url']?.toString(),
      );
    } catch (_) {
      return const ProductosOrdenTiendaResultado(
        ok: false,
        lineas: [],
        totalArticulos: 0,
        error: 'Error de conexión al cargar productos.',
      );
    }
  }
}
