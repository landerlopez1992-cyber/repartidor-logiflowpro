/// Monedas visibles según el país de operación del tenant.
/// CUP solo aplica cuando la empresa opera en Cuba.
class MonedaTenantUtil {
  MonedaTenantUtil._();

  static bool paisOperacionEsCuba(String? pais) {
    final n = (pais ?? '').trim().toLowerCase();
    if (n.isEmpty) return false;
    return n == 'cuba' || n == 'cu' || n.contains('cuba');
  }

  static bool permiteCup(String? pais) => paisOperacionEsCuba(pais);

  static List<String> monedasDisponibles(String? pais) {
    if (permiteCup(pais)) return const ['USD', 'CUP'];
    return const ['USD'];
  }

  static String monedaPorDefecto([String? pais]) => 'USD';

  static String normalizarMoneda(String? moneda, String? pais) {
    final m = (moneda ?? '').trim().toUpperCase();
    if (m.isEmpty) return 'USD';
    if (m == 'CUP' && !permiteCup(pais)) return 'USD';
    if (m == 'USD') return 'USD';
    if (m == 'CUP' && permiteCup(pais)) return 'CUP';
    return 'USD';
  }

  static String simboloDisplay(String moneda) =>
      moneda.toUpperCase() == 'USD' ? '\$' : 'CUP';
}
