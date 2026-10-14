import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

part 'intro_logo_data.dart';

/// Brand intro shown once over [child] when the app starts (about 3.2 s).
///
/// It builds the real Mukafaah logo piece by piece:
///  1. two sparks trace the outline of the yellow mark from the hook tip and
///     meet on the far side;
///  2. the mark fills with yellow and pops, sending out a ripple and sparkles;
///  3. the Arabic name is revealed right to left, the way it is read, and its
///     dots and hamza drop into place one by one;
///  4. MUKAFAAH rises letter by letter;
///  5. a light sweeps across the whole logo, then the intro fades into the app.
///
/// A tap skips straight to the fade. With reduced motion the finished logo is
/// shown for 600 ms with no animation.
///
/// Use it in `MaterialApp.router(builder: (c, child) => MkIntroGate(child: child!))`.
class MkIntroGate extends StatefulWidget {
  const MkIntroGate({required this.child, this.enabled = true, super.key});

  final Widget child;

  /// False skips the intro entirely (tests, deep links).
  final bool enabled;

  /// True while the intro covers the screen, so things like the fingerprint
  /// prompt can wait until it is gone.
  static final ValueNotifier<bool> playing = ValueNotifier<bool>(false);

  @override
  State<MkIntroGate> createState() => _MkIntroGateState();
}

class _MkIntroGateState extends State<MkIntroGate> with SingleTickerProviderStateMixin {
  /// The logo is complete at this point; after it the intro fades out.
  static const _showMs = _T.end;
  static const _exitMs = 450.0;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_showMs + _exitMs).round()),
  );
  Timer? _timer;
  bool _done = false;
  bool _started = false;
  bool _reduced = false;

  @override
  void initState() {
    super.initState();
    _done = !widget.enabled;
    _c.addStatusListener((st) {
      if (st == AnimationStatus.completed) _finish();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || _done) return;
    _started = true;
    MkIntroGate.playing.value = true;
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced) {
      _timer = Timer(const Duration(milliseconds: 600), _finish);
    } else {
      _c.forward();
    }
  }

  void _finish() {
    MkIntroGate.playing.value = false;
    if (mounted && !_done) setState(() => _done = true);
  }

  void _skip() {
    if (_done) return;
    if (_reduced) {
      _timer?.cancel();
      _finish();
      return;
    }
    final exitAt = _showMs / (_showMs + _exitMs);
    if (_c.value < exitAt) _c.forward(from: exitAt);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_done)
          Positioned.fill(
            child: Semantics(
              label: 'Mukafaah',
              button: true,
              onTap: _skip,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _skip,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) {
                    final ms = _reduced ? _showMs : _c.value * (_showMs + _exitMs);
                    final exit = Curves.easeInCubic.transform(((ms - _showMs) / _exitMs).clamp(0.0, 1.0));
                    return Opacity(
                      opacity: 1 - exit,
                      child: ColoredBox(
                        color: _bg,
                        child: Transform.scale(
                          scale: 1 + 0.08 * exit,
                          child: CustomPaint(painter: _LogoPainter(ms), size: Size.infinite),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

const _bg = Color(0xFFFBFAFD);
const _yellow = MkColors.yellow500;
const _purple = MkColors.purple900;

/// The intro timeline, in milliseconds.
abstract final class _T {
  // 1. Sparks trace the mark's outline.
  static const traceStart = 0.0;
  static const traceEnd = 900.0;
  // 2. The mark fills and pops.
  static const fillStart = 760.0;
  static const fillEnd = 1180.0;
  static const popEnd = 1300.0;
  static const rippleEnd = 1560.0;
  // 3. Arabic name, right to left, then its dots.
  static const arabicStart = 1040.0;
  static const arabicEnd = 1720.0;
  static const dotsStart = 1540.0;
  static const dotGap = 85.0;
  static const dotDur = 420.0;
  // 4. MUKAFAAH, letter by letter.
  static const latinStart = 1420.0;
  static const latinGap = 80.0;
  static const latinDur = 420.0;
  // 5. A light sweeps across.
  static const shineStart = 2200.0;
  static const shineEnd = 2800.0;
  static const end = 3150.0;
}

double _seg(double ms, double a, double b, [Curve curve = Curves.linear]) =>
    curve.transform(((ms - a) / (b - a)).clamp(0.0, 1.0));

/// The logo artwork is 600 x 606; the mark's centre is about here.
const _markCentre = Offset(296, 148);

class _Shape {
  const _Shape(this.contours, this.bounds);

  /// Each contour is x, y pairs. The first is the outline, any others are holes.
  final List<List<double>> contours;

  /// left, top, right, bottom
  final List<double> bounds;
}

/// Turns traced points into a smooth closed path: a quadratic curve through
/// the midpoints of each pair of points.
void _addContour(Path path, List<double> p) {
  final n = p.length ~/ 2;
  Offset at(int i) => Offset(p[(i % n) * 2], p[(i % n) * 2 + 1]);
  Offset mid(int i) => Offset.lerp(at(i), at(i + 1), 0.5)!;
  final start = mid(n - 1);
  path.moveTo(start.dx, start.dy);
  for (var i = 0; i < n; i++) {
    final c = at(i);
    final m = mid(i);
    path.quadraticBezierTo(c.dx, c.dy, m.dx, m.dy);
  }
  path.close();
}

Path _pathOf(_Shape s) {
  final path = Path()..fillType = ui.PathFillType.evenOdd;
  for (final c in s.contours) {
    _addContour(path, c);
  }
  return path;
}

/// Paths are built once and reused for every frame.
final class _Art {
  _Art._();
  static final instance = _Art._();

  final Path mark = _pathOf(_mark.first);
  late final Path markOutline = Path().._addOutline(_mark.first.contours.first);
  late final ui.PathMetric outlineMetric = markOutline.computeMetrics().first;
  final List<Path> arabicBody = _arabicBody.map(_pathOf).toList();
  final List<Path> arabicDots = _arabicDots.map(_pathOf).toList();
  final List<Path> latin = _latin.map(_pathOf).toList();

  late final Path all = () {
    final p = Path()..fillType = ui.PathFillType.evenOdd;
    for (final x in [mark, ...arabicBody, ...arabicDots, ...latin]) {
      p.addPath(x, Offset.zero);
    }
    return p;
  }();
}

extension on Path {
  void _addOutline(List<double> points) => _addContour(this, points);
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.ms);

  /// Time since the intro started.
  final double ms;

  static const _artW = 600.0;
  static const _artH = 606.0;

  @override
  void paint(Canvas canvas, Size size) {
    final art = _Art.instance;
    final w = math.min(size.width * 0.72, 320.0);
    final k = w / _artW;

    canvas
      ..save()
      ..translate(size.width / 2, size.height * 0.47)
      ..scale(k)
      ..translate(-_artW / 2, -_artH / 2);

    _paintMark(canvas, art);
    _paintArabic(canvas, art);
    _paintLatin(canvas, art);
    _paintShine(canvas, art);

    canvas.restore();
  }

  void _paintMark(Canvas canvas, _Art art) {
    final trace = _seg(ms, _T.traceStart, _T.traceEnd, Curves.easeInOutCubic);
    final fill = _seg(ms, _T.fillStart, _T.fillEnd, Curves.easeOutCubic);
    final pop = math.sin(math.pi * _seg(ms, _T.fillStart, _T.popEnd));
    final ripple = _seg(ms, _T.fillStart + 80, _T.rippleEnd, Curves.easeOutCubic);

    // A soft glow that blooms with the fill and stays behind the mark.
    if (fill > 0) {
      canvas.drawCircle(
        _markCentre,
        250,
        Paint()
          ..shader = ui.Gradient.radial(_markCentre, 250, [
            _yellow.withValues(alpha: 0.14 * fill),
            _yellow.withValues(alpha: 0),
          ]),
      );
    }

    // Ripple ring and sparkles as the mark lands.
    if (ripple > 0 && ripple < 1) {
      final fade = 1 - ripple;
      canvas.drawCircle(
        _markCentre,
        150 + 190 * ripple,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 + 7 * fade
          ..color = _yellow.withValues(alpha: 0.55 * fade),
      );
      for (var i = 0; i < 10; i++) {
        final a = (i * 36 + 18) * math.pi / 180;
        final d = 165 + 175 * ripple;
        final c = _markCentre + Offset(math.cos(a) * d, math.sin(a) * d * 0.9);
        _sparkle(canvas, c, 9 * fade + 1, (i.isEven ? _yellow : _purple).withValues(alpha: fade * (i.isEven ? 1 : 0.55)));
      }
    }

    // The outline being traced from the hook tip by two sparks.
    if (trace > 0 && fill < 1) {
      final m = art.outlineMetric;
      final len = m.length;
      final half = trace * len / 2;
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round
        ..color = _yellow.withValues(alpha: 1 - fill);
      canvas
        ..drawPath(m.extractPath(0, half), stroke)
        ..drawPath(m.extractPath(len - half, len), stroke);
      if (trace < 1) {
        for (final at in [half, len - half]) {
          final p = m.getTangentForOffset(at)?.position;
          if (p == null) continue;
          canvas
            ..drawCircle(p, 22, Paint()..color = _yellow.withValues(alpha: 0.35)..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 10))
            ..drawCircle(p, 9, Paint()..color = _yellow)
            ..drawCircle(p, 4.5, Paint()..color = Colors.white);
        }
      }
    }

    // The filled mark, popping slightly as it lands.
    if (fill > 0) {
      canvas
        ..save()
        ..translate(_markCentre.dx, _markCentre.dy)
        ..scale(1 + 0.07 * pop)
        ..translate(-_markCentre.dx, -_markCentre.dy)
        ..drawPath(art.mark, Paint()..color = _yellow.withValues(alpha: fill))
        ..restore();
    }
  }

  void _paintArabic(Canvas canvas, _Art art) {
    final p = _seg(ms, _T.arabicStart, _T.arabicEnd, Curves.easeInOutCubic);
    if (p > 0) {
      const feather = 70.0;
      // The reveal edge moves from the right of the word to the left.
      final edge = _artW + feather - (_artW + 2 * feather) * p;
      const bounds = Rect.fromLTRB(0, 300, _artW, 520);
      canvas
        ..saveLayer(bounds, Paint())
        ..translate(0, 12 * (1 - p));
      final ink = Paint()..color = _purple;
      for (final path in art.arabicBody) {
        canvas.drawPath(path, ink);
      }
      canvas
        ..translate(0, -12 * (1 - p))
        ..drawRect(
          bounds,
          Paint()
            ..blendMode = ui.BlendMode.dstIn
            ..shader = ui.Gradient.linear(
              Offset(edge - feather, 0),
              Offset(edge + feather, 0),
              [const Color(0x00000000), const Color(0xFF000000)],
            ),
        )
        ..restore();
    }

    for (var i = 0; i < art.arabicDots.length; i++) {
      final start = _T.dotsStart + i * _T.dotGap;
      final d = _seg(ms, start, start + _T.dotDur, Curves.easeOutBack);
      final o = _seg(ms, start, start + _T.dotDur * 0.5);
      if (o <= 0) continue;
      canvas
        ..save()
        ..translate(0, -40 * (1 - d))
        ..drawPath(art.arabicDots[i], Paint()..color = _purple.withValues(alpha: o))
        ..restore();
    }
  }

  void _paintLatin(Canvas canvas, _Art art) {
    for (var i = 0; i < art.latin.length; i++) {
      final start = _T.latinStart + i * _T.latinGap;
      final q = _seg(ms, start, start + _T.latinDur, Curves.easeOutBack);
      final o = _seg(ms, start, start + _T.latinDur * 0.6);
      if (o <= 0) continue;
      canvas
        ..save()
        ..translate(0, 28 * (1 - q))
        ..drawPath(art.latin[i], Paint()..color = _purple.withValues(alpha: o))
        ..restore();
    }
  }

  /// A light band sweeping across the finished logo, only over its shapes.
  void _paintShine(Canvas canvas, _Art art) {
    final s = _seg(ms, _T.shineStart, _T.shineEnd, Curves.easeInOutSine);
    if (s <= 0 || s >= 1) return;
    const bounds = Rect.fromLTRB(-20, -20, _artW + 20, _artH + 20);
    final x = -260 + (_artW + 520) * s;
    // Tilted about 20 degrees.
    const tilt = 0.36;
    canvas
      ..saveLayer(bounds, Paint())
      ..drawPath(art.all, Paint()..color = Colors.white)
      ..drawRect(
        bounds,
        Paint()
          ..blendMode = ui.BlendMode.srcIn
          ..shader = ui.Gradient.linear(
            Offset(x - 70, -70 * tilt),
            Offset(x + 70, 70 * tilt),
            [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.6), Colors.white.withValues(alpha: 0)],
            [0, 0.5, 1],
          ),
      )
      ..restore();
  }

  /// A small four-pointed star.
  void _sparkle(Canvas canvas, Offset c, double r, Color color) {
    final p = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r)
      ..close();
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LogoPainter old) => old.ms != ms;
}
