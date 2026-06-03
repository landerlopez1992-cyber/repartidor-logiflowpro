import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Clase para mostrar el aviso de ubicación en segundo plano
/// REQUERIDO por Google Play cuando se solicita ACCESS_BACKGROUND_LOCATION (permiso "Permitir todo el tiempo")
/// Este aviso debe mostrarse ANTES de solicitar el permiso de segundo plano
/// Referencia: https://support.google.com/googleplay/android-developer/answer/9799150
class AvisoUbicacionSegundoPlanoScreen {
  AvisoUbicacionSegundoPlanoScreen._(); // Constructor privado para evitar instancias

  /// Mostrar el aviso destacado si el usuario no lo ha visto antes
  static Future<bool> mostrarSiNecesario(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final yaVisto = prefs.getBool('aviso_ubicacion_segundo_plano_visto') ?? false;
    
    if (yaVisto) {
      print('✅ Aviso de segundo plano ya fue visto anteriormente');
      return false; // Ya se mostró antes, no mostrar de nuevo
    }

    print('📍 Mostrando aviso de segundo plano...');
    
    // Verificar que el contexto sigue siendo válido
    if (!context.mounted) {
      print('❌ Contexto no válido');
      return false;
    }

    // Mostrar el aviso destacado usando showDialog
    bool? resultado;
    try {
      resultado = await showDialog<bool>(
        context: context,
        barrierDismissible: false, // No permitir cerrar tocando fuera
        barrierColor: Colors.black87, // Fondo oscuro
        useRootNavigator: true, // Usar el navigator raíz
        builder: (dialogContext) {
          print('📍 Construyendo diálogo de segundo plano');
          return const AvisoUbicacionSegundoPlanoDialog();
        },
      );
      
      print('📍 Resultado del diálogo: $resultado');
    } catch (e) {
      print('❌ Error mostrando diálogo de segundo plano: $e');
      return false;
    }

    // Guardar que ya se mostró solo si el usuario aceptó
    if (resultado == true) {
      await prefs.setBool('aviso_ubicacion_segundo_plano_visto', true);
      print('✅ Aviso aceptado y guardado');
    } else {
      print('⚠️ Aviso rechazado');
    }

    return resultado ?? false;
  }
}

/// Diálogo para mostrar el aviso de ubicación en segundo plano
class AvisoUbicacionSegundoPlanoDialog extends StatefulWidget {
  const AvisoUbicacionSegundoPlanoDialog({super.key});

  @override
  State<AvisoUbicacionSegundoPlanoDialog> createState() => _AvisoUbicacionSegundoPlanoDialogState();
}

class _AvisoUbicacionSegundoPlanoDialogState extends State<AvisoUbicacionSegundoPlanoDialog> {
  bool _procesando = false; // Evitar múltiples toques
  
  void _manejarRechazo() {
    if (_procesando) {
      print('⚠️ Ya se está procesando el rechazo, ignorando toque adicional');
      return;
    }
    print('📍 [BOTÓN] Usuario presionó Rechazar');
    setState(() {
      _procesando = true;
      print('📍 [ESTADO] _procesando = true');
    });
    
    // Cerrar inmediatamente
    Future.microtask(() {
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        print('📍 [NAVEGACIÓN] Cerrando diálogo con resultado: false');
        Navigator.of(context, rootNavigator: true).pop(false);
      } else {
        print('⚠️ [NAVEGACIÓN] No se puede cerrar el diálogo (contexto inválido)');
      }
    });
  }
  
  void _manejarAceptacion() {
    if (_procesando) {
      print('⚠️ Ya se está procesando la aceptación, ignorando toque adicional');
      return;
    }
    print('📍 [BOTÓN] Usuario presionó Aceptar');
    setState(() {
      _procesando = true;
      print('📍 [ESTADO] _procesando = true');
    });
    
    // Cerrar inmediatamente
    Future.microtask(() {
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        print('📍 [NAVEGACIÓN] Cerrando diálogo con resultado: true');
        Navigator.of(context, rootNavigator: true).pop(true);
      } else {
        print('⚠️ [NAVEGACIÓN] No se puede cerrar el diálogo (contexto inválido)');
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    print('📍 Construyendo widget del diálogo de segundo plano');
    return WillPopScope(
      onWillPop: () async {
        // REQUERIDO por Google Play: No permitir cerrar sin aceptar explícitamente
        // El usuario debe presionar "Aceptar" o "Rechazar" para proceder
        return false; // Bloquear el botón de atrás
      },
      child: AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        contentPadding: const EdgeInsets.all(24),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icono
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on,
                  size: 56,
                  color: Color(0xFF4CAF50),
                ),
              ),
              const SizedBox(height: 24),
              
              // Título
              const Text(
                'Permiso de Ubicación en Segundo Plano',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C2C2C),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              
              // Descripción principal - Formato recomendado por Google Play
              const Text(
                'VolonexPro+ recopila datos de ubicación para habilitar el rastreo de entregas en tiempo real, incluso cuando la app está cerrada o no está en uso.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF666666),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              
              // Información detallada
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoItem(
                      Icons.check_circle,
                      'Solo durante tu jornada laboral',
                    ),
                    const SizedBox(height: 12),
                    _buildInfoItem(
                      Icons.security,
                      'Datos protegidos y cifrados',
                    ),
                    const SizedBox(height: 12),
                    _buildInfoItem(
                      Icons.business,
                      'Compartido únicamente con tu agencia',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              
              // Nota importante
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF9800).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFFF9800).withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Color(0xFFFF9800),
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'En la siguiente ventana, selecciona "Permitir todo el tiempo"',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF666666),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              // Botones
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        print('📍 [ONPRESSED] Botón Rechazar presionado');
                        _manejarRechazo();
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFFDC2626), width: 2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        _procesando ? 'Cerrando...' : 'Rechazar',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        print('📍 [ONPRESSED] Botón Aceptar presionado');
                        _manejarAceptacion();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        _procesando ? 'Cerrando...' : 'Aceptar',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildInfoItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(
          icon,
          color: const Color(0xFF4CAF50),
          size: 18,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF666666),
            ),
          ),
        ),
      ],
    );
  }
}
