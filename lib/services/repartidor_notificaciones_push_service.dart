import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Evita repetir push/vibración al reiniciar la app para notificaciones ya existentes.
/// La fuente de verdad de "leída" sigue siendo `leida` en Supabase.
class RepartidorNotificacionesPushService {
  RepartidorNotificacionesPushService._();
  static final RepartidorNotificacionesPushService instance =
      RepartidorNotificacionesPushService._();

  static const int _maxIdsGuardados = 500;
  static const String _keyIds = 'repartidor_notif_push_ids';
  static const String _keyRepartidor = 'repartidor_notif_push_repartidor_id';

  String? _repartidorId;
  Set<String> _idsMostrados = {};

  Future<void> initForRepartidor(String repartidorId) async {
    if (repartidorId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final guardado = prefs.getString(_keyRepartidor);
    if (guardado != repartidorId) {
      await prefs.remove(_keyIds);
      await prefs.setString(_keyRepartidor, repartidorId);
      _idsMostrados = {};
    } else {
      _idsMostrados = _leerIds(prefs);
    }
    _repartidorId = repartidorId;
  }

  bool yaSeMostroPushLocal(String notificacionId) {
    if (notificacionId.isEmpty) return false;
    return _idsMostrados.contains(notificacionId);
  }

  /// Al abrir la app: las no leídas existentes no deben volver a vibrar/sonar.
  Future<void> marcarExistentesSinPush(Iterable<String> notificacionIds) async {
    if (notificacionIds.isEmpty) return;
    var cambio = false;
    for (final id in notificacionIds) {
      if (id.isEmpty) continue;
      if (_idsMostrados.add(id)) cambio = true;
    }
    if (cambio) await _persistir();
  }

  Future<void> marcarPushMostrado(String notificacionId) async {
    if (notificacionId.isEmpty) return;
    if (_idsMostrados.add(notificacionId)) {
      await _persistir();
    }
  }

  Future<void> limpiarAlCerrarSesion() async {
    _repartidorId = null;
    _idsMostrados = {};
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyIds);
    await prefs.remove(_keyRepartidor);
  }

  Set<String> _leerIds(SharedPreferences prefs) {
    final raw = prefs.getString(_keyIds);
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).where((id) => id.isNotEmpty).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _persistir() async {
    final prefs = await SharedPreferences.getInstance();
    var lista = _idsMostrados.toList();
    if (lista.length > _maxIdsGuardados) {
      lista = lista.sublist(lista.length - _maxIdsGuardados);
      _idsMostrados = lista.toSet();
    }
    await prefs.setString(_keyIds, jsonEncode(lista));
    if (_repartidorId != null) {
      await prefs.setString(_keyRepartidor, _repartidorId!);
    }
  }
}
