import 'package:flutter/material.dart';

import '../config/app_colors.dart';

/// Panel embebido en pestaña Viajes cuando `cuenta_suspendida` (no bloquea toda la app).
class RepartidorViajesSuspendidoPanel extends StatelessWidget {
  const RepartidorViajesSuspendidoPanel({
    super.key,
    this.empresaNombre,
    this.onAbrirChat,
  });

  final String? empresaNombre;
  final VoidCallback? onAbrirChat;

  @override
  Widget build(BuildContext context) {
    final empresa = (empresaNombre ?? '').trim().isEmpty
        ? 'tu empresa'
        : empresaNombre!.trim();

    return ColoredBox(
      color: AppColors.darkBg,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.block_rounded,
                      color: Color(0xFFDC2626),
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Viajes suspendidos',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.darkText,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Tu cuenta de chofer fue suspendida por $empresa. '
                    'No puedes buscar ni aceptar viajes hasta que te reactiven.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.darkTextMuted,
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.darkElevated,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: const Text(
                      'Puedes seguir usando Repartidor, chat y otras funciones. '
                      'Contacta a tu empresa por el chat de soporte.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.darkTextMuted,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                  if (onAbrirChat != null) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onAbrirChat,
                        icon: const Icon(Icons.chat_bubble_outline, size: 18),
                        label: const Text('Abrir chat de soporte'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF37474F),
                          foregroundColor: AppColors.darkText,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
