import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// Fade + rise entrance. Use [index] inside lists for a short stagger.
class MkEntrance extends StatefulWidget {
  const MkEntrance({required this.child, this.index = 0, this.offset = 14, super.key});

  final Widget child;
  final int index;
  final double offset;

  @override
  State<MkEntrance> createState() => _MkEntranceState();
}

class _MkEntranceState extends State<MkEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: MkMotion.slow);
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: MkMotion.enter);

  @override
  void initState() {
    super.initState();
    final delay = MkMotion.stagger * widget.index.clamp(0, 10);
    Future<void>.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: _t,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _t.value,
        child: Transform.translate(offset: Offset(0, (1 - _t.value) * widget.offset), child: child),
      ),
    );
  }
}

/// Subtle press feedback: scales down slightly while pressed.
class MkPressable extends StatefulWidget {
  const MkPressable({required this.child, this.onTap, this.scale = 0.97, super.key});

  final Widget child;
  final VoidCallback? onTap;
  final double scale;

  @override
  State<MkPressable> createState() => _MkPressableState();
}

class _MkPressableState extends State<MkPressable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: MkMotion.fast,
        curve: MkMotion.standard,
        child: widget.child,
      ),
    );
  }
}

/// Counts smoothly from the previous value to [value]. Display only: the value
/// always comes from the server.
class AnimatedPoints extends StatelessWidget {
  const AnimatedPoints({required this.value, this.style, this.format, super.key});

  final int value;
  final TextStyle? style;
  final String Function(int)? format;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.toDouble()),
      duration: MkMotion.count,
      curve: MkMotion.enter,
      builder: (context, v, _) {
        final n = v.round();
        return Text(
          format?.call(n) ?? n.toString(),
          style: style,
          textDirection: TextDirection.ltr,
          maxLines: 1,
        );
      },
    );
  }
}

/// Animated check mark for success moments.
class MkSuccessMark extends StatefulWidget {
  const MkSuccessMark({this.size = 96, this.color = MkColors.success, super.key});

  final double size;
  final Color color;

  @override
  State<MkSuccessMark> createState() => _MkSuccessMarkState();
}

class _MkSuccessMarkState extends State<MkSuccessMark> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(painter: _CheckPainter(_c.value, widget.color)),
      ),
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final circleT = Curves.easeOutBack.transform((t / 0.55).clamp(0.0, 1.0));
    canvas.drawCircle(c, r * circleT, Paint()..color = color.withValues(alpha: 0.14));
    canvas.drawCircle(c, r * 0.72 * circleT, Paint()..color = color);
    final checkT = Curves.easeOutCubic.transform(((t - 0.4) / 0.6).clamp(0.0, 1.0));
    if (checkT <= 0) return;
    final p1 = Offset(size.width * 0.34, size.height * 0.52);
    final p2 = Offset(size.width * 0.45, size.height * 0.63);
    final p3 = Offset(size.width * 0.67, size.height * 0.40);
    final path = Path()..moveTo(p1.dx, p1.dy);
    final first = (checkT / 0.4).clamp(0.0, 1.0);
    path.lineTo(p1.dx + (p2.dx - p1.dx) * first, p1.dy + (p2.dy - p1.dy) * first);
    if (checkT > 0.4) {
      final second = ((checkT - 0.4) / 0.6).clamp(0.0, 1.0);
      path.lineTo(p2.dx + (p3.dx - p2.dx) * second, p2.dy + (p3.dy - p2.dy) * second);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.075
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.t != t;
}

/// Slow ambient float used for the coin/gift accents.
class MkFloat extends StatefulWidget {
  const MkFloat({required this.child, this.amplitude = 6, super.key});

  final Widget child;
  final double amplitude;

  @override
  State<MkFloat> createState() => _MkFloatState();
}

class _MkFloatState extends State<MkFloat> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 3))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, (Curves.easeInOut.transform(_c.value) - 0.5) * 2 * widget.amplitude),
        child: child,
      ),
    );
  }
}
