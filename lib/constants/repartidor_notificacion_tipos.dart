/// Tipos canónicos de notificaciones (alineado con VolonexPro+ panel / Supabase).
class RepartidorNotificacionTipos {
  RepartidorNotificacionTipos._();

  static const String nuevaOrden = 'nueva_orden';
  static const String legacyOrdenNueva = 'ORDEN_NUEVA';

  static const List<String> tiposOrdenNueva = [nuevaOrden, legacyOrdenNueva];

  static const String pagoAceptado = 'PAGO_ACEPTADO';
  static const String pagoCancelado = 'PAGO_CANCELADO';
  static const String pagoRechazado = 'PAGO_RECHAZADO';
  static const String general = 'general';
}
