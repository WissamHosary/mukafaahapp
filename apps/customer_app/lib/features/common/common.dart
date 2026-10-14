import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../../data/api.dart';

String money(int minor) => formatMinor(minor, 'USD');

String two(int n) => n.toString().padLeft(2, '0');

String fmtDate(DateTime d) => '${two(d.day)}/${two(d.month)}/${d.year}';

String fmtDateTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${fmtDate(d)} · ${two(h)}:${two(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
}

/// "2026-07-07" -> "07/07/2026"
String fmtIsoDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  final d = DateTime.tryParse(iso);
  return d == null ? iso : fmtDate(d);
}

/// A category's name as set in Mukafaah Manager, falling back to the built-in name.
/// Pass `ref.watch(categoriesProvider).value` from the widget's build.
String categoryName(S s, List<CategoryInfo>? cats, String key) {
  for (final c in cats ?? const <CategoryInfo>[]) {
    if (c.key == key) return c.name(s.isAr);
  }
  return s.category(key);
}

String errorText(S s, Object e) => e is ApiException ? s.errorV2(e.code) : s.somethingWrong;

/// A tier's name as set in Mukafaah Manager, falling back to the built-in name.
String tierName(S s, String? name, String code) => (name == null || name.trim().isEmpty) ? s.tier(code) : name;

/// Error text for codes added in v0.7 (redeem approvals, Mukafaah Points), else the shared table.
String errorV7(S s, String? code) => switch (code) {
      null || '' => s.somethingWrong,
      'REQUEST_EXPIRED' || 'EXPIRED' => s.tr('انتهت مدة الطلب', 'This request has expired'),
      'REQUEST_NOT_PENDING' || 'NOT_PENDING' => s.tr('الطلب انعالج من قبل', 'This request was already handled'),
      'CANCELLED' => s.tr('الكاشير لغى الطلب', 'The cashier cancelled this request'),
      'NOT_A_FRIEND' => s.tr('هالمحل مش من أصدقاء مكافأة', 'This shop is not a Mukafaah Friend'),
      'OVER_LIMIT' => s.tr('أكتر من الحد المسموح بالمحل', "Above this shop's limit"),
      final String c => RegExp(r'^[A-Z0-9_]+$').hasMatch(c) ? s.errorV2(c) : c,
    };

/// Shop card wired to strings, image URLs and navigation.
class ShopCardTile extends ConsumerWidget {
  const ShopCardTile({required this.shop, this.width, super.key});

  final ShopCard shop;
  final double? width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final url = ref.watch(mediaUrlProvider);
    return MkShopCard(
      width: width,
      name: shop.name,
      coverUrl: url(shop.coverUrl),
      logoUrl: url(shop.logoUrl),
      rating: shop.rating,
      programType: shop.programType,
      programLabel: s.programType(shop.programType),
      pointsText: '${formatPoints(shop.myPoints)} ${s.tr('نقطة', 'pts')}',
      pointsBackText: s.tr('${shop.earnText}% نقاط', '${shop.earnText}% back'),
      ratingCount: shop.ratingCount,
      addressText: shop.place.isEmpty ? s.noAddress : shop.place,
      buttonLabel: s.visitShop,
      badge: shop.offersCount > 0 ? '${shop.offersCount} ${s.offers}' : null,
      onTap: () => context.push('/shop/${shop.id}'),
    );
  }
}

/// One line of points activity (earned, used, sent, received).
class ActivityTile extends ConsumerWidget {
  const ActivityTile({required this.item, super.key});

  final ActivityItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final plus = item.points > 0;
    final reversed = item.type == 'VOID' || item.type == 'REVERSAL';
    final title = item.type == 'TRANSFER'
        ? (item.counterpartName ?? s.txLabel2(item.type, item.points))
        : (item.businessName ?? s.appName);
    final sub = [s.txLabel2(item.type, item.points), if (item.detail != null) item.detail!].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            height: 42,
            child: item.businessLogoUrl != null && item.type != 'TRANSFER'
                ? ClipOval(child: MkNetImage(url: url(item.businessLogoUrl), fallbackName: item.businessName, cacheWidth: 120))
                : MkIconTile(
                    icon: item.type == 'TRANSFER'
                        ? Icons.swap_horiz_rounded
                        : plus
                            ? Icons.toll_rounded
                            : Icons.redeem_rounded,
                    size: 42,
                    bg: plus ? MkColors.successBg : MkColors.dangerBg,
                    color: plus ? MkColors.success : MkColors.danger,
                  ),
          ),
          const SizedBox(width: MkSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: MkColors.ink2)),
                Text(fmtDateTime(item.createdAt), style: t.labelSmall?.copyWith(color: MkColors.ink3, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          Text(
            '${plus ? '+' : ''}${formatPoints(item.points)}',
            textDirection: TextDirection.ltr,
            style: t.titleSmall?.copyWith(
              color: reversed ? MkColors.ink3 : (plus ? MkColors.success : MkColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}

/// Offer card wired to the booking sheet.
class OfferTile extends ConsumerWidget {
  const OfferTile({required this.offer, this.width, super.key});

  final Offer offer;
  final double? width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final url = ref.watch(mediaUrlProvider);
    return MkOfferCard(
      width: width,
      title: offer.title,
      subtitle: offer.description ?? offer.businessName,
      meta: s.validity(fmtIsoDate(offer.validFrom), offer.validTo == null ? '∞' : fmtIsoDate(offer.validTo)),
      imageUrl: url(offer.imageUrl),
      logoUrl: url(offer.businessLogoUrl),
      actionLabel: offer.requiresBooking ? s.book : s.tr('بالمحل', 'In store'),
      tag: offer.discountPercent != null
          ? '-${offer.discountPercent}%'
          : offer.pointsCost > 0
              ? '${formatPoints(offer.pointsCost)} ${s.points}'
              : null,
      onTap: () => showOfferSheet(context, ref, offer),
    );
  }
}

/// Offer details and booking request.
Future<void> showOfferSheet(BuildContext context, WidgetRef ref, Offer offer) {
  return showMkSheet<void>(context, builder: (ctx) => _OfferSheet(offer: offer));
}

class _OfferSheet extends ConsumerStatefulWidget {
  const _OfferSheet({required this.offer});
  final Offer offer;

  @override
  ConsumerState<_OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends ConsumerState<_OfferSheet> {
  DateTime? _at;
  int _party = 2;
  final _note = TextEditingController();
  bool _busy = false;
  Booking? _done;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 120)),
      initialDate: _at ?? now,
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at ?? now.add(const Duration(hours: 1))));
    if (t == null) return;
    setState(() => _at = DateTime(d.year, d.month, d.day, t.hour, t.minute));
  }

  Future<void> _book() async {
    final s = ref.read(stringsProvider);
    setState(() => _busy = true);
    try {
      final b = await ref.read(apiProvider).book(widget.offer.id, at: _at, partySize: _party, note: _note.text);
      ref
        ..invalidate(bookingsProvider)
        ..invalidate(shopProvider(widget.offer.businessId));
      setState(() => _done = b);
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
    final url = ref.watch(mediaUrlProvider);
    final o = widget.offer;
    if (_done != null) {
      return Padding(
        padding: const EdgeInsets.only(top: MkSpace.xl),
        child: MkSuccessView(
          title: s.tr('انبعت طلب الحجز', 'Booking request sent'),
          subtitle: s.tr(
            'رح يوصلك إشعار لما ${o.businessName} يقبل. رمز الحجز: ${_done!.code}',
            "You'll get a notification when ${o.businessName} accepts. Booking code: ${_done!.code}",
          ),
          action: s.myBookings,
          onAction: () {
            Navigator.of(context).pop();
            context.push('/bookings');
          },
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(aspectRatio: 16 / 9, child: MkNetImage(url: url(o.imageUrl), radius: MkRadius.lg, fallbackIcon: Icons.local_offer_rounded)),
        const SizedBox(height: MkSpace.md),
        Row(
          children: [
            SizedBox(width: 28, height: 28, child: ClipOval(child: MkNetImage(url: url(o.businessLogoUrl), fallbackName: o.businessName))),
            const SizedBox(width: MkSpace.xs),
            Expanded(child: Text(o.businessName, style: t.labelLarge?.copyWith(color: MkColors.ink2))),
            if (o.discountPercent != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: MkColors.yellow500, borderRadius: MkRadius.all(MkRadius.pill)),
                child: Text('-${o.discountPercent}%', style: t.labelMedium?.copyWith(color: MkColors.purple900)),
              ),
          ],
        ),
        const SizedBox(height: MkSpace.xs),
        Text(o.title, style: t.headlineSmall),
        if (o.description != null) ...[
          const SizedBox(height: MkSpace.xs),
          Text(o.description!, style: t.bodyMedium?.copyWith(color: MkColors.ink2)),
        ],
        const SizedBox(height: MkSpace.sm),
        Wrap(
          spacing: MkSpace.xs,
          runSpacing: MkSpace.xs,
          children: [
            _Fact(icon: Icons.event_rounded, text: s.validity(fmtIsoDate(o.validFrom), o.validTo == null ? '∞' : fmtIsoDate(o.validTo))),
            if (o.pointsCost > 0) _Fact(icon: Icons.toll_rounded, text: '${formatPoints(o.pointsCost)} ${s.points}'),
            if (o.savingMinor > 0) _Fact(icon: Icons.savings_rounded, text: s.tr('بتوفّر ${money(o.savingMinor)}', 'Save ${money(o.savingMinor)}')),
          ],
        ),
        if (o.terms != null) ...[
          const SizedBox(height: MkSpace.sm),
          Text(s.tr('الشروط', 'Terms'), style: t.titleSmall),
          Text(o.terms!, style: t.bodySmall?.copyWith(color: MkColors.ink2)),
        ],
        const SizedBox(height: MkSpace.lg),
        if (!o.requiresBooking) ...[
          MkCard(
            color: MkColors.yellow50,
            child: Row(
              children: [
                const Icon(Icons.qr_code_2_rounded, color: MkColors.purple900),
                const SizedBox(width: MkSpace.sm),
                Expanded(child: Text(s.tr('ما بدو حجز. اعرض رمزك عند الكاشير ليطبّق العرض.', 'No booking needed. Show your QR at the counter to use it.'))),
              ],
            ),
          ),
          const SizedBox(height: MkSpace.md),
          MkButton(
            label: s.myQr,
            icon: Icons.qr_code_2_rounded,
            kind: MkButtonKind.accent,
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/wallet');
            },
          ),
        ] else if (o.myOpenBooking != null) ...[
          MkCard(
            color: MkColors.purple50,
            child: Text(s.tr('عندك حجز لهالعرض: ', 'You booked this offer: ') + s.bookingStatus(o.myOpenBooking!)),
          ),
          const SizedBox(height: MkSpace.md),
          MkButton(
            label: s.myBookings,
            kind: MkButtonKind.secondary,
            onPressed: () {
              Navigator.of(context).pop();
              context.push('/bookings');
            },
          ),
        ] else ...[
          Text(s.tr('تفاصيل الحجز', 'Booking details'), style: t.titleMedium),
          const SizedBox(height: MkSpace.sm),
          MkCard(
            onTap: _pickTime,
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded, color: MkColors.purple700),
                const SizedBox(width: MkSpace.sm),
                Expanded(
                  child: Text(_at == null ? s.tr('اختار الوقت (اختياري)', 'Pick a time (optional)') : fmtDateTime(_at!)),
                ),
                const Icon(Icons.chevron_right_rounded, color: MkColors.ink3),
              ],
            ),
          ),
          const SizedBox(height: MkSpace.sm),
          MkCard(
            child: Row(
              children: [
                const Icon(Icons.groups_rounded, color: MkColors.purple700),
                const SizedBox(width: MkSpace.sm),
                Expanded(child: Text(s.tr('عدد الأشخاص', 'People'))),
                IconButton(onPressed: _party > 1 ? () => setState(() => _party--) : null, icon: const Icon(Icons.remove_circle_outline_rounded)),
                Text('$_party', style: t.titleMedium),
                IconButton(onPressed: _party < 50 ? () => setState(() => _party++) : null, icon: const Icon(Icons.add_circle_outline_rounded)),
              ],
            ),
          ),
          const SizedBox(height: MkSpace.sm),
          TextField(
            controller: _note,
            maxLength: 300,
            maxLines: 2,
            decoration: InputDecoration(hintText: s.tr('ملاحظة للمحل (اختياري)', 'Note for the shop (optional)')),
          ),
          const SizedBox(height: MkSpace.sm),
          MkButton(label: s.book, icon: Icons.event_available_rounded, kind: MkButtonKind.accent, loading: _busy, onPressed: _book),
          const SizedBox(height: MkSpace.xs),
          Text(
            s.tr('المحل بيقبل الحجز وبيوصلك إشعار. ما في دفع بالتطبيق.', 'The shop accepts your request and you get notified. No payment in the app.'),
            textAlign: TextAlign.center,
            style: t.bodySmall?.copyWith(color: MkColors.ink3),
          ),
        ],
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: MkColors.purple50, borderRadius: MkRadius.all(MkRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: MkColors.purple700),
          const SizedBox(width: 4),
          Text(text, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

/// Standard async section: skeleton while loading, retry on error.
class AsyncSection<T> extends ConsumerWidget {
  const AsyncSection({required this.value, required this.builder, required this.onRetry, this.loading, super.key});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback onRetry;
  final Widget? loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return value.when(
      data: builder,
      loading: () => loading ?? const Padding(padding: EdgeInsets.all(MkSpace.xxl), child: Center(child: CircularProgressIndicator())),
      error: (e, _) => MkErrorState(title: errorText(s, e), retryLabel: s.retry, onRetry: onRetry),
    );
  }
}
