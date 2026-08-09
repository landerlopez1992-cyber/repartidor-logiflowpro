import 'package:flutter/material.dart';

import 'taxi_cash_montos_modal.dart';

/// Aviso cash al aceptar / tras completar (compat API).
class TaxiCashComisionAvisoModal {
  TaxiCashComisionAvisoModal._();

  /// true = continuar; false = cancelar.
  static Future<bool?> show(
    BuildContext context, {
    required double totalViajeUsd,
    required double comisionUsd,
    required double topeDeudaUsd,
    double? comisionPct,
    double? gananciaChoferUsd,
    String tituloAccion = 'Entendido',
    bool mostrarCancelar = true,
  }) {
    final cobrar = totalViajeUsd.clamp(0.0, double.infinity);
    final empresa = comisionUsd.clamp(0.0, cobrar);
    final neto = (cobrar - empresa).clamp(0.0, cobrar).toDouble();
    // Si viene ganancia = total (bruto) o 0 tras completar cash, usar neto.
    final g = gananciaChoferUsd;
    final queda = (g == null ||
            g < 0.009 ||
            (g - cobrar).abs() < 0.02)
        ? neto
        : ((g + empresa - cobrar).abs() < 0.05
            ? g.clamp(0.0, cobrar).toDouble()
            : neto);
    return TaxiCashMontosModal.show(
      context,
      cobrarClienteUsd: cobrar,
      quedaChoferUsd: queda,
      empresaUsd: empresa,
      titulo: 'Pago en cash',
      botonTexto: tituloAccion,
      mostrarCancelar: mostrarCancelar,
      textoCancelar: 'Cancelar',
    );
  }
}
