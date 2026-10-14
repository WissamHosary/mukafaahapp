import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'brand.dart';
import 'catalog_widgets.dart';
import 'motion.dart';
import 'tokens.dart';

/// A home banner made in Mukafaah Manager: purple, yellow or a photo, with a title,
/// a subtitle and an optional tap action. Text is drawn by the app, so it stays sharp
/// and works in Arabic and English.
class MkServerBanner extends StatelessWidget {
  const MkServerBanner({
    required this.style,
    this.title,
    this.subtitle,
    this.imageUrl,
    this.actionLabel,
    this.onTap,
    super.key,
  });

  /// PURPLE, YELLOW or IMAGE.
  final String style;
  final String? title;
  final String? subtitle;
  final String? imageUrl;

  /// Small call-to-action pill ("Open", "See offers"); hidden when null.
  final String? actionLabel;
  final VoidCallback? onTap;

  bool get _isImage => style == 'IMAGE' && imageUrl != null;
  bool get _isYellow => style == 'YELLOW';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fg = _isYellow ? MkColors.purple900 : Colors.white;
    final accent = _isYellow ? MkColors.purple900 : (_isImage ? Colors.white : MkColors.yellow500);
    final hasText = (title ?? '').isNotEmpty || (subtitle ?? '').isNotEmpty;

    final text = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(MkSpace.lg, MkSpace.md, MkSpace.md, MkSpace.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if ((title ?? '').isNotEmpty)
                  Text(
                    title!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.headlineSmall?.copyWith(color: accent, fontWeight: FontWeight.w900, height: 1.15),
                  ),
                if ((subtitle ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.bodySmall?.copyWith(color: fg.withValues(alpha: 0.88)),
                  ),
                ],
                if (actionLabel != null) ...[
                  const SizedBox(height: MkSpace.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _isYellow ? MkColors.purple900 : MkColors.yellow500,
                      borderRadius: MkRadius.all(MkRadius.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          actionLabel!,
                          style: t.labelMedium?.copyWith(color: _isYellow ? MkColors.yellow500 : MkColors.purple900),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Directionality.of(context) == TextDirection.rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                          size: 16,
                          color: _isYellow ? MkColors.yellow500 : MkColors.purple900,
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (!_isImage) ...[
            const SizedBox(width: MkSpace.sm),
            const MkFloat(child: _CoinStack()),
          ],
        ],
      ),
    );

    final Widget body;
    if (_isImage) {
      body = Stack(
        fit: StackFit.expand,
        children: [
          MkNetImage(url: imageUrl, cacheWidth: 1080),
          if (hasText)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.centerStart,
                  end: AlignmentDirectional.centerEnd,
                  colors: [Colors.black.withValues(alpha: 0.62), Colors.black.withValues(alpha: 0)],
                ),
              ),
            ),
          if (hasText || actionLabel != null) text,
        ],
      );
    } else if (_isYellow) {
      body = ColoredBox(color: MkColors.yellow500, child: _Sparkles(color: MkColors.purple900, child: text));
    } else {
      body = MkSwirlBackground(child: _Sparkles(color: MkColors.yellow500, child: text));
    }

    final shine = MkShine(child: body);
    if (onTap == null) return shine;
    return Semantics(button: true, label: title ?? subtitle, child: MkPressable(onTap: onTap, child: shine));
  }
}

/// Three stacked coins used on drawn banners.
class _CoinStack extends StatelessWidget {
  const _CoinStack();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 78,
      height: 78,
      child: Stack(
        children: [
          Positioned(right: 0, top: 2, child: MkCoin(size: 44)),
          Positioned(left: 4, top: 22, child: MkCoin(size: 34)),
          Positioned(right: 18, bottom: 0, child: MkCoin(size: 28)),
        ],
      ),
    );
  }
}

/// A few slowly twinkling dots behind banner content.
class _Sparkles extends StatefulWidget {
  const _Sparkles({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  State<_Sparkles> createState() => _SparklesState();
}

class _SparklesState extends State<_Sparkles> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 4));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SparklePainter(_c, widget.color),
      child: widget.child,
    );
  }
}

class _SparklePainter extends CustomPainter {
  _SparklePainter(this.anim, this.color) : super(repaint: anim);

  final Animation<double> anim;
  final Color color;
  static const _dots = [
    (0.55, 0.18, 3.0, 0.0),
    (0.68, 0.78, 2.0, 0.3),
    (0.82, 0.12, 2.5, 0.55),
    (0.46, 0.86, 2.0, 0.8),
    (0.93, 0.55, 3.0, 0.15),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    for (final (x, y, r, phase) in _dots) {
      final v = (math.sin((anim.value + phase) * 2 * math.pi) + 1) / 2;
      p.color = color.withValues(alpha: 0.15 + v * 0.45);
      canvas.drawCircle(Offset(x * size.width, y * size.height), r + v * 1.5, p);
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.color != color;
}

/// A soft light sweep that passes over its child every few seconds.
class MkShine extends StatefulWidget {
  const MkShine({required this.child, this.period = const Duration(seconds: 5), super.key});

  final Widget child;
  final Duration period;

  @override
  State<MkShine> createState() => _MkShineState();
}

class _MkShineState extends State<MkShine> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                // The sweep runs during the first 30% of each period, then rests.
                final v = (_c.value / 0.3).clamp(0.0, 1.0);
                if (v <= 0 || v >= 1) return const SizedBox.shrink();
                final x = -1.5 + v * 3;
                return DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(x - 0.5, -1),
                      end: Alignment(x + 0.5, 1),
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(alpha: 0.22),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Slides and fades a list item in, one after another.
class MkStagger extends StatelessWidget {
  const MkStagger({required this.index, required this.child, this.axis = Axis.vertical, super.key});

  final int index;
  final Widget child;
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final delay = math.min(index, 8) * 60;
    final total = 380 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: MkMotion.enter),
      builder: (context, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: axis == Axis.vertical ? Offset(0, (1 - v) * 18) : Offset((1 - v) * 24, 0),
          child: c,
        ),
      ),
      child: child,
    );
  }
}
