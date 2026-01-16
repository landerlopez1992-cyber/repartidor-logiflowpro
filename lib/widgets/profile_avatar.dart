import 'package:flutter/material.dart';

class ProfileAvatar extends StatelessWidget {
  final String? fotoUrl;
  final String nombre;
  final double radius;
  final Color backgroundColor;
  final Color textColor;
  final double fontSize;

  const ProfileAvatar({
    super.key,
    this.fotoUrl,
    required this.nombre,
    this.radius = 20,
    this.backgroundColor = const Color(0xFF4CAF50),
    this.textColor = Colors.white,
    this.fontSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    // Validar que la foto URL sea válida
    final urlValida = fotoUrl != null && 
                      fotoUrl!.isNotEmpty && 
                      fotoUrl!.trim().isNotEmpty &&
                      (fotoUrl!.startsWith('http://') || fotoUrl!.startsWith('https://'));
    
    debugPrint('ProfileAvatar - fotoUrl: "$fotoUrl", urlValida: $urlValida, nombre: "$nombre"');
    
    // Si no hay foto URL válida, mostrar iniciales directamente
    if (!urlValida) {
      return _buildInitials();
    }
    
    // Si hay foto URL válida, intentar mostrar la imagen con fallback a iniciales
    return ClipOval(
      child: Image.network(
        fotoUrl!,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          // Si falla la carga, mostrar iniciales
          debugPrint('❌ Error cargando foto de perfil: $error');
          return _buildInitials();
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            return child;
          }
          // Mientras carga, mostrar iniciales temporalmente
          return _buildInitials();
        },
      ),
    );
  }

  Widget _buildInitials() {
    // Obtener la primera letra del nombre, limpiando espacios
    final nombreLimpio = nombre.trim();
    final inicial = nombreLimpio.isNotEmpty 
        ? nombreLimpio.substring(0, 1).toUpperCase()
        : 'U';
    
    debugPrint('ProfileAvatar - Nombre: "$nombre", Inicial: "$inicial", FotoUrl: "$fotoUrl"');
    
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          inicial,
          style: TextStyle(
            color: textColor,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}




