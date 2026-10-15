import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

/// The Mukafaah coin: a gold coin with a ridged rim and an embossed "M".
///
/// Drawn with vector paths so it is sharp at any size. The falling coins
/// ([MkCoinRain]) draw it once into a small bitmap and then only move and
/// squeeze that bitmap, which keeps the animation cheap on any phone.
void paintMukafaahCoin(Canvas canvas, Offset c, double r) {
  final rect = Rect.fromCircle(center: c, radius: r);
  // Rim.
  canvas.drawCircle(
    c,
    r,
    Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFFE680), Color(0xFFE5AE00), Color(0xFFA06F00)],
        stops: [0, 0.55, 1],
      ).createShader(rect),
  );
  // Ridges around the rim (only where they can be seen).
  if (r >= 10) {
    final ridge = Paint()
      ..color = const Color(0x55704C00)
      ..strokeWidth = math.max(0.6, r * 0.035);
    const n = 44;
    for (var i = 0; i < n; i++) {
      final a = i / n * math.pi * 2;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + d * (r * 0.9), c + d * (r * 0.985), ridge);
    }
  }
  // Face.
  final face = r * 0.82;
  canvas.drawCircle(
    c,
    face,
    Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.35, -0.4),
        radius: 1.05,
        colors: [Color(0xFFFFF5BC), Color(0xFFFBD404), Color(0xFFD69E00)],
        stops: [0, 0.5, 1],
      ).createShader(Rect.fromCircle(center: c, radius: face)),
  );
  // Thin inner ring.
  canvas.drawCircle(
    c,
    r * 0.73,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.6, r * 0.035)
      ..color = const Color(0x66A06F00),
  );
  // Embossed "M": light edge up-left, dark edge down-right, then the letter.
  final m = _mPath(c, r * 0.5);
  canvas
    ..drawPath(m.shift(Offset(-r * 0.035, -r * 0.035)), Paint()..color = const Color(0xCCFFF8D0))
    ..drawPath(m.shift(Offset(r * 0.045, r * 0.05)), Paint()..color = const Color(0xB0805500))
    ..drawPath(
      m,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF2C21A), Color(0xFFC98F00)],
        ).createShader(rect),
    );
  // Shine.
  canvas.drawOval(
    Rect.fromCenter(center: c + Offset(-r * 0.32, -r * 0.42), width: r * 0.75, height: r * 0.34),
    Paint()..color = const Color(0x40FFFFFF),
  );
}

/// A bold geometric "M" centred on [c], [s] = half its width.
Path _mPath(Offset c, double s) {
  const pts = [
    (-0.95, 0.82), (-0.95, -0.8), (-0.58, -0.8), (0.0, 0.04), (0.58, -0.8), (0.95, -0.8), //
    (0.95, 0.82), (0.58, 0.82), (0.58, -0.12), (0.08, 0.58), (-0.08, 0.58), (-0.58, -0.12), (-0.58, 0.82),
  ];
  final p = Path()..moveTo(c.dx + pts[0].$1 * s, c.dy + pts[0].$2 * s);
  for (final q in pts.skip(1)) {
    p.lineTo(c.dx + q.$1 * s, c.dy + q.$2 * s);
  }
  return p..close();
}

/// A single Mukafaah coin.
class MkMCoin extends StatelessWidget {
  const MkMCoin({this.size = 28, super.key});
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(dimension: size, child: CustomPaint(painter: _OneCoin()));
  }
}

class _OneCoin extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => paintMukafaahCoin(canvas, size.center(Offset.zero), size.shortestSide / 2);

  @override
  bool shouldRepaint(_OneCoin old) => false;
}

/// Mukafaah coins falling, flipping in 3D and catching the light now and then.
///
/// Light on purpose: the coin is drawn once into a bitmap; each frame only
/// moves, squeezes and fades that bitmap ([count] draws, no new shaders).
/// It stops when animations are off, and pauses while its tab is hidden.
class MkCoinRain extends StatefulWidget {
  const MkCoinRain({this.count = 12, this.opacity = 0.9, super.key});
  final int count;
  final double opacity;

  @override
  State<MkCoinRain> createState() => _MkCoinRainState();
}

class _MkCoinRainState extends State<MkCoinRain> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 40))..repeat();
  ui.Image? _coin;
  double _dpr = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dpr = MediaQuery.devicePixelRatioOf(context);
    if (dpr != _dpr) {
      _dpr = dpr;
      _coin?.dispose();
      _coin = _bake(dpr);
    }
  }

  /// Draws the coin once at 48 logical px.
  static ui.Image _bake(double dpr) {
    const logical = 48.0;
    final px = (logical * dpr).ceil();
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    paintMukafaahCoin(canvas, Offset(px / 2, px / 2), px / 2 - 1);
    final pic = rec.endRecording();
    final img = pic.toImageSync(px, px);
    pic.dispose();
    return img;
  }

  @override
  void dispose() {
    _c.dispose();
    _coin?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context) || _coin == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(child: CustomPaint(painter: _RainPainter(_c, _coin!, widget.count, widget.opacity), size: Size.infinite)),
    );
  }
}

class _Drop {
  _Drop(int i)
      : x = _r(i, 1),
        off = _r(i, 2),
        speed = 0.45 + _r(i, 3) * 0.8,
        size = 9 + _r(i, 4) * 13,
        spin = _r(i, 5) * 6.28,
        spinSpeed = 1.2 + _r(i, 6) * 2.4,
        sway = 6 + _r(i, 7) * 14,
        glint = _r(i, 8);
  final double x, off, speed, size, spin, spinSpeed, sway, glint;
  static double _r(int i, int k) => (math.sin(i * 12.9898 + k * 78.233) * 43758.5453).abs() % 1;
}

class _RainPainter extends CustomPainter {
  _RainPainter(this.anim, this.coin, int count, this.opacity)
      : drops = List.generate(count, _Drop.new),
        super(repaint: anim);
  final Animation<double> anim;
  final ui.Image coin;
  final List<_Drop> drops;
  final double opacity;

  static final _edge = Paint()..color = const Color(0xFFB27E00);
  static final _glint = Paint()..color = const Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value * 40;
    final src = Rect.fromLTWH(0, 0, coin.width.toDouble(), coin.height.toDouble());
    final paint = Paint()..filterQuality = FilterQuality.low;
    for (final d in drops) {
      final travel = size.height + 60;
      final y = (d.off * travel + t * 38 * d.speed) % travel - 30;
      final x = d.x * size.width + math.sin(t * 0.8 * d.speed + d.spin) * d.sway;
      final turn = math.cos(d.spin + t * d.spinSpeed);
      final squeeze = turn.abs().clamp(0.07, 1.0);
      // Fade in at the top, out at the bottom.
      final fade = (math.min(1.0, (y + 30) / 60) * math.min(1.0, (size.height - y) / 80)).clamp(0.0, 1.0);
      if (fade <= 0) continue;
      final r = d.size;
      canvas
        ..save()
        ..translate(x, y)
        ..rotate(math.sin(t * 0.6 + d.spin) * 0.35);
      // Coin thickness shows when it turns edge-on.
      if (squeeze < 0.5) {
        final w = r * 0.22 * (1 - squeeze * 2);
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(turn > 0 ? r * squeeze - w : -r * squeeze, -r, w, r * 2), Radius.circular(w)),
          _edge..color = const Color(0xFFB27E00).withValues(alpha: opacity * fade),
        );
      }
      paint.color = Color.fromRGBO(255, 255, 255, opacity * fade);
      canvas
        ..scale(squeeze, 1)
        ..drawImageRect(coin, src, Rect.fromCircle(center: Offset.zero, radius: r), paint)
        ..restore();
      // Now and then a coin facing us catches the light.
      final g = (t * 0.25 + d.glint) % 1;
      if (squeeze > 0.85 && g < 0.08) {
        final k = math.sin(g / 0.08 * math.pi);
        final p = Offset(x - r * 0.35, y - r * 0.45);
        final s = r * 0.55 * k;
        _glint.color = Color.fromRGBO(255, 255, 255, 0.9 * k * fade);
        canvas.drawPath(
          Path()
            ..moveTo(p.dx, p.dy - s)
            ..quadraticBezierTo(p.dx, p.dy, p.dx + s, p.dy)
            ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy + s)
            ..quadraticBezierTo(p.dx, p.dy, p.dx - s, p.dy)
            ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy - s)
            ..close(),
          _glint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_RainPainter old) => old.coin != coin || old.drops.length != drops.length;
}
