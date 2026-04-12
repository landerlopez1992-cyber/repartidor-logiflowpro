import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'dart:io' show Platform;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import 'repartidor_mobile_screen.dart';
import 'aviso_ubicacion_destacado_screen.dart';
import 'loading_data_screen.dart';
import '../services/orden_cache_service.dart';
import '../services/auth_error_handler.dart';
import '../services/sync_service.dart';

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

  // Función helper para detectar si es iOS/Android (solo móviles)
  bool get _esMovilSolo {
    if (kIsWeb) return false; // Web no es móvil
    if (defaultTargetPlatform == TargetPlatform.windows ||
        (!kIsWeb && Platform.isWindows))
      return false; // Windows no es móvil
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
      // 🔒 CRÍTICO: Limpiar TODOS los cachés de cualquier sesión anterior ANTES de iniciar sesión
      // Esto previene que el nuevo usuario vea datos del anterior
      try {
        final prefs = await SharedPreferences.getInstance();
        final keys = prefs.getKeys();
        for (final key in keys) {
          if (key.startsWith('cached_')) {
            await prefs.remove(key);
          }
        }

        // 🔒 CRÍTICO: Limpiar caché de órdenes
        await OrdenCacheService.clearCache();

        print('🧹 TODOS los cachés de sesiones anteriores limpiados');
      } catch (cacheError) {
        print('⚠️ Error limpiando cachés: $cacheError');
      }

      // Autenticar con Supabase
      final response = await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (response.user != null) {
        // Verificar que el usuario es un repartidor
        final userResponse = await supabase
            .from('usuarios')
            .select('rol, nombre, tenant_id, auth_id')
            .eq('auth_id', response.user!.id)
            .single()
            .onError((error, stackTrace) async {
              // Si no se encuentra por auth_id, intentar por email
              final userEmail = response.user!.email;
              if (userEmail != null) {
                return await supabase
                    .from('usuarios')
                    .select('rol, nombre, tenant_id, auth_id')
                    .eq('email', userEmail)
                    .single();
              }
              throw error!;
            });

        final rol = userResponse['rol']?.toString().toUpperCase();

        if (rol == 'REPARTIDOR') {
          // 💾 Guardar datos de usuario en caché para uso offline
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString(
              'cached_user_data_${response.user!.id}',
              jsonEncode(userResponse),
            );
            print('💾 Datos de usuario guardados en caché para uso offline');
          } catch (e) {
            print('⚠️ Error guardando caché de usuario: $e');
          }
          // Obtener información de la empresa para el modal
          String? empresaNombre = 'LogiFlow Pro';
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
                empresaNombre = tenantData['nombre'] ?? 'LogiFlow Pro';
                empresaLogoUrl = tenantData['logo_url'];
              }
            } catch (e) {
              print('⚠️ Error obteniendo datos de empresa: $e');
            }
          }

          // Mostrar modal de carga
          if (mounted) {
            await _mostrarModalInicioSistema(
              empresaNombre ?? 'LogiFlow Pro',
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
                  color: Color(0xFF2C2C2C),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Texto de carga
              const Text(
                'Iniciando sistema de paquetería...',
                style: TextStyle(fontSize: 16, color: Color(0xFF666666)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Icono de carga
              const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1976D2)),
                strokeWidth: 3,
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
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              title?.toLowerCase().contains('confirmar') == true
                  ? Icons.email_outlined
                  : Icons.error_outline,
              color: title?.toLowerCase().contains('confirmar') == true
                  ? const Color(0xFF1976D2)
                  : const Color(0xFFDC2626),
              size: 24,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title ?? 'Error',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: title?.toLowerCase().contains('confirmar') == true
                      ? const Color(0xFF1976D2)
                      : const Color(0xFFDC2626),
                ),
              ),
            ),
          ],
        ),
        content: Text(
          mensaje,
          style: const TextStyle(fontSize: 16, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text(
              'Entendido',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: title?.toLowerCase().contains('confirmar') == true
                    ? const Color(0xFF1976D2)
                    : const Color(0xFFDC2626),
              ),
            ),
          ),
        ],
      ),
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

                          // Título con efecto gradiente
                          ShaderMask(
                            shaderCallback: (bounds) => const LinearGradient(
                              colors: [Colors.white, Color(0xFF81C784)],
                            ).createShader(bounds),
                            child: const Text(
                              'LogiFlow Pro',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
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
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
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

  /// Navega a la pantalla de carga que precarga datos antes de mostrar pantalla principal
  void _navegarAPantallaCarga(String? empresaNombre, String? empresaLogoUrl) {
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => LoadingDataScreen(
          empresaNombre: empresaNombre,
          empresaLogoUrl: empresaLogoUrl,
          onLoadData: (updateProgress) async {
            try {
              // PASO 1: Inicializar SyncService (5%)
              updateProgress(0.05, 'Inicializando sistema...');
              final syncService = SyncService();
              await syncService.initialize();
              await Future.delayed(const Duration(milliseconds: 300));

              // PASO 2: Verificar usuario (15%)
              updateProgress(0.15, 'Verificando permisos...');
              final user = supabase.auth.currentUser;
              if (user == null) throw Exception('Usuario no autenticado');
              await Future.delayed(const Duration(milliseconds: 400));

              // PASO 3: Cargar configuraciones (30%)
              updateProgress(0.30, 'Cargando configuración...');
              await Future.delayed(const Duration(milliseconds: 400));

              // PASO 4: Precargar órdenes (50%)
              updateProgress(0.50, 'Cargando órdenes...');
              
              // Nota: Las órdenes se cargarán automáticamente cuando se abra RepartidorMobileScreen
              // Este paso simplemente simula la carga para dar feedback visual al usuario
              await Future.delayed(const Duration(milliseconds: 800));

              // PASO 5: Preparando datos (70%)
              updateProgress(0.70, 'Preparando datos...');
              await Future.delayed(const Duration(milliseconds: 400));

              // PASO 6: Verificando notificaciones (85%)
              updateProgress(0.85, 'Verificando notificaciones...');
              await Future.delayed(const Duration(milliseconds: 400));

              // PASO 7: Sincronizar operaciones pendientes si hay conexión (95%)
              updateProgress(0.95, 'Sincronizando datos...');
              if (syncService.isOnline) {
                try {
                  // Sincronizar en segundo plano sin bloquear
                  syncService.syncPendingOperations().then((_) {
                    print('✅ Sincronización completada');
                  }).catchError((e) {
                    print('⚠️ Error en sincronización (no crítico): $e');
                  });
                } catch (e) {
                  print('⚠️ Error iniciando sincronización: $e');
                }
              }
              await Future.delayed(const Duration(milliseconds: 400));

              // PASO 8: Completado (100%)
              updateProgress(1.0, 'Completado');
              await Future.delayed(const Duration(milliseconds: 200));

              print('✅ Precarga de datos completada exitosamente');
            } catch (e) {
              print('❌ Error en precarga de datos: $e');
              // Continuar de todas formas, los datos se cargarán en la pantalla principal
              updateProgress(1.0, 'Error en carga, continuando...');
            }
          },
          onComplete: () {
            // Navegar a pantalla principal cuando la carga esté completa
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => const RepartidorMobileScreen(),
                ),
              );
            }
          },
        ),
      ),
    );
  }
}
