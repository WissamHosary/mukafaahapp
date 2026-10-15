import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'coin.dart';
import 'tokens.dart';

const _pkg = 'mk_ui';

/// The Mukafaah logo. [onDark] uses the white wordmark variant.
class MkLogo extends StatelessWidget {
  const MkLogo({this.height = 96, this.onDark = false, this.markOnly = false, super.key});

  final double height;
  final bool onDark;
  final bool markOnly;

  @override
  Widget build(BuildContext context) {
    final file = markOnly
        ? 'assets/brand/logo_mark.png'
        : onDark
            ? 'assets/brand/logo_full_on_dark.png'
            : 'assets/brand/logo_full.png';
    return Semantics(
      label: 'Mukafaah',
      image: true,
      child: Image.asset(file, package: _pkg, height: height, filterQuality: FilterQuality.medium),
    );
  }
}

/// A gold coin with the Mukafaah mark, used as the points symbol.
class MkCoin extends StatelessWidget {
  const MkCoin({this.size = 28, super.key});

  final double size;

  /// The Mukafaah "M" coin (see paintMukafaahCoin).
  @override
  Widget build(BuildContext context) {
    final coin = MkMCoin(size: size);
    if (size <= 40) return coin;
    return DecoratedBox(decoration: const BoxDecoration(shape: BoxShape.circle, boxShadow: MkShadow.glow), child: coin);
  }
}

/// Decorative swirl background used on hero surfaces (echoes the yellow
/// squiggles in the brand posts). Purely visual.
class MkSwirlBackground extends StatelessWidget {
  const MkSwirlBackground({required this.child, this.color = MkColors.purple900, super.key});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _SwirlPainter(color), child: child);
  }
}

class _SwirlPainter extends CustomPainter {
  _SwirlPainter(this.bg);

  final Color bg;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [MkColors.purple500.withValues(alpha: 0.55), Colors.transparent],
      ).createShader(Rect.fromCircle(center: Offset(size.width * 0.9, size.height * 0.1), radius: size.width * 0.8));
    canvas.drawRect(Offset.zero & size, glow);
    final p = Paint()
      ..color = MkColors.yellow500.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    void squiggle(Offset o, double s, double rot) {
      canvas.save();
      canvas.translate(o.dx, o.dy);
      canvas.rotate(rot);
      final path = Path()..moveTo(0, 0);
      for (var i = 0; i < 3; i++) {
        path.relativeQuadraticBezierTo(s * 0.5, -s * 0.6, s, 0);
      }
      canvas.drawPath(path, p);
      canvas.restore();
    }

    squiggle(Offset(size.width * 0.08, size.height * 0.18), 14, -0.4);
    squiggle(Offset(size.width * 0.78, size.height * 0.82), 12, 0.5);
    final dot = Paint()..color = MkColors.yellow500.withValues(alpha: 0.9);
    canvas.drawCircle(Offset(size.width * 0.86, size.height * 0.2), 4, dot);
    canvas.drawCircle(Offset(size.width * 0.15, size.height * 0.85), 3, dot);
    final ring = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 26;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(size.width * 1.05, size.height * 1.1), radius: size.width * 0.55),
      math.pi,
      math.pi / 2,
      false,
      ring,
    );
  }

  @override
  bool shouldRepaint(_SwirlPainter old) => old.bg != bg;
}
