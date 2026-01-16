import 'package:flutter/material.dart';

/// Servicio para manejar errores y mostrar modales informativos
class ErrorHandlerService {
  static final ErrorHandlerService _instance = ErrorHandlerService._internal();
  factory ErrorHandlerService() => _instance;
  ErrorHandlerService._internal();

  /// Mostrar modal de error
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
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.error_outline,
                color: Color(0xFFDC2626),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                titulo,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C2C2C),
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mensaje,
                style: const TextStyle(
                  fontSize: 15,
                  color: Color(0xFF2C2C2C),
                  height: 1.5,
                ),
              ),
              if (detalleTecnico != null && detalleTecnico.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.bug_report, size: 16, color: Color(0xFF666666)),
                          SizedBox(width: 8),
                          Text(
                            'Detalle técnico:',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF666666),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        detalleTecnico,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF666666),
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              onAceptar?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  /// Mostrar modal de advertencia
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
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9800).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFFF9800),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                titulo,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C2C2C),
                ),
              ),
            ),
          ],
        ),
        content: Text(
          mensaje,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF2C2C2C),
            height: 1.5,
          ),
        ),
        actions: [
          if (onCancelar != null)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onCancelar();
              },
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF666666),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              child: const Text('Cancelar'),
            ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              onAceptar?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF9800),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  /// Mostrar modal de éxito
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
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.check_circle_outline,
                color: Color(0xFF4CAF50),
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                titulo,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C2C2C),
                ),
              ),
            ),
          ],
        ),
        content: Text(
          mensaje,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xFF2C2C2C),
            height: 1.5,
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              onAceptar?.call();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4CAF50),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
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

    // Determinar tipo de error y mensaje apropiado
    final errorString = error.toString();
    
    if (errorString.contains('SocketException') || 
        errorString.contains('network') ||
        errorString.contains('connection')) {
      tituloFinal = 'Error de Conexión';
      mensaje = 'No hay conexión a internet. Los datos se guardaron localmente y se sincronizarán cuando haya conexión.';
      detalleTecnico = null; // No mostrar detalle técnico de errores de red
    } else if (errorString.contains('timeout')) {
      tituloFinal = 'Tiempo de Espera Agotado';
      mensaje = 'La operación tardó demasiado. Los datos se guardaron localmente y se sincronizarán más tarde.';
    } else if (errorString.contains('permission') || errorString.contains('Permission')) {
      tituloFinal = 'Permiso Denegado';
      mensaje = 'No se tiene permiso para realizar esta operación.';
      detalleTecnico = errorString;
    } else if (errorString.contains('storage') || errorString.contains('Storage')) {
      tituloFinal = 'Error de Almacenamiento';
      mensaje = 'No se pudo guardar en el almacenamiento local. Verifica que haya espacio disponible.';
      detalleTecnico = errorString;
    } else {
      // Error genérico
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
