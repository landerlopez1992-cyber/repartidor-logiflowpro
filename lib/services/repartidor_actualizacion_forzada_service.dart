import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../main.dart';

/// Estado de actualización obligatoria desde tienda (Google Play / App Store).
class ActualizacionForzadaEstado {
  const ActualizacionForzadaEstado({
    required this.plataforma,
    required this.onda,
    required this.urlTienda,
    this.titulo = 'Nueva versión disponible',
    this.mensaje =
        'Hay una actualización obligatoria. Instala la última versión desde la tienda para continuar.',
  });

  final String plataforma; // android | ios
  final int onda;
  final String urlTienda;
  final String titulo;
  final String mensaje;
}

class RepartidorActualizacionForzadaService {
  RepartidorActualizacionForzadaService._();
  static final RepartidorActualizacionForzadaService instance =
      RepartidorActualizacionForzadaService._();

  static const _prefOndaAndroid = 'repartidor_onda_actualizacion_android';
  static const _prefOndaIos = 'repartidor_onda_actualizacion_ios';

  String? get _plataformaActual {
    if (kIsWeb) return null;
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return null;
  }

  Future<int> _ondaLocal(String plataforma) async {
    final prefs = await SharedPreferences.getInstance();
    if (plataforma == 'android') {
      return prefs.getInt(_prefOndaAndroid) ?? 0;
    }
    return prefs.getInt(_prefOndaIos) ?? 0;
  }

  Future<void> marcarTiendaAbierta({
    required String plataforma,
    required int onda,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (plataforma == 'android') {
      await prefs.setInt(_prefOndaAndroid, onda);
    } else {
      await prefs.setInt(_prefOndaIos, onda);
    }
  }

  Future<ActualizacionForzadaEstado?> consultarDesdeConfig() async {
    final plataforma = _plataformaActual;
    if (plataforma == null) return null;

    try {
      final row = await supabase
          .from('logiflow_descargas_app')
          .select(
            'onda_actualizacion_android, onda_actualizacion_ios, '
            'google_play_store_url, google_play_url, '
            'apple_store_listing_url, apple_store_url',
          )
          .eq('id', 1)
          .maybeSingle();
      if (row == null) return null;

      final ondaServidor = plataforma == 'android'
          ? _parseOnda(row['onda_actualizacion_android'])
          : _parseOnda(row['onda_actualizacion_ios']);
      if (ondaServidor <= 0) return null;

      final ondaLocal = await _ondaLocal(plataforma);
      if (ondaLocal >= ondaServidor) return null;

      final url = plataforma == 'android'
          ? _primeraUrl([
              row['google_play_store_url'],
              row['google_play_url'],
            ])
          : _primeraUrl([
              row['apple_store_listing_url'],
              row['apple_store_url'],
            ]);
      if (url == null || url.isEmpty) return null;

      return ActualizacionForzadaEstado(
        plataforma: plataforma,
        onda: ondaServidor,
        urlTienda: url,
        mensaje: plataforma == 'android'
            ? 'Hay una actualización obligatoria. Abre Google Play e instala la última versión para continuar.'
            : 'Hay una actualización obligatoria. Abre la App Store e instala la última versión para continuar.',
      );
    } catch (_) {
      return null;
    }
  }

  /// Consulta config global; si falla, usa datos de la notificación push/realtime.
  Future<ActualizacionForzadaEstado?> resolverActualizacionForzada({
    Map<String, dynamic>? notificacion,
  }) async {
    final desdeConfig = await consultarDesdeConfig();
    if (desdeConfig != null) return desdeConfig;
    if (notificacion == null) return null;

    final estado = desdeNotificacion(notificacion);
    if (estado == null) return null;

    try {
      final row = await supabase
          .from('logiflow_descargas_app')
          .select('onda_actualizacion_android, onda_actualizacion_ios')
          .eq('id', 1)
          .maybeSingle();
      if (row == null) return estado;

      final onda = estado.plataforma == 'android'
          ? _parseOnda(row['onda_actualizacion_android'])
          : _parseOnda(row['onda_actualizacion_ios']);
      if (onda <= 0) return estado;

      return ActualizacionForzadaEstado(
        plataforma: estado.plataforma,
        onda: onda,
        urlTienda: estado.urlTienda,
        titulo: estado.titulo,
        mensaje: estado.mensaje,
      );
    } catch (_) {
      return estado;
    }
  }

  ActualizacionForzadaEstado? desdeNotificacion(Map<String, dynamic> notif) {
    final plataforma = _plataformaActual;
    if (plataforma == null) return null;

    final tipo = notif['tipo']?.toString() ?? '';
    final esperado =
        plataforma == 'android' ? 'actualizacion_forzada_android' : 'actualizacion_forzada_ios';
    if (tipo != esperado) return null;

    final url = notif['url_adjunto']?.toString().trim() ?? '';
    if (url.isEmpty) return null;

    return ActualizacionForzadaEstado(
      plataforma: plataforma,
      onda: DateTime.now().millisecondsSinceEpoch,
      urlTienda: url,
      titulo: notif['titulo']?.toString() ?? 'Nueva versión disponible',
      mensaje: notif['mensaje']?.toString() ??
          'Hay una actualización obligatoria. Instala la última versión desde la tienda.',
    );
  }

  Future<bool> abrirTienda(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
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
