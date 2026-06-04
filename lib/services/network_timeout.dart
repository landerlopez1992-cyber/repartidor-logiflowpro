import 'dart:async';

/// Evita que pantallas queden colgadas esperando Supabase sin respuesta.
Future<T?> ejecutarConTimeout<T>(
  Future<T> futuro, {
  Duration timeout = const Duration(seconds: 22),
}) async {
  try {
    return await futuro.timeout(timeout);
  } on TimeoutException {
    print('⏱️ Operación de red cancelada por timeout (${timeout.inSeconds}s)');
    return null;
  }
}
