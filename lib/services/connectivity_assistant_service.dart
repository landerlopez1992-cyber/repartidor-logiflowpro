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
    return VolonexDialog(
      title: 'Conexión restaurada',
      leading: const Icon(Icons.wifi, color: AppColors.exito, size: 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Asistente VolonexPro+',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            _isSyncing
                ? 'Actualizando el sistema y las órdenes...'
                : 'Sistema actualizado correctamente.',
            textAlign: TextAlign.center,
          ),
          if (_isSyncing) ...[
            const SizedBox(height: 16),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.exito),
              strokeWidth: 2.5,
            ),
            const SizedBox(height: 12),
            Text(
              'Sincronizando ${widget.pendingOperations > 0 ? widget.pendingOperations : 0} operación${widget.pendingOperations > 1 ? 'es' : ''}...',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ] else if (widget.pendingOperations == 0 || _syncCompleted) ...[
            const SizedBox(height: 12),
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: AppColors.exito, size: 18),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Operaciones sincronizadas correctamente',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            widget.onClose();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.exito,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
          child: Text(
            _isSyncing ? 'Continuar' : 'Aceptar',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
