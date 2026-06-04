import 'package:flutter/material.dart';
import '../config/app_colors.dart';

/// Insignia compacta de repartidor master (AppBar, avatar, etc.).
class RepartidorMasterBadgeOverlay extends StatelessWidget {
  const RepartidorMasterBadgeOverlay({
    super.key,
    this.size = 14,
    this.iconSize = 9,
    this.borderColor,
  });

  final double size;
  final double iconSize;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF9800), Color(0xFFFFB74D)],
        ),
        shape: BoxShape.circle,
        border: Border.all(
          color: borderColor ?? AppColors.header,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Icon(
        Icons.workspace_premium,
        color: Colors.white,
        size: iconSize,
      ),
    );
  }
}

/// Barra superior compacta «Repartidor Master» (lista de órdenes).
class RepartidorMasterBannerCompact extends StatelessWidget {
  const RepartidorMasterBannerCompact({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.darkElevated,
        border: Border(
          bottom: BorderSide(
            color: AppColors.botonPrincipal.withOpacity(0.45),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: const [
          RepartidorMasterBadgeOverlay(size: 14, iconSize: 9),
          SizedBox(width: 6),
          Text(
            'Repartidor Master',
            style: TextStyle(
              color: Color(0xFFFFCC80),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// Etiqueta «Master» compacta junto al título.
class RepartidorMasterChip extends StatelessWidget {
  const RepartidorMasterChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.botonPrincipal.withOpacity(0.22),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: AppColors.botonPrincipal.withOpacity(0.55),
          width: 0.5,
        ),
      ),
      child: const Text(
        'Master',
        style: TextStyle(
          color: Color(0xFFFFCC80),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.1,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
