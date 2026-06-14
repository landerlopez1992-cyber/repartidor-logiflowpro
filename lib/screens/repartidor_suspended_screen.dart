import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_repartidor_screen.dart';
import '../main.dart';
import 'chat_repartidor_lista_screen.dart';
import 'repartidor_mobile_screen.dart';
import '../config/app_colors.dart';
import '../widgets/volonex_dialog.dart';

class RepartidorSuspendedScreen extends StatefulWidget {
  final String? empresaNombre;

  const RepartidorSuspendedScreen({
    super.key,
    this.empresaNombre,
  });

  @override
  State<RepartidorSuspendedScreen> createState() => _RepartidorSuspendedScreenState();
}

class _RepartidorSuspendedScreenState extends State<RepartidorSuspendedScreen> {
  String? _empresaNombre;
  Timer? _timerVerificacion;
  RealtimeChannel? _channelSuspension;
  bool _isVerificando = false;

  @override
  void initState() {
    super.initState();
    _cargarNombreEmpresa();
    _verificarSuspensionPeriodicamente();
    _suscribirseARealtime();
  }

  @override
  void dispose() {
    _timerVerificacion?.cancel();
    _channelSuspension?.unsubscribe();
    super.dispose();
  }

  Future<void> _cargarNombreEmpresa() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // Obtener tenant_id del repartidor
      final userData = await supabase
          .from('usuarios')
          .select('tenant_id')
          .eq('auth_id', user.id)
          .single();

      final tenantId = userData['tenant_id'];

      if (tenantId != null) {
        final empresaData = await supabase
            .from('tenants')
            .select('nombre')
            .eq('id', tenantId)
            .maybeSingle();

        if (mounted) {
          setState(() {
            _empresaNombre =
                empresaData?['nombre'] ?? widget.empresaNombre ?? 'la empresa';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _empresaNombre = widget.empresaNombre ?? 'la empresa';
          });
        }
      }
    } catch (e) {
      print('❌ Error cargando nombre de empresa: $e');
      if (mounted) {
        setState(() {
          _empresaNombre = widget.empresaNombre ?? 'la empresa';
        });
      }
    }
  }

  void _verificarSuspensionPeriodicamente() {
    // Verificar cada 5 segundos si la suspensión fue levantada
    _timerVerificacion = Timer.periodic(const Duration(seconds: 5), (_) {
      _verificarEstadoSuspension();
    });
    
    // Verificar inmediatamente también
    _verificarEstadoSuspension();
  }

  void _suscribirseARealtime() {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      _channelSuspension = supabase
          .channel('suspension_repartidor_${user.id}')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'usuarios',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'auth_id',
              value: user.id,
            ),
            callback: (payload) {
              print('🔄 Cambio detectado en estado de suspensión');
              _verificarEstadoSuspension();
            },
          )
          .subscribe();

      print('✅ Suscrito a cambios de suspensión en tiempo real');
    } catch (e) {
      print('❌ Error suscribiéndose a Realtime: $e');
    }
  }

  Future<void> _verificarEstadoSuspension() async {
    if (_isVerificando) return; // Evitar múltiples verificaciones simultáneas
    
    try {
      _isVerificando = true;
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final userData = await supabase
          .from('usuarios')
          .select('cuenta_suspendida')
          .eq('auth_id', user.id)
          .single();

      final cuentaSuspendida = userData['cuenta_suspendida'] ?? false;
      
      // Verificar diferentes representaciones de boolean
      final estaSuspendido = cuentaSuspendida == true || 
                            cuentaSuspendida == 'true' || 
                            cuentaSuspendida == 1;

      print('🔍 Verificando suspensión: $estaSuspendido');

      if (!estaSuspendido && mounted) {
        // La suspensión fue levantada - redirigir a la pantalla principal
        print('✅ Suspensión levantada - Redirigiendo a pantalla principal');
        _timerVerificacion?.cancel();
        _channelSuspension?.unsubscribe();
        
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => const RepartidorMobileScreen(),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      print('❌ Error verificando estado de suspensión: $e');
    } finally {
      _isVerificando = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Prevenir que el usuario regrese con el botón de atrás
        return false;
      },
      child: Scaffold(
        backgroundColor: AppColors.darkBg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Container(
                constraints: const BoxConstraints(maxWidth: AppLayout.dialogMaxWidth),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: AppColors.darkSurface,
                  borderRadius: BorderRadius.circular(16),
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
                    // Icono de bloqueo
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppColors.error.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.block,
                        size: 60,
                        color: AppColors.error,
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Título
                    const Text(
                      'Cuenta Temporalmente Fuera de Servicio',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkText,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    
                    // Mensaje principal
                    Text(
                      'Contactar a $_empresaNombre',
                      style: const TextStyle(
                        fontSize: 18,
                        color: AppColors.darkTextMuted,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    
                    VolonexActionButton(
                      label: 'Ir al Chat de Soporte',
                      icon: Icons.chat_bubble_outline,
                      backgroundColor: AppColors.exito,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const ChatRepartidorListaScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    VolonexActionButton(
                      label: 'Cerrar Sesión',
                      icon: Icons.logout,
                      outlined: true,
                      foregroundColor: AppColors.error,
                      onPressed: () {
                          print('🚪 Cerrando sesión desde pantalla de suspensión...');
                          
                          if (kIsWeb) {
                            supabase.auth.signOut(scope: SignOutScope.global).then((_) {
                              print('✅ Sesión cerrada');
                            }).catchError((e) {
                              print('❌ Error signOut: $e');
                            });
                          } else {
                            supabase.auth.signOut().then((_) {
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute(builder: (_) => const LoginRepartidorScreen()),
                                (route) => false,
                              );
                            });
                          }
                        },
                    ),
                    const SizedBox(height: 24),
                    
                    // Información adicional
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.darkElevated,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Column(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: AppColors.darkTextMuted,
                            size: 20,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Su cuenta ha sido suspendida temporalmente. Por favor contacte a su empresa a través del chat de soporte para más información.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.darkTextMuted,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

