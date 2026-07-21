/// Canal de [conversaciones_soporte] para la app del socio (no mezclar con web/cliente).
class RepartidorChatOrigen {
  RepartidorChatOrigen._();

  /// Hilo empresa ↔ repartidor (app Repartidor).
  static const String repartidorApp = 'repartidor_app';

  /// Cliente tienda / CubaLink (NO debe verse en app Repartidor).
  static const String clienteWeb = 'cliente_web';

  /// Membresía / super admin (NO debe verse en app Repartidor).
  static const String membresiaLogiflow = 'membresia_logiflow';

  /// Preferir legado null o canal explícito de la app socio.
  /// [cliente_web] y [membresia_logiflow] se excluyen siempre.
  static bool esCanalEmpresaRepartidor(String? origen) {
    if (origen == null || origen.trim().isEmpty) return true;
    final o = origen.trim().toLowerCase();
    if (o == clienteWeb || o == membresiaLogiflow) return false;
    return o == repartidorApp;
  }

  static bool esRolEmpresa(String? rol) {
    final r = (rol ?? '').trim().toUpperCase();
    if (r.isEmpty) return false;
    return r == 'ADMINISTRADOR' ||
        r == 'ADMIN' ||
        r == 'EMPLEADO' ||
        r.contains('ADMIN');
  }
}
