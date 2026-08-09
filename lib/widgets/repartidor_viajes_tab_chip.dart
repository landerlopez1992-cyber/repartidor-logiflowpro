import 'package:flutter/material.dart';

/// Chip de pestaña «Viajes»: pulsa en naranja si hay carrera activa.
class RepartidorViajesTabChip extends StatefulWidget {
  const RepartidorViajesTabChip({
    super.key,
    required this.selected,
    required this.enabled,
    required this.showOnlineDot,
    required this.viajeActivo,
    required this.onTap,
  });

  final bool selected;
  final bool enabled;
  final bool showOnlineDot;
  final bool viajeActivo;
  final VoidCallback onTap;

  @override
  State<RepartidorViajesTabChip> createState() =>
      _RepartidorViajesTabChipState();
}

class _RepartidorViajesTabChipState extends State<RepartidorViajesTabChip>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulse;

  @override
  void initState() {
    super.initState();
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant RepartidorViajesTabChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viajeActivo != widget.viajeActivo ||
        oldWidget.enabled != widget.enabled) {
      _syncPulse();
    }
  }

  void _syncPulse() {
    final need = widget.viajeActivo && widget.enabled;
    if (need) {
      _pulse ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 750),
      )..repeat(reverse: true);
      if (!(_pulse!.isAnimating)) {
        _pulse!.repeat(reverse: true);
      }
    } else {
      _pulse?.stop();
      _pulse?.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorIcon = !widget.enabled
        ? const Color(0xFF6B7280).withValues(alpha: 0.55)
        : widget.viajeActivo
            ? const Color(0xFFFF9800)
            : widget.selected
                ? const Color(0xFFECEFF1)
                : const Color(0xFF9CA3AF);

    Widget body = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: widget.viajeActivo
                ? const Color(0xFFFF9800).withValues(alpha: 0.18)
                : widget.selected
                    ? const Color(0xFF37474F)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: widget.viajeActivo
                ? Border.all(
                    color: const Color(0xFFFF9800).withValues(alpha: 0.85),
                    width: 1.5,
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    Icons.local_taxi_outlined,
                    size: 15,
                    color: colorIcon,
                  ),
                  if (widget.showOnlineDot && widget.enabled)
                    Positioned(
                      right: -3,
                      top: -3,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF1E232E),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  if (widget.viajeActivo && widget.enabled)
                    Positioned(
                      right: -3,
                      top: -3,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF9800),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFF1E232E),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 6),
              Text(
                'Viajes',
                style: TextStyle(
                  color: colorIcon,
                  fontSize: 12.5,
                  fontWeight: widget.selected || widget.viajeActivo
                      ? FontWeight.w700
                      : FontWeight.w500,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (_pulse != null && widget.viajeActivo && widget.enabled) {
      body = FadeTransition(
        opacity: Tween<double>(begin: 0.45, end: 1.0).animate(
          CurvedAnimation(parent: _pulse!, curve: Curves.easeInOut),
        ),
        child: body,
      );
    }

    return Expanded(child: body);
  }
}
