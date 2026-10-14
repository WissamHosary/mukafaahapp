import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  String? _cat;
  String _q = '';
  String _sort = 'featured';

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final data = ref.watch(shopStoreProvider(widget.shopId));
    final cart = ref.watch(cartProvider);
    final myCart = cart.shopId == widget.shopId && cart.count > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(data.value?.shopName ?? s.tr('المتجر', 'Store')),
        centerTitle: true,
        actions: const [_CartButton(), SizedBox(width: 4)],
      ),
      bottomNavigationBar: myCart
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.xs, MkSpace.lg, MkSpace.sm),
                child: MkButton(
                  label: s.tr('السلة (${cart.count}) · ${money(cart.totalMinor)}', 'View cart (${cart.count}) · ${money(cart.totalMinor)}'),
                  icon: Icons.shopping_bag_rounded,
                  kind: MkButtonKind.accent,
                  onPressed: () => context.push('/cart'),
                ),
              ),
            )
          : null,
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => MkErrorState(
          title: errorText(s, e),
          retryLabel: s.retry,
          onRetry: () => ref.invalidate(shopStoreProvider(widget.shopId)),
        ),
        data: (d) {
          var list = d.products.where((p) => (_cat == null || p.categoryId == _cat) && (_q.isEmpty || p.name.toLowerCase().contains(_q.toLowerCase()))).toList();
          if (_sort == 'low') list.sort((a, b) => a.priceMinor.compareTo(b.priceMinor));
          if (_sort == 'high') list.sort((a, b) => b.priceMinor.compareTo(a.priceMinor));
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(shopStoreProvider(widget.shopId));
              await ref.read(shopStoreProvider(widget.shopId).future);
            },
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.xs, MkSpace.lg, 0),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(child: MkSearchField(hint: s.tr('دوّر عن منتج', 'Search products'), onChanged: (v) => setState(() => _q = v.trim()))),
                        const SizedBox(width: MkSpace.xs),
                        PopupMenuButton<String>(
                          tooltip: s.tr('ترتيب', 'Sort'),
                          icon: const Icon(Icons.tune_rounded),
                          initialValue: _sort,
                          onSelected: (v) => setState(() => _sort = v),
                          itemBuilder: (ctx) => [
                            PopupMenuItem(value: 'featured', child: Text(s.tr('المميز أولاً', 'Featured'))),
                            PopupMenuItem(value: 'low', child: Text(s.tr('السعر: من الأقل', 'Price: low to high'))),
                            PopupMenuItem(value: 'high', child: Text(s.tr('السعر: من الأعلى', 'Price: high to low'))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (d.categories.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: MkSpace.sm),
                      child: MkChoiceChips<String?>(
                        padding: const EdgeInsets.symmetric(horizontal: MkSpace.lg),
                        items: [(null, s.all), for (final c in d.categories) (c.id, c.name)],
                        selected: _cat,
                        onSelected: (v) => setState(() => _cat = v),
                      ),
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
                  padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.md, MkSpace.lg, MkSpace.xs),
                  sliver: SliverToBoxAdapter(
                    child: Text(s.tr('${list.length} منتج', '${list.length} products'), style: t.labelLarge?.copyWith(color: MkColors.ink3)),
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
                    padding: const EdgeInsets.fromLTRB(MkSpace.lg, 0, MkSpace.lg, MkSpace.xxl),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        childAspectRatio: 0.66,
                        crossAxisSpacing: MkSpace.sm,
                        mainAxisSpacing: MkSpace.sm,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        childCount: list.length,
                        (context, i) {
                          final p = list[i];
                          return MkStagger(
                            index: i % 8,
                            child: MkProductCard(
                              name: p.name,
                              imageUrl: url(p.imageUrl),
                              price: _priceText(s, p),
                              oldPrice: p.compareAtMinor != null && p.compareAtMinor! > p.priceMinor ? money(p.compareAtMinor!) : null,
                              saleLabel: _saleText(p.priceMinor, p.compareAtMinor),
                              soldOutLabel: p.inStock ? null : s.tr('خلصت الكمية', 'Sold out'),
                              subtitle: p.hasVariants ? s.tr('خيارات متعددة', 'More options') : null,
                              onTap: () => context.push('/shop/${widget.shopId}/product/${p.id}'),
                              onAdd: p.hasVariants || !d.canOrder
                                  ? null
                                  : () => _addToCart(
                                        context,
                                        ref,
                                        widget.shopId,
                                        d.shopName,
                                        CartLine(
                                          productId: p.id,
                                          name: p.name,
                                          priceMinor: p.priceMinor,
                                          qty: 1,
                                          imageUrl: p.imageUrl,
                                          maxQty: p.trackStock ? p.stock : null,
                                        ),
                                      ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
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

        return Scaffold(
          bottomNavigationBar: SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.sm, MkSpace.lg, MkSpace.sm),
              decoration: const BoxDecoration(
                color: MkColors.surface,
                boxShadow: [BoxShadow(color: Color(0x142C123F), blurRadius: 20, offset: Offset(0, -4))],
              ),
              child: Row(
                children: [
                  MkQtyStepper(value: _qty, max: stock, onChanged: (v) => setState(() => _qty = v)),
                  const SizedBox(width: MkSpace.sm),
                  Expanded(
                    child: MkButton(
                      label: !inStock
                          ? s.tr('خلصت الكمية', 'Sold out')
                          : missing
                              ? s.tr('اختار ${p.options[chosen.indexOf(null)].name}', 'Choose ${p.options[chosen.indexOf(null)].name}')
                              : s.tr('أضف · ${money(price * _qty)}', 'Add · ${money(price * _qty)}'),
                      icon: Icons.shopping_bag_rounded,
                      kind: MkButtonKind.accent,
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
                expandedHeight: MediaQuery.sizeOf(context).width.clamp(280.0, 460.0),
                backgroundColor: MkColors.surface,
                foregroundColor: MkColors.ink,
                actions: const [_CartButton(), SizedBox(width: 4)],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (images.isEmpty)
                        const MkNetImage(url: null, fallbackIcon: Icons.shopping_bag_rounded)
                      else
                        PageView.builder(
                          controller: _pages,
                          itemCount: images.length,
                          onPageChanged: (i) => setState(() => _page = i),
                          itemBuilder: (context, i) => MkNetImage(url: url(images[i]), cacheWidth: 1080),
                        ),
                      if (images.length > 1)
                        Positioned(
                          bottom: 14,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < images.length; i++)
                                AnimatedContainer(
                                  duration: MkMotion.base,
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  width: i == _page ? 20 : 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                    color: i == _page ? MkColors.purple900 : Colors.white.withValues(alpha: 0.8),
                                    borderRadius: MkRadius.all(MkRadius.pill),
                                    boxShadow: MkShadow.soft,
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.lg, MkSpace.lg, MkSpace.xxl),
                sliver: SliverList.list(
                  children: [
                    Text(p.name, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: MkSpace.xs),
                    Row(
                      children: [
                        MkPrice(
                          price: missing && p.maxPriceMinor > p.priceMinor ? _priceText(s, p) : money(price),
                          oldPrice: compareAt != null && compareAt > price ? money(compareAt) : null,
                          large: true,
                        ),
                        const SizedBox(width: MkSpace.xs),
                        if (_saleText(price, compareAt) case final sale?)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: MkColors.dangerBg, borderRadius: MkRadius.all(MkRadius.pill)),
                            child: Text(sale, style: t.labelMedium?.copyWith(color: MkColors.danger, fontWeight: FontWeight.w800)),
                          ),
                      ],
                    ),
                    const SizedBox(height: MkSpace.xs),
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
                          _qty = 1;
                          // Show the variant's own photo when it has one.
                          final nv = p.variantFor(chosen);
                          if (nv?.imageUrl != null && _pages.hasClients) {
                            final idx = images.indexOf(nv!.imageUrl!);
                            if (idx >= 0) _pages.animateToPage(idx, duration: MkMotion.slow, curve: MkMotion.standard);
                          }
                        }),
                      ),
                    ],
                    if ((p.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: MkSpace.xl),
                      Text(s.tr('الوصف', 'Description'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: MkSpace.xs),
                      Text(p.description!, style: t.bodyMedium?.copyWith(color: MkColors.ink2, height: 1.5)),
                    ],
                    const SizedBox(height: MkSpace.xl),
                    MkCard(
                      color: MkColors.purple50,
                      child: Row(
                        children: [
                          const Icon(Icons.chat_rounded, color: MkColors.purple700),
                          const SizedBox(width: MkSpace.sm),
                          Expanded(
                            child: Text(
                              s.tr(
                                'الطلب بينبعت للمحل عالواتساب. الدفع عند الاستلام أو التوصيل.',
                                'Your order goes to the shop on WhatsApp. Pay on pickup or delivery.',
                              ),
                              style: t.bodySmall?.copyWith(color: MkColors.ink2),
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
        );
      },
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
  final _address = TextEditingController();
  final _note = TextEditingController();
  bool _delivery = false;
  bool _busy = false;

  @override
  void dispose() {
    _address.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final s = ref.read(stringsProvider);
    final cart = ref.read(cartProvider);
    if (cart.shopId == null || cart.lines.isEmpty) return;
    if (_delivery && _address.text.trim().length < 5) {
      MkToast.show(context, s.tr('اكتب عنوان التوصيل.', 'Add your delivery address.'), kind: MkToastKind.error);
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await ref.read(apiProvider).order(
            cart.shopId!,
            [for (final l in cart.lines) (productId: l.productId, variantId: l.variantId, qty: l.qty)],
            delivery: _delivery,
            address: _address.text,
            note: _note.text,
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
                  ? s.tr('اضغط إرسال بالواتساب. المحل بيأكدلك الطلب وبتوصلك إشعار.', 'Tap Send in WhatsApp. The shop confirms it and you get a notification.')
                  : s.tr('ما قدرنا نفتح الواتساب. جرّب مرة تانية من السلة.', "We couldn't open WhatsApp. Please try again."),
              textAlign: TextAlign.center,
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: MkColors.ink2),
            ),
            const SizedBox(height: MkSpace.lg),
            MkButton(label: s.tr('تمام', 'Done'), onPressed: () => Navigator.of(ctx).pop()),
          ],
        ),
      );
      if (mounted) context.pop();
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

    return Scaffold(
      appBar: AppBar(title: Text(s.tr('السلة', 'Your cart')), centerTitle: true),
      bottomNavigationBar: cart.lines.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.xs, MkSpace.lg, MkSpace.sm),
                child: MkButton(
                  label: s.tr('ابعت الطلب عالواتساب · ${money(cart.totalMinor)}', 'Send order on WhatsApp · ${money(cart.totalMinor)}'),
                  icon: Icons.chat_rounded,
                  kind: MkButtonKind.accent,
                  loading: _busy,
                  onPressed: _send,
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
                    Expanded(child: Text(cart.shopName ?? '', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
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
                          SizedBox(width: 68, height: 68, child: MkNetImage(url: url(l.imageUrl), radius: MkRadius.md, fallbackIcon: Icons.shopping_bag_rounded)),
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
                Text(s.tr('كيف بدك تستلم؟', 'How do you want it?'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: MkSpace.xs),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: false, icon: const Icon(Icons.storefront_rounded), label: Text(s.tr('استلام من المحل', 'Pickup'))),
                    ButtonSegment(value: true, icon: const Icon(Icons.delivery_dining_rounded), label: Text(s.tr('توصيل', 'Delivery'))),
                  ],
                  selected: {_delivery},
                  onSelectionChanged: (v) => setState(() => _delivery = v.first),
                ),
                AnimatedSize(
                  duration: MkMotion.base,
                  child: _delivery
                      ? Padding(
                          padding: const EdgeInsets.only(top: MkSpace.sm),
                          child: TextField(
                            controller: _address,
                            maxLength: 300,
                            minLines: 2,
                            maxLines: 3,
                            decoration: InputDecoration(labelText: s.tr('عنوان التوصيل', 'Delivery address'), prefixIcon: const Icon(Icons.location_on_outlined)),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                const SizedBox(height: MkSpace.sm),
                TextField(
                  controller: _note,
                  maxLength: 300,
                  decoration: InputDecoration(labelText: s.tr('ملاحظة للمحل (اختياري)', 'Note for the shop (optional)')),
                ),
                const SizedBox(height: MkSpace.sm),
                MkCard(
                  child: Column(
                    children: [
                      _row(t, s.tr('المنتجات (${cart.count})', 'Items (${cart.count})'), money(cart.totalMinor)),
                      const SizedBox(height: 6),
                      _row(t, _delivery ? s.tr('التوصيل', 'Delivery') : s.tr('الاستلام', 'Pickup'), s.tr('بيأكده المحل', 'Confirmed by the shop')),
                      const Divider(height: MkSpace.lg),
                      _row(t, s.tr('المجموع', 'Total'), money(cart.totalMinor), bold: true),
                    ],
                  ),
                ),
                const SizedBox(height: MkSpace.sm),
                Text(
                  s.tr('ما في دفع أونلاين. بتدفع للمحل عند الاستلام أو التوصيل.', 'No online payment. You pay the shop on pickup or delivery.'),
                  style: t.bodySmall?.copyWith(color: MkColors.ink3),
                  textAlign: TextAlign.center,
                ),
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
