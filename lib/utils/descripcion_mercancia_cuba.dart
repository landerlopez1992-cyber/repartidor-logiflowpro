import '../models/orden.dart';

/// Descripción de mercancías para etiqueta CUBATRANS / manifiesto Anexo 7:
/// solo el texto de [Orden.notas] (campo Notas en crear/editar orden).
/// Sin plantilla "Paquete de…"; si no hay notas, cadena vacía.
String descripcionMercanciaCubaDesdeOrden(Orden orden) {
  final n = orden.notas?.trim() ?? '';
  return n;
}

/// Misma regla leyendo un mapa (p. ej. fila de Supabase para Excel).
String descripcionMercanciaCubaDesdeMap(Map<String, dynamic> o) {
  final n = o['notas']?.toString().trim() ?? '';
  return n;
}
