import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'brand.dart';
import 'tokens.dart';

/// Brand intro shown once over [child] when the app starts (about 2.3 s):
/// the gold Mukafaah coin pops in with a soft glow, "Mukafaah" is typed letter
/// by letter with a yellow caret, the Arabic name fades in, then the intro
/// fades and scales away to reveal the app. A tap skips it. With reduced motion
/// the logo shows for 400 ms with no typing.
///
/// Use it in `MaterialApp.router(builder: (c, child) => MkIntroGate(child: child!))`.
class MkIntroGate extends StatefulWidget {
  const MkIntroGate({required this.child, this.enabled = true, super.key});

  final Widget child;

  /// False skips the intro entirely (tests, deep links).
  final bool enabled;

  @override
  State<MkIntroGate> createState() => _MkIntroGateState();
}

class _MkIntroGateState extends State<MkIntroGate> with SingleTickerProviderStateMixin {
  static const _word = 'Mukafaah';
  static const _arabic = 'مكافأة';
  static const _totalMs = 2300;

  // Timeline, as fractions of the whole intro.
  static const _typeStart = 0.22;
  static const _typeEnd = 0.60;
  static const _exitStart = 0.80;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _totalMs),
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
    _reduced = MediaQuery.disableAnimationsOf(context);
    if (_reduced) {
      _timer = Timer(const Duration(milliseconds: 400), _finish);
    } else {
      _c.forward();
    }
  }

  void _finish() {
    if (mounted && !_done) setState(() => _done = true);
  }

  void _skip() {
    if (_done) return;
    if (_reduced) {
      _timer?.cancel();
      _finish();
      return;
    }
    if (_c.value < _exitStart) _c.forward(from: _exitStart);
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
      alignment: Alignment.center,
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
                child: _reduced
                    ? const _IntroFrame(logo: 1, letters: _word.length, fade: 0, arabic: 1, exit: 0, ring: 0, caretOn: false)
                    : AnimatedBuilder(
                        animation: _c,
                        builder: (context, _) {
                          final t = _c.value;
                          double seg(double a, double b, [Curve curve = Curves.linear]) =>
                              curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));
                          final typed = seg(_typeStart, _typeEnd) * _word.length;
                          final letters = typed.floor().clamp(0, _word.length);
                          final elapsedMs = (t * _totalMs).round();
                          return _IntroFrame(
                            logo: seg(0.04, 0.30, Curves.easeOutBack),
                            ring: seg(0.10, 0.55, Curves.easeOutCubic),
                            letters: letters,
                            fade: letters >= _word.length ? 0 : typed - letters,
                            arabic: seg(0.58, 0.74, Curves.easeOutCubic),
                            exit: seg(_exitStart, 1, Curves.easeInCubic),
                            // Solid while typing, then a slow blink.
                            caretOn: t < _typeEnd || (elapsedMs ~/ 420).isEven,
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

/// One frame of the intro. All values are 0..1 except [letters].
class _IntroFrame extends StatelessWidget {
  const _IntroFrame({
    required this.logo,
    required this.letters,
    required this.fade,
    required this.arabic,
    required this.exit,
    required this.ring,
    required this.caretOn,
  });

  final double logo;
  final int letters;

  /// Opacity of the letter being typed right now.
  final double fade;
  final double arabic;
  final double exit;
  final double ring;
  final bool caretOn;

  @override
  Widget build(BuildContext context) {
    const word = _MkIntroGateState._word;
    final base = Theme.of(context).textTheme.displaySmall ?? const TextStyle(fontSize: 34);
    final wordStyle = base.copyWith(
      color: Colors.white,
      fontSize: 40,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.6,
      height: 1.1,
      decoration: TextDecoration.none,
    );
    final hidden = wordStyle.copyWith(color: Colors.transparent);
    final caret = Container(
      width: 3,
      height: 38,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: caretOn ? MkColors.yellow500 : Colors.transparent,
        borderRadius: MkRadius.all(2),
        boxShadow: caretOn ? const [BoxShadow(color: Color(0x88FBD404), blurRadius: 10)] : null,
      ),
    );
    final logoScale = 0.55 + 0.45 * logo;

    return Opacity(
      opacity: (1 - exit).clamp(0.0, 1.0),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.25),
            radius: 1.15,
            colors: [MkColors.purple700, MkColors.purple900],
            stops: [0, 0.75],
          ),
        ),
        child: DefaultTextStyle(
          style: wordStyle,
          child: Transform.scale(
            scale: 1 + 0.12 * exit,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 220,
                    height: 180,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Soft glow behind the coin.
                        Opacity(
                          opacity: logo.clamp(0.0, 1.0),
                          child: Container(
                            width: 200,
                            height: 200,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(colors: [Color(0x66FBD404), Color(0x00FBD404)]),
                            ),
                          ),
                        ),
                        // A ring that ripples out once as the coin lands.
                        CustomPaint(size: const Size(220, 180), painter: _RingPainter(ring)),
                        Opacity(
                          opacity: logo.clamp(0.0, 1.0),
                          child: Transform.scale(scale: logoScale, child: const MkCoin(size: 96)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: MkSpace.sm),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: word.substring(0, letters)),
                        if (letters < word.length)
                          TextSpan(
                            text: word.substring(letters, letters + 1),
                            style: wordStyle.copyWith(color: Colors.white.withValues(alpha: fade.clamp(0.0, 1.0))),
                          ),
                        WidgetSpan(alignment: PlaceholderAlignment.middle, child: caret),
                        if (letters + 1 < word.length) TextSpan(text: word.substring(letters + 1), style: hidden),
                      ],
                    ),
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.center,
                    style: wordStyle,
                  ),
                  const SizedBox(height: MkSpace.xs),
                  Opacity(
                    opacity: arabic.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, 10 * (1 - arabic)),
                      child: Text(
                        _MkIntroGateState._arabic,
                        textDirection: TextDirection.rtl,
                        style: wordStyle.copyWith(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                          color: MkColors.yellow500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    final c = size.center(Offset.zero);
    final r = 46 + 64 * t;
    final alpha = (1 - t) * 0.55;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 + 4 * (1 - t)
        ..color = MkColors.yellow500.withValues(alpha: alpha),
    );
    // A few sparks riding the ring.
    final spark = Paint()..color = Colors.white.withValues(alpha: alpha);
    for (var i = 0; i < 6; i++) {
      final a = i * math.pi / 3 + t * 0.8;
      canvas.drawCircle(c + Offset(math.cos(a) * r, math.sin(a) * r), 2.2 * (1 - t) + 0.6, spark);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t;
}
