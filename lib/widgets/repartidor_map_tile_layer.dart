import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:mbtiles/mbtiles.dart';

import '../config/carto_map_config.dart';
import '../services/map_tile_disk_cache.dart';
import '../services/tenant_mapa_offline_service.dart';

/// Capa base del mapa: con internet → Carto Voyager (calles modernas);
/// sin internet → MBTiles del tenant si hay cobertura.
///
/// Antes se prefería MBTiles aunque hubiera red: si el paquete no tenía
/// teselas de calle en la zona, el mapa quedaba en blanco.
class RepartidorMapTileLayer extends StatefulWidget {
  const RepartidorMapTileLayer({
    super.key,
    this.tenantId,
    this.maxZoom = 18,
    this.preferOnline = false,
  });

  final String? tenantId;
  final int maxZoom;

  /// Si true, fuerza Carto online (ignora MBTiles aunque no haya red).
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

  Future<bool> _hayRed() async {
    try {
      final r = await Connectivity().checkConnectivity();
      if (r.isEmpty) return true;
      return !r.every((e) => e == ConnectivityResult.none);
    } catch (_) {
      // Ante duda: online, para no mostrar mapa en blanco.
      return true;
    }
  }

  Future<void> _load() async {
    MbTiles? opened;
    var useOffline = false;
    var tms = false;
    try {
      final forzarOnline = widget.preferOnline || await _hayRed();
      if (!forzarOnline) {
        var tid = widget.tenantId?.trim();
        tid ??= await TenantMapaOfflineService.instance.tenantIdChofer();
        final path =
            await TenantMapaOfflineService.instance.ensureLocalMbtiles(tid);
        if (path != null && path.isNotEmpty) {
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
                '⚠️ MBTiles local sin teselas útiles → mapa online',
              );
            }
          }
        }
      } else {
        if (!CartoMapConfig.hasApiKey) {
          print(
            '⚠️ Mapa Carto sin CARTO_BASEMAP_KEY → marca de agua. '
            'Solicita clave en https://carto.com/basemaps/apikey',
          );
        }
        print('🗺️ Mapa base: Carto online (calles)');
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
    if (raw.length > 8 &&
        raw[0] == 0x89 &&
        raw[1] == 0x50 &&
        raw[2] == 0x4E &&
        raw[3] == 0x47) {
      return true;
    }
    if (raw.length > 3 && raw[0] == 0xFF && raw[1] == 0xD8) return true;
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
    final maxNative = widget.maxZoom.clamp(1, 19);
    return TileLayer(
      urlTemplate: MapTileDiskCache.urlTemplate,
      subdomains: MapTileDiskCache.subdomains,
      userAgentPackageName: MapTileDiskCache.userAgent,
      tileProvider: DiskCachedCartoTileProvider(),
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
      if (raw == null || raw.isEmpty) {
        final yAlt = (1 << z) - 1 - coordinates.y;
        raw = db.getTile(z: z, x: x, y: yAlt);
      }
      if (raw != null && raw.isNotEmpty) {
        return MemoryImage(raw);
      }
    } catch (_) {}
    return MemoryImage(emptyPng);
  }
}
