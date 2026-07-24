import 'package:flutter/material.dart';

import '../config/app_colors.dart';

/// Modal previo a completar un viaje cash: el chofer debe cobrar al pasajero
/// el total en efectivo antes de marcar la carrera terminada.
class TaxiCashCobrarCompletarModal extends StatelessWidget {
  const TaxiCashCobrarCompletarModal({
    super.key,
    required this.totalCobrarUsd,
    required this.gananciaChoferUsd,
    this.comisionEmpresaUsd = 0,
  });

  final double totalCobrarUsd;
  final double gananciaChoferUsd;
  final double comisionEmpresaUsd;

  /// true = el chofer confirma que cobró y quiere completar.
  static Future<bool?> show(
    BuildContext context, {
    required double totalCobrarUsd,
    required double gananciaChoferUsd,
    double comisionEmpresaUsd = 0,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => TaxiCashCobrarCompletarModal(
        totalCobrarUsd: totalCobrarUsd,
        gananciaChoferUsd: gananciaChoferUsd,
        comisionEmpresaUsd: comisionEmpresaUsd,
      ),
    );
  }

  String _money(double v) => '\$${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
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
                        'Cobrar en efectivo',
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
                  'Este viaje es de pago en cash. Antes de marcar la carrera '
                  'terminada, cobra al pasajero el total en efectivo.',
                  style: TextStyle(
                    color: AppColors.darkTextMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.darkElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.45),
                    ),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Total a cobrar al pasajero',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.darkTextMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_money(totalCobrarUsd)} USD',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF4CAF50),
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _filaDetalle(
                  'Tu ganancia',
                  _money(gananciaChoferUsd),
                  const Color(0xFFECEFF1),
                ),
                if (comisionEmpresaUsd > 0) ...[
                  const SizedBox(height: 6),
                  _filaDetalle(
                    'Parte empresa (luego liquidas)',
                    _money(comisionEmpresaUsd),
                    const Color(0xFFFF9800),
                  ),
                ],
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
                  child: const Text(
                    'Ya cobré — completar viaje',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'Volver',
                    style: TextStyle(
                      color: AppColors.darkTextMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _filaDetalle(String label, String value, Color valueColor) {
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
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
