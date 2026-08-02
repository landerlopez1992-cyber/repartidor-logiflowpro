import 'package:flutter/material.dart';
import '../models/orden.dart';

/// Origen visual de un ítem de compra de tienda (app repartidor).
enum OrigenProductoTienda {
  amazon,
  shein,
  vendedor,
  tienda,
  formulario,
  otro,
}

class OrigenProductoTiendaInfo {
  const OrigenProductoTiendaInfo({
    required this.origen,
    required this.etiqueta,
    required this.icono,
    required this.color,
  });

  final OrigenProductoTienda origen;
  final String etiqueta;
  final IconData icono;
  final Color color;
}

class ProductoOrdenTiendaLinea {
  const ProductoOrdenTiendaLinea({
    required this.nombre,
    required this.cantidad,
    required this.imagenUrl,
    required this.origen,
    this.detalle,
    this.imagenLocalPath,
  });

  final String nombre;
  final int cantidad;
  final String? imagenUrl;
  final OrigenProductoTienda origen;
  final String? detalle;
  /// Ruta en disco (caché offline); tiene prioridad sobre [imagenUrl].
  final String? imagenLocalPath;
}

class ProductosOrdenTiendaUtil {
  ProductosOrdenTiendaUtil._();

  /// Solo compras de tienda (Amazon/Shein/vendedor/catálogo), no envíos por libras.
  static bool esCompraTienda(Orden orden) {
    final id = (orden.tiendaOrdenId ?? '').trim();
    if (id.isNotEmpty) return true;
    final d = orden.descripcion.toLowerCase();
    return d.contains('pedido de tienda') ||
        d.contains('tienda online') ||
        d.contains('compra tienda');
  }

  static bool lineaEsRemesa(Map<String, dynamic> p) =>
      (p['tipo']?.toString().toLowerCase() ?? '') == 'remesa';

  static bool lineaEsShein(Map<String, dynamic> p) {
    final src = (p['catalog_source'] ?? p['store'] ?? '').toString().toLowerCase();
    if (src == 'shein') return true;
    final vendor = (p['vendorId'] ?? p['vendor_id'] ?? '').toString().toLowerCase();
    if (vendor == 'shein') return true;
    final sn = p['goods_sn']?.toString().trim();
    if (sn != null && sn.isNotEmpty && src != 'amazon') return true;
    return false;
  }

  static bool lineaEsAmazon(Map<String, dynamic> p) {
    if (lineaEsShein(p)) return false;
    final t = p['tipo']?.toString().toLowerCase();
    if (t == 'amazon') return true;
    final a = p['amazon_asin']?.toString().trim();
    if (a != null && a.isNotEmpty) return true;
    final id = p['id']?.toString() ?? '';
    if (id.startsWith('amz_')) return true;
    final src = (p['catalog_source'] ?? p['store'] ?? '').toString().toLowerCase();
    return src == 'amazon';
  }

  static bool lineaEsVendedor(Map<String, dynamic> p) {
    final vid = p['vendedor_usuario_web_id']?.toString().trim();
    if (vid != null && vid.isNotEmpty && vid.toLowerCase() != 'null') {
      return true;
    }
    final id = p['id']?.toString() ?? '';
    return id.startsWith('vendedor_') || id.startsWith('vend_');
  }

  static bool lineaEsFormulario(Map<String, dynamic> p) {
    final t = p['tipo']?.toString().toLowerCase();
    if (t == 'formulario') return true;
    final id = p['id']?.toString() ?? '';
    return id.startsWith('formulario');
  }

  static OrigenProductoTienda clasificarOrigen(Map<String, dynamic> p) {
    if (lineaEsShein(p)) return OrigenProductoTienda.shein;
    if (lineaEsAmazon(p)) return OrigenProductoTienda.amazon;
    if (lineaEsVendedor(p)) return OrigenProductoTienda.vendedor;
    if (lineaEsFormulario(p)) return OrigenProductoTienda.formulario;
    final t = p['tipo']?.toString().toLowerCase() ?? '';
    if (t == 'producto' || t.isEmpty || t == 'store') {
      return OrigenProductoTienda.tienda;
    }
    return OrigenProductoTienda.otro;
  }

  static OrigenProductoTiendaInfo infoOrigen(OrigenProductoTienda o) {
    switch (o) {
      case OrigenProductoTienda.amazon:
        return const OrigenProductoTiendaInfo(
          origen: OrigenProductoTienda.amazon,
          etiqueta: 'Amazon',
          icono: Icons.shopping_cart_outlined,
          color: Color(0xFFFF9900),
        );
      case OrigenProductoTienda.shein:
        return const OrigenProductoTiendaInfo(
          origen: OrigenProductoTienda.shein,
          etiqueta: 'Shein',
          icono: Icons.checkroom_outlined,
          color: Color(0xFF37474F),
        );
      case OrigenProductoTienda.vendedor:
        return const OrigenProductoTiendaInfo(
          origen: OrigenProductoTienda.vendedor,
          etiqueta: 'Vendedor',
          icono: Icons.storefront_outlined,
          color: Color(0xFF4DB6AC),
        );
      case OrigenProductoTienda.tienda:
        return const OrigenProductoTiendaInfo(
          origen: OrigenProductoTienda.tienda,
          etiqueta: 'Tienda',
          icono: Icons.store_mall_directory_outlined,
          color: Color(0xFF4CAF50),
        );
      case OrigenProductoTienda.formulario:
        return const OrigenProductoTiendaInfo(
          origen: OrigenProductoTienda.formulario,
          etiqueta: 'Formulario',
          icono: Icons.assignment_outlined,
          color: Color(0xFF64B5F6),
        );
      case OrigenProductoTienda.otro:
        return const OrigenProductoTiendaInfo(
          origen: OrigenProductoTienda.otro,
          etiqueta: 'Producto',
          icono: Icons.inventory_2_outlined,
          color: Color(0xFF90A4AE),
        );
    }
  }

  static String? _imagenDe(Map<String, dynamic> p) {
    for (final k in [
      'imagen_url',
      'imagen',
      'image',
      'image_url',
      'foto',
      'photo',
    ]) {
      final v = p[k]?.toString().trim();
      if (v != null && v.isNotEmpty && v.startsWith('http')) return v;
    }
    final imgs = p['imagenes'];
    if (imgs is List && imgs.isNotEmpty) {
      final first = imgs.first?.toString().trim();
      if (first != null && first.startsWith('http')) return first;
    }
    return null;
  }

  static String? _detalleDe(Map<String, dynamic> p) {
    final parts = <String>[];
    final labels = p['variant_labels'];
    if (labels is Map) {
      for (final e in labels.entries) {
        final k = e.key.toString().trim();
        final v = e.value?.toString().trim() ?? '';
        if (k.isNotEmpty && v.isNotEmpty) parts.add('$k: $v');
      }
    }
    final color = p['color']?.toString().trim();
    final size = p['size']?.toString().trim();
    if (parts.isEmpty) {
      if (color != null && color.isNotEmpty) parts.add('Color: $color');
      if (size != null && size.isNotEmpty) parts.add('Talla: $size');
    }
    final desc = p['descripcion']?.toString().trim();
    if (desc != null && desc.isNotEmpty && parts.isEmpty) {
      return desc.length > 80 ? '${desc.substring(0, 80)}…' : desc;
    }
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  static List<ProductoOrdenTiendaLinea> parsearProductos(List<dynamic> raw) {
    final out = <ProductoOrdenTiendaLinea>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final p = Map<String, dynamic>.from(item);
      if (lineaEsRemesa(p)) continue;
      final nombre = (p['nombre'] ?? p['name'] ?? p['title'] ?? 'Producto')
          .toString()
          .trim();
      final qtyRaw = p['cantidad'] ?? p['quantity'] ?? 1;
      final qty = qtyRaw is num
          ? qtyRaw.toInt()
          : int.tryParse(qtyRaw.toString()) ?? 1;
      out.add(
        ProductoOrdenTiendaLinea(
          nombre: nombre.isEmpty ? 'Producto' : nombre,
          cantidad: qty < 1 ? 1 : qty,
          imagenUrl: _imagenDe(p),
          origen: clasificarOrigen(p),
          detalle: _detalleDe(p),
        ),
      );
    }
    return out;
  }

  static int totalArticulos(List<ProductoOrdenTiendaLinea> lineas) =>
      lineas.fold(0, (a, b) => a + b.cantidad);
}
