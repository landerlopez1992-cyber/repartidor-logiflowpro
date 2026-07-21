/// Catálogo ligero: marcas + mapa avatar_key → asset (sin fotos por marca).
class TaxiVehiculoCatalog {
  TaxiVehiculoCatalog._();

  static const List<String> marcas = [
    'Chevrolet',
    'Ford',
    'Buick',
    'Pontiac',
    'Oldsmobile',
    'Cadillac',
    'Dodge',
    'Plymouth',
    'Chrysler',
    'Hyundai',
    'Kia',
    'Toyota',
    'Nissan',
    'Honda',
    'Peugeot',
    'Renault',
    'Volkswagen',
    'Suzuki',
    'Mitsubishi',
    'Geely',
    'BYD',
    'Lada',
    'Moskvitch',
    'Otro',
  ];

  static const List<String> colores = [
    'Blanco',
    'Negro',
    'Gris',
    'Plata',
    'Azul',
    'Rojo',
    'Verde',
    'Amarillo',
    'Beige',
    'Marrón',
    'Otro',
  ];

  static List<int> aniosDisponibles({int from = 1940}) {
    final now = DateTime.now().year + 1;
    return [for (var y = now; y >= from; y--) y];
  }

  static String assetForKey(String? key, {String? ofertaTipo}) {
    final k = (key ?? '').trim().toLowerCase();
    if (k == 'clasico') return 'assets/images/taxi-auto-clasico-3d-v3.png';
    if (k == 'van') return 'assets/images/taxi-auto-van-3d-v3.png';
    final t = (ofertaTipo ?? '').toLowerCase();
    if (t.startsWith('van_') || t.startsWith('xl_')) {
      return 'assets/images/taxi-auto-van-3d-v3.png';
    }
    if (t == 'cercano' || t.contains('comfort')) {
      return 'assets/images/taxi-auto-comfort-3d-v3.png';
    }
    return 'assets/images/taxi-auto-estandar-3d-v3.png';
  }

  static String resolveAvatarKey({
    required String marca,
    int? anio,
    int capacidad = 4,
  }) {
    if (capacidad >= 6) return 'van';
    final m = marca.trim().toLowerCase();
    if (m.contains('van') || m.contains('minivan')) return 'van';
    if (anio != null && anio >= 1900 && anio <= 1975) return 'clasico';
    const clasicas = {
      'chevrolet',
      'chevy',
      'ford',
      'buick',
      'pontiac',
      'oldsmobile',
      'cadillac',
      'dodge',
      'plymouth',
      'chrysler',
    };
    if (clasicas.contains(m) && anio != null && anio <= 1985) return 'clasico';
    return 'moderno';
  }
}
