import '../models/orden.dart';
import 'orden_tipo_tarjeta_repartidor.dart';

/// UI y reglas de negocio para pedidos de tienda donde el repartidor recoge en un colaborador.
class OrdenRecogidaColaboradorUi {
  OrdenRecogidaColaboradorUi._();

  static bool esRecogidaColaborador(Orden orden) =>
      OrdenTipoTarjetaRepartidorUtil.clasificar(orden) ==
      OrdenTipoTarjetaRepartidor.recogidaColaborador;

  /// Antes de confirmar recogida: solo datos del colaborador, no destino final.
  static bool enFaseRecogidaColaborador(Orden orden) {
    if (!esRecogidaColaborador(orden)) return false;
    final e = orden.estado.trim().toUpperCase();
    return e == 'POR ENVIAR';
  }

  static bool colaboradorMarcoListo(Orden orden) {
    final avisos = orden.avisosRecogidaVendedor;
    return avisos != null && avisos.isNotEmpty;
  }

  /// Etiqueta visible al repartidor (no usar «POR ENVIAR» en fase de recogida local).
  static String estadoVisibleRepartidor(Orden orden) {
    if (enFaseRecogidaColaborador(orden)) {
      return colaboradorMarcoListo(orden) ? 'LISTO PARA RECOGIDA' : 'POR RECOLECTAR';
    }
    return orden.estado.trim();
  }

  static const List<String> estadosTimeline = [
    'POR RECOLECTAR',
    'LISTO PARA RECOGIDA',
    'EN REPARTO',
    'ENTREGADO',
  ];

  static int indiceEstadoTimeline(Orden orden) {
    if (enFaseRecogidaColaborador(orden)) {
      return colaboradorMarcoListo(orden) ? 1 : 0;
    }
    final e = orden.estado.trim().toUpperCase();
    if (e == 'ENTREGADO' || e == 'ENTREGADO EN SUCURSAL') return 3;
    if (e == 'EN REPARTO' || e == 'EN TRANSITO' || e == 'ATRASADO') return 2;
    if (colaboradorMarcoListo(orden)) return 1;
    return 0;
  }

  static String mensajeInfoTarjeta(Orden orden) {
    if (colaboradorMarcoListo(orden)) {
      return 'El colaborador indicó que los artículos están listos. Ve al punto de recogida indicado abajo.';
    }
    return 'Debes recoger este pedido en el colaborador. La entrega al cliente será después de la recogida.';
  }

  static String mensajeAccionBloqueada(Orden orden) {
    if (colaboradorMarcoListo(orden)) {
      return 'Recoge el pedido en el colaborador y pulsa «Confirmar recogida» para iniciar la entrega al cliente.';
    }
    return 'Coordina la recogida con el colaborador. Cuando tengas el pedido, confirma la recogida para pasar a reparto.';
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
}
