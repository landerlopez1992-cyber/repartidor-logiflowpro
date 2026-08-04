/// Tipos canónicos de notificaciones (alineado con VolonexPro+ panel / Supabase).
class RepartidorNotificacionTipos {
  RepartidorNotificacionTipos._();

  static const String nuevaOrden = 'nueva_orden';
  static const String legacyOrdenNueva = 'ORDEN_NUEVA';

  static const String taxiViaje = 'taxi_viaje';
  static const String taxiReserva = 'taxi_reserva';
  static const String taxiViajeCompletado = 'taxi_viaje_completado';
  static const String taxiPropina = 'taxi_propina';
  static const String taxiChat = 'taxi_chat';

  static const List<String> tiposOrdenNueva = [nuevaOrden, legacyOrdenNueva];

  /// Solo oferta entrante → modal llamada + ringtone/vibración persistente.
  /// Incluye reservas programadas (misma UX de aceptar/rechazar).
  static const List<String> tiposTaxiViaje = [taxiViaje, taxiReserva];

  static const List<String> tiposTaxiViajeCompletado = [taxiViajeCompletado];
  static const List<String> tiposTaxiPropina = [taxiPropina];
  static const List<String> tiposTaxiChat = [taxiChat];

  /// Badge / lista de notificaciones (todos los avisos del módulo taxi).
  static const List<String> tiposTaxiTodos = [
    taxiViaje,
    taxiReserva,
    taxiViajeCompletado,
    taxiPropina,
    taxiChat,
  ];

  static const String pagoAceptado = 'PAGO_ACEPTADO';
  static const String pagoCancelado = 'PAGO_CANCELADO';
  static const String pagoRechazado = 'PAGO_RECHAZADO';
  static const String general = 'general';
}
