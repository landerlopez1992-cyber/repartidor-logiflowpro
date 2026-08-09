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
    final d = await detalleSuspensionAhora();
    return d?.suspendido;
  }

  /// Incluye motivo (p. ej. auto por viajes ignorados).
  Future<({bool suspendido, String? motivo})?> detalleSuspensionAhora() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return null;
      Map<String, dynamic>? row = await supabase
          .from('usuarios')
          .select('cuenta_suspendida, cuenta_suspendida_motivo')
          .eq('auth_id', user.id)
          .maybeSingle();
      if (row == null) {
        final email = user.email;
        if (email == null || email.isEmpty) return null;
        row = await supabase
            .from('usuarios')
            .select('cuenta_suspendida, cuenta_suspendida_motivo')
            .eq('email', email)
            .maybeSingle();
        if (row == null) return null;
      }
      final flag = esSuspendidoFlag(row['cuenta_suspendida']);
      await marcarSuspendidoEnCache(flag);
      final motivo = row['cuenta_suspendida_motivo']?.toString().trim();
      return (
        suspendido: flag,
        motivo: (motivo == null || motivo.isEmpty) ? null : motivo,
      );
    } catch (_) {
      return null;
    }
  }
}
