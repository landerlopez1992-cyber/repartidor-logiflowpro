import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Preferencia local persistente: modo «Buscando viajes».
/// Sobrevive cierre/reinicio de la app; solo se apaga si el socio lo desactiva.
class TaxiBuscandoPrefs {
  TaxiBuscandoPrefs._();

  static const _keyPrefix = 'taxi_buscando_viajes_activo';

  static String _key() {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? 'anon';
    return '${_keyPrefix}_$uid';
  }

  static Future<bool> esActivo() async {
    final prefs = await SharedPreferences.getInstance();
    final keyed = prefs.getBool(_key());
    if (keyed != null) return keyed;
    // Migración: clave antigua sin user id
    return prefs.getBool(_keyPrefix) ?? false;
  }

  static Future<void> setActivo(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(), value);
    // Limpiar clave legacy
    if (prefs.containsKey(_keyPrefix)) {
      await prefs.remove(_keyPrefix);
    }
  }
}
