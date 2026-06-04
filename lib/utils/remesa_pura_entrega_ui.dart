import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/orden.dart';
import 'orden_tipo_tarjeta_repartidor.dart';

/// Colores de remesa pura sobre tema oscuro (legibles en lista y detalle).
class RemesaPuraUiTheme {
  RemesaPuraUiTheme._();

  static const Color acento = Color(0xFFFFB74D);
  static const Color acentoFuerte = Color(0xFFFF9800);
  static const Color fondoTarjeta = AppColors.darkSurface;
  static const Color fondoDestacado = AppColors.darkElevated;
  static const Color borde = Color(0xFFE5A84A);
}

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
