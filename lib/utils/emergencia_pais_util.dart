/// Número de emergencia según país de operación del tenant.
class EmergenciaPaisUtil {
  EmergenciaPaisUtil._();

  /// Devuelve (número a marcar, etiqueta corta).
  static ({String numero, String etiqueta}) paraPais(String? paisOperacion) {
    final p = (paisOperacion ?? '').trim().toLowerCase();
    final n = p
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u');

    if (n.contains('cuba') || n == 'cu') {
      // Policía nacional / emergencias habituales en Cuba.
      return (numero: '106', etiqueta: '106 (emergencias)');
    }
    if (n.contains('estados unidos') ||
        n.contains('united states') ||
        n == 'usa' ||
        n == 'us' ||
        n.contains('ee.uu') ||
        n.contains('eeuu')) {
      return (numero: '911', etiqueta: '911');
    }
    if (n.contains('canada') || n == 'ca') {
      return (numero: '911', etiqueta: '911');
    }
    if (n.contains('mexico') || n == 'mx') {
      return (numero: '911', etiqueta: '911');
    }
    if (n.contains('espana') || n.contains('spain') || n == 'es') {
      return (numero: '112', etiqueta: '112');
    }
    if (n.contains('republica dominicana') ||
        n.contains('dominican') ||
        n == 'do') {
      return (numero: '911', etiqueta: '911');
    }
    if (n.contains('colombia') || n == 'co') {
      return (numero: '123', etiqueta: '123');
    }
    if (n.contains('venezuela') || n == 've') {
      return (numero: '911', etiqueta: '911');
    }
    if (n.contains('argentina') || n == 'ar') {
      return (numero: '911', etiqueta: '911');
    }
    if (n.contains('chile') || n == 'cl') {
      return (numero: '133', etiqueta: '133');
    }
    if (n.contains('peru') || n == 'pe') {
      return (numero: '105', etiqueta: '105');
    }
    if (n.contains('ecuador') || n == 'ec') {
      return (numero: '911', etiqueta: '911');
    }
    if (n.contains('panama') || n == 'pa') {
      return (numero: '911', etiqueta: '911');
    }
    if (n.contains('costa rica') || n == 'cr') {
      return (numero: '911', etiqueta: '911');
    }
    if (n.contains('brasil') || n.contains('brazil') || n == 'br') {
      return (numero: '190', etiqueta: '190');
    }
    if (n.contains('puerto rico') || n == 'pr') {
      return (numero: '911', etiqueta: '911');
    }
    // Fallback razonable para la mayoría de países con sistema unificado.
    return (numero: '911', etiqueta: '911');
  }
}
