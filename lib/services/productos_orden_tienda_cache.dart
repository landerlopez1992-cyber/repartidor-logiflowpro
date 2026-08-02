import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/productos_orden_tienda_util.dart';
import 'productos_orden_tienda_service.dart';

/// Caché offline de productos de compra tienda (JSON + fotos en disco).
class ProductosOrdenTiendaCache {
  ProductosOrdenTiendaCache._();

  static const _prefix = 'repartidor_productos_orden_tienda_v1_';

  static String _key(String ordenId) => '$_prefix${ordenId.trim()}';

  static Future<void> save(
    String ordenId,
    ProductosOrdenTiendaResultado resultado,
  ) async {
    final id = ordenId.trim();
    if (id.isEmpty || !resultado.ok) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lineasJson = <Map<String, dynamic>>[];
      for (final l in resultado.lineas) {
        lineasJson.add({
          'nombre': l.nombre,
          'cantidad': l.cantidad,
          'imagen_url': l.imagenUrl,
          'imagen_local': l.imagenLocalPath,
          'origen': l.origen.name,
          'detalle': l.detalle,
        });
      }
      await prefs.setString(
        _key(id),
        jsonEncode({
          'ok': true,
          'numero_orden': resultado.numeroOrden,
          'total_articulos': resultado.totalArticulos,
          'comprador_nombre': resultado.compradorNombre,
          'comprador_avatar_url': resultado.compradorAvatarUrl,
          'destinatario_nombre': resultado.destinatarioNombre,
          'destinatario_avatar_url': resultado.destinatarioAvatarUrl,
          'productos': lineasJson,
          'saved_at': DateTime.now().toIso8601String(),
        }),
      );
    } catch (e) {
      print('⚠️ ProductosOrdenTiendaCache.save: $e');
    }
  }

  static Future<ProductosOrdenTiendaResultado?> load(String ordenId) async {
    final id = ordenId.trim();
    if (id.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(id));
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final map = Map<String, dynamic>.from(m);
      final rawList = map['productos'];
      final lineas = <ProductoOrdenTiendaLinea>[];
      if (rawList is List) {
        for (final item in rawList) {
          if (item is! Map) continue;
          final pmap = Map<String, dynamic>.from(item);
          final origenName = pmap['origen']?.toString() ?? 'otro';
          OrigenProductoTienda origen = OrigenProductoTienda.otro;
          for (final e in OrigenProductoTienda.values) {
            if (e.name == origenName) {
              origen = e;
              break;
            }
          }
          final local = pmap['imagen_local']?.toString().trim();
          final localOk =
              local != null && local.isNotEmpty && File(local).existsSync();
          lineas.add(
            ProductoOrdenTiendaLinea(
              nombre: (pmap['nombre']?.toString().trim().isNotEmpty == true)
                  ? pmap['nombre'].toString().trim()
                  : 'Producto',
              cantidad: (pmap['cantidad'] is num)
                  ? (pmap['cantidad'] as num).toInt()
                  : int.tryParse('${pmap['cantidad']}') ?? 1,
              imagenUrl: pmap['imagen_url']?.toString(),
              imagenLocalPath: localOk ? local : null,
              origen: origen,
              detalle: pmap['detalle']?.toString(),
            ),
          );
        }
      }
      if (lineas.isEmpty) return null;
      final totalRpc = map['total_articulos'];
      return ProductosOrdenTiendaResultado(
        ok: true,
        lineas: lineas,
        totalArticulos: totalRpc is num
            ? totalRpc.toInt()
            : ProductosOrdenTiendaUtil.totalArticulos(lineas),
        numeroOrden: map['numero_orden']?.toString(),
        compradorNombre: map['comprador_nombre']?.toString(),
        compradorAvatarUrl: map['comprador_avatar_url']?.toString(),
        destinatarioNombre: map['destinatario_nombre']?.toString(),
        destinatarioAvatarUrl: map['destinatario_avatar_url']?.toString(),
        desdeCache: true,
      );
    } catch (e) {
      print('⚠️ ProductosOrdenTiendaCache.load: $e');
      return null;
    }
  }

  /// Descarga fotos a disco y actualiza rutas locales en el resultado.
  static Future<ProductosOrdenTiendaResultado> enrichWithLocalImages(
    String ordenId,
    ProductosOrdenTiendaResultado resultado,
  ) async {
    if (!resultado.ok || resultado.lineas.isEmpty) return resultado;
    final id = ordenId.trim();
    if (id.isEmpty) return resultado;
    try {
      final dir = await _dirForOrden(id);
      final updated = <ProductoOrdenTiendaLinea>[];
      for (final l in resultado.lineas) {
        final url = (l.imagenUrl ?? '').trim();
        String? local = l.imagenLocalPath;
        if (local != null && local.isNotEmpty && File(local).existsSync()) {
          updated.add(l);
          continue;
        }
        if (url.startsWith('http')) {
          local = await _downloadImage(dir, url);
        }
        updated.add(
          ProductoOrdenTiendaLinea(
            nombre: l.nombre,
            cantidad: l.cantidad,
            imagenUrl: l.imagenUrl,
            imagenLocalPath: local,
            origen: l.origen,
            detalle: l.detalle,
          ),
        );
      }
      final out = ProductosOrdenTiendaResultado(
        ok: true,
        lineas: updated,
        totalArticulos: resultado.totalArticulos,
        numeroOrden: resultado.numeroOrden,
        compradorNombre: resultado.compradorNombre,
        compradorAvatarUrl: resultado.compradorAvatarUrl,
        destinatarioNombre: resultado.destinatarioNombre,
        destinatarioAvatarUrl: resultado.destinatarioAvatarUrl,
        desdeCache: resultado.desdeCache,
      );
      await save(id, out);
      return out;
    } catch (e) {
      print('⚠️ enrichWithLocalImages: $e');
      return resultado;
    }
  }

  static Future<Directory> _dirForOrden(String ordenId) async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${root.path}${Platform.pathSeparator}productos_orden_tienda'
      '${Platform.pathSeparator}$ordenId',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<String?> _downloadImage(Directory dir, String url) async {
    try {
      final hash = md5.convert(utf8.encode(url)).toString();
      final ext = _guessExt(url);
      final file = File('${dir.path}${Platform.pathSeparator}$hash$ext');
      if (await file.exists() && await file.length() > 0) {
        return file.path;
      }
      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 12));
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      if (res.bodyBytes.isEmpty) return null;
      await file.writeAsBytes(res.bodyBytes, flush: true);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  static String _guessExt(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.png')) return '.png';
    if (lower.contains('.webp')) return '.webp';
    if (lower.contains('.gif')) return '.gif';
    return '.jpg';
  }
}
