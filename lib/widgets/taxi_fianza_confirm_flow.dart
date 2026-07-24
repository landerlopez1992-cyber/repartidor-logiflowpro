import 'package:flutter/material.dart';

import '../config/app_colors.dart';

enum TaxiFianzaConfirmModo {
  /// Billetera → fianza (no reversible a billetera).
  transferirAFianza,

  /// Fianza → paga comisión empresa (liquidación).
  pagarComisionConFianza,
}

/// Flujo: explicación → loading → confirmación.
class TaxiFianzaConfirmFlow {
  TaxiFianzaConfirmFlow._();

  /// Retorna true si la acción terminó bien.
  static Future<bool> run(
    BuildContext context, {
    required TaxiFianzaConfirmModo modo,
    required double montoUsd,
    required double saldoBilleteraUsd,
    required double fianzaActualUsd,
    required Future<({bool ok, String? err, String? mensajeOk})> Function()
        accion,
    String? botonAceptar,
  }) async {
    final okExplicacion = await _showExplicacion(
      context,
      modo: modo,
      montoUsd: montoUsd,
      saldoBilleteraUsd: saldoBilleteraUsd,
      fianzaActualUsd: fianzaActualUsd,
      botonAceptar: botonAceptar ??
          (modo == TaxiFianzaConfirmModo.transferirAFianza
              ? 'Transferir'
              : 'Pagar con fianza'),
    );
    if (okExplicacion != true || !context.mounted) return false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => const _TaxiFianzaLoadingDialog(),
    );

    final started = DateTime.now();
    ({bool ok, String? err, String? mensajeOk}) result;
    try {
      result = await accion();
    } catch (e) {
      result = (ok: false, err: '$e', mensajeOk: null);
    }

    final elapsed = DateTime.now().difference(started);
    const minWait = Duration(milliseconds: 1600);
    if (elapsed < minWait) {
      await Future<void>.delayed(minWait - elapsed);
    }

    if (!context.mounted) return false;
    Navigator.of(context, rootNavigator: true).pop();

    if (!context.mounted) return false;

    if (!result.ok) {
      await _showResultado(
        context,
        ok: false,
        titulo: 'No se pudo completar',
        mensaje: result.err ?? 'Inténtalo de nuevo.',
      );
      return false;
    }

    final okMsg = result.mensajeOk ??
        (modo == TaxiFianzaConfirmModo.transferirAFianza
            ? 'Se movieron \$${montoUsd.toStringAsFixed(2)} de tu billetera a la fianza de viajes cash.'
            : 'Se pagaron \$${montoUsd.toStringAsFixed(2)} de comisión con tu fianza.');

    await _showResultado(
      context,
      ok: true,
      titulo: 'Listo',
      mensaje: okMsg,
    );
    return true;
  }

  static Future<bool?> _showExplicacion(
    BuildContext context, {
    required TaxiFianzaConfirmModo modo,
    required double montoUsd,
    required double saldoBilleteraUsd,
    required double fianzaActualUsd,
    required String botonAceptar,
  }) {
    final esTransfer = modo == TaxiFianzaConfirmModo.transferirAFianza;
    final titulo = esTransfer ? 'Transferir a fianza' : 'Pagar con fianza';
    final montoLabel = esTransfer
        ? 'Se descontará de tu billetera'
        : 'Se descontará de tu fianza';
    final aviso = esTransfer
        ? 'Esta operación no es reversible. El dinero pasa a tu fianza de '
            'viajes cash y no vuelve a la billetera.'
        : 'Se usará tu fianza para liquidar la comisión cash a la empresa. '
            'Esta acción no se puede deshacer.';

    final saldoDespues = esTransfer
        ? (saldoBilleteraUsd - montoUsd).clamp(0.0, saldoBilleteraUsd)
        : saldoBilleteraUsd;
    final fianzaDespues = esTransfer
        ? fianzaActualUsd + montoUsd
        : (fianzaActualUsd - montoUsd).clamp(0.0, fianzaActualUsd);

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Material(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9800).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      esTransfer
                          ? Icons.account_balance_wallet_outlined
                          : Icons.payments_outlined,
                      color: const Color(0xFFFF9800),
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    titulo,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.darkText,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _montoBox(
                    montoLabel,
                    '\$${montoUsd.toStringAsFixed(2)}',
                    const Color(0xFFFF9800),
                    grande: true,
                  ),
                  const SizedBox(height: 8),
                  if (esTransfer)
                    _fila('Saldo billetera', saldoBilleteraUsd, saldoDespues),
                  if (esTransfer) const SizedBox(height: 4),
                  _fila('Fianza cash', fianzaActualUsd, fianzaDespues),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.darkElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFFDC2626).withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      aviso,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.darkTextMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.header,
                        foregroundColor: AppColors.darkText,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        botonAceptar,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(
                        color: AppColors.darkTextMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _showResultado(
    BuildContext context, {
    required bool ok,
    required String titulo,
    required String mensaje,
  }) {
    final color = ok ? const Color(0xFF4CAF50) : const Color(0xFFDC2626);
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Material(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    ok ? Icons.check_circle_rounded : Icons.error_outline,
                    color: color,
                    size: 48,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    titulo,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.darkText,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    mensaje,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.darkTextMuted,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.header,
                        foregroundColor: AppColors.darkText,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Entendido',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _montoBox(
    String label,
    String value,
    Color accent, {
    bool grande = false,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: 12,
        vertical: grande ? 12 : 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.darkElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.darkTextMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: accent,
              fontSize: grande ? 24 : 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _fila(String label, double antes, double despues) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.darkTextMuted,
              fontSize: 12,
            ),
          ),
        ),
        Text(
          '\$${antes.toStringAsFixed(2)} → \$${despues.toStringAsFixed(2)}',
          style: const TextStyle(
            color: AppColors.darkText,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _TaxiFianzaLoadingDialog extends StatelessWidget {
  const _TaxiFianzaLoadingDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Material(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(16),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Color(0xFFFF9800),
                  ),
                ),
                SizedBox(height: 14),
                Text(
                  'Procesando…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.darkText,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
