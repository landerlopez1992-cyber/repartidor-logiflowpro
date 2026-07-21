import 'package:flutter/material.dart';

/// Auto vista superior (mismo estilo que CubaLink taxi / MapLibre).
class TaxiUberMapCar extends StatelessWidget {
  const TaxiUberMapCar({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _TopDownCarPainter(),
    );
  }
}

class _TopDownCarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = size.width / 32;
    final shadow = Paint()
      ..color = const Color(0x40000000)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2.5 * scale);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, cy + 1.2 * scale),
          width: 14 * scale,
          height: 24 * scale,
        ),
        Radius.circular(4 * scale),
      ),
      shadow,
    );
    final body = Paint()..color = const Color(0xFFF5F5F5);
    final bodyStroke = Paint()
      ..color = const Color(0xFF2C2C2C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1 * scale;
    final bodyR = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx, cy),
        width: 13 * scale,
        height: 23 * scale,
      ),
      Radius.circular(3.5 * scale),
    );
    canvas.drawRRect(bodyR, body);
    canvas.drawRRect(bodyR, bodyStroke);
    final glass = Paint()..color = const Color(0xFF9E9E9E);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, cy - 5.5 * scale),
          width: 9 * scale,
          height: 4.5 * scale,
        ),
        Radius.circular(1.2 * scale),
      ),
      glass,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, cy + 5.2 * scale),
          width: 9 * scale,
          height: 3.8 * scale,
        ),
        Radius.circular(1.2 * scale),
      ),
      glass,
    );
    final roof = Paint()..color = const Color(0xFFE8E8E8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: 8.5 * scale,
          height: 7 * scale,
        ),
        Radius.circular(1.5 * scale),
      ),
      roof,
    );
    final light = Paint()..color = const Color(0xFFFFF59D);
    canvas.drawCircle(Offset(cx - 3.2 * scale, cy - 10.2 * scale), 1.3 * scale, light);
    canvas.drawCircle(Offset(cx + 3.2 * scale, cy - 10.2 * scale), 1.3 * scale, light);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
