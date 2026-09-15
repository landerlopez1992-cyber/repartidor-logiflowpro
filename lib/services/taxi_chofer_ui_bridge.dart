import 'package:flutter/foundation.dart';

/// Puente UI: tras aceptar reserva → pestaña Viajes + refrescar listado.
class TaxiChoferUiBridge {
  TaxiChoferUiBridge._();

  /// Incrementar para pedir recarga del panel de reservas.
  static final ValueNotifier<int> reservasRefreshTick = ValueNotifier<int>(0);

  /// Pedir abrir pestaña Viajes en la home del socio.
  static final ValueNotifier<int> irAPestanaViajesTick = ValueNotifier<int>(0);

  static void afterReservaConfirmada() {
    reservasRefreshTick.value++;
    irAPestanaViajesTick.value++;
  }

  static void refreshReservas() {
    reservasRefreshTick.value++;
  }
}
