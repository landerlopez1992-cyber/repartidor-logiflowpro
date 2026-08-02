import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'services/repartidor_telemetry_service.dart';
import 'services/firebase_messaging_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'config/supabase_config.dart';
import 'theme/volonex_theme.dart';
import 'navigation/repartidor_navigator.dart';
import 'screens/login_repartidor_screen.dart';
import 'screens/repartidor_mobile_screen.dart';
import 'screens/loading_data_screen.dart';
import 'services/repartidor_suspension_service.dart';
import 'services/repartidor_boot_cache_service.dart';
import 'widgets/repartidor_loading_spinner.dart';
import 'config/app_colors.dart';
import 'utils/repartidor_connectivity.dart';
import 'widgets/volonex_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  RepartidorConnectivity.bindNavigatorKey(RepartidorNavigator.key);
  RepartidorConnectivity.startWatching();

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
      print(
        '⚠️ Firebase Messaging no disponible aún (¿falta google-services.json?): $e',
      );
    }
  }

  await RepartidorTelemetryService.instance.initialize();

  runApp(const RepartidorApp());
}

// Get supabase client
final supabase = Supabase.instance.client;

/// Último auth_id de repartidor con sesión válida en caché (arranque offline).
const kLastRepartidorAuthIdKey = 'last_repartidor_auth_id';

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
  bool _authCheckDone = false;
  StreamSubscription<AuthState>? _authSub;

  String? _splashEmpresaNombre;
  String? _splashEmpresaLogoUrl;
  String? _splashEmpresaLogoLocal;
  String _splashMessage = 'Restaurando sesión…';

  @override
  void initState() {
    super.initState();
    unawaited(_preloadSplashBranding());
    unawaited(_checkAuthState());

    _authSub = supabase.auth.onAuthStateChange.listen((data) {
      // Esperar a que termine el chequeo inicial (evita carrera → login).
      if (!_authCheckDone) return;

      final session = data.session;
      if (session != null) {
        unawaited(_verifyRepartidorRole(session.user.id));
        return;
      }

      // Sesión nula: si ya entramos por caché, NO echar al login.
      if (_isAuthenticated) {
        print('ℹ️ Auth event sin sesión; se mantiene modo offline/caché');
        return;
      }
      unawaited(_recuperarSesionDesdeCacheSiPosible());
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _preloadSplashBranding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = await _buscarAuthIdEnCache(prefs) ??
          supabase.auth.currentSession?.user.id ??
          supabase.auth.currentUser?.id;
      if (userId == null || userId.isEmpty) return;

      final cached =
          await RepartidorBootCacheService.instance.loadEmpresaCached(userId);
      if (!mounted || cached == null) return;
      setState(() {
        _splashEmpresaNombre = cached.nombre;
        _splashEmpresaLogoUrl = cached.logoUrl;
        _splashEmpresaLogoLocal = cached.logoLocalPath;
        _splashMessage = 'Cargando datos guardados…';
      });
    } catch (e) {
      print('⚠️ splash branding: $e');
    }
  }

  Future<bool> _hayRed() async {
    try {
      final r = await Connectivity()
          .checkConnectivity()
          .timeout(const Duration(seconds: 2));
      if (r.isEmpty) return false;
      return !r.every((e) => e == ConnectivityResult.none);
    } catch (_) {
      // Ante duda en arranque: asumir offline (prioridad caché).
      return false;
    }
  }

  /// Busca cualquier `cached_user_data_*` de repartidor (instala viejas sin last_id).
  Future<String?> _buscarAuthIdEnCache(SharedPreferences prefs) async {
    final last = prefs.getString(kLastRepartidorAuthIdKey);
    if (last != null && last.isNotEmpty) {
      final raw = prefs.getString('cached_user_data_$last');
      if (raw != null && raw.isNotEmpty) return last;
    }
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('cached_user_data_')) continue;
      final id = key.substring('cached_user_data_'.length);
      if (id.isEmpty) continue;
      try {
        final raw = prefs.getString(key);
        if (raw == null || raw.isEmpty) continue;
        final m = jsonDecode(raw) as Map<String, dynamic>;
        if (m['rol']?.toString().toUpperCase() == 'REPARTIDOR') {
          await prefs.setString(kLastRepartidorAuthIdKey, id);
          return id;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<bool> _entrarDesdeCache(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedUserData = prefs.getString('cached_user_data_$userId');
      if (cachedUserData == null || cachedUserData.isEmpty) return false;

      final userData = jsonDecode(cachedUserData) as Map<String, dynamic>;
      final rol = userData['rol']?.toString().toUpperCase();
      if (rol != 'REPARTIDOR') return false;

      await prefs.setString(kLastRepartidorAuthIdKey, userId);
      final suspendidoCache = RepartidorSuspensionService.esSuspendidoFlag(
        userData['cuenta_suspendida'],
      );
      if (mounted) {
        setState(() {
          _isAuthenticated = true;
          _isSuspended = suspendidoCache;
          _isLoading = false;
          _authCheckDone = true;
          _splashMessage = 'Sesión restaurada';
        });
      }
      print('✅ Sesión restaurada desde caché (offline-first): $userId');
      FirebaseMessagingService().refreshRegistrationForCurrentUser();
      return true;
    } catch (e) {
      print('⚠️ _entrarDesdeCache: $e');
      return false;
    }
  }

  Future<bool> _entrarDesdeCualquierCache() async {
    final prefs = await SharedPreferences.getInstance();
    final id = await _buscarAuthIdEnCache(prefs);
    if (id == null) return false;
    return _entrarDesdeCache(id);
  }

  Future<void> _recuperarSesionDesdeCacheSiPosible() async {
    if (!mounted) return;
    if (_isAuthenticated) return;

    final session = supabase.auth.currentSession;
    final prefs = await SharedPreferences.getInstance();
    final userId = session?.user.id ??
        supabase.auth.currentUser?.id ??
        await _buscarAuthIdEnCache(prefs);
    if (userId != null && userId.isNotEmpty) {
      final ok = await _entrarDesdeCache(userId);
      if (ok) return;
    }
    if (await _entrarDesdeCualquierCache()) return;

    if (mounted) {
      setState(() {
        _isAuthenticated = false;
        _isSuspended = false;
        _isLoading = false;
        _authCheckDone = true;
      });
    }
  }

  bool _pareceErrorRed(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('socket') ||
        s.contains('network') ||
        s.contains('failed host') ||
        s.contains('timed out') ||
        s.contains('timeout') ||
        s.contains('connection') ||
        s.contains('offline') ||
        s.contains('unreachable') ||
        s.contains('clientexception') ||
        s.contains('handshake');
  }

  Future<void> _checkAuthState() async {
    try {
      if (mounted) {
        setState(() => _splashMessage = 'Comprobando sesión…');
      }

      final online = await _hayRed();
      final prefs = await SharedPreferences.getInstance();
      final cachedId = await _buscarAuthIdEnCache(prefs);
      final session = supabase.auth.currentSession;
      final sessionUserId =
          session?.user.id ?? supabase.auth.currentUser?.id;

      // ——— SIN INTERNET: solo caché, nunca refresh ni login forzado ———
      if (!online) {
        print('📴 Arranque sin red → sesión desde caché');
        if (mounted) {
          setState(() => _splashMessage = 'Sin internet · cargando caché…');
        }
        if (cachedId != null && await _entrarDesdeCache(cachedId)) {
          return;
        }
        if (sessionUserId != null &&
            await _entrarDesdeCache(sessionUserId)) {
          return;
        }
        if (await _entrarDesdeCualquierCache()) return;

        if (mounted) {
          setState(() {
            _isAuthenticated = false;
            _isLoading = false;
            _authCheckDone = true;
          });
        }
        return;
      }

      // ——— CON INTERNET ———
      var activeSession = session;

      if (activeSession != null && activeSession.expiresAt != null) {
        final expiresAt = DateTime.fromMillisecondsSinceEpoch(
          activeSession.expiresAt! * 1000,
        );
        if (DateTime.now().isAfter(expiresAt)) {
          final userId = activeSession.user.id;
          // Preferir caché inmediata; refresh en segundo plano.
          if (await _entrarDesdeCache(userId)) {
            unawaited(() async {
              try {
                await supabase.auth
                    .refreshSession()
                    .timeout(const Duration(seconds: 8));
              } catch (_) {}
            }());
            return;
          }
          try {
            final refreshed = await supabase.auth
                .refreshSession()
                .timeout(const Duration(seconds: 8));
            activeSession = refreshed.session ?? activeSession;
          } catch (refreshError) {
            print('⚠️ Refresh falló: $refreshError');
            if (await _entrarDesdeCache(userId) ||
                await _entrarDesdeCualquierCache()) {
              return;
            }
          }
        }
      }

      if (activeSession != null) {
        await _verifyRepartidorRole(activeSession.user.id);
        return;
      }

      if (cachedId != null && await _entrarDesdeCache(cachedId)) return;
      if (await _entrarDesdeCualquierCache()) return;

      if (mounted) {
        setState(() {
          _isAuthenticated = false;
          _isLoading = false;
          _authCheckDone = true;
        });
      }
    } catch (e) {
      print('⚠️ Error en _checkAuthState: $e');
      if (await _entrarDesdeCualquierCache()) return;
      await _recuperarSesionDesdeCacheSiPosible();
    }
  }

  Future<void> _verifyRepartidorRole(String userId) async {
    try {
      print('🔍 Verificando rol de repartidor para usuario: $userId');

      if (await _entrarDesdeCache(userId)) {
        unawaited(_verifyAndUpdateCache(userId));
        return;
      }

      if (!await _hayRed()) {
        if (await _entrarDesdeCualquierCache()) return;
        if (mounted) {
          setState(() {
            _isAuthenticated = false;
            _isLoading = false;
            _authCheckDone = true;
          });
        }
        return;
      }

      Map<String, dynamic>? userData;
      try {
        userData = await supabase
            .from('usuarios')
            .select(
              'rol, nombre, tenant_id, auth_id, repartidor_master, tipo_repartidor, foto_perfil, cuenta_suspendida',
            )
            .eq('auth_id', userId)
            .maybeSingle()
            .timeout(const Duration(seconds: 6));

        if (userData == null) {
          final user = supabase.auth.currentUser;
          if (user?.email != null) {
            userData = await supabase
                .from('usuarios')
                .select(
                  'rol, nombre, tenant_id, auth_id, repartidor_master, tipo_repartidor, foto_perfil, cuenta_suspendida',
                )
                .eq('email', user!.email!)
                .maybeSingle()
                .timeout(const Duration(seconds: 6));
          }
        }
      } catch (e) {
        print('⚠️ Verificación online falló: $e');
        if (await _entrarDesdeCache(userId) ||
            await _entrarDesdeCualquierCache()) {
          return;
        }
        if (_pareceErrorRed(e)) {
          if (mounted) {
            setState(() {
              _isAuthenticated = false;
              _isLoading = false;
              _authCheckDone = true;
            });
          }
          return;
        }
        rethrow;
      }

      final prefs = await SharedPreferences.getInstance();

      if (userData != null) {
        final rol = userData['rol']?.toString().toUpperCase();

        if (rol == 'REPARTIDOR') {
          await prefs.setString(
            'cached_user_data_$userId',
            jsonEncode(userData),
          );
          await prefs.setString(kLastRepartidorAuthIdKey, userId);
          print('💾 Datos de usuario guardados en caché');

          final suspendido = RepartidorSuspensionService.esSuspendidoFlag(
            userData['cuenta_suspendida'],
          );
          if (mounted) {
            setState(() {
              _isAuthenticated = true;
              _isSuspended = suspendido;
              _isLoading = false;
              _authCheckDone = true;
            });
          }
          FirebaseMessagingService().refreshRegistrationForCurrentUser();
        } else {
          await prefs.remove('cached_user_data_$userId');
          await prefs.remove('cached_repartidor_nombre_$userId');
          await prefs.remove('cached_repartidor_master_$userId');
          await prefs.remove('cached_repartidor_tipo_$userId');
          await prefs.remove('cached_repartidor_foto_$userId');
          await prefs.remove('cached_tenant_id_$userId');
          if (prefs.getString(kLastRepartidorAuthIdKey) == userId) {
            await prefs.remove(kLastRepartidorAuthIdKey);
          }
          print('🧹 Caché del usuario limpiado (no es repartidor)');
          await supabase.auth.signOut();
          if (mounted) {
            setState(() {
              _isAuthenticated = false;
              _isLoading = false;
              _authCheckDone = true;
            });
          }
        }
      } else {
        if (await _entrarDesdeCache(userId) ||
            await _entrarDesdeCualquierCache()) {
          print('✅ Sin fila online; se mantiene sesión por caché');
          return;
        }
        print('🧹 Usuario no encontrado online y sin caché');
        await supabase.auth.signOut();
        if (mounted) {
          setState(() {
            _isAuthenticated = false;
            _isLoading = false;
            _authCheckDone = true;
          });
        }
      }
    } catch (e) {
      print('⚠️ Error verificando rol: $e');
      if (await _entrarDesdeCache(userId) ||
          await _entrarDesdeCualquierCache()) {
        print('✅ Usando caché como fallback (sin conexión)');
        return;
      }
      if (mounted) {
        setState(() {
          _isAuthenticated = false;
          _isLoading = false;
          _authCheckDone = true;
        });
      }
    }
  }

  Future<void> _verifyAndUpdateCache(String userId) async {
    if (!await _hayRed()) return;
    try {
      final userData = await supabase
          .from('usuarios')
          .select(
            'rol, nombre, tenant_id, auth_id, repartidor_master, tipo_repartidor, foto_perfil, cuenta_suspendida',
          )
          .eq('auth_id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 5));

      if (userData != null) {
        final rol = userData['rol']?.toString().toUpperCase();
        final prefs = await SharedPreferences.getInstance();

        if (rol == 'REPARTIDOR') {
          await prefs.setString(
            'cached_user_data_$userId',
            jsonEncode(userData),
          );
          await prefs.setString(kLastRepartidorAuthIdKey, userId);
          print('🔄 Caché actualizado en segundo plano');
          final suspendido = RepartidorSuspensionService.esSuspendidoFlag(
            userData['cuenta_suspendida'],
          );
          if (mounted && (_isSuspended != suspendido)) {
            setState(() => _isSuspended = suspendido);
          }
        } else if (rol != null) {
          await prefs.remove('cached_user_data_$userId');
          await prefs.remove('cached_repartidor_nombre_$userId');
          await prefs.remove('cached_repartidor_master_$userId');
          await prefs.remove('cached_repartidor_tipo_$userId');
          await prefs.remove('cached_repartidor_foto_$userId');
          await prefs.remove('cached_tenant_id_$userId');
          if (prefs.getString(kLastRepartidorAuthIdKey) == userId) {
            await prefs.remove(kLastRepartidorAuthIdKey);
          }
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
      print(
        '⚠️ No se pudo verificar en segundo plano (probablemente offline): $e',
      );
    }
  }

  Widget _buildAuthSplash() {
    final nombre = _splashEmpresaNombre;
    final local = _splashEmpresaLogoLocal;
    final url = _splashEmpresaLogoUrl;

    Widget logo;
    if (!kIsWeb &&
        local != null &&
        local.isNotEmpty &&
        File(local).existsSync()) {
      logo = Image.file(
        File(local),
        width: 140,
        height: 140,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const RepartidorLoadingSpinner.large(
          color: AppColors.botonPrincipal,
        ),
      );
    } else if (url != null && url.isNotEmpty) {
      logo = Image.network(
        url,
        width: 140,
        height: 140,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.local_shipping,
          size: 72,
          color: AppColors.botonPrincipal,
        ),
      );
    } else {
      logo = const Icon(
        Icons.local_shipping,
        size: 72,
        color: AppColors.botonPrincipal,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.header, Color(0xFF263238)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: AppLayout.formMaxWidth),
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  logo,
                  if (nombre != null && nombre.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      nombre,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkText,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  const RepartidorLoadingSpinner.large(
                    color: AppColors.botonPrincipal,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _splashMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.darkTextMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildAuthSplash();
    }

    if (_isAuthenticated) {
      return _LoadingScreenWrapper(
        initialEmpresaNombre: _splashEmpresaNombre,
        initialEmpresaLogoUrl: _splashEmpresaLogoUrl,
        initialEmpresaLogoLocalPath: _splashEmpresaLogoLocal,
      );
    } else {
      return const LoginRepartidorScreen();
    }
  }
}

/// Wrapper que muestra la pantalla de carga cuando el usuario ya está autenticado
class _LoadingScreenWrapper extends StatefulWidget {
  const _LoadingScreenWrapper({
    this.initialEmpresaNombre,
    this.initialEmpresaLogoUrl,
    this.initialEmpresaLogoLocalPath,
  });

  final String? initialEmpresaNombre;
  final String? initialEmpresaLogoUrl;
  final String? initialEmpresaLogoLocalPath;

  @override
  State<_LoadingScreenWrapper> createState() => _LoadingScreenWrapperState();
}

class _LoadingScreenWrapperState extends State<_LoadingScreenWrapper> {
  String? _empresaNombre;
  String? _empresaLogoUrl;
  String? _empresaLogoLocalPath;

  @override
  void initState() {
    super.initState();
    _empresaNombre = widget.initialEmpresaNombre;
    _empresaLogoUrl = widget.initialEmpresaLogoUrl;
    _empresaLogoLocalPath = widget.initialEmpresaLogoLocalPath;
    _cargarDatosEmpresa();
  }

  Future<String?> _resolverAuthUserId() async {
    final fromAuth =
        supabase.auth.currentUser?.id ?? supabase.auth.currentSession?.user.id;
    if (fromAuth != null && fromAuth.isNotEmpty) return fromAuth;
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString(kLastRepartidorAuthIdKey);
    if (last != null && last.isNotEmpty) return last;
    // Escaneo por si last_id no existía aún.
    for (final key in prefs.getKeys()) {
      if (!key.startsWith('cached_user_data_')) continue;
      final id = key.substring('cached_user_data_'.length);
      try {
        final raw = prefs.getString(key);
        if (raw == null) continue;
        final m = jsonDecode(raw) as Map<String, dynamic>;
        if (m['rol']?.toString().toUpperCase() == 'REPARTIDOR') return id;
      } catch (_) {}
    }
    return null;
  }

  Future<void> _cargarDatosEmpresa() async {
    try {
      final userId = await _resolverAuthUserId();
      if (userId == null || userId.isEmpty) return;

      final boot = RepartidorBootCacheService.instance;
      final cached = await boot.loadEmpresaCached(userId);
      if (cached != null && mounted) {
        setState(() {
          _empresaNombre = cached.nombre ?? _empresaNombre;
          _empresaLogoUrl = cached.logoUrl ?? _empresaLogoUrl;
          _empresaLogoLocalPath = cached.logoLocalPath ?? _empresaLogoLocalPath;
        });
      }

      final resolved = await boot.resolveEmpresa(authUserId: userId);
      if (mounted) {
        setState(() {
          _empresaNombre = resolved.nombre ?? _empresaNombre;
          _empresaLogoUrl = resolved.logoUrl ?? _empresaLogoUrl;
          _empresaLogoLocalPath =
              resolved.logoLocalPath ?? _empresaLogoLocalPath;
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
      empresaLogoLocalPath: _empresaLogoLocalPath,
      onLoadData: (updateProgress) async {
        await RepartidorBootCacheService.instance.runBootLoad(
          updateProgress: updateProgress,
        );
      },
      onComplete: _navegarAPantallaPrincipal,
    );
  }
}
