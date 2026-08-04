import 'package:flutter/material.dart';

import '../models/orden.dart';
import '../services/productos_orden_tienda_service.dart';
import '../utils/productos_orden_tienda_util.dart';

/// Resultado del diálogo parcial vs completa.
class EntregaTipoResultado {
  const EntregaTipoResultado({
    required this.tipo,
    this.indicesItems = const [],
    this.fechaEstimadaFaltantes,
  });

  /// `parcial` | `completa`
  final String tipo;
  final List<int> indicesItems;
  final DateTime? fechaEstimadaFaltantes;
}

/// Pregunta Parcial/Completa. En tienda, checklist de productos para parcial.
Future<EntregaTipoResultado?> mostrarDialogoTipoEntrega({
  required BuildContext context,
  required Orden orden,
}) async {
  final esTienda = ProductosOrdenTiendaUtil.esCompraTienda(orden);
  List<ProductoOrdenTiendaLinea> lineas = const [];
  if (esTienda) {
    final r = await ProductosOrdenTiendaService().cargar(orden.id, orden: orden);
    lineas = r.lineas;
  }

  if (!context.mounted) return null;

  return showDialog<EntregaTipoResultado>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return _EntregaTipoDialog(
        esTienda: esTienda,
        lineas: lineas,
      );
    },
  );
}

class _EntregaTipoDialog extends StatefulWidget {
  const _EntregaTipoDialog({
    required this.esTienda,
    required this.lineas,
  });

  final bool esTienda;
  final List<ProductoOrdenTiendaLinea> lineas;

  @override
  State<_EntregaTipoDialog> createState() => _EntregaTipoDialogState();
}

class _EntregaTipoDialogState extends State<_EntregaTipoDialog> {
  String? _tipo;
  final Set<int> _sel = {};
  DateTime? _fechaFaltantes;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E232E),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      constraints: const BoxConstraints(maxWidth: 420),
      title: const Text(
        'Tipo de entrega',
        style: TextStyle(color: Color(0xFFECEFF1), fontWeight: FontWeight.w600),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '¿Entrega parcial o completa?',
              style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
            ),
            const SizedBox(height: 12),
            _chip('parcial', 'Parcial', Icons.inventory_2_outlined),
            const SizedBox(height: 8),
            _chip('completa', 'Completa', Icons.check_circle_outline),
            if (_tipo == 'parcial' && widget.esTienda) ...[
              const SizedBox(height: 16),
              const Text(
                'Productos que entregas ahora',
                style: TextStyle(
                  color: Color(0xFFECEFF1),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              if (widget.lineas.isEmpty)
                const Text(
                  'No se encontraron productos de tienda en esta orden.',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
                )
              else
                ...List.generate(widget.lineas.length, (i) {
                  final l = widget.lineas[i];
                  final checked = _sel.contains(i);
                  return CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: checked,
                    activeColor: const Color(0xFF37474F),
                    checkColor: const Color(0xFFECEFF1),
                    title: Text(
                      '${l.nombre} ×${l.cantidad}',
                      style: const TextStyle(
                        color: Color(0xFFECEFF1),
                        fontSize: 13,
                      ),
                    ),
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _sel.add(i);
                        } else {
                          _sel.remove(i);
                        }
                      });
                    },
                  );
                }),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 3)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() => _fechaFaltantes = picked);
                  }
                },
                child: Text(
                  _fechaFaltantes == null
                      ? 'Fecha estimada de lo pendiente (opcional)'
                      : 'Faltantes: ${_fechaFaltantes!.day}/${_fechaFaltantes!.month}/${_fechaFaltantes!.year}',
                  style: const TextStyle(color: Color(0xFF9CA3AF)),
                ),
              ),
            ],
            if (_tipo == 'parcial' && !widget.esTienda) ...[
              const SizedBox(height: 12),
              const Text(
                'Se registrará entrega parcial del paquete. La orden seguirá activa hasta la entrega completa.',
                style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 12, height: 1.35),
              ),
              TextButton(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 3)),
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() => _fechaFaltantes = picked);
                  }
                },
                child: Text(
                  _fechaFaltantes == null
                      ? 'Fecha estimada de cierre (opcional)'
                      : 'Estimada: ${_fechaFaltantes!.day}/${_fechaFaltantes!.month}/${_fechaFaltantes!.year}',
                  style: const TextStyle(color: Color(0xFF9CA3AF)),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: Color(0xFF9CA3AF))),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF37474F),
            foregroundColor: const Color(0xFFECEFF1),
          ),
          onPressed: _puedeConfirmar
              ? () {
                  Navigator.pop(
                    context,
                    EntregaTipoResultado(
                      tipo: _tipo!,
                      indicesItems: _sel.toList()..sort(),
                      fechaEstimadaFaltantes: _fechaFaltantes,
                    ),
                  );
                }
              : null,
          child: const Text('Continuar'),
        ),
      ],
    );
  }

  bool get _puedeConfirmar {
    if (_tipo == null) return false;
    if (_tipo == 'completa') return true;
    if (!widget.esTienda) return true;
    return _sel.isNotEmpty;
  }

  Widget _chip(String value, String label, IconData icon) {
    final sel = _tipo == value;
    return InkWell(
      onTap: () => setState(() => _tipo = value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFF37474F) : const Color(0xFF252A35),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: sel
                ? const Color(0xFFECEFF1).withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF9CA3AF), size: 20),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFECEFF1),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
