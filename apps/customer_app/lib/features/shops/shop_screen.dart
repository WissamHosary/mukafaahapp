import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../data/api.dart';
import '../common/common.dart';

class ShopScreen extends ConsumerWidget {
  const ShopScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final shop = ref.watch(shopProvider(id));
    return shop.when(
      data: (d) => _ShopBody(d: d),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: MkErrorState(title: errorText(s, e), retryLabel: s.retry, onRetry: () => ref.invalidate(shopProvider(id))),
      ),
    );
  }
}

class _ShopBody extends ConsumerWidget {
  const _ShopBody({required this.d});
  final ShopDetail d;

  Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final catInfo = ref.watch(categoriesProvider).value;
    final c = d.card;
    final cart = ref.watch(cartProvider);
    final myCart = cart.shopId == c.id ? cart : null;

    return Scaffold(
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
        onRefresh: () async {
          ref.invalidate(shopProvider(c.id));
          await ref.read(shopProvider(c.id).future);
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              expandedHeight: 220,
              backgroundColor: MkColors.purple900,
              foregroundColor: Colors.white,
              title: Text(c.name),
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    MkNetImage(url: url(c.coverUrl), fallbackIcon: Icons.storefront_rounded),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x66000000), Color(0x00000000), Color(0xAA1C1024)],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(MkSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
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
                              Text(c.name, style: t.headlineSmall),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  MkStars(rating: c.rating, count: c.ratingCount),
                                  const SizedBox(width: MkSpace.xs),
                                  MkProgramBadge(type: c.programType, label: s.programType(c.programType)),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(categoryName(s, catInfo, c.category), style: t.bodySmall?.copyWith(color: MkColors.ink3)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: MkSpace.md),
                    Row(
                      children: [
                        Expanded(child: MkSummaryTile(label: s.tr('نقاطك هون', 'Your points here'), value: formatPoints(c.myPoints))),
                        const SizedBox(width: MkSpace.sm),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(color: MkColors.purple50, borderRadius: MkRadius.all(MkRadius.md)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.tr('نقاط مرتجعة', 'Points back'), style: t.labelMedium?.copyWith(color: MkColors.ink2)),
                                const SizedBox(height: 2),
                                Text('${c.earnText}%', style: t.titleLarge?.copyWith(color: MkColors.purple700)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (c.description != null && c.description!.isNotEmpty) ...[
                      const SizedBox(height: MkSpace.md),
                      Text(c.description!, style: t.bodyMedium?.copyWith(color: MkColors.ink2)),
                    ],
                    const SizedBox(height: MkSpace.md),
                    Wrap(
                      spacing: MkSpace.xs,
                      runSpacing: MkSpace.xs,
                      children: [
                        if (c.lat != null && c.lng != null)
                          ActionChip(
                            avatar: const Icon(Icons.directions_rounded, size: 18),
                            label: Text(s.tr('الاتجاهات', 'Directions')),
                            onPressed: () => _open('https://www.google.com/maps/search/?api=1&query=${c.lat},${c.lng}'),
                          ),
                        if (d.instagram != null && d.instagram!.isNotEmpty)
                          ActionChip(
                            avatar: const Icon(Icons.camera_alt_rounded, size: 18),
                            label: const Text('Instagram'),
                            onPressed: () => _open('https://instagram.com/${d.instagram!.replaceAll('@', '')}'),
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.qr_code_2_rounded, size: 18),
                          label: Text(s.myQr),
                          onPressed: () => context.go('/wallet'),
                        ),
                      ],
                    ),
                    if (c.place.isNotEmpty || d.branches.isNotEmpty) ...[
                      const SizedBox(height: MkSpace.sm),
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded, size: 18, color: MkColors.ink3),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              [if (c.place.isNotEmpty) c.place, if (d.branches.length > 1) s.tr('${d.branches.length} فروع', '${d.branches.length} branches')]
                                  .join(' · '),
                              style: t.bodySmall?.copyWith(color: MkColors.ink2),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (d.offers.isNotEmpty)
              SliverToBoxAdapter(
                child: MkHorizontalSection(
                  title: s.offers,
                  height: 256,
                  itemWidth: 280,
                  itemCount: d.offers.length,
                  itemBuilder: (context, i) => OfferTile(offer: d.offers[i]),
                ),
              ),
            if (d.rewards.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: MkSpace.lg),
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
                  padding: const EdgeInsets.symmetric(horizontal: MkSpace.lg),
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
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.sm, MkSpace.lg, 0),
                  child: MkButton(
                    label: s.tr('تسوّق من ${c.name}', 'Shop ${c.name}'),
                    icon: Icons.storefront_rounded,
                    onPressed: () => context.push('/shop/${c.id}/store'),
                  ),
                ),
              ),
            ],
            if (d.canRate)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(MkSpace.lg),
                  child: MkCard(
                    child: Column(
                      children: [
                        Text(s.tr('شو رأيك بـ ${c.name}؟', 'How was ${c.name}?'), style: t.titleSmall),
                        const SizedBox(height: MkSpace.xs),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 1; i <= 5; i++)
                              IconButton(
                                onPressed: () async {
                                  try {
                                    await ref.read(apiProvider).rate(c.id, i);
                                    ref.invalidate(shopProvider(c.id));
                                    if (context.mounted) MkToast.show(context, s.tr('شكراً على تقييمك', 'Thanks for rating'), kind: MkToastKind.success);
                                  } on ApiException catch (e) {
                                    if (context.mounted) MkToast.show(context, s.errorV2(e.code), kind: MkToastKind.error);
                                  }
                                },
                                icon: Icon(
                                  (d.myStars ?? 0) >= i ? Icons.star_rounded : Icons.star_outline_rounded,
                                  color: const Color(0xFFF5B400),
                                  size: 32,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: MkSpace.xxxl)),
          ],
        ),
      ),
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
