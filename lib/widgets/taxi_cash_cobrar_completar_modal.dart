import 'package:flutter/material.dart';

import 'taxi_cash_montos_modal.dart';

/// Confirmación previa a completar viaje cash.
class TaxiCashCobrarCompletarModal {
  TaxiCashCobrarCompletarModal._();

  /// true = ya cobró y completa.
  static Future<bool?> show(
    BuildContext context, {
    required double totalCobrarUsd,
    required double gananciaChoferUsd,
    double comisionEmpresaUsd = 0,
  }) {
    return TaxiCashMontosModal.show(
      context,
      cobrarClienteUsd: totalCobrarUsd,
      quedaChoferUsd: gananciaChoferUsd,
      empresaUsd: comisionEmpresaUsd,
      titulo: 'Cobrar en cash',
      botonTexto: 'Ya cobré — completar',
      mostrarCancelar: true,
      textoCancelar: 'Volver',
    );
  }
}
