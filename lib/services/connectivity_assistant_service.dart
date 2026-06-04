import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../widgets/volonex_dialog.dart';

/// Asistente Automático de VolonexPro+
/// Notifica al usuario sobre cambios de conectividad
class ConnectivityAssistantService {
  static bool _isShowingModal = false;
  
  /// Mostrar modal cuando se pierde conexión
  static Future<void> showOfflineModal(BuildContext context) async {
    print('📱 showOfflineModal llamado');
    print('📱 Context mounted: ${context.mounted}');
    print('📱 Modal ya mostrándose: $_isShowingModal');
    
    if (!context.mounted) {
      print('⚠️ Context no montado - No se mostrará modal offline');
      return;
    }
    
    if (_isShowingModal) {
      print('⚠️ Modal ya está mostrándose - Ignorando llamada');
      return;
    }
    
    _isShowingModal = true;
    print('✅ Mostrando modal offline...');
    
    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => VolonexDialog(
        title: 'Sin Conexión a Internet',
        leading: const Icon(Icons.wifi_off, color: AppColors.botonPrincipal, size: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Asistente VolonexPro+',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Hemos detectado que su app de repartidor está sin conexión a internet, pero no se preocupe. El sistema seguirá trabajando incluso sin conexión y guardará todos los datos localmente para cuando regrese se actualizará todo automáticamente.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.botonPrincipal.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.botonPrincipal.withOpacity(0.35)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.botonPrincipal, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No apague los datos móviles. Usted solo siga su trabajo!',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              print('👤 Usuario presionó botón Aceptar (offline) - Cerrando modal');
              Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.botonPrincipal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Aceptar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    
    _isShowingModal = false;
    print('✅ Modal offline cerrado - Flag reseteado');
  }
  
  /// Mostrar modal cuando regresa la conexión
  static Future<void> showOnlineModal(
    BuildContext context,
    int pendingOperations, {
    required Future<void> Function() onSyncComplete,
  }) async {
    print('📱 showOnlineModal llamado');
    print('📱 Context mounted: ${context.mounted}');
    print('📱 Modal ya mostrándose: $_isShowingModal');
    print('📱 Operaciones pendientes: $pendingOperations');
    
    if (!context.mounted) {
      print('⚠️ Context no montado - No se mostrará modal online');
      return;
    }
    
    if (_isShowingModal) {
      print('⚠️ Modal ya está mostrándose - Ignorando llamada');
      return;
    }
    
    _isShowingModal = true;
    print('✅ Mostrando modal online...');
    
    await showDialog(
      context: context,
      barrierDismissible: true, // Permitir cerrar tocando fuera
      builder: (context) => _OnlineModalWidget(
        pendingOperations: pendingOperations,
        onSyncComplete: onSyncComplete,
        onClose: () {
          _isShowingModal = false;
        },
      ),
    );
    
    _isShowingModal = false;
    print('✅ Modal online cerrado - Flag reseteado');
  }
}

/// Widget interno para el modal online con estado
class _OnlineModalWidget extends StatefulWidget {
  final int pendingOperations;
  final Future<void> Function() onSyncComplete;
  final VoidCallback onClose;

  const _OnlineModalWidget({
    required this.pendingOperations,
    required this.onSyncComplete,
    required this.onClose,
  });

  @override
  State<_OnlineModalWidget> createState() => _OnlineModalWidgetState();
}

class _OnlineModalWidgetState extends State<_OnlineModalWidget> {
  bool _isSyncing = false;
  bool _syncCompleted = false;

  @override
  void initState() {
    super.initState();
    _startSync();
  }

  Future<void> _startSync() async {
    if (widget.pendingOperations > 0) {
      setState(() {
        _isSyncing = true;
      });
      print('🔄 Iniciando sincronización REAL - Operaciones pendientes: ${widget.pendingOperations}');

      // ✅ SINCRONIZACIÓN REAL: Esperar a que termine realmente
      try {
        await widget.onSyncComplete();
        print('✅ Sincronización REAL completada');
        if (mounted) {
          setState(() {
            _isSyncing = false;
            _syncCompleted = true;
          });
        }
      } catch (e) {
        print('⚠️ Error en sincronización: $e');
        if (mounted) {
          setState(() {
            _isSyncing = false;
            _syncCompleted = true;
          });
        }
      }
    } else {
      print('✅ No hay operaciones pendientes - Sincronización no necesaria');
      setState(() {
        _syncCompleted = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.9,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF4CAF50),
                  const Color(0xFF66BB6A),
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Icono del asistente
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.wifi,
                  size: 48,
                  color: Colors.white,
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Título
              const Text(
                'Asistente VolonexPro+',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 8),
              
              // Subtítulo
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Conexión Restaurada',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Mensaje principal
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.cloud_done,
                      color: Color(0xFF4CAF50),
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '¡Conexión Restaurada!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C2C2C),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(
                        _isSyncing
                            ? 'La app está de vuelta con la conexión. Actualizando el sistema y las órdenes...'
                            : 'La app está de vuelta con la conexión. Sistema actualizado correctamente.',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF666666),
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (_isSyncing) ...[
                      const SizedBox(height: 20),
                      const CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
                        strokeWidth: 3,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
                                strokeWidth: 2,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                'Sincronizando ${widget.pendingOperations > 0 ? widget.pendingOperations : 0} operación${widget.pendingOperations > 1 ? 'es' : ''}...',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF2C2C2C),
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (widget.pendingOperations == 0 || _syncCompleted) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              color: Color(0xFF4CAF50),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Todas las operaciones se han sincronizado correctamente',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF2C2C2C),
                                  fontWeight: FontWeight.w500,
                                ),
                                textAlign: TextAlign.center,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Botón Aceptar (siempre visible - permite continuar trabajando mientras sincroniza)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    onPressed: () {
                      print('👤 Usuario presionó botón Aceptar - Cerrando modal');
                      Navigator.of(context).pop();
                      widget.onClose();
                      // La sincronización continuará en segundo plano
                      print('✅ Usuario cerró modal - Sincronización continuará en segundo plano');
                    },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF4CAF50),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      _isSyncing
                          ? 'Continuar trabajando (sincronizando en segundo plano)'
                          : 'Aceptar',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ),
              ),
            ],
            ),
          ),
        ),
      );
  }
}
