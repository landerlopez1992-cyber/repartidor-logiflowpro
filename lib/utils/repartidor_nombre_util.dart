/// Utilidades de nombre de repartidor (mismo criterio que VolonexPro+).
class RepartidorNombreUtil {
  RepartidorNombreUtil._();

  static String normalizar(String? nombre) => (nombre ?? '').trim();

  static bool coincide(String? repartidorEnOrden, String? nombreUsuario) {
    final a = normalizar(repartidorEnOrden);
    final b = normalizar(nombreUsuario);
    if (a.isEmpty || b.isEmpty) return false;
    return a == b;
  }
}
