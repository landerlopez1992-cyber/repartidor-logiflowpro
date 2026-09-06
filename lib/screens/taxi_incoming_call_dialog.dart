import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../navigation/repartidor_navigator.dart';
import '../services/taxi_chofer_service.dart';
import '../services/taxi_directions_service.dart';
import 'package:latlong2/latlong.dart';
import '../widgets/taxi_chofer_maplibre.dart';
import '../services/taxi_llamada_persistente_service.dart';
import '../widgets/taxi_cash_comision_aviso_modal.dart';
import '../widgets/taxi_itinerario_chofer_panel.dart';
import 'taxi_navegacion_chofer_screen.dart';

/// Modal estilo “llamada entrante” persistente (Uber).
/// Ringtone / notificación ongoing: [TaxiLlamadaPersistenteService].
class TaxiIncomingCallDialog extends StatefulWidget {
  const TaxiIncomingCallDialog({
    super.key,
    required this.solicitudId,
  });

  final String solicitudId;

  static String? _solicitudMostrada;

  /// Pantalla de llamada. No se cierra al tocar fuera ni con atrás.
  ///
  /// Si el viaje ya no es oferta entrante (p. ej. recordatorio de
  /// `reserva_confirmada`), no abre el modal ni el ringtone — evita el
  /// parpadeo de aceptar/cerrar en bucle.
  static Future<bool?> show(BuildContext context, String solicitudId) async {
    final id = solicitudId.trim();
    if (id.isEmpty) return null;
    if (_solicitudMostrada == id) return null;
    _solicitudMostrada = id;

    try {
      final o = await TaxiChoferService.instance.detalleOferta(id);
      if (o == null ||
          !_TaxiIncomingCallDialogState.esOfertaEntranteValida(o.estado)) {
        if (_solicitudMostrada == id) _solicitudMostrada = null;
        return null;
      }
    } catch (_) {
      // Sin red: igual mostrar; el dialog reintentará cargar.
    }

    unawaited(
      TaxiLlamadaPersistenteService.instance.iniciar(
        solicitudId: id,
        titulo: 'Viaje de taxi entrante',
        mensaje:
            'Tienes una solicitud de viaje. Acepta o rechaza para continuar.',
      ),
    );

    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) =>
          TaxiIncomingCallDialog(solicitudId: id),
    ).whenComplete(() {
      if (_solicitudMostrada == id) _solicitudMostrada = null;
    });
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
  Timer? _pollUi;
  List<LatLng> _rutaOverview = const [];
  String? _viajeEtaLabel;

  /// Oferta aún disponible para aceptar/rechazar (inmediato o reserva futura).
  static bool esOfertaEntranteValida(String raw) {
    final e = raw.trim().toLowerCase();
    return e == 'buscando_chofer' ||
        e == 'reserva_pendiente_chofer' ||
        e == 'reserva_reasignando';
  }

  /// Oferta aún disponible para aceptar/rechazar (inmediato o reserva futura).
  static bool _estadoOfertaEntranteValido(String raw) =>
      esOfertaEntranteValida(raw);

  /// Ya asignado a un chofer (viaje en curso o reserva tomada).
  static bool _estadoViajeAsignado(String raw) {
    final e = raw.trim().toLowerCase();
    return e == 'aceptado' ||
        e == 'en_camino' ||
        e == 'en_viaje' ||
        e == 'reserva_confirmada';
  }

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _cargar();
    _pollUi =
        Timer.periodic(const Duration(seconds: 4), (_) => _cargarSilencioso());
  }

  Future<void> _cerrarViajePerdido(String motivo) async {
    if (!mounted) return;
    final msg = motivo == 'cancelado_pasajero'
        ? 'El pasajero canceló este viaje.'
        : motivo == 'ya_no_disponible'
            ? 'Este viaje ya no está disponible.'
            : 'Otro socio ya tomó este viaje.';
    // Aviso antes de cerrar (detener hace pop del modal).
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF37474F),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
    await TaxiLlamadaPersistenteService.instance.detener(
      motivo: motivo,
      resultado: false,
    );
  }

  Future<TaxiOfertaChofer> _conRating(TaxiOfertaChofer o) async {
    final r = await TaxiChoferService.instance
        .pasajeroRatingPorSolicitud(o.id);
    return o.copyWith(pasajeroRating: r.rating, pasajeroReviews: r.reviews);
  }

  Future<void> _cargarSilencioso() async {
    if (_busy || !mounted) return;
    try {
      final o =
          await TaxiChoferService.instance.detalleOferta(widget.solicitudId);
      if (!mounted) return;
      if (o == null) {
        await _cerrarViajePerdido('ya_no_disponible');
        return;
      }
      final est = o.estado.toLowerCase();
      if (_estadoViajeAsignado(est)) {
        final activo = await TaxiChoferService.instance.viajeActivo();
        if (!mounted) return;
        final mio = activo != null &&
            activo.id.trim() == widget.solicitudId.trim();
        if (mio) {
          await TaxiLlamadaPersistenteService.instance.detener(
            motivo: 'viaje_en_curso',
            resultado: true,
          );
          return;
        }
        await _cerrarViajePerdido('tomado_por_otro');
        return;
      }
      if (est == 'cancelado' || !_estadoOfertaEntranteValido(est)) {
        await _cerrarViajePerdido(
          est == 'cancelado' ? 'cancelado_pasajero' : 'tomado_por_otro',
        );
        return;
      }
      final conR = await _conRating(o);
      if (!mounted) return;
      setState(() => _oferta = conR);
    } catch (_) {}
  }


  Future<void> _cargarRutaOverview(TaxiOfertaChofer o) async {
    try {
      final origen = LatLng(o.origenLat, o.origenLng);
      final destino = LatLng(o.destinoLat, o.destinoLng);
      final paradas = o.paradasLatLng;
      final r = await TaxiDirectionsService.instance.rutaItinerario(
        origen: origen,
        destino: destino,
        paradas: paradas,
      );
      if (!mounted) return;
      setState(() {
        _rutaOverview = r.points.length >= 2
            ? r.points
            : [origen, ...paradas, destino];
        final t = TaxiDirectionsService.formatDuracionCorta(r.durationS);
        _viajeEtaLabel = t.isEmpty ? null : t;
      });
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
      if (o == null || !_estadoOfertaEntranteValido(o.estado)) {
        setState(() {
          _loading = false;
          _error = 'Este viaje ya no está disponible.';
        });
        await TaxiLlamadaPersistenteService.instance.detener(
          motivo: 'ya_no_disponible',
          resultado: false,
        );
        return;
      }
      final conR = await _conRating(o);
      if (!mounted) return;
      setState(() {
        _oferta = conR;
        _loading = false;
      });
      unawaited(_cargarRutaOverview(conR));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudo cargar el detalle del viaje. Inténtalo de nuevo.';
      });
    }
  }

  Future<void> _aceptar() async {
    if (_busy) return;
    final ofertaActual = _oferta;
    if (ofertaActual != null && ofertaActual.esPagoCash) {
      final m = ofertaActual.montosCash;
      final okCash = await TaxiCashComisionAvisoModal.show(
        context,
        totalViajeUsd: m.cobrarClienteUsd,
        comisionUsd: m.empresaUsd,
        topeDeudaUsd: ofertaActual.topeDeudaUsd,
        comisionPct: ofertaActual.comisionPct,
        gananciaChoferUsd: m.quedaChoferUsd,
        tituloAccion: 'Aceptar viaje',
      );
      if (okCash != true || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      final res = await TaxiChoferService.instance.aceptar(widget.solicitudId);
      if (!mounted) return;
      if (!res.ok || res.oferta == null) {
        setState(() => _busy = false);
        final msg = TaxiChoferService.mensajeErrorUsuario(res.err);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.error,
          ),
        );
        final low = (res.err ?? msg).toLowerCase();
        if (low.contains('ya_tomado') ||
            low.contains('otro socio') ||
            low.contains('no está disponible') ||
            low.contains('ya_rechazado') ||
            low.contains('ya aceptó')) {
          await TaxiLlamadaPersistenteService.instance.onRechazadoDesdeUi();
          if (mounted) Navigator.of(context).pop(false);
        }
        return;
      }
      await TaxiLlamadaPersistenteService.instance.onAceptadoDesdeUi();
      if (!mounted) return;
      final oferta = res.oferta!;
      Navigator.of(context).pop(true);

      // Reserva futura: no abrir navegación GPS; queda en pestaña Viajes.
      if (oferta.esReserva ||
          oferta.estado.trim().toLowerCase() == 'reserva_confirmada') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Reserva confirmada. La verás en Viajes cuando llegue el día.',
            ),
            backgroundColor: Color(0xFF37474F),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      final rootNav = RepartidorNavigator.state;
      if (rootNav != null) {
        await rootNav.push(
          MaterialPageRoute<void>(
            builder: (_) => TaxiNavegacionChoferScreen(oferta: oferta),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo aceptar el viaje. Inténtalo de nuevo.'),
          backgroundColor: AppColors.error,
        ),
      );
    }
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
            'Si no puedes atender este viaje ahora, puedes rechazarlo.\n\n'
            'Importante: ignorar o rechazar viajes afecta la salud de tu cuenta. '
            'Con 5 viajes ignorados en el mes tu cuenta se suspende hasta que '
            'la empresa la reactive.',
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
    final res = await TaxiChoferService.instance.rechazar(widget.solicitudId);
    if (!mounted) return;
    if (!res.ok) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(TaxiChoferService.mensajeErrorUsuario(res.err)),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    await TaxiLlamadaPersistenteService.instance.onRechazadoDesdeUi();
    if (!mounted) return;
    Navigator.of(context).pop(false);
  }

  @override
  void dispose() {
    _pollUi?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return PopScope(
      canPop: false,
      child: Material(
        color: const Color(0xFF12151C),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 420,
                maxHeight: size.height * 0.96,
              ),
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E232E),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
                                onPressed: () async {
                                  await TaxiLlamadaPersistenteService.instance
                                      .detener(
                                    motivo: 'ya_no_disponible',
                                    resultado: false,
                                  );
                                  if (context.mounted) {
                                    Navigator.pop(context, false);
                                  }
                                },
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
      ),
    );
  }

  Widget _buildBody(TaxiOfertaChofer o) {
    final distA = o.distanciaAlOrigenKm;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (_, __) {
                    final t = _pulse.value;
                    return Icon(
                      Icons.local_taxi_rounded,
                      size: 36,
                      color: Color.lerp(
                        const Color(0xFFFF9800),
                        const Color(0xFFFFB74D),
                        t,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                const Text(
                  'Nueva solicitud de viaje',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFFF9800),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                if (o.estado.startsWith('reserva_') ||
                    o.rutaFase == 'reserva') ...[
                  const SizedBox(height: 6),
                  const Text(
                    'VIAJE CON RESERVA — acepta y se confirma la cita. '
                    'El saldo se acredita solo al completar el trayecto.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFECEFF1),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                const Text(
                  'Revisa el trayecto y responde',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  o.pasajeroNombre,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFECEFF1),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded,
                        color: Color(0xFFFF9800), size: 18),
                    const SizedBox(width: 4),
                    Text(
                      o.pasajeroReviews > 0
                          ? '${o.pasajeroRating.toStringAsFixed(1)} · ${o.pasajeroReviews} valoraciones'
                          : 'Pasajero nuevo',
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                if (o.esPagoCash) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Text(
                      'Pago en efectivo',
                      style: TextStyle(
                        color: Color(0xFF4CAF50),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                if (o.esCompartido || o.tieneParadas) ...[
                  TaxiOfertaTipoBanner(oferta: o),
                  const SizedBox(height: 10),
                ],
                if (o.esPagoCash) ...[
                  Builder(
                    builder: (_) {
                      final m = o.montosCash;
                      return _cashMontosCompactos(
                        cobrar: m.cobrarClienteUsd,
                        queda: m.quedaChoferUsd,
                        empresa: m.empresaUsd,
                      );
                    },
                  ),
                ] else ...[
                  _infoCard(
                    icon: Icons.payments_outlined,
                    label: 'Tu ganancia',
                    value: '\$${o.gananciaUsd.toStringAsFixed(2)} USD',
                    highlight: true,
                  ),
                  const SizedBox(height: 8),
                  _infoCard(
                    icon: Icons.account_balance_wallet_outlined,
                    label: 'Método de pago',
                    value: 'Por la empresa',
                  ),
                ],
                const SizedBox(height: 8),
                _infoCard(
                  icon: Icons.route_outlined,
                  label: o.esCompartido
                      ? 'Trayecto compartido (aprox.)'
                      : (o.tieneParadas
                          ? 'Trayecto A → paradas → B'
                          : 'Trayecto A → B'),
                  value:
                      '${o.distanciaKm.toStringAsFixed(2)} km · ${o.distanciaMi.toStringAsFixed(2)} mi'
                      '${_viajeEtaLabel != null ? ' · $_viajeEtaLabel' : ''}'
                      '${o.ofertaTipoEtiqueta != '—' ? ' · ${o.ofertaTipoEtiqueta}' : ''}',
                ),
                if (distA != null) ...[
                  const SizedBox(height: 8),
                  _infoCard(
                    icon: Icons.near_me_outlined,
                    label: 'Hasta la primera recogida',
                    value: '${distA.toStringAsFixed(2)} km desde tu ubicación',
                  ),
                ],
                const SizedBox(height: 10),
                if (_rutaOverview.length >= 2) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 150,
                      width: double.infinity,
                      child: TaxiChoferMapLibre(
                        driver: null,
                        pickup: LatLng(o.origenLat, o.origenLng),
                        destination: LatLng(o.destinoLat, o.destinoLng),
                        showDestination: true,
                        stops: o.paradasLatLng,
                        overviewPoints: _rutaOverview,
                        routePoints: _rutaOverview,
                        totalTripEtaLabel: _viajeEtaLabel,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                TaxiItinerarioChoferPanel(
                  oferta: o,
                  compact: true,
                  dark: true,
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
                  textAlign: TextAlign.center,
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
                        textAlign: TextAlign.center,
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _cashMontosCompactos({
    required double cobrar,
    required double queda,
    required double empresa,
  }) {
    Widget fila(String label, double monto, Color color) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Text(
              '\$${monto.toStringAsFixed(2)}',
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF252A35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF4CAF50).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.payments_rounded, color: Color(0xFF4CAF50), size: 16),
              SizedBox(width: 6),
              Text(
                'Pago en efectivo',
                style: TextStyle(
                  color: Color(0xFF4CAF50),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          fila('Cobrar al cliente', cobrar, const Color(0xFF4CAF50)),
          fila('Tu ganancia', queda, const Color(0xFFECEFF1)),
          fila('Comisión de la empresa', empresa, const Color(0xFFFF9800)),
        ],
      ),
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String label,
    required String value,
    bool highlight = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF252A35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF9CA3AF)),
          const SizedBox(height: 8),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: highlight
                  ? const Color(0xFF4CAF50)
                  : const Color(0xFFECEFF1),
              fontSize: highlight ? 18 : 14,
              fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
