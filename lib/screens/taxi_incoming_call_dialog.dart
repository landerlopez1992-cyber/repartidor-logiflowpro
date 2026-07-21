import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vibration/vibration.dart';

import '../config/app_colors.dart';
import '../services/taxi_chofer_service.dart';

/// Modal estilo “llamada entrante” con el detalle completo del viaje.
class TaxiIncomingCallDialog extends StatefulWidget {
  const TaxiIncomingCallDialog({
    super.key,
    required this.solicitudId,
  });

  final String solicitudId;

  /// Muestra el modal. Devuelve true si aceptó.
  static Future<bool?> show(BuildContext context, String solicitudId) {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) =>
          TaxiIncomingCallDialog(solicitudId: solicitudId),
    );
  }

  @override
  State<TaxiIncomingCallDialog> createState() => _TaxiIncomingCallDialogState();
}

class _TaxiIncomingCallDialogState extends State<TaxiIncomingCallDialog>
    with SingleTickerProviderStateMixin {
  TaxiOfertaChofer? _oferta;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  late final AnimationController _pulse;
  final AudioPlayer _player = AudioPlayer();
  Timer? _vibTimer;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _cargar();
    _iniciarSonido();
  }

  Future<void> _iniciarSonido() async {
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('sounds/taxi_incoming.mp3'));
    } catch (_) {}
    _vibTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        if (await Vibration.hasVibrator() == true) {
          Vibration.vibrate(duration: 450);
        }
      } catch (_) {}
    });
  }

  Future<void> _detenerAlertas() async {
    _vibTimer?.cancel();
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final o =
          await TaxiChoferService.instance.detalleOferta(widget.solicitudId);
      if (!mounted) return;
      if (o == null || o.estado != 'buscando_chofer') {
        setState(() {
          _loading = false;
          _error = 'Este viaje ya no está disponible.';
        });
        return;
      }
      setState(() {
        _oferta = o;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _aceptar() async {
    if (_busy) return;
    setState(() => _busy = true);
    await _detenerAlertas();
    final res = await TaxiChoferService.instance.aceptar(widget.solicitudId);
    if (!mounted) return;
    if (!res.ok || res.oferta == null) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.err ?? 'No se pudo aceptar'),
          backgroundColor: AppColors.error,
        ),
      );
      if ((res.err ?? '').contains('ya_tomado') ||
          (res.err ?? '').contains('Otro socio')) {
        Navigator.of(context).pop(false);
      }
      return;
    }
    Navigator.of(context).pop(true);
  }

  Future<void> _rechazar() async {
    if (_busy) return;

    final confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E232E),
        constraints: const BoxConstraints(maxWidth: 400),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '¿Rechazar este viaje?',
          style: TextStyle(
            color: Color(0xFFECEFF1),
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        content: const SingleChildScrollView(
          child: Text(
            'Puedes rechazar este viaje si no puedes tomarlo ahora.\n\n'
            'Importante: mientras más viajes rechaces, mayor es el riesgo de '
            'una suspensión de tu cuenta por rechazos o cancelaciones reiteradas.',
            style: TextStyle(
              color: Color(0xFF9CA3AF),
              height: 1.4,
              fontSize: 14,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Volver',
              style: TextStyle(color: Color(0xFF9CA3AF)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sí, rechazar',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmar != true || !mounted) return;

    setState(() => _busy = true);
    await _detenerAlertas();
    await TaxiChoferService.instance.rechazar(widget.solicitudId);
    if (!mounted) return;
    Navigator.of(context).pop(false);
  }

  Future<void> _llamar(String telefono) async {
    final t = telefono.trim();
    if (t.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: t.replaceAll(RegExp(r'[^\d+]'), ''));
    try {
      await launchUrl(uri);
    } catch (_) {}
  }

  String _fmtHora(DateTime? d) {
    if (d == null) return '—';
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm · ${d.day}/${d.month}/${d.year}';
  }

  @override
  void dispose() {
    _vibTimer?.cancel();
    _pulse.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.92;
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 400, maxHeight: maxH),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E232E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFFF9800),
                        ),
                      ),
                    )
                  : _error != null
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Color(0xFFECEFF1)),
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text(
                                'Cerrar',
                                style: TextStyle(color: Color(0xFF9CA3AF)),
                              ),
                            ),
                          ],
                        )
                      : _buildBody(_oferta!),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(TaxiOfertaChofer o) {
    final foto = o.pasajeroFotoUrl?.trim();
    final zona = o.zonaOrigen;
    final distA = o.distanciaAlOrigenKm;
    final tel = o.pasajeroTelefono.trim();
    final solicitanteDistinto = !o.paraMi &&
        o.solicitanteNombre.trim().isNotEmpty &&
        o.solicitanteNombre.trim().toLowerCase() !=
            o.pasajeroNombre.trim().toLowerCase();

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    final t = _pulse.value;
                    return Container(
                      padding: EdgeInsets.all(4 + t * 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF4CAF50)
                              .withValues(alpha: 0.35 + t * 0.4),
                          width: 2,
                        ),
                      ),
                      child: CircleAvatar(
                        radius: 36,
                        backgroundColor: const Color(0xFF37474F),
                        backgroundImage: (foto != null && foto.startsWith('http'))
                            ? NetworkImage(foto)
                            : null,
                        child: (foto == null || !foto.startsWith('http'))
                            ? const Icon(Icons.person,
                                color: Colors.white, size: 36)
                            : null,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                const Text(
                  'Viaje de taxi entrante',
                  style: TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  o.pasajeroNombre,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFECEFF1),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF252A35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    o.paraMi
                        ? 'Viaje para el cliente'
                        : 'Pasajero distinto al solicitante',
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _infoCard(
                  icon: Icons.groups,
                  label: 'Pasajeros en este viaje',
                  value: o.pasajeros == 1
                      ? '1 persona (tu auto admite hasta ${o.capacidadChofer})'
                      : '${o.pasajeros} personas (tu auto admite hasta ${o.capacidadChofer})',
                  highlight: true,
                ),
                const SizedBox(height: 8),
                _infoCard(
                  icon: Icons.attach_money,
                  label: 'Ganarás',
                  value: '\$${o.gananciaUsd.toStringAsFixed(2)} USD',
                  highlight: true,
                ),
                if (o.precioUsd != null) ...[
                  const SizedBox(height: 8),
                  _infoCard(
                    icon: Icons.receipt_long_outlined,
                    label: 'Precio del viaje (cliente)',
                    value: '\$${o.precioUsd!.toStringAsFixed(2)} USD',
                  ),
                ],
                const SizedBox(height: 8),
                _infoCard(
                  icon: Icons.local_taxi_outlined,
                  label: 'Tipo de oferta',
                  value: o.ofertaTipoEtiqueta,
                ),
                const SizedBox(height: 8),
                _infoCard(
                  icon: Icons.route,
                  label: 'Trayecto A → B',
                  value:
                      '${o.distanciaKm.toStringAsFixed(2)} km · ${o.distanciaMi.toStringAsFixed(2)} mi',
                ),
                if (distA != null) ...[
                  const SizedBox(height: 8),
                  _infoCard(
                    icon: Icons.near_me,
                    label: 'Distancia hasta el punto de recogida',
                    value: '${distA.toStringAsFixed(2)} km desde tu ubicación',
                  ),
                ],
                const SizedBox(height: 8),
                _infoCard(
                  icon: Icons.trip_origin,
                  label: 'Recoger en (punto A)',
                  value: o.origenTexto.isEmpty ? '—' : o.origenTexto,
                ),
                if (zona.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _infoCard(
                    icon: Icons.map_outlined,
                    label: 'Municipio / provincia de origen',
                    value: zona,
                  ),
                ],
                const SizedBox(height: 8),
                _infoCard(
                  icon: Icons.flag,
                  label: 'Destino (punto B)',
                  value: o.destinoTexto.isEmpty ? '—' : o.destinoTexto,
                ),
                const SizedBox(height: 8),
                _infoCard(
                  icon: Icons.phone_outlined,
                  label: 'Teléfono del pasajero',
                  value: tel.isEmpty ? 'No disponible' : tel,
                  trailing: tel.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Llamar',
                          onPressed: () => _llamar(tel),
                          icon: const Icon(
                            Icons.call,
                            color: Color(0xFF4CAF50),
                            size: 20,
                          ),
                        ),
                ),
                if (solicitanteDistinto) ...[
                  const SizedBox(height: 8),
                  _infoCard(
                    icon: Icons.person_outline,
                    label: 'Solicitó el viaje',
                    value: o.solicitanteNombre,
                  ),
                  if (o.solicitanteTelefono.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _infoCard(
                      icon: Icons.phone_iphone_outlined,
                      label: 'Teléfono del solicitante',
                      value: o.solicitanteTelefono.trim(),
                      trailing: IconButton(
                        tooltip: 'Llamar',
                        onPressed: () => _llamar(o.solicitanteTelefono),
                        icon: const Icon(
                          Icons.call,
                          color: Color(0xFF4CAF50),
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 8),
                _infoCard(
                  icon: Icons.schedule,
                  label: 'Solicitado',
                  value: _fmtHora(o.createdAt),
                ),
                const SizedBox(height: 8),
                _infoCard(
                  icon: Icons.pin_drop_outlined,
                  label: 'Coordenadas de recogida',
                  value:
                      '${o.origenLat.toStringAsFixed(5)}, ${o.origenLng.toStringAsFixed(5)}',
                ),
                const SizedBox(height: 8),
                _infoCard(
                  icon: Icons.flag_outlined,
                  label: 'Coordenadas de destino',
                  value:
                      '${o.destinoLat.toStringAsFixed(5)}, ${o.destinoLng.toStringAsFixed(5)}',
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _rechazar,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFDC2626),
                  side: const BorderSide(color: Color(0xFFDC2626)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Rechazar',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _busy ? null : _aceptar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CAF50),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Aceptar',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String label,
    required String value,
    bool highlight = false,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF252A35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF9CA3AF)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: highlight
                        ? const Color(0xFF4CAF50)
                        : const Color(0xFFECEFF1),
                    fontSize: highlight ? 18 : 13,
                    fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}
