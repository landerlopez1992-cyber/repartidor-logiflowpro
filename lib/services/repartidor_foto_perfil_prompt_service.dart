import 'package:shared_preferences/shared_preferences.dart';

/// Controla cada cuánto mostrar el aviso para subir foto de perfil.
class RepartidorFotoPerfilPromptService {
  RepartidorFotoPerfilPromptService._();

  static const Duration intervalo = Duration(days: 2);
  static const String _prefsPrefix = 'foto_perfil_prompt_last_';

  static String _key(String authUserId) => '$_prefsPrefix$authUserId';

  /// `true` si no hay foto y ya pasaron ≥ 2 días desde el último aviso (o nunca).
  static Future<bool> debeMostrar({
    required String authUserId,
    required bool tieneFoto,
  }) async {
    if (authUserId.isEmpty || tieneFoto) return false;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(authUserId));
    if (raw == null || raw.isEmpty) return true;
    final last = DateTime.tryParse(raw);
    if (last == null) return true;
    return DateTime.now().difference(last) >= intervalo;
  }

  static Future<void> marcarMostrada(String authUserId) async {
    if (authUserId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(authUserId), DateTime.now().toIso8601String());
  }
}
