import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'services/repartidor_telemetry_service.dart';
import 'services/firebase_messaging_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'config/supabase_config.dart';
import 'theme/volonex_theme.dart';
import 'navigation/repartidor_navigator.dart';
import 'screens/login_repartidor_screen.dart';
import 'screens/repartidor_mobile_screen.dart';
import 'screens/loading_data_screen.dart';
import 'services/sync_service.dart';
import 'services/repartidor_suspension_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Verificar actualizaciones OTA con Shorebird (solo en móviles)
  if (!kIsWeb) {
    print('🔄 ===== VERIFICANDO SHOREBIRD =====');
    // TODO: Agregar verificación de Shorebird cuando esté configurado
  }

  // Inicializar Supabase con persistencia de sesión
  try {
    print('🔄 Inicializando Supabase...');
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.info,
      ),
    );
    print('✅ Supabase inicializado correctamente');
  } catch (e, stackTrace) {
    print('❌ ERROR CRÍTICO: No se pudo inicializar Supabase');
    print('📚 Error: $e');
    print('📚 Stack: $stackTrace');
  }

  if (!kIsWeb) {
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await FirebaseMessagingService().initialize();
    } catch (e) {
      print('⚠️ Firebase Messaging no disponible aún (¿falta google-services.json?): $e');
    }
  }

  await RepartidorTelemetryService.instance.initialize();

  runApp(const RepartidorApp());
}

// Get supabase client
final supabase = Supabase.instance.client;

class RepartidorApp extends StatelessWidget {
  const RepartidorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VolonexPro+',
      debugShowCheckedModeBanner: false,
      theme: VolonexTheme.material,
      navigatorKey: RepartidorNavigator.key,
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoading = true;
  bool _isAuthenticated = false;
  bool _isSuspended = false;

  @override
  void initState() {
    super.initState();
    _checkAuthState();
    
    // Escuchar cambios en el estado de autenticación
    supabase.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null) {
        _verifyRepartidorRole(session.user.id);
      } else {
        if (mounted) {
          setState(() {
            _isAuthenticated = false;
            _isSuspended = false;
            _isLoading = false;
          });
        }
      }
    });
  }

  Future<void> _checkAuthState() async {
    try {
      // Verificar si hay una sesión activa
      final session = supabase.auth.currentSession;
      
      if (session != null) {
        // Verificar si la sesión no ha expirado
        final now = DateTime.now();
        final expiresAt = DateTime.fromMillisecondsSinceEpoch(session.expiresAt! * 1000);
        
        if (now.isBefore(expiresAt)) {
          await _verifyRepartidorRole(session.user.id);
        } else {
          // Sesión expirada, intentar refrescar
          try {
            final refreshedSession = await supabase.auth.refreshSession();
            if (refreshedSession.session != null) {
              await _verifyRepartidorRole(refreshedSession.session!.user.id);
            } else {
              setState(() {
                _isAuthenticated = false;
                _isLoading = false;
              });
            }
          } catch (refreshError) {
            print('⚠️ Error refrescando sesión: $refreshError');
            setState(() {
              _isAuthenticated = false;
              _isLoading = false;
            });
          }
        }
      } else {
        setState(() {
          _isAuthenticated = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('⚠️ Error en _checkAuthState: $e');
      setState(() {
        _isAuthenticated = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyRepartidorRole(String userId) async {
    try {
      print('🔍 Verificando rol de repartidor para usuario: $userId');
      
      // 1️⃣ PRIMERO: Intentar cargar desde caché local (funciona offline)
      final prefs = await SharedPreferences.getInstance();
      final cachedUserData = prefs.getString('cached_user_data_$userId');
      
      if (cachedUserData != null) {
        try {
          final userData = jsonDecode(cachedUserData) as Map<String, dynamic>;
          final rol = userData['rol']?.toString().toUpperCase();
          
          if (rol == 'REPARTIDOR') {
            print('✅ Usuario autenticado desde caché (modo offline)');
            final suspendidoCache =
                RepartidorSuspensionService.esSuspendidoFlag(
              userData['cuenta_suspendida'],
            );
            if (mounted) {
              setState(() {
                _isAuthenticated = true;
                _isSuspended = suspendidoCache;
                _isLoading = false;
              });
            }
            // Reasociar token FCM con el usuario autenticado
            FirebaseMessagingService().refreshRegistrationForCurrentUser();
            
            // Si hay conexión, verificar en segundo plano y actualizar caché
            _verifyAndUpdateCache(userId);
            return;
          }
        } catch (e) {
          print('⚠️ Error leyendo caché, verificando online: $e');
        }
      }
      
      // 2️⃣ SEGUNDO: Si no hay caché o falló, verificar online
      var userData = await supabase
          .from('usuarios')
          .select('rol, nombre, tenant_id, auth_id, repartidor_master, tipo_repartidor, foto_perfil, cuenta_suspendida')
          .eq('auth_id', userId)
          .maybeSingle();
      
      // Si no se encuentra por auth_id, intentar por email
      if (userData == null) {
        final user = supabase.auth.currentUser;
        if (user?.email != null) {
          userData = await supabase
              .from('usuarios')
              .select('rol, nombre, tenant_id, auth_id, repartidor_master, tipo_repartidor, foto_perfil, cuenta_suspendida')
              .eq('email', user!.email!)
              .maybeSingle();
        }
      }
      
      if (userData != null) {
        final rol = userData['rol']?.toString().toUpperCase();
        
        if (rol == 'REPARTIDOR') {
          // 💾 Guardar en caché para uso offline
          await prefs.setString('cached_user_data_$userId', jsonEncode(userData));
          print('💾 Datos de usuario guardados en caché');
          
          final suspendido = RepartidorSuspensionService.esSuspendidoFlag(
            userData['cuenta_suspendida'],
          );
          if (mounted) {
            setState(() {
              _isAuthenticated = true;
              _isSuspended = suspendido;
              _isLoading = false;
            });
          }
          FirebaseMessagingService().refreshRegistrationForCurrentUser();
        } else {
          // No es repartidor, cerrar sesión y limpiar TODOS los cachés
          await prefs.remove('cached_user_data_$userId');
          await prefs.remove('cached_repartidor_nombre_$userId');
          await prefs.remove('cached_repartidor_master_$userId');
          await prefs.remove('cached_repartidor_tipo_$userId');
          await prefs.remove('cached_repartidor_foto_$userId');
          await prefs.remove('cached_tenant_id_$userId'); // 🔒 CRÍTICO
          print('🧹 Caché del usuario limpiado (no es repartidor)');
          await supabase.auth.signOut();
          if (mounted) {
            setState(() {
              _isAuthenticated = false;
              _isLoading = false;
            });
          }
        }
      } else {
        // Usuario no encontrado, limpiar TODOS los cachés
        await prefs.remove('cached_user_data_$userId');
        await prefs.remove('cached_repartidor_nombre_$userId');
        await prefs.remove('cached_repartidor_master_$userId');
        await prefs.remove('cached_repartidor_tipo_$userId');
        await prefs.remove('cached_repartidor_foto_$userId');
        await prefs.remove('cached_tenant_id_$userId'); // 🔒 CRÍTICO
        print('🧹 Caché del usuario limpiado (no encontrado)');
        await supabase.auth.signOut();
        if (mounted) {
          setState(() {
            _isAuthenticated = false;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('⚠️ Error verificando rol: $e');
      
      // ⚠️ Si falla la verificación online, intentar usar caché como fallback
      try {
        final prefs = await SharedPreferences.getInstance();
        final cachedUserData = prefs.getString('cached_user_data_$userId');
        
        if (cachedUserData != null) {
          final userData = jsonDecode(cachedUserData) as Map<String, dynamic>;
          final rol = userData['rol']?.toString().toUpperCase();
          
          if (rol == 'REPARTIDOR') {
            print('✅ Usando caché como fallback (sin conexión)');
            final suspendidoCache =
                RepartidorSuspensionService.esSuspendidoFlag(
              userData['cuenta_suspendida'],
            );
            if (mounted) {
              setState(() {
                _isAuthenticated = true;
                _isSuspended = suspendidoCache;
                _isLoading = false;
              });
            }
            return;
          }
        }
      } catch (cacheError) {
        print('❌ Error al intentar fallback de caché: $cacheError');
      }
      
      // Si no hay caché, marcar como no autenticado
      if (mounted) {
        setState(() {
          _isAuthenticated = false;
          _isLoading = false;
        });
      }
    }
  }
  
  /// Verificar y actualizar caché en segundo plano (no bloquea UI)
  Future<void> _verifyAndUpdateCache(String userId) async {
    try {
      // Intentar verificar online sin bloquear
      final userData = await supabase
          .from('usuarios')
          .select('rol, nombre, tenant_id, auth_id, repartidor_master, tipo_repartidor, foto_perfil, cuenta_suspendida')
          .eq('auth_id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));
      
      if (userData != null) {
        final rol = userData['rol']?.toString().toUpperCase();
        
        if (rol == 'REPARTIDOR') {
          // Actualizar caché
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('cached_user_data_$userId', jsonEncode(userData));
          print('🔄 Caché actualizado en segundo plano');
          final suspendido = RepartidorSuspensionService.esSuspendidoFlag(
            userData['cuenta_suspendida'],
          );
          if (mounted && (_isSuspended != suspendido)) {
            setState(() => _isSuspended = suspendido);
          }
        } else {
          // El rol cambió, cerrar sesión y limpiar TODOS los cachés
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('cached_user_data_$userId');
          await prefs.remove('cached_repartidor_nombre_$userId');
          await prefs.remove('cached_repartidor_master_$userId');
          await prefs.remove('cached_repartidor_tipo_$userId');
          await prefs.remove('cached_repartidor_foto_$userId');
          await prefs.remove('cached_tenant_id_$userId'); // 🔒 CRÍTICO
          print('🧹 Todos los cachés limpiados (rol cambió)');
          await supabase.auth.signOut();
          if (mounted) {
            setState(() {
              _isAuthenticated = false;
            });
          }
        }
      }
    } catch (e) {
      print('⚠️ No se pudo verificar en segundo plano (probablemente offline): $e');
      // No hacer nada, seguir con caché
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_isAuthenticated) {
      // Suspensión NO bloquea toda la app: se aplica en Viajes / ajustes taxi.
      return _LoadingScreenWrapper();
    } else {
      return const LoginRepartidorScreen();
    }
  }
}

/// Wrapper que muestra la pantalla de carga cuando el usuario ya está autenticado
class _LoadingScreenWrapper extends StatefulWidget {
  @override
  State<_LoadingScreenWrapper> createState() => _LoadingScreenWrapperState();
}

class _LoadingScreenWrapperState extends State<_LoadingScreenWrapper> {
  String? _empresaNombre;
  String? _empresaLogoUrl;

  @override
  void initState() {
    super.initState();
    _cargarDatosEmpresa();
  }

  Future<void> _cargarDatosEmpresa() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // Obtener datos del usuario
      final usuarioData = await supabase
          .from('usuarios')
          .select('tenant_id')
          .eq('auth_id', user.id)
          .maybeSingle();

      final tenantId = usuarioData?['tenant_id'] as String?;
      if (tenantId == null) return;

      // Obtener datos del tenant
      final tenantData = await supabase
          .from('tenants')
          .select('nombre, logo_url')
          .eq('id', tenantId)
          .maybeSingle();

      if (tenantData != null && mounted) {
        setState(() {
          _empresaNombre = tenantData['nombre'] as String?;
          _empresaLogoUrl = tenantData['logo_url'] as String?;
        });
      }
    } catch (e) {
      print('⚠️ Error cargando datos de empresa: $e');
    }
  }

  void _navegarAPantallaPrincipal() {
    if (!mounted) return;
    unawaited(_navegarTrasCarga());
  }

  Future<void> _navegarTrasCarga() async {
    if (!mounted) return;
    // Suspensión se maneja dentro de la app (pestaña Viajes), no bloquea el acceso.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const RepartidorMobileScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LoadingDataScreen(
      empresaNombre: _empresaNombre,
      empresaLogoUrl: _empresaLogoUrl,
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
      onComplete: _navegarAPantallaPrincipal,
    );
  }
}

