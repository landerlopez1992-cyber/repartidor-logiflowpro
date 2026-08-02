import 'package:flutter/material.dart';
import '../utils/repartidor_connectivity.dart';

/// Asistente de conectividad — modales idénticos a CubaLink23.
class ConnectivityAssistantService {
  static bool _isShowingModal = false;

  /// Modal cuando se pierde conexión (mismo diseño CubaLink23).
  static Future<void> showOfflineModal(BuildContext context) async {
    if (!context.mounted || _isShowingModal) return;
    _isShowingModal = true;
    try {
      await RepartidorConnectivity.showOfflineStatusModal(context);
    } finally {
      _isShowingModal = false;
    }
  }

  /// Modal cuando regresa la conexión (+ sync de pendientes si aplica).
  static Future<void> showOnlineModal(
    BuildContext context,
    int pendingOperations, {
    required Future<void> Function() onSyncComplete,
  }) async {
    if (!context.mounted || _isShowingModal) return;
    _isShowingModal = true;
    try {
      await RepartidorConnectivity.showOnlineStatusModal(context);
      if (context.mounted) {
        await onSyncComplete();
      }
    } finally {
      _isShowingModal = false;
    }
  }
}
