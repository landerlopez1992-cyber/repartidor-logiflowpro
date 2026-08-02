import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/sync_service.dart';
import 'repartidor_connectivity.dart';

/// Acciones que obligatoriamente necesitan red (pagos, aceptar viajes, guardar en BD).
///
/// `online == null` (aún no comprobado) se trata como sin internet para no
/// colgar el home con llamadas a red: primero caché/UI, luego probe real.
bool repartidorSinInternet() {
  if (RepartidorConnectivity.online.value != true) return true;
  if (!SyncService().isOnline) return true;
  return false;
}

/// Muestra snackbar y retorna `false` si no hay red (no ejecutar la acción).
Future<bool> repartidorRequiereInternet(
  BuildContext context, {
  required String accion,
}) async {
  if (!repartidorSinInternet()) return true;
  if (!context.mounted) return false;
  final a = accion.trim().isEmpty ? 'continuar' : accion.trim();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Sin internet: no se puede $a ahora. '
        'Puedes ver los datos guardados; al volver la red inténtalo de nuevo.',
      ),
      backgroundColor: AppColors.botonPrincipal,
      duration: const Duration(seconds: 4),
    ),
  );
  return false;
}
