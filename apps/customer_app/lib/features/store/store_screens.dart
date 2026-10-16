import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../data/api.dart';
import '../common/common.dart';

String _priceText(S s, StoreProduct p) =>
    p.maxPriceMinor > p.priceMinor ? s.tr('من ${money(p.priceMinor)}', 'From ${money(p.priceMinor)}') : money(p.priceMinor);

String? _saleText(int price, int? compareAt) {
  if (compareAt == null || compareAt <= price || compareAt == 0) return null;
  return '-${((compareAt - price) * 100 / compareAt).round()}%';
}

/// Adds a product or variant; asks to empty the cart if it holds another shop's items.
bool _addToCart(BuildContext context, WidgetRef ref, String shopId, String shopName, CartLine line) {
  final s = ref.read(stringsProvider);
  final ok = ref.read(cartProvider.notifier).add(shopId, shopName, line);
  if (!ok) {
    MkToast.show(
      context,
      s.tr('سلتك فيها أغراض من محل تاني. فرّغها أول.', 'Your cart has items from another shop. Empty it first.'),
      kind: MkToastKind.error,
    );
  } else {
    MkToast.show(context, s.tr('انضاف عالسلة', 'Added to cart'), kind: MkToastKind.success);
  }
  return ok;
}

/// Cart icon with a count, for app bars.
class _CartButton extends ConsumerWidget {
  const _CartButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final cart = ref.watch(cartProvider);
    return MkBadgeIcon(icon: Icons.shopping_bag_outlined, count: cart.count, onTap: () => context.push('/cart'))
        .withTooltip(s.tr('السلة', 'Cart'));
  }
}

extension on Widget {
  Widget withTooltip(String text) => Tooltip(message: text, child: this);
}

// =====================================================================
// Store: categories, search and the product grid
// =====================================================================
class StoreScreen extends ConsumerStatefulWidget {
  const StoreScreen({required this.shopId, super.key});
  final String shopId;

  @override
  ConsumerState<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends ConsumerState<StoreScreen> {
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final data = ref.watch(shopStoreProvider(widget.shopId));
    return Scaffold(
      appBar: AppBar(
        title: Text(data.value?.shopName ?? s.tr('المتجر', 'Store')),
        centerTitle: true,
        actions: const [_CartButton(), SizedBox(width: 4)],
      ),
      bottomNavigationBar: StoreCartBar(shopId: widget.shopId),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(shopStoreProvider(widget.shopId));
          await ref.read(shopStoreProvider(widget.shopId).future);
        },
        child: CustomScrollView(slivers: [StoreCatalog(shopId: widget.shopId)]),
      ),
    );
  }
}

/// "View cart" bar shown under a store while its cart has items.
class StoreCartBar extends ConsumerWidget {
  const StoreCartBar({required this.shopId, super.key});
  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final cart = ref.watch(cartProvider);
    if (cart.shopId != shopId || cart.count == 0) return const SizedBox.shrink();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.xs, MkSpace.lg, MkSpace.sm),
        child: MkButton(
          label: s.tr('السلة (${cart.count}) · ${money(cart.totalMinor)}', 'View cart (${cart.count}) · ${money(cart.totalMinor)}'),
          icon: Icons.shopping_bag_rounded,
          kind: MkButtonKind.accent,
          onPressed: () => context.push('/cart'),
        ),
      ),
    );
  }
}

/// The shop's online store as slivers: search, sort, categories and the
/// product grid. Used on its own page and in the shop page's store tab.
class StoreCatalog extends ConsumerStatefulWidget {
  const StoreCatalog({required this.shopId, super.key});
  final String shopId;

  @override
  ConsumerState<StoreCatalog> createState() => _StoreCatalogState();
}

class _StoreCatalogState extends ConsumerState<StoreCatalog> {
  String? _cat;
  String _q = '';
  String _sort = 'featured';

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final data = ref.watch(shopStoreProvider(widget.shopId));

    return data.when(
      loading: () => SliverPadding(
        padding: const EdgeInsets.all(MkSpace.lg),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 220,
            mainAxisExtent: 268,
            crossAxisSpacing: MkSpace.sm,
            mainAxisSpacing: MkSpace.sm,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => DecoratedBox(decoration: BoxDecoration(color: MkColors.purple50, borderRadius: MkRadius.all(MkRadius.lg))),
            childCount: 4,
          ),
        ),
      ),
      error: (e, _) => SliverToBoxAdapter(
        child: MkErrorState(
          title: errorText(s, e),
          retryLabel: s.retry,
          onRetry: () => ref.invalidate(shopStoreProvider(widget.shopId)),
        ),
      ),
      data: (d) {
        final list = d.products
            .where((p) => (_cat == null || p.categoryId == _cat) && (_q.isEmpty || p.name.toLowerCase().contains(_q.toLowerCase())))
            .toList();
        if (_sort == 'low') list.sort((a, b) => a.priceMinor.compareTo(b.priceMinor));
        if (_sort == 'high') list.sort((a, b) => b.priceMinor.compareTo(a.priceMinor));
        final catName = _cat == null ? s.tr('كل المنتجات', 'All products') : d.categories.firstWhere((c) => c.id == _cat, orElse: () => (id: '', name: '', imageUrl: null)).name;
        return SliverMainAxisGroup(
          slivers: [
            if (d.categories.isNotEmpty)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 108,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.sm, MkSpace.lg, 0),
                    scrollDirection: Axis.horizontal,
                    itemCount: d.categories.length + 1,
                    separatorBuilder: (context, i) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      if (i == 0) {
                        return _CatTile(label: s.all, selected: _cat == null, icon: Icons.grid_view_rounded, onTap: () => setState(() => _cat = null));
                      }
                      final c = d.categories[i - 1];
                      return _CatTile(
                        label: c.name,
                        imageUrl: url(c.imageUrl),
                        selected: _cat == c.id,
                        onTap: () => setState(() => _cat = _cat == c.id ? null : c.id),
                      );
                    },
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.sm, MkSpace.lg, 0),
              sliver: SliverToBoxAdapter(
                child: MkSearchField(hint: s.tr('دوّر عن منتج', 'Search products'), onChanged: (v) => setState(() => _q = v.trim())),
              ),
            ),
            if (!d.canOrder)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.sm, MkSpace.lg, 0),
                  child: MkCard(
                    color: MkColors.warningBg,
                    child: Text(
                      s.tr('المحل لسا ما حط رقم واتساب، فما فيك تطلب هلق.', "This shop hasn't added a WhatsApp number yet, so orders are off for now."),
                      style: t.bodySmall?.copyWith(color: MkColors.warning),
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.md, MkSpace.md, MkSpace.xs),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: catName, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                            TextSpan(text: '  ${list.length}', style: t.labelLarge?.copyWith(color: MkColors.ink3)),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: s.tr('ترتيب', 'Sort'),
                      initialValue: _sort,
                      onSelected: (v) => setState(() => _sort = v),
                      itemBuilder: (ctx) => [
                        PopupMenuItem(value: 'featured', child: Text(s.tr('المميز أولاً', 'Featured'))),
                        PopupMenuItem(value: 'low', child: Text(s.tr('السعر: من الأقل', 'Price: low to high'))),
                        PopupMenuItem(value: 'high', child: Text(s.tr('السعر: من الأعلى', 'Price: high to low'))),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.swap_vert_rounded, size: 18, color: MkColors.purple700),
                            const SizedBox(width: 4),
                            Text(
                              switch (_sort) { 'low' => s.tr('الأرخص', 'Lowest price'), 'high' => s.tr('الأغلى', 'Highest price'), _ => s.tr('المميز', 'Featured') },
                              style: t.labelLarge?.copyWith(color: MkColors.purple700),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (list.isEmpty)
              SliverToBoxAdapter(
                child: MkEmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: s.tr('ما في منتجات هون', 'No products here'),
                  message: s.tr('جرّب فئة تانية أو كلمة تانية.', 'Try another category or search.'),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.xs, MkSpace.lg, MkSpace.xxl),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 220,
                    mainAxisExtent: 268,
                    crossAxisSpacing: MkSpace.sm,
                    mainAxisSpacing: MkSpace.md,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    childCount: list.length,
                    (context, i) => MkStagger(
                      index: i % 8,
                      child: _ProductTile(shopId: widget.shopId, shopName: d.shopName, canOrder: d.canOrder, p: list[i]),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Category tile: the category's picture (from Manager) in a rounded square.
class _CatTile extends StatelessWidget {
  const _CatTile({required this.label, required this.selected, required this.onTap, this.imageUrl, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? imageUrl;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: MkPressable(
        onTap: onTap,
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              AnimatedContainer(
                duration: MkMotion.base,
                width: 66,
                height: 66,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  borderRadius: MkRadius.all(20),
                  border: Border.all(color: selected ? MkColors.purple700 : Colors.transparent, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: MkRadius.all(16),
                  child: imageUrl != null
                      ? MkNetImage(url: imageUrl, fallbackIcon: Icons.category_rounded, cacheWidth: 200)
                      : ColoredBox(
                          color: selected ? MkColors.purple900 : MkColors.purple50,
                          child: Icon(icon ?? Icons.category_rounded, color: selected ? MkColors.yellow500 : MkColors.purple700),
                        ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: t.labelMedium?.copyWith(fontWeight: selected ? FontWeight.w800 : FontWeight.w600, color: selected ? MkColors.purple900 : MkColors.ink2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A product in the grid: photo, name, price, and add right from the grid
/// (a quantity stepper once it's in the cart). Products with options open
/// their page to choose.
class _ProductTile extends ConsumerWidget {
  const _ProductTile({required this.shopId, required this.shopName, required this.canOrder, required this.p});
  final String shopId;
  final String shopName;
  final bool canOrder;
  final StoreProduct p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final cart = ref.watch(cartProvider);
    final inCart = cart.shopId == shopId ? cart.lines.where((l) => l.key == p.id).firstOrNull : null;
    final sale = _saleText(p.priceMinor, p.compareAtMinor);
    void open() => context.push('/shop/$shopId/product/${p.id}');

    final Widget action;
    if (!p.inStock || !canOrder) {
      action = const SizedBox.shrink();
    } else if (p.hasVariants) {
      action = _RoundAdd(icon: Icons.tune_rounded, tooltip: s.tr('اختار', 'Choose options'), onTap: open, light: true);
    } else if (inCart != null) {
      action = Container(
        height: 34,
        decoration: BoxDecoration(color: MkColors.purple900, borderRadius: MkRadius.all(MkRadius.pill)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepBtn(icon: inCart.qty == 1 ? Icons.delete_outline_rounded : Icons.remove_rounded, onTap: () => ref.read(cartProvider.notifier).setQty(inCart.key, inCart.qty - 1)),
            Text('${inCart.qty}', style: t.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
            _StepBtn(
              icon: Icons.add_rounded,
              onTap: inCart.maxQty != null && inCart.qty >= inCart.maxQty! ? null : () => ref.read(cartProvider.notifier).setQty(inCart.key, inCart.qty + 1),
            ),
          ],
        ),
      );
    } else {
      action = _RoundAdd(
        icon: Icons.add_rounded,
        tooltip: s.tr('أضف عالسلة', 'Add to cart'),
        onTap: () => _addToCart(
          context,
          ref,
          shopId,
          shopName,
          CartLine(productId: p.id, name: p.name, priceMinor: p.priceMinor, qty: 1, imageUrl: p.imageUrl, maxQty: p.trackStock ? p.stock : null),
        ),
      );
    }

    return Semantics(
      button: true,
      label: p.name,
      child: GestureDetector(
        onTap: open,
        behavior: HitTestBehavior.opaque,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F1F7),
                  borderRadius: MkRadius.all(MkRadius.lg),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Hero(tag: 'p-${p.id}', child: MkNetImage(url: url(p.imageUrl), fallbackIcon: Icons.shopping_bag_outlined, cacheWidth: 520)),
                    if (!p.inStock)
                      ColoredBox(
                        color: Colors.white.withValues(alpha: 0.55),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: MkColors.ink, borderRadius: MkRadius.all(MkRadius.pill)),
                            child: Text(s.tr('خلصت الكمية', 'Sold out'), style: t.labelSmall?.copyWith(color: Colors.white)),
                          ),
                        ),
                      ),
                    if (sale != null && p.inStock)
                      PositionedDirectional(
                        top: 8,
                        start: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(color: MkColors.danger, borderRadius: MkRadius.all(MkRadius.pill)),
                          child: Text(sale, style: t.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    if (p.featured)
                      PositionedDirectional(
                        top: 8,
                        end: 8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: MkColors.yellow500, shape: BoxShape.circle),
                          child: const Icon(Icons.star_rounded, size: 13, color: MkColors.purple900),
                        ),
                      ),
                    PositionedDirectional(bottom: 8, end: 8, child: action),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.25)),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    _priceText(s, p),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: MkColors.purple900),
                  ),
                ),
                if (p.compareAtMinor != null && p.compareAtMinor! > p.priceMinor) ...[
                  const SizedBox(width: 6),
                  Text(
                    money(p.compareAtMinor!),
                    style: t.labelSmall?.copyWith(color: MkColors.ink3, decoration: TextDecoration.lineThrough),
                  ),
                ],
              ],
            ),
            if (p.hasVariants)
              Text(
                p.options.map((o) => '${o.values.length} ${o.name.toLowerCase()}').join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.labelSmall?.copyWith(color: MkColors.ink3, fontWeight: FontWeight.w500),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoundAdd extends StatelessWidget {
  const _RoundAdd({required this.icon, required this.tooltip, required this.onTap, this.light = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool light;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: MkPressable(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: light ? Colors.white : MkColors.purple900,
            shape: BoxShape.circle,
            boxShadow: const [BoxShadow(color: Color(0x332C123F), blurRadius: 10, offset: Offset(0, 4))],
          ),
          child: Icon(icon, size: 20, color: light ? MkColors.purple900 : MkColors.yellow500),
        ),
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 18,
      child: SizedBox(width: 32, height: 34, child: Icon(icon, size: 17, color: onTap == null ? Colors.white38 : MkColors.yellow500)),
    );
  }
}

// =====================================================================
// Product: gallery, options, quantity, add to cart
// =====================================================================
class ProductScreen extends ConsumerStatefulWidget {
  const ProductScreen({required this.shopId, required this.productId, super.key});
  final String shopId;
  final String productId;

  @override
  ConsumerState<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends ConsumerState<ProductScreen> {
  final _pages = PageController();
  int _page = 0;
  int _qty = 1;
  bool _more = false;
  List<String?>? _chosen;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Can [value] for option [i] still be bought with the other choices made so far?
  bool _available(StoreProduct p, int i, String value) {
    final chosen = _chosen ?? List<String?>.filled(p.options.length, null);
    return p.variants.any((v) {
      if (!v.inStock || v.optionValues.length != chosen.length || v.optionValues[i] != value) return false;
      for (var k = 0; k < chosen.length; k++) {
        if (k != i && chosen[k] != null && v.optionValues[k] != chosen[k]) return false;
      }
      return true;
    });
  }

  void _goTo(int i) {
    if (_pages.hasClients) _pages.animateToPage(i, duration: MkMotion.slow, curve: MkMotion.standard);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final data = ref.watch(storeProductProvider((shopId: widget.shopId, productId: widget.productId)));
    final store = ref.watch(shopStoreProvider(widget.shopId)).value;

    return data.when(
      loading: () => Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: MkErrorState(
          title: errorText(s, e),
          retryLabel: s.retry,
          onRetry: () => ref.invalidate(storeProductProvider((shopId: widget.shopId, productId: widget.productId))),
        ),
      ),
      data: (p) {
        final chosen = _chosen ??= List<String?>.filled(p.options.length, null);
        final variant = p.hasVariants ? p.variantFor(chosen) : null;
        final price = variant?.priceMinor ?? p.priceMinor;
        final compareAt = variant?.compareAtMinor ?? p.compareAtMinor;
        final stock = p.hasVariants ? variant?.stock : (p.trackStock ? p.stock : null);
        final inStock = p.hasVariants ? (variant?.inStock ?? p.inStock) : p.inStock;
        final missing = p.hasVariants && variant == null;
        final images = [
          ...p.imageUrls,
          if (variant?.imageUrl != null && !p.imageUrls.contains(variant!.imageUrl)) variant.imageUrl!,
        ];
        final canOrder = store?.canOrder ?? true;
        final ful = store?.fulfilment ?? const StoreFulfilment();
        final sale = _saleText(price, compareAt);
        final firstMissing = missing ? chosen.indexOf(null) : -1;
        final w = MediaQuery.sizeOf(context).width;

        return Scaffold(
          backgroundColor: MkColors.surface,
          bottomNavigationBar: SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.sm, MkSpace.lg, MkSpace.sm),
              decoration: const BoxDecoration(
                color: MkColors.surface,
                border: Border(top: BorderSide(color: MkColors.line)),
              ),
              child: Row(
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.tr('المجموع', 'Total'), style: t.labelSmall?.copyWith(color: MkColors.ink3)),
                      AnimatedSwitcher(
                        duration: MkMotion.fast,
                        child: Text(
                          missing && p.maxPriceMinor > p.priceMinor ? _priceText(s, p) : money(price * _qty),
                          key: ValueKey('$price$_qty$missing'),
                          style: t.titleLarge?.copyWith(fontWeight: FontWeight.w900, color: MkColors.purple900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: MkSpace.md),
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: MkColors.purple900,
                          foregroundColor: MkColors.yellow500,
                          disabledBackgroundColor: MkColors.purple100,
                          disabledForegroundColor: MkColors.ink3,
                          shape: RoundedRectangleBorder(borderRadius: MkRadius.all(18)),
                          textStyle: t.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        onPressed: !inStock || missing || !canOrder
                            ? null
                            : () {
                                final ok = _addToCart(
                                  context,
                                  ref,
                                  widget.shopId,
                                  store?.shopName ?? '',
                                  CartLine(
                                    productId: p.id,
                                    variantId: variant?.id,
                                    name: p.name,
                                    variantLabel: variant?.label,
                                    priceMinor: price,
                                    qty: _qty,
                                    imageUrl: variant?.imageUrl ?? p.imageUrl,
                                    maxQty: stock,
                                  ),
                                );
                                if (ok) setState(() => _qty = 1);
                              },
                        icon: Icon(!inStock ? Icons.block_rounded : (missing ? Icons.touch_app_rounded : Icons.add_shopping_cart_rounded)),
                        label: Text(
                          !canOrder
                              ? s.tr('الطلب مسكّر', 'Ordering is off')
                              : !inStock
                                  ? s.tr('خلصت الكمية', 'Sold out')
                                  : missing
                                      ? s.tr('اختار ${p.options[firstMissing].name}', 'Choose ${p.options[firstMissing].name.toLowerCase()}')
                                      : s.tr('أضف للسلة', 'Add to cart'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                stretch: true,
                expandedHeight: w.clamp(280.0, 520.0),
                backgroundColor: MkColors.surface,
                surfaceTintColor: Colors.transparent,
                foregroundColor: MkColors.ink,
                leading: Padding(
                  padding: const EdgeInsetsDirectional.only(start: 8),
                  child: Center(
                    child: IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: MkColors.ink, elevation: 2),
                      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                      onPressed: () => context.pop(),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                ),
                actions: [
                  Container(
                    margin: const EdgeInsetsDirectional.only(end: 8),
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Color(0x262C123F), blurRadius: 8)]),
                    child: const _CartButton(),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [StretchMode.zoomBackground],
                  background: ColoredBox(
                    color: const Color(0xFFF4F1F7),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (images.isEmpty)
                          const Center(child: Icon(Icons.shopping_bag_outlined, size: 72, color: MkColors.purple100))
                        else
                          PageView.builder(
                            controller: _pages,
                            itemCount: images.length,
                            onPageChanged: (i) => setState(() => _page = i),
                            itemBuilder: (context, i) => i == 0
                                ? Hero(tag: 'p-${p.id}', child: MkNetImage(url: url(images[i]), cacheWidth: 1080))
                                : MkNetImage(url: url(images[i]), cacheWidth: 1080),
                          ),
                        if (sale != null && inStock)
                          PositionedDirectional(
                            start: MkSpace.lg,
                            bottom: images.length > 1 ? 76 : 18,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: MkColors.danger, borderRadius: MkRadius.all(MkRadius.pill)),
                              child: Text(sale, style: t.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
                            ),
                          ),
                        // Thumbnails of every photo; the chosen one is outlined.
                        if (images.length > 1)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 12,
                            height: 54,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: MkSpace.lg),
                              itemCount: images.length,
                              separatorBuilder: (context, i) => const SizedBox(width: 8),
                              itemBuilder: (context, i) => GestureDetector(
                                onTap: () => _goTo(i),
                                child: AnimatedContainer(
                                  duration: MkMotion.fast,
                                  width: 54,
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: MkRadius.all(12),
                                    border: Border.all(color: i == _page ? MkColors.purple900 : Colors.white, width: 2),
                                    boxShadow: const [BoxShadow(color: Color(0x262C123F), blurRadius: 8)],
                                  ),
                                  child: MkNetImage(url: url(images[i]), radius: 9, cacheWidth: 160),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.lg, MkSpace.lg, MkSpace.xxl),
                sliver: SliverList.list(
                  children: [
                    if (store != null)
                      Row(
                        children: [
                          SizedBox(width: 22, height: 22, child: ClipOval(child: MkNetImage(url: url(store.logoUrl), fallbackName: store.shopName, cacheWidth: 66))),
                          const SizedBox(width: 6),
                          Text(store.shopName, style: t.labelLarge?.copyWith(color: MkColors.purple700, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    const SizedBox(height: 6),
                    Text(p.name, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.2)),
                    const SizedBox(height: MkSpace.xs),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          missing && p.maxPriceMinor > p.priceMinor ? _priceText(s, p) : money(price),
                          style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w900, color: MkColors.purple900),
                        ),
                        if (compareAt != null && compareAt > price) ...[
                          const SizedBox(width: 8),
                          Text(money(compareAt), style: t.titleSmall?.copyWith(color: MkColors.ink3, decoration: TextDecoration.lineThrough)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    _StockLine(inStock: inStock, stock: stock, missing: missing),
                    for (var i = 0; i < p.options.length; i++) ...[
                      const SizedBox(height: MkSpace.lg),
                      MkOptionPicker(
                        label: p.options[i].name,
                        values: p.options[i].values,
                        selected: chosen[i],
                        isAvailable: (v) => _available(p, i, v),
                        onSelect: (v) => setState(() {
                          chosen[i] = chosen[i] == v ? null : v;
                          // A choice that clashes with another clears the other one.
                          for (var k = 0; k < chosen.length; k++) {
                            if (k != i && chosen[k] != null && !_available(p, k, chosen[k]!)) chosen[k] = null;
                          }
                          _qty = 1;
                          // Show the variant's own photo when it has one.
                          final img = p.variantFor(chosen)?.imageUrl;
                          if (img != null) {
                            final all = [...p.imageUrls, if (!p.imageUrls.contains(img)) img];
                            final idx = all.indexOf(img);
                            if (idx >= 0) WidgetsBinding.instance.addPostFrameCallback((_) => _goTo(idx));
                          }
                        }),
                      ),
                    ],
                    const SizedBox(height: MkSpace.lg),
                    Row(
                      children: [
                        Text(s.tr('الكمية', 'Quantity'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                        const Spacer(),
                        MkQtyStepper(value: _qty, max: stock, onChanged: (v) => setState(() => _qty = v)),
                      ],
                    ),
                    if ((p.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: MkSpace.lg),
                      const Divider(height: 1),
                      const SizedBox(height: MkSpace.md),
                      Text(s.tr('التفاصيل', 'Details'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: MkSpace.xs),
                      AnimatedSize(
                        duration: MkMotion.base,
                        alignment: Alignment.topCenter,
                        child: Text(
                          p.description!,
                          maxLines: _more ? null : 4,
                          overflow: _more ? null : TextOverflow.fade,
                          style: t.bodyMedium?.copyWith(color: MkColors.ink2, height: 1.55),
                        ),
                      ),
                      if (p.description!.length > 180)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                            onPressed: () => setState(() => _more = !_more),
                            child: Text(_more ? s.tr('أقل', 'Show less') : s.tr('اقرأ أكتر', 'Read more')),
                          ),
                        ),
                    ],
                    const SizedBox(height: MkSpace.lg),
                    _ServiceCard(ful: ful),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Delivery, pickup and payment, as the shop set them up.
class _ServiceCard extends ConsumerWidget {
  const _ServiceCard({required this.ful});
  final StoreFulfilment ful;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final rows = <(IconData, String, String)>[
      if (ful.delivery)
        (
          Icons.delivery_dining_rounded,
          ful.deliveryFeeMinor == 0 ? s.tr('توصيل مجاني', 'Free delivery') : s.tr('توصيل ${money(ful.deliveryFeeMinor)}', 'Delivery ${money(ful.deliveryFeeMinor)}'),
          [
            if (ful.freeDeliveryOverMinor != null && ful.deliveryFeeMinor > 0) s.tr('مجاني فوق ${money(ful.freeDeliveryOverMinor!)}', 'Free over ${money(ful.freeDeliveryOverMinor!)}'),
            if (ful.note != null) ful.note!,
          ].join(' · '),
        ),
      if (ful.pickup) (Icons.storefront_rounded, s.tr('استلام من المحل', 'Pickup from the shop'), s.tr('بلا رسوم', 'No fee')),
      (Icons.payments_outlined, s.tr('الدفع عند الاستلام', 'Pay on delivery or pickup'), s.tr('الطلب بيروح للمحل عالواتساب', 'Your order goes to the shop on WhatsApp')),
    ];
    return Container(
      decoration: BoxDecoration(color: MkColors.purple50, borderRadius: MkRadius.all(MkRadius.lg)),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Row(
                children: [
                  Icon(r.$1, color: MkColors.purple700, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.$2, style: t.labelLarge?.copyWith(fontWeight: FontWeight.w800)),
                        if (r.$3.isNotEmpty) Text(r.$3, style: t.labelSmall?.copyWith(color: MkColors.ink3)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _StockLine extends ConsumerWidget {
  const _StockLine({required this.inStock, required this.stock, required this.missing});
  final bool inStock;
  final int? stock;
  final bool missing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final (icon, color, text) = !inStock
        ? (Icons.block_rounded, MkColors.danger, s.tr('خلصت الكمية', 'Sold out'))
        : missing
            ? (Icons.touch_app_rounded, MkColors.ink3, s.tr('اختار الخيارات لتشوف التوفر', 'Choose options to see availability'))
            : stock != null && stock! <= 5
                ? (Icons.local_fire_department_rounded, MkColors.warning, s.tr('باقي $stock بس', 'Only $stock left'))
                : (Icons.check_circle_rounded, MkColors.success, s.tr('متوفر', 'In stock'));
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(text, style: t.labelMedium?.copyWith(color: color)),
      ],
    );
  }
}

// =====================================================================
// Cart and WhatsApp checkout
// =====================================================================
class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  late final _name = TextEditingController(text: ref.read(authProvider).user?.name ?? '');
  final _phone = TextEditingController();
  final _area = TextEditingController();
  final _street = TextEditingController();
  final _building = TextEditingController();
  final _landmark = TextEditingController();
  final _note = TextEditingController();
  bool _delivery = true;
  bool _busy = false;
  bool _locating = false;
  ({double lat, double lng})? _pin;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _phone, _area, _street]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _area, _street, _building, _landmark, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _contactOk => _name.text.trim().length >= 2 && RegExp(r'^\+?[0-9 ]{7,20}$').hasMatch(_phone.text.trim());
  bool get _placeOk => !_delivery || (_area.text.trim().length >= 2 && _street.text.trim().length >= 2);
  bool get _ready => _contactOk && _placeOk;

  Future<void> _locate() async {
    final s = ref.read(stringsProvider);
    setState(() => _locating = true);
    try {
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      if (p != LocationPermission.whileInUse && p != LocationPermission.always) {
        if (mounted) MkToast.show(context, s.tr('ما في إذن للموقع', 'Location not allowed'), kind: MkToastKind.error);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      if (mounted) setState(() => _pin = (lat: pos.latitude, lng: pos.longitude));
    } on Object {
      if (mounted) MkToast.show(context, s.tr('ما قدرنا نلاقي موقعك', "Couldn't find your location"), kind: MkToastKind.error);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _send() async {
    final s = ref.read(stringsProvider);
    final cart = ref.read(cartProvider);
    if (cart.shopId == null || cart.lines.isEmpty || !_ready) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(apiProvider).order(
            cart.shopId!,
            [for (final l in cart.lines) (productId: l.productId, variantId: l.variantId, qty: l.qty)],
            delivery: _delivery,
            note: _note.text,
            contact: (name: _name.text, phone: _phone.text),
            place: _delivery
                ? (area: _area.text, street: _street.text, building: _building.text, landmark: _landmark.text, lat: _pin?.lat, lng: _pin?.lng)
                : null,
          );
      final opened = await launchUrl(Uri.parse(r.url), mode: LaunchMode.externalApplication);
      if (!mounted) return;
      ref.read(cartProvider.notifier).clear();
      await showMkSheet<void>(
        context,
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MkSuccessMark(size: 84),
            const SizedBox(height: MkSpace.md),
            Text(s.tr('طلبك #${r.code} جاهز', 'Order #${r.code} is ready to send'), style: Theme.of(ctx).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: MkSpace.xs),
            Text(
              opened
                  ? s.tr('اضغط إرسال بالواتساب. المحل بيأكد الطلب #${r.code} وبتوصلك إشعار.', 'Tap Send in WhatsApp. The shop confirms order #${r.code} and you get a notification.')
                  : s.tr('ما قدرنا نفتح الواتساب. جرّب مرة تانية.', "We couldn't open WhatsApp. Please try again."),
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: MkColors.ink2),
            ),
            const SizedBox(height: MkSpace.lg),
            MkButton(label: s.tr('تمام', 'Done'), onPressed: () => Navigator.of(ctx).pop()),
          ],
        ),
      );
      if (mounted) context.pop();
    } on ApiException catch (e) {
      if (mounted) MkToast.show(context, s.errorV2(e.code), kind: MkToastKind.error);
    } on Object catch (e) {
      if (mounted) MkToast.show(context, errorText(s, e), kind: MkToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final cart = ref.watch(cartProvider);
    final store = cart.shopId == null ? null : ref.watch(shopStoreProvider(cart.shopId!)).value;
    final ful = store?.fulfilment ?? const StoreFulfilment();
    // Only what the shop offers: delivery, pickup or both.
    final canDeliver = ful.delivery || !ful.pickup;
    if (_delivery && !canDeliver) _delivery = false;
    if (!_delivery && !ful.pickup) _delivery = true;
    final subtotal = cart.totalMinor;
    final fee = _delivery ? ful.feeFor(subtotal) : 0;
    final total = subtotal + fee;
    final belowMin = ful.minOrderMinor > 0 && subtotal < ful.minOrderMinor;

    Widget field(TextEditingController c, String label, IconData icon, {TextInputType? type, int max = 120, String? hint}) => Padding(
          padding: const EdgeInsets.only(bottom: MkSpace.sm),
          child: TextField(
            controller: c,
            keyboardType: type,
            maxLength: max,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: Icon(icon), counterText: ''),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(s.tr('إتمام الطلب', 'Checkout')), centerTitle: true),
      bottomNavigationBar: cart.lines.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.xs, MkSpace.lg, MkSpace.sm),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (belowMin)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          s.tr('أقل طلب ${money(ful.minOrderMinor)}. زيد ${money(ful.minOrderMinor - subtotal)}.', 'Minimum order is ${money(ful.minOrderMinor)}. Add ${money(ful.minOrderMinor - subtotal)} more.'),
                          style: t.labelSmall?.copyWith(color: MkColors.danger, fontWeight: FontWeight.w700),
                        ),
                      )
                    else if (!_ready)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          s.tr('عبّي اسمك ورقمك${_delivery ? ' والعنوان' : ''} لتبعت الطلب', 'Add your name, phone${_delivery ? ' and address' : ''} to send the order'),
                          style: t.labelSmall?.copyWith(color: MkColors.ink3),
                        ),
                      ),
                    _WhatsAppButton(
                      label: s.tr('ابعت على واتساب · ${money(total)}', 'Send to WhatsApp · ${money(total)}'),
                      busy: _busy,
                      onTap: _ready && !belowMin ? _send : null,
                    ),
                  ],
                ),
              ),
            ),
      body: cart.lines.isEmpty
          ? MkEmptyState(
              icon: Icons.shopping_bag_outlined,
              title: s.tr('سلتك فاضية', 'Your cart is empty'),
              message: s.tr('افتح متجر أي محل وزيد منتجات.', "Open any shop's store and add products."),
            )
          : ListView(
              padding: const EdgeInsets.all(MkSpace.lg),
              children: [
                Row(
                  children: [
                    const Icon(Icons.storefront_rounded, color: MkColors.purple700),
                    const SizedBox(width: MkSpace.xs),
                    Expanded(child: Text(cart.shopName ?? '', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                    TextButton(onPressed: () => ref.read(cartProvider.notifier).clear(), child: Text(s.tr('فرّغ', 'Clear'))),
                  ],
                ),
                const SizedBox(height: MkSpace.xs),
                for (final l in cart.lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: MkSpace.sm),
                    child: MkCard(
                      child: Row(
                        children: [
                          SizedBox(width: 64, height: 64, child: MkNetImage(url: url(l.imageUrl), radius: MkRadius.md, fallbackIcon: Icons.shopping_bag_rounded)),
                          const SizedBox(width: MkSpace.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                                if (l.variantLabel != null) Text(l.variantLabel!, style: t.labelMedium?.copyWith(color: MkColors.ink3)),
                                const SizedBox(height: 4),
                                Text(money(l.priceMinor * l.qty), style: t.titleSmall?.copyWith(color: MkColors.purple900, fontWeight: FontWeight.w800)),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              IconButton(
                                tooltip: s.tr('شيل', 'Remove'),
                                visualDensity: VisualDensity.compact,
                                onPressed: () => ref.read(cartProvider.notifier).setQty(l.key, 0),
                                icon: const Icon(Icons.delete_outline_rounded, color: MkColors.ink3),
                              ),
                              MkQtyStepper(compact: true, value: l.qty, max: l.maxQty, onChanged: (v) => ref.read(cartProvider.notifier).setQty(l.key, v)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: MkSpace.sm),
                _Step(n: 1, title: s.tr('كيف بدك تستلم؟', 'How do you want it?')),
                Row(
                  children: [
                    if (canDeliver)
                      Expanded(
                        child: _Choice(
                          on: _delivery,
                          icon: Icons.delivery_dining_rounded,
                          title: s.tr('توصيل', 'Delivery'),
                          sub: ful.feeFor(subtotal) == 0 ? s.tr('مجاني', 'Free') : money(ful.feeFor(subtotal)),
                          onTap: () => setState(() => _delivery = true),
                        ),
                      ),
                    if (canDeliver && ful.pickup) const SizedBox(width: MkSpace.sm),
                    if (ful.pickup)
                      Expanded(
                        child: _Choice(
                          on: !_delivery,
                          icon: Icons.storefront_rounded,
                          title: s.tr('استلام', 'Pickup'),
                          sub: s.tr('من المحل، بلا رسوم', 'From the shop, no fee'),
                          onTap: () => setState(() => _delivery = false),
                        ),
                      ),
                  ],
                ),
                if (_delivery && (ful.note != null || (ful.freeDeliveryOverMinor != null && fee > 0)))
                  Padding(
                    padding: const EdgeInsets.only(top: MkSpace.xs),
                    child: Text(
                      [
                        if (ful.freeDeliveryOverMinor != null && fee > 0)
                          s.tr('التوصيل مجاني فوق ${money(ful.freeDeliveryOverMinor!)}', 'Free delivery over ${money(ful.freeDeliveryOverMinor!)}'),
                        if (ful.note != null) ful.note!,
                      ].join(' · '),
                      style: t.labelMedium?.copyWith(color: MkColors.purple700, fontWeight: FontWeight.w700),
                    ),
                  ),
                const SizedBox(height: MkSpace.lg),
                _Step(n: 2, title: s.tr('معلوماتك', 'Your details')),
                field(_name, s.tr('الاسم الكامل', 'Full name'), Icons.person_outline_rounded, max: 60),
                field(_phone, s.tr('رقم التلفون للتواصل', 'Phone to reach you'), Icons.call_outlined, type: TextInputType.phone, max: 20, hint: '+961 70 123 456'),
                AnimatedSize(
                  duration: MkMotion.base,
                  curve: MkMotion.standard,
                  child: !_delivery
                      ? const SizedBox(width: double.infinity)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: MkSpace.sm),
                            _Step(n: 3, title: s.tr('وين نوصّل؟', 'Where should it go?')),
                            field(_area, s.tr('المنطقة', 'Area / city'), Icons.location_city_rounded, max: 80, hint: s.tr('الحمرا، بيروت', 'Hamra, Beirut')),
                            field(_street, s.tr('الشارع', 'Street'), Icons.signpost_outlined),
                            field(_building, s.tr('البناية والطابق', 'Building and floor'), Icons.apartment_rounded, max: 80),
                            field(_landmark, s.tr('علامة قريبة (اختياري)', 'Nearby landmark (optional)'), Icons.flag_outlined),
                            AnimatedSwitcher(
                              duration: MkMotion.base,
                              child: _pin == null
                                  ? OutlinedButton.icon(
                                      key: const ValueKey('add'),
                                      onPressed: _locating ? null : _locate,
                                      icon: _locating
                                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                          : const Icon(Icons.my_location_rounded),
                                      label: Text(s.tr('زيد موقعي الحالي', 'Add my current location')),
                                    )
                                  : Container(
                                      key: const ValueKey('pin'),
                                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                                      decoration: BoxDecoration(color: MkColors.successBg, borderRadius: MkRadius.all(MkRadius.md)),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.check_circle_rounded, color: MkColors.success),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              s.tr('انضاف موقعك. المحل بيشوفه على الخريطة.', 'Location added. The shop sees it on the map.'),
                                              style: t.bodySmall?.copyWith(color: MkColors.success, fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: s.tr('شيل', 'Remove'),
                                            onPressed: () => setState(() => _pin = null),
                                            icon: const Icon(Icons.close_rounded, color: MkColors.success),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: MkSpace.md),
                TextField(
                  controller: _note,
                  maxLength: 300,
                  decoration: InputDecoration(labelText: s.tr('ملاحظة للمحل (اختياري)', 'Note for the shop (optional)'), prefixIcon: const Icon(Icons.edit_note_rounded)),
                ),
                const SizedBox(height: MkSpace.sm),
                MkCard(
                  child: Column(
                    children: [
                      _row(t, s.tr('المنتجات (${cart.count})', 'Items (${cart.count})'), money(subtotal)),
                      const SizedBox(height: 6),
                      _row(t, _delivery ? s.tr('التوصيل', 'Delivery') : s.tr('الاستلام', 'Pickup'), fee == 0 ? s.tr('مجاني', 'Free') : money(fee)),
                      const Divider(height: MkSpace.lg),
                      _row(t, s.tr('المجموع', 'Total'), money(total), bold: true),
                      const SizedBox(height: 2),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(s.tr('الدفع عند الاستلام', 'Pay on delivery or pickup'), style: t.labelSmall?.copyWith(color: MkColors.ink3)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: MkSpace.sm),
                const _SafeOrderNote(),
              ],
            ),
    );
  }

  Widget _row(TextTheme t, String a, String b, {bool bold = false}) => Row(
        children: [
          Expanded(child: Text(a, style: (bold ? t.titleMedium : t.bodyMedium)?.copyWith(fontWeight: bold ? FontWeight.w800 : null))),
          Text(b, style: (bold ? t.titleMedium : t.bodyMedium)?.copyWith(fontWeight: bold ? FontWeight.w800 : null, color: bold ? MkColors.purple900 : MkColors.ink2)),
        ],
      );
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.title});
  final int n;
  final String title;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: MkSpace.sm),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: MkColors.purple900, shape: BoxShape.circle),
            child: Text('$n', style: t.labelMedium?.copyWith(color: MkColors.yellow500, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 8),
          Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Big pickup / delivery choice card.
class _Choice extends StatelessWidget {
  const _Choice({required this.on, required this.icon, required this.title, required this.sub, required this.onTap});
  final bool on;
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      selected: on,
      button: true,
      child: MkPressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: MkMotion.base,
          padding: const EdgeInsets.all(MkSpace.sm),
          decoration: BoxDecoration(
            gradient: on ? const LinearGradient(colors: [MkColors.purple700, MkColors.purple900]) : null,
            color: on ? null : Colors.white,
            borderRadius: MkRadius.all(MkRadius.lg),
            border: Border.all(color: on ? MkColors.purple900 : MkColors.line, width: 1.5),
            boxShadow: on ? const [BoxShadow(color: Color(0x442C123F), blurRadius: 16, offset: Offset(0, 8))] : null,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: on ? MkColors.yellow500 : MkColors.purple50, shape: BoxShape.circle),
                child: Icon(icon, color: MkColors.purple900, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: on ? Colors.white : MkColors.ink)),
                    Text(sub, style: t.labelSmall?.copyWith(color: on ? Colors.white70 : MkColors.ink3)),
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

/// Why ordering is safe, for the member and the shop.
class _SafeOrderNote extends ConsumerWidget {
  const _SafeOrderNote();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    Widget line(String text) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(padding: EdgeInsets.only(top: 3), child: Icon(Icons.check_rounded, size: 15, color: MkColors.success)),
              const SizedBox(width: 6),
              Expanded(child: Text(text, style: t.bodySmall?.copyWith(color: MkColors.ink2))),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(MkSpace.sm),
      decoration: BoxDecoration(color: MkColors.purple50, borderRadius: MkRadius.all(MkRadius.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_rounded, color: MkColors.purple700, size: 20),
              const SizedBox(width: 6),
              Text(s.tr('طلب آمن', 'Safe ordering'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          line(s.tr('الأسعار من المحل نفسه، ما حدا فيه يغيّرها بالرسالة.', 'Prices come from the shop. Nobody can change them in the message.')),
          line(s.tr('طلبك إلو رمز، والمحل بيتأكد منه بتطبيق مكافأة.', 'Your order gets a code the shop checks in Mukafaah.')),
          line(s.tr('بتدفع بس لما تستلم. ما تبعت مصاري سلف لحدا.', 'Pay only when you receive it. Never send money in advance.')),
        ],
      ),
    );
  }
}

/// Green WhatsApp send button.
class _WhatsAppButton extends StatelessWidget {
  const _WhatsAppButton({required this.label, required this.busy, required this.onTap});
  final String label;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final on = onTap != null && !busy;
    return Semantics(
      button: true,
      enabled: on,
      label: label,
      child: MkPressable(
        onTap: on ? onTap : null,
        child: AnimatedOpacity(
          duration: MkMotion.fast,
          opacity: onTap == null ? 0.45 : 1,
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF25D366), Color(0xFF128C7E)]),
              borderRadius: MkRadius.all(MkRadius.lg),
              boxShadow: const [BoxShadow(color: Color(0x5525D366), blurRadius: 18, offset: Offset(0, 8))],
            ),
            alignment: Alignment.center,
            child: busy
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.chat_rounded, color: Colors.white),
                      const SizedBox(width: 10),
                      Text(label, style: t.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
