import 'package:material_ui/material_ui.dart';

import 'catalog_widgets.dart';
import 'motion.dart';
import 'server_widgets.dart';
import 'tokens.dart';

/// Purple header with soft rings, and a card that overlaps its bottom edge
/// (the home screen's greeting + points card).
class MkHeroHeader extends StatelessWidget {
  const MkHeroHeader({required this.top, required this.card, this.overlap = 72, super.key});

  /// Greeting row shown on the purple part.
  final Widget top;

  /// Card that sits half on the purple, half on the page.
  final Widget card;
  final double overlap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          bottom: overlap,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(30)),
            child: CustomPaint(painter: _HeroPainter()),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(MkSpace.lg, MediaQuery.paddingOf(context).top + MkSpace.sm, MkSpace.lg, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [top, const SizedBox(height: MkSpace.lg), card],
          ),
        ),
      ],
    );
  }
}

class _HeroPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = MkColors.purple900);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment.topRight,
          radius: 1.1,
          colors: [MkColors.purple500, Color(0x007446A8)],
        ).createShader(rect),
    );
    canvas.drawCircle(
      Offset(size.width + 10, -20),
      110,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 28
        ..color = MkColors.yellow500.withValues(alpha: 0.10),
    );
    canvas.drawCircle(Offset(-20, size.height + 10), 64, Paint()..color = Colors.white.withValues(alpha: 0.05));
  }

  @override
  bool shouldRepaint(_HeroPainter old) => false;
}

/// Round see-through button for use on the purple header (bell, cart).
class MkGlassButton extends StatelessWidget {
  const MkGlassButton({required this.icon, required this.onTap, this.count = 0, this.label, super.key});

  final IconData icon;
  final VoidCallback onTap;
  final int count;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: MkPressable(
        onTap: onTap,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Center(
            child: Badge(
              isLabelVisible: count > 0,
              backgroundColor: MkColors.danger,
              label: Text(count > 99 ? '99+' : '$count'),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

/// The customer's points card: animated balance, tier chip, progress to the next
/// tier, and a shortcut to the QR. A gold light sweeps across it now and then.
class MkPointsCard extends StatelessWidget {
  const MkPointsCard({
    required this.title,
    required this.points,
    required this.pointsUnit,
    required this.caption,
    required this.tier,
    required this.tierLabel,
    required this.progress,
    required this.progressLabel,
    required this.qrLabel,
    required this.onQr,
    this.onTier,
    this.onTap,
    super.key,
  });

  final String title;
  final int points;
  final String pointsUnit;

  /// e.g. "≈ $12 to spend · saved $2.50".
  final String caption;
  final String tier;
  final String tierLabel;

  /// 0..1 towards the next tier.
  final double progress;
  final String progressLabel;
  final String qrLabel;
  final VoidCallback onQr;
  final VoidCallback? onTier;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final card = Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white, Color(0xFFFBF8FF)]),
        borderRadius: MkRadius.all(24),
        boxShadow: const [BoxShadow(color: Color(0x382C123F), blurRadius: 40, offset: Offset(0, 18))],
      ),
      clipBehavior: Clip.antiAlias,
      child: MkShine(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(MkSpace.md, MkSpace.md, MkSpace.md, MkSpace.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: t.labelMedium?.copyWith(color: MkColors.ink3))),
                  MkTierChip(tier: tier, label: tierLabel, onTap: onTier),
                ],
              ),
              const SizedBox(height: MkSpace.xs),
              Row(
                children: [
                  const MkFloat(child: _Coin()),
                  const SizedBox(width: MkSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            AnimatedPoints(
                              value: points,
                              format: _thousands,
                              style: t.headlineLarge?.copyWith(
                                color: MkColors.purple900,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(pointsUnit, style: t.labelLarge?.copyWith(color: MkColors.ink3)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: MkColors.ink3)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: MkSpace.sm),
              ClipRRect(
                borderRadius: MkRadius.all(MkRadius.pill),
                child: SizedBox(
                  height: 6,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 1100),
                    curve: MkMotion.enter,
                    builder: (context, v, _) => Stack(
                      fit: StackFit.expand,
                      children: [
                        const ColoredBox(color: MkColors.purple50),
                        FractionallySizedBox(
                          alignment: AlignmentDirectional.centerStart,
                          widthFactor: v,
                          child: const DecoratedBox(
                            decoration: BoxDecoration(gradient: LinearGradient(colors: [MkColors.yellow500, Color(0xFFF5A300)])),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: MkSpace.xs),
              Row(
                children: [
                  Expanded(child: Text(progressLabel, style: t.labelSmall?.copyWith(color: MkColors.ink3, fontWeight: FontWeight.w500))),
                  MkPressable(
                    onTap: onQr,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(color: MkColors.purple900, borderRadius: MkRadius.all(MkRadius.md)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.qr_code_2_rounded, size: 16, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(qrLabel, style: t.labelMedium?.copyWith(color: Colors.white)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return onTap == null ? card : MkPressable(onTap: onTap, child: card);
  }
}

String _thousands(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

/// Glossy gold coin with the Mukafaah "م".
class _Coin extends StatelessWidget {
  const _Coin();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(center: Alignment(-0.3, -0.4), colors: [Color(0xFFFFF3A6), MkColors.yellow500, Color(0xFFD9A800)], stops: [0, 0.45, 1]),
        boxShadow: [BoxShadow(color: Color(0x73E9C200), blurRadius: 14, offset: Offset(0, 6))],
      ),
      alignment: Alignment.center,
      child: const Text('م', style: TextStyle(color: MkColors.purple900, fontWeight: FontWeight.w900, fontSize: 20, height: 1)),
    );
  }
}

/// One quick action on the home screen.
typedef MkQuickAction = ({IconData icon, String label, VoidCallback onTap});

/// Four round shortcuts under the points card. The first one is highlighted.
class MkQuickActions extends StatelessWidget {
  const MkQuickActions({required this.items, super.key});

  final List<MkQuickAction> items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        for (var i = 0; i < items.length; i++)
          Expanded(
            child: Semantics(
              button: true,
              label: items[i].label,
              child: MkPressable(
                onTap: items[i].onTap,
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: i == 0 ? MkColors.yellow500 : MkColors.surface,
                        borderRadius: MkRadius.all(18),
                        border: Border.all(color: i == 0 ? MkColors.yellow500 : MkColors.line),
                        boxShadow: i == 0 ? MkShadow.glow : MkShadow.soft,
                      ),
                      child: Icon(items[i].icon, color: MkColors.purple900, size: 26),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      items[i].label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelSmall?.copyWith(color: MkColors.ink2, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Floating, rounded bottom navigation with a raised gold centre button.
class MkFloatingNav extends StatelessWidget {
  const MkFloatingNav({
    required this.items,
    required this.selected,
    required this.onSelect,
    required this.centerIcon,
    required this.centerLabel,
    required this.centerIndex,
    super.key,
  });

  /// Tabs other than the centre one, in order; their index is their branch index.
  final List<({int index, IconData icon, String label})> items;
  final int selected;
  final ValueChanged<int> onSelect;
  final IconData centerIcon;
  final String centerLabel;
  final int centerIndex;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget tab(({int index, IconData icon, String label}) it) {
      final on = it.index == selected;
      final c = on ? Colors.white : MkColors.ink3;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: it.label,
          child: MkPressable(
            onTap: () => onSelect(it.index),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: MkMotion.base,
                  curve: MkMotion.emphasized,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  transform: Matrix4.translationValues(0, on ? -2 : 0, 0),
                  decoration: BoxDecoration(
                    color: on ? MkColors.purple900 : Colors.transparent,
                    borderRadius: MkRadius.all(MkRadius.pill),
                  ),
                  child: Icon(it.icon, color: c, size: 22),
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: MkMotion.base,
                  style: (t.labelSmall ?? const TextStyle()).copyWith(
                    color: on ? MkColors.purple900 : MkColors.ink3,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                  ),
                  child: Text(it.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final half = (items.length / 2).ceil();
    final centerOn = selected == centerIndex;
    // The QR tab sits inside the bar like the others: a yellow pill with its label.
    final center = Expanded(
      child: Semantics(
        button: true,
        selected: centerOn,
        label: centerLabel,
        child: MkPressable(
          onTap: () => onSelect(centerIndex),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: MkMotion.base,
                curve: MkMotion.emphasized,
                width: 52,
                height: 34,
                decoration: BoxDecoration(
                  color: centerOn ? MkColors.purple900 : MkColors.yellow500,
                  borderRadius: MkRadius.all(14),
                ),
                child: Icon(centerIcon, color: centerOn ? MkColors.yellow500 : MkColors.purple900, size: 22),
              ),
              const SizedBox(height: 3),
              Text(
                centerLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: (t.labelSmall ?? const TextStyle()).copyWith(
                  color: MkColors.purple900,
                  fontWeight: centerOn ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            color: MkColors.surface,
            borderRadius: MkRadius.all(26),
            boxShadow: const [BoxShadow(color: Color(0x2E2C123F), blurRadius: 30, offset: Offset(0, 10))],
          ),
          child: Row(
            children: [
              for (final it in items.take(half)) tab(it),
              center,
              for (final it in items.skip(half)) tab(it),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pastel background for a category tile, picked from its key so it stays stable.
Color mkCategoryTint(String key) {
  const tints = [Color(0xFFFFF6CC), Color(0xFFEDE5F6), Color(0xFFDDF2F3), Color(0xFFFCE7EF), Color(0xFFE5F6EE), Color(0xFFFFEBDD)];
  var h = 0;
  for (final c in key.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return tints[h % tints.length];
}
