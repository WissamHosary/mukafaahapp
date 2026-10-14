import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'brand.dart';
import 'components.dart';
import 'home_widgets.dart';
import 'motion.dart';
import 'tokens.dart';

/// Icon for each shop category (labels come from the strings class).
abstract final class MkCategory {
  /// Built-in categories have a proper icon; admin-made ones fall back to their emoji.
  static bool known(String key) => const {
        'RESTAURANTS_CAFES', 'FOOD_DRINKS', 'FASHION', 'ELECTRONICS', 'FITNESS', 'BEAUTY_WELLNESS',
        'ENTERTAINMENT', 'GIFTS', 'RETAIL', 'SERVICES', 'OTHER',
      }.contains(key);

  static IconData icon(String key) => switch (key) {
        'RESTAURANTS_CAFES' => Icons.local_cafe_rounded,
        'FOOD_DRINKS' => Icons.lunch_dining_rounded,
        'FASHION' => Icons.checkroom_rounded,
        'ELECTRONICS' => Icons.headphones_rounded,
        'FITNESS' => Icons.fitness_center_rounded,
        'BEAUTY_WELLNESS' => Icons.spa_rounded,
        'ENTERTAINMENT' => Icons.sports_esports_rounded,
        'GIFTS' => Icons.redeem_rounded,
        'RETAIL' => Icons.shopping_bag_rounded,
        'SERVICES' => Icons.handyman_rounded,
        _ => Icons.storefront_rounded,
      };
}

/// Network image with a branded placeholder, fade-in and a graceful fallback.
class MkNetImage extends StatelessWidget {
  const MkNetImage({
    required this.url,
    this.fit = BoxFit.cover,
    this.radius = 0,
    this.fallbackIcon = Icons.image_rounded,
    this.fallbackName,
    this.cacheWidth,
    super.key,
  });

  final String? url;
  final BoxFit fit;
  final double radius;
  final IconData fallbackIcon;

  /// When set, the fallback shows this name's first letter instead of an icon.
  final String? fallbackName;

  /// Decode at this width (pixels) to save memory in long lists.
  final int? cacheWidth;

  Widget _fallback() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [MkColors.purple700, MkColors.purple900],
        ),
      ),
      child: Center(
        child: fallbackName != null && fallbackName!.trim().isNotEmpty
            ? Text(
                fallbackName!.trim().characters.first.toUpperCase(),
                style: const TextStyle(color: MkColors.yellow500, fontWeight: FontWeight.w800, fontSize: 22),
              )
            : Icon(fallbackIcon, color: MkColors.yellow500.withValues(alpha: 0.85)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final child = url == null
        ? _fallback()
        : Image.network(
            url!,
            fit: fit,
            cacheWidth: cacheWidth,
            gaplessPlayback: true,
            frameBuilder: (context, img, frame, sync) => sync
                ? img
                : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: MkMotion.base, child: img),
            loadingBuilder: (context, img, progress) =>
                progress == null ? img : const ColoredBox(color: MkColors.purple50),
            errorBuilder: (context, error, stack) => _fallback(),
          );
    return radius == 0 ? child : ClipRRect(borderRadius: MkRadius.all(radius), child: child);
  }
}

/// Five-star rating display.
class MkStars extends StatelessWidget {
  const MkStars({required this.rating, this.size = 14, this.count, super.key});

  final double rating;
  final double size;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            rating >= i
                ? Icons.star_rounded
                : rating >= i - 0.5
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
            size: size,
            color: rating == 0 ? MkColors.line : const Color(0xFFF5B400),
          ),
        if (count != null) ...[
          const SizedBox(width: 4),
          Text('($count)', style: TextStyle(fontSize: size * 0.8, color: MkColors.ink3)),
        ],
      ],
    );
  }
}

/// Shop card used in home sections, the shops grid and the map sheet:
/// cover photo with logo, offers tag and a gold "% back" badge, then name,
/// rating, place, program and the customer's points there.
class MkShopCard extends StatelessWidget {
  const MkShopCard({
    required this.name,
    required this.programType,
    required this.programLabel,
    required this.pointsText,
    required this.pointsBackText,
    required this.addressText,
    required this.buttonLabel,
    required this.onTap,
    this.coverUrl,
    this.logoUrl,
    this.rating = 0,
    this.ratingCount,
    this.width,
    this.badge,
    super.key,
  });

  final String name;
  final String? coverUrl;
  final String? logoUrl;
  final double rating;
  final int? ratingCount;
  final String programType;
  final String programLabel;
  final String pointsText;

  /// Short text for the gold badge, e.g. "10% back".
  final String pointsBackText;
  final String addressText;

  /// Used as the accessibility hint (the whole card is the button).
  final String buttonLabel;
  final VoidCallback onTap;
  final double? width;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final card = Container(
      width: width,
      decoration: BoxDecoration(
        color: MkColors.surface,
        borderRadius: MkRadius.all(MkRadius.lg),
        boxShadow: const [BoxShadow(color: Color(0x172C123F), blurRadius: 24, offset: Offset(0, 8))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 124,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MkNetImage(url: coverUrl, fallbackIcon: Icons.storefront_rounded, cacheWidth: 540),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0x00000000), Color(0x59000000)],
                      stops: [0, 0.45, 1],
                    ),
                  ),
                ),
                PositionedDirectional(
                  top: 10,
                  start: 10,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: MkShadow.soft,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: MkNetImage(url: logoUrl, fallbackName: name, cacheWidth: 120),
                  ),
                ),
                if (badge != null)
                  PositionedDirectional(
                    top: 10,
                    end: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.93), borderRadius: MkRadius.all(MkRadius.pill)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.local_offer_rounded, size: 12, color: MkColors.purple700),
                          const SizedBox(width: 3),
                          Text(badge!, style: t.labelSmall?.copyWith(color: MkColors.purple900)),
                        ],
                      ),
                    ),
                  ),
                PositionedDirectional(
                  bottom: 10,
                  start: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: MkColors.yellow500,
                      borderRadius: MkRadius.all(MkRadius.pill),
                      boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 10, offset: Offset(0, 4))],
                    ),
                    child: Text(pointsBackText, style: t.labelSmall?.copyWith(color: MkColors.purple900, fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 15, color: Color(0xFFF5B400)),
                    const SizedBox(width: 2),
                    Text(
                      rating == 0 ? '–' : rating.toStringAsFixed(1),
                      style: t.labelSmall?.copyWith(color: MkColors.ink, fontWeight: FontWeight.w700),
                    ),
                    if (ratingCount != null) Text(' ($ratingCount)', style: t.labelSmall?.copyWith(color: MkColors.ink3)),
                    const SizedBox(width: 6),
                    const Icon(Icons.location_on_rounded, size: 12, color: MkColors.ink3),
                    const SizedBox(width: 1),
                    Expanded(
                      child: Text(
                        addressText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.labelSmall?.copyWith(color: MkColors.ink3, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Flexible(child: MkProgramBadge(type: programType, label: programLabel)),
                    const SizedBox(width: 6),
                    const Spacer(),
                    Text(pointsText, style: t.labelMedium?.copyWith(color: MkColors.purple700, fontWeight: FontWeight.w800)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return Semantics(button: true, label: name, hint: buttonLabel, child: MkPressable(onTap: onTap, child: card));
  }
}

/// Round-cornered category tile. Shows the admin's icon image, else its emoji, else a built-in icon.
class MkCategoryTile extends StatelessWidget {
  const MkCategoryTile({
    required this.categoryKey,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.emoji,
    this.iconUrl,
    super.key,
  });

  final String categoryKey;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  /// Set by Mukafaah Manager; used when there is no icon image.
  final String? emoji;

  /// Full URL of an icon uploaded in Mukafaah Manager.
  final String? iconUrl;

  @override
  Widget build(BuildContext context) {
    final Widget glyph;
    if (iconUrl != null) {
      glyph = MkNetImage(url: iconUrl, fallbackIcon: MkCategory.icon(categoryKey), cacheWidth: 186);
    } else if (!MkCategory.known(categoryKey) && emoji != null && emoji!.trim().isNotEmpty) {
      glyph = Center(child: Text(emoji!, style: const TextStyle(fontSize: 30, height: 1.1)));
    } else {
      glyph = Icon(MkCategory.icon(categoryKey), color: MkColors.purple800, size: 28);
    }
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: MkPressable(
        onTap: onTap,
        child: SizedBox(
          width: 84,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: MkMotion.base,
                curve: MkMotion.enter,
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: selected ? MkColors.yellow500 : mkCategoryTint(categoryKey),
                  borderRadius: MkRadius.all(MkRadius.lg),
                  border: Border.all(color: selected ? MkColors.yellow500 : MkColors.line),
                  boxShadow: selected ? MkShadow.glow : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: AnimatedScale(
                  scale: selected ? 1.08 : 1,
                  duration: MkMotion.base,
                  curve: MkMotion.emphasized,
                  child: glyph,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: selected ? MkColors.purple900 : MkColors.ink,
                      fontWeight: selected ? FontWeight.w700 : null,
                      height: 1.2,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Auto-playing banner carousel: neighbours shrink and fade, autoplay pauses while touched.
class MkCarousel extends StatefulWidget {
  const MkCarousel({required this.pages, this.height = 160, this.interval = const Duration(seconds: 5), super.key});

  final List<Widget> pages;
  final double height;
  final Duration interval;

  @override
  State<MkCarousel> createState() => _MkCarouselState();
}

class _MkCarouselState extends State<MkCarousel> {
  final _ctl = PageController(viewportFraction: 0.9);
  Timer? _timer;
  int _page = 0;
  bool _touching = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted || _touching || !_ctl.hasClients || widget.pages.length < 2) return;
      final next = (_page + 1) % widget.pages.length;
      _ctl.animateToPage(next, duration: MkMotion.slow, curve: MkMotion.standard);
    });
  }

  @override
  void didUpdateWidget(MkCarousel old) {
    super.didUpdateWidget(old);
    if (_page >= widget.pages.length) _page = 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.pages.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: Listener(
            onPointerDown: (_) => _touching = true,
            onPointerUp: (_) => _touching = false,
            onPointerCancel: (_) => _touching = false,
            child: PageView.builder(
              controller: _ctl,
              itemCount: widget.pages.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => AnimatedBuilder(
                animation: _ctl,
                builder: (context, child) {
                  var delta = (i - _page).toDouble();
                  if (_ctl.hasClients && _ctl.position.haveDimensions) delta = i - (_ctl.page ?? _page.toDouble());
                  final d = delta.abs().clamp(0.0, 1.0);
                  return Opacity(
                    opacity: 1 - d * 0.35,
                    child: Transform.scale(scale: 1 - d * 0.07, child: child),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: ClipRRect(borderRadius: MkRadius.all(MkRadius.xl), child: widget.pages[i]),
                ),
              ),
            ),
          ),
        ),
        if (widget.pages.length > 1) ...[
          const SizedBox(height: MkSpace.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.pages.length; i++)
                AnimatedContainer(
                  duration: MkMotion.base,
                  curve: MkMotion.enter,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 22 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page ? MkColors.purple700 : MkColors.line,
                    borderRadius: MkRadius.all(MkRadius.pill),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// A drawn promo banner (no image download needed): title, subtitle and three steps.
class MkPromoBanner extends StatelessWidget {
  const MkPromoBanner({
    required this.title,
    required this.subtitle,
    required this.steps,
    this.icon = Icons.storefront_rounded,
    this.yellow = false,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<(IconData, String)> steps;
  final IconData icon;
  final bool yellow;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fg = yellow ? MkColors.purple900 : Colors.white;
    final accent = yellow ? MkColors.purple900 : MkColors.yellow500;
    final body = Padding(
      padding: const EdgeInsets.all(MkSpace.lg),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(title, style: t.headlineSmall?.copyWith(color: accent, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(color: fg.withValues(alpha: 0.85)),
                ),
                const SizedBox(height: MkSpace.sm),
                Row(
                  children: [
                    for (var i = 0; i < steps.length; i++) ...[
                      if (i > 0) Icon(Icons.chevron_right_rounded, size: 16, color: fg.withValues(alpha: 0.6)),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: yellow ? MkColors.purple900 : MkColors.yellow500,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(steps[i].$1, size: 16, color: yellow ? MkColors.yellow500 : MkColors.purple900),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              steps[i].$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.labelSmall?.copyWith(color: fg, fontSize: 9.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: MkSpace.sm),
          MkFloat(
            child: Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: yellow ? MkColors.purple900 : MkColors.yellow500,
                borderRadius: MkRadius.all(MkRadius.lg),
                boxShadow: MkShadow.lifted,
              ),
              child: Icon(icon, size: 40, color: yellow ? MkColors.yellow500 : MkColors.purple900),
            ),
          ),
        ],
      ),
    );
    return yellow ? ColoredBox(color: MkColors.yellow500, child: body) : MkSwirlBackground(child: body);
  }
}

/// Horizontal row of selectable chips.
class MkChoiceChips<T> extends StatelessWidget {
  const MkChoiceChips({required this.items, required this.selected, required this.onSelected, this.padding, super.key});

  final List<(T, String)> items;
  final T selected;
  final ValueChanged<T> onSelected;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        padding: padding,
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (context, i) => const SizedBox(width: MkSpace.xs),
        itemBuilder: (context, i) {
          final on = items[i].$1 == selected;
          return MkPressable(
            onTap: () => onSelected(items[i].$1),
            child: AnimatedContainer(
              duration: MkMotion.base,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? MkColors.purple700 : MkColors.surface,
                borderRadius: MkRadius.all(MkRadius.pill),
                border: Border.all(color: on ? MkColors.purple700 : MkColors.line),
              ),
              child: Text(
                items[i].$2,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: on ? Colors.white : MkColors.ink),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Underlined text tabs (All / In-Store / Shared / Network).
class MkTextTabs<T> extends StatelessWidget {
  const MkTextTabs({required this.items, required this.selected, required this.onSelected, super.key});

  final List<(T, String)> items;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        for (final it in items)
          Expanded(
            child: InkWell(
              onTap: () => onSelected(it.$1),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Text(
                      it.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelMedium?.copyWith(color: it.$1 == selected ? MkColors.purple700 : MkColors.ink3),
                    ),
                    const SizedBox(height: 6),
                    AnimatedContainer(
                      duration: MkMotion.base,
                      height: 3,
                      width: it.$1 == selected ? 28 : 0,
                      decoration: BoxDecoration(color: MkColors.purple700, borderRadius: MkRadius.all(MkRadius.pill)),
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

/// Icon button with a small count badge (bell, cart).
class MkBadgeIcon extends StatelessWidget {
  const MkBadgeIcon({required this.icon, required this.count, required this.onTap, this.color = MkColors.ink, super.key});

  final IconData icon;
  final int count;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Badge(
        isLabelVisible: count > 0,
        backgroundColor: MkColors.danger,
        label: Text(count > 99 ? '99+' : '$count'),
        child: Icon(icon, color: color),
      ),
    );
  }
}

/// Ticket-style offer card: photo with a gold tag, a perforated tear line,
/// then title, shop and validity with the action pill.
class MkOfferCard extends StatelessWidget {
  const MkOfferCard({
    required this.title,
    required this.onTap,
    this.imageUrl,
    this.logoUrl,
    this.subtitle,
    this.meta,
    this.actionLabel,
    this.tag,
    this.width,
    super.key,
  });

  final String title;
  final String? imageUrl;
  final String? logoUrl;
  final String? subtitle;
  final String? meta;
  final String? actionLabel;
  final String? tag;
  final VoidCallback onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: title,
      child: MkPressable(
        onTap: onTap,
        child: Container(
          width: width,
          decoration: BoxDecoration(
            color: MkColors.surface,
            borderRadius: MkRadius.all(MkRadius.lg),
            boxShadow: const [BoxShadow(color: Color(0x172C123F), blurRadius: 24, offset: Offset(0, 8))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(MkRadius.lg)),
                child: AspectRatio(
                  aspectRatio: 16 / 7.5,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MkNetImage(url: imageUrl, fallbackIcon: Icons.local_offer_rounded, cacheWidth: 720),
                      if (logoUrl != null)
                        PositionedDirectional(
                          top: 8,
                          end: 8,
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: Colors.white, width: 2)),
                            clipBehavior: Clip.antiAlias,
                            child: MkNetImage(url: logoUrl, cacheWidth: 100),
                          ),
                        ),
                      if (tag != null)
                        PositionedDirectional(
                          top: 8,
                          start: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(color: MkColors.yellow500, borderRadius: MkRadius.all(MkRadius.pill)),
                            child: Text(tag!, style: t.labelSmall?.copyWith(color: MkColors.purple900, fontWeight: FontWeight.w800)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const _TearLine(),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    if (subtitle != null)
                      Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: MkColors.ink3)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(meta ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelSmall?.copyWith(color: MkColors.ink3)),
                        ),
                        if (actionLabel != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(color: MkColors.purple900, borderRadius: MkRadius.all(MkRadius.pill)),
                            child: Text(actionLabel!, style: t.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
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

/// Dashed tear line with half-circle notches on both sides.
class _TearLine extends StatelessWidget {
  const _TearLine();

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 16, child: CustomPaint(painter: _TearPainter()));
  }
}

class _TearPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final notch = Paint()..color = MkColors.canvas;
    canvas.drawCircle(Offset(0, y), 8, notch);
    canvas.drawCircle(Offset(size.width, y), 8, notch);
    final dash = Paint()
      ..color = MkColors.line
      ..strokeWidth = 1.6;
    for (var x = 16.0; x < size.width - 16; x += 9) {
      canvas.drawLine(Offset(x, y), Offset(x + 5, y), dash);
    }
  }

  @override
  bool shouldRepaint(_TearPainter old) => false;
}

/// Search box used on list screens.
class MkSearchField extends StatelessWidget {
  const MkSearchField({required this.hint, required this.onChanged, this.controller, super.key});

  final String hint;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: const Icon(Icons.search_rounded),
        isDense: true,
      ),
    );
  }
}

/// Small tier pill (Silver / Gold / Platinum).
class MkTierChip extends StatelessWidget {
  const MkTierChip({required this.tier, required this.label, this.onTap, super.key});

  final String tier;
  final String label;
  final VoidCallback? onTap;

  static (Color, Color) colors(String tier) => switch (tier) {
        'GOLD' => (const Color(0xFFF5C518), MkColors.purple900),
        'PLATINUM' => (const Color(0xFFDCE3EA), MkColors.purple900),
        _ => (const Color(0xFFE7E7EC), MkColors.ink),
      };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = colors(tier);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: MkRadius.all(MkRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium_rounded, size: 15, color: fg),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg)),
          if (onTap != null) Icon(Icons.chevron_right_rounded, size: 16, color: fg),
        ],
      ),
    );
    return onTap == null ? chip : MkPressable(onTap: onTap, child: chip);
  }
}

/// Two-tone summary tile (Balance Points / Total Saving).
class MkSummaryTile extends StatelessWidget {
  const MkSummaryTile({required this.label, required this.value, this.positive = true, super.key});

  final String label;
  final String value;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final bg = positive ? MkColors.successBg : MkColors.dangerBg;
    final fg = positive ? MkColors.success : MkColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: MkRadius.all(MkRadius.md)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.labelMedium?.copyWith(color: MkColors.ink2)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value, textDirection: TextDirection.ltr, style: t.titleLarge?.copyWith(color: fg)),
          ),
        ],
      ),
    );
  }
}

/// Horizontal list section with a "See all" action.
class MkHorizontalSection extends StatelessWidget {
  const MkHorizontalSection({
    required this.title,
    required this.itemCount,
    required this.itemBuilder,
    this.height = 300,
    this.itemWidth = 168,
    this.action,
    this.onAction,
    super.key,
  });

  final String title;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double height;
  final double itemWidth;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: MkSpace.lg),
          child: MkSectionHeader(title: title, action: action, onAction: onAction),
        ),
        SizedBox(
          height: height,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: MkSpace.lg, vertical: 4),
            scrollDirection: Axis.horizontal,
            itemCount: itemCount,
            separatorBuilder: (context, i) => const SizedBox(width: MkSpace.sm),
            itemBuilder: (context, i) => SizedBox(width: itemWidth, child: itemBuilder(context, i)),
          ),
        ),
      ],
    );
  }
}
