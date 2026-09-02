import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/repartidor_actualizacion_forzada_service.dart';
import 'actualizacion_forzada_overlay.dart';

/// Bloquea la app con modal obligatorio hasta actualizar (paridad CubaLink23).
class RepartidorStoreUpdateBlocker extends StatefulWidget {
  const RepartidorStoreUpdateBlocker({super.key, required this.child});

  final Widget child;

  @override
  State<RepartidorStoreUpdateBlocker> createState() =>
      _RepartidorStoreUpdateBlockerState();
}

class _RepartidorStoreUpdateBlockerState extends State<RepartidorStoreUpdateBlocker>
    with WidgetsBindingObserver {
  bool get _plataformaSoportada {
    if (kIsWeb) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  @override
  void initState() {
    super.initState();
    if (_plataformaSoportada) {
      WidgetsBinding.instance.addObserver(this);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(
          RepartidorActualizacionForzadaService.instance.refresh(),
        );
      });
    }
  }

  @override
  void dispose() {
    if (_plataformaSoportada) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(
        RepartidorActualizacionForzadaService.instance.refresh(
          forceStoreLookup: true,
        ),
      );
    }
  }

  Future<void> _onActualizar(ActualizacionForzadaEstado estado) async {
    await RepartidorActualizacionForzadaService.instance.abrirTienda(
      estado.urlTienda,
    );
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await RepartidorActualizacionForzadaService.instance.refresh(
      forceStoreLookup: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_plataformaSoportada) return widget.child;

    return ValueListenableBuilder<ActualizacionForzadaEstado?>(
      valueListenable: RepartidorActualizacionForzadaService.estado,
      builder: (context, estado, child) {
        return ValueListenableBuilder<RepartidorBuildPendienteInfo?>(
          valueListenable: RepartidorActualizacionForzadaService.buildPendiente,
          builder: (context, pendiente, child2) {
            return Stack(
              children: [
                child2!,
                if (estado != null)
                  ActualizacionForzadaOverlay(
                    estado: estado,
                    onActualizar: () => _onActualizar(estado),
                  )
                else if (pendiente != null)
                  _BannerBuildPendiente(info: pendiente),
              ],
            );
          },
          child: widget.child,
        );
      },
      child: widget.child,
    );
  }
}

class _BannerBuildPendiente extends StatelessWidget {
  const _BannerBuildPendiente({required this.info});

  final RepartidorBuildPendienteInfo info;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Material(
            color: Colors.transparent,
            elevation: 6,
            shadowColor: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.darkElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.darkBorder),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.system_update_outlined,
                    size: 18,
                    color: AppColors.darkTextMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Nueva versión de ${info.nombreApp} en preparación. '
                      'Pronto en la tienda.',
                      style: const TextStyle(
                        color: AppColors.darkTextMuted,
                        fontSize: 11,
                        height: 1.3,
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
