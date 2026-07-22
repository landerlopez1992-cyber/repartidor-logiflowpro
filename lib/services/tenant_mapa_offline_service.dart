import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Descarga y cachea el MBTiles offline del tenant (mapa de zona).
class TenantMapaOfflineService {
  TenantMapaOfflineService._();
  static final instance = TenantMapaOfflineService._();

  static const _prefsShaPrefix = 'tenant_mapa_sha_';
  static const _bucket = 'tenant-mapas-offline';

  SupabaseClient get _db => Supabase.instance.client;

  /// Ruta local al `.mbtiles` si el tenant tiene mapa activo.
  /// Null = usar mapa online (OpenFreeMap / MapLibre).
  Future<String?> ensureLocalMbtiles(String? tenantId) async {
    if (kIsWeb) return null;
    final tid = (tenantId ?? '').trim();
    if (tid.isEmpty) return null;

    try {
      final res = await _db.rpc(
        'tenant_mapa_offline_get',
        params: {'p_tenant_id': tid},
      );
      if (res is! Map || res['ok'] != true || res['activo'] != true) {
        return null;
      }
      final path = res['storage_path']?.toString() ?? '';
      final sha = res['sha256']?.toString() ?? '';
      if (path.isEmpty) return null;

      final local = await _localFile(tid);
      final prefs = await SharedPreferences.getInstance();
      final cachedSha = prefs.getString('$_prefsShaPrefix$tid') ?? '';

      if (await local.exists() &&
          (sha.isEmpty || sha == cachedSha) &&
          await local.length() > 1024) {
        return local.path;
      }

      final signed = await _db.storage.from(_bucket).createSignedUrl(path, 3600);
      final resp = await http.get(Uri.parse(signed));
      if (resp.statusCode < 200 || resp.statusCode >= 300) return null;
      if (resp.bodyBytes.length < 1024) return null;

      await local.parent.create(recursive: true);
      await local.writeAsBytes(resp.bodyBytes, flush: true);
      if (sha.isNotEmpty) {
        await prefs.setString('$_prefsShaPrefix$tid', sha);
      }
      return local.path;
    } catch (_) {
      try {
        final local = await _localFile(tid);
        if (await local.exists() && await local.length() > 1024) {
          return local.path;
        }
      } catch (_) {}
      return null;
    }
  }

  Future<File> _localFile(String tenantId) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/tenant_mapas/$tenantId.mbtiles');
  }

  Future<String?> tenantIdChofer() async {
    try {
      final uid = _db.auth.currentUser?.id;
      if (uid == null) return null;
      final row = await _db
          .from('usuarios')
          .select('tenant_id')
          .eq('auth_id', uid)
          .maybeSingle();
      return row?['tenant_id']?.toString();
    } catch (_) {
      return null;
    }
  }
}
