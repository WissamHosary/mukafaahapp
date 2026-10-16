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

/// Common colour names (English and Arabic) to the colour shown in the swatch.
const Map<String, Color> _kColourNames = {
  'black': Color(0xFF1B1B1F), 'أسود': Color(0xFF1B1B1F), 'اسود': Color(0xFF1B1B1F),
  'white': Color(0xFFFFFFFF), 'أبيض': Color(0xFFFFFFFF), 'ابيض': Color(0xFFFFFFFF),
  'grey': Color(0xFF9AA0A6), 'gray': Color(0xFF9AA0A6), 'رمادي': Color(0xFF9AA0A6), 'silver': Color(0xFFC9CED6), 'فضي': Color(0xFFC9CED6),
  'red': Color(0xFFD7263D), 'أحمر': Color(0xFFD7263D), 'احمر': Color(0xFFD7263D), 'burgundy': Color(0xFF7A1F2B), 'maroon': Color(0xFF7A1F2B),
  'pink': Color(0xFFF49AC1), 'زهري': Color(0xFFF49AC1), 'وردي': Color(0xFFF49AC1),
  'orange': Color(0xFFF28C28), 'برتقالي': Color(0xFFF28C28),
  'yellow': Color(0xFFF7D02C), 'أصفر': Color(0xFFF7D02C), 'اصفر': Color(0xFFF7D02C), 'gold': Color(0xFFD4AF37), 'ذهبي': Color(0xFFD4AF37),
  'green': Color(0xFF2E9E5B), 'أخضر': Color(0xFF2E9E5B), 'اخضر': Color(0xFF2E9E5B), 'olive': Color(0xFF6B7A3A), 'mint': Color(0xFF9FE3C4),
  'blue': Color(0xFF2F6BD8), 'أزرق': Color(0xFF2F6BD8), 'ازرق': Color(0xFF2F6BD8), 'navy': Color(0xFF1F2A55), 'كحلي': Color(0xFF1F2A55), 'sky': Color(0xFF8CC8F2),
  'purple': Color(0xFF7446A8), 'بنفسجي': Color(0xFF7446A8), 'lilac': Color(0xFFC3A8E6),
  'brown': Color(0xFF7A4E2D), 'بني': Color(0xFF7A4E2D), 'beige': Color(0xFFE6D3B3), 'بيج': Color(0xFFE6D3B3), 'cream': Color(0xFFF4EBD6), 'khaki': Color(0xFFC3B091),
};

/// The swatch colour for an option value: "#C8463F", a known colour name, or null.
Color? mkColourFor(String value) {
  final v = value.trim();
  final hex = RegExp(r'#?([0-9a-fA-F]{6})$').firstMatch(v);
  if (hex != null && v.startsWith('#')) return Color(int.parse('FF${hex.group(1)}', radix: 16));
  final k = v.toLowerCase();
  if (_kColourNames.containsKey(k)) return _kColourNames[k];
  // "Light blue", "Dark green", "Navy blue": use the last known word.
  for (final w in k.split(RegExp(r'\s+')).reversed) {
    final c = _kColourNames[w];
    if (c != null) {
      if (k.startsWith('light')) return Color.lerp(c, Colors.white, 0.45);
      if (k.startsWith('dark')) return Color.lerp(c, Colors.black, 0.35);
      return c;
    }
  }
  return null;
}

/// One option (Size, Colour…) the way shops show it: colours as round
/// swatches, everything else as clean pills. The chosen value shows next to
/// the label. Values that can't be bought with the other choices are faded
/// and struck through, and still tappable (choosing one clears the clash).
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

  bool get _isColour {
    final l = label.toLowerCase();
    final named = l.contains('colo') || l.contains('لون') || l.contains('الوان');
    final known = values.where((v) => mkColourFor(v) != null).length;
    return named ? known >= (values.length / 2).ceil() : known == values.length && values.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final colour = _isColour;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: MkMotion.fast,
                child: Text(
                  selected ?? '',
                  key: ValueKey(selected),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyMedium?.copyWith(color: MkColors.ink2),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: colour ? 12 : 8,
          runSpacing: colour ? 12 : 8,
          children: [
            for (final v in values)
              Builder(
                builder: (context) {
                  final on = v == selected;
                  final ok = isAvailable?.call(v) ?? true;
                  final c = colour ? mkColourFor(v) : null;
                  final Widget chip;
                  if (colour && c != null) {
                    final light = c.computeLuminance() > 0.8;
                    chip = AnimatedContainer(
                      duration: MkMotion.fast,
                      width: 44,
                      height: 44,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: on ? MkColors.purple900 : Colors.transparent, width: 2),
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c,
                          border: light ? Border.all(color: MkColors.line, width: 1.2) : null,
                          boxShadow: on ? [BoxShadow(color: c.withValues(alpha: 0.45), blurRadius: 10, offset: const Offset(0, 3))] : null,
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            if (on) Icon(Icons.check_rounded, size: 18, color: light ? MkColors.purple900 : Colors.white),
                            if (!ok) CustomPaint(size: const Size.square(34), painter: _Strike(light ? MkColors.ink3 : Colors.white)),
                          ],
                        ),
                      ),
                    );
                  } else {
                    chip = AnimatedContainer(
                      duration: MkMotion.fast,
                      curve: MkMotion.standard,
                      constraints: const BoxConstraints(minWidth: 52, minHeight: 44),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: on ? MkColors.purple900 : (ok ? MkColors.surface : const Color(0xFFF4F1F7)),
                        borderRadius: MkRadius.all(14),
                        border: Border.all(color: on ? MkColors.purple900 : (ok ? const Color(0xFFDCD3E6) : const Color(0xFFEDE8F2)), width: 1.4),
                        boxShadow: on ? const [BoxShadow(color: Color(0x402C123F), blurRadius: 12, offset: Offset(0, 4))] : null,
                      ),
                      child: Text(
                        v,
                        textAlign: TextAlign.center,
                        style: t.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: on ? Colors.white : (ok ? MkColors.ink : MkColors.ink3),
                          decoration: ok ? null : TextDecoration.lineThrough,
                        ),
                      ),
                    );
                  }
                  return Tooltip(
                    message: ok ? v : '$v (sold out)',
                    child: Semantics(
                      button: true,
                      selected: on,
                      enabled: ok,
                      label: '$label $v',
                      child: MkPressable(onTap: () => onSelect(v), child: Opacity(opacity: ok ? 1 : 0.55, child: chip)),
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

/// Diagonal line across a sold-out colour swatch.
class _Strike extends CustomPainter {
  const _Strike(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(size.width * 0.15, size.height * 0.85),
      Offset(size.width * 0.85, size.height * 0.15),
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_Strike old) => old.color != color;
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
