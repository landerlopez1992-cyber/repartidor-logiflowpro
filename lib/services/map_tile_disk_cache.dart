import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';

import '../config/carto_map_config.dart';

/// Caché en disco de teselas raster (Carto Voyager) para mapas FlutterMap.
///
/// Con internet: guarda cada tile al pedirlo.
/// Sin internet: sirve solo lo ya descargado (MBTiles del tenant tiene prioridad).
class MapTileDiskCache {
  MapTileDiskCache._();
  static final instance = MapTileDiskCache._();

  static String get urlTemplate => CartoMapConfig.urlTemplate;
  static const subdomains = ['a', 'b', 'c', 'd'];
  static const userAgent = 'com.logiflow.repartidor';

  Directory? _dir;
  final Set<String> _inflight = {};

  Future<Directory> cacheDir() async {
    if (_dir != null) return _dir!;
    final root = await getApplicationDocumentsDirectory();
    final d = Directory('${root.path}/map_tiles_carto_v1');
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    _dir = d;
    return d;
  }

  String tileKey(int z, int x, int y) => '${z}_${x}_$y.png';

  Future<File> tileFile(int z, int x, int y) async {
    final d = await cacheDir();
    return File('${d.path}/${tileKey(z, x, y)}');
  }

  String urlFor(int z, int x, int y) {
    final s = subdomains[(x + y) % subdomains.length];
    return urlTemplate
        .replaceAll('{s}', s)
        .replaceAll('{z}', '$z')
        .replaceAll('{x}', '$x')
        .replaceAll('{y}', '$y');
  }

  Future<Uint8List?> readCached(int z, int x, int y) async {
    try {
      final f = await tileFile(z, x, y);
      if (await f.exists() && await f.length() > 64) {
        return f.readAsBytes();
      }
    } catch (_) {}
    return null;
  }

  Future<Uint8List?> fetchAndCache(int z, int x, int y) async {
    final key = tileKey(z, x, y);
    if (_inflight.contains(key)) {
      // Esperar un poco a otro download del mismo tile.
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final hit = await readCached(z, x, y);
        if (hit != null) return hit;
        if (!_inflight.contains(key)) break;
      }
    }
    _inflight.add(key);
    try {
      final cached = await readCached(z, x, y);
      if (cached != null) return cached;

      final resp = await http
          .get(
            Uri.parse(urlFor(z, x, y)),
            headers: {'User-Agent': userAgent},
          )
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode < 200 ||
          resp.statusCode >= 300 ||
          resp.bodyBytes.length < 64) {
        return null;
      }
      final f = await tileFile(z, x, y);
      await f.writeAsBytes(resp.bodyBytes, flush: true);
      return resp.bodyBytes;
    } catch (_) {
      return await readCached(z, x, y);
    } finally {
      _inflight.remove(key);
    }
  }

  static int lon2tileX(double lon, int z) {
    return ((lon + 180.0) / 360.0 * (1 << z)).floor();
  }

  static int lat2tileY(double lat, int z) {
    final latRad = lat * math.pi / 180.0;
    final n = 1 << z;
    final y = ((1.0 -
                math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) /
                    math.pi) /
            2.0 *
            n)
        .floor();
    return y.clamp(0, n - 1);
  }

  /// Precarga teselas alrededor de puntos (órdenes / GPS) para uso offline.
  /// Limitado para no alargar el boot.
  Future<int> prefetchAroundPoints(
    List<LatLng> points, {
    int minZoom = 11,
    int maxZoom = 15,
    int radiusTiles = 1,
    int maxTiles = 220,
  }) async {
    if (kIsWeb || points.isEmpty) return 0;
    var saved = 0;
    final seen = <String>{};

    for (final p in points) {
      for (var z = minZoom; z <= maxZoom; z++) {
        final cx = lon2tileX(p.longitude, z);
        final cy = lat2tileY(p.latitude, z);
        final maxIndex = (1 << z) - 1;
        for (var dx = -radiusTiles; dx <= radiusTiles; dx++) {
          for (var dy = -radiusTiles; dy <= radiusTiles; dy++) {
            if (saved >= maxTiles) return saved;
            final x = (cx + dx).clamp(0, maxIndex);
            final y = (cy + dy).clamp(0, maxIndex);
            final key = tileKey(z, x, y);
            if (!seen.add(key)) continue;
            final existing = await readCached(z, x, y);
            if (existing != null) {
              saved++;
              continue;
            }
            final bytes = await fetchAndCache(z, x, y);
            if (bytes != null) saved++;
          }
        }
      }
    }
    return saved;
  }
}

/// TileProvider: disco primero, red después (y guarda).
class DiskCachedCartoTileProvider extends TileProvider {
  DiskCachedCartoTileProvider();

  static final Uint8List emptyPng = Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _DiskCachedTileImage(coordinates.z, coordinates.x, coordinates.y);
  }
}

class _DiskCachedTileImage extends ImageProvider<_DiskCachedTileImage> {
  const _DiskCachedTileImage(this.z, this.x, this.y);

  final int z;
  final int x;
  final int y;

  @override
  Future<_DiskCachedTileImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_DiskCachedTileImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _DiskCachedTileImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: 1.0,
      debugLabel: 'map_tile_${key.z}_${key.x}_${key.y}',
    );
  }

  Future<ui.Codec> _load(
    _DiskCachedTileImage key,
    ImageDecoderCallback decode,
  ) async {
    var bytes = await MapTileDiskCache.instance.readCached(key.z, key.x, key.y);
    bytes ??= await MapTileDiskCache.instance.fetchAndCache(key.z, key.x, key.y);
    bytes ??= DiskCachedCartoTileProvider.emptyPng;
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is _DiskCachedTileImage &&
      other.z == z &&
      other.x == x &&
      other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);
}
