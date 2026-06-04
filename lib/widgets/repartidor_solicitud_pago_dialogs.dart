import 'package:flutter/material.dart';
import '../services/repartidor_solicitud_pago_service.dart';
import '../config/app_colors.dart';
import 'volonex_ui.dart';

/// Diálogos para solicitar nómina según método de pago de la empresa.
class RepartidorSolicitudPagoDialogs {
  RepartidorSolicitudPagoDialogs._();

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
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final dist = double.tryParse(distanciaCtrl.text.trim()) ?? 0;
          montoCalc = RepartidorSolicitudPagoService.calcularMontoDistancia(
            tarifa: preview.tarifa,
            distancia: dist,
          );
          return AlertDialog(
            backgroundColor: const Color(0xFFFFFFFF),
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            constraints: const BoxConstraints(maxWidth: 420),
            title: const Row(
              children: [
                Icon(Icons.route, color: Color(0xFFFF9800)),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Recorrido del período',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textOnLight),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tarifa de la empresa: ${preview.tarifa.toStringAsFixed(2)} ${preview.moneda} por $unidadLabel.',
                    style: const TextStyle(fontSize: 13, color: AppColors.textMutedOnLight),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: distanciaCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setSt(() {}),
                    decoration: InputDecoration(
                      labelText: 'Total $unidadLabel recorridos',
                      hintText: preview.unidadEsMilla ? 'Ej: 45.5' : 'Ej: 100',
                      suffixText: unidadCorto,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF4CAF50)),
                    ),
                    child: Text(
                      'Total a solicitar: ${montoCalc.toStringAsFixed(2)} ${preview.moneda}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF9800)),
                onPressed: () {
                  if (dist <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Ingresa la distancia recorrida'), backgroundColor: Colors.red),
                    );
                    return;
                  }
                  if (montoCalc <= 0) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('No se pudo calcular el monto'), backgroundColor: Colors.red),
                    );
                    return;
                  }
                  distanciaFinal = dist;
                  Navigator.pop(ctx, true);
                },
                child: const Text('Enviar solicitud'),
              ),
            ],
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
          backgroundColor: Colors.orange,
        ),
      );
      return false;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFFFFFF),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        constraints: const BoxConstraints(maxWidth: 420),
        title: const Row(
          children: [
            Icon(Icons.calendar_month, color: Color(0xFFFF9800)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Nómina por días trabajados',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textOnLight),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Última nómina aceptada: $fechaTxt',
              style: const TextStyle(fontSize: 13, color: AppColors.textMutedOnLight),
            ),
            if (preview.diasLaborablesEtiqueta.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Días laborables (empresa): ${preview.diasLaborablesEtiqueta}',
                style: const TextStyle(fontSize: 13, color: AppColors.textMutedOnLight),
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'Días laborables a cobrar: $dias',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textOnLight),
            ),
            const SizedBox(height: 6),
            Text(
              'Tarifa: ${preview.tarifa.toStringAsFixed(2)} ${preview.moneda} / día',
              style: const TextStyle(fontSize: 13, color: AppColors.textMutedOnLight),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF4CAF50)),
              ),
              child: Text(
                'Total: ${monto.toStringAsFixed(2)} ${preview.moneda}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF9800)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enviar solicitud'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  static Future<({double monto, String moneda})?> modalPorOrden(
    BuildContext context, {
    required double saldo,
    required String moneda,
    required int totalOrdenes,
  }) async {
    final montoCtrl = TextEditingController(text: saldo > 0 ? saldo.toStringAsFixed(2) : '');
    String monedaSel = moneda;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: const Color(0xFFFFFFFF),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          constraints: const BoxConstraints(maxWidth: 420),
          title: const Row(
            children: [
              Icon(Icons.payment, color: Color(0xFFFF9800)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Solicitar pago',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textOnLight),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF4CAF50)),
                  ),
                  child: Text(
                    'Saldo disponible: ${saldo.toStringAsFixed(2)} $moneda',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF2E7D32)),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  totalOrdenes > 0
                      ? 'Órdenes pendientes de cobro: $totalOrdenes'
                      : 'Sin órdenes nuevas; puedes cobrar solo el saldo acumulado.',
                  style: const TextStyle(fontSize: 13, color: AppColors.textMutedOnLight),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: montoCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Monto a solicitar',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    VolonexUi.materialFilterChip(
                      label: 'USD',
                      selected: monedaSel == 'USD',
                      onSelected: (v) => setSt(() => monedaSel = 'USD'),
                    ),
                    const SizedBox(width: 8),
                    VolonexUi.materialFilterChip(
                      label: 'CUP',
                      selected: monedaSel == 'CUP',
                      onSelected: (v) => setSt(() => monedaSel = 'CUP'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF9800)),
              onPressed: () {
                final m = double.tryParse(montoCtrl.text.trim());
                if (m == null || m <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Monto inválido'), backgroundColor: Colors.red),
                  );
                  return;
                }
                if (m > saldo + 0.001) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('No puede superar el saldo (${saldo.toStringAsFixed(2)})'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Enviar'),
            ),
          ],
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
}
