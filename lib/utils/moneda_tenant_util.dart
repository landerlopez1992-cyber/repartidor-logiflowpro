/// Monedas según configuración del tenant (país de operación / saldo del repartidor).
/// No hardcodear selectores CUP/USD en flujos de cobro: usar la moneda ya
/// definida en `repartidor_saldo_moneda` del personal.
class MonedaTenantUtil {
  MonedaTenantUtil._();

  static bool paisOperacionEsCuba(String? pais) {
    final n = (pais ?? '').trim().toLowerCase();
    if (n.isEmpty) return false;
    return n == 'cuba' || n == 'cu' || n.contains('cuba');
  }

  /// CUP solo como opción de configuración cuando el tenant opera en Cuba.
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
    // Otras monedas del tenant (si en el futuro se amplían): respetar código ISO.
    if (RegExp(r'^[A-Z]{3}$').hasMatch(m)) return m;
    return 'USD';
  }

  static String simboloDisplay(String moneda) {
    switch (moneda.trim().toUpperCase()) {
      case 'USD':
        return '\$';
      case 'CUP':
        return 'CUP';
      case 'EUR':
        return '€';
      default:
        return moneda.trim().toUpperCase();
    }
  }
}
