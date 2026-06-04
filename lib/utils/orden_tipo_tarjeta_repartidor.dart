import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/orden.dart';

/// Tipo visual de tarjeta en la lista del repartidor (sin jerga técnica al usuario).
enum OrdenTipoTarjetaRepartidor {
  remesaPura,
  recogidaDomicilio,
  recogidaColaborador,
  entregaColaborador,
  envioPanel,
  envioConRemesa,
}

class OrdenTipoTarjetaInfo {
  const OrdenTipoTarjetaInfo({
    required this.tipo,
    required this.etiqueta,
    required this.icono,
    required this.colorAcento,
    required this.colorFondo,
  });

  final OrdenTipoTarjetaRepartidor tipo;
  final String etiqueta;
  final IconData icono;
  final Color colorAcento;
  final Color colorFondo;
}

class OrdenTipoTarjetaRepartidorUtil {
  OrdenTipoTarjetaRepartidorUtil._();

  static const Color _fondoTarjeta = AppColors.darkSurface;

  static bool esRemesaPura(Orden orden) {
    if (!orden.tieneRemesa) return false;
    final peso = orden.peso ?? 0.0;
    if (peso > 0) return false;
    final items = orden.itemsAdicionales;
    final tieneItems = items != null && items.isNotEmpty;
    return !tieneItems;
  }

  static OrdenTipoTarjetaRepartidor clasificar(Orden orden) {
    if (esRemesaPura(orden)) {
      return OrdenTipoTarjetaRepartidor.remesaPura;
    }
    if ((orden.tipoOrden ?? '').toUpperCase() == 'RECOGIDA') {
      return OrdenTipoTarjetaRepartidor.recogidaDomicilio;
    }
    if (orden.entregaPorVendedor) {
      return OrdenTipoTarjetaRepartidor.entregaColaborador;
    }
    final avisos = orden.avisosRecogidaVendedor;
    final tieneAvisos = avisos != null && avisos.isNotEmpty;
    final contactoVendedor =
        (orden.vendedorContactoNombre ?? '').trim().isNotEmpty;
    if (orden.esOrdenTiendaOnline && (tieneAvisos || contactoVendedor)) {
      return OrdenTipoTarjetaRepartidor.recogidaColaborador;
    }
    if (orden.esOrdenTiendaOnline) {
      return OrdenTipoTarjetaRepartidor.entregaColaborador;
    }
    if (orden.tieneRemesa) {
      return OrdenTipoTarjetaRepartidor.envioConRemesa;
    }
    return OrdenTipoTarjetaRepartidor.envioPanel;
  }

  static OrdenTipoTarjetaInfo info(OrdenTipoTarjetaRepartidor tipo) {
    switch (tipo) {
      case OrdenTipoTarjetaRepartidor.remesaPura:
        return const OrdenTipoTarjetaInfo(
          tipo: OrdenTipoTarjetaRepartidor.remesaPura,
          etiqueta: 'Remesa',
          icono: Icons.payments_outlined,
          colorAcento: Color(0xFF64B5F6),
          colorFondo: _fondoTarjeta,
        );
      case OrdenTipoTarjetaRepartidor.recogidaDomicilio:
        return const OrdenTipoTarjetaInfo(
          tipo: OrdenTipoTarjetaRepartidor.recogidaDomicilio,
          etiqueta: 'Recogida',
          icono: Icons.home_work_outlined,
          colorAcento: Color(0xFFCE93D8),
          colorFondo: _fondoTarjeta,
        );
      case OrdenTipoTarjetaRepartidor.recogidaColaborador:
        return const OrdenTipoTarjetaInfo(
          tipo: OrdenTipoTarjetaRepartidor.recogidaColaborador,
          etiqueta: 'Recoger colaborador',
          icono: Icons.storefront_outlined,
          colorAcento: AppColors.botonPrincipal,
          colorFondo: _fondoTarjeta,
        );
      case OrdenTipoTarjetaRepartidor.entregaColaborador:
        return const OrdenTipoTarjetaInfo(
          tipo: OrdenTipoTarjetaRepartidor.entregaColaborador,
          etiqueta: 'Pedido colaborador',
          icono: Icons.shopping_bag_outlined,
          colorAcento: Color(0xFF4DB6AC),
          colorFondo: _fondoTarjeta,
        );
      case OrdenTipoTarjetaRepartidor.envioConRemesa:
        return const OrdenTipoTarjetaInfo(
          tipo: OrdenTipoTarjetaRepartidor.envioConRemesa,
          etiqueta: 'Envío + remesa',
          icono: Icons.local_shipping_outlined,
          colorAcento: Color(0xFF4FC3F7),
          colorFondo: _fondoTarjeta,
        );
      case OrdenTipoTarjetaRepartidor.envioPanel:
        return const OrdenTipoTarjetaInfo(
          tipo: OrdenTipoTarjetaRepartidor.envioPanel,
          etiqueta: 'Envío empresa',
          icono: Icons.inventory_2_outlined,
          colorAcento: Color(0xFF90A4AE),
          colorFondo: _fondoTarjeta,
        );
    }
  }

  static OrdenTipoTarjetaInfo infoDeOrden(Orden orden) =>
      info(clasificar(orden));
}
