import 'package:flutter/material.dart';
import '../services/repartidor_solicitud_pago_service.dart';
import '../config/app_colors.dart';
import 'volonex_dialog.dart';
import 'volonex_ui.dart';
import '../utils/moneda_tenant_util.dart';

/// Diálogos para solicitar nómina — tema oscuro Volonex.
class RepartidorSolicitudPagoDialogs {
  RepartidorSolicitudPagoDialogs._();

  static InputDecoration _campoOscuro({
    required String label,
    String? hint,
    String? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixText: suffix,
      labelStyle: const TextStyle(color: AppColors.darkTextMuted),
      hintStyle: const TextStyle(color: AppColors.darkTextMuted),
      filled: true,
      fillColor: AppColors.darkElevated,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.botonPrincipal, width: 1.5),
      ),
    );
  }

  static Widget _cajaDestacada(String texto, {Color? color}) {
    final c = color ?? AppColors.exito;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text(
        texto,
        style: TextStyle(fontWeight: FontWeight.w600, color: c, fontSize: 14),
      ),
    );
  }

  static Future<({double distancia, double monto})?> modalPorDistancia(
    BuildContext context,
    RepartidorSolicitudPreview preview,
  ) async {
    final distanciaCtrl = TextEditingController();
    double montoCalc = 0;
    double distanciaFinal = 0;
    final unidadLabel = preview.unidadEsMilla ? 'millas' : 'km';
    final unidadCorto = preview.unidadEsMilla ? 'mi' : 'km';

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final dist = double.tryParse(distanciaCtrl.text.trim()) ?? 0;
          montoCalc = RepartidorSolicitudPagoService.calcularMontoDistancia(
            tarifa: preview.tarifa,
            distancia: dist,
          );
          return VolonexDialog(
            title: 'Recorrido del período',
            leading: const Icon(Icons.route, color: AppColors.botonPrincipal, size: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tarifa: ${preview.tarifa.toStringAsFixed(2)} ${preview.moneda} por $unidadLabel.',
                  style: const TextStyle(color: AppColors.darkTextMuted, fontSize: 13),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: distanciaCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: AppColors.darkText),
                  onChanged: (_) => setSt(() {}),
                  decoration: _campoOscuro(
                    label: 'Total $unidadLabel recorridos',
                    hint: preview.unidadEsMilla ? 'Ej: 45.5' : 'Ej: 100',
                    suffix: unidadCorto,
                  ),
                ),
                const SizedBox(height: 12),
                _cajaDestacada(
                  'Total a solicitar: ${montoCalc.toStringAsFixed(2)} ${preview.moneda}',
                ),
              ],
            ),
            actions: _accionesEnviar(
              ctx,
              onEnviar: () {
                if (dist <= 0) {
                  _snack(ctx, 'Ingresa la distancia recorrida');
                  return;
                }
                if (montoCalc <= 0) {
                  _snack(ctx, 'No se pudo calcular el monto');
                  return;
                }
                distanciaFinal = dist;
                Navigator.pop(ctx, true);
              },
            ),
          );
        },
      ),
    );

    distanciaCtrl.dispose();
    if (ok == true && montoCalc > 0 && distanciaFinal > 0) {
      return (distancia: distanciaFinal, monto: montoCalc);
    }
    return null;
  }

  static Future<bool> modalPorDia(
    BuildContext context,
    RepartidorSolicitudPreview preview,
  ) async {
    final dias = preview.diasDesdeUltimaNomina;
    final monto = preview.montoEstimadoPorDia;
    String fechaTxt = '—';
    if (preview.ultimaNominaFecha != null) {
      final d = preview.ultimaNominaFecha!;
      fechaTxt = '${d.day}/${d.month}/${d.year}';
    }

    if (dias <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay días nuevos desde tu última nómina aceptada'),
          backgroundColor: AppColors.botonPrincipal,
        ),
      );
      return false;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) => VolonexDialog(
        title: 'Nómina por días trabajados',
        leading: const Icon(Icons.calendar_month, color: AppColors.botonPrincipal, size: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Última nómina aceptada: $fechaTxt',
              style: const TextStyle(fontSize: 13, color: AppColors.darkTextMuted),
            ),
            if (preview.diasLaborablesEtiqueta.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Días laborables: ${preview.diasLaborablesEtiqueta}',
                style: const TextStyle(fontSize: 13, color: AppColors.darkTextMuted),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Días a cobrar: $dias',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.darkText),
            ),
            const SizedBox(height: 6),
            Text(
              'Tarifa: ${preview.tarifa.toStringAsFixed(2)} ${preview.moneda} / día',
              style: const TextStyle(fontSize: 13, color: AppColors.darkTextMuted),
            ),
            const SizedBox(height: 12),
            _cajaDestacada('Total: ${monto.toStringAsFixed(2)} ${preview.moneda}'),
          ],
        ),
        actions: _accionesEnviar(ctx, onEnviar: () => Navigator.pop(ctx, true)),
      ),
    );
    return ok == true;
  }

  static Future<({double monto, String moneda})?> modalPorOrden(
    BuildContext context, {
    required double saldo,
    required String moneda,
    required int totalOrdenes,
    String? paisOperacion,
  }) async {
    final montoCtrl = TextEditingController(text: saldo > 0 ? saldo.toStringAsFixed(2) : '');
    String monedaSel = MonedaTenantUtil.normalizarMoneda(moneda, paisOperacion);

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => VolonexDialog(
          title: 'Solicitar pago',
          leading: const Icon(Icons.payment, color: AppColors.botonPrincipal, size: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _cajaDestacada(
                'Saldo disponible: ${saldo.toStringAsFixed(2)} $moneda',
              ),
              const SizedBox(height: 12),
              Text(
                totalOrdenes > 0
                    ? 'Órdenes pendientes de cobro: $totalOrdenes'
                    : 'Sin órdenes nuevas; puedes cobrar el saldo acumulado.',
                style: const TextStyle(fontSize: 13, color: AppColors.darkTextMuted, height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: montoCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: AppColors.darkText, fontSize: 16),
                decoration: _campoOscuro(label: 'Monto a solicitar'),
              ),
              const SizedBox(height: 14),
              const Text(
                'Moneda',
                style: TextStyle(fontSize: 12, color: AppColors.darkTextMuted),
              ),
              const SizedBox(height: 8),
              Wrap(
                children: [
                  VolonexUi.filterChip(
                    label: 'USD',
                    selected: monedaSel == 'USD',
                    onTap: () => setSt(() => monedaSel = 'USD'),
                  ),
                  if (MonedaTenantUtil.permiteCup(paisOperacion))
                    VolonexUi.filterChip(
                      label: 'CUP',
                      selected: monedaSel == 'CUP',
                      onTap: () => setSt(() => monedaSel = 'CUP'),
                    ),
                ],
              ),
            ],
          ),
          actions: _accionesEnviar(
            ctx,
            onEnviar: () {
              final m = double.tryParse(montoCtrl.text.trim());
              if (m == null || m <= 0) {
                _snack(ctx, 'Monto inválido');
                return;
              }
              if (m > saldo + 0.001) {
                _snack(ctx, 'No puede superar el saldo (${saldo.toStringAsFixed(2)})');
                return;
              }
              Navigator.pop(ctx, true);
            },
          ),
        ),
      ),
    );

    final monto = double.tryParse(montoCtrl.text.trim());
    montoCtrl.dispose();
    if (ok == true && monto != null && monto > 0) {
      return (monto: monto, moneda: monedaSel);
    }
    return null;
  }

  static List<Widget> _accionesEnviar(BuildContext ctx, {required VoidCallback onEnviar}) {
    return [
      TextButton(
        onPressed: () => Navigator.pop(ctx, false),
        child: const Text('Cancelar', style: TextStyle(color: AppColors.darkTextMuted)),
      ),
      ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.botonPrincipal,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        ),
        onPressed: onEnviar,
        child: const Text('Enviar', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    ];
  }

  static void _snack(BuildContext ctx, String msg) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }
}
