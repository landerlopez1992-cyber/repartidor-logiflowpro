import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/entrega_progreso.dart';

/// Checklist visible del proceso de entrega (persistente en pantalla).
class EntregaProgresoPanel extends StatelessWidget {
  const EntregaProgresoPanel({
    super.key,
    required this.progreso,
    required this.pasosRequeridos,
    this.siguientePaso,
  });

  final EntregaProgreso progreso;
  final List<EntregaPaso> pasosRequeridos;
  final EntregaPaso? siguientePaso;

  @override
  Widget build(BuildContext context) {
    if (pasosRequeridos.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE8E8E8)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Row(
              children: [
                Icon(Icons.checklist_rtl, color: AppColors.header, size: 22),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Proceso de entrega',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Los pasos completados se guardan en el teléfono. Si cierras la app, continúas donde quedaste.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.darkTextMuted,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            ...pasosRequeridos.map((paso) => _filaPaso(paso)),
          ],
        ),
      ),
    );
  }

  Widget _filaPaso(EntregaPaso paso) {
    final completo = progreso.pasoCompleto(paso);
    final esActual = !completo && siguientePaso == paso;
    final info = _infoPaso(paso, completo);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: completo
              ? AppColors.exito.withValues(alpha: 0.08)
              : esActual
                  ? AppColors.botonPrincipal.withValues(alpha: 0.1)
                  : const Color(0xFFF5F5F5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: completo
                ? AppColors.exito
                : esActual
                    ? AppColors.botonPrincipal
                    : const Color(0xFFE0E0E0),
            width: esActual ? 1.5 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              completo
                  ? Icons.check_circle
                  : esActual
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
              color: completo
                  ? AppColors.exito
                  : esActual
                      ? AppColors.botonPrincipal
                      : const Color(0xFFB0B0B0),
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    info.titulo,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: completo
                          ? AppColors.exito
                          : AppColors.textoPrincipal,
                    ),
                  ),
                  if (info.subtitulo != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      info.subtitulo!,
                      style: TextStyle(
                        fontSize: 12,
                        color: completo
                            ? const Color(0xFF2E7D32)
                            : AppColors.textoSecundario,
                      ),
                    ),
                  ],
                  if (esActual) ...[
                    const SizedBox(height: 4),
                    const Text(
                      'Pendiente — pulsa «Entregar» para continuar',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.botonPrincipal,
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

  _PasoUi _infoPaso(EntregaPaso paso, bool completo) {
    switch (paso) {
      case EntregaPaso.cobro:
        return _PasoUi(
          titulo: completo ? 'Monto cobrado' : 'Cobrar al cliente',
          subtitulo: completo
              ? (progreso.cobroMontoEtiqueta != null
                  ? '${progreso.cobroMontoEtiqueta} — exitoso'
                  : 'Cobro registrado exitosamente')
              : 'Confirma el pago contra entrega',
        );
      case EntregaPaso.remesa:
        return _PasoUi(
          titulo: completo ? 'Remesa entregada' : 'Entregar remesa',
          subtitulo: completo
              ? (progreso.remesaMontoEtiqueta != null
                  ? '${progreso.remesaMontoEtiqueta} — exitoso'
                  : 'Remesa entregada exitosamente')
              : 'Confirma entrega del dinero al destinatario',
        );
      case EntregaPaso.foto:
        return _PasoUi(
          titulo: completo ? 'Foto de entrega' : 'Foto de entrega',
          subtitulo: completo
              ? 'Foto guardada exitosamente'
              : 'Toma la foto del paquete entregado',
        );
      case EntregaPaso.firma:
        return _PasoUi(
          titulo: completo ? 'Firma del cliente' : 'Firma del cliente',
          subtitulo: completo
              ? 'Firma guardada exitosamente'
              : 'Captura la firma en pantalla',
        );
      case EntregaPaso.bultos:
        return _PasoUi(
          titulo: completo ? 'Bultos confirmados' : 'Confirmar bultos',
          subtitulo: completo
              ? 'Cantidad de bultos confirmada'
              : 'Verifica cuántos bultos entregaste',
        );
    }
  }
}

class _PasoUi {
  final String titulo;
  final String? subtitulo;
  const _PasoUi({required this.titulo, this.subtitulo});
}

/// Banner verde temporal tras completar un paso.
class EntregaPasoExitoBanner extends StatelessWidget {
  const EntregaPasoExitoBanner({super.key, required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.exito.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.exito),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: AppColors.exito, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              mensaje,
              style: const TextStyle(
                color: Color(0xFF1B5E20),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
