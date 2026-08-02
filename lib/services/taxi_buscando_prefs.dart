import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Preferencia local persistente: modo «Buscando viajes».
/// Sobrevive cierre/reinicio de la app; solo se apaga si el socio lo desactiva.
///
/// Si no hay red, el cambio se guarda aquí y se sincroniza a BD al volver online
/// (`pendiente_sync_disponible`).
class TaxiBuscandoPrefs {
  TaxiBuscandoPrefs._();

  static const _keyPrefix = 'taxi_buscando_viajes_activo';
  static const _keyPendientePrefix = 'taxi_disponible_pendiente_sync';

  static String _uid() =>
      Supabase.instance.client.auth.currentUser?.id ?? 'anon';

  static String _key() => '${_keyPrefix}_${_uid()}';

  static String _keyPendiente() => '${_keyPendientePrefix}_${_uid()}';

  static Future<bool> esActivo() async {
    final prefs = await SharedPreferences.getInstance();
    final keyed = prefs.getBool(_key());
    if (keyed != null) return keyed;
    return prefs.getBool(_keyPrefix) ?? false;
  }

  static Future<void> setActivo(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(), value);
    if (prefs.containsKey(_keyPrefix)) {
      await prefs.remove(_keyPrefix);
    }
  }

  /// `true`/`false` = hay que empujar ese valor a BD; `null` = nada pendiente.
  static Future<bool?> pendienteSyncDisponible() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_keyPendiente())) return null;
    return prefs.getBool(_keyPendiente());
  }

  static Future<void> marcarPendienteSyncDisponible(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyPendiente(), value);
  }

  static Future<void> limpiarPendienteSyncDisponible() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPendiente());
  }
}
