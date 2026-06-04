import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../config/app_colors.dart';
import '../widgets/volonex_dialog.dart';

/// Pantalla de aviso destacado para permiso de ubicación
/// REQUERIDO por Google Play: Debe mostrarse ANTES de solicitar cualquier permiso del sistema
/// Esta pantalla es OBLIGATORIA y no se puede omitir
class AvisoUbicacionDestacadoScreen extends StatefulWidget {
  final VoidCallback onContinuar;

  const AvisoUbicacionDestacadoScreen({
    super.key,
    required this.onContinuar,
  });

  @override
  State<AvisoUbicacionDestacadoScreen> createState() => _AvisoUbicacionDestacadoScreenState();
}

class _AvisoUbicacionDestacadoScreenState extends State<AvisoUbicacionDestacadoScreen> {
  bool _solicitandoPermisos = false;

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // REQUERIDO por Google Play: No permitir cerrar sin aceptar explícitamente
        // El usuario debe presionar "Continuar" para proceder
        return false; // Bloquear el botón de atrás
      },
      child: Scaffold(
        backgroundColor: AppColors.darkBg,
        body: SafeArea(
          child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              // Icono de ubicación grande y destacado
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on,
                  size: 70,
                  color: Color(0xFF4CAF50),
                ),
              ),
              const SizedBox(height: 24),
              
              // Título principal
              const Text(
                'Acceso a Ubicación Requerido',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkText,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              
              // Subtítulo - Formato recomendado por Google Play
              const Text(
                'VolonexPro+ recopila datos de ubicación para habilitar el rastreo de entregas en tiempo real durante tu jornada laboral.',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.darkTextMuted,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              
              // Sección de información destacada
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.darkElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFF4CAF50),
                    width: 2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.info_outline,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            '¿Por qué necesitamos tu ubicación?',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.darkText,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildRazon(
                      icon: Icons.delivery_dining,
                      titulo: 'Rastreo de Entregas',
                      descripcion: 'Permite rastrear tus entregas en tiempo real durante tu jornada laboral',
                    ),
                    const SizedBox(height: 12),
                    _buildRazon(
                      icon: Icons.location_searching,
                      titulo: 'Visibilidad para Clientes',
                      descripcion: 'Los clientes pueden ver la ubicación de sus paquetes en tiempo real',
                    ),
                    const SizedBox(height: 12),
                    _buildRazon(
                      icon: Icons.security,
                      titulo: 'Seguridad',
                      descripcion: 'Garantiza tu seguridad durante las entregas al permitir que tu agencia conozca tu ubicación',
                    ),
                    const SizedBox(height: 12),
                    _buildRazon(
                      icon: Icons.route,
                      titulo: 'Optimización de Rutas',
                      descripcion: 'Ayuda a optimizar rutas y mejorar la eficiencia operativa',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              
              // Información de privacidad
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.darkSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_outline,
                      color: AppColors.darkTextMuted,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Los datos de ubicación se recopilan y transmiten únicamente durante tu jornada laboral activa y se comparten exclusivamente con tu agencia para gestionar las entregas.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.darkTextMuted,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              
              Center(
                child: ElevatedButton(
                  onPressed: _solicitandoPermisos ? null : () async {
                    setState(() {
                      _solicitandoPermisos = true;
                    });
                    
                    try {
                      // Marcar que el usuario ha visto el aviso
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('aviso_ubicacion_destacado_visto', true);
                      
                      print('✅ Usuario aceptó el aviso destacado');
                      print('📍 Ahora solicitando permisos del sistema...');
                      
                      // CRÍTICO: Solicitar permisos del sistema INMEDIATAMENTE después del aviso
                      // Esto es lo que el usuario espera ver
                      
                      // 1. Verificar si los servicios de ubicación están habilitados
                      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
                      if (!serviceEnabled) {
                        print('⚠️ Servicios de ubicación deshabilitados');
                        // Mostrar mensaje al usuario
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Por favor, habilita los servicios de ubicación en tu dispositivo'),
                              backgroundColor: Color(0xFFFF9800),
                              duration: Duration(seconds: 3),
                            ),
                          );
                        }
                      }
                      
                      // 2. Solicitar permiso básico de ubicación (whileInUse)
                      print('📍 Solicitando permiso de ubicación básico...');
                      
                      try {
                        LocationPermission permission = await Geolocator.checkPermission();
                        print('📍 Estado actual: $permission');
                        
                        if (permission == LocationPermission.denied) {
                          print('📍 Abriendo diálogo del sistema para solicitar permiso...');
                          permission = await Geolocator.requestPermission();
                          print('📍 Usuario respondió: $permission');
                        }
                        
                        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
                          print('❌ Usuario denegó los permisos de ubicación');
                          // Mostrar mensaje
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Los permisos de ubicación son necesarios para usar la app'),
                                backgroundColor: Color(0xFFDC2626),
                                duration: Duration(seconds: 3),
                              ),
                            );
                          }
                        } else {
                          print('✅ Permiso básico concedido: $permission');
                        }
                      } catch (e) {
                        print('❌ Error al solicitar permisos: $e');
                        // Si hay error, mostrar mensaje pero continuar de todas formas
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error al solicitar permisos. Por favor, habilítalos manualmente en Configuración.'),
                              backgroundColor: const Color(0xFFFF9800),
                              duration: const Duration(seconds: 4),
                            ),
                          );
                        }
                      }
                      
                      // 3. Cerrar la pantalla y continuar (incluso si hubo error, para no bloquear al usuario)
                      print('📍 Navegando a pantalla principal...');
                      if (mounted && Navigator.of(context).canPop()) {
                        Navigator.of(context).pop(true);
                      }
                      
                      // Pequeño delay para asegurar que la navegación se complete
                      await Future.delayed(const Duration(milliseconds: 300));
                      
                      // Llamar al callback que navegará a la pantalla principal
                      if (mounted) {
                        widget.onContinuar();
                      }
                    } catch (e) {
                      print('❌ Error general solicitando permisos: $e');
                      if (mounted) {
                        setState(() {
                          _solicitandoPermisos = false;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: const Color(0xFFDC2626),
                            duration: const Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.exito,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                  child: _solicitandoPermisos
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.arrow_forward, size: 22),
                            SizedBox(width: 10),
                            Text(
                              'Continuar',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 12),
              
              // Texto informativo - REQUERIDO por Google Play
              const Text(
                'Al continuar, se te solicitará el permiso de ubicación del sistema. Este aviso cumple con los requisitos de Google Play para transparencia en el uso de datos.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.darkTextMuted,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildRazon({
    required IconData icon,
    required String titulo,
    required String descripcion,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50).withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF4CAF50),
            size: 24,
          ),
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
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkText,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                descripcion,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.darkTextMuted,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

