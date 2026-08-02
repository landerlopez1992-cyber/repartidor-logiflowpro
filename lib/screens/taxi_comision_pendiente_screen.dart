import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../main.dart';
import '../services/repartidor_saldo_service.dart';
import '../services/repartidor_seguridad_service.dart';
import '../services/repartidor_pantallas_offline_service.dart';
import '../services/sync_service.dart';
import '../utils/repartidor_requires_online.dart';
import '../widgets/taxi_fianza_confirm_flow.dart';
import '../widgets/taxi_zelle_enviar_recibo_flow.dart';
import '../widgets/taxi_zelle_pago_explicacion_modal.dart';

/// Comisión cash pendiente + fianza + transferir saldo → fianza + pagar a empresa.
class TaxiComisionPendienteScreen extends StatefulWidget {
  const TaxiComisionPendienteScreen({super.key});

  @override
  State<TaxiComisionPendienteScreen> createState() =>
      _TaxiComisionPendienteScreenState();
}

class _TaxiComisionPendienteScreenState
    extends State<TaxiComisionPendienteScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  Map<String, dynamic> _data = {};
  RealtimeChannel? _pagoChannel;

  final _transferCtrl = TextEditingController();
  final _pagoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _pagoChannel?.unsubscribe();
    _transferCtrl.dispose();
    _pagoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid != null) {
        final cached =
            await RepartidorPantallasOfflineService.cargarComisionMiDeuda(uid);
        if (cached != null && cached['ok'] == true && mounted) {
          setState(() {
            _data = cached;
            _loading = false;
            final deuda = _n(cached['deuda_usd']);
            if (deuda > 0 && _pagoCtrl.text.isEmpty) {
              _pagoCtrl.text = deuda.toStringAsFixed(2);
            }
          });
        }
      }

      if (!SyncService().isOnline) {
        if (_data.isEmpty && mounted) {
          setState(() {
            _error =
                'Sin conexión y sin datos guardados. Abre esta pantalla con internet una vez.';
            _loading = false;
          });
        } else if (mounted) {
          setState(() => _loading = false);
        }
        return;
      }

      final res = await supabase.rpc('taxi_comision_mi_deuda');
      final map = Map<String, dynamic>.from(res as Map);
      if (map['ok'] != true) {
        throw Exception(map['mensaje'] ?? map['error'] ?? 'Error');
      }
      if (uid != null) {
        await RepartidorPantallasOfflineService.guardarComisionMiDeuda(uid, map);
      }
      if (!mounted) return;
      setState(() {
        _data = map;
        _loading = false;
        final deuda = _n(map['deuda_usd']);
        if (deuda > 0 && _pagoCtrl.text.isEmpty) {
          _pagoCtrl.text = deuda.toStringAsFixed(2);
        }
      });
      _suscribirPagoPendiente();
    } catch (e) {
      if (!mounted) return;
      if (_data.isNotEmpty) {
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? get _pagoPendiente {
    final p = _data['pago_pendiente'];
    if (p is Map) return Map<String, dynamic>.from(p);
    return null;
  }

  void _suscribirPagoPendiente() {
    final pago = _pagoPendiente;
    final pagoId = pago?['id']?.toString();
    _pagoChannel?.unsubscribe();
    _pagoChannel = null;
    if (pagoId == null || pagoId.isEmpty) return;

    _pagoChannel = supabase
        .channel('taxi_comision_pago_chofer_$pagoId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'taxi_comision_pagos',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: pagoId,
          ),
          callback: (_) async {
            final habiaPendiente = _pagoPendiente != null;
            await _cargar();
            if (!mounted || !habiaPendiente) return;
            if (_pagoPendiente == null) {
              _toast('La empresa revisó tu pago');
            }
          },
        )
        .subscribe();
  }

  double _n(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  Future<void> _transferirAFianza() async {
    final monto = double.tryParse(_transferCtrl.text.replaceAll(',', '.'));
    if (monto == null || monto < 0.01) {
      _toast('Indica un monto válido', error: true);
      return;
    }
    final saldo = _n(_data['saldo_billetera_usd']);
    final fianza = _n(_data['fianza_usd']);
    if (monto > saldo + 0.001) {
      _toast('No tienes saldo suficiente en billetera', error: true);
      return;
    }
    if (_busy) return;
    if (!await repartidorRequiereInternet(
      context,
      accion: 'transferir a fianza',
    )) {
      return;
    }

    final ok = await TaxiFianzaConfirmFlow.run(
      context,
      modo: TaxiFianzaConfirmModo.transferirAFianza,
      montoUsd: monto,
      saldoBilleteraUsd: saldo,
      fianzaActualUsd: fianza,
      botonAceptar: 'Confirmar transferencia',
      accion: () async {
        final res = await supabase.rpc(
          'taxi_fianza_transferir_desde_saldo',
          params: {'p_monto': monto},
        );
        final map = Map<String, dynamic>.from(res as Map);
        if (map['ok'] != true) {
          return (
            ok: false,
            err: map['mensaje']?.toString() ??
                map['error']?.toString() ??
                'Error',
            mensajeOk: null,
          );
        }
        final saldoNuevo = map['saldo_billetera'];
        if (saldoNuevo is num) {
          await RepartidorSaldoService.aplicarSaldoServidorYNotificar(
            saldoServidor: saldoNuevo.toDouble(),
          );
        } else {
          RepartidorSaldoService.notificarCambioSaldo();
        }
        return (
          ok: true,
          err: null,
          mensajeOk:
              'Se movieron \$${monto.toStringAsFixed(2)} de tu billetera a la fianza de viajes cash.',
        );
      },
    );
    if (!ok || !mounted) return;
    _transferCtrl.clear();
    await _cargar();
  }

  Future<void> _pagarConFianza() async {
    final monto = double.tryParse(_pagoCtrl.text.replaceAll(',', '.'));
    if (monto == null || monto < 0.01) {
      _toast('Indica el monto a pagar', error: true);
      return;
    }
    final saldo = _n(_data['saldo_billetera_usd']);
    final fianza = _n(_data['fianza_usd']);
    if (monto > fianza + 0.001) {
      _toast('Tu fianza no cubre ese monto', error: true);
      return;
    }
    if (_busy) return;
    if (!await repartidorRequiereInternet(
      context,
      accion: 'pagar con fianza',
    )) {
      return;
    }

    final ok = await TaxiFianzaConfirmFlow.run(
      context,
      modo: TaxiFianzaConfirmModo.pagarComisionConFianza,
      montoUsd: monto,
      saldoBilleteraUsd: saldo,
      fianzaActualUsd: fianza,
      botonAceptar: 'Confirmar pago',
      accion: () async {
        final res = await supabase.rpc(
          'taxi_comision_solicitar_pago',
          params: {
            'p_metodo': 'fianza',
            'p_monto': monto,
          },
        );
        final map = Map<String, dynamic>.from(res as Map);
        if (map['ok'] != true) {
          return (
            ok: false,
            err: map['mensaje']?.toString() ??
                map['error']?.toString() ??
                'Error',
            mensajeOk: null,
          );
        }
        // Puede afectar deuda/fianza; refrescar billetera por si el ledger cambió.
        RepartidorSaldoService.notificarCambioSaldo();
        return (
          ok: true,
          err: null,
          mensajeOk:
              'Comisión de \$${monto.toStringAsFixed(2)} cubierta con tu fianza.',
        );
      },
    );
    if (!ok || !mounted) return;
    await _cargar();
  }

  Future<void> _pagarOficina() async {
    final monto = double.tryParse(_pagoCtrl.text.replaceAll(',', '.'));
    if (monto == null || monto < 0.01) {
      _toast('Indica el monto', error: true);
      return;
    }
    if (!await repartidorRequiereInternet(
      context,
      accion: 'registrar pago en oficina',
    )) {
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await supabase.rpc(
        'taxi_comision_solicitar_pago',
        params: {
          'p_metodo': 'oficina',
          'p_monto': monto,
          'p_notas': 'Pago en oficina',
        },
      );
      final map = Map<String, dynamic>.from(res as Map);
      if (map['ok'] != true) {
        throw Exception(map['mensaje'] ?? map['error'] ?? 'Error');
      }
      _toast(map['mensaje']?.toString() ?? 'Registrado. Espera confirmación.');
      await _cargar();
    } catch (e) {
      _toast('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pagarZelle() async {
    if (_pagoPendiente != null) {
      _toast('Ya hay un comprobante en revisión. Espera la confirmación.');
      return;
    }
    final monto = double.tryParse(_pagoCtrl.text.replaceAll(',', '.'));
    if (monto == null || monto < 0.01) {
      _toast('Indica el monto', error: true);
      return;
    }
    if (!await repartidorRequiereInternet(
      context,
      accion: 'pagar con Zelle',
    )) {
      return;
    }

    final zelle = _data['zelle'] is Map
        ? Map<String, dynamic>.from(_data['zelle'] as Map)
        : <String, dynamic>{};
    final datosZelle = _datosZelleTexto(zelle);
    final nombreEmpresa = await _nombreEmpresaActual();

    if (!mounted) return;
    final okModal = await TaxiZellePagoExplicacionModal.show(
      context,
      nombreEmpresa: nombreEmpresa,
      datosZelle: datosZelle,
      montoUsd: monto,
    );
    if (okModal != true || !mounted) return;

    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
      maxWidth: 1600,
    );
    if (x == null || !mounted) return;

    final bytes = await x.readAsBytes();
    if (!mounted) return;

    final result = await TaxiZelleEnviarReciboFlow.run(
      context,
      imagenBytes: bytes,
      montoUsd: monto,
      enviar: () async {
        final uid = supabase.auth.currentUser?.id ?? 'anon';
        final path =
            'taxi_comision_${uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        String url;
        try {
          await supabase.storage.from('comprobantes').uploadBinary(
                path,
                bytes,
                fileOptions: const FileOptions(
                  contentType: 'image/jpeg',
                  upsert: true,
                ),
              );
          url = supabase.storage.from('comprobantes').getPublicUrl(path);
        } catch (_) {
          await supabase.storage.from('fotos-perfil').uploadBinary(
                path,
                bytes,
                fileOptions: const FileOptions(
                  contentType: 'image/jpeg',
                  upsert: true,
                ),
              );
          url = supabase.storage.from('fotos-perfil').getPublicUrl(path);
        }

        final res = await supabase.rpc(
          'taxi_comision_solicitar_pago',
          params: {
            'p_metodo': 'zelle',
            'p_monto': monto,
            'p_comprobante_url': url,
          },
        );
        final map = Map<String, dynamic>.from(res as Map);
        if (map['ok'] != true) {
          return (
            ok: false,
            err: map['mensaje']?.toString() ??
                map['error']?.toString() ??
                'Error',
            mensajeOk: null,
          );
        }
        return (
          ok: true,
          err: null,
          mensajeOk: map['mensaje']?.toString() ??
              'La empresa revisará tu pago. Cuando lo confirme, '
                  'se descontará de tu deuda.',
        );
      },
    );

    if (result?.ok == true) {
      await _cargar();
    }
  }

  String _datosZelleTexto(Map<String, dynamic> zelle) {
    final email = zelle['email']?.toString().trim() ?? '';
    final tel = zelle['telefono']?.toString().trim() ?? '';
    final texto = zelle['texto']?.toString().trim() ?? '';
    final partes = <String>[];
    if (email.isNotEmpty) partes.add(email);
    if (tel.isNotEmpty && tel != email) partes.add(tel);
    if (texto.isNotEmpty) partes.add(texto);
    if (partes.isEmpty) return 'Ver datos Zelle en la empresa';
    return partes.join(' · ');
  }

  Future<String> _nombreEmpresaActual() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid != null) {
      final cached =
          await RepartidorSeguridadService.nombreEmpresaDesdeCache(uid);
      if (cached != null && cached.trim().isNotEmpty) {
        return cached.trim();
      }
    }
    try {
      final ctx = await RepartidorSeguridadService.cargarContexto();
      if (ctx.nombreEmpresa.trim().isNotEmpty &&
          ctx.nombreEmpresa.trim().toLowerCase() != 'tu empresa') {
        return ctx.nombreEmpresa.trim();
      }
    } catch (_) {}
    return 'la empresa';
  }

  void _toast(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? const Color(0xFFDC2626) : const Color(0xFF37474F),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deuda = _n(_data['deuda_usd']);
    final fianza = _n(_data['fianza_usd']);
    final saldo = _n(_data['saldo_billetera_usd']);
    final tope = _n(_data['tope_deuda_usd']);
    final pct = _n(_data['pct_tope']);
    final bloqueado = _data['bloqueado'] == true;
    final zelle = _data['zelle'] is Map
        ? Map<String, dynamic>.from(_data['zelle'] as Map)
        : <String, dynamic>{};
    final pagoPendiente = _pagoPendiente;
    final esperandoEmpresa = pagoPendiente != null;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF37474F),
        title: const Text('Comisión pendiente'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            style: const TextStyle(color: AppColors.darkTextMuted)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _cargar,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF9800),
                          ),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (bloqueado)
                      Container(
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFDC2626)),
                        ),
                        child: const Text(
                          'Estás bloqueado para nuevos viajes. '
                          'Paga tu comisión o usa tu fianza.',
                          style: TextStyle(color: Color(0xFFECEFF1), fontSize: 13),
                        ),
                      ),
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Debes \$${deuda.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: AppColors.darkText,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: tope > 0
                                ? (pct / 100).clamp(0.0, 1.0)
                                : 0,
                            backgroundColor: Colors.white12,
                            color: pct >= 100
                                ? const Color(0xFFDC2626)
                                : pct >= 80
                                    ? const Color(0xFFFF9800)
                                    : const Color(0xFF4CAF50),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Tope \$${tope.toStringAsFixed(0)} · ${pct.toStringAsFixed(0)}%',
                            style: const TextStyle(
                              color: AppColors.darkTextMuted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Fianza: \$${fianza.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: AppColors.darkText,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'La fianza sirve para que, cuando un pasajero te pague en efectivo, '
                            'la app descuente de aquí la comisión de la empresa y tú no te endeudes.',
                            style: TextStyle(
                              color: AppColors.darkTextMuted,
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Billetera (saldo): \$${saldo.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: AppColors.darkTextMuted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_data['metodo_fianza'] == true) ...[
                      const SizedBox(height: 16),
                      _card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Transferir saldo → fianza',
                              style: TextStyle(
                                color: AppColors.darkText,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Pasa dinero de tu billetera a la fianza. Ese monto queda listo '
                              'para cubrir la comisión de los viajes que cobres en cash.',
                              style: TextStyle(
                                color: AppColors.darkTextMuted,
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _transferCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              style: const TextStyle(color: AppColors.darkText),
                              decoration: _dec('Monto USD'),
                            ),
                            const SizedBox(height: 8),
                            ElevatedButton(
                              onPressed: _busy ? null : _transferirAFianza,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF9800),
                              ),
                              child: const Text('Transferir a fianza'),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pagar comisión a la empresa',
                            style: TextStyle(
                              color: AppColors.darkText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _pagoCtrl,
                            enabled: !esperandoEmpresa,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            style: const TextStyle(color: AppColors.darkText),
                            decoration: _dec('Monto a pagar'),
                          ),
                          if (_data['metodo_zelle'] == true) ...[
                            const SizedBox(height: 12),
                            Text(
                              'Zelle empresa: ${zelle['email'] ?? zelle['telefono'] ?? 'Ver en tienda'}',
                              style: const TextStyle(
                                color: AppColors.darkTextMuted,
                                fontSize: 12,
                              ),
                            ),
                            if ((zelle['texto']?.toString() ?? '').isNotEmpty)
                              Text(
                                zelle['texto'].toString(),
                                style: const TextStyle(
                                  color: AppColors.darkTextMuted,
                                  fontSize: 12,
                                ),
                              ),
                            const SizedBox(height: 8),
                            if (esperandoEmpresa) ...[
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF455A64),
                                    disabledBackgroundColor:
                                        const Color(0xFF455A64),
                                    disabledForegroundColor:
                                        const Color(0xFFECEFF1),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                      horizontal: 12,
                                    ),
                                  ),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFFECEFF1),
                                        ),
                                      ),
                                      SizedBox(width: 10),
                                      Flexible(
                                        child: Text(
                                          'Esperando confirmación…',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Enviaste \$${_n(pagoPendiente['monto']).toStringAsFixed(2)} '
                                'por ${pagoPendiente['metodo']}. '
                                'La empresa debe aceptar el pago.',
                                style: const TextStyle(
                                  color: AppColors.darkTextMuted,
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                              ),
                            ] else
                              ElevatedButton(
                                onPressed:
                                    _busy || deuda < 0.01 ? null : _pagarZelle,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF9800),
                                ),
                                child: const Text('Pagar con Zelle'),
                              ),
                          ],
                          if (_data['metodo_oficina'] == true) ...[
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed:
                                  _busy || deuda < 0.01 ? null : _pagarOficina,
                              child: const Text(
                                'Registrar pago en oficina',
                                style: TextStyle(color: AppColors.darkText),
                              ),
                            ),
                          ],
                          if (_data['metodo_fianza'] == true) ...[
                            const SizedBox(height: 8),
                            OutlinedButton(
                              onPressed: _busy ||
                                      deuda < 0.01 ||
                                      fianza < 0.01
                                  ? null
                                  : _pagarConFianza,
                              child: const Text(
                                'Pagar con fianza',
                                style: TextStyle(color: AppColors.darkText),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  InputDecoration _dec(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.darkTextMuted),
      filled: true,
      fillColor: AppColors.darkSurface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: child,
    );
  }
}
