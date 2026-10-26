import 'package:flutter/material.dart';

import '../core/constants/app_strings.dart';

/// The DoseMate mark, "Care Heart": two capsules leaning together into a
/// heart, white and teal on the brand violet tile. Brand colours are fixed,
/// so the logo looks the same in light and dark mode. Every screen uses this
/// one widget; the launcher icons are drawn from the same geometry.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32});

  final double size;

  /// Brand colours: violet, white and teal.
  static const violet = Color(0xFF8B80D9);
  static const white = Color(0xFFFFFFFF);
  static const teal = Color(0xFF5BAA9B);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: AppStrings.appName,
      child: CustomPaint(
        size: Size.square(size),
        painter: const _CareHeartPainter(),
      ),
    );
  }
}

class _CareHeartPainter extends CustomPainter {
  const _CareHeartPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Offset.zero & Size.square(side),
        Radius.circular(side * 0.28),
      ),
      Paint()..color = AppLogo.violet,
    );
    // The mark is drawn on a 100-unit grid filling 5/6 of the tile.
    final unit = side * (5 / 6) / 100;
    final inset = side / 12;
    Offset at(double x, double y) => Offset(inset + x * unit, inset + y * unit);
    final capsule = Paint()
      ..strokeWidth = 24 * unit
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(at(50, 72), at(32, 40), capsule..color = AppLogo.white)
      ..drawLine(at(50, 72), at(68, 40), capsule..color = AppLogo.teal);
  }

  @override
  bool shouldRepaint(_CareHeartPainter oldDelegate) => false;
}
