import 'package:flutter/material.dart';

/// Colores oficiales de VolonexPro+
/// NUNCA usar Theme.of(context).colorScheme - SIEMPRE usar estos colores específicos
class AppColors {
  // COLORES OFICIALES VOLONEXPRO+
  
  /// Header/AppBar: Azul gris oscuro del header "Información de Envío"
  static const Color header = Color(0xFF37474F);
  
  /// Verde Secciones: Verde vibrante como en "Selecciona método de envío"
  static const Color verdeSecciones = Color(0xFF4CAF50);
  
  /// Botones Principales: Naranja energético como "Proceder al Pago"
  static const Color botonPrincipal = Color(0xFFFF9800);
  
  /// Cards/Fondos: Blanco puro
  static const Color cardFondo = Color(0xFFFFFFFF);
  
  /// Texto Principal: Negro para títulos
  static const Color textoPrincipal = Color(0xFF2C2C2C);
  
  /// Texto Secundario: Gris para subtítulos
  static const Color textoSecundario = Color(0xFF666666);
  
  /// Éxito/Confirmación: Verde para totales y éxito
  static const Color exito = Color(0xFF4CAF50);
  
  /// Error/Cancelar: Rojo para errores
  static const Color error = Color(0xFFDC2626);
  
  /// Fondo General: Gris muy claro
  static const Color fondoGeneral = Color(0xFFF5F5F5);

  // Tema oscuro VolonexPro+ (modales / login / paneles compactos)
  static const Color darkBg = Color(0xFF12151C);
  static const Color darkSurface = Color(0xFF1E232E);
  static const Color darkElevated = Color(0xFF252A35);
  static const Color darkBorder = Color(0xFF455A64);
  static const Color darkText = Color(0xFFECEFF1);
  static const Color darkTextMuted = Color(0xFF9CA3AF);
  
  /// Azul para información
  static const Color info = Color(0xFF2196F3);
  
  /// Gris para bordes
  static const Color borde = Color(0xFFE0E0E0);
  
  // Alias para compatibilidad
  static const Color primary = Color(0xFF1976D2); // Azul principal
  static const Color accent = Color(0xFFFF9800); // Naranja de acento (igual que botonPrincipal)
  static const Color success = Color(0xFF4CAF50); // Verde para éxito (igual que exito)
  static const Color warning = Color(0xFFFFC107); // Amarillo para advertencias
  static const Color bordeClaro = Color(0xFFE0E0E0); // Alias de borde
  
  // PROHIBIDO usar:
  // - Theme.of(context).colorScheme.primary
  // - Colors.blue, Colors.green (usar códigos específicos)
  // - Cualquier color que no esté en esta lista
}

