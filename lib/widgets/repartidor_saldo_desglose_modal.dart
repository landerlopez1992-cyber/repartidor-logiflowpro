import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/repartidor_historial_pago_service.dart';

/// Abre modal moderno con desglose de créditos (+) y débitos (−) del saldo.
Future<void> showRepartidorSaldoDesgloseModal(
  BuildContext context, {
  required String repartidorId,
  required double saldoActual,
  required String moneda,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _RepartidorSaldoDesgloseSheet(
      repartidorId: repartidorId,
      saldoActual: saldoActual,
      moneda: moneda,
    ),
  );
}

class _RepartidorSaldoDesgloseSheet extends StatefulWidget {
  const _RepartidorSaldoDesgloseSheet({
    required this.repartidorId,
    required this.saldoActual,
    required this.moneda,
  });

  final String repartidorId;
  final double saldoActual;
  final String moneda;

  @override
  State<_RepartidorSaldoDesgloseSheet> createState() =>
      _RepartidorSaldoDesgloseSheetState();
}

class _RepartidorSaldoDesgloseSheetState
    extends State<_RepartidorSaldoDesgloseSheet> {
  bool _cargando = true;
  String? _error;
  List<Map<String, dynamic>> _movimientos = [];
  String _filtro = 'todos'; // todos | credito | debito

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final rows = await RepartidorHistorialPagoService.cargarMovimientosSaldo(
        widget.repartidorId,
      );
      if (!mounted) return;
      setState(() {
        _movimientos = rows;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo cargar el historial.';
        _cargando = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtrados {
    return _movimientos.where((m) {
      final monto = m['monto'];
      final v = monto is num ? monto.toDouble() : double.tryParse('$monto') ?? 0;
      final tipo = m['tipo']?.toString() ?? '';
      final esDeb = RepartidorHistorialPagoService.esDebito(tipo, v);
      if (_filtro == 'credito') return !esDeb;
      if (_filtro == 'debito') return esDeb;
      return true;
    }).toList();
  }

  double get _totalCreditos {
    double s = 0;
    for (final m in _movimientos) {
      final v = m['monto'] is num
          ? (m['monto'] as num).toDouble()
          : double.tryParse('${m['monto']}') ?? 0;
      final tipo = m['tipo']?.toString() ?? '';
      if (!RepartidorHistorialPagoService.esDebito(tipo, v)) {
        s += v.abs();
      }
    }
    return s;
  }

  double get _totalDebitos {
    double s = 0;
    for (final m in _movimientos) {
      final v = m['monto'] is num
          ? (m['monto'] as num).toDouble()
          : double.tryParse('${m['monto']}') ?? 0;
      final tipo = m['tipo']?.toString() ?? '';
      if (RepartidorHistorialPagoService.esDebito(tipo, v)) {
        s += v.abs();
      }
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    final moneda = widget.moneda;

    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        constraints: BoxConstraints(maxWidth: 480, maxHeight: h * 0.88),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.darkBorder.withValues(alpha: 0.7)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _buildHeader(moneda),
            _buildResumen(moneda),
            _buildFiltros(),
            Expanded(child: _buildLista(moneda)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String moneda) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF37474F), Color(0xFF455A64)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF4CAF50), width: 1.2),
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: Color(0xFF4CAF50),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tu saldo',
                  style: TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.saldoActual.toStringAsFixed(2)} $moneda',
                  style: const TextStyle(
                    color: Color(0xFFECEFF1),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Color(0xFFECEFF1)),
          ),
        ],
      ),
    );
  }

  Widget _buildResumen(String moneda) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: _miniStat(
              label: 'Créditos',
              value: '+${_totalCreditos.toStringAsFixed(2)}',
              color: AppColors.exito,
              icon: Icons.arrow_upward_rounded,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _miniStat(
              label: 'Débitos (nómina)',
              value: '-${_totalDebitos.toStringAsFixed(2)}',
              color: AppColors.error,
              icon: Icons.arrow_downward_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.darkElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.darkTextMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltros() {
    Widget chip(String id, String label) {
      final on = _filtro == id;
      return GestureDetector(
        onTap: () => setState(() => _filtro = id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: on ? AppColors.header : AppColors.darkElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: on ? AppColors.header : AppColors.darkBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: on ? AppColors.darkText : AppColors.darkTextMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          chip('todos', 'Todos'),
          const SizedBox(width: 8),
          chip('credito', 'Créditos'),
          const SizedBox(width: 8),
          chip('debito', 'Débitos'),
          const Spacer(),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _cargando ? null : _cargar,
            icon: const Icon(Icons.refresh, color: AppColors.darkTextMuted, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildLista(String moneda) {
    if (_cargando) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF4CAF50)),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.darkTextMuted),
          ),
        ),
      );
    }
    final list = _filtrados;
    if (list.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.receipt_long_outlined,
                  color: AppColors.darkTextMuted, size: 40),
              SizedBox(height: 12),
              Text(
                'Aún no hay movimientos.\nCuando entregues pedidos o solicites nómina, aparecerán aquí.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.darkTextMuted,
                  height: 1.4,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      itemCount: list.length,
      itemBuilder: (_, i) => _MovimientoTile(movimiento: list[i], monedaFallback: moneda),
    );
  }
}

class _MovimientoTile extends StatelessWidget {
  const _MovimientoTile({
    required this.movimiento,
    required this.monedaFallback,
  });

  final Map<String, dynamic> movimiento;
  final String monedaFallback;

  @override
  Widget build(BuildContext context) {
    final montoRaw = movimiento['monto'];
    final monto = montoRaw is num
        ? montoRaw.toDouble()
        : double.tryParse('$montoRaw') ?? 0;
    final tipo = movimiento['tipo']?.toString() ?? '';
    final detalle = movimiento['detalle']?.toString() ?? '';
    final moneda = movimiento['moneda']?.toString() ?? monedaFallback;
    final esDeb = RepartidorHistorialPagoService.esDebito(tipo, monto);
    final titulo =
        RepartidorHistorialPagoService.etiquetaMovimiento(tipo, detalle);
    final fecha = DateTime.tryParse(movimiento['created_at']?.toString() ?? '');
    final fechaTxt = fecha == null
        ? ''
        : '${fecha.day.toString().padLeft(2, '0')}/'
            '${fecha.month.toString().padLeft(2, '0')}/'
            '${fecha.year}';

    final color = esDeb ? AppColors.error : AppColors.exito;
    final signo = esDeb ? '−' : '+';
    final abs = monto.abs();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.darkElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              esDeb
                  ? Icons.remove_circle_outline_rounded
                  : Icons.add_circle_outline_rounded,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: const TextStyle(
                    color: AppColors.darkText,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  esDeb ? 'Débito · Nómina' : 'Crédito · Ganancia',
                  style: TextStyle(
                    color: color.withValues(alpha: 0.9),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (fechaTxt.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    fechaTxt,
                    style: const TextStyle(
                      color: AppColors.darkTextMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$signo\$${abs.toStringAsFixed(2)}',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              Text(
                moneda,
                style: const TextStyle(
                  color: AppColors.darkTextMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
