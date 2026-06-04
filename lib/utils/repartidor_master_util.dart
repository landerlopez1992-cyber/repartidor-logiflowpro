import 'package:shared_preferences/shared_preferences.dart';

/// Lectura y caché del flag [usuarios.repartidor_master].
class RepartidorMasterUtil {
  RepartidorMasterUtil._();

  static String cacheKey(String authUserId) => 'cached_repartidor_master_$authUserId';

  static bool parseFlag(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 't' || s == 'yes' || s == 'si';
  }

  static Future<bool?> loadCached(String authUserId) async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(cacheKey(authUserId))) return null;
    return prefs.getBool(cacheKey(authUserId));
  }

  static Future<void> saveCached(String authUserId, bool esMaster) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(cacheKey(authUserId), esMaster);
  }
}
