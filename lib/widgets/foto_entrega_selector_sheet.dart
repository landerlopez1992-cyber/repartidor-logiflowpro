import 'package:flutter/material.dart';
import '../config/app_colors.dart';

/// Bottom sheet oscuro para elegir cámara o galería al entregar una orden.
class FotoEntregaSelectorSheet {
  FotoEntregaSelectorSheet._();

  /// Retorna `'camara'` o `'galeria'`, o `null` si canceló.
  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (ctx) => SafeArea(
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.darkBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Seleccionar foto de entrega',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkText,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _opcion(
                  ctx,
                  valor: 'camara',
                  icon: Icons.camera_alt,
                  iconColor: const Color(0xFF64B5F6),
                  titulo: 'Tomar foto',
                  subtitulo: 'Usar la cámara para tomar una nueva foto',
                ),
                _opcion(
                  ctx,
                  valor: 'galeria',
                  icon: Icons.photo_library,
                  iconColor: AppColors.exito,
                  titulo: 'Elegir de galería',
                  subtitulo: 'Seleccionar una foto de tu galería',
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: AppColors.darkTextMuted),
                  ),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _opcion(
    BuildContext ctx, {
    required String valor,
    required IconData icon,
    required Color iconColor,
    required String titulo,
    required String subtitulo,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pop(ctx, valor),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.darkText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.darkTextMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.darkTextMuted, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
