import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import 'store_listing_version_service.dart';

/// Aviso suave mientras se publica un build nuevo en tienda.
class RepartidorBuildPendienteInfo {
  const RepartidorBuildPendienteInfo({required this.nombreApp});

  final String nombreApp;
}

/// Estado de actualización obligatoria (tienda + refuerzo Super Admin).
class ActualizacionForzadaEstado {
  const ActualizacionForzadaEstado({
    required this.plataforma,
    required this.onda,
    required this.urlTienda,
    this.titulo = 'Nueva versión disponible',
    this.mensaje =
        'Hay una actualización obligatoria. Instala la última versión desde la tienda para continuar.',
    this.installedVersion,
    this.storePublishedVersion,
  });

  final String plataforma; // android | ios
  final int onda;
  final String urlTienda;
  final String titulo;
  final String mensaje;
  final String? installedVersion;
  final String? storePublishedVersion;
}

class RepartidorActualizacionForzadaService {
  RepartidorActualizacionForzadaService._();
  static final RepartidorActualizacionForzadaService instance =
      RepartidorActualizacionForzadaService._();

  static final ValueNotifier<ActualizacionForzadaEstado?> estado =
      ValueNotifier<ActualizacionForzadaEstado?>(null);

  static final ValueNotifier<RepartidorBuildPendienteInfo?> buildPendiente =
      ValueNotifier<RepartidorBuildPendienteInfo?>(null);

  static bool _refreshing = false;

  Future<void> refresh({bool forceStoreLookup = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      if (forceStoreLookup) {
        StoreListingVersionService.clearCache();
      }
      final res = await consultarDesdeConfig(
        forceStoreLookup: forceStoreLookup,
      );
      estado.value = res;
      buildPendiente.value = res == null ? await consultarBuildPendiente() : null;
    } catch (_) {
      estado.value = null;
      buildPendiente.value = null;
    } finally {
      _refreshing = false;
    }
  }

  static const _prefOndaAndroid = 'repartidor_onda_actualizacion_android';
  static const _prefOndaIos = 'repartidor_onda_actualizacion_ios';

  static const String _playStoreFallbackUrl =
      'https://play.google.com/store/apps/details?id=${StoreListingVersionService.androidPackageId}';

  String? get _plataformaActual {
    if (kIsWeb) return null;
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return null;
  }

  /// Android + iOS: consulta versión publicada en Play / App Store.
  bool get storeListingCheckEnabled {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  Future<int> _ondaLocal(String plataforma) async {
    final prefs = await SharedPreferences.getInstance();
    if (plataforma == 'android') {
      return prefs.getInt(_prefOndaAndroid) ?? 0;
    }
    return prefs.getInt(_prefOndaIos) ?? 0;
  }

  /// Persiste la onda solo cuando la versión instalada ya es suficiente
  /// (no al abrir la tienda sin actualizar).
  Future<void> marcarActualizacionResuelta({
    required String plataforma,
    required int onda,
  }) async {
    if (onda <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    if (plataforma == 'android') {
      await prefs.setInt(_prefOndaAndroid, onda);
    } else {
      await prefs.setInt(_prefOndaIos, onda);
    }
  }

  /// @deprecated No usar para cerrar el modal: abrir tienda ≠ haber actualizado.
  @Deprecated('Usar marcarActualizacionResuelta solo tras verificar versión')
  Future<void> marcarTiendaAbierta({
    required String plataforma,
    required int onda,
  }) async {
    // Intencionalmente vacío: no cerrar overlay al abrir la tienda.
  }

  static int compareVersions(String a, String b) {
    List<int> parts(String v) {
      return v
          .split(RegExp(r'[.\-+]'))
          .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
          .toList();
    }

    final pa = parts(a.trim());
    final pb = parts(b.trim());
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  static String normalizeInstalledVersion(String raw) =>
      StoreListingVersionService.normalizeVersion(raw);

  /// Resultado de In-App Updates de Play (null = no se pudo consultar).
  static Future<bool?> playInAppUpdateAvailableOrNull() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final info = await InAppUpdate.checkForUpdate()
          .timeout(const Duration(seconds: 12));
      return info.updateAvailability == UpdateAvailability.updateAvailable;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> playInAppUpdateAvailable() async {
    return (await playInAppUpdateAvailableOrNull()) == true;
  }

  /// ¿Bloquear? Paridad Cubalink23 + regla Android Abrir:
  /// 1) Play In-App Update disponible → sí
  /// 2) Si Play respondió “sin update” → no (ficha con Abrir; no tiene sentido forzar)
  /// 3) Ficha scrapeada más nueva → sí
  /// 4) nonce + mínima (si la mínima ya está en tienda) → sí
  /// 5) onda Super Admin (solo si Play no respondió) → sí
  static bool requiresMandatoryUpdate({
    required String installed,
    required String minVersion,
    required int nonce,
    required int ondaServidor,
    required int ondaLocal,
    String? storePublishedVersion,
    bool playUpdateAvailable = false,
    bool? playCheckSucceeded,
  }) {
    final inst = normalizeInstalledVersion(installed);
    final min = normalizeInstalledVersion(minVersion);
    final store = storePublishedVersion != null
        ? normalizeInstalledVersion(storePublishedVersion)
        : '';

    // 1) Igual Cubalink23: API oficial Play primero.
    if (playUpdateAvailable) return true;

    // 2) Play consultó OK y no hay update instalable → no bloquear
    //    (caso modal + botón Abrir). Cubalink23 no tenía este corte;
    //    en Repartidor evita el bloqueo inútil.
    if (playCheckSucceeded == true && !playUpdateAvailable) {
      return false;
    }

    // 3) Ficha pública más nueva que la instalada.
    if (store.isNotEmpty && compareVersions(inst, store) < 0) {
      return true;
    }

    // 4) Pedido panel (nonce + mínima), como Cubalink23.
    if (nonce > 0 && min.isNotEmpty) {
      if (store.isNotEmpty && compareVersions(min, store) > 0) {
        return false;
      }
      if (compareVersions(inst, min) < 0) return true;
    }

    // 5) Onda solo si no hubo respuesta clara de Play.
    if (playCheckSucceeded != true &&
        ondaServidor > 0 &&
        ondaLocal < ondaServidor) {
      return true;
    }

    return false;
  }

  bool _esUrlTiendaAndroidValida(String url) {
    final raw = url.trim();
    if (raw.isEmpty) return false;
    if (raw.startsWith('market://details')) return true;
    final u = Uri.tryParse(raw);
    if (u == null || !u.hasScheme) return false;
    final host = u.host.toLowerCase();
    if (!host.contains('play.google.com')) return false;
    final id = u.queryParameters['id']?.trim();
    return id != null && id.isNotEmpty;
  }

  bool _esUrlAppStoreValida(String url) {
    final raw = url.trim();
    if (raw.isEmpty) return false;
    final u = Uri.tryParse(raw);
    if (u == null || !u.hasScheme) return false;
    final host = u.host.toLowerCase();
    return host.contains('apps.apple.com') || host.contains('itunes.apple.com');
  }

  String _resolverUrlAndroid(String guardada) {
    if (_esUrlTiendaAndroidValida(guardada)) return guardada.trim();
    return _playStoreFallbackUrl;
  }

  Future<ActualizacionForzadaEstado?> consultarDesdeConfig({
    bool forceStoreLookup = false,
  }) async {
    final plataforma = _plataformaActual;
    if (plataforma == null) return null;

    try {
      final row = await supabase
          .from('logiflow_descargas_app')
          .select(
            'onda_actualizacion_android, onda_actualizacion_ios, '
            'google_play_store_url, google_play_url, '
            'apple_store_listing_url, apple_store_url, '
            'app_movil_update_min_version, app_movil_update_prompt_nonce, '
            'app_movil_update_build_pending_at, app_movil_ios_en_produccion',
          )
          .eq('id', 1)
          .maybeSingle();
      if (row == null) return null;

      final minVersionRaw =
          (row['app_movil_update_min_version'] ?? '').toString().trim();
      final nonce =
          (row['app_movil_update_prompt_nonce'] as num?)?.toInt() ?? 0;
      final iosEnProduccion = row['app_movil_ios_en_produccion'] != false;
      var minVersion = minVersionRaw;
      var nonceParaCheck = nonce;
      if (plataforma == 'ios' && !iosEnProduccion) {
        minVersion = '';
        nonceParaCheck = 0;
      }

      final ondaServidor = plataforma == 'android'
          ? _parseOnda(row['onda_actualizacion_android'])
          : _parseOnda(row['onda_actualizacion_ios']);

      final urlAndroidRaw = _primeraUrl([
            row['google_play_store_url'],
            row['google_play_url'],
          ]) ??
          '';
      final urlIosRaw = _primeraUrl([
            row['apple_store_listing_url'],
            row['apple_store_url'],
          ]) ??
          '';

      // iOS sin listing App Store: no bloquear.
      if (plataforma == 'ios' && !_esUrlAppStoreValida(urlIosRaw)) {
        return null;
      }

      final urlTienda = plataforma == 'android'
          ? _resolverUrlAndroid(urlAndroidRaw)
          : urlIosRaw.trim();
      if (urlTienda.isEmpty) return null;

      final info = await PackageInfo.fromPlatform();
      final installed = normalizeInstalledVersion(info.version);

      String? storePublishedVersion;
      var playUpdateAvailable = false;
      bool? playCheckSucceeded;
      if (storeListingCheckEnabled) {
        if (forceStoreLookup) {
          StoreListingVersionService.clearCache();
        }
        storePublishedVersion =
            await StoreListingVersionService.fetchPublishedVersion(
          iosStoreUrl: urlIosRaw,
          androidStoreUrl: urlTienda,
          forceRefresh: forceStoreLookup,
        );
        if (plataforma == 'android') {
          final play = await playInAppUpdateAvailableOrNull();
          playCheckSucceeded = play != null;
          playUpdateAvailable = play == true;
        }
      } else if (plataforma == 'ios' && _esUrlAppStoreValida(urlIosRaw)) {
        if (forceStoreLookup) {
          StoreListingVersionService.clearCache();
        }
        storePublishedVersion =
            await StoreListingVersionService.fetchPublishedVersion(
          iosStoreUrl: urlIosRaw,
          androidStoreUrl: urlAndroidRaw,
          forceRefresh: forceStoreLookup,
        );
      }

      final ondaLocal = await _ondaLocal(plataforma);

      // Si ya está actualizado respecto a la tienda, sincronizar onda local.
      final store = storePublishedVersion != null
          ? normalizeInstalledVersion(storePublishedVersion)
          : '';
      if (store.isNotEmpty &&
          compareVersions(installed, store) >= 0 &&
          ondaServidor > 0 &&
          ondaLocal < ondaServidor) {
        await marcarActualizacionResuelta(
          plataforma: plataforma,
          onda: ondaServidor,
        );
      }

      if (!requiresMandatoryUpdate(
        installed: installed,
        minVersion: minVersion,
        nonce: nonceParaCheck,
        ondaServidor: ondaServidor,
        ondaLocal: ondaLocal,
        storePublishedVersion: storePublishedVersion,
        playUpdateAvailable: playUpdateAvailable,
        playCheckSucceeded: playCheckSucceeded,
      )) {
        return null;
      }

      final minParaUi = minVersion.isNotEmpty
          ? minVersion
          : (storePublishedVersion ?? '');

      return ActualizacionForzadaEstado(
        plataforma: plataforma,
        onda: ondaServidor > 0 ? ondaServidor : nonce,
        urlTienda: urlTienda,
        installedVersion: installed,
        storePublishedVersion:
            storePublishedVersion ?? (minParaUi.isNotEmpty ? minParaUi : null),
        mensaje: plataforma == 'android'
            ? 'Hay una actualización obligatoria. Abre Google Play e instala la última versión para continuar.'
            : 'Hay una actualización obligatoria. Abre la App Store e instala la última versión para continuar.',
      );
    } catch (_) {
      return null;
    }
  }

  /// Evalúa tienda + onda. El push solo dispara esta consulta (no cierra el modal).
  Future<ActualizacionForzadaEstado?> resolverActualizacionForzada({
    Map<String, dynamic>? notificacion,
    bool forceStoreLookup = true,
  }) async {
    // La onda en BD ya subió con el RPC de Super Admin; no forzar solo por
    // payload del push (evita mostrar el modal si la versión ya está al día).
    final desdeConfig = await consultarDesdeConfig(
      forceStoreLookup: forceStoreLookup,
    );
    if (desdeConfig != null) return desdeConfig;

    // Respaldo: si la fila global no respondió, validar URL del push vs tienda.
    if (notificacion == null) return null;
    final provisional = desdeNotificacion(notificacion);
    if (provisional == null) return null;

    try {
      final info = await PackageInfo.fromPlatform();
      final installed = normalizeInstalledVersion(info.version);
      String? storePublished;
      var playOk = false;
      bool? playCheckSucceeded;
      if (storeListingCheckEnabled) {
        storePublished = await StoreListingVersionService.fetchPublishedVersion(
          androidStoreUrl: provisional.urlTienda,
          forceRefresh: true,
        );
        final play = await playInAppUpdateAvailableOrNull();
        playCheckSucceeded = play != null;
        playOk = play == true;
      }
      // Sin evidencia de tienda desactualizada / Play update, no bloquear.
      if (storePublished == null && !playOk) return null;
      if (!requiresMandatoryUpdate(
        installed: installed,
        minVersion: '',
        nonce: 0,
        ondaServidor: 0,
        ondaLocal: 0,
        storePublishedVersion: storePublished,
        playUpdateAvailable: playOk,
        playCheckSucceeded: playCheckSucceeded,
      )) {
        return null;
      }
      return ActualizacionForzadaEstado(
        plataforma: provisional.plataforma,
        onda: provisional.onda,
        urlTienda: provisional.urlTienda,
        titulo: provisional.titulo,
        mensaje: provisional.mensaje,
        installedVersion: installed,
        storePublishedVersion: storePublished,
      );
    } catch (_) {
      return null;
    }
  }

  ActualizacionForzadaEstado? desdeNotificacion(Map<String, dynamic> notif) {
    final plataforma = _plataformaActual;
    if (plataforma == null) return null;

    final tipo = notif['tipo']?.toString() ?? '';
    final esperado = plataforma == 'android'
        ? 'actualizacion_forzada_android'
        : 'actualizacion_forzada_ios';
    if (tipo != esperado) return null;

    // iOS sin listing: no bloquear por push.
    if (plataforma == 'ios') {
      final url = notif['url_adjunto']?.toString().trim() ?? '';
      if (!_esUrlAppStoreValida(url)) return null;
    }

    final url = notif['url_adjunto']?.toString().trim() ?? '';
    final urlFinal = plataforma == 'android'
        ? (url.isNotEmpty ? _resolverUrlAndroid(url) : _playStoreFallbackUrl)
        : url;
    if (urlFinal.isEmpty) return null;

    return ActualizacionForzadaEstado(
      plataforma: plataforma,
      onda: DateTime.now().millisecondsSinceEpoch,
      urlTienda: urlFinal,
      titulo: notif['titulo']?.toString() ?? 'Nueva versión disponible',
      mensaje: notif['mensaje']?.toString() ??
          'Hay una actualización obligatoria. Instala la última versión desde la tienda.',
    );
  }

  Future<bool> abrirTienda(String url, {bool preferInAppUpdate = true}) async {
    if (Platform.isAndroid) {
      if (preferInAppUpdate) {
        final inApp = await _intentarActualizacionInAppPlay();
        if (inApp) return true;
      }
      return _abrirTiendaAndroid(url);
    }
    if (Platform.isIOS) {
      return _abrirTiendaIos(url);
    }
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _intentarActualizacionInAppPlay() async {
    if (kIsWeb || !Platform.isAndroid) return false;
    try {
      final info = await InAppUpdate.checkForUpdate()
          .timeout(const Duration(seconds: 15));
      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return false;
      }
      if (info.immediateUpdateAllowed) {
        final result = await InAppUpdate.performImmediateUpdate();
        return result == AppUpdateResult.success ||
            result == AppUpdateResult.userDeniedUpdate;
      }
      if (info.flexibleUpdateAllowed) {
        final started = await InAppUpdate.startFlexibleUpdate();
        if (started != AppUpdateResult.success) return false;
        await InAppUpdate.completeFlexibleUpdate();
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> _abrirTiendaIos(String storeUrl) async {
    final raw = storeUrl.trim();
    final appId = RegExp(r'/id(\d+)').firstMatch(raw)?.group(1);
    if (appId != null && appId.isNotEmpty) {
      final itms = Uri.parse('itms-apps://apps.apple.com/app/id$appId');
      try {
        if (await canLaunchUrl(itms)) {
          final ok = await launchUrl(
            itms,
            mode: LaunchMode.externalApplication,
          );
          if (ok) return true;
        }
      } catch (_) {}
    }
    final httpsUri = Uri.tryParse(raw);
    if (httpsUri == null) return false;
    try {
      return await launchUrl(httpsUri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Aviso suave si hay build en preparación (paridad CubaLink23).
  Future<RepartidorBuildPendienteInfo?> consultarBuildPendiente() async {
    final plataforma = _plataformaActual;
    if (plataforma == null) return null;
    try {
      final row = await supabase
          .from('logiflow_descargas_app')
          .select(
            'app_movil_update_build_pending_at, app_movil_update_min_version',
          )
          .eq('id', 1)
          .maybeSingle();
      if (row == null) return null;

      final pendingRaw = row['app_movil_update_build_pending_at']?.toString();
      if (pendingRaw == null || pendingRaw.isEmpty) return null;

      final info = await PackageInfo.fromPlatform();
      final installed = normalizeInstalledVersion(info.version);
      final minVersion =
          (row['app_movil_update_min_version'] ?? '').toString().trim();

      if (minVersion.isNotEmpty &&
          compareVersions(installed, minVersion) >= 0) {
        return null;
      }

      final pendingAt = DateTime.parse(pendingRaw).toUtc();
      final age = DateTime.now().toUtc().difference(pendingAt);
      if (age.inHours > 48) return null;

      return const RepartidorBuildPendienteInfo(nombreApp: 'VolonexPro+');
    } catch (_) {
      return null;
    }
  }

  Future<bool> _abrirTiendaAndroid(String urlPreferida) async {
    const packageId = StoreListingVersionService.androidPackageId;
    final httpsUrl = _resolverUrlAndroid(urlPreferida);
    final marketUri = Uri.parse('market://details?id=$packageId');
    try {
      if (await canLaunchUrl(marketUri)) {
        final ok = await launchUrl(
          marketUri,
          mode: LaunchMode.externalApplication,
        );
        if (ok) return true;
      }
    } catch (_) {}

    final httpsUri = Uri.tryParse(httpsUrl);
    if (httpsUri == null) return false;
    try {
      return await launchUrl(
        httpsUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }

  int _parseOnda(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  String? _primeraUrl(List<dynamic> candidatos) {
    for (final c in candidatos) {
      final s = c?.toString().trim() ?? '';
      if (s.isNotEmpty) return s;
    }
    return null;
  }
}
