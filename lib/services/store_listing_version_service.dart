import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// Lee la versión publicada en Google Play / App Store.
class StoreListingVersionService {
  StoreListingVersionService._();

  /// Package id de la app Repartidor en Play.
  static const String androidPackageId = 'com.logiflowpro.repartidor';

  static const Duration _cacheTtl = Duration(minutes: 10);
  static const Duration _timeout = Duration(seconds: 8);

  static String? _cachedVersion;
  static DateTime? _cachedAt;
  static String? _cacheKey;

  static String normalizeVersion(String raw) {
    var v = raw.trim();
    if (v.isEmpty) return '';
    final plus = v.indexOf('+');
    if (plus > 0) v = v.substring(0, plus);
    final space = v.indexOf(' ');
    if (space > 0) v = v.substring(0, space);
    return v.trim();
  }

  /// Versión publicada en la tienda de la plataforma actual. `null` si no se pudo leer.
  static Future<String?> fetchPublishedVersion({
    String? iosStoreUrl,
    String? androidStoreUrl,
    bool forceRefresh = false,
  }) async {
    if (kIsWeb) return null;
    if (Platform.isMacOS) return null;

    final key = Platform.isAndroid
        ? 'and:${androidStoreUrl ?? ''}:$androidPackageId'
        : 'ios:${iosStoreUrl ?? ''}:$androidPackageId';

    if (!forceRefresh &&
        _cacheKey == key &&
        _cachedVersion != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _cacheTtl) {
      return _cachedVersion;
    }

    String? version;
    try {
      if (Platform.isAndroid) {
        version = await _fetchPlayStoreVersion(androidStoreUrl);
      } else if (Platform.isIOS) {
        version = await _fetchAppStoreVersion(iosStoreUrl);
      }
    } catch (_) {
      version = null;
    }

    final normalized = version != null ? normalizeVersion(version) : null;
    if (normalized != null && normalized.isNotEmpty) {
      _cacheKey = key;
      _cachedVersion = normalized;
      _cachedAt = DateTime.now();
    }
    return normalized;
  }

  static void clearCache() {
    _cachedVersion = null;
    _cachedAt = null;
    _cacheKey = null;
  }

  static Future<String?> _fetchPlayStoreVersion(String? storeUrl) async {
    final packageId = _playPackageId(storeUrl) ?? androidPackageId;
    if (packageId.isEmpty) return null;

    final uri = Uri.parse(
      'https://play.google.com/store/apps/details?id=$packageId&hl=en&gl=US',
    );
    final res = await http
        .get(
          uri,
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
            'Accept-Language': 'en-US,en;q=0.9',
          },
        )
        .timeout(_timeout);

    if (res.statusCode != 200) return null;
    return _parsePlayStoreVersion(res.body);
  }

  static String? _playPackageId(String? storeUrl) {
    final raw = (storeUrl ?? '').trim();
    if (raw.isEmpty) return null;
    final u = Uri.tryParse(raw);
    if (u == null) return null;
    final id = u.queryParameters['id']?.trim();
    return (id != null && id.isNotEmpty) ? id : null;
  }

  static String? _parsePlayStoreVersion(String html) {
    final patterns = <RegExp>[
      RegExp(r'"softwareVersion"\s*:\s*"([^"]+)"'),
      RegExp(r'\[\[\["([\d]+(?:\.[\d]+){0,3})"\]\]'),
      RegExp(r'Current Version</div>.*?>([\d.]+)<', dotAll: true),
      RegExp(r'itemprop="softwareVersion"[^>]*content="([^"]+)"'),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(html);
      if (m == null) continue;
      final v = normalizeVersion(m.group(1) ?? '');
      if (v.isNotEmpty && RegExp(r'^\d').hasMatch(v)) return v;
    }
    return null;
  }

  static Future<String?> _fetchAppStoreVersion(String? storeUrl) async {
    final appId = _appStoreNumericId(storeUrl);
    if (appId == null) return null;

    final uri =
        Uri.parse('https://itunes.apple.com/lookup?id=$appId&country=us');
    final res = await http.get(uri).timeout(_timeout);
    if (res.statusCode != 200) return null;
    return _parseItunesVersion(res.body);
  }

  static String? _appStoreNumericId(String? storeUrl) {
    final raw = (storeUrl ?? '').trim();
    if (raw.isEmpty) return null;
    final m = RegExp(r'/id(\d+)').firstMatch(raw);
    return m?.group(1);
  }

  static String? _parseItunesVersion(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is! Map) return null;
      final results = decoded['results'];
      if (results is! List || results.isEmpty) return null;
      final first = results.first;
      if (first is! Map) return null;
      final v = first['version']?.toString();
      if (v == null || v.trim().isEmpty) return null;
      return normalizeVersion(v);
    } catch (_) {
      return null;
    }
  }
}
