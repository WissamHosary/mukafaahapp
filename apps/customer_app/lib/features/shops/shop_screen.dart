import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../data/api.dart';
import '../common/common.dart';
import '../common/map_style.dart';

Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

String _digits(String v) => v.replaceAll(RegExp('[^0-9]'), '');

class ShopScreen extends ConsumerWidget {
  const ShopScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final shop = ref.watch(shopProvider(id));
    return shop.when(
      data: (d) => _ShopBody(d: d),
      loading: () => const _ShopLoading(),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: MkErrorState(title: errorText(s, e), retryLabel: s.retry, onRetry: () => ref.invalidate(shopProvider(id))),
      ),
    );
  }
}

/// Same shape as the page, so opening a shop never flashes a blank screen.
class _ShopLoading extends StatelessWidget {
  const _ShopLoading();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: MkColors.canvas,
      body: Stack(
        children: [
          ListView(
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              Container(height: 270 + top, color: MkColors.purple100),
              Padding(
                padding: const EdgeInsets.all(MkSpace.lg),
                child: MkSkeleton(
                  loading: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _box(200, 26, 8),
                      const SizedBox(height: 10),
                      _box(150, 14, 6),
                      const SizedBox(height: MkSpace.lg),
                      _box(double.infinity, 170, 24),
                      const SizedBox(height: MkSpace.lg),
                      _box(double.infinity, 120, 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Positioned(top: top + 8, left: 12, child: const _RoundButton(icon: Icons.arrow_back_rounded)),
        ],
      ),
    );
  }
}

Widget _box(double w, double h, double r) =>
    Container(width: w, height: h, decoration: BoxDecoration(color: MkColors.purple50, borderRadius: MkRadius.all(r)));

/// White round button floating over the banner.
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, this.onTap, this.tooltip});
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: MkPressable(
        onTap: onTap ?? () => context.canPop() ? context.pop() : context.go('/home'),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94),
            shape: BoxShape.circle,
            boxShadow: const [BoxShadow(color: Color(0x332C123F), blurRadius: 14, offset: Offset(0, 4))],
          ),
          child: Icon(icon, color: MkColors.purple900, size: 22),
        ),
      ),
    );
  }
}

class _ShopBody extends ConsumerWidget {
  const _ShopBody({required this.d});
  final ShopDetail d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final catInfo = ref.watch(categoriesProvider).value;
    final me = ref.watch(myLocationProvider).value;
    final c = d.card;
    final cart = ref.watch(cartProvider);
    final myCart = cart.shopId == c.id ? cart : null;
    final km = (me != null && c.lat != null && c.lng != null)
        ? Geolocator.distanceBetween(me.lat, me.lng, c.lat!, c.lng!) / 1000
        : c.distanceKm;
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: MkColors.canvas,
      bottomNavigationBar: (myCart?.count ?? 0) > 0
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.xs, MkSpace.lg, MkSpace.sm),
                child: MkButton(
                  label: s.tr(
                    'السلة (${myCart!.count}) · ${money(myCart.totalMinor)}',
                    'Cart (${myCart.count}) · ${money(myCart.totalMinor)}',
                  ),
                  icon: Icons.shopping_cart_checkout_rounded,
                  kind: MkButtonKind.accent,
                  onPressed: () => context.push('/cart'),
                ),
              ),
            )
          : null,
      body: RefreshIndicator(
        edgeOffset: top,
        onRefresh: () async {
          ref.invalidate(shopProvider(c.id));
          await ref.read(shopProvider(c.id).future);
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              stretch: true,
              expandedHeight: 270,
              backgroundColor: MkColors.purple900,
              foregroundColor: Colors.white,
              automaticallyImplyLeading: false,
              leadingWidth: 64,
              leading: const Padding(
                padding: EdgeInsetsDirectional.only(start: 12),
                child: Center(child: _RoundButton(icon: Icons.arrow_back_rounded)),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 12),
                  child: _RoundButton(
                    icon: Icons.qr_code_2_rounded,
                    tooltip: s.myQr,
                    onTap: () => context.go('/wallet'),
                  ),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                stretchModes: const [StretchMode.zoomBackground],
                background: _BannerHero(
                  banners: [
                    for (final b in d.banners) ShopBanner(url: url(b.url) ?? b.url, caption: b.caption),
                  ],
                  coverUrl: url(c.coverUrl),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.lg, MkSpace.lg, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MkEntrance(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Hero(
                            tag: 'shop-logo-${c.id}',
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: MkShadow.soft,
                                border: Border.all(color: Colors.white, width: 3),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: MkNetImage(url: url(c.logoUrl), fallbackName: c.name),
                            ),
                          ),
                          const SizedBox(width: MkSpace.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.name, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _RatingChip(rating: c.rating, count: c.ratingCount),
                                    Text(categoryName(s, catInfo, c.category), style: t.bodySmall?.copyWith(color: MkColors.ink2)),
                                    if (km != null)
                                      Text('· ${_fmtKm(km)}', style: t.bodySmall?.copyWith(color: MkColors.ink2, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                                if (d.hours != null && d.hours!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.schedule_rounded, size: 15, color: MkColors.ink3),
                                      const SizedBox(width: 4),
                                      Expanded(child: Text(d.hours!, style: t.bodySmall?.copyWith(color: MkColors.ink3))),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (c.description != null && c.description!.isNotEmpty) ...[
                      const SizedBox(height: MkSpace.sm),
                      MkEntrance(index: 1, child: Text(c.description!, style: t.bodyMedium?.copyWith(color: MkColors.ink2))),
                    ],
                    const SizedBox(height: MkSpace.lg),
                    MkEntrance(index: 2, child: _PointsHero(d: d)),
                    const SizedBox(height: MkSpace.md),
                    MkEntrance(index: 3, child: _QuickActions(d: d)),
                  ],
                ),
              ),
            ),
            if (d.offers.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: MkSpace.md),
                  child: MkHorizontalSection(
                    title: s.offers,
                    height: 256,
                    itemWidth: 280,
                    itemCount: d.offers.length,
                    itemBuilder: (context, i) => OfferTile(offer: d.offers[i]),
                  ),
                ),
              ),
            if (d.rewards.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.md, MkSpace.lg, 0),
                  child: MkSectionHeader(title: s.rewards),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: MkSpace.lg),
                sliver: SliverList.separated(
                  itemCount: d.rewards.length,
                  separatorBuilder: (context, i) => const SizedBox(height: MkSpace.sm),
                  itemBuilder: (context, i) => RewardTile(reward: d.rewards[i]),
                ),
              ),
            ],
            if (d.storeEnabled) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.md, MkSpace.lg, 0),
                  child: MkSectionHeader(
                    title: s.tr('المتجر', 'Shop online'),
                    action: s.tr('افتح المتجر', 'Open store'),
                    onAction: () => context.push('/shop/${c.id}/store'),
                  ),
                ),
              ),
              if (d.products.isNotEmpty)
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 236,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: MkSpace.lg, vertical: 4),
                      scrollDirection: Axis.horizontal,
                      itemCount: d.products.length,
                      separatorBuilder: (context, i) => const SizedBox(width: MkSpace.sm),
                      itemBuilder: (context, i) {
                        final p = d.products[i];
                        return SizedBox(
                          width: 156,
                          child: MkProductCard(
                            name: p.name,
                            imageUrl: url(p.imageUrl),
                            price: money(p.priceMinor),
                            onTap: () => context.push('/shop/${c.id}/product/${p.id}'),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
            if (c.lat != null && c.lng != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.lg, MkSpace.lg, 0),
                  child: _FindUs(d: d, me: me, km: km),
                ),
              ),
            if (!d.social.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.lg, MkSpace.lg, 0),
                  child: _Socials(social: d.social, shopName: c.name),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.lg, MkSpace.lg, 0),
                child: _Reviews(d: d),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: MkSpace.xxxl)),
          ],
        ),
      ),
    );
  }
}

String _fmtKm(double km) => km < 1 ? '${(km * 1000).round()} m' : '${km < 10 ? km.toStringAsFixed(1) : km.round()} km';

class _RatingChip extends StatelessWidget {
  const _RatingChip({required this.rating, required this.count});
  final double rating;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: MkColors.yellow50, borderRadius: MkRadius.all(MkRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 15, color: Color(0xFFF5B400)),
          const SizedBox(width: 2),
          Text(count == 0 ? '–' : rating.toStringAsFixed(1), style: t.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
          Text(' ($count)', style: t.labelSmall?.copyWith(color: MkColors.ink3)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Banners

/// The shop's banners sliding on their own (or the cover photo), with dots.
class _BannerHero extends StatefulWidget {
  const _BannerHero({required this.banners, required this.coverUrl});
  final List<ShopBanner> banners;
  final String? coverUrl;

  @override
  State<_BannerHero> createState() => _BannerHeroState();
}

class _BannerHeroState extends State<_BannerHero> {
  final _page = PageController();
  Timer? _auto;
  int _i = 0;

  int get _count => widget.banners.isEmpty ? 1 : widget.banners.length;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _auto?.cancel();
    if (_count > 1 && !MediaQuery.disableAnimationsOf(context)) {
      _auto = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!_page.hasClients) return;
        _page.animateToPage((_i + 1) % _count, duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubic);
      });
    }
  }

  @override
  void dispose() {
    _auto?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final items = widget.banners.isEmpty ? [ShopBanner(url: widget.coverUrl ?? '')] : widget.banners;
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _page,
          itemCount: items.length,
          onPageChanged: (i) => setState(() => _i = i),
          itemBuilder: (context, i) => AnimatedBuilder(
            animation: _page,
            builder: (context, child) {
              // Slight parallax while swiping.
              final pos = _page.hasClients && _page.position.haveDimensions ? (_page.page ?? 0) - i : 0.0;
              return Transform.translate(offset: Offset(pos * -60, 0), child: child);
            },
            child: MkNetImage(url: items[i].url.isEmpty ? null : items[i].url, fallbackIcon: Icons.storefront_rounded),
          ),
        ),
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x80000000), Color(0x00000000), Color(0x00000000), Color(0x9E1C1024)],
                stops: [0, 0.3, 0.6, 1],
              ),
            ),
          ),
        ),
        if (items[_i].caption != null)
          PositionedDirectional(
            start: MkSpace.lg,
            end: 90,
            bottom: 18,
            child: AnimatedSwitcher(
              duration: MkMotion.base,
              child: Text(
                items[_i].caption!,
                key: ValueKey(_i),
                maxLines: 2,
                style: t.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, shadows: const [Shadow(blurRadius: 8)]),
              ),
            ),
          ),
        if (items.length > 1)
          PositionedDirectional(
            end: MkSpace.lg,
            bottom: 22,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  AnimatedContainer(
                    duration: MkMotion.base,
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    width: i == _i ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _i ? MkColors.yellow500 : Colors.white.withValues(alpha: 0.6),
                      borderRadius: MkRadius.all(3),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Your points + what you get back

/// The most important part of the page: the member's points here, how close
/// the next reward is, and how much of every bill comes back as points.
class _PointsHero extends ConsumerWidget {
  const _PointsHero({required this.d});
  final ShopDetail d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final c = d.card;
    final sorted = [...d.rewards]..sort((a, b) => a.pointsCost.compareTo(b.pointsCost));
    final next = sorted.where((r) => r.pointsCost > c.myPoints).firstOrNull;
    final ready = sorted.where((r) => r.pointsCost <= c.myPoints).lastOrNull;
    final progress = next == null ? 1.0 : (c.myPoints / next.pointsCost).clamp(0.0, 1.0);
    // A $20 bill gives earnPercent of $20 back, at pointsPerDollar points per $1.
    final example = (20 * c.earnPercent / 100 * c.pointsPerDollar).round();

    return ClipRRect(
      borderRadius: MkRadius.all(24),
      child: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.9, -1),
            radius: 1.6,
            colors: [Color(0xFF6A3E99), MkColors.purple700, MkColors.purple900],
            stops: [0, 0.4, 1],
          ),
        ),
        child: MkShine(
          period: const Duration(seconds: 6),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.tr('نقاطك هون', 'Your points here'), style: t.labelLarge?.copyWith(color: Colors.white70)),
                          const SizedBox(height: 2),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0, end: c.myPoints.toDouble()),
                                duration: const Duration(milliseconds: 1100),
                                curve: Curves.easeOutCubic,
                                builder: (context, v, _) => Text(
                                  formatPoints(v.round()),
                                  textDirection: TextDirection.ltr,
                                  style: t.displaySmall?.copyWith(color: MkColors.yellow500, fontWeight: FontWeight.w900, height: 1),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(s.points, style: t.titleSmall?.copyWith(color: Colors.white70)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            s.tr('= ${money((c.myPoints * 100 / math.max(1, c.pointsPerDollar)).round())} تصرفها هون',
                                '= ${money((c.myPoints * 100 / math.max(1, c.pointsPerDollar)).round())} to spend here'),
                            style: t.bodySmall?.copyWith(color: Colors.white60),
                          ),
                        ],
                      ),
                    ),
                    _ReturnMedal(percent: c.earnText, label: s.tr('بيرجعلك', 'comes back')),
                  ],
                ),
                const SizedBox(height: 14),
                if (next != null || ready != null) ...[
                  ClipRRect(
                    borderRadius: MkRadius.all(MkRadius.pill),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: progress),
                      duration: const Duration(milliseconds: 1200),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => LinearProgressIndicator(
                        value: v,
                        minHeight: 8,
                        backgroundColor: Colors.white.withValues(alpha: 0.14),
                        color: MkColors.yellow500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(next == null ? Icons.redeem_rounded : Icons.flag_rounded, size: 16, color: MkColors.yellow200),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          next == null
                              ? s.tr('جاهزة: ${ready!.title}', 'Ready for you: ${ready!.title}')
                              : s.tr('ناقصك ${formatPoints(next.pointsCost - c.myPoints)} نقطة لـ ${next.title}',
                                  '${formatPoints(next.pointsCost - c.myPoints)} more points for ${next.title}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.09),
                    borderRadius: MkRadius.all(MkRadius.md),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long_rounded, color: MkColors.yellow500, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.tr('${c.earnText}% من كل فاتورة بيرجعلك نقاط', '${c.earnText}% of every bill comes back as points'),
                              style: t.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                            ),
                            Text(
                              s.tr('فاتورة \$20 = ${formatPoints(example)} نقطة', 'A \$20 bill = ${formatPoints(example)} points'),
                              style: t.labelSmall?.copyWith(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => context.go('/wallet'),
                        style: FilledButton.styleFrom(
                          backgroundColor: MkColors.yellow500,
                          foregroundColor: MkColors.purple900,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                        label: Text(s.tr('رمزي', 'My QR'), style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Gold medal with the % that comes back, ringed by a slowly turning dotted ring.
class _ReturnMedal extends StatefulWidget {
  const _ReturnMedal({required this.percent, required this.label});
  final String percent;
  final String label;

  @override
  State<_ReturnMedal> createState() => _ReturnMedalState();
}

class _ReturnMedalState extends State<_ReturnMedal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 14));

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
    final t = Theme.of(context).textTheme;
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          RotationTransition(turns: _c, child: const CustomPaint(size: Size(96, 96), painter: _DotRing())),
          Container(
            width: 78,
            height: 78,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFF0A0), MkColors.yellow500, Color(0xFFE0B000)],
              ),
              boxShadow: [BoxShadow(color: Color(0x66FBD404), blurRadius: 18)],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${widget.percent}%',
                  textDirection: TextDirection.ltr,
                  style: t.titleLarge?.copyWith(color: MkColors.purple900, fontWeight: FontWeight.w900, height: 1),
                ),
                Text(widget.label, style: t.labelSmall?.copyWith(color: MkColors.purple900, fontWeight: FontWeight.w700, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DotRing extends CustomPainter {
  const _DotRing();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 2;
    final p = Paint()..color = const Color(0xCCFBD404);
    for (var i = 0; i < 24; i++) {
      final a = i / 24 * math.pi * 2;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r, i.isEven ? 2 : 1.2, p);
    }
  }

  @override
  bool shouldRepaint(_DotRing old) => false;
}

// ---------------------------------------------------------------- Quick actions

class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.d});
  final ShopDetail d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final c = d.card;
    final phone = d.social.phone;
    final wa = d.social.whatsapp;
    final items = <(IconData, String, Color, VoidCallback)>[
      if (c.lat != null && c.lng != null)
        (
          Icons.directions_rounded,
          s.tr('الطريق', 'Directions'),
          const Color(0xFF2563EB),
          () => _open('https://www.google.com/maps/dir/?api=1&destination=${c.lat},${c.lng}'),
        ),
      if (phone != null && phone.isNotEmpty) (Icons.call_rounded, s.tr('اتصل', 'Call'), MkColors.purple700, () => _open('tel:${_digits(phone)}')),
      if (wa != null && wa.isNotEmpty) (Icons.chat_rounded, 'WhatsApp', const Color(0xFF1FAF55), () => _open('https://wa.me/${_digits(wa)}')),
      if (d.storeEnabled) (Icons.storefront_rounded, s.tr('المتجر', 'Store'), const Color(0xFFB86E00), () => context.push('/shop/${c.id}/store')),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        for (final (i, x) in items.indexed) ...[
          if (i > 0) const SizedBox(width: MkSpace.xs),
          Expanded(
            child: MkPressable(
              onTap: x.$4,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: MkRadius.all(MkRadius.lg), boxShadow: MkShadow.soft),
                child: Column(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: x.$3.withValues(alpha: 0.12), shape: BoxShape.circle),
                      child: Icon(x.$1, color: x.$3, size: 21),
                    ),
                    const SizedBox(height: 6),
                    Text(x.$2, maxLines: 1, style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- Map

/// Where the shop is, on a map that is already open when the page scrolls to it.
class _FindUs extends ConsumerWidget {
  const _FindUs({required this.d, required this.me, required this.km});
  final ShopDetail d;
  final ({double lat, double lng})? me;
  final double? km;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final c = d.card;
    final shop = LatLng(c.lat!, c.lng!);
    final you = me == null ? null : LatLng(me!.lat, me!.lng);
    // Show both the shop and the member when they are close enough to share a view.
    final both = you != null && km != null && km! < 15;
    final address = [if ((c.address ?? '').isNotEmpty) c.address!, if ((c.city ?? '').isNotEmpty) c.city!].join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MkSectionHeader(title: s.tr('وين نحنا', 'Find us')),
        Container(
          height: 250,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: MkRadius.all(22), boxShadow: MkShadow.soft, color: MkColors.purple50),
          child: Stack(
            children: [
              FlutterMap(
                options: MapOptions(
                  initialCenter: shop,
                  initialZoom: 15.5,
                  initialCameraFit: both
                      ? CameraFit.coordinates(coordinates: [shop, you], padding: const EdgeInsets.fromLTRB(50, 60, 50, 110), maxZoom: 16)
                      : null,
                  // A still map inside the page; pinch or drag on the full map tab instead.
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                ),
                children: [
                  mukafaahTiles(),
                  MarkerLayer(
                    markers: [
                      if (you != null) Marker(point: you, width: 26, height: 26, child: const _YouDot()),
                      Marker(
                        point: shop,
                        width: 52,
                        height: 64,
                        alignment: Alignment.topCenter,
                        child: MkMapPin(
                          color: MkColors.purple900,
                          size: 52,
                          child: MkNetImage(url: url(c.logoUrl), fallbackName: c.name, cacheWidth: 140),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: MkRadius.all(MkRadius.lg),
                    boxShadow: const [BoxShadow(color: Color(0x332C123F), blurRadius: 18, offset: Offset(0, 6))],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_rounded, color: MkColors.purple700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              address.isEmpty ? c.name : address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              km == null
                                  ? (d.branches.length > 1 ? s.tr('${d.branches.length} فروع', '${d.branches.length} branches') : s.tr('اضغط للطريق', 'Tap for directions'))
                                  : s.tr('${_fmtKm(km!)} منك', '${_fmtKm(km!)} from you'),
                              style: t.labelSmall?.copyWith(color: MkColors.ink3),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _open('https://www.google.com/maps/dir/?api=1&destination=${c.lat},${c.lng}'),
                        style: FilledButton.styleFrom(backgroundColor: MkColors.purple900, visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.near_me_rounded, size: 18),
                        label: Text(s.tr('روح', 'Go')),
                      ),
                    ],
                  ),
                ),
              ),
              const Positioned(
                right: 8,
                top: 6,
                child: Text('© OpenStreetMap', style: TextStyle(fontSize: 9, color: Color(0x99000000))),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _YouDot extends StatelessWidget {
  const _YouDot();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF2563EB),
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: const [BoxShadow(color: Color(0x662563EB), blurRadius: 10, spreadRadius: 2)],
        ),
      );
}

// ---------------------------------------------------------------- Social links

class _Socials extends ConsumerWidget {
  const _Socials({required this.social, required this.shopName});
  final ShopSocial social;
  final String shopName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    String handle(String v) => v.replaceAll('@', '').trim();
    String link(String v, String base) => v.startsWith('http') ? v : '$base${handle(v)}';
    final items = <(String, IconData, Gradient, String)>[
      if (social.instagram?.isNotEmpty ?? false)
        (
          'Instagram',
          Icons.camera_alt_rounded,
          const LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [Color(0xFFFEDA75), Color(0xFFFA7E1E), Color(0xFFD62976), Color(0xFF962FBF), Color(0xFF4F5BD5)]),
          link(social.instagram!, 'https://instagram.com/'),
        ),
      if (social.facebook?.isNotEmpty ?? false)
        ('Facebook', Icons.facebook, const LinearGradient(colors: [Color(0xFF1877F2), Color(0xFF1877F2)]), link(social.facebook!, 'https://facebook.com/')),
      if (social.tiktok?.isNotEmpty ?? false)
        ('TikTok', Icons.music_note_rounded, const LinearGradient(colors: [Color(0xFF111111), Color(0xFF2B2B2B)]), link(social.tiktok!, 'https://www.tiktok.com/@')),
      if (social.whatsapp?.isNotEmpty ?? false)
        ('WhatsApp', Icons.chat_rounded, const LinearGradient(colors: [Color(0xFF25D366), Color(0xFF128C7E)]), 'https://wa.me/${_digits(social.whatsapp!)}'),
      if (social.website?.isNotEmpty ?? false)
        (s.tr('الموقع', 'Website'), Icons.language_rounded, const LinearGradient(colors: [MkColors.purple500, MkColors.purple900]), social.website!),
      if (social.phone?.isNotEmpty ?? false)
        (s.tr('اتصل', 'Call'), Icons.call_rounded, const LinearGradient(colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)]), 'tel:${_digits(social.phone!)}'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MkSectionHeader(title: s.tr('تابع $shopName', 'Follow $shopName')),
        Wrap(
          spacing: MkSpace.md,
          runSpacing: MkSpace.sm,
          children: [
            for (final (i, x) in items.indexed)
              MkEntrance(
                index: i,
                child: Semantics(
                  button: true,
                  label: x.$1,
                  child: MkPressable(
                    onTap: () => _open(x.$4),
                    child: SizedBox(
                      width: 64,
                      child: Column(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              gradient: x.$3,
                              borderRadius: MkRadius.all(18),
                              boxShadow: const [BoxShadow(color: Color(0x262C123F), blurRadius: 12, offset: Offset(0, 5))],
                            ),
                            child: Icon(x.$2, color: Colors.white, size: 26),
                          ),
                          const SizedBox(height: 6),
                          Text(x.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Reviews

class _Reviews extends ConsumerStatefulWidget {
  const _Reviews({required this.d});
  final ShopDetail d;

  @override
  ConsumerState<_Reviews> createState() => _ReviewsState();
}

class _ReviewsState extends ConsumerState<_Reviews> {
  bool _all = false;

  Future<void> _write() async {
    final s = ref.read(stringsProvider);
    final saved = await showMkSheet<bool>(
      context,
      builder: (ctx) => _ReviewSheet(shopId: widget.d.card.id, shopName: widget.d.card.name, stars: widget.d.myStars, comment: widget.d.myComment),
    );
    if (saved == true && mounted) {
      ref.invalidate(shopProvider(widget.d.card.id));
      MkToast.show(context, s.tr('شكراً على تقييمك', 'Thanks for your review'), kind: MkToastKind.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final d = widget.d;
    final total = d.starCounts.fold<int>(0, (a, b) => a + b);
    final list = _all ? d.reviews : d.reviews.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MkSectionHeader(
          title: s.tr('التقييمات', 'Reviews'),
          action: d.canRate ? (d.myStars == null ? s.tr('قيّم', 'Write a review') : s.tr('عدّل تقييمك', 'Edit your review')) : null,
          onAction: d.canRate ? _write : null,
        ),
        Container(
          padding: const EdgeInsets.all(MkSpace.md),
          decoration: BoxDecoration(color: Colors.white, borderRadius: MkRadius.all(20), boxShadow: MkShadow.soft),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                child: Column(
                  children: [
                    Text(
                      total == 0 ? '–' : d.card.rating.toStringAsFixed(1),
                      style: t.displaySmall?.copyWith(fontWeight: FontWeight.w900, color: MkColors.purple900, height: 1),
                    ),
                    const SizedBox(height: 4),
                    MkStars(rating: d.card.rating, size: 15),
                    const SizedBox(height: 4),
                    Text(s.tr('$total تقييم', '$total reviews'), style: t.labelSmall?.copyWith(color: MkColors.ink3)),
                  ],
                ),
              ),
              const SizedBox(width: MkSpace.md),
              Expanded(
                child: Column(
                  children: [
                    for (var n = 5; n >= 1; n--)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            SizedBox(width: 12, child: Text('$n', style: t.labelSmall?.copyWith(color: MkColors.ink3))),
                            const SizedBox(width: 6),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: MkRadius.all(4),
                                child: TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0, end: total == 0 ? 0 : d.starCounts[n - 1] / total),
                                  duration: Duration(milliseconds: 500 + n * 120),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, v, _) => LinearProgressIndicator(
                                    value: v,
                                    minHeight: 7,
                                    backgroundColor: MkColors.purple50,
                                    color: const Color(0xFFF5B400),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: MkSpace.sm),
        if (d.reviews.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: MkSpace.sm),
            child: Text(
              d.canRate
                  ? s.tr('ما في تقييمات بعد. كون أول واحد!', 'No reviews yet. Be the first!')
                  : s.tr('ما في تقييمات بعد. فيك تقيّم بعد أول زيارة.', 'No reviews yet. You can rate after your first visit.'),
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(color: MkColors.ink3),
            ),
          ),
        for (final (i, r) in list.indexed) ...[
          MkEntrance(index: i, child: _ReviewCard(r: r)),
          const SizedBox(height: MkSpace.xs),
        ],
        if (d.reviews.length > 3)
          TextButton(
            onPressed: () => setState(() => _all = !_all),
            child: Text(_all ? s.tr('أقل', 'Show less') : s.tr('كل التقييمات (${d.reviews.length})', 'All reviews (${d.reviews.length})')),
          ),
        if (d.canRate && d.myStars == null) ...[
          const SizedBox(height: MkSpace.xs),
          MkButton(label: s.tr('قيّم ${d.card.name}', 'Rate ${d.card.name}'), icon: Icons.star_rounded, kind: MkButtonKind.secondary, onPressed: _write),
        ],
      ],
    );
  }
}

class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({required this.r});
  final ShopReview r;

  static const _colors = [Color(0xFF7446A8), Color(0xFF0E7C86), Color(0xFFB05A1E), Color(0xFFC2477A), Color(0xFF2554C7), Color(0xFF17895E)];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final color = _colors[r.name.codeUnits.fold<int>(0, (a, b) => a + b) % _colors.length];
    return Container(
      padding: const EdgeInsets.all(MkSpace.sm),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MkRadius.all(MkRadius.lg),
        border: Border.all(color: r.mine ? MkColors.yellow500 : MkColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.14),
            child: Text(r.name.isEmpty ? '?' : r.name[0].toUpperCase(), style: t.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.mine ? s.tr('تقييمك', 'Your review') : r.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(_ago(s, r.at), style: t.labelSmall?.copyWith(color: MkColors.ink3)),
                  ],
                ),
                const SizedBox(height: 2),
                MkStars(rating: r.stars.toDouble(), size: 14),
                if (r.comment != null && r.comment!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(r.comment!, style: t.bodyMedium?.copyWith(color: MkColors.ink2, height: 1.35)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _ago(S s, DateTime at) {
  final d = DateTime.now().difference(at);
  if (d.inDays >= 30) return fmtDate(at.toLocal());
  if (d.inDays >= 1) return s.tr('قبل ${d.inDays} يوم', d.inDays == 1 ? 'Yesterday' : '${d.inDays} days ago');
  if (d.inHours >= 1) return s.tr('قبل ${d.inHours} ساعة', '${d.inHours}h ago');
  return s.tr('هلق', 'Just now');
}

class _ReviewSheet extends ConsumerStatefulWidget {
  const _ReviewSheet({required this.shopId, required this.shopName, this.stars, this.comment});
  final String shopId;
  final String shopName;
  final int? stars;
  final String? comment;

  @override
  ConsumerState<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends ConsumerState<_ReviewSheet> {
  late int _stars = widget.stars ?? 0;
  late final _text = TextEditingController(text: widget.comment ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_stars == 0 || _busy) return;
    final s = ref.read(stringsProvider);
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).rate(widget.shopId, _stars, comment: _text.text);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) MkToast.show(context, s.errorV2(e.code), kind: MkToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final words = [
      '',
      s.tr('سيئ', 'Bad'),
      s.tr('مقبول', 'Okay'),
      s.tr('منيح', 'Good'),
      s.tr('كتير منيح', 'Very good'),
      s.tr('ممتاز', 'Excellent'),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: MkSpace.md),
        Text(s.tr('شو رأيك بـ ${widget.shopName}؟', 'How was ${widget.shopName}?'), textAlign: TextAlign.center, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: MkSpace.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                onPressed: () => setState(() => _stars = i),
                icon: AnimatedScale(
                  scale: _stars == i ? 1.25 : 1,
                  duration: MkMotion.base,
                  curve: MkMotion.emphasized,
                  child: Icon(_stars >= i ? Icons.star_rounded : Icons.star_outline_rounded, color: const Color(0xFFF5B400), size: 40),
                ),
              ),
          ],
        ),
        AnimatedSwitcher(
          duration: MkMotion.fast,
          child: Text(words[_stars], key: ValueKey(_stars), textAlign: TextAlign.center, style: t.titleSmall?.copyWith(color: MkColors.purple700)),
        ),
        const SizedBox(height: MkSpace.md),
        TextField(
          controller: _text,
          maxLength: 500,
          minLines: 3,
          maxLines: 5,
          decoration: InputDecoration(hintText: s.tr('خبّر الناس عن تجربتك (اختياري)', 'Tell others about your visit (optional)')),
        ),
        const SizedBox(height: MkSpace.sm),
        MkButton(label: s.tr('انشر التقييم', 'Post review'), loading: _busy, onPressed: _stars == 0 ? null : _save),
      ],
    );
  }
}

/// Reward row with "can afford" state; redeemed at the counter with the customer's QR.
class RewardTile extends ConsumerWidget {
  const RewardTile({required this.reward, this.showShop = false, super.key});

  final Reward reward;
  final bool showShop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final r = reward;
    final progress = r.pointsCost == 0 ? 1.0 : (r.myPoints / r.pointsCost).clamp(0.0, 1.0);
    return MkCard(
      onTap: showShop ? () => context.push('/shop/${r.businessId}') : null,
      child: Row(
        children: [
          SizedBox(width: 64, height: 64, child: MkNetImage(url: url(r.imageUrl), radius: MkRadius.md, fallbackIcon: Icons.redeem_rounded)),
          const SizedBox(width: MkSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showShop) Text(r.businessName, style: t.labelSmall?.copyWith(color: MkColors.ink3)),
                Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                const SizedBox(height: 2),
                Text('${formatPoints(r.pointsCost)} ${s.points}', style: t.labelLarge?.copyWith(color: MkColors.purple700)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: MkRadius.all(MkRadius.pill),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: MkColors.purple50,
                    color: r.canAfford ? MkColors.success : MkColors.yellow600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  r.canAfford
                      ? s.tr('جاهزة! اعرض رمزك عند الكاشير', 'Ready! Show your QR at the counter')
                      : s.tr('ناقصك ${formatPoints(r.pointsCost - r.myPoints)} نقطة', '${formatPoints(r.pointsCost - r.myPoints)} more points'),
                  style: t.labelSmall?.copyWith(color: r.canAfford ? MkColors.success : MkColors.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
