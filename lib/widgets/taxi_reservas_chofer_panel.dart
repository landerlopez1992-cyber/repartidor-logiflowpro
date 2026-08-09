import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/taxi_chofer_service.dart';
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
    _cargar();
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
    if (d == 0) return 'Hoy es el día';
    if (d == 1) return 'Falta 1 día';
    return 'Faltan $d días';
  }

  Future<void> _liberar(TaxiReservaChoferItem r) async {
    if (_busy) return;
    final ok = await showVolonexConfirmDialog(
      context,
      title: 'Liberar reserva',
      message:
          'Se buscará otro conductor. El pasajero mantiene la reserva. ¿Continuar?',
      confirmLabel: 'Liberar',
      confirmColor: const Color(0xFFDC2626),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    final res =
        await TaxiChoferService.instance.cancelarViajeChofer(r.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res.ok) {
      await TaxiReservaReminderChoferService.instance.cancelReserva(r.id);
      await _cargar();
    } else {
      await showVolonexMessageDialog(
        context,
        title: 'No se pudo liberar',
        message: res.err ?? 'Intenta de nuevo.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty) {
      return const SizedBox.shrink();
    }
    if (_items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_fromCache)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF37474F),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Reservas guardadas en el teléfono. Los avisos del día se programan en el dispositivo.',
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
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.darkElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.event_available,
                          color: Color(0xFF4CAF50), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Reserva lista · esperando el día',
                          style: const TextStyle(
                            color: Color(0xFFECEFF1),
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (resto.isNotEmpty)
                        Text(
                          resto,
                          style: TextStyle(
                            color: resto.startsWith('Hoy')
                                ? const Color(0xFF4CAF50)
                                : const Color(0xFFFF9800),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _fmt(r.programadoEn),
                    style: const TextStyle(
                      color: Color(0xFFFF9800),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    r.pasajeroNombre.isEmpty
                        ? 'Pasajero'
                        : r.pasajeroNombre,
                    style: const TextStyle(
                      color: Color(0xFFECEFF1),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    r.origenTexto,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '→ ${r.destinoTexto}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _busy ? null : () => _liberar(r),
                      child: const Text(
                        'Liberar reserva',
                        style: TextStyle(
                          color: Color(0xFFDC2626),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
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
