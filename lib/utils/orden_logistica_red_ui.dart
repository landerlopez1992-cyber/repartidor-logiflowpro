import '../models/orden.dart';

/// Helpers UI para red de hubs / lotes en la app repartidor.
class OrdenLogisticaRedUi {
  OrdenLogisticaRedUi._();

  static bool tieneHub(Orden orden) =>
      (orden.hubActualId ?? '').trim().isNotEmpty;

  static bool tieneLoteActivo(Orden orden) =>
      (orden.loteActualId ?? '').trim().isNotEmpty;

  /// Recoger en hub (última milla tras recepción, o en tránsito con lote).
  static bool mostrarPuntoHub(Orden orden) => tieneHub(orden);

  static bool puedeConfirmarRecepcionLote(Orden orden) =>
      tieneLoteActivo(orden);
}
