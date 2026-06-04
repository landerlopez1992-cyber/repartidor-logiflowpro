import 'package:flutter/material.dart';

/// Colores oficiales VolonexPro+ (app Repartidor — tema oscuro).
/// Usar [darkText] / [darkTextMuted] en textos; nunca grises oscuros (#2C2C2C, #666) sobre fondos oscuros.
class AppColors {
  // —— Tema oscuro (principal) ——
  static const Color darkBg = Color(0xFF12151C);
  static const Color darkSurface = Color(0xFF1E232E);
  static const Color darkElevated = Color(0xFF252A35);
  static const Color darkBorder = Color(0xFF455A64);
  static const Color darkText = Color(0xFFECEFF1);
  static const Color darkTextMuted = Color(0xFF9CA3AF);

  /// Header / AppBar
  static const Color header = Color(0xFF37474F);

  static const Color verdeSecciones = Color(0xFF4CAF50);
  static const Color botonPrincipal = Color(0xFFFF9800);

  /// Alias históricos → tema oscuro
  static const Color cardFondo = darkSurface;
  static const Color textoPrincipal = darkText;
  static const Color textoSecundario = darkTextMuted;
  static const Color fondoGeneral = darkBg;

  static const Color exito = Color(0xFF4CAF50);
  static const Color error = Color(0xFFDC2626);

  static const Color info = Color(0xFF2196F3);
  static const Color borde = Color(0xFF455A64);

  static const Color primary = Color(0xFF2196F3);
  static const Color accent = Color(0xFFFF9800);
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);
  static const Color bordeClaro = darkBorder;

  /// Texto sobre botón naranja/verde/rojo (siempre claro)
  static const Color onAccentButton = Color(0xFFFFFFFF);

  /// Texto sobre fondos claros (diálogo blanco, pantalla remesa dorada)
  static const Color textOnLight = Color(0xFF2C2C2C);
  static const Color textMutedOnLight = Color(0xFF5D4037);
}
