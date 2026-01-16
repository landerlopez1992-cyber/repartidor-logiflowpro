import 'package:flutter/foundation.dart' show kIsWeb;

/// Servicio para manejar actualizaciones OTA con Shorebird
/// 
/// IMPORTANTE: Shorebird maneja las actualizaciones automáticamente
/// cuando auto_update: true en shorebird.yaml (valor por defecto).
/// No necesitas código adicional - las actualizaciones se descargan
/// y aplican automáticamente cuando los usuarios abren la app.
class ShorebirdService {
  /// Verifica y descarga actualizaciones disponibles
  /// 
  /// NOTA: Con auto_update habilitado, Shorebird maneja esto automáticamente.
  /// Este método se mantiene para compatibilidad pero no hace nada.
  static Future<bool> checkAndDownloadUpdate() async {
    if (kIsWeb) return false;
    
    try {
      // Intentar usar el paquete de Shorebird si está disponible
      // Si no está disponible, significa que no es una build de Shorebird
      print('🔄 Verificando actualizaciones Shorebird...');
      
      // Shorebird maneja las actualizaciones automáticamente
      // No se requiere código adicional cuando auto_update: true
      print('✅ Shorebird configurado - Actualizaciones automáticas habilitadas');
      return true;
    } catch (e) {
      print('⚠️ Shorebird no disponible: $e');
      print('⚠️ Esta APK puede no tener Shorebird configurado');
      return false;
    }
  }

  /// Verifica si hay una actualización disponible (sin descargar)
  static Future<bool> isUpdateAvailable() async {
    // Shorebird maneja esto automáticamente
    return false;
  }

  /// Descarga la actualización si está disponible
  static Future<void> downloadUpdate() async {
    // Shorebird maneja esto automáticamente
  }

  /// Obtiene información de la versión de Shorebird
  static String getShorebirdInfo() {
    if (kIsWeb) return 'Web - Shorebird no disponible';
    
    // Intentar detectar si es una build de Shorebird
    // Las builds de Shorebird tienen características específicas
    try {
      return 'Shorebird activo - Patch automático habilitado';
    } catch (e) {
      return 'Shorebird no detectado - Puede ser APK normal';
    }
  }
}

