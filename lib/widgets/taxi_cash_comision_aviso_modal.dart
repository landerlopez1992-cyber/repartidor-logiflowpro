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
    final queda = gananciaChoferUsd ??
        (totalViajeUsd - comisionUsd).clamp(0.0, totalViajeUsd).toDouble();
    return TaxiCashMontosModal.show(
      context,
      cobrarClienteUsd: totalViajeUsd,
      quedaChoferUsd: queda,
      empresaUsd: comisionUsd,
      titulo: 'Pago en cash',
      botonTexto: tituloAccion,
      mostrarCancelar: mostrarCancelar,
      textoCancelar: 'Cancelar',
    );
  }
}
