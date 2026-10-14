import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../../data/api.dart';
import 'owner_widgets.dart';

String _usd(int minor) => formatMinor(minor, 'USD');

/// The shop's online store, shown in the Products tab: on/off switch,
/// categories and the product list. Turning it off hides the store from customers.
class StoreManager extends ConsumerWidget {
  const StoreManager({super.key});

  Future<void> _toggle(BuildContext context, WidgetRef ref, bool on) async {
    final s = ref.read(stringsProvider);
    try {
      await ref.read(apiProvider).setStoreEnabled(on);
      ref.invalidate(storeInfoProvider);
      if (context.mounted) {
        MkToast.show(
          context,
          on ? s.tr('متجرك صار ظاهر للزباين', 'Your store is now open to customers') : s.tr('متجرك مخفي', 'Your store is hidden'),
          kind: MkToastKind.success,
        );
      }
    } on Object catch (e) {
      if (context.mounted) showApiError(context, s, e);
    }
  }

  Future<void> _category(BuildContext context, WidgetRef ref, {Json? cat}) async {
    final s = ref.read(stringsProvider);
    final ctl = TextEditingController(text: cat?['name'] as String? ?? '');
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(cat == null ? s.tr('فئة جديدة', 'New category') : s.tr('تعديل الفئة', 'Edit category')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLength: 40,
          decoration: InputDecoration(hintText: s.tr('مثلاً: قمصان', 'e.g. T-shirts')),
        ),
        actions: [
          if (cat != null) TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: Text(s.tr('حذف', 'Delete'), style: const TextStyle(color: MkColors.danger))),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(s.save)),
        ],
      ),
    );
    final name = ctl.text.trim();
    ctl.dispose();
    if (action == null) return;
    try {
      final api = ref.read(apiProvider);
      if (action == 'delete') {
        await api.patchStoreCategory(cat!['id'] as String, {'active': false});
      } else if (name.isNotEmpty) {
        if (cat == null) {
          await api.createStoreCategory(name);
        } else {
          await api.patchStoreCategory(cat['id'] as String, {'name': name});
        }
      }
      ref.invalidate(storeInfoProvider);
    } on Object catch (e) {
      if (context.mounted) showApiError(context, s, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    return ref.watch(storeInfoProvider).when(
          loading: () => const Padding(padding: EdgeInsets.all(MkSpace.xl), child: Center(child: CircularProgressIndicator())),
          error: (e, _) => MkErrorState(title: s.noConnection, retryLabel: s.retry, onRetry: () => ref.invalidate(storeInfoProvider)),
          data: (st) {
            final enabled = st['enabled'] == true;
            final cats = ((st['categories'] as List?) ?? const []).cast<Json>();
            final products = ((st['products'] as List?) ?? const []).cast<Json>();
            final newOrders = (st['newOrders'] as num?)?.toInt() ?? 0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                MkCard(
                  color: enabled ? MkColors.successBg : MkColors.surface,
                  child: Row(
                    children: [
                      MkIconTile(icon: Icons.storefront_rounded, bg: enabled ? MkColors.success : MkColors.purple100, color: enabled ? Colors.white : MkColors.purple900),
                      const SizedBox(width: MkSpace.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.tr('متجر أونلاين', 'Online store'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            Text(
                              enabled
                                  ? s.tr('الزباين بيشوفوا منتجاتك وبيطلبوا عالواتساب.', 'Customers see your products and order on WhatsApp.')
                                  : s.tr('اختياري. شغّله إذا بدك تبيع منتجات بالتطبيق.', 'Optional. Turn it on to sell products in the app.'),
                              style: t.bodySmall?.copyWith(color: MkColors.ink2),
                            ),
                          ],
                        ),
                      ),
                      Switch(value: enabled, onChanged: (v) => _toggle(context, ref, v)),
                    ],
                  ),
                ),
                if (enabled && st['hasWhatsapp'] != true)
                  Padding(
                    padding: const EdgeInsets.only(top: MkSpace.sm),
                    child: MkCard(
                      color: MkColors.warningBg,
                      onTap: () => context.go('/owner/profile'),
                      child: Text(
                        s.tr('زيد رقم واتساب بملف المحل لتوصلك الطلبات.', 'Add a WhatsApp number in Shop profile to receive orders.'),
                        style: t.bodyMedium?.copyWith(color: MkColors.warning),
                      ),
                    ),
                  ),
                if (newOrders > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: MkSpace.sm),
                    child: MkCard(
                      color: MkColors.yellow50,
                      onTap: () => context.go('/owner/orders'),
                      child: Row(
                        children: [
                          const Icon(Icons.receipt_long_rounded, color: MkColors.purple900),
                          const SizedBox(width: MkSpace.sm),
                          Expanded(child: Text(s.tr('$newOrders طلب جديد بانتظار التأكيد', '$newOrders new orders to confirm'), style: t.titleSmall)),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                  ),
                MkSectionHeader(title: s.tr('فئات المتجر', 'Store categories')),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in cats)
                      ActionChip(
                        label: Text('${c['name']} · ${c['products']}'),
                        onPressed: () => _category(context, ref, cat: c),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add_rounded, size: 18),
                      label: Text(s.tr('فئة', 'Category')),
                      onPressed: () => _category(context, ref),
                    ),
                  ],
                ),
                MkSectionHeader(title: s.tr('المنتجات (${products.length})', 'Products (${products.length})')),
                if (products.isEmpty)
                  MkEmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: s.tr('ما في منتجات بعد', 'No products yet'),
                    message: s.tr('زيد منتج بصور وأسعار، وإذا بدك قياسات أو ألوان.', 'Add a product with photos and a price, plus sizes or colours if you need them.'),
                  )
                else
                  MkCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final p in products)
                          ListTile(
                            onTap: () => context.push('/owner/store/product', extra: p['id'] as String),
                            leading: SizedBox(
                              width: 52,
                              height: 52,
                              child: MkNetImage(url: url(p['imageUrl'] as String?), radius: MkRadius.sm, fallbackIcon: Icons.shopping_bag_rounded),
                            ),
                            title: Text(p['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              [
                                if ((p['maxPriceMinor'] as num) > (p['priceMinor'] as num))
                                  '${_usd((p['priceMinor'] as num).toInt())} – ${_usd((p['maxPriceMinor'] as num).toInt())}'
                                else
                                  _usd((p['priceMinor'] as num).toInt()),
                                if (p['hasVariants'] == true) s.tr('${(p['options'] as List).length} خيارات', '${(p['options'] as List).length} options'),
                                if (p['inStock'] != true) s.tr('خلصت', 'Sold out'),
                                if (p['available'] != true) s.tr('مخفي', 'Hidden'),
                              ].join(' · '),
                            ),
                            trailing: const Icon(Icons.chevron_right_rounded),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        );
  }
}

// =====================================================================
// Product editor (full screen): photos, details, options and variants
// =====================================================================

/// One editable variant row.
class _VariantRow {
  _VariantRow({required this.values, this.id, int? priceMinor, int? stock, this.active = true})
      : price = TextEditingController(text: minorToText(priceMinor)),
        stock = TextEditingController(text: stock?.toString() ?? '');
  final String? id;
  final List<String> values;
  final TextEditingController price;
  final TextEditingController stock;
  bool active;

  String get key => values.join('\u0000').toLowerCase();
  void dispose() {
    price.dispose();
    stock.dispose();
  }
}

class _OptionDraft {
  _OptionDraft(this.name, this.values);
  final TextEditingController name;
  final List<String> values;
  final TextEditingController add = TextEditingController();
  void dispose() {
    name.dispose();
    add.dispose();
  }
}

class StoreProductEditor extends ConsumerStatefulWidget {
  const StoreProductEditor({this.productId, super.key});
  final String? productId;

  @override
  ConsumerState<StoreProductEditor> createState() => _StoreProductEditorState();
}

class _StoreProductEditorState extends ConsumerState<StoreProductEditor> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  final _compare = TextEditingController();
  final _stock = TextEditingController();
  final List<({String id, String? url, Uint8List? bytes})> _images = [];
  final List<_OptionDraft> _options = [];
  List<_VariantRow> _variants = [];
  String? _categoryId;
  bool _available = true;
  bool _featured = false;
  bool _trackStock = false;
  bool _loading = true;
  bool _busy = false;
  int _uploading = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.productId;
    if (id == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final p = await ref.read(apiProvider).storeProduct(id);
      _name.text = p['name'] as String? ?? '';
      _desc.text = p['description'] as String? ?? '';
      _price.text = minorToText((p['priceMinor'] as num?)?.toInt());
      _compare.text = minorToText((p['compareAtMinor'] as num?)?.toInt());
      _categoryId = p['categoryId'] as String?;
      _available = p['available'] != false;
      _featured = p['featured'] == true;
      _trackStock = p['trackStock'] == true;
      _stock.text = (p['stock'] as num?)?.toString() ?? '';
      final ids = ((p['imageIds'] as List?) ?? const []).cast<String>();
      final urls = ((p['imageUrls'] as List?) ?? const []).cast<String?>();
      for (var i = 0; i < ids.length; i++) {
        _images.add((id: ids[i], url: i < urls.length ? urls[i] : null, bytes: null));
      }
      for (final o in ((p['options'] as List?) ?? const []).cast<Json>()) {
        _options.add(_OptionDraft(TextEditingController(text: o['name'] as String), ((o['values'] as List?) ?? const []).cast<String>().toList()));
      }
      _variants = [
        for (final v in ((p['variants'] as List?) ?? const []).cast<Json>())
          _VariantRow(
            id: v['id'] as String,
            values: ((v['optionValues'] as List?) ?? const []).cast<String>().toList(),
            priceMinor: (v['priceMinor'] as num?)?.toInt(),
            stock: (v['stock'] as num?)?.toInt(),
            active: v['active'] != false,
          ),
      ];
    } on Object catch (e) {
      if (mounted) showApiError(context, ref.read(stringsProvider), e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _desc, _price, _compare, _stock]) {
      c.dispose();
    }
    for (final o in _options) {
      o.dispose();
    }
    for (final v in _variants) {
      v.dispose();
    }
    super.dispose();
  }

  Future<void> _addPhoto() async {
    final s = ref.read(stringsProvider);
    if (_images.length >= 8) return;
    final bytes = await pickImageBytes(maxWidth: 1400);
    if (bytes == null) return;
    setState(() => _uploading++);
    try {
      final r = await ref.read(apiProvider).uploadImage('item', bytes);
      setState(() => _images.add((id: r.id, url: r.url, bytes: bytes)));
    } on Object catch (e) {
      if (mounted) showApiError(context, s, e);
    } finally {
      if (mounted) setState(() => _uploading--);
    }
  }

  /// Rebuilds the variant list as every combination of option values,
  /// keeping prices and stock of combinations that already existed.
  void _rebuildVariants() {
    final opts = _options.where((o) => o.values.isNotEmpty).toList();
    final old = {for (final v in _variants) v.key: v};
    var combos = <List<String>>[<String>[]];
    for (final o in opts) {
      combos = [
        for (final c in combos)
          for (final v in o.values) [...c, v],
      ];
    }
    if (opts.isEmpty) combos = [];
    final basePrice = parseToMinor(_price.text);
    final next = <_VariantRow>[];
    for (final c in combos.take(100)) {
      final key = c.join('\u0000').toLowerCase();
      final prev = old.remove(key);
      next.add(prev ?? _VariantRow(values: c, priceMinor: basePrice, stock: _trackStock ? 0 : null));
    }
    for (final v in old.values) {
      v.dispose();
    }
    _variants = next;
  }

  void _addOption() {
    if (_options.length >= 3) return;
    final s = ref.read(stringsProvider);
    final defaults = [s.tr('القياس', 'Size'), s.tr('اللون', 'Colour'), s.tr('النوع', 'Style')];
    setState(() => _options.add(_OptionDraft(TextEditingController(text: defaults[_options.length]), [])));
  }

  void _addValue(_OptionDraft o) {
    final v = o.add.text.trim();
    if (v.isEmpty || v.length > 30 || o.values.length >= 20) return;
    if (o.values.any((x) => x.toLowerCase() == v.toLowerCase())) return;
    setState(() {
      o.values.add(v);
      o.add.clear();
      _rebuildVariants();
    });
  }

  Future<void> _save({bool archive = false}) async {
    final s = ref.read(stringsProvider);
    final price = parseToMinor(_price.text);
    if (_name.text.trim().isEmpty || price == null) {
      MkToast.show(context, s.tr('اكتب الاسم والسعر', 'Add a name and a price'), kind: MkToastKind.error);
      return;
    }
    final opts = _options.where((o) => o.values.isNotEmpty && o.name.text.trim().isNotEmpty).toList();
    final names = opts.map((o) => o.name.text.trim().toLowerCase()).toSet();
    if (names.length != opts.length) {
      MkToast.show(context, s.tr('أسماء الخيارات لازم تكون مختلفة', 'Option names must be different'), kind: MkToastKind.error);
      return;
    }
    final variants = <Json>[];
    for (final v in _variants) {
      final vp = parseToMinor(v.price.text) ?? price;
      final st = int.tryParse(v.stock.text.trim());
      variants.add({
        if (v.id != null) 'id': v.id,
        'optionValues': v.values,
        'priceMinor': vp,
        'stock': _trackStock ? (st ?? 0) : null,
        'active': v.active,
      });
    }
    final compare = parseToMinor(_compare.text);
    final data = <String, dynamic>{
      'name': _name.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'categoryId': _categoryId,
      'priceMinor': price,
      'compareAtMinor': compare != null && compare > price ? compare : null,
      'imageIds': [for (final i in _images) i.id],
      'trackStock': _trackStock,
      'stock': _trackStock && opts.isEmpty ? (int.tryParse(_stock.text.trim()) ?? 0) : null,
      'options': [
        for (final o in opts) {'name': o.name.text.trim(), 'values': o.values},
      ],
      'variants': opts.isEmpty ? <Json>[] : variants,
      'available': _available,
      'featured': _featured,
      if (archive) 'archived': true,
    };
    setState(() => _busy = true);
    try {
      final api = ref.read(apiProvider);
      if (widget.productId != null) {
        await api.patchStoreProduct(widget.productId!, data);
      } else {
        data.removeWhere((k, v) => v == null);
        await api.createStoreProduct(data);
      }
      ref.invalidate(storeInfoProvider);
      if (mounted) {
        MkToast.show(context, archive ? s.tr('انحذف المنتج', 'Product removed') : s.saved, kind: MkToastKind.success);
        context.pop();
      }
    } on Object catch (e) {
      if (mounted) showApiError(context, s, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final cats = ((ref.watch(storeInfoProvider).value?['categories'] as List?) ?? const []).cast<Json>();
    final money = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    final digits = [FilteringTextInputFormatter.digitsOnly];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.productId == null ? s.tr('منتج جديد', 'New product') : s.tr('تعديل المنتج', 'Edit product')),
        centerTitle: true,
      ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.xs, MkSpace.lg, MkSpace.sm),
                child: MkButton(
                  label: s.save,
                  icon: Icons.check_rounded,
                  kind: MkButtonKind.accent,
                  loading: _busy,
                  onPressed: _uploading > 0 ? null : _save,
                ),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.md, MkSpace.lg, MkSpace.xxl),
              children: [
                Text(s.tr('الصور (لحد 8)', 'Photos (up to 8)'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: MkSpace.xs),
                SizedBox(
                  height: 96,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < _images.length; i++)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: MkSpace.xs),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: MkRadius.all(MkRadius.md),
                                child: SizedBox(
                                  width: 96,
                                  height: 96,
                                  child: _images[i].bytes != null
                                      ? Image.memory(_images[i].bytes!, fit: BoxFit.cover)
                                      : MkNetImage(url: url(_images[i].url)),
                                ),
                              ),
                              if (i == 0)
                                PositionedDirectional(
                                  bottom: 4,
                                  start: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(color: MkColors.yellow500, borderRadius: MkRadius.all(MkRadius.pill)),
                                    child: Text(s.tr('الرئيسية', 'Cover'), style: t.labelSmall?.copyWith(color: MkColors.purple900)),
                                  ),
                                ),
                              PositionedDirectional(
                                top: 2,
                                end: 2,
                                child: MkPressable(
                                  onTap: () => setState(() => _images.removeAt(i)),
                                  child: const CircleAvatar(radius: 12, backgroundColor: Colors.white, child: Icon(Icons.close_rounded, size: 16, color: MkColors.ink)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_images.length < 8)
                        SizedBox(
                          width: 96,
                          child: ImagePickBox(aspectRatio: 1, busy: _uploading > 0, label: s.tr('أضف صورة', 'Add photo'), onTap: _addPhoto),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: MkSpace.md),
                TextField(controller: _name, maxLength: 90, decoration: InputDecoration(labelText: s.tr('اسم المنتج', 'Product name'))),
                TextField(
                  controller: _desc,
                  maxLength: 2000,
                  minLines: 2,
                  maxLines: 6,
                  decoration: InputDecoration(labelText: s.tr('الوصف', 'Description'), alignLabelWithHint: true),
                ),
                DropdownButtonFormField<String?>(
                  key: ValueKey('cat-${cats.length}'),
                  initialValue: cats.any((c) => c['id'] == _categoryId) ? _categoryId : null,
                  decoration: InputDecoration(labelText: s.tr('الفئة', 'Category')),
                  items: [
                    DropdownMenuItem<String?>(child: Text(s.tr('بدون فئة', 'No category'))),
                    for (final c in cats) DropdownMenuItem<String?>(value: c['id'] as String, child: Text(c['name'] as String)),
                  ],
                  onChanged: (v) => setState(() => _categoryId = v),
                ),
                const SizedBox(height: MkSpace.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _price,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: money,
                        decoration: InputDecoration(labelText: s.tr('السعر', 'Price'), prefixText: r'$ '),
                      ),
                    ),
                    const SizedBox(width: MkSpace.sm),
                    Expanded(
                      child: TextField(
                        controller: _compare,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: money,
                        decoration: InputDecoration(labelText: s.tr('السعر قبل الخصم', 'Was (optional)'), prefixText: r'$ '),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MkSpace.sm),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.tr('تتبّع الكمية', 'Track stock')),
                  subtitle: Text(s.tr('بتنقص لما تأكد طلب', 'Goes down when you confirm an order')),
                  value: _trackStock,
                  onChanged: (v) => setState(() => _trackStock = v),
                ),
                if (_trackStock && _options.every((o) => o.values.isEmpty))
                  TextField(
                    controller: _stock,
                    keyboardType: TextInputType.number,
                    inputFormatters: digits,
                    decoration: InputDecoration(labelText: s.tr('الكمية المتوفرة', 'In stock')),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.tr('ظاهر بالمتجر', 'Visible in store')),
                  value: _available,
                  onChanged: (v) => setState(() => _available = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.tr('منتج مميز (أول المتجر)', 'Featured (top of the store)')),
                  value: _featured,
                  onChanged: (v) => setState(() => _featured = v),
                ),
                MkSectionHeader(title: s.tr('الخيارات (قياس، لون…)', 'Options (size, colour…)')),
                for (final o in _options)
                  Padding(
                    padding: const EdgeInsets.only(bottom: MkSpace.sm),
                    child: MkCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: o.name,
                                  maxLength: 30,
                                  decoration: InputDecoration(labelText: s.tr('اسم الخيار', 'Option name'), counterText: ''),
                                ),
                              ),
                              IconButton(
                                tooltip: s.tr('شيل الخيار', 'Remove option'),
                                onPressed: () => setState(() {
                                  _options.remove(o);
                                  o.dispose();
                                  _rebuildVariants();
                                }),
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: MkSpace.xs),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final v in o.values)
                                InputChip(
                                  label: Text(v),
                                  onDeleted: () => setState(() {
                                    o.values.remove(v);
                                    _rebuildVariants();
                                  }),
                                ),
                            ],
                          ),
                          TextField(
                            controller: o.add,
                            maxLength: 30,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _addValue(o),
                            decoration: InputDecoration(
                              hintText: s.tr('زيد قيمة، مثلاً M', 'Add a value, e.g. M'),
                              counterText: '',
                              suffixIcon: IconButton(onPressed: () => _addValue(o), icon: const Icon(Icons.add_circle_rounded, color: MkColors.purple700)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_options.length < 3)
                  OutlinedButton.icon(
                    onPressed: _addOption,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(_options.isEmpty ? s.tr('هالمنتج إلو قياسات أو ألوان', 'This product has sizes or colours') : s.tr('زيد خيار تاني', 'Add another option')),
                  ),
                if (_variants.isNotEmpty) ...[
                  MkSectionHeader(title: s.tr('النسخ (${_variants.length})', 'Variants (${_variants.length})')),
                  Text(
                    s.tr('كل تركيبة إلها سعرها وكميتها. وقّف اللي مش متوفر.', 'Each combination has its own price and stock. Switch off the ones you do not sell.'),
                    style: t.bodySmall?.copyWith(color: MkColors.ink3),
                  ),
                  const SizedBox(height: MkSpace.xs),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: () => setState(() {
                        for (final v in _variants) {
                          v.price.text = _price.text;
                        }
                      }),
                      icon: const Icon(Icons.copy_all_rounded, size: 18),
                      label: Text(s.tr('نفس السعر للكل', 'Same price for all')),
                    ),
                  ),
                  for (final v in _variants)
                    Padding(
                      padding: const EdgeInsets.only(bottom: MkSpace.xs),
                      child: Opacity(
                        opacity: v.active ? 1 : 0.5,
                        child: Row(
                          children: [
                            Expanded(flex: 4, child: Text(v.values.join(' / '), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                            const SizedBox(width: 6),
                            Expanded(
                              flex: 3,
                              child: TextField(
                                controller: v.price,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: money,
                                decoration: const InputDecoration(isDense: true, prefixText: r'$ '),
                              ),
                            ),
                            if (_trackStock) ...[
                              const SizedBox(width: 6),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: v.stock,
                                  keyboardType: TextInputType.number,
                                  inputFormatters: digits,
                                  decoration: InputDecoration(isDense: true, hintText: s.tr('كمية', 'Qty')),
                                ),
                              ),
                            ],
                            Switch(value: v.active, onChanged: (x) => setState(() => v.active = x)),
                          ],
                        ),
                      ),
                    ),
                ],
                if (widget.productId != null) ...[
                  const SizedBox(height: MkSpace.xl),
                  MkButton(
                    label: s.tr('حذف المنتج', 'Delete product'),
                    kind: MkButtonKind.danger,
                    onPressed: _busy ? null : () => _save(archive: true),
                  ),
                ],
              ],
            ),
    );
  }
}
