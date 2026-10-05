import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Crisp vector Google "G" (no asset / pubspec change needed).
/// Rendered on a white circle so it stays clear on dark backgrounds.
class GoogleLogo extends StatelessWidget {
  final double size;
  const GoogleLogo({super.key, this.size = 26});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
      child: CustomPaint(
        size: Size.square(size * 0.62),
        painter: _GPainter(),
      ),
    );
  }
}

class _GPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.22;
    final r = (s - stroke) / 2;
    final c = Offset(s / 2, s / 2);
    final rect = Rect.fromCircle(center: c, radius: r);
    double rad(double d) => d * math.pi / 180;

    Paint p(Color col) => Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..isAntiAlias = true;

    canvas.drawArc(rect, rad(-150), rad(105), false, p(_red));
    canvas.drawArc(rect, rad(135), rad(75), false, p(_yellow));
    canvas.drawArc(rect, rad(45), rad(90), false, p(_green));
    canvas.drawArc(rect, rad(-2), rad(47), false, p(_blue));

    // horizontal bar of the "G"
    canvas.drawRect(
      Rect.fromLTRB(c.dx, c.dy - stroke * 0.5, c.dx + r + stroke / 2, c.dy + stroke * 0.5),
      Paint()..color = _blue..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
