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
    final cobrar = totalCobrarUsd.clamp(0.0, double.infinity);
    final empresa = comisionEmpresaUsd.clamp(0.0, cobrar);
    final neto = (cobrar - empresa).clamp(0.0, cobrar).toDouble();
    final g = gananciaChoferUsd;
    final queda = (g < 0.009 || (g - cobrar).abs() < 0.02)
        ? neto
        : ((g + empresa - cobrar).abs() < 0.05
            ? g.clamp(0.0, cobrar).toDouble()
            : neto);
    return TaxiCashMontosModal.show(
      context,
      cobrarClienteUsd: cobrar,
      quedaChoferUsd: queda,
      empresaUsd: empresa,
      titulo: 'Cobrar en cash',
      botonTexto: 'Ya cobré — completar',
      mostrarCancelar: true,
      textoCancelar: 'Volver',
    );
  }
}
