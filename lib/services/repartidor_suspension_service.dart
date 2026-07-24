import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../main.dart';

/// Cuenta suspendida por la empresa (`usuarios.cuenta_suspendida`).
class RepartidorSuspensionService {
  RepartidorSuspensionService._();
  static final RepartidorSuspensionService instance =
      RepartidorSuspensionService._();

  static bool esSuspendidoFlag(dynamic raw) {
    return raw == true || raw == 'true' || raw == 1;
  }

  /// Actualiza caché local para que el próximo arranque (incluso offline) bloquee.
  Future<void> marcarSuspendidoEnCache(bool suspendido) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;
      final prefs = await SharedPreferences.getInstance();
      final key = 'cached_user_data_${user.id}';
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return;
      final map = Map<String, dynamic>.from(
        jsonDecode(raw) as Map<dynamic, dynamic>,
      );
      map['cuenta_suspendida'] = suspendido;
      await prefs.setString(key, jsonEncode(map));
    } catch (_) {}
  }

  /// Consulta BD. `null` = no se pudo verificar (offline / error).
  Future<bool?> estaSuspendidoAhora() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return null;
      final row = await supabase
          .from('usuarios')
          .select('cuenta_suspendida')
          .eq('auth_id', user.id)
          .maybeSingle();
      if (row == null) {
        final email = user.email;
        if (email == null || email.isEmpty) return null;
        final byEmail = await supabase
            .from('usuarios')
            .select('cuenta_suspendida')
            .eq('email', email)
            .maybeSingle();
        if (byEmail == null) return null;
        final flag = esSuspendidoFlag(byEmail['cuenta_suspendida']);
        await marcarSuspendidoEnCache(flag);
        return flag;
      }
      final flag = esSuspendidoFlag(row['cuenta_suspendida']);
      await marcarSuspendidoEnCache(flag);
      return flag;
    } catch (_) {
      return null;
    }
  }
}
