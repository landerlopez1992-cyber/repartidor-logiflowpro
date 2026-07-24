import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_colors.dart';
import '../main.dart';
import '../services/repartidor_saldo_service.dart';
import '../widgets/taxi_fianza_confirm_flow.dart';

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

  final _transferCtrl = TextEditingController();
  final _pagoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
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
      final res = await supabase.rpc('taxi_comision_mi_deuda');
      final map = Map<String, dynamic>.from(res as Map);
      if (map['ok'] != true) {
        throw Exception(map['mensaje'] ?? map['error'] ?? 'Error');
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
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
    final monto = double.tryParse(_pagoCtrl.text.replaceAll(',', '.'));
    if (monto == null || monto < 0.01) {
      _toast('Indica el monto', error: true);
      return;
    }
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
      maxWidth: 1600,
    );
    if (x == null) return;

    setState(() => _busy = true);
    try {
      final bytes = await x.readAsBytes();
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
        throw Exception(map['mensaje'] ?? map['error'] ?? 'Error');
      }
      _toast(map['mensaje']?.toString() ?? 'Comprobante enviado');
      await _cargar();
    } catch (e) {
      _toast('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                              'Mueve dinero de tu billetera a la fianza para cubrir comisiones cash automáticamente.',
                              style: TextStyle(
                                color: AppColors.darkTextMuted,
                                fontSize: 12,
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
                            ElevatedButton(
                              onPressed: _busy || deuda < 0.01 ? null : _pagarZelle,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF9800),
                              ),
                              child: const Text('Pagar con Zelle (foto)'),
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
