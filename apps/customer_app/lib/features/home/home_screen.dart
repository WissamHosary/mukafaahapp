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
import '../shops/shop_screen.dart' show RewardTile;

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
      body: RefreshIndicator(
        color: MkColors.purple900,
        onRefresh: () async {
          refreshBalances(ref);
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
    final user = ref.watch(authProvider).user;
    final cart = ref.watch(cartProvider);
    final name = h.name ?? user?.name;

    final url = ref.watch(mediaUrlProvider);
    final cats = ref.watch(categoriesProvider).value ?? h.categories;
    // Tier progress is spend based; the tier endpoint has the exact amounts.
    final tier = ref.watch(tierProvider).value;
    final blocks = h.blocks.isNotEmpty ? h.blocks : _legacyBlocks(h);

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: MkHeroHeader(
            top: Row(
              children: [
                MkPressable(
                  onTap: () => context.go('/profile'),
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      (name == null || name.isEmpty) ? '؟' : name.characters.first.toUpperCase(),
                      style: t.titleMedium?.copyWith(color: MkColors.yellow500, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: MkSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_greeting(s), style: t.bodySmall?.copyWith(color: const Color(0xFFD8CCE6))),
                      Text(
                        (name == null || name.isEmpty) ? s.tr('أهلا فيك بمكافأة!', 'Welcome to Mukafaah!') : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                if (cart.count > 0) ...[
                  MkGlassButton(
                    icon: Icons.shopping_cart_rounded,
                    count: cart.count,
                    label: s.tr('السلة', 'Cart'),
                    onTap: () => context.push('/cart'),
                  ),
                  const SizedBox(width: MkSpace.xs),
                ],
                MkGlassButton(
                  icon: Icons.notifications_rounded,
                  count: h.unreadNotifications,
                  label: s.tr('الإشعارات', 'Notifications'),
                  onTap: () => context.push('/notifications'),
                ),
              ],
            ),
            card: MkEntrance(
              child: MkPointsCard(
                title: s.tr('نقاطك بمكافأة', 'Your Mukafaah points'),
                points: h.balancePoints,
                pointsUnit: s.tr('نقطة', 'pts'),
                caption: s.tr(
                  '≈ ${money(h.balancePoints)} للصرف · وفّرت ${money(h.totalSavingMinor)}',
                  '≈ ${money(h.balancePoints)} to spend · saved ${money(h.totalSavingMinor)}',
                ),
                tier: h.tier,
                tierLabel: s.tier(h.tier),
                progress: tier?.progress ?? h.tierProgress,
                progressLabel: tier == null
                    ? s.tr('شوف مستواك', 'See your tier')
                    : tier.nextCode == null
                        ? s.tr('وصلت لأعلى مستوى', 'Top tier reached')
                        : s.tr(
                            'اصرف ${money(tier.toNextMinor)} كمان لتوصل ${tierName(s, tier.nextName, tier.nextCode!)}',
                            'Spend ${money(tier.toNextMinor)} more to reach ${tierName(s, tier.nextName, tier.nextCode!)}',
                          ),
                qrLabel: s.tr('اعرض رمزي', 'Show my QR'),
                onQr: () => context.go('/wallet'),
                onTier: () => context.push('/tier'),
                onTap: () => context.push('/points'),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.lg, MkSpace.lg, 0),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: MkStagger(
                    index: 1,
                    child: MkActionCard(
                      icon: Icons.toll_rounded,
                      title: s.viewPoints,
                      subtitle: s.tr(
                        '${formatPoints(h.balancePoints)} نقطة · رصيدك وسجلك',
                        '${formatPoints(h.balancePoints)} pts · balances & history',
                      ),
                      onTap: () => context.push('/points'),
                    ),
                  ),
                ),
                const SizedBox(width: MkSpace.sm),
                Expanded(
                  child: MkStagger(
                    index: 2,
                    child: MkActionCard(
                      accent: true,
                      icon: Icons.redeem_rounded,
                      title: s.offersRewards,
                      subtitle: s.tr('خصومات وهدايا من محلاتك', 'Deals and gifts from your shops'),
                      onTap: () => context.push('/offers'),
                    ),
                  ),
                ),
              ],
            ),
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
                            Text(
                              '${formatPoints(h.pendingPrePoints)} ${s.points}',
                              style: t.bodySmall?.copyWith(color: MkColors.purple800),
                            ),
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
        for (var i = 0; i < blocks.length; i++)
          SliverToBoxAdapter(
            child: MkStagger(
              index: i + 3,
              child: _Block(block: blocks[i], home: h, cats: cats),
            ),
          ),
        if (blocks.isEmpty)
          SliverToBoxAdapter(
            child: MkEmptyState(
              icon: Icons.storefront_rounded,
              title: s.noBusinesses,
              message: s.tr('أول ما تنضم محلات رح تبيّن هون.', 'Shops will show here as soon as they join.'),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: MkSpace.xxl)),
      ],
    );
  }
}

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
      if (h.featured.isNotEmpty) HomeBlock(id: 'f', type: 'FEATURED_SHOPS', shops: h.featured),
      if (h.offers.isNotEmpty) HomeBlock(id: 'o', type: 'NEW_OFFERS', offers: h.offers),
      for (final sec in h.sections)
        if (sec.shops.isNotEmpty) HomeBlock(id: 's${sec.category}', type: 'CATEGORY_SHOPS', categoryKey: sec.category, shops: sec.shops),
      const HomeBlock(id: 'r', type: 'RECENT_ACTIVITY'),
    ];

/// One home section, drawn by its type. Titles, order and contents come from Mukafaah Manager.
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

    switch (b.type) {
      case 'CATEGORIES':
        final list = home.categories.isNotEmpty ? home.categories : cats;
        if (list.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: MkSpace.lg),
              child: MkSectionHeader(title: title(s.categories), action: s.seeAll, onAction: () => context.go('/shops')),
            ),
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
      case 'FEATURED_SHOPS' || 'CATEGORY_SHOPS' || 'PICKED_SHOPS':
        if (b.shops.isEmpty) return const SizedBox.shrink();
        final fallback = switch (b.type) {
          'FEATURED_SHOPS' => s.featuredShops,
          'CATEGORY_SHOPS' => categoryName(s, cats, b.categoryKey ?? ''),
          _ => s.shops,
        };
        return MkHorizontalSection(
          title: title(fallback),
          height: 250,
          itemWidth: 200,
          itemCount: b.shops.length,
          action: s.seeAll,
          onAction: b.type == 'CATEGORY_SHOPS' && b.categoryKey != null
              ? () => context.push('/category/${b.categoryKey}')
              : () => context.go('/shops'),
          itemBuilder: (context, i) => MkStagger(index: i, axis: Axis.horizontal, child: ShopCardTile(shop: b.shops[i])),
        );
      case 'NEW_OFFERS':
        if (b.offers.isEmpty) return const SizedBox.shrink();
        return MkHorizontalSection(
          title: title(s.tr('عروض جديدة', 'New offers')),
          height: 256,
          itemWidth: 280,
          itemCount: b.offers.length,
          action: s.seeAll,
          onAction: () => context.push('/offers'),
          itemBuilder: (context, i) => MkStagger(index: i, axis: Axis.horizontal, child: OfferTile(offer: b.offers[i])),
        );
      case 'REWARDS':
        if (b.rewards.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: MkSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MkSectionHeader(title: title(s.rewards), action: s.seeAll, onAction: () => context.push('/offers')),
              for (var i = 0; i < b.rewards.length && i < 4; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: MkSpace.xs),
                  child: MkStagger(index: i, child: RewardTile(reward: b.rewards[i], showShop: true)),
                ),
            ],
          ),
        );
      case 'RECENT_ACTIVITY':
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: MkSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MkSectionHeader(
                title: title(s.tr('آخر العمليات', 'Recent Transactions')),
                action: s.seeAll,
                onAction: () => context.push('/points'),
              ),
              if (home.recent.isEmpty)
                MkCard(
                  child: Row(
                    children: [
                      const MkIconTile(icon: Icons.qr_code_2_rounded),
                      const SizedBox(width: MkSpace.sm),
                      Expanded(child: Text(s.noActivityBody, style: t.bodyMedium?.copyWith(color: MkColors.ink2))),
                    ],
                  ),
                )
              else
                MkCard(
                  padding: const EdgeInsets.symmetric(horizontal: MkSpace.md, vertical: MkSpace.xs),
                  child: Column(children: [for (final it in home.recent) ActivityTile(item: it)]),
                ),
            ],
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return MkSkeleton(
      loading: true,
      child: ListView(
        padding: const EdgeInsets.all(MkSpace.lg),
        children: [
          const SizedBox(height: MkSpace.xxl),
          const Row(
            children: [
              Expanded(child: MkSummaryTile(label: 'Balance Points', value: '0,000')),
              SizedBox(width: MkSpace.sm),
              Expanded(child: MkSummaryTile(label: 'Total Saving', value: r'$000')),
            ],
          ),
          const SizedBox(height: MkSpace.md),
          Container(height: 160, decoration: BoxDecoration(color: MkColors.purple100, borderRadius: MkRadius.all(MkRadius.xl))),
          const SizedBox(height: MkSpace.md),
          const Row(
            children: [
              CircleAvatar(radius: 30),
              SizedBox(width: MkSpace.sm),
              CircleAvatar(radius: 30),
              SizedBox(width: MkSpace.sm),
              CircleAvatar(radius: 30),
            ],
          ),
          const SizedBox(height: MkSpace.md),
          Container(height: 260, decoration: BoxDecoration(color: MkColors.purple100, borderRadius: MkRadius.all(MkRadius.lg))),
        ],
      ),
    );
  }
}
