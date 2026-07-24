import 'package:flutter/material.dart';

import '../config/app_colors.dart';

/// Aviso al chofer cuando el pasajero paga en efectivo (cash).
/// Explica que cobra el total del viaje y debe liquidar la comisión a la empresa.
class TaxiCashComisionAvisoModal extends StatelessWidget {
  const TaxiCashComisionAvisoModal({
    super.key,
    required this.totalViajeUsd,
    required this.comisionUsd,
    required this.topeDeudaUsd,
    this.comisionPct,
    this.tituloAccion = 'Entendido, continuar',
    this.mostrarCancelar = true,
  });

  final double totalViajeUsd;
  final double comisionUsd;
  final double topeDeudaUsd;
  final double? comisionPct;
  final String tituloAccion;
  final bool mostrarCancelar;

  /// true = continuar / aceptar; false = cancelar.
  static Future<bool?> show(
    BuildContext context, {
    required double totalViajeUsd,
    required double comisionUsd,
    required double topeDeudaUsd,
    double? comisionPct,
    String tituloAccion = 'Entendido, continuar',
    bool mostrarCancelar = true,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => TaxiCashComisionAvisoModal(
        totalViajeUsd: totalViajeUsd,
        comisionUsd: comisionUsd,
        topeDeudaUsd: topeDeudaUsd,
        comisionPct: comisionPct,
        tituloAccion: tituloAccion,
        mostrarCancelar: mostrarCancelar,
      ),
    );
  }

  String _money(double v) => '\$${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final pct = comisionPct;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Material(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.payments_rounded,
                        color: Color(0xFF4CAF50),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Viaje con pago en efectivo',
                        style: TextStyle(
                          color: AppColors.darkText,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'El pasajero te pagará en cash el total del viaje '
                  '(incluye la parte de la empresa). Tú cobras todo en el auto '
                  'y después liquidas la comisión a la empresa.',
                  style: TextStyle(
                    color: AppColors.darkTextMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                _montoCard(
                  label: 'Total que cobrarás del pasajero',
                  value: _money(totalViajeUsd),
                  accent: const Color(0xFF4CAF50),
                ),
                const SizedBox(height: 8),
                _montoCard(
                  label: pct != null && pct > 0
                      ? 'Comisión a pagar a la empresa (${pct.toStringAsFixed(0)}%)'
                      : 'Comisión a pagar a la empresa',
                  value: _money(comisionUsd),
                  accent: const Color(0xFFFF9800),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.darkElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Qué debes hacer',
                        style: TextStyle(
                          color: AppColors.darkText,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _paso(
                        '1',
                        'Al terminar, cobra ${_money(totalViajeUsd)} en efectivo al pasajero.',
                      ),
                      _paso(
                        '2',
                        'Entra a tu perfil → Comisión / fianza cash y paga a la empresa ${_money(comisionUsd)} de este viaje.',
                      ),
                      _paso(
                        '3',
                        'No acumules más de ${_money(topeDeudaUsd)} en comisiones sin pagar: tu cuenta puede suspenderse por falta de pago.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Tope máximo de deuda configurado por la empresa: ${_money(topeDeudaUsd)}.',
                  style: const TextStyle(
                    color: AppColors.darkTextMuted,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.header,
                    foregroundColor: AppColors.darkText,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    tituloAccion,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (mostrarCancelar) ...[
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(
                        color: AppColors.darkTextMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _montoCard({
    required String label,
    required String value,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.darkElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.darkTextMuted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: accent,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paso(String n, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.header,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              n,
              style: const TextStyle(
                color: AppColors.darkText,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(
                color: AppColors.darkText,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
