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
              SizedBox(height: top + 64),
              Padding(
                padding: const EdgeInsets.all(MkSpace.lg),
                child: MkSkeleton(
                  loading: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [_box(78, 78, 39), const SizedBox(width: MkSpace.lg), Expanded(child: _box(double.infinity, 40, 10))]),
                      const SizedBox(height: MkSpace.md),
                      _box(200, 22, 8),
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

enum _Tab { offers, rewards, store, info }

/// The shop as a social profile: logo with the three numbers that matter
/// (rating, points back, your points), name, about, social links and banners;
/// then Offers, Rewards, Online store and Info as icon tabs; then where the
/// shop is on the map and its star rating.
class _ShopBodyState extends ConsumerState<_ShopBody> {
  _Tab _tab = _Tab.offers;
  final _scroll = ScrollController();
  final _tabsKey = GlobalKey();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _select(_Tab t) {
    setState(() => _tab = t);
    // Keep the tabs in view when the content below them changes.
    final ctx = _tabsKey.currentContext;
    if (ctx != null && _scroll.hasClients) {
      final box = ctx.findRenderObject() as RenderBox?;
      final y = box?.localToGlobal(Offset.zero).dy;
      final top = MediaQuery.paddingOf(context).top + kToolbarHeight;
      if (y != null && y < top) Scrollable.ensureVisible(ctx, duration: MkMotion.base, curve: MkMotion.standard);
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
    final handle = (d.social.instagram ?? '').replaceAll('@', '').trim();
    final tabs = [_Tab.offers, _Tab.rewards, if (d.storeEnabled) _Tab.store, _Tab.info];
    final tab = tabs.contains(_tab) ? _tab : _Tab.offers;
    final banners = [for (final b in d.banners) ShopBanner(url: url(b.url) ?? b.url)];
    final cover = url(c.coverUrl);

    return Scaffold(
      backgroundColor: MkColors.canvas,
      bottomNavigationBar: StoreCartBar(shopId: c.id),
      body: RefreshIndicator(
        edgeOffset: top + kToolbarHeight,
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
              backgroundColor: MkColors.canvas,
              surfaceTintColor: Colors.transparent,
              foregroundColor: MkColors.ink,
              centerTitle: true,
              title: Text(
                handle.isNotEmpty ? handle : c.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              leading: IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.canPop() ? context.pop() : context.go('/home'),
              ),
              actions: [IconButton(tooltip: s.myQr, icon: const Icon(Icons.qr_code_2_rounded), onPressed: () => context.go('/wallet'))],
            ),
            // ---------- Profile ----------
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.xs, MkSpace.lg, 0),
                child: MkEntrance(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 84,
                            height: 84,
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(colors: [Color(0xFFFFE97A), MkColors.yellow500, Color(0xFFE0A800)]),
                              boxShadow: [BoxShadow(color: Color(0x332C123F), blurRadius: 16, offset: Offset(0, 6))],
                            ),
                            child: Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                              child: ClipOval(child: MkNetImage(url: url(c.logoUrl), fallbackName: c.name, cacheWidth: 260)),
                            ),
                          ),
                          const SizedBox(width: MkSpace.md),
                          Expanded(
                            child: Row(
                              children: [
                                _Count(value: c.ratingCount == 0 ? '–' : c.rating.toStringAsFixed(1), label: s.tr('تقييم', 'rating'), star: c.ratingCount > 0),
                                _Count(value: '${c.earnText}%', label: s.tr('نقاط راجعة', 'back')),
                                _Count(value: formatPoints(c.myPoints), label: s.tr('نقاطك', 'your pts')),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: MkSpace.sm),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: c.name),
                            if (c.friends)
                              WidgetSpan(
                                alignment: PlaceholderAlignment.middle,
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.only(start: 6),
                                  child: MkFriendsBadge(size: 20, label: s.tr('من أصدقاء مكافأة: بيقبل نقاط مكافأة', 'Mukafaah Friend: accepts Mukafaah Points')),
                                ),
                              ),
                          ],
                        ),
                        style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      if ((c.description ?? '').isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(c.description!, style: t.bodyMedium?.copyWith(color: MkColors.ink2, height: 1.35)),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (c.temporarilyClosed)
                            MkOpenChip(open: false, label: s.tr('مسكّر مؤقتاً', 'Temporarily closed'))
                          else if (c.openNow != null)
                            MkOpenChip(
                              open: c.openNow!,
                              label: c.openNow!
                                  ? (c.todayHours == null || c.todayHours!.allDay ? s.tr('مفتوح', 'Open') : s.tr('مفتوح لـ ${c.todayHours!.close}', 'Open until ${c.todayHours!.close}'))
                                  : s.tr('مسكّر', 'Closed'),
                            ),
                          if (d.group != null) _GroupChip(g: d.group!),
                          Text(
                            [categoryName(s, catInfo, c.category), if (km != null) _fmtKm(km)].join(' · '),
                            style: t.labelMedium?.copyWith(color: MkColors.ink3),
                          ),
                        ],
                      ),
                      if (!d.social.isEmpty) ...[const SizedBox(height: MkSpace.sm), _SocialPills(social: d.social)],
                    ],
                  ),
                ),
              ),
            ),
            if (banners.isNotEmpty || cover != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.md, MkSpace.lg, 0),
                  child: ClipRRect(
                    borderRadius: MkRadius.all(20),
                    child: AspectRatio(aspectRatio: 16 / 8, child: _BannerHero(banners: banners, coverUrl: cover)),
                  ),
                ),
              ),
            // ---------- Offers / Rewards / Store / Info ----------
            SliverPersistentHeader(
              pinned: true,
              delegate: _IconTabs(
                key: _tabsKey,
                items: [
                  for (final x in tabs)
                    switch (x) {
                      _Tab.offers => (Icons.local_offer_outlined, s.offers, d.offers.length),
                      _Tab.rewards => (Icons.redeem_rounded, s.rewards, d.rewards.length),
                      _Tab.store => (Icons.shopping_bag_outlined, s.tr('المتجر', 'Store'), 0),
                      _Tab.info => (Icons.info_outline_rounded, s.tr('معلومات', 'Info'), 0),
                    },
                ],
                selected: tabs.indexOf(tab),
                onTap: (i) => _select(tabs[i]),
              ),
            ),
            ...switch (tab) {
              _Tab.offers => [
                  d.offers.isEmpty
                      ? _EmptyTab(icon: Icons.local_offer_outlined, text: s.tr('ما في عروض هلق', 'No offers right now'))
                      : SliverPadding(
                          padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.md, MkSpace.lg, 0),
                          sliver: SliverGrid(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisExtent: 150,
                              crossAxisSpacing: MkSpace.sm,
                              mainAxisSpacing: MkSpace.sm,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, i) => MkStagger(index: i, child: _OfferBlock(offer: d.offers[i], index: i)),
                              childCount: d.offers.length,
                            ),
                          ),
                        ),
                ],
              _Tab.rewards => [
                  d.rewards.isEmpty
                      ? _EmptyTab(icon: Icons.redeem_rounded, text: s.tr('ما في مكافآت هلق', 'No rewards right now'))
                      : SliverPadding(
                          padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.md, MkSpace.lg, 0),
                          sliver: SliverGrid(
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisExtent: 150,
                              crossAxisSpacing: MkSpace.sm,
                              mainAxisSpacing: MkSpace.sm,
                            ),
                            delegate: SliverChildBuilderDelegate(
                              (context, i) => MkStagger(index: i, child: _RewardBlock(reward: d.rewards[i])),
                              childCount: d.rewards.length,
                            ),
                          ),
                        ),
                ],
              _Tab.store => [StoreCatalog(shopId: c.id)],
              _Tab.info => [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.md, MkSpace.lg, 0),
                      child: _InfoCard(d: d),
                    ),
                  ),
                ],
            },
            // ---------- Location, then rating ----------
            if (c.lat != null && c.lng != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.xl, MkSpace.lg, 0),
                  child: _FindUs(d: d, me: me, km: km),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.xl, MkSpace.lg, 0),
                child: _StarRating(d: d),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: MkSpace.xxxl)),
          ],
        ),
      ),
    );
  }
}

/// One of the three numbers next to the logo.
class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label, this.star = false});
  final String value;
  final String label;
  final bool star;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: MkColors.purple900),
                ),
              ),
              if (star) const Padding(padding: EdgeInsetsDirectional.only(start: 2), child: Icon(Icons.star_rounded, size: 16, color: Color(0xFFF5B400))),
            ],
          ),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelSmall?.copyWith(color: MkColors.ink3)),
        ],
      ),
    );
  }
}

/// "Shared · Beirut Bites" or "Network · …" (with how much this shop takes).
class _GroupChip extends ConsumerWidget {
  const _GroupChip({required this.g});
  final PointsGroup g;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final shared = g.type == 'SHARED';
    final color = shared ? MkColors.shared : MkColors.network;
    final limit = !shared && (g.maxPercent < 100 || g.maxPoints != null) ? s.tr(' · لحد ${g.maxPercent}%', ' · up to ${g.maxPercent}%') : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: MkRadius.all(MkRadius.pill)),
      child: Text(
        '${shared ? s.shared : s.tr('شبكة', 'Network')} · ${g.name}$limit',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// Instagram, TikTok, Facebook, WhatsApp and website as small pills under the name.
class _SocialPills extends ConsumerWidget {
  const _SocialPills({required this.social});
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
          const CustomPaint(size: Size(15, 15), painter: _InstaGlyph()),
          const LinearGradient(begin: Alignment.bottomLeft, end: Alignment.topRight, colors: [Color(0xFFFEDA75), Color(0xFFFA7E1E), Color(0xFFD62976), Color(0xFF962FBF)]),
          link(social.instagram!, 'https://instagram.com/'),
        ),
      if (social.tiktok?.isNotEmpty ?? false)
        ('TikTok', const Icon(Icons.tiktok, color: Colors.white, size: 15), const LinearGradient(colors: [Color(0xFF111111), Color(0xFF2B2B2B)]), link(social.tiktok!, 'https://www.tiktok.com/@')),
      if (social.facebook?.isNotEmpty ?? false)
        ('Facebook', const Icon(Icons.facebook, color: Colors.white, size: 16), const LinearGradient(colors: [Color(0xFF1877F2), Color(0xFF0F5FD6)]), link(social.facebook!, 'https://facebook.com/')),
      if (social.whatsapp?.isNotEmpty ?? false)
        ('WhatsApp', const Icon(Icons.chat_rounded, color: Colors.white, size: 15), const LinearGradient(colors: [Color(0xFF25D366), Color(0xFF128C7E)]), 'https://wa.me/${_digits(social.whatsapp!)}'),
      if (social.website?.isNotEmpty ?? false)
        (s.tr('الموقع', 'Website'), const Icon(Icons.language_rounded, color: Colors.white, size: 15), const LinearGradient(colors: [MkColors.purple500, MkColors.purple900]), social.website!),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final x in items)
          Semantics(
            button: true,
            label: x.$1,
            child: MkPressable(
              onTap: () => _open(x.$4),
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(gradient: x.$3, borderRadius: MkRadius.all(MkRadius.pill)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    x.$2,
                    const SizedBox(width: 6),
                    Text(x.$1, style: t.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Offers, Rewards, Store and Info as icon tabs that stay at the top while scrolling.
class _IconTabs extends SliverPersistentHeaderDelegate {
  _IconTabs({required this.items, required this.selected, required this.onTap, this.key});
  final List<(IconData, String, int)> items;
  final int selected;
  final ValueChanged<int> onTap;
  final Key? key;

  @override
  double get minExtent => 62;
  @override
  double get maxExtent => 62;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = Theme.of(context).textTheme;
    return Container(
      key: key,
      margin: const EdgeInsets.only(top: MkSpace.sm),
      decoration: BoxDecoration(
        color: MkColors.canvas,
        border: const Border(bottom: BorderSide(color: MkColors.line)),
        boxShadow: overlapsContent || shrinkOffset > 0 ? const [BoxShadow(color: Color(0x142C123F), blurRadius: 12, offset: Offset(0, 4))] : null,
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth / items.length;
          final rtl = Directionality.of(context) == TextDirection.rtl;
          return Stack(
            children: [
              Row(
                children: [
                  for (final (i, x) in items.indexed)
                    Expanded(
                      child: Semantics(
                        selected: i == selected,
                        button: true,
                        child: InkWell(
                          onTap: () => onTap(i),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Badge(
                                isLabelVisible: x.$3 > 0,
                                label: Text('${x.$3}'),
                                backgroundColor: MkColors.yellow500,
                                textColor: MkColors.purple900,
                                child: Icon(x.$1, size: 22, color: i == selected ? MkColors.purple900 : MkColors.ink3),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                x.$2,
                                maxLines: 1,
                                style: t.labelMedium?.copyWith(
                                  color: i == selected ? MkColors.purple900 : MkColors.ink3,
                                  fontWeight: i == selected ? FontWeight.w800 : FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              AnimatedPositioned(
                duration: MkMotion.base,
                curve: MkMotion.emphasized,
                bottom: 0,
                left: (rtl ? items.length - 1 - selected : selected) * w + w * 0.28,
                width: w * 0.44,
                height: 3,
                child: const DecoratedBox(decoration: BoxDecoration(color: MkColors.purple900, borderRadius: BorderRadius.all(Radius.circular(2)))),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  bool shouldRebuild(_IconTabs old) => old.selected != selected || old.items.length != items.length;
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: MkSpace.xl),
        child: Column(
          children: [
            Icon(icon, size: 34, color: MkColors.ink3),
            const SizedBox(height: 6),
            Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: MkColors.ink3)),
          ],
        ),
      ),
    );
  }
}

/// A colourful offer tile: the offer's picture (or a brand gradient), what it costs and its title.
class _OfferBlock extends ConsumerWidget {
  const _OfferBlock({required this.offer, required this.index});
  final Offer offer;
  final int index;

  static const _bgs = [
    [Color(0xFFFF9A59), Color(0xFFC8463F)],
    [Color(0xFF7446A8), MkColors.purple900],
    [Color(0xFF26A69A), Color(0xFF0E5E66)],
    [Color(0xFFF59AC0), Color(0xFF93355F)],
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final img = url(offer.imageUrl);
    final tag = offer.discountPercent != null
        ? '-${offer.discountPercent}%'
        : offer.pointsCost > 0
            ? '${formatPoints(offer.pointsCost)} ${s.tr('نقطة', 'PTS')}'
            : s.tr('مجاني', 'FREE');
    return Semantics(
      button: true,
      label: offer.title,
      child: MkPressable(
        onTap: () => showOfferSheet(context, ref, offer),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: MkRadius.all(18),
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: _bgs[index % _bgs.length]),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (img != null) ...[
                MkNetImage(url: img, cacheWidth: 500),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00000000), Color(0xB3000000)]),
                  ),
                ),
              ],
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: MkRadius.all(MkRadius.pill)),
                      child: Text(tag, style: t.labelSmall?.copyWith(color: MkColors.purple900, fontWeight: FontWeight.w900)),
                    ),
                    const Spacer(),
                    Text(
                      offer.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, height: 1.2),
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

/// A reward tile: gold when it's ready, purple with progress when not yet.
class _RewardBlock extends ConsumerWidget {
  const _RewardBlock({required this.reward});
  final Reward reward;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final r = reward;
    final ready = r.canAfford;
    final progress = r.pointsCost == 0 ? 1.0 : (r.myPoints / r.pointsCost).clamp(0.0, 1.0);
    final fg = ready ? MkColors.purple900 : Colors.white;
    return Semantics(
      label: r.title,
      child: MkPressable(
        onTap: () => showMkSheet<void>(context, builder: (ctx) => RewardTile(reward: r)),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: MkRadius.all(18),
            gradient: ready
                ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFE97A), MkColors.yellow500, Color(0xFFE0A800)])
                : const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF7446A8), MkColors.purple900]),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ready ? s.tr('${formatPoints(r.pointsCost)} نقطة · جاهزة', '${formatPoints(r.pointsCost)} PTS · READY') : '${formatPoints(r.pointsCost)} ${s.tr('نقطة', 'PTS')}',
                style: t.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w900, letterSpacing: 0.3),
              ),
              const Spacer(),
              Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w800, height: 1.2)),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: MkRadius.all(MkRadius.pill),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: fg.withValues(alpha: 0.22),
                  color: ready ? MkColors.purple900 : MkColors.yellow500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                ready ? s.tr('اعرض رمزك عند الكاشير', 'Show your QR at the counter') : s.tr('ناقصك ${formatPoints(r.pointsCost - r.myPoints)}', '${formatPoints(r.pointsCost - r.myPoints)} to go'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.labelSmall?.copyWith(color: fg.withValues(alpha: 0.85)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phone, WhatsApp, address and opening hours.
class _InfoCard extends ConsumerWidget {
  const _InfoCard({required this.d});
  final ShopDetail d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final c = d.card;
    final address = [if ((c.address ?? '').isNotEmpty) c.address!, if ((c.city ?? '').isNotEmpty) c.city!].join(', ');
    final rows = <(IconData, String, String, VoidCallback?)>[
      if ((d.social.phone ?? '').isNotEmpty) (Icons.call_rounded, s.tr('تلفون', 'Phone'), d.social.phone!, () => _open('tel:${_digits(d.social.phone!)}')),
      if ((d.social.whatsapp ?? '').isNotEmpty) (Icons.chat_rounded, 'WhatsApp', d.social.whatsapp!, () => _open('https://wa.me/${_digits(d.social.whatsapp!)}')),
      if (address.isNotEmpty) (Icons.location_on_outlined, s.tr('العنوان', 'Address'), address, null),
      if (d.branches.length > 1) (Icons.storefront_outlined, s.tr('الفروع', 'Branches'), d.branches.join(' · '), null),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rows.isNotEmpty)
          Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: MkRadius.all(MkRadius.lg), border: Border.all(color: MkColors.line)),
            child: Column(
              children: [
                for (final (i, x) in rows.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 56),
                  ListTile(
                    onTap: x.$4,
                    leading: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: MkColors.purple50, borderRadius: MkRadius.all(10)),
                      child: Icon(x.$1, size: 19, color: MkColors.purple700),
                    ),
                    title: Text(x.$2, style: t.labelSmall?.copyWith(color: MkColors.ink3)),
                    subtitle: Text(
                      x.$3,
                      textDirection: x.$1 == Icons.location_on_outlined || x.$1 == Icons.storefront_outlined ? null : TextDirection.ltr,
                      style: t.bodyMedium?.copyWith(color: MkColors.ink, fontWeight: FontWeight.w700),
                    ),
                    trailing: x.$4 == null ? null : const Icon(Icons.chevron_right_rounded, color: MkColors.ink3),
                  ),
                ],
              ],
            ),
          ),
        if (d.openingHours != null || c.temporarilyClosed || (d.hours ?? '').isNotEmpty) ...[
          const SizedBox(height: MkSpace.sm),
          _HoursCard(d: d),
        ],
      ],
    );
  }
}

/// Open now / Closed, today's hours, and the whole week on tap.
class _HoursCard extends ConsumerStatefulWidget {
  const _HoursCard({required this.d});
  final ShopDetail d;

  @override
  ConsumerState<_HoursCard> createState() => _HoursCardState();
}

class _HoursCardState extends ConsumerState<_HoursCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final d = widget.d;
    final c = d.card;
    final week = d.openingHours;
    final days = [
      s.tr('الاثنين', 'Monday'),
      s.tr('الثلاثاء', 'Tuesday'),
      s.tr('الأربعاء', 'Wednesday'),
      s.tr('الخميس', 'Thursday'),
      s.tr('الجمعة', 'Friday'),
      s.tr('السبت', 'Saturday'),
      s.tr('الأحد', 'Sunday'),
    ];
    String range(DayHours? h) => h == null ? s.tr('مسكّر', 'Closed') : (h.allDay ? s.tr('24 ساعة', 'Open 24 hours') : '${h.open} – ${h.close}');
    String opens(String at) {
      final p = at.split(' ');
      if (p.length == 1) return s.tr('بيفتح الساعة $at', 'Opens at $at');
      const keys = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
      final i = keys.indexOf(p[0]);
      return s.tr('بيفتح ${i >= 0 ? days[i] : p[0]} ${p[1]}', 'Opens ${i >= 0 ? days[i] : p[0]} ${p[1]}');
    }

    final String status;
    if (c.temporarilyClosed) {
      status = s.tr('مسكّر مؤقتاً', 'Temporarily closed');
    } else if (c.openNow == true) {
      status = c.todayHours == null || c.todayHours!.allDay ? s.tr('مفتوح هلّق', 'Open now') : s.tr('مفتوح لـ ${c.todayHours!.close}', 'Open until ${c.todayHours!.close}');
    } else if (c.openNow == false) {
      status = c.opensAt == null ? s.tr('مسكّر', 'Closed') : opens(c.opensAt!);
    } else {
      status = '';
    }
    final today = DateTime.now().weekday - 1;
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: MkRadius.all(MkRadius.lg), border: Border.all(color: MkColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: MkRadius.all(MkRadius.lg),
            onTap: week == null ? null : () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 20, color: MkColors.purple700),
                  const SizedBox(width: 10),
                  if (c.openNow != null || c.temporarilyClosed) ...[
                    MkOpenChip(open: c.openNow == true && !c.temporarilyClosed, label: c.openNow == true && !c.temporarilyClosed ? s.tr('مفتوح', 'Open') : s.tr('مسكّر', 'Closed')),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      status.isNotEmpty ? status : (d.hours ?? ''),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: MkColors.ink),
                    ),
                  ),
                  if (week != null) AnimatedRotation(turns: _open ? 0.5 : 0, duration: MkMotion.base, child: const Icon(Icons.expand_more_rounded, color: MkColors.ink3)),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: MkMotion.base,
            curve: MkMotion.standard,
            alignment: Alignment.topCenter,
            child: !_open || week == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: Column(
                      children: [
                        const Divider(height: 1),
                        const SizedBox(height: 6),
                        for (var i = 0; i < 7; i++)
                          Container(
                            margin: const EdgeInsets.symmetric(vertical: 1),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(color: i == today ? MkColors.purple50 : null, borderRadius: MkRadius.all(MkRadius.sm)),
                            child: Row(
                              children: [
                                Text(days[i], style: t.bodyMedium?.copyWith(fontWeight: i == today ? FontWeight.w800 : FontWeight.w500)),
                                const Spacer(),
                                Text(
                                  range(week[i]),
                                  textDirection: TextDirection.ltr,
                                  style: t.bodyMedium?.copyWith(
                                    color: week[i] == null ? MkColors.danger : MkColors.ink,
                                    fontWeight: i == today ? FontWeight.w800 : FontWeight.w500,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (d.hours != null && d.hours!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(d.hours!, style: t.bodySmall?.copyWith(color: MkColors.ink2)),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
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
        // Only a soft shade at the top so the round buttons stay readable; the banners carry no text.
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x59000000), Color(0x00000000)],
                stops: [0, 0.35],
              ),
            ),
          ),
        ),
        if (items.length > 1)
          Positioned(
            left: 0,
            right: 0,
            bottom: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
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
        MkSectionHeader(title: s.tr('الموقع', 'Location')),
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

// ---------------------------------------------------------------- Rating

/// Stars only: the average, how the stars split, and the member's own rating.
/// One rating per person after a real visit; tapping again changes it.
class _StarRating extends ConsumerStatefulWidget {
  const _StarRating({required this.d});
  final ShopDetail d;

  @override
  ConsumerState<_StarRating> createState() => _StarRatingState();
}

class _StarRatingState extends ConsumerState<_StarRating> {
  late int _mine = widget.d.myStars ?? 0;
  bool _busy = false;

  Future<void> _rate(int n) async {
    if (_busy || n == _mine) return;
    final s = ref.read(stringsProvider);
    final before = _mine;
    setState(() {
      _mine = n;
      _busy = true;
    });
    try {
      await ref.read(apiProvider).rate(widget.d.card.id, n);
      ref.invalidate(shopProvider(widget.d.card.id));
      if (mounted) MkToast.show(context, s.tr('شكراً على تقييمك', 'Thanks for rating'), kind: MkToastKind.success);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _mine = before);
        MkToast.show(context, s.errorV2(e.code), kind: MkToastKind.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final d = widget.d;
    final total = d.starCounts.fold<int>(0, (a, b) => a + b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MkSectionHeader(title: s.tr('التقييم', 'Rating')),
        Container(
          padding: const EdgeInsets.all(MkSpace.md),
          decoration: BoxDecoration(color: Colors.white, borderRadius: MkRadius.all(20), border: Border.all(color: MkColors.line)),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 96,
                    child: Column(
                      children: [
                        Text(total == 0 ? '–' : d.card.rating.toStringAsFixed(1), style: t.displaySmall?.copyWith(fontWeight: FontWeight.w900, color: MkColors.purple900, height: 1)),
                        const SizedBox(height: 4),
                        MkStars(rating: d.card.rating, size: 15),
                        const SizedBox(height: 4),
                        Text(s.tr('$total تقييم', '$total ratings'), style: t.labelSmall?.copyWith(color: MkColors.ink3)),
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
                                      builder: (context, v, _) => LinearProgressIndicator(value: v, minHeight: 7, backgroundColor: MkColors.purple50, color: const Color(0xFFF5B400)),
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
              const Divider(height: MkSpace.xl),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      d.canRate ? (_mine == 0 ? s.tr('قيّم المحل', 'Your rating') : s.tr('تقييمك', 'Your rating')) : s.tr('فيك تقيّم بعد أول زيارة', 'Rate after your first visit'),
                      style: t.labelLarge?.copyWith(color: d.canRate ? MkColors.ink : MkColors.ink3),
                    ),
                  ),
                  for (var i = 1; i <= 5; i++)
                    Semantics(
                      button: true,
                      label: s.tr('$i نجوم', '$i star${i > 1 ? 's' : ''}'),
                      selected: _mine == i,
                      child: InkResponse(
                        onTap: d.canRate ? () => _rate(i) : null,
                        radius: 22,
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: AnimatedScale(
                            scale: _mine == i ? 1.2 : 1,
                            duration: MkMotion.base,
                            curve: MkMotion.emphasized,
                            child: Icon(
                              _mine >= i ? Icons.star_rounded : Icons.star_outline_rounded,
                              size: 30,
                              color: d.canRate ? const Color(0xFFF5B400) : MkColors.line,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
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
