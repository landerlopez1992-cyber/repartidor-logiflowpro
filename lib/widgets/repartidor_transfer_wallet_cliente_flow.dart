import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_colors.dart';
import '../services/repartidor_saldo_service.dart';
import '../services/repartidor_transfer_wallet_cliente_service.dart';
import 'repartidor_loading_spinner.dart';

/// Flujo: monto → confirmación → loading → resultado.
class RepartidorTransferWalletClienteFlow {
  RepartidorTransferWalletClienteFlow._();

  /// Retorna true si la transferencia terminó bien.
  static Future<bool> run(
    BuildContext context, {
    required RepartidorWalletClienteDestino destino,
    required double saldoDisponible,
  }) async {
    if (!destino.tieneCuentaCliente) return false;

    final monto = await _showMontoDialog(
      context,
      destino: destino,
      saldoDisponible: saldoDisponible,
    );
    if (monto == null || !context.mounted) return false;

    final confirmar = await _showConfirmDialog(
      context,
      destino: destino,
      monto: monto,
      saldoDisponible: saldoDisponible,
    );
    if (confirmar != true || !context.mounted) return false;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (_) => const _TransferLoadingDialog(),
    );

    final started = DateTime.now();
    Map<String, dynamic> result;
    try {
      result = await RepartidorTransferWalletClienteService.transferir(monto);
    } catch (e) {
      result = {'ok': false, 'mensaje': '$e'};
    }

    final elapsed = DateTime.now().difference(started);
    const minWait = Duration(milliseconds: 1400);
    if (elapsed < minWait) {
      await Future<void>.delayed(minWait - elapsed);
    }

    if (!context.mounted) return false;
    Navigator.of(context, rootNavigator: true).pop();

    if (!context.mounted) return false;

    if (result['ok'] != true) {
      await _showResultado(
        context,
        ok: false,
        titulo: 'No se pudo transferir',
        mensaje: result['mensaje']?.toString() ??
            result['error']?.toString() ??
            'Inténtalo de nuevo.',
      );
      return false;
    }

    final saldoNuevo = result['saldo_repartidor'];
    if (saldoNuevo is num) {
      await RepartidorSaldoService.aplicarSaldoServidorYNotificar(
        saldoServidor: saldoNuevo.toDouble(),
      );
    } else {
      RepartidorSaldoService.notificarCambioSaldo();
    }

    await _showResultado(
      context,
      ok: true,
      titulo: 'Transferencia lista',
      mensaje:
          'Se enviaron \$${monto.toStringAsFixed(2)} a tu billetera de cliente. '
          'Ya puedes usarlo en la app.',
    );
    return true;
  }

  static Future<double?> _showMontoDialog(
    BuildContext context, {
    required RepartidorWalletClienteDestino destino,
    required double saldoDisponible,
  }) {
    return showDialog<double>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) => _MontoTransferDialog(
        destino: destino,
        saldoDisponible: saldoDisponible,
      ),
    );
  }

  static Future<bool?> _showConfirmDialog(
    BuildContext context, {
    required RepartidorWalletClienteDestino destino,
    required double monto,
    required double saldoDisponible,
  }) {
    final despues = (saldoDisponible - monto).clamp(0.0, saldoDisponible);
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Material(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.verified_user_outlined,
                    color: Color(0xFFFF9800),
                    size: 36,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Confirmar transferencia',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.darkText,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '\$${monto.toStringAsFixed(2)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFF9800),
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'a tu billetera de ${destino.nombreEmpresa}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.darkTextMuted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tu saldo: \$${saldoDisponible.toStringAsFixed(2)} → \$${despues.toStringAsFixed(2)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.darkText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.darkElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFFDC2626).withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Text(
                      'Esta acción no se puede deshacer. El monto deja de estar '
                      'en tu saldo de repartidor y queda en tu billetera de cliente.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.darkTextMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.header,
                        foregroundColor: AppColors.darkText,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Confirmar transferencia',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(
                        color: AppColors.darkTextMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Future<void> _showResultado(
    BuildContext context, {
    required bool ok,
    required String titulo,
    required String mensaje,
  }) {
    final color = ok ? const Color(0xFF4CAF50) : const Color(0xFFDC2626);
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.7),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Material(
            color: AppColors.darkSurface,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    ok ? Icons.check_circle_rounded : Icons.error_outline,
                    color: color,
                    size: 48,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    titulo,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.darkText,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    mensaje,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.darkTextMuted,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.header,
                        foregroundColor: AppColors.darkText,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Entendido',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TransferLoadingDialog extends StatelessWidget {
  const _TransferLoadingDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Material(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(16),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RepartidorLoadingSpinner.medium(color: Color(0xFFFF9800)),
                SizedBox(height: 14),
                Text(
                  'Procesando transferencia…',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.darkText,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Modal de monto: el controller vive en el State (evita dispose prematuro).
class _MontoTransferDialog extends StatefulWidget {
  const _MontoTransferDialog({
    required this.destino,
    required this.saldoDisponible,
  });

  final RepartidorWalletClienteDestino destino;
  final double saldoDisponible;

  @override
  State<_MontoTransferDialog> createState() => _MontoTransferDialogState();
}

class _MontoTransferDialogState extends State<_MontoTransferDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final s = widget.saldoDisponible;
    _ctrl = TextEditingController(
      text: s > 0 ? s.toStringAsFixed(2) : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _usarTodo() {
    _ctrl.text = widget.saldoDisponible.toStringAsFixed(2);
    _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
  }

  void _continuar() {
    final raw = _ctrl.text.replaceAll(',', '.').trim();
    final m = double.tryParse(raw);
    if (m == null || m < 0.01) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Indica un monto válido'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }
    if (m > widget.saldoDisponible + 0.001) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El monto supera tu saldo'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }
    Navigator.of(context).pop(m);
  }

  @override
  Widget build(BuildContext context) {
    final destino = widget.destino;
    final saldo = widget.saldoDisponible;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Material(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF9800).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.swap_horiz_rounded,
                    color: Color(0xFFFF9800),
                    size: 22,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Transferir saldo a billetera',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.darkText,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  destino.nombreEmpresa,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFF9800),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Disponible: \$${saldo.toStringAsFixed(2)} ${destino.moneda}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.darkTextMuted,
                    fontSize: 13,
                  ),
                ),
                if ((destino.emailCliente ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    destino.emailCliente!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.darkTextMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: _ctrl,
                  textAlign: TextAlign.center,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  style: const TextStyle(
                    color: AppColors.darkText,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Monto',
                    labelStyle: const TextStyle(color: AppColors.darkTextMuted),
                    alignLabelWithHint: true,
                    filled: true,
                    fillColor: AppColors.darkElevated,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.darkBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppColors.darkBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFFF9800)),
                    ),
                    prefixText: '\$ ',
                    prefixStyle: const TextStyle(
                      color: AppColors.darkText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _usarTodo,
                  child: const Text(
                    'Usar todo el saldo',
                    style: TextStyle(
                      color: Color(0xFFFF9800),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  'Sin aprobación de la empresa. El dinero pasa a tu billetera '
                  'de cliente (no es cobro a banco).',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.darkTextMuted.withValues(alpha: 0.95),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _continuar,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.header,
                      foregroundColor: AppColors.darkText,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Continuar',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(
                      color: AppColors.darkTextMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
