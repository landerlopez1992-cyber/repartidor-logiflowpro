import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Icono oficial de carga (misma UX que la app móvil CubaLink23):
/// [Icons.sync_rounded] girando.
///
/// Usar en pantallas de carga, botones y overlays.
/// Preferir esto frente a [CircularProgressIndicator].
class RepartidorLoadingSpinner extends StatefulWidget {
  static const Color accentColor = Color(0xFFFF9800);

  final double size;
  final Color color;
  final Duration duration;
  final List<Shadow>? shadows;
  final IconData icon;

  const RepartidorLoadingSpinner({
    super.key,
    this.size = 40,
    this.color = accentColor,
    this.duration = const Duration(milliseconds: 1100),
    this.shadows,
    this.icon = Icons.sync_rounded,
  });

  const RepartidorLoadingSpinner.small({
    super.key,
    this.color = accentColor,
    this.duration = const Duration(milliseconds: 1100),
    this.shadows,
    this.icon = Icons.sync_rounded,
  }) : size = 16;

  const RepartidorLoadingSpinner.medium({
    super.key,
    this.color = accentColor,
    this.duration = const Duration(milliseconds: 1100),
    this.shadows,
    this.icon = Icons.sync_rounded,
  }) : size = 28;

  const RepartidorLoadingSpinner.large({
    super.key,
    this.color = accentColor,
    this.duration = const Duration(milliseconds: 1100),
    this.shadows,
    this.icon = Icons.sync_rounded,
  }) : size = 48;

  @override
  State<RepartidorLoadingSpinner> createState() =>
      _RepartidorLoadingSpinnerState();
}

class _RepartidorLoadingSpinnerState extends State<RepartidorLoadingSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void didUpdateWidget(covariant RepartidorLoadingSpinner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW =
            constraints.maxWidth.isFinite ? constraints.maxWidth : widget.size;
        final maxH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : widget.size;
        final s =
            math.min(widget.size, math.min(maxW, maxH)).clamp(10.0, 128.0);

        return SizedBox(
          width: s,
          height: s,
          child: RotationTransition(
            turns: _controller,
            child: Transform.translate(
              offset: Offset(s * (0.5 / 24), s * (-1.0 / 24)),
              child: Icon(
                widget.icon,
                size: s,
                color: widget.color,
                shadows: widget.shadows,
              ),
            ),
          ),
        );
      },
    );
  }
}
