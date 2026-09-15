import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/taxi_chofer_service.dart';
import '../services/taxi_chofer_ui_bridge.dart';
import '../services/taxi_reserva_reminder_chofer_service.dart';
import 'volonex_dialog.dart';

/// Tarjetas de reservas confirmadas (esperando el día) en pestaña Viajes.
class TaxiReservasChoferPanel extends StatefulWidget {
  const TaxiReservasChoferPanel({super.key});

  @override
  State<TaxiReservasChoferPanel> createState() =>
      _TaxiReservasChoferPanelState();
}

class _TaxiReservasChoferPanelState extends State<TaxiReservasChoferPanel> {
  List<TaxiReservaChoferItem> _items = const [];
  bool _loading = true;
  bool _fromCache = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    TaxiChoferUiBridge.reservasRefreshTick.addListener(_onRefreshTick);
    _cargar();
  }

  @override
  void dispose() {
    TaxiChoferUiBridge.reservasRefreshTick.removeListener(_onRefreshTick);
    super.dispose();
  }

  void _onRefreshTick() {
    if (mounted) _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _fromCache = false;
    });
    final res = await TaxiChoferService.instance.listarReservasConfirmadas();
    if (!mounted) return;
    if (res.error != null && res.items.isEmpty) {
      final cached = await TaxiReservaReminderChoferService.instance.loadCache();
      final items = cached
          .map(TaxiReservaChoferItem.fromJson)
          .where((e) => e.id.isNotEmpty)
          .toList();
      await TaxiReservaReminderChoferService.instance.rescheduleFromCache();
      if (!mounted) return;
      setState(() {
        _items = items;
        _fromCache = items.isNotEmpty;
        _loading = false;
      });
      return;
    }
    await TaxiReservaReminderChoferService.instance.syncFromReservas(
      res.items
          .map(
            (e) => {
              'id': e.id,
              'estado': e.estado,
              'programado_en': e.programadoEn?.toUtc().toIso8601String(),
              'origen_texto': e.origenTexto,
              'destino_texto': e.destinoTexto,
              'pasajero_nombre_snap': e.pasajeroNombre,
            },
          )
          .toList(),
    );
    if (!mounted) return;
    setState(() {
      _items = res.items;
      _loading = false;
    });
  }

  String _fmt(DateTime? d) {
    if (d == null) return '—';
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year} · '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  String _resto(DateTime? p) {
    if (p == null) return '';
    final local = p.toLocal();
    final now = DateTime.now();
    final hoy = DateTime(now.year, now.month, now.day);
    final dia = DateTime(local.year, local.month, local.day);
    final d = dia.difference(hoy).inDays;
    if (d < 0) return 'Fecha pasada';
    if (d == 0) return 'Hoy';
    if (d == 1) return 'Mañana';
    return 'En $d días';
  }

  Future<void> _liberar(TaxiReservaChoferItem r) async {
    if (_busy) return;
    final ok = await showVolonexConfirmDialog(
      context,
      title: 'Cancelar esta reserva',
      message:
          'Se liberará tu cita y se buscará otro conductor. '
          'El pasajero mantiene su reserva. ¿Continuar?',
      confirmLabel: 'Sí, cancelar mi cita',
      confirmColor: const Color(0xFFDC2626),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final res = await TaxiChoferService.instance.cancelarViajeChofer(r.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.ok) {
      await TaxiReservaReminderChoferService.instance.cancelReserva(r.id);
      await _cargar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reserva liberada. Ya no estás asignado a ese viaje.'),
          backgroundColor: Color(0xFF37474F),
        ),
      );
    } else {
      await showVolonexMessageDialog(
        context,
        title: 'No se pudo cancelar',
        message: res.err ?? 'Intenta de nuevo.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF9CA3AF),
            ),
          ),
        ),
      );
    }
    if (_items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF252A35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.event_note, color: Color(0xFFFF9800), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Mis reservas (${_items.length})',
                    style: const TextStyle(
                      color: Color(0xFFECEFF1),
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Actualizar',
                  onPressed: _busy ? null : _cargar,
                  icon: const Icon(Icons.refresh, color: Color(0xFF9CA3AF), size: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Viajes que ya aceptaste para otra fecha. Aquí puedes verlos o cancelar tu cita.',
            style: TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          if (_fromCache)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF37474F),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Mostrando reservas guardadas en el teléfono (sin red).',
                style: TextStyle(
                  color: Color(0xFFECEFF1),
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ),
          ..._items.map((r) {
            final resto = _resto(r.programadoEn);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.darkElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.45),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.event_available,
                          color: Color(0xFF4CAF50), size: 22),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Reserva confirmada',
                          style: TextStyle(
                            color: Color(0xFFECEFF1),
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (resto.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: resto == 'Hoy'
                                ? const Color(0xFF4CAF50).withValues(alpha: 0.2)
                                : const Color(0xFFFF9800).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            resto,
                            style: TextStyle(
                              color: resto == 'Hoy'
                                  ? const Color(0xFF4CAF50)
                                  : const Color(0xFFFF9800),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _fmt(r.programadoEn),
                    style: const TextStyle(
                      color: Color(0xFFFF9800),
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                    ),
                  ),
                  if (r.precioUsd > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Ganas ~\$${r.precioUsd.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Color(0xFF4CAF50),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    r.pasajeroNombre.isEmpty ? 'Pasajero' : r.pasajeroNombre,
                    style: const TextStyle(
                      color: Color(0xFFECEFF1),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Salida: ${r.origenTexto}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                  Text(
                    'Destino: ${r.destinoTexto}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _busy ? null : () => _liberar(r),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      child: const Text(
                        'Cancelar mi reserva',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
