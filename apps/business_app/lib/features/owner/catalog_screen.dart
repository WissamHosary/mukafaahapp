import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../../data/api.dart';
import 'owner_shell.dart';
import 'owner_widgets.dart';
import 'store_screen.dart';

/// Offers, rewards and products in one place.
class CatalogScreen extends ConsumerStatefulWidget {
  const CatalogScreen({super.key});

  @override
  ConsumerState<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends ConsumerState<CatalogScreen> {
  int _tab = 0;

  void _add() {
    switch (_tab) {
      case 0:
        showMkSheet<void>(context, builder: (ctx) => const OfferEditor());
      case 1:
        showMkSheet<void>(context, builder: (ctx) => const RewardEditor());
      default:
        context.push('/owner/store/product');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final addLabel = switch (_tab) {
      0 => s.tr('عرض جديد', 'New offer'),
      1 => s.tr('مكافأة جديدة', 'New reward'),
      _ => s.tr('منتج جديد', 'New product'),
    };
    return Stack(
      children: [
        OwnerPage(
          title: s.tr('العروض والمكافآت', 'Offers & rewards'),
          onRefresh: () async {
            ref
              ..invalidate(ownerOffersProvider)
              ..invalidate(ownerRewardsProvider)
              ..invalidate(storeInfoProvider);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.md, MkSpace.lg, 120),
            children: [
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: 0, icon: const Icon(Icons.local_offer_rounded), label: Text(s.offers)),
                  ButtonSegment(value: 1, icon: const Icon(Icons.redeem_rounded), label: Text(s.rewards)),
                  ButtonSegment(value: 2, icon: const Icon(Icons.storefront_rounded), label: Text(s.tr('المتجر', 'Store'))),
                ],
                selected: {_tab},
                onSelectionChanged: (v) => setState(() => _tab = v.first),
              ),
              const SizedBox(height: MkSpace.md),
              Text(
                switch (_tab) {
                  0 => s.tr(
                      'العروض بتظهر للزباين بالتطبيق. إذا بدها حجز، بتقبل الطلب من الحجوزات والكاشير بيكمّله.',
                      'Offers show in the customer app. If booking is on, you accept requests in Bookings and the cashier completes them.',
                    ),
                  1 => s.tr(
                      'المكافآت بتنصرف بالنقاط عند الكاشير بعد ما يمسح رمز الزبون.',
                      'Rewards are paid with points at the counter after scanning the customer QR.',
                    ),
                  _ => s.tr(
                      'متجر اختياري بمنتجات وصور وقياسات وألوان. الزبون بيبعتلك الطلب عالواتساب وانت بتأكده. ما في دفع أونلاين.',
                      'An optional store with products, photos, sizes and colours. Customers send orders to your WhatsApp and you confirm them. No online payment.',
                    ),
                },
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: MkColors.ink3),
              ),
              const SizedBox(height: MkSpace.md),
              if (_tab == 0) const _OffersList() else if (_tab == 1) const _RewardsList() else const StoreManager(),
            ],
          ),
        ),
        PositionedDirectional(
          end: MkSpace.lg,
          bottom: MkSpace.lg,
          child: FloatingActionButton.extended(
            heroTag: 'catalog-add',
            backgroundColor: MkColors.yellow500,
            foregroundColor: MkColors.purple900,
            onPressed: _add,
            icon: const Icon(Icons.add_rounded),
            label: Text(addLabel),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Offers
class _OffersList extends ConsumerWidget {
  const _OffersList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    return ref.watch(ownerOffersProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => MkErrorState(title: s.noConnection, retryLabel: s.retry, onRetry: () => ref.invalidate(ownerOffersProvider)),
          data: (list) => list.isEmpty
              ? MkEmptyState(
                  icon: Icons.local_offer_rounded,
                  title: s.tr('ما عندك عروض بعد', 'No offers yet'),
                  message: s.tr('اعمل أول عرض: خصم، هدية، أو خدمة.', 'Create your first offer: a discount, a gift or a service.'),
                )
              : Column(
                  children: [
                    for (final o in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: MkSpace.sm),
                        child: MkCard(
                          onTap: () => showMkSheet<void>(context, builder: (ctx) => OfferEditor(offer: o)),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 72,
                                height: 72,
                                child: MkNetImage(url: url(o['imageUrl'] as String?), radius: MkRadius.md, fallbackIcon: Icons.local_offer_rounded),
                              ),
                              const SizedBox(width: MkSpace.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(o['title'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                                    const SizedBox(height: 2),
                                    Text(
                                      [
                                        if (o['requiresBooking'] == true) s.tr('بحجز', 'Booking') else s.tr('بالمحل', 'Walk-in'),
                                        if ((o['pointsCost'] as num) > 0) '${formatPoints(o['pointsCost'] as num)} ${s.points}',
                                        if (o['discountPercent'] != null) '-${o['discountPercent']}%',
                                      ].join(' · '),
                                      style: t.bodySmall?.copyWith(color: MkColors.ink2),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        StatusPill(status: o['hiddenByAdmin'] == true ? 'HIDDEN' : o['status'] as String),
                                        InfoChip(icon: Icons.mark_email_unread_rounded, text: '${(o['stats'] as Map)['requested']}'),
                                        InfoChip(icon: Icons.check_circle_rounded, text: '${(o['stats'] as Map)['accepted']}'),
                                        InfoChip(icon: Icons.done_all_rounded, text: '${(o['stats'] as Map)['redeemed']}'),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: o['status'] == 'ACTIVE',
                                onChanged: (v) async {
                                  try {
                                    await ref.read(apiProvider).patchOffer(o['id'] as String, {'status': v ? 'ACTIVE' : 'PAUSED'});
                                    ref.invalidate(ownerOffersProvider);
                                  } on Object catch (e) {
                                    if (context.mounted) showApiError(context, s, e);
                                  }
                                },
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

class OfferEditor extends ConsumerStatefulWidget {
  const OfferEditor({this.offer, this.initialKind, super.key});
  final Json? offer;

  /// Pre-selected type for a new offer ('DEAL', 'DISCOUNT', ...).
  final String? initialKind;

  @override
  ConsumerState<OfferEditor> createState() => _OfferEditorState();
}

class _OfferEditorState extends ConsumerState<OfferEditor> {
  late final Json o = widget.offer ?? const {};
  late final _title = TextEditingController(text: o['title'] as String? ?? '');
  late final _desc = TextEditingController(text: o['description'] as String? ?? '');
  late final _terms = TextEditingController(text: o['terms'] as String? ?? '');
  late final _points = TextEditingController(text: ((o['pointsCost'] as num?) ?? 0) == 0 ? '' : '${o['pointsCost']}');
  late final _saving = TextEditingController(text: minorToText((o['savingMinor'] as num?)?.toInt()));
  late final _discount = TextEditingController(text: o['discountPercent']?.toString() ?? '');
  late final _max = TextEditingController(text: '${o['maxPerCustomer'] ?? 1}');
  late final _limit = TextEditingController(text: o['totalLimit']?.toString() ?? '');
  late String _kind = (o['kind'] as String?) ?? widget.initialKind ?? 'DEAL';
  // A quick % discount is usually applied straight at the counter.
  late bool _booking = (o['requiresBooking'] as bool?) ?? widget.initialKind != 'DISCOUNT';
  late DateTime _from = DateTime.tryParse((o['validFrom'] as String?) ?? '') ?? DateTime.now();
  late DateTime? _to = DateTime.tryParse((o['validTo'] as String?) ?? '');
  late String? _imageId = o['imageId'] as String?;
  Uint8List? _bytes;
  bool _uploading = false;
  bool _busy = false;

  bool get _isEdit => widget.offer != null;

  @override
  void dispose() {
    for (final c in [_title, _desc, _terms, _points, _saving, _discount, _max, _limit]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final s = ref.read(stringsProvider);
    final bytes = await pickImageBytes();
    if (bytes == null) return;
    setState(() {
      _bytes = bytes;
      _uploading = true;
    });
    try {
      final r = await ref.read(apiProvider).uploadImage('item', bytes);
      setState(() => _imageId = r.id);
    } on Object catch (e) {
      if (mounted) showApiError(context, s, e);
      setState(() => _bytes = null);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickDate(bool from) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: from ? now.subtract(const Duration(days: 365)) : _from,
      lastDate: now.add(const Duration(days: 365 * 3)),
      initialDate: from ? _from : (_to ?? _from.add(const Duration(days: 30))),
    );
    if (d == null) return;
    setState(() {
      if (from) {
        _from = d;
        if (_to != null && _to!.isBefore(d)) _to = d;
      } else {
        _to = d;
      }
    });
  }

  Future<void> _save({String? status}) async {
    final s = ref.read(stringsProvider);
    if (_title.text.trim().length < 2) {
      MkToast.show(context, s.tr('اكتب عنوان العرض', 'Add a title'), kind: MkToastKind.error);
      return;
    }
    final pct = int.tryParse(_discount.text) ?? 0;
    if (_kind == 'DISCOUNT' && (pct < 1 || pct > 100)) {
      MkToast.show(context, s.tr('اكتب نسبة خصم بين ١ و١٠٠', 'Enter a discount between 1 and 100%'), kind: MkToastKind.error);
      return;
    }
    final data = <String, dynamic>{
      'title': _title.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'terms': _terms.text.trim().isEmpty ? null : _terms.text.trim(),
      'imageId': _imageId,
      'kind': _kind,
      'discountPercent': _kind == 'DISCOUNT' ? int.tryParse(_discount.text) : null,
      'pointsCost': int.tryParse(_points.text) ?? 0,
      'savingMinor': parseToMinor(_saving.text) ?? 0,
      'requiresBooking': _booking,
      'maxPerCustomer': (int.tryParse(_max.text) ?? 1).clamp(1, 100),
      'totalLimit': int.tryParse(_limit.text),
      'validFrom': isoDate(_from),
      'validTo': _to == null ? null : isoDate(_to!),
      if (status != null) 'status': status,
    };
    setState(() => _busy = true);
    try {
      final api = ref.read(apiProvider);
      if (_isEdit) {
        await api.patchOffer(o['id'] as String, data);
      } else {
        data.removeWhere((k, v) => v == null);
        await api.createOffer(data);
      }
      ref
        ..invalidate(ownerOffersProvider)
        ..invalidate(dashboardProvider);
      if (mounted) {
        Navigator.of(context).pop();
        MkToast.show(context, s.saved, kind: MkToastKind.success);
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
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_isEdit ? s.tr('تعديل العرض', 'Edit offer') : s.tr('عرض جديد', 'New offer'), style: t.titleLarge),
        const SizedBox(height: MkSpace.md),
        ImagePickBox(
          url: url(o['imageUrl'] as String?),
          bytes: _bytes,
          busy: _uploading,
          label: s.tr('صورة العرض', 'Offer photo'),
          onTap: _pickImage,
        ),
        const SizedBox(height: MkSpace.md),
        TextField(controller: _title, maxLength: 90, decoration: InputDecoration(labelText: s.tr('العنوان', 'Title'))),
        TextField(controller: _desc, maxLength: 600, maxLines: 3, minLines: 1, decoration: InputDecoration(labelText: s.tr('الوصف', 'Description'))),
        const SizedBox(height: MkSpace.xs),
        Text(s.tr('النوع', 'Type'), style: t.labelLarge?.copyWith(color: MkColors.ink2)),
        const SizedBox(height: MkSpace.xs),
        Wrap(
          spacing: MkSpace.xs,
          runSpacing: MkSpace.xs,
          children: [
            for (final (k, icon, label) in [
              ('DEAL', Icons.local_offer_rounded, s.tr('عرض', 'Deal')),
              ('DISCOUNT', Icons.percent_rounded, s.tr('خصم بالمئة', '% discount')),
              ('FREE_ITEM', Icons.card_giftcard_rounded, s.tr('شي ببلاش', 'Free item')),
              ('SERVICE', Icons.room_service_rounded, s.tr('خدمة / حجز', 'Service / booking')),
            ])
              ChoiceChip(
                avatar: Icon(icon, size: 18, color: _kind == k ? MkColors.purple900 : MkColors.purple500),
                label: Text(label),
                selected: _kind == k,
                showCheckmark: false,
                selectedColor: MkColors.yellow500,
                onSelected: (_) => setState(() => _kind = k),
              ),
          ],
        ),
        if (_kind == 'DISCOUNT') ...[
          const SizedBox(height: MkSpace.sm),
          TextField(
            controller: _discount,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            decoration: InputDecoration(labelText: s.tr('نسبة الخصم', 'Discount'), suffixText: '%'),
          ),
        ],
        const SizedBox(height: MkSpace.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _points,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                decoration: InputDecoration(labelText: s.tr('سعره بالنقاط', 'Points cost'), hintText: '0', helperText: s.tr('٠ = ببلاش', '0 = free')),
              ),
            ),
            const SizedBox(width: MkSpace.sm),
            Expanded(
              child: TextField(
                controller: _saving,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: s.tr('توفير الزبون', 'Customer saves'), prefixText: r'$ '),
              ),
            ),
          ],
        ),
        const SizedBox(height: MkSpace.xs),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _booking,
          onChanged: (v) => setState(() => _booking = v),
          title: Text(s.tr('بدها حجز وموافقة', 'Needs booking and approval')),
          subtitle: Text(
            _booking
                ? s.tr('الزبون بيطلب، إنت بتقبل', 'Customer requests, you accept')
                : s.tr('الكاشير بيطبقها مباشرة بالمحل', 'Cashier applies it in store'),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _max,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                decoration: InputDecoration(labelText: s.tr('لكل زبون', 'Per customer')),
              ),
            ),
            const SizedBox(width: MkSpace.sm),
            Expanded(
              child: TextField(
                controller: _limit,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                decoration: InputDecoration(labelText: s.tr('العدد الكلي', 'Total limit'), hintText: '∞'),
              ),
            ),
          ],
        ),
        const SizedBox(height: MkSpace.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickDate(true),
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text('${s.tr('من', 'From')} ${fmtDate(_from)}'),
              ),
            ),
            const SizedBox(width: MkSpace.sm),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickDate(false),
                icon: const Icon(Icons.event_busy_rounded, size: 18),
                label: Text(_to == null ? s.tr('بلا نهاية', 'No end') : '${s.tr('لـ', 'To')} ${fmtDate(_to!)}'),
              ),
            ),
          ],
        ),
        if (_to != null)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(onPressed: () => setState(() => _to = null), child: Text(s.tr('شيل تاريخ النهاية', 'Remove end date'))),
          ),
        const SizedBox(height: MkSpace.xs),
        TextField(controller: _terms, maxLength: 600, maxLines: 3, minLines: 1, decoration: InputDecoration(labelText: s.tr('الشروط (اختياري)', 'Terms (optional)'))),
        const SizedBox(height: MkSpace.md),
        MkButton(label: s.save, icon: Icons.check_rounded, kind: MkButtonKind.accent, loading: _busy, onPressed: _uploading ? null : _save),
        if (_isEdit) ...[
          const SizedBox(height: MkSpace.xs),
          MkButton(label: s.tr('أرشفة العرض', 'Archive offer'), kind: MkButtonKind.danger, onPressed: _busy ? null : () => _save(status: 'ARCHIVED')),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- Rewards
class _RewardsList extends ConsumerWidget {
  const _RewardsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    return ref.watch(ownerRewardsProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => MkErrorState(title: s.noConnection, retryLabel: s.retry, onRetry: () => ref.invalidate(ownerRewardsProvider)),
          data: (list) => list.isEmpty
              ? MkEmptyState(
                  icon: Icons.redeem_rounded,
                  title: s.tr('ما عندك مكافآت بعد', 'No rewards yet'),
                  message: s.tr('مثلاً: قهوة ببلاش مقابل ٥٠٠ نقطة.', 'For example: a free coffee for 500 points.'),
                )
              : Column(
                  children: [
                    for (final w in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: MkSpace.sm),
                        child: MkCard(
                          onTap: () => showMkSheet<void>(context, builder: (ctx) => RewardEditor(reward: w)),
                          child: Row(
                            children: [
                              SizedBox(width: 64, height: 64, child: MkNetImage(url: url(w['imageUrl'] as String?), radius: MkRadius.md, fallbackIcon: Icons.redeem_rounded)),
                              const SizedBox(width: MkSpace.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(w['title'] as String, style: t.titleSmall),
                                    Text('${formatPoints(w['pointsCost'] as num)} ${s.points}', style: t.labelLarge?.copyWith(color: MkColors.purple700)),
                                    Text(
                                      [
                                        s.tr('انصرفت ${w['redeemed']} مرة', 'Redeemed ${w['redeemed']}×'),
                                        if (w['stock'] != null) s.tr('بقي ${w['stock']}', '${w['stock']} left'),
                                      ].join(' · '),
                                      style: t.bodySmall?.copyWith(color: MkColors.ink3),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: w['status'] == 'ACTIVE',
                                onChanged: (v) async {
                                  try {
                                    await ref.read(apiProvider).patchReward(w['id'] as String, {'status': v ? 'ACTIVE' : 'PAUSED'});
                                    ref.invalidate(ownerRewardsProvider);
                                  } on Object catch (e) {
                                    if (context.mounted) showApiError(context, s, e);
                                  }
                                },
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

class RewardEditor extends ConsumerStatefulWidget {
  const RewardEditor({this.reward, super.key});
  final Json? reward;

  @override
  ConsumerState<RewardEditor> createState() => _RewardEditorState();
}

class _RewardEditorState extends ConsumerState<RewardEditor> {
  late final Json w = widget.reward ?? const {};
  late final _title = TextEditingController(text: w['title'] as String? ?? '');
  late final _desc = TextEditingController(text: w['description'] as String? ?? '');
  late final _points = TextEditingController(text: w['pointsCost']?.toString() ?? '');
  late final _value = TextEditingController(text: minorToText((w['valueMinor'] as num?)?.toInt()));
  late final _stock = TextEditingController(text: w['stock']?.toString() ?? '');
  late String? _imageId = w['imageId'] as String?;
  Uint8List? _bytes;
  bool _uploading = false;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_title, _desc, _points, _value, _stock]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final s = ref.read(stringsProvider);
    final bytes = await pickImageBytes(maxWidth: 1200);
    if (bytes == null) return;
    setState(() {
      _bytes = bytes;
      _uploading = true;
    });
    try {
      final r = await ref.read(apiProvider).uploadImage('item', bytes);
      setState(() => _imageId = r.id);
    } on Object catch (e) {
      if (mounted) showApiError(context, s, e);
      setState(() => _bytes = null);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save({String? status}) async {
    final s = ref.read(stringsProvider);
    final pts = int.tryParse(_points.text) ?? 0;
    if (_title.text.trim().length < 2 || pts <= 0) {
      MkToast.show(context, s.tr('اكتب الاسم وعدد النقاط', 'Add a name and the points'), kind: MkToastKind.error);
      return;
    }
    final data = <String, dynamic>{
      'title': _title.text.trim(),
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'imageId': _imageId,
      'pointsCost': pts,
      'valueMinor': parseToMinor(_value.text) ?? 0,
      'stock': int.tryParse(_stock.text),
      if (status != null) 'status': status,
    };
    setState(() => _busy = true);
    try {
      final api = ref.read(apiProvider);
      if (widget.reward != null) {
        await api.patchReward(w['id'] as String, data);
      } else {
        data.removeWhere((k, v) => v == null);
        await api.createReward(data);
      }
      ref.invalidate(ownerRewardsProvider);
      if (mounted) {
        Navigator.of(context).pop();
        MkToast.show(context, s.saved, kind: MkToastKind.success);
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
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final pts = int.tryParse(_points.text) ?? 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.reward == null ? s.tr('مكافأة جديدة', 'New reward') : s.tr('تعديل المكافأة', 'Edit reward'), style: t.titleLarge),
        const SizedBox(height: MkSpace.md),
        ImagePickBox(url: url(w['imageUrl'] as String?), bytes: _bytes, busy: _uploading, label: s.tr('صورة', 'Photo'), aspectRatio: 2, onTap: _pickImage),
        const SizedBox(height: MkSpace.md),
        TextField(controller: _title, maxLength: 90, decoration: InputDecoration(labelText: s.tr('الاسم', 'Name'), hintText: s.tr('قهوة ببلاش', 'Free coffee'))),
        TextField(controller: _desc, maxLength: 600, maxLines: 2, minLines: 1, decoration: InputDecoration(labelText: s.tr('الوصف', 'Description'))),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _points,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: s.tr('النقاط', 'Points'), helperText: pts > 0 ? '≈ ${formatMinor(pts, 'USD')}' : null),
              ),
            ),
            const SizedBox(width: MkSpace.sm),
            Expanded(
              child: TextField(
                controller: _value,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: s.tr('قيمتها', 'Value'), prefixText: r'$ '),
              ),
            ),
          ],
        ),
        const SizedBox(height: MkSpace.sm),
        TextField(
          controller: _stock,
          keyboardType: TextInputType.number,
          inputFormatters: digits,
          decoration: InputDecoration(labelText: s.tr('الكمية (اختياري)', 'Stock (optional)'), hintText: '∞'),
        ),
        const SizedBox(height: MkSpace.md),
        MkButton(label: s.save, icon: Icons.check_rounded, kind: MkButtonKind.accent, loading: _busy, onPressed: _uploading ? null : _save),
        if (widget.reward != null) ...[
          const SizedBox(height: MkSpace.xs),
          MkButton(label: s.tr('أرشفة', 'Archive'), kind: MkButtonKind.danger, onPressed: _busy ? null : () => _save(status: 'ARCHIVED')),
        ],
      ],
    );
  }
}
