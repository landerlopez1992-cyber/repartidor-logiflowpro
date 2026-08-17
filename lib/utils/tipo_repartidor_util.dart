/// Normaliza `usuarios.tipo_repartidor` (RECOLECTOR / Recolector / etc.).
String normalizarTipoRepartidor(dynamic raw) {
  final s = (raw ?? '').toString().trim().toUpperCase();
  if (s.contains('RECOLECT')) return 'RECOLECTOR';
  return 'REPARTIDOR';
}

bool esTipoRecolector(dynamic raw) =>
    normalizarTipoRepartidor(raw) == 'RECOLECTOR';
