import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/volonex_dialog.dart';

/// Servicio para manejar errores y mostrar modales informativos (estilo VolonexPro+).
class ErrorHandlerService {
  static final ErrorHandlerService _instance = ErrorHandlerService._internal();
  factory ErrorHandlerService() => _instance;
  ErrorHandlerService._internal();

  static Future<void> showErrorModal(
    BuildContext context,
    String titulo,
    String mensaje, {
    String? detalleTecnico,
    VoidCallback? onAceptar,
  }) async {
    if (!context.mounted) return;

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => VolonexDialog(
        title: titulo,
        leading: const Icon(Icons.error_outline, color: AppColors.error, size: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(mensaje),
            if (detalleTecnico != null && detalleTecnico.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.darkElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.darkBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bug_report, size: 14, color: AppColors.darkTextMuted),
                        SizedBox(width: 6),
                        Text(
                          'Detalle técnico',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.darkTextMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      detalleTecnico,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.darkTextMuted,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
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

  /// Manejar error y mostrar modal apropiado
  static Future<void> handleError(
    BuildContext context,
    dynamic error, {
    String? titulo,
    String? mensajePersonalizado,
    VoidCallback? onAceptar,
  }) async {
    if (!context.mounted) return;

    String tituloFinal = titulo ?? 'Error';
    String mensaje = mensajePersonalizado ?? 'Ha ocurrido un error inesperado';
    String? detalleTecnico;

    final errorString = error.toString();

    if (errorString.contains('SocketException') ||
        errorString.contains('network') ||
        errorString.contains('connection')) {
      tituloFinal = 'Error de Conexión';
      mensaje =
          'No hay conexión a internet. Los datos se guardaron localmente y se sincronizarán cuando haya conexión.';
      detalleTecnico = null;
    } else if (errorString.contains('timeout')) {
      tituloFinal = 'Tiempo de Espera Agotado';
      mensaje =
          'La operación tardó demasiado. Los datos se guardaron localmente y se sincronizarán más tarde.';
    } else if (errorString.contains('permission') || errorString.contains('Permission')) {
      tituloFinal = 'Permiso Denegado';
      mensaje = 'No se tiene permiso para realizar esta operación.';
      detalleTecnico = errorString;
    } else if (errorString.contains('storage') || errorString.contains('Storage')) {
      tituloFinal = 'Error de Almacenamiento';
      mensaje =
          'No se pudo guardar en el almacenamiento local. Verifica que haya espacio disponible.';
      detalleTecnico = errorString;
    } else {
      detalleTecnico = errorString;
    }

    await showErrorModal(
      context,
      tituloFinal,
      mensaje,
      detalleTecnico: detalleTecnico,
      onAceptar: onAceptar,
    );
  }
}
