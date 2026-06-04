import '../models/orden.dart';
import 'orden_tipo_tarjeta_repartidor.dart';

/// Reglas de entrega para remesas puras (solo dinero, sin envío físico).
class RemesaPuraEntregaUi {
  RemesaPuraEntregaUi._();

  static bool esRemesaPura(Orden orden) =>
      OrdenTipoTarjetaRepartidorUtil.esRemesaPura(orden);

  /// Remesas puras no exigen firma del destinatario en la app.
  static bool exigeFirmaEntrega(Orden orden) =>
      !esRemesaPura(orden) && orden.requiereFirma;

  /// Remesas puras no exigen foto de entrega aunque el tenant la tenga activa.
  static bool exigeFotoEntrega(Orden orden, bool fotoObligatoriaTenant) =>
      !esRemesaPura(orden) && fotoObligatoriaTenant;
}
