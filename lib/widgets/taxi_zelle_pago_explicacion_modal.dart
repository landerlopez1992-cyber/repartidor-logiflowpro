import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_colors.dart';

/// Explica el flujo Zelle → captura → revisión empresa antes de subir el comprobante.
class TaxiZellePagoExplicacionModal extends StatelessWidget {
  const TaxiZellePagoExplicacionModal({
    super.key,
    required this.nombreEmpresa,
    required this.datosZelle,
    required this.montoUsd,
  });

  final String nombreEmpresa;
  final String datosZelle;
  final double montoUsd;

  static Future<bool?> show(
    BuildContext context, {
    required String nombreEmpresa,
    required String datosZelle,
    required double montoUsd,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => TaxiZellePagoExplicacionModal(
        nombreEmpresa: nombreEmpresa,
        datosZelle: datosZelle,
        montoUsd: montoUsd,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;
    final iconSize = landscape ? 52.0 : 78.0;
    final empresa = nombreEmpresa.trim().isEmpty ? 'la empresa' : nombreEmpresa.trim();
    final zelle = datosZelle.trim().isEmpty ? 'los datos Zelle de la empresa' : datosZelle.trim();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: landscape ? 40 : 28,
        vertical: landscape ? 10 : 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 360,
          maxHeight: size.height * 0.9,
        ),
        child: Material(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              landscape ? 12 : 18,
              20,
              landscape ? 8 : 12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/payment_zelle_3d.png',
                  width: iconSize,
                  height: iconSize,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.account_balance_wallet_rounded,
                    color: const Color(0xFF6CC24A),
                    size: iconSize * 0.55,
                  ),
                ),
                SizedBox(height: landscape ? 8 : 12),
                const Text(
                  'Pagar con Zelle',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.darkText,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: landscape ? 8 : 12),
                _paso(
                  '1',
                  'Envía un pago por Zelle a la empresa ',
                  empresa,
                  ' a ',
                  zelle,
                  '.',
                ),
                const SizedBox(height: 10),
                _pasoTexto(
                  '2',
                  'Haz una captura del pago exitoso y súbela aquí.',
                ),
                const SizedBox(height: 10),
                _pasoTexto(
                  '3',
                  'Cuando la empresa verifique que el pago fue exitoso, '
                  'lo marcará como pagado y se descontará de tu deuda.',
                ),
                SizedBox(height: landscape ? 10 : 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.darkElevated,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Monto a pagar',
                        style: TextStyle(
                          color: AppColors.darkTextMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '\$${montoUsd.toStringAsFixed(2)} USD',
                        style: TextStyle(
                          color: AppColors.botonPrincipal,
                          fontSize: landscape ? 20 : 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (zelle != 'los datos Zelle de la empresa') ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                zelle,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.darkText,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copiar',
                              visualDensity: VisualDensity.compact,
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: zelle));
                                if (!context.mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Datos Zelle copiados'),
                                    backgroundColor: Color(0xFF37474F),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                              icon: const Icon(
                                Icons.copy_rounded,
                                size: 18,
                                color: AppColors.darkTextMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: landscape ? 10 : 14),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text:
                            'Nota: Asegúrate de agregar bien el contacto de pago. '
                            'La empresa no se responsabiliza por errores en el Zelle '
                            'por un contacto mal agregado. Si el Zelle no lo recibe, '
                            'la empresa no lo marcará como pagado y ',
                        style: TextStyle(
                          color: const Color(0xFFDC2626).withValues(alpha: 0.95),
                          fontSize: 12,
                          height: 1.35,
                          decoration: TextDecoration.underline,
                          decorationColor: const Color(0xFFDC2626),
                        ),
                      ),
                      const TextSpan(
                        text: 'seguirá tu deuda',
                        style: TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w800,
                          decoration: TextDecoration.underline,
                          decorationColor: Color(0xFFDC2626),
                        ),
                      ),
                      TextSpan(
                        text: '.',
                        style: TextStyle(
                          color: const Color(0xFFDC2626).withValues(alpha: 0.95),
                          fontSize: 12,
                          height: 1.35,
                          decoration: TextDecoration.underline,
                          decorationColor: const Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: landscape ? 12 : 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.header,
                      foregroundColor: AppColors.darkText,
                      padding: EdgeInsets.symmetric(
                        vertical: landscape ? 11 : 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Entendido, subir captura',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text(
                    'Cancelar',
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

  Widget _paso(
    String n,
    String a,
    String bold1,
    String mid,
    String bold2,
    String end,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _badge(n),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              style: const TextStyle(
                color: AppColors.darkTextMuted,
                fontSize: 13,
                height: 1.35,
              ),
              children: [
                TextSpan(text: a),
                TextSpan(
                  text: bold1,
                  style: const TextStyle(
                    color: AppColors.darkText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: mid),
                TextSpan(
                  text: bold2,
                  style: const TextStyle(
                    color: AppColors.darkText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(text: end),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _pasoTexto(String n, String texto) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _badge(n),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(
              color: AppColors.darkTextMuted,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _badge(String n) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.header,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        n,
        style: const TextStyle(
          color: AppColors.darkText,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
