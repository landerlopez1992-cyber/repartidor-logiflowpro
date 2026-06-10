import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_colors.dart';
import '../main.dart';
import '../models/orden.dart';
import '../utils/repartidor_master_util.dart';
import '../widgets/volonex_dialog.dart';

/// Resultado de validar si un repartidor puede abrir/trabajar una orden.
enum RepartidorOrdenAcceso {
  permitido,
  otraEmpresa,
  noAsignada,
  sesionInvalida,
  entregaPorVendedor,
}

/// Contexto de sesión del repartidor (empresa + rol).
class RepartidorSesionContext {
  final String? tenantId;
  final String nombreEmpresa;
  final String? repartidorNombre;
  final bool esMaster;

  const RepartidorSesionContext({
    required this.tenantId,
    required this.nombreEmpresa,
    required this.repartidorNombre,
    required this.esMaster,
  });
}

/// Aislamiento por tenant y permisos master vs repartidor normal.
class RepartidorSeguridadService {
  RepartidorSeguridadService._();

  static String _tenantNombreKey(String authUserId) =>
      'cached_tenant_nombre_$authUserId';

  static Future<void> guardarNombreEmpresaEnCache(
    String authUserId,
    String nombre,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tenantNombreKey(authUserId), nombre.trim());
  }

  static Future<String?> nombreEmpresaDesdeCache(String authUserId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tenantNombreKey(authUserId));
  }

  static Future<RepartidorSesionContext> cargarContexto() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      return const RepartidorSesionContext(
        tenantId: null,
        nombreEmpresa: 'tu empresa',
        repartidorNombre: null,
        esMaster: false,
      );
    }

    final prefs = await SharedPreferences.getInstance();
    var tenantId = prefs.getString('cached_tenant_id_${user.id}');
    var nombreEmpresa =
        prefs.getString(_tenantNombreKey(user.id)) ?? 'tu empresa';
    var repartidorNombre = prefs.getString('cached_repartidor_nombre_${user.id}');
    var esMaster = prefs.getBool('cached_repartidor_master_${user.id}') ?? false;

    final cachedUser = prefs.getString('cached_user_data_${user.id}');
    if (cachedUser != null) {
      try {
        final map = jsonDecode(cachedUser) as Map<String, dynamic>;
        tenantId ??= map['tenant_id']?.toString();
        repartidorNombre ??= map['nombre']?.toString();
        if (!prefs.containsKey('cached_repartidor_master_${user.id}')) {
          esMaster = RepartidorMasterUtil.parseFlag(map['repartidor_master']);
        }
      } catch (_) {}
    }

    try {
      final userData = await supabase
          .from('usuarios')
          .select(
            'tenant_id, nombre, repartidor_master',
          )
          .eq('auth_id', user.id)
          .maybeSingle();

      if (userData != null) {
        tenantId = userData['tenant_id']?.toString() ?? tenantId;
        repartidorNombre = userData['nombre']?.toString() ?? repartidorNombre;
        esMaster = RepartidorMasterUtil.parseFlag(userData['repartidor_master']);
        await prefs.setString('cached_tenant_id_${user.id}', tenantId ?? '');
        if (repartidorNombre != null) {
          await prefs.setString(
            'cached_repartidor_nombre_${user.id}',
            repartidorNombre,
          );
        }
        await RepartidorMasterUtil.saveCached(user.id, esMaster);

        if (tenantId != null && tenantId.isNotEmpty) {
          final tenantData = await supabase
              .from('tenants')
              .select('nombre')
              .eq('id', tenantId)
              .maybeSingle();
          if (tenantData?['nombre'] != null) {
            nombreEmpresa = tenantData!['nombre'].toString();
            await guardarNombreEmpresaEnCache(user.id, nombreEmpresa);
          }
        }
      }
    } catch (e) {
      print('⚠️ [SEGURIDAD] Error cargando contexto: $e');
    }

    return RepartidorSesionContext(
      tenantId: tenantId?.trim().isEmpty == true ? null : tenantId,
      nombreEmpresa:
          nombreEmpresa.trim().isEmpty ? 'tu empresa' : nombreEmpresa.trim(),
      repartidorNombre: repartidorNombre,
      esMaster: esMaster,
    );
  }

  static bool nombresRepartidorCoinciden(String? a, String? b) {
    if (a == null || b == null) return false;
    return a.trim().toUpperCase() == b.trim().toUpperCase();
  }

  static RepartidorOrdenAcceso evaluarAccesoOrden({
    required Orden orden,
    required RepartidorSesionContext ctx,
  }) {
    if (ctx.tenantId == null || ctx.tenantId!.isEmpty) {
      return RepartidorOrdenAcceso.sesionInvalida;
    }

    final ordenTenant = orden.tenantId?.trim() ?? '';
    if (ordenTenant.isEmpty || ordenTenant != ctx.tenantId) {
      return RepartidorOrdenAcceso.otraEmpresa;
    }

    if (orden.entregaPorVendedor) {
      return RepartidorOrdenAcceso.entregaPorVendedor;
    }

    if (ctx.esMaster) {
      return RepartidorOrdenAcceso.permitido;
    }

    final asignado = orden.repartidor?.trim() ?? '';
    if (asignado.isEmpty) {
      return RepartidorOrdenAcceso.noAsignada;
    }

    if (!nombresRepartidorCoinciden(asignado, ctx.repartidorNombre)) {
      return RepartidorOrdenAcceso.noAsignada;
    }

    return RepartidorOrdenAcceso.permitido;
  }

  static Future<void> mostrarDialogoAccesoDenegado({
    required BuildContext context,
    required RepartidorOrdenAcceso motivo,
    required RepartidorSesionContext ctx,
    required String numeroOrden,
    String? repartidorAsignado,
  }) async {
    if (!context.mounted) return;

    final String titulo;
    final String mensaje;

    switch (motivo) {
      case RepartidorOrdenAcceso.otraEmpresa:
        titulo = 'Orden no reconocida';
        mensaje =
            'No se reconoce esta orden. No pertenece a la empresa ${ctx.nombreEmpresa}. '
            'Solo puedes escanear órdenes de tu empresa.';
        break;
      case RepartidorOrdenAcceso.noAsignada:
        titulo = 'Orden no asignada a usted';
        if (repartidorAsignado != null && repartidorAsignado.trim().isNotEmpty) {
          mensaje =
              'La orden $numeroOrden no le pertenece. '
              'Está asignada al repartidor $repartidorAsignado. '
              'Contacte a su supervisor o al repartidor asignado.';
        } else {
          mensaje =
              'La orden $numeroOrden no está asignada a usted. '
              'Solo puede trabajar órdenes que tenga asignadas.';
        }
        break;
      case RepartidorOrdenAcceso.sesionInvalida:
        titulo = 'Sesión incompleta';
        mensaje =
            'No se pudo verificar su empresa. Cierre sesión e inicie de nuevo.';
        break;
      case RepartidorOrdenAcceso.entregaPorVendedor:
        titulo = 'Entrega por vendedor';
        mensaje =
            'La orden $numeroOrden la entrega el vendedor de la tienda. '
            'No está disponible en el panel del repartidor.';
        break;
      case RepartidorOrdenAcceso.permitido:
        return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => VolonexDialog(
        title: titulo,
        leading: const Icon(
          Icons.block,
          color: AppColors.error,
          size: 26,
        ),
        child: Text(
          mensaje,
          style: const TextStyle(
            color: AppColors.darkText,
            fontSize: 14,
            height: 1.45,
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.botonPrincipal,
              foregroundColor: Colors.white,
            ),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }
}
