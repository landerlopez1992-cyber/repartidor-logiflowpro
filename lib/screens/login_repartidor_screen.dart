import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'dart:async';
import 'dart:io' show Platform;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../services/repartidor_seguridad_service.dart';
import '../services/repartidor_suspension_service.dart';
import 'repartidor_mobile_screen.dart';
import 'aviso_ubicacion_destacado_screen.dart';
import 'loading_data_screen.dart';
import '../services/sesion_offline_cleanup.dart';
import '../services/auth_error_handler.dart';
import '../services/repartidor_boot_cache_service.dart';
import '../services/tenant_fuera_servicio_service.dart';
import '../config/app_colors.dart';
import '../navigation/repartidor_navigator.dart';
import '../widgets/volonex_dialog.dart';
import '../widgets/repartidor_loading_spinner.dart';
import 'tenant_fuera_servicio_screen.dart';

class LoginRepartidorScreen extends StatefulWidget {
  const LoginRepartidorScreen({super.key});

  @override
  State<LoginRepartidorScreen> createState() => _LoginRepartidorScreenState();
}

class _LoginRepartidorScreenState extends State<LoginRepartidorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  // Función helper para detectar si es iOS/Android (solo móviles).
  // Excepción temporal: macOS permitido solo el 2026-07-21 para pruebas.
  bool get _esMovilSolo {
    if (kIsWeb) return false; // Web no es móvil
    if (defaultTargetPlatform == TargetPlatform.windows ||
        (!kIsWeb && Platform.isWindows)) {
      return false; // Windows no es móvil
    }

    // Permitir Mac solo hoy (pruebas); se desactiva solo al cambiar el día.
    if (!kIsWeb &&
        (Platform.isMacOS || defaultTargetPlatform == TargetPlatform.macOS)) {
      final now = DateTime.now();
      const y = 2026;
      const m = 7;
      const d = 21;
      return now.year == y && now.month == m && now.day == d;
    }

    final isMobile =
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    return isMobile;
  }

  static const String _kLogiflowProLogoUrl = 'https://www.logiflowpro.com/assets/logo.png?v=9';
  static const double _kLoginBrandLogoSize = 220;

  Widget _loginBrandLogo() {
    return Image.asset(
      'assets/www.logiflowpro.com.png',
      width: _kLoginBrandLogoSize,
      height: _kLoginBrandLogoSize,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return Image.network(
          _kLogiflowProLogoUrl,
          width: _kLoginBrandLogoSize,
          height: _kLoginBrandLogoSize,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return SizedBox(
              width: _kLoginBrandLogoSize,
              height: _kLoginBrandLogoSize,
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: loadingProgress.expectedTotalBytes != null
                      ? loadingProgress.cumulativeBytesLoaded /
                          loadingProgress.expectedTotalBytes!
                      : null,
                  color: const Color(0xFF81C784),
                ),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return const Icon(
              Icons.local_shipping,
              size: 96,
              color: Color(0xFF81C784),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    // ✅ VALIDAR PLATAFORMA: Solo iOS/Android pueden usar esta pantalla
    if (!_esMovilSolo) {
      _mostrarError(
        'Esta aplicación es solo para repartidores en dispositivos móviles (iOS/Android).\n\n'
            'Si eres administrador o empleado, usa la aplicación de Windows o accede desde la web.',
        'Acceso Denegado',
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // Autenticar primero. NO borrar caché offline antes: si falla el login
      // (o no hay internet), el socio debe poder seguir abriendo con su sesión.
      final response = await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (response.user != null) {
        // Verificar que el usuario es un repartidor
        final userResponse = await supabase
            .from('usuarios')
            .select('rol, nombre, tenant_id, auth_id, cuenta_suspendida')
            .eq('auth_id', response.user!.id)
            .single()
            .onError((error, stackTrace) async {
              // Si no se encuentra por auth_id, intentar por email
              final userEmail = response.user!.email;
              if (userEmail != null) {
                return await supabase
                    .from('usuarios')
                    .select('rol, nombre, tenant_id, auth_id, cuenta_suspendida')
                    .eq('email', userEmail)
                    .single();
              }
              throw error!;
            });

        final rol = userResponse['rol']?.toString().toUpperCase();

        if (rol == 'REPARTIDOR') {
          // Tras login OK: limpiar datos de OTRO usuario, luego guardar el actual.
          try {
            final prefs = await SharedPreferences.getInstance();
            final nuevoId = response.user!.id;
            final anterior = prefs.getString(kLastRepartidorAuthIdKey);
            if (anterior != null &&
                anterior.isNotEmpty &&
                anterior != nuevoId) {
              final keys = prefs.getKeys().toList();
              for (final key in keys) {
                if (key.startsWith('cached_') && key.contains(anterior)) {
                  await prefs.remove(key);
                }
              }
              await SesionOfflineCleanup.limpiarTodo();
              print('🧹 Caché del usuario anterior ($anterior) limpiado');
            }

            await prefs.setString(
              'cached_user_data_$nuevoId',
              jsonEncode(userResponse),
            );
            await prefs.setString(kLastRepartidorAuthIdKey, nuevoId);
            await prefs.setString(
              kRepartidorOfflineSessionKey,
              jsonEncode({
                'auth_id': nuevoId,
                'rol': 'REPARTIDOR',
                'user_data': userResponse,
                'validated_at': DateTime.now().toIso8601String(),
              }),
            );
            final tid = userResponse['tenant_id']?.toString();
            if (tid != null && tid.isNotEmpty) {
              await prefs.setString(
                'cached_tenant_id_${response.user!.id}',
                tid,
              );
            }
            print('💾 Datos de usuario guardados en caché para uso offline');
          } catch (e) {
            print('⚠️ Error guardando caché de usuario: $e');
          }

          final suspendido = RepartidorSuspensionService.esSuspendidoFlag(
            userResponse['cuenta_suspendida'],
          );
          // Suspensión no bloquea el login: se aplica en Viajes / ajustes taxi.
          if (suspendido) {
            await RepartidorSuspensionService.instance
                .marcarSuspendidoEnCache(true);
          }
          // Obtener información de la empresa para el modal
          String? empresaNombre = 'Tu empresa';
          String? empresaLogoUrl;

          String? tenantId = userResponse['tenant_id'];
          if (tenantId != null) {
            try {
              final tenantData = await supabase
                  .from('tenants')
                  .select('nombre, logo_url')
                  .eq('id', tenantId)
                  .maybeSingle();

              if (tenantData != null) {
                empresaNombre = tenantData['nombre'] ?? 'Tu empresa';
                empresaLogoUrl = tenantData['logo_url'];
                await RepartidorSeguridadService.guardarNombreEmpresaEnCache(
                  response.user!.id,
                  empresaNombre ?? 'Tu empresa',
                );
              }
            } catch (e) {
              print('⚠️ Error obteniendo datos de empresa: $e');
            }
          }

          // Mostrar modal de carga
          if (mounted) {
            await _mostrarModalInicioSistema(
              empresaNombre ?? 'Tu empresa',
              empresaLogoUrl,
            );
          }

          // CRÍTICO: Mostrar aviso destacado ANTES de navegar a la pantalla principal
          // REQUERIDO por Google Play: El aviso debe aparecer ANTES de solicitar cualquier permiso
          if (mounted) {
            // Verificar si ya se mostró el aviso destacado
            final prefs = await SharedPreferences.getInstance();
            final avisoVisto =
                prefs.getBool('aviso_ubicacion_destacado_visto') ?? false;

            if (!avisoVisto) {
              // Mostrar pantalla de aviso destacado (obligatoria)
              final resultado = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (context) => AvisoUbicacionDestacadoScreen(
                    onContinuar: () {
                      // La pantalla se cierra automáticamente en el botón
                      // Navegar a pantalla de carga que precargará datos
                      _navegarAPantallaCarga(empresaNombre, empresaLogoUrl);
                    },
                  ),
                  fullscreenDialog:
                      true, // Hace que sea modal y no se pueda cerrar con back
                ),
              );

              // Si el usuario no aceptó, no continuar
              if (resultado != true && mounted) {
                return; // No navegar si no aceptó
              }
            } else {
              // Ya se mostró antes, navegar a pantalla de carga directamente
              _navegarAPantallaCarga(empresaNombre, empresaLogoUrl);
            }
          }
        } else {
          // No es repartidor
          await supabase.auth.signOut();
          _mostrarError('Este usuario no es un repartidor autorizado');
        }
      }
    } catch (e) {
      // Manejar errores de autenticación de forma amigable
      final friendlyMessage = AuthErrorHandler.getFriendlyErrorMessage(e);
      final isEmailNotConfirmed = AuthErrorHandler.isEmailNotConfirmedError(e);

      if (mounted) {
        _mostrarError(
          friendlyMessage,
          isEmailNotConfirmed
              ? 'Confirma tu correo electrónico'
              : 'Error al iniciar sesión',
        );
      }

      // Log del error técnico para debugging (solo en consola, no visible para el usuario)
      print('❌ Error técnico de autenticación: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _mostrarModalInicioSistema(
    String empresaNombre,
    String? empresaLogoUrl,
  ) async {
    // Mostrar modal de carga
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo de la empresa
              if (empresaLogoUrl != null && empresaLogoUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    empresaLogoUrl,
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: const Color(0xFF37474F),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            empresaNombre.isNotEmpty
                                ? empresaNombre[0].toUpperCase()
                                : 'L',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                )
              else
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFF37474F),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      empresaNombre.isNotEmpty
                          ? empresaNombre[0].toUpperCase()
                          : 'L',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),

              // Nombre de la empresa
              Text(
                empresaNombre,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkText,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Texto de carga
              const Text(
                'Iniciando sistema de paquetería...',
                style: TextStyle(fontSize: 16, color: AppColors.darkTextMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Icono de carga (mismo que app móvil)
              const RepartidorLoadingSpinner.large(
                color: AppColors.botonPrincipal,
              ),
            ],
          ),
        ),
      ),
    );

    // Esperar mínimo 2-3 segundos
    await Future.delayed(const Duration(seconds: 3));

    // Cerrar el modal
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _mostrarError(String mensaje, [String? title]) {
    if (!mounted) return;
    final esConfirmarCorreo =
        title?.toLowerCase().contains('confirmar') == true;
    showVolonexMessageDialog(
      context,
      title: title ?? 'Error',
      message: mensaje,
      isError: !esConfirmarCorreo,
      buttonLabel: 'Entendido',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 340),
                margin: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.1),
                        Colors.white.withOpacity(0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Logo oficial (sin halo circular detrás)
                          _loginBrandLogo(),
                          const SizedBox(height: 16),

                          // Título (sin marca de plataforma)
                          const Text(
                            'Repartidor',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),

                          // Subtítulo
                          Text(
                            'Sistema de Repartidores',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                              letterSpacing: 0.2,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),

                          // Campo Email - Diseño oscuro moderno
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withOpacity(0.1),
                                  Colors.white.withOpacity(0.05),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.95),
                                fontSize: 14,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Correo electrónico',
                                labelStyle: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                prefixIcon: Icon(
                                  Icons.email_outlined,
                                  color: const Color(0xFF64B5F6),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: const Color(
                                      0xFF64B5F6,
                                    ).withOpacity(0.6),
                                    width: 2,
                                  ),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: const Color(
                                      0xFFDC2626,
                                    ).withOpacity(0.6),
                                    width: 1,
                                  ),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFDC2626),
                                    width: 2,
                                  ),
                                ),
                                errorStyle: TextStyle(
                                  color: const Color(0xFFFF6B6B),
                                  fontSize: 12,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                filled: true,
                                fillColor: Colors.transparent,
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Por favor ingresa tu correo electrónico';
                                }
                                if (!RegExp(
                                  r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                                ).hasMatch(value)) {
                                  return 'Por favor ingresa un correo válido';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Campo Contraseña - Diseño oscuro moderno
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withOpacity(0.1),
                                  Colors.white.withOpacity(0.05),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: TextFormField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.95),
                                fontSize: 14,
                              ),
                              decoration: InputDecoration(
                                labelText: 'Contraseña',
                                labelStyle: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                                prefixIcon: Icon(
                                  Icons.lock_outline,
                                  color: const Color(0xFF64B5F6),
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                    color: Colors.white.withOpacity(0.7),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: const Color(
                                      0xFF64B5F6,
                                    ).withOpacity(0.6),
                                    width: 2,
                                  ),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: const Color(
                                      0xFFDC2626,
                                    ).withOpacity(0.6),
                                    width: 1,
                                  ),
                                ),
                                focusedErrorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFDC2626),
                                    width: 2,
                                  ),
                                ),
                                errorStyle: TextStyle(
                                  color: const Color(0xFFFF6B6B),
                                  fontSize: 12,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                filled: true,
                                fillColor: Colors.transparent,
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Por favor ingresa tu contraseña';
                                }
                                if (value.length < 6) {
                                  return 'La contraseña debe tener al menos 6 caracteres';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Botón de Login - Diseño oscuro moderno
                          Container(
                            width: double.infinity,
                            height: 50,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF64B5F6), Color(0xFF2196F3)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF2196F3,
                                  ).withOpacity(0.5),
                                  blurRadius: 15,
                                  offset: const Offset(0, 5),
                                  spreadRadius: 0,
                                ),
                              ],
                            ),
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _login,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _isLoading
                                  ? const RepartidorLoadingSpinner.small(
                                      color: Colors.white,
                                    )
                                  : const Text(
                                      'INICIAR SESIÓN',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Información adicional
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white.withOpacity(0.1),
                                  Colors.white.withOpacity(0.05),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.2),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: const Color(0xFF64B5F6),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Solo repartidores autorizados pueden acceder',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Footer
                          Text(
                            'Versión 1.0.0',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Navega a la pantalla de carga que precarga datos (caché offline-first).
  void _navegarAPantallaCarga(String? empresaNombre, String? empresaLogoUrl) {
    if (!mounted) return;

    final user = supabase.auth.currentUser;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => LoadingDataScreen(
          empresaNombre: empresaNombre,
          empresaLogoUrl: empresaLogoUrl,
          onLoadData: (updateProgress) async {
            final boot = RepartidorBootCacheService.instance;
            if (user != null) {
              await boot.saveEmpresa(
                authUserId: user.id,
                nombre: empresaNombre,
                logoUrl: empresaLogoUrl,
              );
              if (empresaLogoUrl != null && empresaLogoUrl.isNotEmpty) {
                final local =
                    await boot.cacheLogoToDisk(empresaLogoUrl, user.id);
                if (local != null) {
                  await boot.saveEmpresa(
                    authUserId: user.id,
                    nombre: empresaNombre,
                    logoUrl: empresaLogoUrl,
                    logoLocalPath: local,
                  );
                }
              }
            }
            await boot.runBootLoad(updateProgress: updateProgress);
          },
          onComplete: () {
            // Login ya fue reemplazado por LoadingDataScreen → `mounted` del
            // login es false. Navegar con la clave global del Navigator.
            unawaited(_irAHomeOFueraServicio());
          },
        ),
      ),
    );
  }

  Future<void> _irAHomeOFueraServicio() async {
    final nav = RepartidorNavigator.state;
    if (nav == null) {
      print('❌ Post-login: Navigator global no disponible');
      return;
    }
    try {
      final user = supabase.auth.currentUser;
      String? tenantId;
      if (user != null) {
        final prefs = await SharedPreferences.getInstance();
        tenantId = prefs.getString('cached_tenant_id_${user.id}');
        if (tenantId == null || tenantId.isEmpty) {
          final raw = prefs.getString('cached_user_data_${user.id}');
          if (raw != null && raw.isNotEmpty) {
            try {
              final m = jsonDecode(raw) as Map<String, dynamic>;
              tenantId = m['tenant_id']?.toString();
            } catch (_) {}
          }
        }
        if (tenantId == null || tenantId.isEmpty) {
          final row = await supabase
              .from('usuarios')
              .select('tenant_id')
              .eq('auth_id', user.id)
              .maybeSingle()
              .timeout(const Duration(seconds: 5));
          tenantId = row?['tenant_id']?.toString();
        }
      }
      if (tenantId != null && tenantId.isNotEmpty) {
        final fuera = await TenantFueraServicioService.fetch(
          tenantId: tenantId,
          forceRefresh: true,
        ).timeout(const Duration(seconds: 6));
        if (fuera?.bloqueada == true) {
          nav.pushReplacement(
            MaterialPageRoute(
              builder: (_) => TenantFueraServicioScreen(tenantId: tenantId!),
            ),
          );
          return;
        }
      }
    } catch (e) {
      print('⚠️ Check fuera de servicio post-login: $e');
    }
    nav.pushReplacement(
      MaterialPageRoute(
        builder: (context) => const RepartidorMobileScreen(),
      ),
    );
  }
}
