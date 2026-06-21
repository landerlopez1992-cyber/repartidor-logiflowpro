/// Conversión para etiquetas y manifiestos Cuba (peso almacenado en lb en VolonexPro+).
double? lbAKg(double? pesoLb) {
  if (pesoLb == null) return null;
  return pesoLb * 0.45359237;
}

String pesoKgEtiqueta(double? pesoLb) {
  final kg = lbAKg(pesoLb);
  if (kg == null) return '-';
  return '${kg.toStringAsFixed(2)} kg';
}
