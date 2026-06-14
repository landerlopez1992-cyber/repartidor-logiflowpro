import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/repartidor_actualizacion_forzada_service.dart';
import 'volonex_dialog.dart';

/// Modal obligatorio y persistente hasta que el repartidor abre la tienda.
class ActualizacionForzadaOverlay extends StatefulWidget {
  const ActualizacionForzadaOverlay({
    super.key,
    required this.estado,
    this.onTiendaAbierta,
  });

  final ActualizacionForzadaEstado estado;
  final VoidCallback? onTiendaAbierta;

  @override
  State<ActualizacionForzadaOverlay> createState() =>
      _ActualizacionForzadaOverlayState();
}

class _ActualizacionForzadaOverlayState extends State<ActualizacionForzadaOverlay> {
  bool _abriendo = false;

  Future<void> _actualizar() async {
    if (_abriendo) return;
    setState(() => _abriendo = true);
    try {
      final ok = await RepartidorActualizacionForzadaService.instance
          .abrirTienda(widget.estado.urlTienda);
      if (ok) {
        await RepartidorActualizacionForzadaService.instance.marcarTiendaAbierta(
          plataforma: widget.estado.plataforma,
          onda: widget.estado.onda,
        );
        widget.onTiendaAbierta?.call();
      }
    } finally {
      if (mounted) setState(() => _abriendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final esAndroid = widget.estado.plataforma == 'android';
    final etiquetaTienda = esAndroid ? 'Google Play' : 'App Store';

    return PopScope(
      canPop: false,
      child: Material(
        color: Colors.black.withValues(alpha: 0.72),
        child: Center(
          child: VolonexDialog(
            title: widget.estado.titulo,
            leading: const Icon(
              Icons.system_update_alt_rounded,
              color: AppColors.botonPrincipal,
              size: 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.estado.mensaje,
                  style: const TextStyle(
                    color: AppColors.darkText,
                    fontSize: 14,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.darkElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.darkBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        esAndroid ? Icons.android_rounded : Icons.apple_rounded,
                        color: AppColors.darkTextMuted,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Debes actualizar desde $etiquetaTienda para seguir usando la app.',
                          style: const TextStyle(
                            color: AppColors.darkTextMuted,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: _abriendo ? null : _actualizar,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.botonPrincipal,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                ),
                child: _abriendo
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text('Actualizar en $etiquetaTienda'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
