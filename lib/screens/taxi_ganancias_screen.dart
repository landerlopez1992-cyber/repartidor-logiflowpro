import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_colors.dart';
import '../services/taxi_chofer_service.dart';

/// Dashboard simple de ganancias del socio (hoy / semana / deuda / fianza).
class TaxiGananciasScreen extends StatefulWidget {
  const TaxiGananciasScreen({super.key});

  @override
  State<TaxiGananciasScreen> createState() => _TaxiGananciasScreenState();
}

class _TaxiGananciasScreenState extends State<TaxiGananciasScreen> {
  bool _loading = true;
  TaxiGananciasResumen? _g;
  TaxiDemandaSugerencia? _d;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _loading = true);
    final g = await TaxiChoferService.instance.gananciasResumen();
    final d = await TaxiChoferService.instance.demandaSugerencia();
    if (!mounted) return;
    setState(() {
      _g = g;
      _d = d;
      _loading = false;
    });
  }

  Widget _card(String title, String value, {Color? accent}) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: accent ?? const Color(0xFFECEFF1),
              fontWeight: FontWeight.w800,
              fontSize: 22,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = _g;
    final d = _d;
    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: AppColors.header,
        title: const Text('Mis ganancias'),
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (g == null)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Text(
                  'No se pudieron cargar las ganancias.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF9CA3AF)),
                ),
              )
            else ...[
              if (d != null && d.mensaje.isNotEmpty) ...[
                Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: d.altaDemanda
                        ? const Color(0xFFFFF3E0)
                        : AppColors.darkElevated,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    d.mensaje,
                    style: TextStyle(
                      color: d.altaDemanda
                          ? const Color(0xFF2C2C2C)
                          : const Color(0xFFECEFF1),
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Center(child: _card('Hoy', '\$${g.gananciaHoy.toStringAsFixed(2)}', accent: const Color(0xFF4CAF50))),
              const SizedBox(height: 10),
              Center(child: _card('Esta semana', '\$${g.gananciaSemana.toStringAsFixed(2)}')),
              const SizedBox(height: 10),
              Center(
                child: _card(
                  'Viajes',
                  '${g.viajesHoy} hoy · ${g.viajesSemana} semana',
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: _card(
                  'Propinas (semana)',
                  '\$${g.propinasSemana.toStringAsFixed(2)}',
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: _card(
                  'Comisión pendiente',
                  '\$${g.comisionPendiente.toStringAsFixed(2)}',
                  accent: g.comisionPendiente > 0
                      ? const Color(0xFFFF9800)
                      : null,
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: _card(
                  'Fianza',
                  '\$${g.fianza.toStringAsFixed(2)}',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Abre Waze o Google Maps hacia lat/lng.
Future<void> abrirNavegacionExterna({
  required BuildContext context,
  required double lat,
  required double lng,
  required String etiqueta,
}) async {
  final gmaps = Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
  );
  final waze = Uri.parse('https://waze.com/ul?ll=$lat,$lng&navigate=yes');
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.darkSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Navegar a $etiqueta',
              style: const TextStyle(
                color: Color(0xFFECEFF1),
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.map, color: Color(0xFF9CA3AF)),
              title: const Text(
                'Google Maps',
                style: TextStyle(color: Color(0xFFECEFF1)),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await launchUrl(gmaps, mode: LaunchMode.externalApplication);
              },
            ),
            ListTile(
              leading: const Icon(Icons.navigation, color: Color(0xFF9CA3AF)),
              title: const Text(
                'Waze',
                style: TextStyle(color: Color(0xFFECEFF1)),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await launchUrl(waze, mode: LaunchMode.externalApplication);
              },
            ),
          ],
        ),
      ),
    ),
  );
}
