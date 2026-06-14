import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/volonex_dialog.dart';
import '../utils/mensaje_error_operacion.dart';

/// Servicio para manejar errores y mostrar modales informativos (estilo VolonexPro+).
class ErrorHandlerService {
  static final ErrorHandlerService _instance = ErrorHandlerService._internal();
  factory ErrorHandlerService() => _instance;
  ErrorHandlerService._internal();

  static Future<void> showErrorModal(
    BuildContext context,
    String titulo,
    String mensaje, {
    VoidCallback? onAceptar,
  }) async {
    if (!context.mounted) return;

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => VolonexDialog(
        title: titulo,
        leading: const Icon(Icons.error_outline, color: AppColors.error, size: 24),
        child: Text(
          mensaje,
          style: const TextStyle(color: AppColors.darkText, fontSize: 14, height: 1.4),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onAceptar?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  static Future<void> showWarningModal(
    BuildContext context,
    String titulo,
    String mensaje, {
    VoidCallback? onAceptar,
    VoidCallback? onCancelar,
  }) async {
    if (!context.mounted) return;

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => VolonexDialog(
        title: titulo,
        leading: const Icon(Icons.warning_amber_rounded, color: AppColors.botonPrincipal, size: 24),
        child: Text(mensaje),
        actions: [
          if (onCancelar != null)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                onCancelar();
              },
              child: const Text('Cancelar', style: TextStyle(color: AppColors.darkTextMuted)),
            ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onAceptar?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.botonPrincipal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  static Future<void> showSuccessModal(
    BuildContext context,
    String titulo,
    String mensaje, {
    VoidCallback? onAceptar,
  }) async {
    if (!context.mounted) return;

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => VolonexDialog(
        title: titulo,
        leading: const Icon(Icons.check_circle_outline, color: AppColors.exito, size: 24),
        child: Text(mensaje),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onAceptar?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.exito,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  static Future<void> handleError(
    BuildContext context,
    dynamic error, {
    String? titulo,
    String? contexto,
    VoidCallback? onAceptar,
  }) async {
    if (!context.mounted) return;

    String tituloFinal = titulo ?? 'No se pudo completar';
    final mensaje = mensajeErrorOperacion(error, contexto: contexto);

    await showErrorModal(
      context,
      tituloFinal,
      mensaje,
      onAceptar: onAceptar,
    );
  }
}
