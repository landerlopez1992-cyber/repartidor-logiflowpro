import 'package:flutter/material.dart';

import '../config/app_colors.dart';

/// Modal cash compacto: cobrar al cliente / se queda el chofer / dar a la empresa.
class TaxiCashMontosModal extends StatelessWidget {
  const TaxiCashMontosModal({
    super.key,
    required this.cobrarClienteUsd,
    required this.quedaChoferUsd,
    required this.empresaUsd,
    this.titulo = 'Pago en cash',
    this.botonTexto = 'Entendido',
    this.mostrarCancelar = true,
    this.textoCancelar = 'Cancelar',
  });

  final double cobrarClienteUsd;
  final double quedaChoferUsd;
  final double empresaUsd;
  final String titulo;
  final String botonTexto;
  final bool mostrarCancelar;
  final String textoCancelar;

  static Future<bool?> show(
    BuildContext context, {
    required double cobrarClienteUsd,
    required double quedaChoferUsd,
    required double empresaUsd,
    String titulo = 'Pago en cash',
    String botonTexto = 'Entendido',
    bool mostrarCancelar = true,
    String textoCancelar = 'Cancelar',
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (_) => TaxiCashMontosModal(
        cobrarClienteUsd: cobrarClienteUsd,
        quedaChoferUsd: quedaChoferUsd,
        empresaUsd: empresaUsd,
        titulo: titulo,
        botonTexto: botonTexto,
        mostrarCancelar: mostrarCancelar,
        textoCancelar: textoCancelar,
      ),
    );
  }

  String _m(double v) => '\$${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.payments_rounded,
                    color: Color(0xFF4CAF50),
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
                const SizedBox(height: 14),
                _monto(
                  'Cobrar al cliente',
                  _m(cobrarClienteUsd),
                  const Color(0xFF4CAF50),
                  grande: true,
                ),
                const SizedBox(height: 8),
                _monto(
                  'Te quedas',
                  _m(quedaChoferUsd),
                  const Color(0xFFECEFF1),
                ),
                const SizedBox(height: 8),
                _monto(
                  'Dar a la empresa',
                  _m(empresaUsd),
                  const Color(0xFFFF9800),
                ),
                const SizedBox(height: 16),
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
                      botonTexto,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                if (mostrarCancelar)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      textoCancelar,
                      style: const TextStyle(
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
    );
  }

  Widget _monto(
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
}
