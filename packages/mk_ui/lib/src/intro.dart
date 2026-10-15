import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'coin.dart';
import 'tokens.dart';

part 'intro_logo_data.dart';

/// Brand intro shown once over [child] when the app starts (about 3.2 s).
///
/// It builds the real Mukafaah logo piece by piece:
///  1. two sparks trace the outline of the yellow mark from the hook tip and
///     meet on the far side;
///  2. liquid gold rises inside the mark; when it is full the mark breathes
///     once, golden rays open behind it and Mukafaah coins spring out,
///     flip and tumble away;
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
  // 2. Liquid gold fills the mark, then rays and a burst of coins.
  static const fillStart = 760.0;
  static const fillEnd = 1180.0;
  static const burstEnd = 1900.0;
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

/// Coins that spring out of the mark: angle (deg), distance, size, half-turns, delay (0..1).
const _coins = [
  (-152.0, 330.0, 40.0, 3.0, 0.0),
  (-120.0, 360.0, 48.0, 4.0, 0.05),
  (-90.0, 300.0, 36.0, 3.0, 0.12),
  (-60.0, 365.0, 46.0, 5.0, 0.02),
  (-28.0, 330.0, 40.0, 3.0, 0.08),
  (-174.0, 270.0, 30.0, 2.0, 0.16),
  (-6.0, 280.0, 30.0, 2.0, 0.14),
];

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
  late final Rect markBounds = mark.getBounds();

  /// The coin drawn once; the burst only moves and squeezes it.
  late final ui.Image coin = () {
    final rec = ui.PictureRecorder();
    paintMukafaahCoin(Canvas(rec), const Offset(64, 64), 62);
    final pic = rec.endRecording();
    final img = pic.toImageSync(128, 128);
    pic.dispose();
    return img;
  }();
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
    final land = _seg(ms, _T.fillEnd - 40, _T.burstEnd);
    final rays = _seg(ms, _T.fillEnd - 60, _T.burstEnd + 150, Curves.easeOutCubic);
    const c = _markCentre;

    // A soft glow that blooms with the fill and stays behind the mark.
    if (fill > 0) {
      canvas.drawCircle(
        c,
        260,
        Paint()
          ..shader = ui.Gradient.radial(c, 260, [
            _yellow.withValues(alpha: 0.16 * fill),
            _yellow.withValues(alpha: 0),
          ]),
      );
    }

    // Golden rays open behind the full mark and turn slowly as they fade.
    if (rays > 0 && rays < 1) {
      final fade = 1 - _seg(ms, _T.fillEnd + 300, _T.burstEnd + 150, Curves.easeInOutSine);
      final rot = rays * 0.35;
      final path = Path();
      for (var i = 0; i < 18; i++) {
        final a = rot + i * math.pi * 2 / 18;
        final len = (i.isOdd ? 150 : 230) * rays + 110;
        final w = i.isOdd ? 0.035 : 0.055;
        path
          ..moveTo(c.dx + math.cos(a - w) * 100, c.dy + math.sin(a - w) * 100)
          ..lineTo(c.dx + math.cos(a) * len, c.dy + math.sin(a) * len)
          ..lineTo(c.dx + math.cos(a + w) * 100, c.dy + math.sin(a + w) * 100)
          ..close();
      }
      canvas
        ..drawPath(
          path,
          Paint()
            ..shader = ui.Gradient.radial(c, 120 + 230 * rays, [_yellow.withValues(alpha: 0.55 * fade), _yellow.withValues(alpha: 0)], [90 / (120 + 230 * rays), 1]),
        )
        ..drawCircle(
          c,
          160 + 150 * rays,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = _yellow.withValues(alpha: 0.5 * (1 - rays)),
        );
    }

    // Mukafaah coins spring out from behind the mark, flip and fall away.
    if (land > 0 && land < 1) {
      final img = art.coin;
      final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
      for (final (deg, dist, size, spin, delay) in _coins) {
        final u = ((land - delay) / (1 - delay)).clamp(0.0, 1.0);
        if (u <= 0 || u >= 1) continue;
        final a = deg * math.pi / 180;
        final e = Curves.easeOutCubic.transform(u);
        final x = c.dx + math.cos(a) * dist * e;
        final y = c.dy + math.sin(a) * dist * e + 260 * u * u;
        final turn = math.cos(u * math.pi * spin);
        final pop = math.min(1.0, u / 0.18);
        final alpha = 1 - _seg(u, 0.62, 1);
        canvas
          ..save()
          ..translate(x, y)
          ..rotate((deg + 90) * math.pi / 180 * 0.25 * u)
          ..scale(math.max(0.08, turn.abs()) * pop, pop);
        if (turn.abs() < 0.45) {
          canvas.drawRect(Rect.fromLTWH(-size * 0.1, -size, size * 0.2, size * 2), Paint()..color = const Color(0xFFB27E00).withValues(alpha: alpha));
        }
        canvas
          ..drawImageRect(img, src, Rect.fromCircle(center: Offset.zero, radius: size), Paint()..color = Color.fromRGBO(255, 255, 255, alpha)..filterQuality = FilterQuality.medium)
          ..restore();
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

    // Liquid gold rising inside the mark, then the full mark breathing once.
    if (fill > 0) {
      final breathe = 1 +
          0.085 * math.sin(math.pi * _seg(ms, _T.fillEnd - 80, _T.fillEnd + 260, Curves.easeOutCubic)) -
          0.025 * math.sin(math.pi * _seg(ms, _T.fillEnd + 260, _T.fillEnd + 520));
      canvas
        ..save()
        ..translate(c.dx, c.dy)
        ..scale(breathe)
        ..translate(-c.dx, -c.dy);
      if (fill < 1) {
        final b = art.markBounds;
        final level = b.bottom - (b.height + 30) * fill;
        final amp = 10 * (1 - fill);
        final wave = Path()..moveTo(b.left - 20, b.bottom + 20);
        for (var x = b.left - 20; x <= b.right + 20; x += 12) {
          wave.lineTo(x, level + math.sin(x * 0.028 + ms * 0.014) * amp + math.sin(x * 0.061 - ms * 0.009) * amp * 0.5);
        }
        wave
          ..lineTo(b.right + 20, b.bottom + 20)
          ..close();
        canvas
          ..save()
          ..clipPath(art.mark)
          ..drawPath(
            wave,
            Paint()
              ..shader = ui.Gradient.linear(
                Offset(0, level),
                Offset(0, b.bottom),
                [const Color(0xFFFFE680), _yellow, const Color(0xFFE5AE00)],
                [0, 0.25, 1],
              ),
          )
          ..restore();
      } else {
        canvas.drawPath(art.mark, Paint()..color = _yellow);
      }
      canvas.restore();
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

  @override
  bool shouldRepaint(_LogoPainter old) => old.ms != ms;
}
