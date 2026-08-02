import 'dart:async';
import 'dart:io' show InternetAddress, SocketException;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Comprobación de red y diálogos (mismo patrón visual/UX que CubaLink23).
class RepartidorConnectivity {
  RepartidorConnectivity._();

  /// Estado observado (null = aún no comprobado).
  static final ValueNotifier<bool?> online = ValueNotifier<bool?>(null);

  static DateTime? _lastProbeAt;
  static bool? _lastProbeResult;
  static const _probeTtl = Duration(seconds: 20);

  static Timer? _watchTimer;
  static bool _modalShowing = false;
  static bool _autoOfflineModalEnabled = true;
  static DateTime? _lastAutoOfflineModalAt;

  static int _consecutiveFailures = 0;
  static const _failuresToMarkOffline = 3;

  static GlobalKey<NavigatorState>? _navigatorKey;

  static bool pendingOfflineStatusModal = false;

  static void startWatching({
    Duration interval = const Duration(seconds: 20),
  }) {
    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(interval, (_) {
      unawaited(hasInternet());
    });
    unawaited(hasInternet());
  }

  static void stopWatching() {
    _watchTimer?.cancel();
    _watchTimer = null;
  }

  static bool consumePendingOfflineStatusModal() {
    if (!pendingOfflineStatusModal) return false;
    pendingOfflineStatusModal = false;
    return true;
  }

  static void bindNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  static Future<bool> hasInternetForSplash() async {
    final ok = await _probeOnceFast();
    _lastProbeAt = DateTime.now();
    if (ok) {
      _consecutiveFailures = 0;
      _lastProbeResult = true;
      if (online.value != true) online.value = true;
    } else {
      _consecutiveFailures = _failuresToMarkOffline;
      _lastProbeResult = false;
      if (online.value != false) online.value = false;
      pendingOfflineStatusModal = true;
    }
    return ok;
  }

  static Future<bool> _probeOnceFast() async {
    if (kIsWeb) {
      try {
        final res = await http
            .head(Uri.parse('https://www.google.com/generate_204'))
            .timeout(const Duration(seconds: 2));
        return res.statusCode >= 200 && res.statusCode < 500;
      } catch (_) {
        return false;
      }
    }

    try {
      final result = await InternetAddress.lookup('dns.google')
          .timeout(const Duration(seconds: 2));
      if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
        return true;
      }
    } catch (_) {}

    try {
      final res = await http
          .get(Uri.parse('https://clients3.google.com/generate_204'))
          .timeout(const Duration(seconds: 2));
      return res.statusCode == 204 ||
          (res.statusCode >= 200 && res.statusCode < 500);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> hasInternet({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastProbeResult != null &&
        _lastProbeAt != null &&
        now.difference(_lastProbeAt!) < _probeTtl) {
      return _lastProbeResult!;
    }
    final okRaw = await _probeOnce();
    _lastProbeAt = DateTime.now();

    bool ok;
    if (okRaw) {
      _consecutiveFailures = 0;
      ok = true;
    } else {
      _consecutiveFailures++;
      if (_lastProbeResult == true &&
          _consecutiveFailures < _failuresToMarkOffline) {
        ok = true;
      } else if (_lastProbeResult == null &&
          _consecutiveFailures < _failuresToMarkOffline) {
        ok = true;
      } else {
        ok = false;
      }
    }

    final was = _lastProbeResult;
    _lastProbeResult = ok;
    if (online.value != ok) online.value = ok;

    if (_autoOfflineModalEnabled &&
        was == true &&
        ok == false &&
        !_modalShowing) {
      final last = _lastAutoOfflineModalAt;
      if (last == null ||
          DateTime.now().difference(last) > const Duration(minutes: 2)) {
        _lastAutoOfflineModalAt = DateTime.now();
        final nav = _navigatorKey?.currentState;
        final ctx = nav?.overlay?.context ?? nav?.context;
        if (ctx != null && ctx.mounted) {
          unawaited(showOfflineStatusModal(ctx));
        }
      }
    }
    return ok;
  }

  static Future<bool> _probeOnce() async {
    if (kIsWeb) {
      try {
        final res = await http
            .head(Uri.parse('https://www.google.com/generate_204'))
            .timeout(const Duration(seconds: 5));
        return res.statusCode >= 200 && res.statusCode < 500;
      } catch (_) {
        return false;
      }
    }

    for (final host in ['one.one.one.one', 'dns.google']) {
      try {
        final result = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 3));
        if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
          return true;
        }
      } on SocketException {
      } on TimeoutException {
      } catch (_) {}
    }

    try {
      final res = await http
          .get(Uri.parse('https://clients3.google.com/generate_204'))
          .timeout(const Duration(seconds: 4));
      return res.statusCode == 204 ||
          (res.statusCode >= 200 && res.statusCode < 500);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> refreshOnline() => hasInternet(force: true);

  static Future<bool> ensureOnlineOrBlock(
    BuildContext context, {
    required String accion,
  }) async {
    if (await hasInternet()) return true;
    if (await hasInternet(force: true)) return true;
    if (!context.mounted) return false;
    await showOfflineOperationBlocked(context, accion: accion);
    return false;
  }

  /// Modal online (mismo diseño que CubaLink23).
  static Future<void> showOnlineStatusModal(BuildContext context) async {
    if (!context.mounted || _modalShowing) return;
    _modalShowing = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (dialogContext) {
          final media = MediaQuery.of(dialogContext);
          final maxH = media.size.height * 0.88;
          final landscape = media.size.width > media.size.height;

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 400, maxHeight: maxH),
              child: Material(
                color: const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(22),
                clipBehavior: Clip.antiAlias,
                elevation: 12,
                shadowColor: Colors.black26,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    22,
                    landscape ? 16 : 24,
                    22,
                    18,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: landscape ? 64 : 88,
                        height: landscape ? 64 : 88,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF455A64),
                              Color(0xFF37474F),
                              Color(0xFF263238),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF37474F)
                                  .withValues(alpha: 0.28),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.wifi_rounded,
                          color: Colors.white,
                          size: landscape ? 32 : 42,
                        ),
                      ),
                      SizedBox(height: landscape ? 10 : 14),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE0E0E0)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.check_circle_rounded,
                              size: 14,
                              color: Color(0xFF37474F),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Conectado',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF37474F),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: landscape ? 10 : 14),
                      const Text(
                        'Conexión a internet activa',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2C2C2C),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Tu dispositivo está en línea. Puedes ver órdenes, '
                        'entregar y sincronizar con normalidad.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: Color(0xFF666666),
                        ),
                      ),
                      SizedBox(height: landscape ? 14 : 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF9800),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Entendido',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    } finally {
      _modalShowing = false;
    }
  }

  /// Modal sin internet (mismo diseño que CubaLink23).
  static Future<void> showOfflineStatusModal(BuildContext context) async {
    if (!context.mounted || _modalShowing) return;
    _modalShowing = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        builder: (dialogContext) {
          final media = MediaQuery.of(dialogContext);
          final maxH = media.size.height * 0.88;
          final landscape = media.size.width > media.size.height;
          final iconSize = landscape ? 72.0 : 120.0;

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 400, maxHeight: maxH),
              child: Material(
                color: const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(22),
                clipBehavior: Clip.antiAlias,
                elevation: 12,
                shadowColor: Colors.black26,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    22,
                    landscape ? 16 : 24,
                    22,
                    18,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: iconSize,
                        height: iconSize,
                        child: Image.asset(
                          'assets/images/connectivity_offline_3d.png',
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3E0),
                              borderRadius: BorderRadius.circular(28),
                            ),
                            child: Icon(
                              Icons.wifi_off_rounded,
                              color: const Color(0xFFFF9800),
                              size: landscape ? 36 : 52,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: landscape ? 6 : 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle,
                                size: 8, color: Color(0xFFDC2626)),
                            SizedBox(width: 6),
                            Text(
                              'Sin conexión',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: landscape ? 10 : 14),
                      const Text(
                        'La app está sin internet',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF2C2C2C),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Algunos o casi todos los servicios se verán afectados '
                        'hasta que se restablezca la conexión Wi‑Fi o de datos móviles.\n\n'
                        'Puedes seguir trabajando con lo que ya está guardado en el '
                        'dispositivo; al volver la red se sincronizará automáticamente. '
                        'Tu sesión no se cierra por quedarte sin red.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.45,
                          color: Color(0xFF666666),
                        ),
                      ),
                      SizedBox(height: landscape ? 14 : 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF9800),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Entendido',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          Navigator.pop(dialogContext);
                          await refreshOnline();
                        },
                        child: const Text(
                          'Reintentar conexión',
                          style: TextStyle(
                            color: Color(0xFF666666),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    } finally {
      _modalShowing = false;
    }
  }

  static Future<void> showOfflineOperationBlocked(
    BuildContext context, {
    required String accion,
  }) async {
    if (!context.mounted) return;
    final accionNorm = accion.trim().isEmpty ? 'continuar' : accion.trim();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (dialogContext) {
        final media = MediaQuery.of(dialogContext);
        final maxH = media.size.height * 0.88;
        final landscape = media.size.width > media.size.height;
        final iconSize = landscape ? 56.0 : 72.0;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 400, maxHeight: maxH),
            child: Material(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  landscape ? 14 : 22,
                  20,
                  16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: iconSize,
                      height: iconSize,
                      child: Image.asset(
                        'assets/images/connectivity_offline_3d.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF3E0),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.wifi_off_rounded,
                            color: Color(0xFFFF9800),
                            size: 30,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: landscape ? 10 : 14),
                    const Text(
                      'Sin conexión a internet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2C2C2C),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No podemos proseguir con «$accionNorm» porque este '
                      'dispositivo no tiene conexión a internet.\n\n'
                      'Puedes seguir con lo que ya está guardado en la app. '
                      'Cuando vuelva el Wi‑Fi o los datos móviles, inténtalo de nuevo.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: Color(0xFF666666),
                      ),
                    ),
                    SizedBox(height: landscape ? 12 : 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF9800),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Entendido',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
