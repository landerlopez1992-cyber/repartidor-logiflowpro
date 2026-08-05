import 'package:flutter/material.dart';

import '../services/taxi_chofer_service.dart';

/// Panel profesional del itinerario (paradas + viaje compartido).
class TaxiItinerarioChoferPanel extends StatelessWidget {
  const TaxiItinerarioChoferPanel({
    super.key,
    required this.oferta,
    this.legs,
    this.activoOrden,
    this.compact = false,
    this.dark = true,
  });

  final TaxiOfertaChofer oferta;
  /// Si se pasa, se usa este orden (p. ej. destinos reordenados por ruta).
  final List<TaxiItinerarioStop>? legs;
  final int? activoOrden;
  final bool compact;
  final bool dark;

  Color get _card =>
      dark ? const Color(0xFF252A35) : const Color(0xFFF5F5F5);
  Color get _border =>
      dark ? Colors.white.withValues(alpha: 0.10) : const Color(0xFFE5E7EB);
  Color get _title =>
      dark ? const Color(0xFFECEFF1) : const Color(0xFF2C2C2C);
  Color get _sub =>
      dark ? const Color(0xFF9CA3AF) : const Color(0xFF666666);

  @override
  Widget build(BuildContext context) {
    final stops = legs ?? oferta.itinerario;
    if (stops.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 14,
        compact ? 12 : 14,
        compact ? 12 : 14,
        compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.alt_route_rounded, size: 18, color: _sub),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Itinerario del viaje',
                  style: TextStyle(
                    color: _title,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (oferta.esCompartido)
                _chip(
                  'Compartido · ${oferta.pasajeros} pasajeros',
                  const Color(0xFF1565C0),
                  const Color(0xFFE3F2FD),
                ),
              if (oferta.tieneParadas)
                _chip(
                  '${oferta.paradasCount} parada${oferta.paradasCount == 1 ? '' : 's'}',
                  const Color(0xFFE65100),
                  const Color(0xFFFFF3E0),
                ),
              _chip(
                '${stops.length} tramos',
                _sub,
                dark
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0xFFEEEEEE),
              ),
            ],
          ),
          if (oferta.esCompartido) ...[
            const SizedBox(height: 8),
            Text(
              'Orden: recoges a cada pasajero y luego bajas en el destino '
              'que quede primero en tu ruta (pueden ser distintos).',
              style: TextStyle(
                color: _sub,
                fontSize: 11,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 12),
          ...List.generate(stops.length, (i) {
            final s = stops[i];
            final activo = activoOrden != null &&
                (s.orden == activoOrden || i == activoOrden);
            return _stopRow(
              s,
              isLast: i == stops.length - 1,
              activo: activo,
              hecho: activoOrden != null && i < (activoOrden ?? 0),
            );
          }),
        ],
      ),
    );
  }

  Widget _chip(String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Color _dotColor(TaxiItinerarioStop s) {
    if (s.esRecogida) return const Color(0xFF4CAF50);
    if (s.esParada) return const Color(0xFFFF9800);
    return const Color(0xFFDC2626);
  }

  IconData _dotIcon(TaxiItinerarioStop s) {
    if (s.esRecogida) return Icons.trip_origin;
    if (s.esParada) return Icons.add_location_alt_outlined;
    return Icons.flag;
  }

  Widget _stopRow(
    TaxiItinerarioStop s, {
    required bool isLast,
    required bool activo,
    required bool hecho,
  }) {
    final dot = hecho
        ? const Color(0xFF9CA3AF)
        : (activo ? const Color(0xFFFF9800) : _dotColor(s));
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Container(
        padding: activo
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 6)
            : EdgeInsets.zero,
        decoration: activo
            ? BoxDecoration(
                color: const Color(0xFFFF9800).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.35),
                ),
              )
            : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              child: Column(
                children: [
                  Icon(
                    hecho ? Icons.check_circle : _dotIcon(s),
                    size: 18,
                    color: dot,
                  ),
                  if (!isLast)
                    ...List.generate(
                      3,
                      (_) => Container(
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        width: 2,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _sub.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activo ? 'AHORA · ${s.etiqueta}' : s.etiqueta,
                    style: TextStyle(
                      color: activo ? const Color(0xFFFF9800) : _sub,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.texto.trim().isEmpty ? '—' : s.texto.trim(),
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _title,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      decoration: hecho ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if ((s.pasajero ?? '').trim().isNotEmpty &&
                      (s.esRecogida || s.esDestino)) ...[
                    const SizedBox(height: 2),
                    Text(
                      s.pasajero!.trim(),
                      style: TextStyle(
                        color: _sub,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner resumen (compartido / paradas).
class TaxiOfertaTipoBanner extends StatelessWidget {
  const TaxiOfertaTipoBanner({super.key, required this.oferta});

  final TaxiOfertaChofer oferta;

  @override
  Widget build(BuildContext context) {
    if (!oferta.esCompartido && !oferta.tieneParadas) {
      return const SizedBox.shrink();
    }
    final parts = <String>[];
    if (oferta.esCompartido) {
      parts.add(
        'Viaje compartido · ${oferta.pasajeros} pasajeros\n'
        '1) Recoges a cada uno  2) Bajas en el destino más cercano en ruta '
        '(pueden ser direcciones distintas)',
      );
    }
    if (oferta.tieneParadas) {
      parts.add(
        'Hay ${oferta.paradasCount} parada'
        '${oferta.paradasCount == 1 ? '' : 's'} intermedia'
        '${oferta.paradasCount == 1 ? '' : 's'} en el trayecto',
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF90CAF9)),
      ),
      child: Text(
        parts.join('\n\n'),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF1565C0),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}
