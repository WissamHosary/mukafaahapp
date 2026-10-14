import 'dart:async';

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
import '../store/store_screens.dart';

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

class _ShopBody extends ConsumerStatefulWidget {
  const _ShopBody({required this.d});
  final ShopDetail d;

  @override
  ConsumerState<_ShopBody> createState() => _ShopBodyState();
}

class _ShopBodyState extends ConsumerState<_ShopBody> {
  /// 0 = the shop, 1 = its online store.
  int _tab = 0;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _openStore() {
    setState(() => _tab = 1);
    // Bring the tabs to the top so the products start right under them.
    if (_scroll.hasClients && _scroll.offset < 200) {
      _scroll.animateTo(200, duration: MkMotion.slow, curve: MkMotion.standard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final catInfo = ref.watch(categoriesProvider).value;
    final me = ref.watch(myLocationProvider).value;
    final c = d.card;
    final km = (me != null && c.lat != null && c.lng != null)
        ? Geolocator.distanceBetween(me.lat, me.lng, c.lat!, c.lng!) / 1000
        : c.distanceKm;
    final top = MediaQuery.paddingOf(context).top;
    final store = d.storeEnabled;

    return Scaffold(
      backgroundColor: MkColors.canvas,
      bottomNavigationBar: StoreCartBar(shopId: c.id),
      body: RefreshIndicator(
        edgeOffset: top,
        onRefresh: () async {
          ref
            ..invalidate(shopProvider(c.id))
            ..invalidate(shopStoreProvider(c.id));
          await ref.read(shopProvider(c.id).future);
        },
        child: CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverAppBar(
              pinned: true,
              stretch: true,
              expandedHeight: 250,
              backgroundColor: MkColors.purple900,
              foregroundColor: Colors.white,
              automaticallyImplyLeading: false,
              leadingWidth: 64,
              title: Text(c.name, style: t.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
              leading: const Padding(
                padding: EdgeInsetsDirectional.only(start: 12),
                child: Center(child: _RoundButton(icon: Icons.arrow_back_rounded)),
              ),
              actions: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 12),
                  child: _RoundButton(icon: Icons.qr_code_2_rounded, tooltip: s.myQr, onTap: () => context.go('/wallet')),
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                stretchModes: const [StretchMode.zoomBackground],
                background: _BannerHero(
                  banners: [for (final b in d.banners) ShopBanner(url: url(b.url) ?? b.url, caption: b.caption)],
                  coverUrl: url(c.coverUrl),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.lg, MkSpace.lg, MkSpace.sm),
                child: MkEntrance(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: MkShadow.soft, border: Border.all(color: Colors.white, width: 3)),
                        clipBehavior: Clip.antiAlias,
                        child: MkNetImage(url: url(c.logoUrl), fallbackName: c.name),
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
                                if (km != null) Text('· ${_fmtKm(km)}', style: t.bodySmall?.copyWith(color: MkColors.ink2, fontWeight: FontWeight.w700)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            _EarnLine(percent: c.earnText),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (store)
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabsHeader(
                  tab: _tab,
                  top: top + kToolbarHeight,
                  labels: (s.tr('المحل', 'Shop'), s.tr('المتجر أونلاين', 'Online store')),
                  onTap: (i) => i == 1 ? _openStore() : setState(() => _tab = 0),
                ),
              ),
            if (store && _tab == 1) ...[
              const SliverToBoxAdapter(child: _StoreHello()),
              StoreCatalog(shopId: c.id),
            ] else ...[
              if (c.description != null && c.description!.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.sm, MkSpace.lg, 0),
                    child: Text(c.description!, style: t.bodyMedium?.copyWith(color: MkColors.ink2, height: 1.4)),
                  ),
                ),
              if (d.hours != null && d.hours!.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.xs, MkSpace.lg, 0),
                    child: Row(
                      children: [
                        const Icon(Icons.schedule_rounded, size: 16, color: MkColors.purple700),
                        const SizedBox(width: 6),
                        Expanded(child: Text(d.hours!, style: t.bodySmall?.copyWith(color: MkColors.ink2, fontWeight: FontWeight.w600))),
                      ],
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.md, MkSpace.lg, 0),
                  child: _QuickActions(d: d, onStore: _openStore),
                ),
              ),
              if (store)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.lg, MkSpace.lg, 0),
                    child: _StoreTeaser(d: d, onOpen: _openStore),
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
              if (c.lat != null && c.lng != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.lg, MkSpace.lg, 0),
                    child: _FindUs(d: d, me: me, km: km),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.lg, MkSpace.lg, 0),
                  child: _Reviews(d: d),
                ),
              ),
              if (!d.social.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.xl, MkSpace.lg, 0),
                    child: _SocialIcons(social: d.social),
                  ),
                ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: MkSpace.xxxl)),
          ],
        ),
      ),
    );
  }
}

/// "10% of every bill comes back as points", one gold line under the name.
class _EarnLine extends ConsumerWidget {
  const _EarnLine({required this.percent});
  final String percent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 3, 10, 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFFFFF4B8), MkColors.yellow50]),
        borderRadius: MkRadius.all(MkRadius.pill),
        border: Border.all(color: const Color(0x66E9C200)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: MkColors.purple900, borderRadius: MkRadius.all(MkRadius.pill)),
            child: Text('$percent%', textDirection: TextDirection.ltr, style: t.labelMedium?.copyWith(color: MkColors.yellow500, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              s.tr('من كل فاتورة بيرجعلك نقاط', 'of every bill comes back as points'),
              style: t.labelMedium?.copyWith(color: MkColors.purple900, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pinned "Shop | Online store" switch.
class _TabsHeader extends SliverPersistentHeaderDelegate {
  _TabsHeader({required this.tab, required this.top, required this.labels, required this.onTap});
  final int tab;
  final double top;
  final (String, String) labels;
  final ValueChanged<int> onTap;

  static const double _h = 64;

  @override
  double get minExtent => _h;
  @override
  double get maxExtent => _h;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = Theme.of(context).textTheme;
    Widget seg(int i, String label, IconData icon) {
      final on = tab == i;
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          child: GestureDetector(
            onTap: () => onTap(i),
            behavior: HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration: MkMotion.base,
              curve: MkMotion.standard,
              margin: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: on ? MkColors.purple900 : Colors.transparent,
                borderRadius: MkRadius.all(MkRadius.pill),
                boxShadow: on ? const [BoxShadow(color: Color(0x442C123F), blurRadius: 12, offset: Offset(0, 4))] : null,
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 18, color: on ? MkColors.yellow500 : MkColors.ink2),
                  const SizedBox(width: 6),
                  Text(label, style: t.labelLarge?.copyWith(color: on ? Colors.white : MkColors.ink2, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      color: MkColors.canvas,
      padding: const EdgeInsets.fromLTRB(MkSpace.lg, 8, MkSpace.lg, 8),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: MkRadius.all(MkRadius.pill), boxShadow: MkShadow.soft),
        child: Row(children: [seg(0, labels.$1, Icons.storefront_rounded), seg(1, labels.$2, Icons.shopping_bag_rounded)]),
      ),
    );
  }

  @override
  bool shouldRebuild(_TabsHeader old) => old.tab != tab || old.labels != labels;
}

/// Big card on the shop tab that leads into the online store.
class _StoreTeaser extends ConsumerWidget {
  const _StoreTeaser({required this.d, required this.onOpen});
  final ShopDetail d;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final pics = d.products.where((p) => p.imageUrl != null).take(3).toList();
    return MkPressable(
      onTap: onOpen,
      child: Container(
        padding: const EdgeInsets.all(MkSpace.md),
        decoration: BoxDecoration(
          borderRadius: MkRadius.all(22),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFE97A), MkColors.yellow500, Color(0xFFE9B800)]),
          boxShadow: const [BoxShadow(color: Color(0x55E9B800), blurRadius: 20, offset: Offset(0, 10))],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: MkColors.purple900, borderRadius: MkRadius.all(MkRadius.pill)),
                    child: Text(s.tr('متجر أونلاين', 'Online store'), style: t.labelSmall?.copyWith(color: MkColors.yellow500, fontWeight: FontWeight.w900)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    s.tr('اطلب من ${d.card.name}', 'Order from ${d.card.name}'),
                    style: t.titleMedium?.copyWith(color: MkColors.purple900, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.tr('توصيل أو استلام، والطلب بيوصل للمحل على واتساب.', 'Delivery or pickup. Your order goes to the shop on WhatsApp.'),
                    style: t.bodySmall?.copyWith(color: MkColors.purple800),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(s.tr('تسوّق هلق', 'Shop now'), style: t.labelLarge?.copyWith(color: MkColors.purple900, fontWeight: FontWeight.w900)),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded, size: 18, color: MkColors.purple900),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: MkSpace.sm),
            SizedBox(
              width: 104,
              height: 104,
              child: pics.isEmpty
                  ? Container(
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.5), shape: BoxShape.circle),
                      child: const Icon(Icons.shopping_bag_rounded, size: 52, color: MkColors.purple900),
                    )
                  : Stack(
                      children: [
                        for (final (i, p) in pics.indexed)
                          Positioned(
                            left: i * 18.0,
                            top: i * 14.0,
                            child: Transform.rotate(
                              angle: (i - 1) * 0.12,
                              child: Container(
                                width: 64,
                                height: 64,
                                clipBehavior: Clip.antiAlias,
                                decoration: BoxDecoration(
                                  borderRadius: MkRadius.all(16),
                                  border: Border.all(color: Colors.white, width: 3),
                                  boxShadow: MkShadow.soft,
                                ),
                                child: MkNetImage(url: url(p.imageUrl), fallbackIcon: Icons.shopping_bag_rounded),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Top of the store tab: how ordering works, in three short steps.
class _StoreHello extends ConsumerWidget {
  const _StoreHello();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    Widget step(IconData icon, String label) => Expanded(
          child: Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(color: MkColors.yellow500, shape: BoxShape.circle),
                child: Icon(icon, size: 19, color: MkColors.purple900),
              ),
              const SizedBox(height: 4),
              Text(label, textAlign: TextAlign.center, style: t.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(MkSpace.lg, 4, MkSpace.lg, MkSpace.xs),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [MkColors.purple700, MkColors.purple900]),
          borderRadius: MkRadius.all(MkRadius.lg),
        ),
        child: Row(
          children: [
            step(Icons.add_shopping_cart_rounded, s.tr('اختار', 'Pick items')),
            step(Icons.delivery_dining_rounded, s.tr('توصيل أو استلام', 'Delivery or pickup')),
            step(Icons.chat_rounded, s.tr('ابعت على واتساب', 'Send on WhatsApp')),
          ],
        ),
      ),
    );
  }
}

/// The shop's social accounts as icons, at the end of the page.
class _SocialIcons extends ConsumerWidget {
  const _SocialIcons({required this.social});
  final ShopSocial social;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    String handle(String v) => v.replaceAll('@', '').trim();
    String link(String v, String base) => v.startsWith('http') ? v : '$base${handle(v)}';
    final items = <(String, Widget, Gradient, String)>[
      if (social.instagram?.isNotEmpty ?? false)
        (
          'Instagram',
          const CustomPaint(size: Size(24, 24), painter: _InstaGlyph()),
          const LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [Color(0xFFFEDA75), Color(0xFFFA7E1E), Color(0xFFD62976), Color(0xFF962FBF), Color(0xFF4F5BD5)]),
          link(social.instagram!, 'https://instagram.com/'),
        ),
      if (social.tiktok?.isNotEmpty ?? false)
        ('TikTok', const Icon(Icons.tiktok, color: Colors.white, size: 24), const LinearGradient(colors: [Color(0xFF111111), Color(0xFF2B2B2B)]), link(social.tiktok!, 'https://www.tiktok.com/@')),
      if (social.facebook?.isNotEmpty ?? false)
        ('Facebook', const Icon(Icons.facebook, color: Colors.white, size: 26), const LinearGradient(colors: [Color(0xFF1877F2), Color(0xFF0F5FD6)]), link(social.facebook!, 'https://facebook.com/')),
      if (social.whatsapp?.isNotEmpty ?? false)
        ('WhatsApp', const Icon(Icons.chat_rounded, color: Colors.white, size: 23), const LinearGradient(colors: [Color(0xFF25D366), Color(0xFF128C7E)]), 'https://wa.me/${_digits(social.whatsapp!)}'),
      if (social.website?.isNotEmpty ?? false)
        (s.tr('الموقع', 'Website'), const Icon(Icons.language_rounded, color: Colors.white, size: 24), const LinearGradient(colors: [MkColors.purple500, MkColors.purple900]), social.website!),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        Text(s.tr('تابعنا', 'Follow us'), style: t.labelLarge?.copyWith(color: MkColors.ink3, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
        const SizedBox(height: MkSpace.sm),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: MkSpace.md,
          runSpacing: MkSpace.sm,
          children: [
            for (final (i, x) in items.indexed)
              MkEntrance(
                index: i,
                child: Tooltip(
                  message: x.$1,
                  child: Semantics(
                    button: true,
                    label: x.$1,
                    child: MkPressable(
                      onTap: () => _open(x.$4),
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          gradient: x.$3,
                          shape: BoxShape.circle,
                          boxShadow: const [BoxShadow(color: Color(0x332C123F), blurRadius: 12, offset: Offset(0, 5))],
                        ),
                        child: Center(child: x.$2),
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

/// Instagram's camera glyph: rounded square, lens and flash dot.
class _InstaGlyph extends CustomPainter {
  const _InstaGlyph();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.09;
    canvas
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(w * .1, w * .1, w * .8, w * .8), Radius.circular(w * .24)), p)
      ..drawCircle(Offset(w / 2, w / 2), w * .19, p)
      ..drawCircle(Offset(w * .72, w * .28), w * .05, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_InstaGlyph old) => false;
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

// ---------------------------------------------------------------- Quick actions

class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.d, required this.onStore});
  final ShopDetail d;
  final VoidCallback onStore;

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
      if (d.storeEnabled) (Icons.shopping_bag_rounded, s.tr('المتجر', 'Store'), const Color(0xFFB86E00), onStore),
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
        const SizedBox(height: 6),
        Row(
          children: [
            const Icon(Icons.verified_rounded, size: 15, color: MkColors.success),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                s.tr('تقييم واحد لكل شخص بعد زيارة حقيقية. إذا غيّرت النجوم، بينحسب نفس التقييم.',
                    'One review per person, after a real visit. Changing your stars updates the same review.'),
                style: t.labelSmall?.copyWith(color: MkColors.ink3),
              ),
            ),
          ],
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
