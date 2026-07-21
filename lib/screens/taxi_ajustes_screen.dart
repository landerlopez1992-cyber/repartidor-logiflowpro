import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_colors.dart';
import '../services/taxi_tarifas_chofer_service.dart';

/// Ajustes de tarifa taxi del socio (precio por km o milla).
class TaxiAjustesScreen extends StatefulWidget {
  const TaxiAjustesScreen({super.key});

  @override
  State<TaxiAjustesScreen> createState() => _TaxiAjustesScreenState();
}

class _TaxiAjustesScreenState extends State<TaxiAjustesScreen> {
  final _precioCtrl = TextEditingController();
  String _unidad = 'km';
  bool _loading = true;
  bool _saving = false;

  static const double _ejemploDistancia = 20;

  @override
  void initState() {
    super.initState();
    _precioCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _cargar();
  }

  double? get _precioParsed {
    final raw = _precioCtrl.text.trim().replaceAll(',', '.');
    return double.tryParse(raw);
  }

  String get _ejemploCobro {
    final p = _precioParsed;
    if (p == null || p < 0.01) {
      return 'Escribe tu tarifa para ver un ejemplo de cobro.';
    }
    final total = p * _ejemploDistancia;
    return 'Si el trayecto es ${_ejemploDistancia.toStringAsFixed(0)} $_unidad, '
        'cobrarías \$${total.toStringAsFixed(2)} USD.';
  }

  Future<void> _cargar() async {
    final t = await TaxiTarifasChoferService.instance.get();
    if (!mounted) return;
    setState(() {
      _unidad = t.unidad;
      if (t.precioPorUnidadUsd > 0) {
        _precioCtrl.text = t.precioPorUnidadUsd.toStringAsFixed(
          t.precioPorUnidadUsd == t.precioPorUnidadUsd.roundToDouble() ? 0 : 2,
        );
      }
      _loading = false;
    });
  }

  Future<void> _guardar() async {
    final raw = _precioCtrl.text.trim().replaceAll(',', '.');
    final precio = double.tryParse(raw);
    if (precio == null || precio < 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa una tarifa válida (mínimo 0.01).'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.darkSurface,
        constraints: const BoxConstraints(maxWidth: 400),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Importante sobre tu tarifa',
          style: TextStyle(
            color: AppColors.darkText,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        content: SingleChildScrollView(
          child: Text(
            'Vas a cobrar \$${precio.toStringAsFixed(2)} USD por $_unidad.\n\n'
            'Mientras más cara sea tu tarifa, menos posibilidades tendrás de '
            'obtener viajes: el cliente verá varios socios y elegirá el más '
            'económico o el más cercano.\n\n'
            'Una tarifa competitiva genera más cantidad de viajes.',
            style: const TextStyle(
              color: AppColors.darkTextMuted,
              height: 1.4,
              fontSize: 14,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Revisar',
              style: TextStyle(color: AppColors.darkTextMuted),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.header,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Guardar tarifa',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    setState(() => _saving = true);
    final res = await TaxiTarifasChoferService.instance.guardar(
      unidad: _unidad,
      precioPorUnidadUsd: precio,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          res.ok
              ? 'Tarifa guardada: \$${precio.toStringAsFixed(2)} / $_unidad'
              : (res.err ?? 'Error al guardar'),
        ),
        backgroundColor: res.ok ? AppColors.exito : AppColors.error,
      ),
    );
    if (res.ok) Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _precioCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.header,
        title: const Text('Ajustes de taxis'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF9800)),
            )
          : Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.darkElevated,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.local_taxi,
                                    color: Color(0xFF9CA3AF), size: 22),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Tu tarifa de viaje',
                                    style: TextStyle(
                                      color: AppColors.darkText,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 10),
                            Text(
                              'El precio del viaje = distancia del trayecto × tu tarifa. '
                              'Ese monto es el que verá el cliente al elegir socio.',
                              style: TextStyle(
                                color: AppColors.darkTextMuted,
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Unidad',
                        style: TextStyle(
                          color: AppColors.darkTextMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _unidadChip('Por kilómetro', 'km'),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _unidadChip('Por milla', 'mi'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _precioCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[0-9.,]'),
                          ),
                        ],
                        style: const TextStyle(color: AppColors.darkText),
                        decoration: InputDecoration(
                          labelText: 'Precio por $_unidad (USD)',
                          labelStyle:
                              const TextStyle(color: AppColors.darkTextMuted),
                          hintText: 'Ej. 1.50',
                          hintStyle: TextStyle(
                            color: AppColors.darkTextMuted.withValues(alpha: 0.6),
                          ),
                          prefixText: '\$ ',
                          prefixStyle:
                              const TextStyle(color: AppColors.darkText),
                          filled: true,
                          fillColor: AppColors.darkElevated,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.darkElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Text(
                          _ejemploCobro,
                          style: const TextStyle(
                            color: Color(0xFFECEFF1),
                            fontSize: 13,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF252A35),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: const Color(0xFFFF9800).withValues(alpha: 0.35),
                          ),
                        ),
                        child: const Text(
                          'Tip: un precio económico suele darte más viajes. '
                          'Si cobras mucho más que otros socios, el cliente '
                          'elegirá a quien esté más barato o más cerca.',
                          style: TextStyle(
                            color: Color(0xFFECEFF1),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: _saving ? null : _guardar,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.header,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Guardar',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _unidadChip(String label, String value) {
    final selected = _unidad == value;
    return InkWell(
      onTap: () => setState(() => _unidad = value),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.header : AppColors.darkElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.white.withValues(alpha: selected ? 0.2 : 0.08),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.darkTextMuted,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
