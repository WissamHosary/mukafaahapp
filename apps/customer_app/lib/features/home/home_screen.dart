import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../data/api.dart';
import '../common/common.dart';

/// Home: the purple header with falling coins and the member's points, the two
/// big buttons, then every section in the order and with the content set in
/// Mukafaah Manager (banners, categories, featured shops, offers, more shops,
/// rewards, recent transactions).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final home = ref.watch(homeProvider);
    // Light status bar icons over the purple header.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: MkColors.canvas,
        body: RefreshIndicator(
          color: MkColors.purple900,
          onRefresh: () async {
            refreshBalances(ref);
            ref.invalidate(myLocationProvider);
            await ref.read(homeProvider.future);
          },
          child: home.when(
            data: (h) => _HomeBody(h: h),
            loading: () => const _HomeSkeleton(),
            error: (e, _) => ListView(
              children: [
                const SizedBox(height: 120),
                MkErrorState(title: errorText(s, e), retryLabel: s.retry, onRetry: () => ref.invalidate(homeProvider)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const _HomeBody({required this.h});
  final HomeData h;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final cats = ref.watch(categoriesProvider).value ?? h.categories;
    final blocks = h.blocks.isNotEmpty ? h.blocks : _legacyBlocks(h);
    final liveOffers = blocks.where((b) => b.type == 'NEW_OFFERS').fold<int>(0, (n, b) => n + b.offers.length);

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        SliverToBoxAdapter(
          // The two big buttons sit half over the purple edge.
          child: Stack(
            children: [
              const Column(children: [_CoinHeader(), SizedBox(height: 66)]),
              PositionedDirectional(
                start: MkSpace.lg,
                end: MkSpace.lg,
                bottom: 0,
                child: Row(
                  children: [
                    Expanded(
                      child: MkStagger(
                        index: 1,
                        child: _BigAction(
                          icon: Icons.toll_rounded,
                          title: s.viewPoints,
                          subtitle: s.tr('${formatPoints(h.balancePoints)} نقطة', '${formatPoints(h.balancePoints)} pts'),
                          onTap: () => context.push('/points'),
                        ),
                      ),
                    ),
                    const SizedBox(width: MkSpace.sm),
                    Expanded(
                      child: MkStagger(
                        index: 2,
                        child: _BigAction(
                          accent: true,
                          icon: Icons.redeem_rounded,
                          title: s.offersRewards,
                          subtitle: liveOffers > 0
                              ? s.tr('$liveOffers عرض شغّال', '$liveOffers live offers')
                              : s.tr('حوالَيك وبكل مكافأة', 'Near you and everywhere'),
                          live: liveOffers > 0,
                          onTap: () => context.push('/offers'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (h.pendingPrePoints > 0)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.md, MkSpace.lg, 0),
            sliver: SliverToBoxAdapter(
              child: MkEntrance(
                index: 1,
                child: MkCard(
                  color: MkColors.yellow500,
                  onTap: () => context.push('/collect'),
                  child: Row(
                    children: [
                      const MkFloat(child: MkCoin(size: 40)),
                      const SizedBox(width: MkSpace.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.pendingBanner, style: t.titleSmall?.copyWith(color: MkColors.purple900)),
                            Text('${formatPoints(h.pendingPrePoints)} ${s.points}', style: t.bodySmall?.copyWith(color: MkColors.purple800)),
                          ],
                        ),
                      ),
                      Text(s.collect, style: t.labelLarge?.copyWith(color: MkColors.purple900)),
                    ],
                  ),
                ),
              ),
            ),
          ),
        // Banners and their layout (UNO, DUO or TRIO) come from Mukafaah Manager; hidden when there are none.
        if (h.banners.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.only(top: MkSpace.lg),
            sliver: SliverToBoxAdapter(
              child: MkStagger(
                index: 3,
                child: MkBannerDeck(
                  layout: h.bannerLayout,
                  itemCount: h.banners.length,
                  itemBuilder: (context, i, slot) {
                    final b = h.banners[i];
                    return MkBannerTile(
                      slot: slot,
                      style: b.style,
                      title: b.title(s.isAr),
                      subtitle: b.subtitle(s.isAr),
                      imageUrl: url(b.imageUrl),
                      actionLabel: b.actionType == 'NONE' ? null : _actionLabel(s, b.actionType),
                      onTap: b.actionType == 'NONE' ? null : () => _openBanner(context, b),
                    );
                  },
                ),
              ),
            ),
          ),
        for (var i = 0; i < blocks.length; i++) SliverToBoxAdapter(child: _Reveal(child: _Block(block: blocks[i], home: h, cats: cats))),
        if (blocks.isEmpty)
          SliverToBoxAdapter(
            child: MkEmptyState(
              icon: Icons.storefront_rounded,
              title: s.noBusinesses,
              message: s.tr('أول ما تنضم محلات رح تبيّن هون.', 'Shops will show here as soon as they join.'),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 120)),
      ],
    );
  }
}

// ---------------------------------------------------------------- Header

/// Purple stage with gold coins falling behind the greeting and the points.
class _CoinHeader extends ConsumerWidget {
  const _CoinHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final h = ref.watch(homeProvider).value;
    final user = ref.watch(authProvider).user;
    final cart = ref.watch(cartProvider);
    final name = (h?.name ?? user?.name ?? '').trim();
    final first = name.split(RegExp(r'\s+')).first;
    final shops = ref.watch(walletProvider).value?.programs.where((p) => p.balance > 0).length;
    final tier = s.tier(h?.tier ?? 'SILVER');
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(36)),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.6, -1),
            radius: 1.3,
            colors: [Color(0xFF6A3CA0), MkColors.purple900],
            stops: [0, 0.6],
          ),
        ),
        child: Stack(
          children: [
            const Positioned.fill(child: _CoinRain()),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.sm, MkSpace.lg, 86),
                child: Column(
                  children: [
                    Row(
                      children: [
                        MkPressable(
                          onTap: () => context.go('/profile'),
                          child: MkAvatar(photoUrl: ref.watch(mediaUrlProvider)(user?.avatarUrl), gender: user?.gender, size: 46),
                        ),
                        const SizedBox(width: MkSpace.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_greeting(s), style: t.bodySmall?.copyWith(color: Colors.white.withValues(alpha: 0.72))),
                              Text(
                                first.isEmpty ? s.tr('أهلا فيك', 'Welcome') : first,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                        if (cart.count > 0) ...[
                          MkGlassButton(icon: Icons.shopping_bag_rounded, count: cart.count, label: s.tr('السلة', 'Cart'), onTap: () => context.push('/cart')),
                          const SizedBox(width: MkSpace.xs),
                        ],
                        MkGlassButton(
                          icon: Icons.notifications_rounded,
                          count: h?.unreadNotifications ?? 0,
                          label: s.tr('الإشعارات', 'Notifications'),
                          onTap: () => context.push('/notifications'),
                        ),
                      ],
                    ),
                    const SizedBox(height: MkSpace.lg),
                    Text(s.tr('نقاطك', 'Your points'), style: t.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.75))),
                    MkPressable(
                      onTap: () => context.push('/points'),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: (h?.balancePoints ?? 0).toDouble()),
                        duration: const Duration(milliseconds: 1500),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => Text(
                          formatPoints(v.round()),
                          textDirection: TextDirection.ltr,
                          style: t.displayMedium?.copyWith(
                            color: MkColors.yellow500,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -2,
                            height: 1.05,
                            fontFeatures: const [ui.FontFeature.tabularFigures()],
                            shadows: const [Shadow(color: Color(0x66FBD404), blurRadius: 30, offset: Offset(0, 8))],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    MkPressable(
                      onTap: () => context.push('/tier'),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(colors: [Color(0xFFFFE97A), Color(0xFFE5B800)]),
                              boxShadow: [BoxShadow(color: Color(0xCCFBD404), blurRadius: 10)],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            shops == null
                                ? s.tr('عضو $tier', '$tier member')
                                : s.tr('عضو $tier · $shops محلات', '$tier member · $shops shop${shops == 1 ? '' : 's'}'),
                            style: t.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mukafaah "M" coins falling behind the header (see MkCoinRain: drawn once, then only moved).
class _CoinRain extends StatelessWidget {
  const _CoinRain();

  @override
  Widget build(BuildContext context) => const MkCoinRain(count: 12, opacity: 0.85);
}

// ---------------------------------------------------------------- Big buttons

/// "View Points" (purple) and "Offers & Rewards" (yellow): a light sweeps
/// across now and then, the icon bobs, and offers show a live dot.
class _BigAction extends StatefulWidget {
  const _BigAction({required this.icon, required this.title, required this.subtitle, required this.onTap, this.accent = false, this.live = false});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool accent;
  final bool live;

  @override
  State<_BigAction> createState() => _BigActionState();
}

class _BigActionState extends State<_BigAction> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 5));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      // The two cards shine at different moments.
      _c.repeat();
      if (widget.accent) _c.value = 0.5;
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
    final fg = widget.accent ? MkColors.purple900 : Colors.white;
    return Semantics(
      button: true,
      label: widget.title,
      child: MkPressable(
        onTap: () {
          unawaited(HapticFeedback.selectionClick());
          widget.onTap();
        },
        child: Container(
          height: 124,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: MkRadius.all(22),
            gradient: RadialGradient(
              center: AlignmentDirectional.topEnd.resolve(Directionality.of(context)),
              radius: 1.4,
              colors: widget.accent
                  ? const [Color(0xFFFFE97A), MkColors.yellow500, Color(0xFFEDB900)]
                  : const [MkColors.purple500, MkColors.purple800, MkColors.purple900],
              stops: const [0, 0.45, 1],
            ),
            boxShadow: [
              BoxShadow(
                color: widget.accent ? const Color(0x8CE9B900) : const Color(0x802C123F),
                blurRadius: 30,
                offset: const Offset(0, 14),
                spreadRadius: -10,
              ),
            ],
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final v = _c.value;
              final bob = math.sin(v * 2 * math.pi * 2);
              // The light crosses during the last 30% of each cycle.
              final sweep = ((v - 0.7) / 0.25).clamp(0.0, 1.0);
              final nudge = v > 0.75 && v < 0.85 ? math.sin((v - 0.75) / 0.1 * math.pi) * 4 : 0.0;
              return Stack(
                children: [
                  PositionedDirectional(
                    end: -40,
                    bottom: -50,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: (widget.accent ? MkColors.purple900 : Colors.white).withValues(alpha: 0.07), width: 18),
                      ),
                    ),
                  ),
                  if (sweep > 0 && sweep < 1)
                    Positioned.fill(
                      child: FractionalTranslation(
                        translation: Offset(-1.2 + 2.4 * sweep, 0),
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment(-1, -0.3),
                              end: Alignment(1, 0.3),
                              colors: [Color(0x00FFFFFF), Color(0x59FFFFFF), Color(0x00FFFFFF)],
                              stops: [0.35, 0.5, 0.65],
                            ),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Transform.translate(
                              offset: Offset(0, -3 * bob),
                              child: Transform.rotate(
                                angle: -0.1 * bob,
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: widget.accent ? MkColors.purple900.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.12),
                                    borderRadius: MkRadius.all(14),
                                  ),
                                  child: Icon(widget.icon, color: widget.accent ? MkColors.purple900 : MkColors.yellow500),
                                ),
                              ),
                            ),
                            const Spacer(),
                            Transform.translate(
                              offset: Offset(nudge * (Directionality.of(context) == TextDirection.rtl ? -1 : 1), 0),
                              child: Icon(Icons.arrow_forward_rounded, size: 20, color: fg.withValues(alpha: 0.7), textDirection: Directionality.of(context)),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text(widget.title, maxLines: 2, style: t.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w800, height: 1.15)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (widget.live) ...[_LiveDot(progress: v), const SizedBox(width: 5)],
                            Flexible(
                              child: Text(
                                widget.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: t.labelSmall?.copyWith(color: fg.withValues(alpha: 0.8), fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    final p = (progress * 3) % 1;
    return SizedBox.square(
      dimension: 14,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 7 + 7 * p,
            height: 7 + 7 * p,
            decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFE2364B).withValues(alpha: 0.5 * (1 - p))),
          ),
          Container(width: 7, height: 7, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE2364B))),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Sections

String _greeting(S s) {
  final h = DateTime.now().hour;
  if (h < 12) return s.tr('صباح الخير', 'Good morning');
  if (h < 18) return s.tr('نهارك سعيد', 'Good afternoon');
  return s.tr('مساء الخير', 'Good evening');
}

String _actionLabel(S s, String type) => switch (type) {
      'SHOP' => s.tr('زور المحل', 'Visit shop'),
      'CATEGORY' => s.tr('تصفّح', 'Browse'),
      'OFFERS' => s.tr('شوف العروض', 'See offers'),
      _ => s.tr('افتح', 'Open'),
    };

String _km(S s, double d) => d < 1 ? '${(d * 1000).round()} ${s.tr('م', 'm')}' : '${d < 10 ? d.toStringAsFixed(1) : d.round()} ${s.tr('كم', 'km')}';

void _openBanner(BuildContext context, HomeBanner b) {
  final v = b.actionValue;
  switch (b.actionType) {
    case 'SHOP' when v != null:
      context.push('/shop/$v');
    case 'CATEGORY' when v != null:
      context.push('/category/$v');
    case 'OFFERS':
      context.push('/offers');
    case 'URL' when v != null:
      final uri = Uri.tryParse(v);
      // Only secure web links from Mukafaah Manager are opened, in the browser.
      if (uri != null && uri.scheme == 'https') launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Home layout for servers that don't send blocks yet (older backend).
List<HomeBlock> _legacyBlocks(HomeData h) => [
      if (h.categories.isNotEmpty) const HomeBlock(id: 'c', type: 'CATEGORIES'),
      if (h.featured.isNotEmpty) HomeBlock(id: 'f', type: 'FEATURED_SHOPS', layout: 'CAROUSEL', shops: h.featured),
      if (h.offers.isNotEmpty) HomeBlock(id: 'o', type: 'NEW_OFFERS', offers: h.offers),
      const HomeBlock(id: 'r', type: 'RECENT_ACTIVITY'),
    ];

/// Slides a section in the first time it is built (as it scrolls into view).
class _Reveal extends StatelessWidget {
  const _Reveal({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (context, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 22 * (1 - v)), child: c)),
      child: child,
    );
  }
}

/// One home section, drawn by its type and layout. Titles, order, contents
/// and look all come from Mukafaah Manager.
class _Block extends ConsumerWidget {
  const _Block({required this.block, required this.home, required this.cats});

  final HomeBlock block;
  final HomeData home;
  final List<CategoryInfo> cats;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final b = block;
    String title(String fallback) {
      final x = b.title(s.isAr);
      return (x == null || x.isEmpty) ? fallback : x;
    }

    Widget header(String text, VoidCallback onAction) => Padding(
          padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.lg, MkSpace.lg, 0),
          child: MkSectionHeader(title: text, action: s.seeAll, onAction: onAction),
        );

    switch (b.type) {
      case 'CATEGORIES':
        final list = home.categories.isNotEmpty ? home.categories : cats;
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header(title(s.categories), () => context.go('/shops')),
            // Logos and colours are set per category in Mukafaah Manager.
            SizedBox(
              height: 132,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(MkSpace.lg, 6, MkSpace.lg, 0),
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: list.length,
                separatorBuilder: (context, i) => const SizedBox(width: MkSpace.xs),
                itemBuilder: (context, i) => MkCategoryCard(
                  index: i,
                  categoryKey: list[i].key,
                  label: list[i].name(s.isAr),
                  emoji: list[i].emoji,
                  iconUrl: url(list[i].iconUrl),
                  color: mkCategoryColor(list[i].key, list[i].color),
                  count: list[i].count,
                  onTap: () => context.push('/category/${list[i].key}'),
                ),
              ),
            ),
          ],
        );
      case 'FEATURED_SHOPS' || 'DISCOVER_SHOPS' || 'CATEGORY_SHOPS' || 'PICKED_SHOPS':
        if (b.shops.isEmpty) return const SizedBox.shrink();
        final fallback = switch (b.type) {
          'FEATURED_SHOPS' => s.featuredShops,
          'DISCOVER_SHOPS' => s.tr('محلات تانية تكتشفها', 'More shops to discover'),
          'CATEGORY_SHOPS' => categoryName(s, cats, b.categoryKey ?? ''),
          _ => s.shops,
        };
        final onAll = b.type == 'CATEGORY_SHOPS' && b.categoryKey != null ? () => context.push('/category/${b.categoryKey}') : () => context.go('/shops');
        switch (b.layout) {
          case 'CAROUSEL':
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [header(title(fallback), onAll), _ShopCarousel(shops: b.shops, cats: cats)],
            );
          case 'GRID':
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [header(title(fallback), onAll), _ShopGrid(shops: b.shops, cats: cats)],
            );
          default:
            return Padding(
              padding: const EdgeInsets.only(top: MkSpace.sm),
              child: MkHorizontalSection(
                title: title(fallback),
                height: 250,
                itemWidth: 200,
                itemCount: b.shops.length,
                action: s.seeAll,
                onAction: onAll,
                itemBuilder: (context, i) => MkStagger(index: i, axis: Axis.horizontal, child: ShopCardTile(shop: b.shops[i])),
              ),
            );
        }
      case 'NEW_OFFERS':
        if (b.offers.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: MkSpace.sm),
          child: MkHorizontalSection(
            title: title(s.tr('عروض جديدة', 'New offers')),
            height: 256,
            itemWidth: 280,
            itemCount: b.offers.length,
            action: s.seeAll,
            onAction: () => context.push('/offers'),
            itemBuilder: (context, i) => MkStagger(index: i, axis: Axis.horizontal, child: OfferTile(offer: b.offers[i])),
          ),
        );
      case 'REWARDS':
        if (b.rewards.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header(title(s.tr('مكافآت إلك', 'Rewards for you')), () => context.push('/offers?tab=rewards')),
            Padding(
              padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.xs, MkSpace.lg, 0),
              child: MkCard(
                padding: const EdgeInsets.symmetric(horizontal: MkSpace.md, vertical: 4),
                child: Column(
                  children: [
                    for (var i = 0; i < b.rewards.length; i++) ...[
                      if (i > 0) const Divider(height: 1, color: MkColors.line),
                      _RewardProgress(reward: b.rewards[i], index: i),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      case 'RECENT_ACTIVITY':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header(title(s.tr('آخر العمليات', 'Recent transactions')), () => context.push('/points')),
            Padding(
              padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.xs, MkSpace.lg, 0),
              child: home.recent.isEmpty
                  ? MkCard(
                      child: Row(
                        children: [
                          const MkIconTile(icon: Icons.qr_code_2_rounded),
                          const SizedBox(width: MkSpace.sm),
                          Expanded(child: Text(s.noActivityBody, style: t.bodyMedium?.copyWith(color: MkColors.ink2))),
                        ],
                      ),
                    )
                  : MkCard(
                      padding: const EdgeInsets.symmetric(horizontal: MkSpace.md, vertical: MkSpace.xs),
                      child: Column(children: [for (final it in home.recent) ActivityTile(item: it)]),
                    ),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ---------------------------------------------------------------- Shops: carousel

/// Big swipeable shop cards. The card in the middle is full size, the others
/// shrink a little; it moves on by itself until the member touches it.
class _ShopCarousel extends StatefulWidget {
  const _ShopCarousel({required this.shops, required this.cats});
  final List<ShopCard> shops;
  final List<CategoryInfo> cats;

  @override
  State<_ShopCarousel> createState() => _ShopCarouselState();
}

class _ShopCarouselState extends State<_ShopCarousel> {
  final _page = PageController(viewportFraction: 0.82);
  Timer? _auto;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (widget.shops.length > 1) {
      _auto = Timer.periodic(const Duration(milliseconds: 3600), (_) {
        if (!mounted || !_page.hasClients || MediaQuery.disableAnimationsOf(context)) return;
        final next = (_index + 1) % widget.shops.length;
        unawaited(_page.animateToPage(next, duration: const Duration(milliseconds: 650), curve: Curves.easeInOutCubic));
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
    return Column(
      children: [
        Listener(
          onPointerDown: (_) => _auto?.cancel(),
          child: SizedBox(
            height: 262,
            child: PageView.builder(
              controller: _page,
              padEnds: true,
              itemCount: widget.shops.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => AnimatedBuilder(
                animation: _page,
                builder: (context, child) {
                  final page = _page.hasClients && _page.position.haveDimensions ? (_page.page ?? 0) : 0.0;
                  final d = (page - i).abs().clamp(0.0, 1.0);
                  return Transform.scale(scale: 1 - 0.07 * d, child: Opacity(opacity: 1 - 0.3 * d, child: child));
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: _ShopCover(shop: widget.shops[i], cats: widget.cats, big: true),
                ),
              ),
            ),
          ),
        ),
        if (widget.shops.length > 1)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.shops.length; i++)
                AnimatedContainer(
                  duration: MkMotion.base,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _index ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(color: i == _index ? MkColors.purple900 : MkColors.line, borderRadius: MkRadius.all(3)),
                ),
            ],
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Shops: grid

class _ShopGrid extends StatelessWidget {
  const _ShopGrid({required this.shops, required this.cats});
  final List<ShopCard> shops;
  final List<CategoryInfo> cats;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.sm, MkSpace.lg, 0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: shops.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: MkSpace.sm,
          crossAxisSpacing: MkSpace.sm,
          mainAxisExtent: 168,
        ),
        itemBuilder: (context, i) => MkStagger(index: i % 6, child: _ShopCover(shop: shops[i], cats: cats)),
      ),
    );
  }
}

/// A shop card with a cover (photo, or the category colour with a dotted
/// pattern), logo, cashback, offers count and distance.
class _ShopCover extends ConsumerWidget {
  const _ShopCover({required this.shop, required this.cats, this.big = false});
  final ShopCard shop;
  final List<CategoryInfo> cats;
  final bool big;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final hex = cats.where((c) => c.key == shop.category).firstOrNull?.color;
    final base = mkCategoryColor(shop.category, hex);
    final cover = url(shop.coverUrl);
    final logoSize = big ? 52.0 : 38.0;
    final place = [shop.city, if (shop.distanceKm != null) _km(s, shop.distanceKm!)].whereType<String>().where((x) => x.isNotEmpty).join(' · ');
    return Semantics(
      button: true,
      label: shop.name,
      child: MkPressable(
        onTap: () => context.push('/shop/${shop.id}'),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: MkRadius.all(big ? 26 : 20),
            border: Border.all(color: MkColors.line, width: 1.4),
            boxShadow: big ? MkShadow.lifted : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: big ? 150 : 92,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (cover != null)
                      MkNetImage(url: cover, cacheWidth: big ? 900 : 480)
                    else ...[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color.lerp(base, Colors.white, 0.28)!, Color.lerp(base, Colors.black, 0.32)!],
                          ),
                        ),
                      ),
                      const CustomPaint(painter: _DotsPainter()),
                    ],
                    PositionedDirectional(
                      start: 10,
                      top: 10,
                      child: Container(
                        width: logoSize,
                        height: logoSize,
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4))],
                        ),
                        child: ClipOval(child: MkNetImage(url: url(shop.logoUrl), fallbackName: shop.name, cacheWidth: 160)),
                      ),
                    ),
                    if (big && shop.offersCount > 0)
                      PositionedDirectional(
                        end: 10,
                        top: 10,
                        child: _Chip(text: s.tr('${shop.offersCount} عروض', '${shop.offersCount} offer${shop.offersCount == 1 ? '' : 's'}'), light: true),
                      ),
                    if (!big && shop.distanceKm != null)
                      PositionedDirectional(end: 8, bottom: 8, child: _Chip(text: _km(s, shop.distanceKm!), dark: true)),
                    if (shop.earnPercent > 0)
                      PositionedDirectional(start: 10, bottom: 10, child: _Chip(text: s.tr('${shop.earnText}% نقاط', '${shop.earnText}% back'))),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(big ? 14 : 11, big ? 10 : 8, big ? 14 : 11, big ? 10 : 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        shop.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: (big ? t.titleMedium : t.titleSmall)?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, size: 15, color: Color(0xFFF2A900)),
                          const SizedBox(width: 2),
                          Text(
                            shop.ratingCount == 0 ? s.tr('جديد', 'New') : '${shop.rating}${big ? ' (${shop.ratingCount})' : ''}',
                            style: t.labelSmall?.copyWith(color: MkColors.ink2, fontWeight: FontWeight.w700),
                          ),
                          if (place.isNotEmpty) ...[
                            Text(' · ', style: t.labelSmall?.copyWith(color: MkColors.ink3)),
                            Flexible(
                              child: Text(place, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelSmall?.copyWith(color: MkColors.ink3)),
                            ),
                          ],
                        ],
                      ),
                      if (big) ...[
                        const Spacer(),
                        Row(
                          children: [
                            MkProgramBadge(type: shop.programType, label: s.programType(shop.programType)),
                            const Spacer(),
                            Text(
                              shop.myPoints > 0 ? '${formatPoints(shop.myPoints)} ${s.tr('نقطة', 'pts')}' : s.tr('جديد إلك', 'New for you'),
                              style: t.titleSmall?.copyWith(color: MkColors.purple700, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.light = false, this.dark = false});
  final String text;
  final bool light;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = dark
        ? (Colors.black.withValues(alpha: 0.45), Colors.white)
        : light
            ? (Colors.white.withValues(alpha: 0.92), MkColors.purple900)
            : (MkColors.yellow500, MkColors.purple900);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: MkRadius.all(MkRadius.pill),
        boxShadow: dark || light ? null : const [BoxShadow(color: Color(0x40000000), blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w800)),
    );
  }
}

class _DotsPainter extends CustomPainter {
  const _DotsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white.withValues(alpha: 0.22);
    canvas
      ..save()
      ..rotate(0.5);
    for (var y = -size.width; y < size.height + size.width; y += 22) {
      for (var x = -size.height; x < size.width + size.height; x += 22) {
        canvas.drawCircle(Offset(x, y), 2.4, p);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DotsPainter old) => false;
}

// ---------------------------------------------------------------- Rewards

/// A reward with how close the member is to it.
class _RewardProgress extends ConsumerWidget {
  const _RewardProgress({required this.reward, required this.index});
  final Reward reward;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final r = reward;
    final p = r.pointsCost == 0 ? 1.0 : (r.myPoints / r.pointsCost).clamp(0.0, 1.0);
    final ok = r.canAfford;
    return InkWell(
      onTap: () => context.push('/shop/${r.businessId}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 44,
              child: ClipRRect(borderRadius: MkRadius.all(14), child: MkNetImage(url: url(r.imageUrl ?? r.businessLogoUrl), fallbackName: r.businessName, cacheWidth: 132)),
            ),
            const SizedBox(width: MkSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  Text(
                    '${r.businessName} · ${formatPoints(r.pointsCost)} ${s.tr('نقطة', 'pts')}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.labelSmall?.copyWith(color: MkColors.ink3),
                  ),
                  const SizedBox(height: 6),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: p),
                    duration: Duration(milliseconds: 1100 + index * 120),
                    curve: Curves.easeOutCubic,
                    builder: (context, v, _) => ClipRRect(
                      borderRadius: MkRadius.all(3),
                      child: Stack(
                        children: [
                          Container(height: 6, color: MkColors.line),
                          FractionallySizedBox(
                            widthFactor: v,
                            child: Container(
                              height: 6,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: ok ? const [MkColors.yellow500, Color(0xFFEDB900)] : const [MkColors.purple500, MkColors.purple900],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: MkSpace.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(color: ok ? MkColors.yellow500 : MkColors.purple50, borderRadius: MkRadius.all(MkRadius.pill)),
              child: Text(
                ok
                    ? s.tr('خده', 'Get it')
                    : s.tr('باقي ${formatPoints(r.pointsCost - r.myPoints)}', '${formatPoints(r.pointsCost - r.myPoints)} to go'),
                style: t.labelSmall?.copyWith(color: ok ? MkColors.purple900 : MkColors.ink3, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Loading

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Container(
          height: 290,
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
            gradient: RadialGradient(center: Alignment(0.6, -1), radius: 1.3, colors: [Color(0xFF6A3CA0), MkColors.purple900], stops: [0, 0.6]),
          ),
          child: const Center(child: CircularProgressIndicator(color: MkColors.yellow500)),
        ),
        MkSkeleton(
          loading: true,
          child: Padding(
            padding: const EdgeInsets.all(MkSpace.lg),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: Container(height: 120, decoration: BoxDecoration(color: MkColors.purple100, borderRadius: MkRadius.all(22)))),
                    const SizedBox(width: MkSpace.sm),
                    Expanded(child: Container(height: 120, decoration: BoxDecoration(color: MkColors.purple100, borderRadius: MkRadius.all(22)))),
                  ],
                ),
                const SizedBox(height: MkSpace.lg),
                Container(height: 240, decoration: BoxDecoration(color: MkColors.purple100, borderRadius: MkRadius.all(26))),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
