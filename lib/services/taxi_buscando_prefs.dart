import 'package:shared_preferences/shared_preferences.dart';

/// Preferencia local: socio en modo «Buscando viajes» (en espera de oferta).
class TaxiBuscandoPrefs {
  TaxiBuscandoPrefs._();

  static const _key = 'taxi_buscando_viajes_activo';

  static Future<bool> esActivo() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  static Future<void> setActivo(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
