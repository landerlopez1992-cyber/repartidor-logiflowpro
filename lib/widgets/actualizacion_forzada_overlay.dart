import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/repartidor_actualizacion_forzada_service.dart';
import 'volonex_dialog.dart';

/// Modal obligatorio hasta que la versión instalada sea >= la de la tienda.
/// Abrir Play/App Store no cierra el modal; al volver a la app se revalida.
class ActualizacionForzadaOverlay extends StatefulWidget {
  const ActualizacionForzadaOverlay({
    super.key,
    required this.estado,
  });

  final ActualizacionForzadaEstado estado;

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
      await RepartidorActualizacionForzadaService.instance
          .abrirTienda(widget.estado.urlTienda);
      // No marcar onda ni cerrar: el padre reconsulta en AppLifecycleState.resumed.
    } finally {
      if (mounted) setState(() => _abriendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final esAndroid = widget.estado.plataforma == 'android';
    final etiquetaTienda = esAndroid ? 'Google Play' : 'App Store';
    final instalada = widget.estado.installedVersion?.trim() ?? '';
    final publicada = widget.estado.storePublishedVersion?.trim() ?? '';

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
                if (instalada.isNotEmpty || publicada.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    [
                      if (instalada.isNotEmpty) 'Instalada: $instalada',
                      if (publicada.isNotEmpty) 'En tienda: $publicada',
                    ].join(' · '),
                    style: const TextStyle(
                      color: AppColors.darkTextMuted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
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
                          'Debes actualizar desde $etiquetaTienda para seguir usando la app. '
                          'Esta ventana se cerrará solo cuando hayas instalado la nueva versión.',
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
