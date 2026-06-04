import '../models/orden.dart';
import 'orden_tipo_tarjeta_repartidor.dart';

/// UI y reglas de negocio para pedidos de tienda donde el repartidor recoge en un colaborador.
class OrdenRecogidaColaboradorUi {
  OrdenRecogidaColaboradorUi._();

  static bool esRecogidaColaborador(Orden orden) =>
      OrdenTipoTarjetaRepartidorUtil.clasificar(orden) ==
      OrdenTipoTarjetaRepartidor.recogidaColaborador;

  /// Antes de confirmar recogida física: estado logística sigue POR ENVIAR.
  static bool enFaseRecogidaColaborador(Orden orden) {
    if (!esRecogidaColaborador(orden)) return false;
    final e = orden.estado.trim().toUpperCase();
    return e == 'POR ENVIAR';
  }

  static bool colaboradorMarcoListo(Orden orden) {
    final avisos = orden.avisosRecogidaVendedor;
    if (avisos == null || avisos.isEmpty) return false;
    for (final raw in avisos) {
      final listo = raw['listo_en'];
      if (listo != null && listo.toString().trim().isNotEmpty) return true;
    }
    return false;
  }

  static bool repartidorInicioRecolecta(Orden orden) {
    final avisos = orden.avisosRecogidaVendedor;
    if (avisos == null || avisos.isEmpty) return false;
    for (final raw in avisos) {
      final ini = raw['inicio_recolecta_en'];
      if (ini != null && ini.toString().trim().isNotEmpty) return true;
    }
    return false;
  }

  /// Etiqueta visible al repartidor (no usar «POR ENVIAR» en fase de recogida local).
  static String estadoVisibleRepartidor(Orden orden) {
    if (!enFaseRecogidaColaborador(orden)) {
      return orden.estado.trim();
    }
    if (repartidorInicioRecolecta(orden)) {
      return 'EN CAMINO A RECOGER';
    }
    if (colaboradorMarcoListo(orden)) {
      return 'LISTO PARA RECOGIDA';
    }
    return 'POR RECOLECTAR';
  }

  static const List<String> estadosTimeline = [
    'POR RECOLECTAR',
    'LISTO PARA RECOGIDA',
    'EN CAMINO A RECOGER',
    'EN REPARTO',
    'ENTREGADO',
  ];

  static int indiceEstadoTimeline(Orden orden) {
    if (enFaseRecogidaColaborador(orden)) {
      if (repartidorInicioRecolecta(orden)) return 2;
      if (colaboradorMarcoListo(orden)) return 1;
      return 0;
    }
    final e = orden.estado.trim().toUpperCase();
    if (e == 'ENTREGADO' || e == 'ENTREGADO EN SUCURSAL') return 4;
    if (e == 'EN REPARTO' || e == 'EN TRANSITO' || e == 'ATRASADO') return 3;
    if (repartidorInicioRecolecta(orden)) return 2;
    if (colaboradorMarcoListo(orden)) return 1;
    return 0;
  }

  static String mensajeInfoTarjeta(Orden orden) {
    if (repartidorInicioRecolecta(orden)) {
      return 'Estás en camino al colaborador. Al tener el pedido, confirma la recogida.';
    }
    if (colaboradorMarcoListo(orden)) {
      return 'El colaborador indicó que está listo. Pulsa «Iniciar recolecta» cuando salgas hacia su punto.';
    }
    return 'Recoge en el punto del colaborador. El cliente final y su dirección se mostrarán después de confirmar la recogida.';
  }

  static String etiquetaPlazo(Orden orden) {
    if (enFaseRecogidaColaborador(orden)) {
      return 'Recoger en colaborador';
    }
    return 'Entregar orden a más tardar';
  }

  static bool tieneDatosColaborador(Orden orden) {
    final n = (orden.vendedorContactoNombre ?? '').trim();
    final t = (orden.vendedorContactoTelefono ?? '').trim();
    final e = (orden.vendedorContactoEmail ?? '').trim();
    return n.isNotEmpty || t.isNotEmpty || e.isNotEmpty;
  }

  static bool puedeIniciarRecolecta(Orden orden) =>
      enFaseRecogidaColaborador(orden) &&
      colaboradorMarcoListo(orden) &&
      !repartidorInicioRecolecta(orden);

  static bool puedeConfirmarRecogida(Orden orden) =>
      enFaseRecogidaColaborador(orden) && repartidorInicioRecolecta(orden);

  /// Mientras el repartidor debe recoger en el colaborador: sin datos del cliente final.
  static bool ocultarDatosDestinatario(Orden orden) =>
      esRecogidaColaborador(orden) && enFaseRecogidaColaborador(orden);

  /// Tras confirmar recogida (EN REPARTO, etc.): sin colaborador ni avisos de recogida.
  static bool ocultarDatosColaboradorYAvisos(Orden orden) =>
      esRecogidaColaborador(orden) && !enFaseRecogidaColaborador(orden);

  static bool mostrarBloquePuntoColaborador(Orden orden) =>
      esRecogidaColaborador(orden) && enFaseRecogidaColaborador(orden);

  static bool mostrarBloqueDestinatario(Orden orden) =>
      !ocultarDatosDestinatario(orden);

  /// Tarjeta azul «Recoger en el vendedor» en lista (órdenes que no son recogida colaborador).
  static bool mostrarTarjetaContactoVendedorEnLista(Orden orden) {
    if (esRecogidaColaborador(orden)) return false;
    if (orden.entregaPorVendedor) return false;
    return tieneDatosColaborador(orden);
  }

  /// Evita bloque grande de avisos en detalle; el estado y el mensaje en tarjeta bastan.
  static bool mostrarBannerAvisosColaborador(Orden orden) => false;
}
