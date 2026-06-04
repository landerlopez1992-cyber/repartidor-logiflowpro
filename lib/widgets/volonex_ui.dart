import 'package:flutter/material.dart';
import '../config/app_colors.dart';

/// Chips, tarjetas y banners con estilo VolonexPro+ oscuro (misma línea que historial de nóminas).
class VolonexUi {
  VolonexUi._();

  static BoxDecoration surfaceCard({Color? borderColor, double radius = 12}) {
    return BoxDecoration(
      color: AppColors.darkSurface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor ?? AppColors.darkBorder),
    );
  }

  /// Chip de filtro con buen contraste (seleccionado = naranja sólido + texto blanco).
  static Widget filterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData? icon,
    Color? selectedColor,
  }) {
    final accent = selectedColor ?? AppColors.botonPrincipal;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? accent : AppColors.darkElevated,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? accent : AppColors.darkBorder,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  const Icon(Icons.check, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                ],
                if (icon != null && !selected) ...[
                  Icon(icon, size: 14, color: AppColors.darkTextMuted),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.darkTextMuted,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// FilterChip Material con contraste corregido (para Wrap / formularios).
  static Widget materialFilterChip({
    required String label,
    required bool selected,
    required ValueChanged<bool>? onSelected,
    bool showCheckmark = true,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      showCheckmark: showCheckmark,
      checkmarkColor: Colors.white,
      selectedColor: AppColors.botonPrincipal,
      backgroundColor: AppColors.darkElevated,
      side: BorderSide(
        color: selected ? AppColors.botonPrincipal : AppColors.darkBorder,
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppColors.darkTextMuted,
        fontSize: 12,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  static Widget offlineBanner({
    required String message,
    int pendingOps = 0,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.botonPrincipal.withValues(alpha: 0.15),
        border: Border(
          bottom: BorderSide(color: AppColors.botonPrincipal.withValues(alpha: 0.4)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, color: AppColors.botonPrincipal, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.darkText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (pendingOps > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.botonPrincipal,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$pendingOps pend.',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static Widget emptyState({
    required IconData icon,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: surfaceCard(),
      child: Column(
        children: [
          Icon(icon, size: 48, color: AppColors.darkTextMuted),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.darkTextMuted,
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
