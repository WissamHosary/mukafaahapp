import 'package:material_ui/material_ui.dart';

import 'catalog_widgets.dart';
import 'motion.dart';
import 'tokens.dart';

/// Product tile for a shop's store grid: square photo, sale and sold-out
/// badges, name, price (with the old price crossed out) and a quick-add button.
class MkProductCard extends StatelessWidget {
  const MkProductCard({
    required this.name,
    required this.price,
    required this.onTap,
    this.imageUrl,
    this.oldPrice,
    this.saleLabel,
    this.soldOutLabel,
    this.onAdd,
    this.subtitle,
    super.key,
  });

  final String name;
  final String? imageUrl;

  /// Already formatted, e.g. "$15" or "From $15".
  final String price;
  final String? oldPrice;

  /// e.g. "-20%".
  final String? saleLabel;

  /// Shown over the photo when nothing is left.
  final String? soldOutLabel;
  final String? subtitle;
  final VoidCallback onTap;

  /// Quick add for products without options; null hides the button.
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: '$name, $price',
      child: MkPressable(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: MkColors.surface,
            borderRadius: MkRadius.all(MkRadius.lg),
            boxShadow: const [BoxShadow(color: Color(0x142C123F), blurRadius: 20, offset: Offset(0, 6))],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MkNetImage(url: imageUrl, fallbackIcon: Icons.shopping_bag_rounded, cacheWidth: 480),
                    if (saleLabel != null && soldOutLabel == null)
                      PositionedDirectional(
                        top: 8,
                        start: 8,
                        child: _Tag(text: saleLabel!, bg: MkColors.danger, fg: Colors.white),
                      ),
                    if (soldOutLabel != null)
                      ColoredBox(
                        color: Colors.white.withValues(alpha: 0.55),
                        child: Center(child: _Tag(text: soldOutLabel!, bg: MkColors.ink, fg: Colors.white)),
                      ),
                    if (onAdd != null && soldOutLabel == null)
                      PositionedDirectional(
                        bottom: 8,
                        end: 8,
                        child: MkPressable(
                          onTap: onAdd,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(color: MkColors.purple900, shape: BoxShape.circle, boxShadow: MkShadow.soft),
                            child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    if (subtitle != null)
                      Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelSmall?.copyWith(color: MkColors.ink3)),
                    const SizedBox(height: 4),
                    MkPrice(price: price, oldPrice: oldPrice),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.bg, required this.fg});
  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: MkRadius.all(MkRadius.pill)),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w800)),
    );
  }
}

/// Price with an optional crossed-out old price.
class MkPrice extends StatelessWidget {
  const MkPrice({required this.price, this.oldPrice, this.large = false, super.key});

  final String price;
  final String? oldPrice;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 6,
      children: [
        Text(
          price,
          style: (large ? t.headlineSmall : t.titleSmall)?.copyWith(
            color: oldPrice != null ? MkColors.danger : MkColors.purple900,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (oldPrice != null)
          Text(
            oldPrice!,
            style: (large ? t.bodyMedium : t.labelSmall)?.copyWith(color: MkColors.ink3, decoration: TextDecoration.lineThrough),
          ),
      ],
    );
  }
}

/// One option (Size, Colour…) as a row of selectable pills. Values that can't
/// be bought with the other choices are shown faded and crossed out.
class MkOptionPicker extends StatelessWidget {
  const MkOptionPicker({
    required this.label,
    required this.values,
    required this.selected,
    required this.onSelect,
    this.isAvailable,
    super.key,
  });

  final String label;
  final List<String> values;
  final String? selected;
  final ValueChanged<String> onSelect;
  final bool Function(String value)? isAvailable;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: label,
            style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            children: [
              if (selected != null) TextSpan(text: ':  $selected', style: t.titleSmall?.copyWith(color: MkColors.ink2, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
        const SizedBox(height: MkSpace.xs),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in values)
              Builder(
                builder: (context) {
                  final on = v == selected;
                  final ok = isAvailable?.call(v) ?? true;
                  return Semantics(
                    button: true,
                    selected: on,
                    enabled: ok,
                    label: '$label $v',
                    child: MkPressable(
                      onTap: () => onSelect(v),
                      child: AnimatedContainer(
                        duration: MkMotion.fast,
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 40),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: on ? MkColors.purple900 : MkColors.surface,
                          borderRadius: MkRadius.all(MkRadius.md),
                          border: Border.all(color: on ? MkColors.purple900 : MkColors.line, width: 1.5),
                        ),
                        child: Text(
                          v,
                          textAlign: TextAlign.center,
                          style: t.labelLarge?.copyWith(
                            color: on ? Colors.white : (ok ? MkColors.ink : MkColors.ink3),
                            decoration: ok ? null : TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

/// − qty + control.
class MkQtyStepper extends StatelessWidget {
  const MkQtyStepper({required this.value, required this.onChanged, this.min = 1, this.max, this.compact = false, super.key});

  final int value;
  final int min;
  final int? max;
  final bool compact;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 30.0 : 40.0;
    Widget btn(IconData icon, bool enabled, VoidCallback onTap, String label) => Semantics(
          button: true,
          enabled: enabled,
          label: label,
          child: MkPressable(
            onTap: enabled ? onTap : null,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(color: enabled ? MkColors.purple50 : MkColors.canvas, borderRadius: MkRadius.all(MkRadius.sm)),
              child: Icon(icon, size: compact ? 16 : 20, color: enabled ? MkColors.purple900 : MkColors.line),
            ),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.remove_rounded, value > min, () => onChanged(value - 1), '−'),
        SizedBox(
          width: compact ? 30 : 40,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        btn(Icons.add_rounded, max == null || value < max!, () => onChanged(value + 1), '+'),
      ],
    );
  }
}
