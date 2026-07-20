import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/orden.dart';
import '../screens/productos_orden_tienda_screen.dart';

/// Botón «Ver productos» solo para compras de tienda.
class BotonVerProductosOrdenTienda extends StatelessWidget {
  const BotonVerProductosOrdenTienda({
    super.key,
    required this.orden,
    this.compact = false,
  });

  final Orden orden;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!orden.esCompraTienda) {
      return const SizedBox.shrink();
    }
    return Center(
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ProductosOrdenTiendaScreen(orden: orden),
            ),
          );
        },
        icon: Icon(Icons.shopping_bag_outlined, size: compact ? 16 : 18),
        label: Text(
          'Ver productos de la orden',
          style: TextStyle(
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.botonPrincipal,
          foregroundColor: AppColors.onAccentButton,
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14 : 18,
            vertical: compact ? 10 : 12,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
