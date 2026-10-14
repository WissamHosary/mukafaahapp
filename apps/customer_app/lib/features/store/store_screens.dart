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
      loading: () => const SliverToBoxAdapter(
        child: Padding(padding: EdgeInsets.all(MkSpace.xxl), child: Center(child: CircularProgressIndicator())),
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
        return SliverMainAxisGroup(
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
        );
      },
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
                    if (!_ready)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          s.tr('عبّي اسمك ورقمك${_delivery ? ' والعنوان' : ''} لتبعت الطلب', 'Add your name, phone${_delivery ? ' and address' : ''} to send the order'),
                          style: t.labelSmall?.copyWith(color: MkColors.ink3),
                        ),
                      ),
                    _WhatsAppButton(
                      label: s.tr('ابعت على واتساب · ${money(cart.totalMinor)}', 'Send to WhatsApp · ${money(cart.totalMinor)}'),
                      busy: _busy,
                      onTap: _ready ? _send : null,
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
                    Expanded(
                      child: _Choice(
                        on: _delivery,
                        icon: Icons.delivery_dining_rounded,
                        title: s.tr('توصيل', 'Delivery'),
                        sub: s.tr('لعندك', 'To your door'),
                        onTap: () => setState(() => _delivery = true),
                      ),
                    ),
                    const SizedBox(width: MkSpace.sm),
                    Expanded(
                      child: _Choice(
                        on: !_delivery,
                        icon: Icons.storefront_rounded,
                        title: s.tr('استلام', 'Pickup'),
                        sub: s.tr('من المحل', 'From the shop'),
                        onTap: () => setState(() => _delivery = false),
                      ),
                    ),
                  ],
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
                      _row(t, s.tr('المنتجات (${cart.count})', 'Items (${cart.count})'), money(cart.totalMinor)),
                      const SizedBox(height: 6),
                      _row(t, _delivery ? s.tr('التوصيل', 'Delivery') : s.tr('الاستلام', 'Pickup'), s.tr('بيأكده المحل', 'Confirmed by the shop')),
                      const Divider(height: MkSpace.lg),
                      _row(t, s.tr('المجموع', 'Total'), money(cart.totalMinor), bold: true),
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
