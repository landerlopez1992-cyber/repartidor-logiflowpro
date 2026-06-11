import 'dart:async' show Timer, unawaited;
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


typedef RepartidorTelemetrySeverity = String;

/// Telemetría central VolonexPro+ — app Repartidor (cola offline + ingest).
class RepartidorTelemetryService {
  RepartidorTelemetryService._();
  static final instance = RepartidorTelemetryService._();

  static const _queueKey = 'repartidor.telemetry.queue.v1';
  static const _installationKey = 'repartidor.telemetry.installation_id';
  static const _maxQueue = 1500;
  static const _maxBatch = 60;
  static const _flushInterval = Duration(seconds: 30);
  static const _minFlushGap = Duration(seconds: 5);

  Timer? _flushTimer;
  bool _flushing = false;
  DateTime? _lastFlushAt;
  String? _sessionId;
  String? _appVersion;
  String? _tenantIdCache;
  bool _initialized = false;
  bool _globalHandlers = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _sessionId = _randomId('sess');
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = info.version;
    } catch (_) {
      _appVersion = 'unknown';
    }
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) => unawaited(flush()));
    _installGlobalHandlers();
    unawaited(flush());
    unawaited(track(
      eventType: 'rep.session.start',
      source: 'repartidorTelemetry',
      message: 'Sesión app repartidor iniciada',
      severity: 'info',
      tags: const ['session', 'repartidor'],
    ));
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  Future<void> track({
    required String eventType,
    required String source,
    required String message,
    RepartidorTelemetrySeverity severity = 'info',
    String? fingerprint,
    List<String>? tags,
    Map<String, dynamic>? context,
    String? tenantId,
  }) async {
    if (kDebugMode && severity == 'debug') return;
    final row = await _buildQueuedEvent(
      eventType: eventType,
      source: source,
      message: message,
      severity: severity,
      fingerprint: fingerprint,
      tags: tags,
      context: context,
      tenantId: tenantId,
      offlineQueued: false,
    );
    if (row == null) return;
    await _enqueue(row);
    if (severity == 'fatal' || severity == 'error') {
      unawaited(flush());
    }
  }

  Future<void> trackError({
    required String source,
    required String message,
    String eventType = 'rep.error',
    String? fingerprint,
    Map<String, dynamic>? context,
    String? tenantId,
  }) {
    return track(
      eventType: eventType,
      source: source,
      message: message,
      severity: 'error',
      fingerprint: fingerprint,
      tags: const ['error', 'repartidor'],
      context: context,
      tenantId: tenantId,
    );
  }

  Future<void> flush() async {
    if (_flushing) return;
    final now = DateTime.now();
    if (_lastFlushAt != null && now.difference(_lastFlushAt!) < _minFlushGap) {
      return;
    }
    _flushing = true;
    _lastFlushAt = now;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_queueKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (list.isEmpty) return;

      final batch = list.take(_maxBatch).toList();
      final res = await Supabase.instance.client.functions.invoke(
        'logiflow-telemetry-ingest',
        body: {
          'batch_id': _randomId('batch'),
          'events': batch,
        },
      );
      if (res.status != 200) {
        final marked = batch
            .map((e) => {...e, 'offline_queued': true})
            .toList();
        final rest = list.skip(_maxBatch).toList();
        await prefs.setString(_queueKey, jsonEncode([...marked, ...rest]));
        return;
      }
      final remaining = list.skip(_maxBatch).toList();
      if (remaining.isEmpty) {
        await prefs.remove(_queueKey);
      } else {
        await prefs.setString(_queueKey, jsonEncode(remaining));
      }
    } catch (e) {
      debugPrint('⚠️ repartidor_telemetry flush: $e');
    } finally {
      _flushing = false;
    }
  }

  void onFlutterError(FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (!kDebugMode) {
      unawaited(trackError(
        source: details.library ?? 'flutter',
        message: details.exceptionAsString().length > 800
            ? details.exceptionAsString().substring(0, 800)
            : details.exceptionAsString(),
        fingerprint: 'rep:flutter:${details.library}',
        context: {
          if (details.stack != null)
            'stack_trace': details.stack.toString().length > 1200
                ? details.stack.toString().substring(0, 1200)
                : details.stack.toString(),
        },
      ));
    }
  }

  bool onPlatformError(Object error, StackTrace stack) {
    if (!kDebugMode) {
      unawaited(trackError(
        source: 'platform',
        message: error.toString().length > 800
            ? error.toString().substring(0, 800)
            : error.toString(),
        fingerprint: 'rep:platform:${error.runtimeType}',
        context: {
          'stack_trace': stack.toString().length > 1200
              ? stack.toString().substring(0, 1200)
              : stack.toString(),
        },
      ));
    }
    return false;
  }

  void _installGlobalHandlers() {
    if (_globalHandlers) return;
    _globalHandlers = true;
    FlutterError.onError = onFlutterError;
    PlatformDispatcher.instance.onError = onPlatformError;
  }

  Future<Map<String, dynamic>?> _buildQueuedEvent({
    required String eventType,
    required String source,
    required String message,
    required RepartidorTelemetrySeverity severity,
    String? fingerprint,
    List<String>? tags,
    Map<String, dynamic>? context,
    String? tenantId,
    required bool offlineQueued,
  }) async {
    final msg = _sanitize(message);
    if (msg.isEmpty) return null;
    final tid = tenantId ?? await _resolveTenantId();
    if (tid == null || tid.isEmpty) return null;
    final installationId = await _installationId();
    return {
      'client_event_id': _randomId('evt'),
      'event_at': DateTime.now().toUtc().toIso8601String(),
      'session_id': _sessionId ?? _randomId('sess'),
      'installation_id': installationId,
      'tenant_id': tid,
      'app_version': _appVersion ?? 'unknown',
      'release_channel': 'repartidor',
      'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
      'locale': 'es',
      'event_type': eventType,
      'severity': severity,
      'source': _sanitize(source, maxLen: 80),
      'message': msg,
      if (fingerprint != null) 'fingerprint': _sanitize(fingerprint, maxLen: 160),
      'tags': (tags ?? const []).map((t) => _sanitize(t, maxLen: 40)).toList(),
      'context': _sanitizeContext(context),
      'offline_queued': offlineQueued,
    };
  }

  Future<void> _enqueue(Map<String, dynamic> row) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    final list = raw == null || raw.isEmpty
        ? <Map<String, dynamic>>[]
        : (jsonDecode(raw) as List<dynamic>)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
    list.add(row);
    while (list.length > _maxQueue) {
      list.removeAt(0);
    }
    await prefs.setString(_queueKey, jsonEncode(list));
  }

  Future<String> _installationId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_installationKey);
    if (existing != null && existing.length >= 8) return existing;
    final next = _randomId('inst');
    await prefs.setString(_installationKey, next);
    return next;
  }

  Future<String?> _resolveTenantId() async {
    if (_tenantIdCache != null && _tenantIdCache!.isNotEmpty) {
      return _tenantIdCache;
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('cached_tenant_id_${user.id}');
      if (cached != null && cached.isNotEmpty) {
        _tenantIdCache = cached;
        return cached;
      }
    } catch (_) {}

    try {
      final row = await Supabase.instance.client
          .from('usuarios')
          .select('tenant_id')
          .eq('auth_id', user.id)
          .maybeSingle();
      final tid = row?['tenant_id']?.toString();
      if (tid != null && tid.isNotEmpty) {
        _tenantIdCache = tid;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_tenant_id_${user.id}', tid);
      }
      return tid;
    } catch (_) {
      return null;
    }
  }

  void invalidateTenantCache() => _tenantIdCache = null;

  String _randomId(String prefix) =>
      '${prefix}_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}_${identityHashCode(this).toRadixString(36)}';

  String _sanitize(String input, {int maxLen = 4000}) {
    var s = input.trim();
    if (s.isEmpty) return '';
    s = s
        .replaceAll(
          RegExp(r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', caseSensitive: false),
          '[email]',
        )
        .replaceAll(RegExp(r'\b(?:sk_(?:live|test)_[A-Za-z0-9_]+|eyJ[A-Za-z0-9._-]+)\b'), '[secret]')
        .replaceAll(RegExp(r'\b(?:https?://|www\.)[^\s]+', caseSensitive: false), '[link]');
    return s.length > maxLen ? s.substring(0, maxLen) : s;
  }

  Map<String, dynamic> _sanitizeContext(Map<String, dynamic>? ctx) {
    if (ctx == null || ctx.isEmpty) return {};
    final out = <String, dynamic>{};
    for (final e in ctx.entries.take(40)) {
      final k = _sanitize(e.key, maxLen: 80);
      if (k.isEmpty) continue;
      if (RegExp(r'token|secret|password|authorization|apikey', caseSensitive: false).hasMatch(k)) {
        out[k] = '[secret]';
      } else if (e.value is String) {
        out[k] = _sanitize(e.value as String, maxLen: 1200);
      } else if (e.value is num || e.value is bool) {
        out[k] = e.value;
      } else {
        out[k] = _sanitize(e.value.toString(), maxLen: 600);
      }
    }
    return out;
  }
}
