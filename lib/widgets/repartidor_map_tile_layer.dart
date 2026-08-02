import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:mbtiles/mbtiles.dart';

import '../services/map_tile_disk_cache.dart';
import '../services/tenant_mapa_offline_service.dart';

/// Capa base del mapa: MBTiles del tenant (si es usable) o Carto online.
///
/// Si el MBTiles no tiene teselas en la zona / esquema incorrecto, cae a red
/// para no dejar el mapa en blanco.
class RepartidorMapTileLayer extends StatefulWidget {
  const RepartidorMapTileLayer({
    super.key,
    this.tenantId,
    this.maxZoom = 16,
    this.preferOnline = false,
  });

  final String? tenantId;
  final int maxZoom;

  /// Si true, usa Carto online (útil en zoom calle cuando el MBTiles no cubre).
  final bool preferOnline;

  @override
  State<RepartidorMapTileLayer> createState() => _RepartidorMapTileLayerState();
}

class _RepartidorMapTileLayerState extends State<RepartidorMapTileLayer> {
  MbTiles? _mbtiles;
  bool _ready = false;
  bool _useMbtiles = false;
  bool _tmsY = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant RepartidorMapTileLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tenantId != widget.tenantId ||
        oldWidget.preferOnline != widget.preferOnline) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    MbTiles? opened;
    var useOffline = false;
    var tms = false;
    try {
      if (!widget.preferOnline) {
        var tid = widget.tenantId?.trim();
        tid ??= await TenantMapaOfflineService.instance.tenantIdChofer();
        final path =
            await TenantMapaOfflineService.instance.ensureLocalMbtiles(tid);
        if (path != null && path.isNotEmpty) {
          // La mayoría de MBTiles guardan PNG gzip; si falla, reintentar sin gzip.
          opened = await _abrirMbtilesUsable(path);
          if (opened != null) {
            final probe = _probeEsquema(opened);
            if (probe.ok) {
              useOffline = true;
              tms = probe.tms;
            } else {
              try {
                opened.close();
              } catch (_) {}
              opened = null;
              print(
                '⚠️ MBTiles local sin teselas útiles en la zona → mapa online',
              );
            }
          }
        }
      }
    } catch (e) {
      print('⚠️ RepartidorMapTileLayer MBTiles: $e');
      try {
        opened?.close();
      } catch (_) {}
      opened = null;
      useOffline = false;
    }

    if (!mounted) {
      try {
        opened?.close();
      } catch (_) {}
      return;
    }

    try {
      _mbtiles?.close();
    } catch (_) {}

    setState(() {
      _mbtiles = opened;
      _useMbtiles = useOffline && opened != null;
      _tmsY = tms;
      _ready = true;
    });
  }

  Future<MbTiles?> _abrirMbtilesUsable(String path) async {
    for (final gzip in [true, false]) {
      try {
        final db = MbTiles(path: path, gzip: gzip);
        final probe = _probeEsquema(db);
        if (probe.ok) return db;
        try {
          db.close();
        } catch (_) {}
      } catch (_) {}
    }
    return null;
  }

  /// Comprueba si hay tiles reales cerca de Cuba (y XYZ vs TMS).
  ({bool ok, bool tms}) _probeEsquema(MbTiles db) {
    const lat = 23.12;
    const lon = -82.38;
    for (final z in [6, 8, 10, 12]) {
      final x = _lon2tileX(lon, z);
      final yXyz = _lat2tileY(lat, z);
      final yTms = (1 << z) - 1 - yXyz;
      for (final tms in [false, true]) {
        final y = tms ? yTms : yXyz;
        try {
          final raw = db.getTile(z: z, x: x, y: y);
          if (raw != null && raw.length > 200 && _pareceImagen(raw)) {
            return (ok: true, tms: tms);
          }
        } catch (_) {}
      }
    }
    return (ok: false, tms: false);
  }

  static bool _pareceImagen(Uint8List raw) {
    // PNG
    if (raw.length > 8 &&
        raw[0] == 0x89 &&
        raw[1] == 0x50 &&
        raw[2] == 0x4E &&
        raw[3] == 0x47) {
      return true;
    }
    // JPEG
    if (raw.length > 3 && raw[0] == 0xFF && raw[1] == 0xD8) return true;
    // WebP
    if (raw.length > 12 &&
        raw[0] == 0x52 &&
        raw[1] == 0x49 &&
        raw[2] == 0x46 &&
        raw[3] == 0x46) {
      return true;
    }
    return false;
  }

  static int _lon2tileX(double lon, int z) =>
      ((lon + 180.0) / 360.0 * (1 << z)).floor();

  static int _lat2tileY(double lat, int z) {
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

  @override
  void dispose() {
    try {
      _mbtiles?.close();
    } catch (_) {}
    super.dispose();
  }

  TileLayer _capaOnline() {
    final maxZ = widget.maxZoom.toDouble();
    final maxNative = widget.maxZoom;
    // NetworkTileProvider nativo de flutter_map (fiable en macOS/iOS/Android).
    return TileLayer(
      urlTemplate: MapTileDiskCache.urlTemplate,
      subdomains: MapTileDiskCache.subdomains,
      userAgentPackageName: MapTileDiskCache.userAgent,
      maxZoom: maxZ,
      maxNativeZoom: maxNative,
      retinaMode: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return _capaOnline();
    }

    if (_useMbtiles && _mbtiles != null) {
      return TileLayer(
        tileProvider: MbtilesMapTileProvider(_mbtiles!, tmsY: _tmsY),
        userAgentPackageName: MapTileDiskCache.userAgent,
        maxZoom: widget.maxZoom.toDouble(),
        maxNativeZoom: widget.maxZoom,
      );
    }

    return _capaOnline();
  }
}

/// Provider de teselas desde un archivo `.mbtiles` local.
class MbtilesMapTileProvider extends TileProvider {
  MbtilesMapTileProvider(this.db, {this.tmsY = false});

  final MbTiles db;
  final bool tmsY;

  static final Uint8List emptyPng = DiskCachedCartoTileProvider.emptyPng;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    try {
      final z = coordinates.z;
      final x = coordinates.x;
      var y = coordinates.y;
      if (tmsY) {
        y = (1 << z) - 1 - y;
      }
      var raw = db.getTile(z: z, x: x, y: y);
      // Fallback al otro esquema si el probe no coincidió en este zoom.
      if (raw == null || raw.isEmpty) {
        final yAlt = (1 << z) - 1 - coordinates.y;
        raw = db.getTile(z: z, x: x, y: yAlt);
      }
      if (raw != null && raw.isNotEmpty) {
        return MemoryImage(raw);
      }
    } catch (_) {}
    // Transparente: deja ver el fondo; no tapa con “blanco sólido” engañoso.
    return MemoryImage(emptyPng);
  }
}
