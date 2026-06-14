import 'package:supabase_flutter/supabase_flutter.dart';

/// Mensajes legibles para repartidores (sin detalles técnicos ni datos de otras empresas).
String mensajeErrorOperacion(Object error, {String? contexto}) {
  if (error is PostgrestException) {
    return _desdePostgrest(error, contexto: contexto);
  }
  if (error is AuthException) {
    return _desdeAuth(error);
  }
  return _desdeTexto(error.toString(), contexto: contexto);
}

String _etiquetaContexto(String? contexto) {
  switch (contexto) {
    case 'orden':
      return 'la orden';
    case 'imagen':
      return 'la imagen';
    case 'chat':
      return 'el mensaje';
    case 'ubicacion':
      return 'la ubicación';
    default:
      return 'la operación';
  }
}

String _mensajeGenerico(String? contexto) {
  final cosa = _etiquetaContexto(contexto);
  return 'No se pudo completar $cosa. Inténtalo de nuevo.';
}

bool _textoEsTecnico(String s) {
  final m = s.toLowerCase();
  return m.contains('postgrest') ||
      m.contains('supabase') ||
      m.contains('pgrst') ||
      m.contains('row-level') ||
      m.contains('violates') ||
      m.contains('constraint') ||
      m.contains('foreign key') ||
      m.contains('tenant_id') ||
      m.contains('exception') ||
      m.contains('stack') ||
      m.contains('rls') ||
      m.contains('policy') ||
      m.contains('volonex') ||
      m.contains('logiflow');
}

String _desdePostgrest(PostgrestException e, {String? contexto}) {
  final code = e.code ?? '';
  final blob = '${e.message} ${e.details ?? ''} ${e.hint ?? ''}'.toLowerCase();

  if (code == '42501' || blob.contains('row-level security') || blob.contains('permission denied')) {
    return 'No tienes permiso para esta acción. Cierra sesión, vuelve a entrar e inténtalo de nuevo.';
  }
  if (blob.contains('duplicate key') || code == '23505') {
    return 'Ya existe un registro con esos datos.';
  }
  if (code == '23503' || blob.contains('foreign key')) {
    return 'No se puede completar porque hay datos relacionados en el sistema.';
  }
  if (blob.contains('violates not-null') || code == '23502') {
    return 'Faltan datos obligatorios. Revisa el formulario.';
  }
  return _mensajeGenerico(contexto);
}

String _desdeAuth(AuthException e) {
  final m = e.message.toLowerCase();
  if (m.contains('invalid login') || m.contains('invalid credentials')) {
    return 'Correo o contraseña incorrectos.';
  }
  if (m.contains('session') || m.contains('jwt')) {
    return 'Tu sesión expiró. Inicia sesión de nuevo.';
  }
  return _mensajeGenerico(null);
}

String _desdeTexto(String raw, {String? contexto}) {
  final m = raw.toLowerCase();
  if (m.contains('socket') ||
      m.contains('network') ||
      m.contains('failed host') ||
      m.contains('timeout') ||
      m.contains('connection')) {
    return 'Sin conexión. Los cambios se guardarán cuando vuelva internet.';
  }
  if (m.contains('permission') || m.contains('rls') || m.contains('policy')) {
    return 'No tienes permiso para esta acción.';
  }
  if (!_textoEsTecnico(raw) && raw.length <= 100) {
    return raw;
  }
  return _mensajeGenerico(contexto);
}
