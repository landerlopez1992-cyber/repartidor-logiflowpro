import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../config/app_colors.dart';

/// Preview del recibo + botón Enviar; luego modal de carga «Enviando evidencia…».
class TaxiZelleEnviarReciboFlow {
  TaxiZelleEnviarReciboFlow._();

  /// Muestra preview. Si el usuario confirma, ejecuta [enviar] con loading.
  /// Retorna el resultado de [enviar], o null si canceló.
  static Future<({bool ok, String? err, String? mensajeOk})?> run(
    BuildContext context, {
    required Uint8List imagenBytes,
    required double montoUsd,
    required Future<({bool ok, String? err, String? mensajeOk})> Function()
        enviar,
  }) async {
    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => _TaxiZellePreviewDialog(
        imagenBytes: imagenBytes,
        montoUsd: montoUsd,
      ),
    );
    if (confirmar != true || !context.mounted) return null;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => const _TaxiZelleEnviandoDialog(),
    );

    final started = DateTime.now();
    ({bool ok, String? err, String? mensajeOk}) result;
    try {
      result = await enviar();
    } catch (e) {
      result = (ok: false, err: '$e', mensajeOk: null);
    }

    final elapsed = DateTime.now().difference(started);
    const minWait = Duration(milliseconds: 2200);
    if (elapsed < minWait) {
      await Future<void>.delayed(minWait - elapsed);
    }

    if (!context.mounted) return result;
    Navigator.of(context, rootNavigator: true).pop();

    if (!context.mounted) return result;

    await showDialog<void>(
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
                    result.ok
                        ? Icons.hourglass_top_rounded
                        : Icons.error_outline,
                    color: result.ok
                        ? const Color(0xFFFF9800)
                        : const Color(0xFFDC2626),
                    size: 48,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    result.ok ? 'Evidencia enviada' : 'No se pudo enviar',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.darkText,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    result.ok
                        ? (result.mensajeOk ??
                            'La empresa revisará tu pago. '
                                'Cuando lo confirme, se descontará de tu deuda.')
                        : (result.err ?? 'Inténtalo de nuevo.'),
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

    return result;
  }
}

class _TaxiZellePreviewDialog extends StatelessWidget {
  const _TaxiZellePreviewDialog({
    required this.imagenBytes,
    required this.montoUsd,
  });

  final Uint8List imagenBytes;
  final double montoUsd;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscape = size.width > size.height;

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
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Recibo de pago',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.darkText,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Monto: \$${montoUsd.toStringAsFixed(2)} USD',
                  style: const TextStyle(
                    color: AppColors.darkTextMuted,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: landscape ? 140 : 220,
                    ),
                    child: Image.memory(
                      imagenBytes,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.header,
                      foregroundColor: AppColors.darkText,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Enviar recibo de pago',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'Elegir otra foto',
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
}

class _TaxiZelleEnviandoDialog extends StatelessWidget {
  const _TaxiZelleEnviandoDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Material(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(16),
          child: const Padding(
            padding: EdgeInsets.fromLTRB(24, 28, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 42,
                  height: 42,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Color(0xFFFF9800),
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  'Enviando evidencia de pago…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.darkText,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Un momento',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.darkTextMuted,
                    fontSize: 12,
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
