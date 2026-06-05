import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/repartidor_historial_pago_service.dart';

/// Tarjeta compacta para el perfil (sin detalle de órdenes; tap abre historial completo).
class HistorialPagoResumenCard extends StatelessWidget {
  const HistorialPagoResumenCard({
    super.key,
    required this.item,
    this.onTap,
  });

  final HistorialNominaItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ui = HistorialPagoDetalleCard._estadoUi(item.estado);
    final metodoLabel = HistorialNominaItem.etiquetaMetodo(item.metodo);
    final esPendiente = item.estado == 'PENDIENTE';
    final ordenesTxt = item.totalOrdenes > 0
        ? '${item.totalOrdenes} orden${item.totalOrdenes == 1 ? '' : 'es'}'
        : null;

    final card = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.darkElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ui.color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: esPendiente
                ? Padding(
                    padding: const EdgeInsets.all(4),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: ui.color,
                    ),
                  )
                : Icon(ui.icon, color: ui.color, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ui.label,
                  style: TextStyle(
                    color: ui.color,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  metodoLabel,
                  style: const TextStyle(color: AppColors.darkTextMuted, fontSize: 11),
                ),
                if (ordenesTxt != null && item.metodo == 'por_orden')
                  Text(
                    ordenesTxt,
                    style: const TextStyle(color: AppColors.darkTextMuted, fontSize: 11),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '\$${item.monto.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: AppColors.darkText,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                item.moneda,
                style: const TextStyle(color: AppColors.darkTextMuted, fontSize: 10),
              ),
            ],
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: AppColors.darkTextMuted, size: 18),
          ],
        ],
      ),
    );

    if (onTap == null) return card;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: card,
    );
  }
}

/// Tarjeta detallada de una solicitud de nómina (tema oscuro, pantalla historial completo).
class HistorialPagoDetalleCard extends StatelessWidget {
  const HistorialPagoDetalleCard({
    super.key,
    required this.item,
    this.expanded = true,
    this.onTap,
  });

  final HistorialNominaItem item;
  final bool expanded;
  final VoidCallback? onTap;

  static String formatearFecha(DateTime? fecha) {
    if (fecha == null) return '—';
    return '${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year} '
        '${fecha.hour.toString().padLeft(2, '0')}:${fecha.minute.toString().padLeft(2, '0')}';
  }

  static ({Color color, IconData icon, String label}) _estadoUi(String estado) {
    switch (estado) {
      case 'PENDIENTE':
        return (color: AppColors.botonPrincipal, icon: Icons.pending, label: 'Pendiente de revisión');
      case 'ACEPTADO':
        return (color: AppColors.exito, icon: Icons.check_circle, label: 'Nómina aceptada');
      case 'RECHAZADO':
        return (color: AppColors.error, icon: Icons.cancel, label: 'Rechazada');
      case 'CANCELADA':
        return (color: AppColors.error, icon: Icons.block, label: 'Cancelada');
      default:
        return (color: AppColors.darkTextMuted, icon: Icons.help_outline, label: estado);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui = HistorialPagoDetalleCard._estadoUi(item.estado);
    final esPendiente = item.estado == 'PENDIENTE';
    final metodoLabel = HistorialNominaItem.etiquetaMetodo(item.metodo);
    final km = item.kilometros;
    final dias = item.diasTrabajados;

    final content = Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ui.color.withValues(alpha: 0.45)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: expanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          leading: Container(
            width: 38,
            height: 38,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: ui.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: esPendiente
                ? CircularProgressIndicator(strokeWidth: 2.2, color: ui.color)
                : Icon(ui.icon, color: ui.color, size: 22),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ui.label,
                style: TextStyle(
                  color: ui.color,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              Text(
                metodoLabel,
                style: const TextStyle(color: AppColors.darkTextMuted, fontSize: 12),
              ),
            ],
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${item.monto.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: AppColors.darkText,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                item.moneda,
                style: const TextStyle(color: AppColors.darkTextMuted, fontSize: 11),
              ),
            ],
          ),
          children: [
            _fila(Icons.send_outlined, 'Solicitud enviada', formatearFecha(item.fechaSolicitud)),
            if (item.estado == 'ACEPTADO' && item.fechaAceptacion != null) ...[
              _fila(Icons.payments_outlined, 'Cobro registrado', formatearFecha(item.fechaAceptacion)),
              if (item.solicitud['aceptado_por_nombre'] != null)
                _fila(
                  Icons.business_outlined,
                  'Revisado por',
                  item.solicitud['aceptado_por_nombre'].toString(),
                ),
              _fila(
                Icons.account_balance_wallet_outlined,
                'Efectivo entregado',
                item.dineroEnviado ? 'Sí — marcado como pagado' : 'Pendiente de marcar en empresa',
              ),
            ],
            if (item.metodo == 'por_orden' && item.totalOrdenes > 0) ...[
              const Divider(color: AppColors.darkBorder, height: 20),
              _fila(
                Icons.local_shipping_outlined,
                'Órdenes incluidas',
                '${item.totalOrdenes} orden${item.totalOrdenes == 1 ? '' : 'es'}',
              ),
            ],
            if (item.metodo == 'por_distancia' && km != null && km > 0) ...[
              const Divider(color: AppColors.darkBorder, height: 20),
              _fila(
                Icons.route,
                'Recorrido declarado',
                '${km.toStringAsFixed(2)} ${item.unidadDistancia == 'milla' ? 'millas' : 'km'}',
              ),
            ],
            if (item.metodo == 'por_dia' && dias != null && dias > 0) ...[
              const Divider(color: AppColors.darkBorder, height: 20),
              _fila(Icons.calendar_month, 'Días laborables cobrados', '$dias días'),
            ],
            if (item.solicitud['notas'] != null &&
                item.solicitud['notas'].toString().trim().isNotEmpty) ...[
              const Divider(color: AppColors.darkBorder, height: 20),
              _fila(Icons.notes, 'Notas', item.solicitud['notas'].toString()),
            ],
          ],
        ),
      ),
    );

    if (onTap == null) return content;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: content);
  }

  Widget _fila(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.darkTextMuted),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 12, color: AppColors.darkTextMuted),
                children: [
                  TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextSpan(text: value, style: const TextStyle(color: AppColors.darkText)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

}

/// Fila compacta de acreditación de saldo por entrega.
class HistorialAcreditacionCard extends StatelessWidget {
  const HistorialAcreditacionCard({super.key, required this.movimiento});

  final Map<String, dynamic> movimiento;

  @override
  Widget build(BuildContext context) {
    final monto = movimiento['monto'];
    final val = monto is num ? monto.toDouble() : double.tryParse('$monto') ?? 0;
    final moneda = movimiento['moneda']?.toString() ?? 'USD';
    final detalle = movimiento['detalle']?.toString() ?? '';
    final tipo = movimiento['tipo']?.toString() ?? '';
    final fecha = HistorialPagoDetalleCard.formatearFecha(
      DateTime.tryParse(movimiento['created_at']?.toString() ?? ''),
    );

    String titulo = 'Acreditación de saldo';
    if (tipo == 'acreditacion_orden') titulo = 'Saldo por entrega/recogida';
    if (tipo == 'reintegro_rechazo') titulo = 'Saldo reintegrado';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.exito.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.add_circle_outline, color: AppColors.exito, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(color: AppColors.darkText, fontWeight: FontWeight.w600, fontSize: 13)),
                if (detalle.isNotEmpty)
                  Text(detalle, style: const TextStyle(color: AppColors.darkTextMuted, fontSize: 11)),
                Text(fecha, style: const TextStyle(color: AppColors.darkTextMuted, fontSize: 10)),
              ],
            ),
          ),
          Text(
            '+\$${val.toStringAsFixed(2)}',
            style: const TextStyle(color: AppColors.exito, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(width: 4),
          Text(moneda, style: const TextStyle(color: AppColors.darkTextMuted, fontSize: 10)),
        ],
      ),
    );
  }
}
