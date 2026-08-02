import 'package:flutter/material.dart';
import '../utils/repartidor_connectivity.dart';

/// Icono de conectividad (idéntico a CubaLink23: wifi + punto naranja/rojo).
class RepartidorConnectivityAppBarIcon extends StatelessWidget {
  const RepartidorConnectivityAppBarIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool?>(
      valueListenable: RepartidorConnectivity.online,
      builder: (context, isOnline, _) {
        final offline = isOnline == false;
        return IconButton(
          tooltip: offline ? 'Sin conexión' : 'Conectado',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () async {
            await RepartidorConnectivity.refreshOnline();
            if (!context.mounted) return;
            if (RepartidorConnectivity.online.value == false) {
              await RepartidorConnectivity.showOfflineStatusModal(context);
            } else {
              await RepartidorConnectivity.showOnlineStatusModal(context);
            }
          },
          icon: SizedBox(
            width: 30,
            height: 30,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: Icon(
                    offline ? Icons.wifi_off_rounded : Icons.wifi_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                if (offline)
                  Positioned(
                    right: -1,
                    top: -1,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF37474F),
                          width: 1.5,
                        ),
                      ),
                    ),
                  )
                else if (isOnline == true)
                  Positioned(
                    right: -1,
                    top: -1,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9800),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFF37474F),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
