import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'brand.dart';
import 'catalog_widgets.dart';
import 'motion.dart';
import 'server_widgets.dart';
import 'tokens.dart';

// ---------------------------------------------------------------- colours

/// Parses "#RRGGBB", "RRGGBB" or "#AARRGGBB". Returns null when empty or invalid.
Color? mkHexColor(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

/// A category's accent: the colour set in Mukafaah Manager, else a stable brand colour from its key.
Color mkCategoryColor(String key, [String? hex]) {
  final c = mkHexColor(hex);
  if (c != null) return c;
  const palette = [
    MkColors.purple500,
    MkColors.shared,
    MkColors.network,
    Color(0xFFE08A00),
    MkColors.success,
    Color(0xFF3D6FD8),
    MkColors.purple700,
  ];
  var h = 0;
  for (final u in key.codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  return palette[h % palette.length];
}

/// Readable text colour on top of [bg].
Color mkOnColor(Color bg) => bg.computeLuminance() > 0.55 ? MkColors.purple900 : Colors.white;

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t) ?? a;

// ---------------------------------------------------------------- home action cards

/// A big, tappable home action: gradient card with an icon badge, title,
/// short subtitle, a corner arrow and a large faint watermark icon.
/// [accent] uses the signature yellow; otherwise the brand purple.
class MkActionCard extends StatelessWidget {
  const MkActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.accent = false,
    this.height = 140,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool accent;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final fg = accent ? MkColors.purple900 : Colors.white;
    final gradient = accent
        ? const LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [Color(0xFFFFE45C), MkColors.yellow500, Color(0xFFF2B800)],
            stops: [0, 0.55, 1],
          )
        : const LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [MkColors.purple500, MkColors.purple800, MkColors.purple900],
            stops: [0, 0.55, 1],
          );
    final shadow = accent
        ? const [BoxShadow(color: Color(0x55E9C200), blurRadius: 24, offset: Offset(0, 12))]
        : const [BoxShadow(color: Color(0x4D2C123F), blurRadius: 24, offset: Offset(0, 12))];

    Widget card = Container(
      height: height,
      decoration: BoxDecoration(gradient: gradient, borderRadius: MkRadius.all(24), boxShadow: shadow),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Soft ring and watermark give depth without noise.
          PositionedDirectional(
            top: -42,
            end: -42,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: fg.withValues(alpha: 0.10), width: 18),
              ),
            ),
          ),
          PositionedDirectional(
            bottom: -26,
            end: -14,
            child: Transform.rotate(
              angle: rtl ? 0.28 : -0.28,
              child: Icon(icon, size: 108, color: fg.withValues(alpha: accent ? 0.10 : 0.08)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(MkSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accent ? MkColors.purple900 : Colors.white.withValues(alpha: 0.14),
                        borderRadius: MkRadius.all(15),
                        border: accent ? null : Border.all(color: Colors.white.withValues(alpha: 0.18)),
                      ),
                      child: Icon(icon, color: MkColors.yellow500, size: 24),
                    ),
                    const Spacer(),
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: fg.withValues(alpha: 0.12)),
                      child: Icon(rtl ? Icons.north_west_rounded : Icons.north_east_rounded, size: 16, color: fg),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w800, letterSpacing: -0.2),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodySmall?.copyWith(color: fg.withValues(alpha: 0.78), height: 1.25),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (accent) card = MkShine(period: const Duration(seconds: 6), child: card);
    return Semantics(button: true, label: title, hint: subtitle, child: MkPressable(onTap: onTap, scale: 0.955, child: card));
  }
}

// ---------------------------------------------------------------- banners

/// Where a banner sits inside a [MkBannerDeck] page.
enum MkBannerSlot { wide, half, tall, quarter }

/// A home banner from Mukafaah Manager. Shows the uploaded image when there is one
/// (with the title over a soft scrim if set), else a drawn gradient in the banner's
/// style (PURPLE or YELLOW) with its title and subtitle.
class MkBannerTile extends StatelessWidget {
  const MkBannerTile({
    this.style = 'PURPLE',
    this.title,
    this.subtitle,
    this.imageUrl,
    this.actionLabel,
    this.onTap,
    this.slot = MkBannerSlot.wide,
    super.key,
  });

  final String style;
  final String? title;
  final String? subtitle;
  final String? imageUrl;
  final String? actionLabel;
  final VoidCallback? onTap;
  final MkBannerSlot slot;

  bool get _small => slot == MkBannerSlot.half || slot == MkBannerSlot.quarter;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final yellow = style == 'YELLOW' && imageUrl == null;
    final hasImage = imageUrl != null;
    final fg = yellow ? MkColors.purple900 : Colors.white;
    final accent = yellow ? MkColors.purple900 : (hasImage ? Colors.white : MkColors.yellow500);
    final title = (this.title ?? '').trim();
    final subtitle = (this.subtitle ?? '').trim();
    final hasText = title.isNotEmpty || subtitle.isNotEmpty;
    final quarter = slot == MkBannerSlot.quarter;
    final rtl = Directionality.of(context) == TextDirection.rtl;

    final text = Padding(
      padding: EdgeInsets.all(_small ? MkSpace.sm : MkSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: hasImage || slot != MkBannerSlot.wide ? MainAxisAlignment.end : MainAxisAlignment.center,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              maxLines: quarter ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: (_small ? t.titleSmall : t.headlineSmall)?.copyWith(color: accent, fontWeight: FontWeight.w900, height: 1.15),
            ),
          if (subtitle.isNotEmpty && !quarter) ...[
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: (_small ? t.labelSmall : t.bodySmall)?.copyWith(color: fg.withValues(alpha: 0.86), fontWeight: FontWeight.w500),
            ),
          ],
          if (actionLabel != null && !_small) ...[
            const SizedBox(height: MkSpace.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: yellow ? MkColors.purple900 : MkColors.yellow500,
                borderRadius: MkRadius.all(MkRadius.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionLabel!, style: t.labelMedium?.copyWith(color: yellow ? MkColors.yellow500 : MkColors.purple900)),
                  const SizedBox(width: 2),
                  Icon(
                    rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                    size: 16,
                    color: yellow ? MkColors.yellow500 : MkColors.purple900,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );

    final Widget body;
    if (hasImage) {
      body = Stack(
        fit: StackFit.expand,
        children: [
          MkNetImage(url: imageUrl, cacheWidth: _small ? 600 : 1080),
          if (hasText)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0x14000000), Color(0x9E000000)],
                  stops: [0, 0.45, 1],
                ),
              ),
            ),
          if (hasText) text,
        ],
      );
    } else {
      body = DecoratedBox(
        decoration: BoxDecoration(
          gradient: yellow
              ? const LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [Color(0xFFFFE45C), MkColors.yellow500, Color(0xFFF2B800)],
                )
              : const LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [MkColors.purple500, MkColors.purple800, MkColors.purple900],
                  stops: [0, 0.5, 1],
                ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _BannerDecorPainter(yellow: yellow)),
            PositionedDirectional(
              end: _small ? 8 : 18,
              top: _small ? 8 : null,
              bottom: _small ? null : 18,
              child: MkFloat(child: MkCoin(size: _small ? 26 : 52)),
            ),
            Padding(
              padding: EdgeInsetsDirectional.only(end: _small ? 0 : 64),
              child: text,
            ),
          ],
        ),
      );
    }
    if (onTap == null) return body;
    return Semantics(
      button: true,
      label: title.isEmpty ? subtitle : title,
      child: MkPressable(onTap: onTap, scale: 0.98, child: body),
    );
  }
}

class _BannerDecorPainter extends CustomPainter {
  _BannerDecorPainter({required this.yellow});

  final bool yellow;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = yellow ? MkColors.purple900 : MkColors.yellow500;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.16
      ..color = (yellow ? Colors.white : MkColors.purple500).withValues(alpha: yellow ? 0.25 : 0.45);
    canvas.drawCircle(Offset(size.width * 1.02, size.height * 0.05), size.shortestSide * 0.62, ring);
    final dot = Paint()..color = ink.withValues(alpha: 0.55);
    canvas.drawCircle(Offset(size.width * 0.62, size.height * 0.16), 2.6, dot);
    canvas.drawCircle(Offset(size.width * 0.78, size.height * 0.86), 2, dot);
    final squiggle = Paint()
      ..color = ink.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    final p = Path()..moveTo(size.width * 0.70, size.height * 0.30);
    for (var i = 0; i < 3; i++) {
      p.relativeQuadraticBezierTo(5, -6, 10, 0);
    }
    canvas.drawPath(p, squiggle);
  }

  @override
  bool shouldRepaint(_BannerDecorPainter old) => old.yellow != yellow;
}

/// Home banners laid out as chosen in Mukafaah Manager:
/// UNO one wide banner per slide, DUO two side by side, TRIO one tall plus two stacked.
/// Pages auto-advance (paused while touched or with reduced motion); the active dot
/// fills up until the next slide.
class MkBannerDeck extends StatefulWidget {
  const MkBannerDeck({
    required this.layout,
    required this.itemCount,
    required this.itemBuilder,
    this.interval = const Duration(seconds: 5),
    super.key,
  });

  /// UNO, DUO or TRIO.
  final String layout;
  final int itemCount;
  final Widget Function(BuildContext context, int index, MkBannerSlot slot) itemBuilder;
  final Duration interval;

  @override
  State<MkBannerDeck> createState() => _MkBannerDeckState();
}

class _MkBannerDeckState extends State<MkBannerDeck> {
  PageController? _ctl;
  double _fraction = 0;
  Timer? _timer;
  int _page = 0;
  bool _touching = false;

  int get _perPage => switch (widget.layout) {
        'DUO' => 2,
        'TRIO' => 3,
        _ => 1,
      };

  int get _pages => widget.itemCount == 0 ? 0 : (widget.itemCount + _perPage - 1) ~/ _perPage;

  double get _height => switch (widget.layout) {
        'DUO' => 150,
        'TRIO' => 210,
        _ => 168,
      };

  PageController _controller() {
    final f = _pages <= 1 ? 1.0 : (_perPage == 1 ? 0.9 : 0.93);
    if (_ctl == null || f != _fraction) {
      // The old PageView still holds the old controller this frame; release it after.
      final old = _ctl;
      if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      _fraction = f;
      _ctl = PageController(viewportFraction: f, initialPage: _page);
    }
    return _ctl!;
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) => _advance());
  }

  void _advance() {
    final c = _ctl;
    if (!mounted || _touching || c == null || !c.hasClients || _pages < 2) return;
    if (MediaQuery.disableAnimationsOf(context)) return;
    c.animateToPage((_page + 1) % _pages, duration: MkMotion.slow, curve: MkMotion.standard);
  }

  @override
  void didUpdateWidget(MkBannerDeck old) {
    super.didUpdateWidget(old);
    if (_page >= _pages) _page = 0;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctl?.dispose();
    super.dispose();
  }

  Widget _clip(Widget child, double r) => ClipRRect(borderRadius: MkRadius.all(r), child: child);

  Widget _pageAt(BuildContext context, int p) {
    final first = p * _perPage;
    final n = math.min(_perPage, widget.itemCount - first);
    const gap = 10.0;
    if (n == 1) return _clip(widget.itemBuilder(context, first, MkBannerSlot.wide), MkRadius.xl);
    if (n == 2) {
      return Row(
        children: [
          Expanded(child: _clip(widget.itemBuilder(context, first, MkBannerSlot.half), MkRadius.lg)),
          const SizedBox(width: gap),
          Expanded(child: _clip(widget.itemBuilder(context, first + 1, MkBannerSlot.half), MkRadius.lg)),
        ],
      );
    }
    return Row(
      children: [
        Expanded(flex: 6, child: _clip(widget.itemBuilder(context, first, MkBannerSlot.tall), MkRadius.lg)),
        const SizedBox(width: gap),
        Expanded(
          flex: 5,
          child: Column(
            children: [
              Expanded(child: _clip(widget.itemBuilder(context, first + 1, MkBannerSlot.quarter), MkRadius.lg)),
              const SizedBox(height: gap),
              Expanded(child: _clip(widget.itemBuilder(context, first + 2, MkBannerSlot.quarter), MkRadius.lg)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    if (pages == 0) return const SizedBox.shrink();
    final ctl = _controller();
    final single = pages == 1;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Column(
      children: [
        SizedBox(
          height: _height,
          child: Listener(
            onPointerDown: (_) => _touching = true,
            onPointerUp: (_) => _touching = false,
            onPointerCancel: (_) => _touching = false,
            child: PageView.builder(
              key: ValueKey<double>(_fraction),
              controller: ctl,
              itemCount: pages,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => AnimatedBuilder(
                animation: ctl,
                builder: (context, child) {
                  var delta = (i - _page).toDouble();
                  if (ctl.hasClients && ctl.position.haveDimensions) delta = i - (ctl.page ?? _page.toDouble());
                  final d = delta.abs().clamp(0.0, 1.0);
                  return Opacity(opacity: 1 - d * 0.3, child: Transform.scale(scale: 1 - d * 0.06, child: child));
                },
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: single ? MkSpace.lg : 5),
                  child: _pageAt(context, i),
                ),
              ),
            ),
          ),
        ),
        if (!single) ...[
          const SizedBox(height: MkSpace.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < pages; i++)
                AnimatedContainer(
                  duration: MkMotion.base,
                  curve: MkMotion.enter,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _page ? 26 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _page ? MkColors.purple100 : MkColors.line,
                    borderRadius: MkRadius.all(MkRadius.pill),
                  ),
                  clipBehavior: Clip.antiAlias,
                  alignment: AlignmentDirectional.centerStart,
                  child: i != _page
                      ? null
                      : TweenAnimationBuilder<double>(
                          key: ValueKey('dot$_page'),
                          tween: Tween<double>(begin: reduced ? 1.0 : 0.0, end: 1.0),
                          duration: widget.interval,
                          builder: (context, v, _) => FractionallySizedBox(
                            widthFactor: v,
                            heightFactor: 1,
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [MkColors.purple700, MkColors.purple500]),
                              ),
                            ),
                          ),
                        ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- categories

/// Logo of a category: the image uploaded in Mukafaah Manager, else the built-in
/// icon for known categories, else the admin's emoji, else a store icon.
class MkCategoryGlyph extends StatelessWidget {
  const MkCategoryGlyph({required this.categoryKey, required this.color, this.iconUrl, this.emoji, this.size = 40, super.key});

  final String categoryKey;
  final String? iconUrl;
  final String? emoji;
  final Color color;
  final double size;

  Widget _fallback() {
    if (!MkCategory.known(categoryKey) && emoji != null && emoji!.trim().isNotEmpty) {
      return Text(emoji!, style: TextStyle(fontSize: size * 0.72, height: 1.1));
    }
    return Icon(MkCategory.icon(categoryKey), color: color, size: size * 0.78);
  }

  @override
  Widget build(BuildContext context) {
    final Widget child = iconUrl == null
        ? _fallback()
        : Image.network(
            iconUrl!,
            width: size,
            height: size,
            fit: BoxFit.contain,
            cacheWidth: (size * 3).round(),
            gaplessPlayback: true,
            frameBuilder: (context, img, frame, sync) =>
                sync ? img : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: MkMotion.base, child: img),
            errorBuilder: (context, error, stack) => _fallback(),
          );
    return SizedBox.square(dimension: size, child: Center(child: child));
  }
}

/// Home category tile: a soft squircle tinted with the category colour, holding
/// its logo, with a gloss highlight, a shop-count bubble and the name below.
/// Pops in with a stagger by [index] and squeezes when pressed.
class MkCategoryCard extends StatelessWidget {
  const MkCategoryCard({
    required this.categoryKey,
    required this.label,
    required this.onTap,
    this.color,
    this.iconUrl,
    this.emoji,
    this.count = 0,
    this.index = 0,
    super.key,
  });

  final String categoryKey;
  final String label;
  final VoidCallback onTap;

  /// Category colour; a brand colour is picked from the key when null.
  final Color? color;

  /// Full URL of the logo uploaded in Mukafaah Manager.
  final String? iconUrl;
  final String? emoji;
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = color ?? mkCategoryColor(categoryKey);
    final deep = _mix(c, MkColors.ink, 0.25);
    final tile = SizedBox(
      width: 86,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 76,
            height: 76,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: const ContinuousRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(46))),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [_mix(c, Colors.white, 0.86), _mix(c, Colors.white, 0.66)],
                      ),
                      shadows: [BoxShadow(color: c.withValues(alpha: 0.26), blurRadius: 18, offset: const Offset(0, 8))],
                    ),
                  ),
                ),
                // Inner edge in the category colour.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      shape: ContinuousRectangleBorder(
                        borderRadius: const BorderRadius.all(Radius.circular(46)),
                        side: BorderSide(color: c.withValues(alpha: 0.22), width: 1.2),
                      ),
                    ),
                  ),
                ),
                // Gloss.
                Positioned(
                  top: 7,
                  left: 12,
                  child: Transform.rotate(
                    angle: -0.35,
                    child: Container(
                      width: 26,
                      height: 9,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: MkRadius.all(MkRadius.pill),
                      ),
                    ),
                  ),
                ),
                Center(child: MkCategoryGlyph(categoryKey: categoryKey, iconUrl: iconUrl, emoji: emoji, color: deep, size: 42)),
                if (count > 0)
                  PositionedDirectional(
                    top: -5,
                    end: -5,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 22),
                      height: 22,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: deep,
                        borderRadius: MkRadius.all(MkRadius.pill),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Text(
                        count > 99 ? '99+' : '$count',
                        textDirection: TextDirection.ltr,
                        style: t.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10, height: 1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: t.labelMedium?.copyWith(color: MkColors.ink, fontWeight: FontWeight.w700, height: 1.2),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      label: label,
      child: _PopIn(index: index, child: MkPressable(onTap: onTap, scale: 0.9, child: tile)),
    );
  }
}

/// Scale-and-fade entrance with a short stagger.
class _PopIn extends StatelessWidget {
  const _PopIn({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final delay = math.min(index, 9) * 50;
    final total = 460 + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delay / total, 1, curve: Curves.easeOutBack),
      builder: (context, v, c) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.6 + 0.4 * v, child: c),
      ),
      child: child,
    );
  }
}

/// Filter chip for a category: its logo in a tinted circle and its name.
/// Selected chips fill with the category colour. Pass a null [categoryKey] for "All".
class MkCategoryChip extends StatelessWidget {
  const MkCategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.categoryKey,
    this.color,
    this.iconUrl,
    this.emoji,
    this.floating = false,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? categoryKey;
  final Color? color;
  final String? iconUrl;
  final String? emoji;

  /// Adds a shadow for chips over a map or photo.
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = categoryKey == null ? MkColors.purple900 : (color ?? mkCategoryColor(categoryKey!));
    final on = mkOnColor(c);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: MkPressable(
        onTap: onTap,
        scale: 0.94,
        child: AnimatedContainer(
          duration: MkMotion.base,
          curve: MkMotion.enter,
          height: 42,
          padding: const EdgeInsetsDirectional.only(start: 4, end: 14),
          decoration: BoxDecoration(
            color: selected ? c : MkColors.surface,
            borderRadius: MkRadius.all(MkRadius.pill),
            border: Border.all(color: selected ? c : MkColors.line),
            boxShadow: selected
                ? [BoxShadow(color: c.withValues(alpha: 0.32), blurRadius: 14, offset: const Offset(0, 6))]
                : (floating ? MkShadow.soft : null),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: MkMotion.base,
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? Colors.white : _mix(c, Colors.white, 0.84),
                ),
                child: Center(
                  child: categoryKey == null
                      ? Icon(Icons.apps_rounded, size: 18, color: selected ? MkColors.purple900 : MkColors.purple700)
                      : MkCategoryGlyph(
                          categoryKey: categoryKey!,
                          iconUrl: iconUrl,
                          emoji: emoji,
                          color: _mix(c, MkColors.ink, 0.2),
                          size: 22,
                        ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedDefaultTextStyle(
                duration: MkMotion.base,
                style: (t.labelLarge ?? const TextStyle()).copyWith(
                  color: selected ? on : MkColors.ink,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
                child: Text(label, maxLines: 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
