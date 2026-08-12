import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../services/tenant_fuera_servicio_service.dart';
import '../widgets/repartidor_loading_spinner.dart';
import 'repartidor_mobile_screen.dart';

/// Empresa suspendida / sin pago: bloquea toda la app del repartidor.
class TenantFueraServicioScreen extends StatefulWidget {
  const TenantFueraServicioScreen({
    super.key,
    required this.tenantId,
  });

  final String tenantId;

  @override
  State<TenantFueraServicioScreen> createState() =>
      _TenantFueraServicioScreenState();
}

class _TenantFueraServicioScreenState extends State<TenantFueraServicioScreen> {
  static const _bg = Color(0xFF0A0A0A);
  static const _card = Color(0xFF141414);
  static const _text = Color(0xFFECEFF1);
  static const _muted = Color(0xFF9CA3AF);
  static const _accent = Color(0xFFFF9800);

  Timer? _poll;
  RealtimeChannel? _channel;
  TenantFueraServicioEstado? _estado;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 20), (_) => _refresh());
    _subscribe();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _channel?.unsubscribe();
    super.dispose();
  }

  void _subscribe() {
    _channel = supabase
        .channel('repartidor_fuera_servicio_${widget.tenantId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tenants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.tenantId,
          ),
          callback: (_) {
            TenantFueraServicioService.invalidateCache();
            if (mounted) _refresh();
          },
        )
        .subscribe();
  }

  Future<void> _refresh() async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final e = await TenantFueraServicioService.fetch(
        tenantId: widget.tenantId,
        forceRefresh: true,
      );
      if (!mounted) return;
      if (e != null && !e.bloqueada) {
        _poll?.cancel();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const RepartidorMobileScreen()),
          (_) => false,
        );
        return;
      }
      setState(() => _estado = e);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _abrirEmail(String email) async {
    try {
      await launchUrl(Uri(scheme: 'mailto', path: email));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final nombre = _estado?.nombreEmpresa.trim().isNotEmpty == true
        ? _estado!.nombreEmpresa.trim()
        : 'la empresa';
    final email = _estado?.emailContacto?.trim();
    final tieneEmail = email != null && email.isNotEmpty;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.storefront_outlined,
                          size: 32,
                          color: _muted,
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Fuera de servicio temporalmente',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: _text,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'La empresa $nombre no está disponible en este momento. '
                        'Por favor, comunícate con${tieneEmail ? ':' : ' la empresa.'}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 15,
                          height: 1.45,
                        ),
                      ),
                      if (tieneEmail) ...[
                        const SizedBox(height: 16),
                        InkWell(
                          onTap: () => _abrirEmail(email),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Text(
                              email,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: _accent,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                decorationColor: _accent,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      if (_checking)
                        const RepartidorLoadingSpinner.small(color: _muted)
                      else
                        const Text(
                          'Comprobando disponibilidad…',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
