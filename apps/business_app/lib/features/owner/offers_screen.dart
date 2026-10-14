import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../../data/api.dart';
import 'catalog_screen.dart';
import 'owner_shell.dart';
import 'owner_widgets.dart';

/// Offers & discounts: the owner creates deals and % discounts, pauses or resumes
/// them, and sees how often they were requested and used.
class OffersScreen extends ConsumerStatefulWidget {
  const OffersScreen({super.key});

  @override
  ConsumerState<OffersScreen> createState() => _OffersScreenState();
}

enum _Filter { all, active, paused }

class _OffersScreenState extends ConsumerState<OffersScreen> {
  _Filter _filter = _Filter.all;

  void _new([String? kind]) =>
      showMkSheet<void>(context, builder: (ctx) => OfferEditor(initialKind: kind));

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final offers = ref.watch(ownerOffersProvider);
    return OwnerPage(
      title: s.tr('العروض والخصومات', 'Offers & discounts'),
      onRefresh: () => ref.refresh(ownerOffersProvider.future),
      fab: FloatingActionButton.extended(
        heroTag: 'offers-add',
        backgroundColor: MkColors.yellow500,
        foregroundColor: MkColors.purple900,
        onPressed: _new,
        icon: const Icon(Icons.add_rounded),
        label: Text(s.tr('عرض جديد', 'New offer')),
      ),
      child: offers.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => MkErrorState(title: s.noConnection, retryLabel: s.retry, onRetry: () => ref.invalidate(ownerOffersProvider)),
        data: (list) {
          final active = list.where((o) => o['status'] == 'ACTIVE').length;
          final paused = list.where((o) => o['status'] == 'PAUSED').length;
          final used = list.fold<int>(0, (n, o) => n + ((((o['stats'] as Map?) ?? const {})['redeemed'] as num?)?.toInt() ?? 0));
          final shown = switch (_filter) {
            _Filter.all => list,
            _Filter.active => list.where((o) => o['status'] == 'ACTIVE').toList(),
            _Filter.paused => list.where((o) => o['status'] == 'PAUSED').toList(),
          };
          return ListView(
            padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.md, MkSpace.lg, 120),
            children: [
              MkEntrance(
                child: _OffersHero(s: s, active: active, paused: paused, used: used, onDeal: () => _new('DEAL'), onDiscount: () => _new('DISCOUNT')),
              ),
              const SizedBox(height: MkSpace.lg),
              if (list.isNotEmpty)
                Wrap(
                  spacing: MkSpace.xs,
                  children: [
                    for (final (f, label) in [
                      (_Filter.all, '${s.tr('الكل', 'All')} · ${list.length}'),
                      (_Filter.active, '${s.tr('فعّالة', 'Active')} · $active'),
                      (_Filter.paused, '${s.tr('موقّفة', 'Paused')} · $paused'),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: _filter == f,
                        onSelected: (_) => setState(() => _filter = f),
                      ),
                  ],
                ),
              const SizedBox(height: MkSpace.md),
              AnimatedSwitcher(
                duration: MkMotion.base,
                switchInCurve: MkMotion.enter,
                child: shown.isEmpty
                    ? MkEmptyState(
                        key: ValueKey('empty-$_filter'),
                        icon: Icons.local_offer_rounded,
                        title: list.isEmpty ? s.tr('ما عندك عروض بعد', 'No offers yet') : s.tr('ما في شي هون', 'Nothing here'),
                        message: list.isEmpty
                            ? s.tr('اعمل أول عرض أو خصم، وبيظهر للزباين بالتطبيق فوراً.', 'Create your first deal or discount. Customers see it in the app right away.')
                            : null,
                        action: list.isEmpty ? s.tr('عرض جديد', 'New offer') : null,
                        onAction: list.isEmpty ? _new : null,
                      )
                    : Column(
                        key: ValueKey('list-$_filter-${shown.length}'),
                        children: [
                          for (final (i, o) in shown.indexed)
                            MkEntrance(index: i, child: _OfferCard(key: ValueKey(o['id']), offer: o)),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OffersHero extends StatelessWidget {
  const _OffersHero({
    required this.s,
    required this.active,
    required this.paused,
    required this.used,
    required this.onDeal,
    required this.onDiscount,
  });

  final S s;
  final int active;
  final int paused;
  final int used;
  final VoidCallback onDeal;
  final VoidCallback onDiscount;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget stat(String label, int v) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedPoints(value: v, style: t.headlineSmall?.copyWith(color: MkColors.yellow500, fontWeight: FontWeight.w800)),
              Text(label, style: t.labelMedium?.copyWith(color: const Color(0xFFD8CCE6))),
            ],
          ),
        );
    Widget quick(IconData icon, String label, VoidCallback onTap) => MkPressable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: MkSpace.sm, vertical: MkSpace.xs),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: MkRadius.all(MkRadius.pill),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: MkColors.yellow500),
                const SizedBox(width: 6),
                Text(label, style: t.labelLarge?.copyWith(color: Colors.white)),
              ],
            ),
          ),
        );
    return ClipRRect(
      borderRadius: MkRadius.all(MkRadius.xl),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [MkColors.purple900, MkColors.purple700, MkColors.purple500],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // Soft decorative bubbles.
            PositionedDirectional(
              top: -40,
              end: -30,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(shape: BoxShape.circle, color: MkColors.yellow500.withValues(alpha: 0.14)),
              ),
            ),
            PositionedDirectional(
              bottom: -50,
              start: -20,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.06)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(MkSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.tr('رجّع زباينك بعروض حلوة', 'Bring customers back'),
                              style: t.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              s.tr(
                                'العروض والخصومات بتظهر للزباين بالتطبيق. فيك تخليها ببلاش أو بالنقاط.',
                                'Deals and % discounts show in the customer app, free or paid with points.',
                              ),
                              style: t.bodySmall?.copyWith(color: const Color(0xFFD8CCE6)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: MkSpace.sm),
                      const MkFloat(
                        child: MkIconTile(icon: Icons.local_offer_rounded, size: 56, bg: MkColors.yellow500, color: MkColors.purple900),
                      ),
                    ],
                  ),
                  const SizedBox(height: MkSpace.lg),
                  Row(
                    children: [
                      stat(s.tr('فعّالة', 'Active'), active),
                      stat(s.tr('موقّفة', 'Paused'), paused),
                      stat(s.tr('انستعملت', 'Times used'), used),
                    ],
                  ),
                  const SizedBox(height: MkSpace.md),
                  Wrap(
                    spacing: MkSpace.xs,
                    runSpacing: MkSpace.xs,
                    children: [
                      quick(Icons.local_offer_rounded, s.tr('عرض', 'Deal'), onDeal),
                      quick(Icons.percent_rounded, s.tr('خصم %', '% discount'), onDiscount),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData offerKindIcon(String kind) => switch (kind) {
      'DISCOUNT' => Icons.percent_rounded,
      'FREE_ITEM' => Icons.card_giftcard_rounded,
      'SERVICE' => Icons.room_service_rounded,
      _ => Icons.local_offer_rounded,
    };

String offerKindLabel(S s, Json o) => switch (o['kind'] as String? ?? 'DEAL') {
      'DISCOUNT' => o['discountPercent'] == null ? s.tr('خصم', 'Discount') : '-${o['discountPercent']}%',
      'FREE_ITEM' => s.tr('ببلاش', 'Free item'),
      'SERVICE' => s.tr('خدمة', 'Service'),
      _ => s.tr('عرض', 'Deal'),
    };

class _OfferCard extends ConsumerStatefulWidget {
  const _OfferCard({required this.offer, super.key});
  final Json offer;

  @override
  ConsumerState<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends ConsumerState<_OfferCard> {
  bool? _optimistic;
  bool _busy = false;

  Json get o => widget.offer;

  Future<void> _toggle(bool v) async {
    final s = ref.read(stringsProvider);
    setState(() {
      _optimistic = v;
      _busy = true;
    });
    try {
      await ref.read(apiProvider).patchOffer(o['id'] as String, {'status': v ? 'ACTIVE' : 'PAUSED'});
      ref.invalidate(ownerOffersProvider);
      if (mounted) {
        MkToast.show(
          context,
          v ? s.tr('العرض رجع شغّال', 'Offer is live again') : s.tr('وقّفنا العرض', 'Offer paused'),
          kind: MkToastKind.success,
        );
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _optimistic = null);
        showApiError(context, s, e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final kind = (o['kind'] as String?) ?? 'DEAL';
    final active = _optimistic ?? o['status'] == 'ACTIVE';
    final cost = (o['pointsCost'] as num?)?.toInt() ?? 0;
    final stats = (o['stats'] as Map?) ?? const {};
    final from = DateTime.tryParse((o['validFrom'] as String?) ?? '');
    final to = DateTime.tryParse((o['validTo'] as String?) ?? '');
    final today = DateTime.now();
    final expired = to != null && to.isBefore(DateTime(today.year, today.month, today.day));
    final status = o['hiddenByAdmin'] == true
        ? 'HIDDEN'
        : expired
            ? 'EXPIRED'
            : (active ? 'ACTIVE' : 'PAUSED');
    final imageUrl = url(o['imageUrl'] as String?);

    final banner = AspectRatio(
      aspectRatio: 2.6,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null)
            MkNetImage(url: imageUrl, fallbackIcon: offerKindIcon(kind))
          else
            DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [MkColors.purple100, MkColors.yellow50],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: MkSpace.xl),
                  child: Icon(offerKindIcon(kind), size: 64, color: MkColors.purple500.withValues(alpha: 0.35)),
                ),
              ),
            ),
          // Paused offers fade back.
          AnimatedContainer(
            duration: MkMotion.base,
            color: active && !expired ? Colors.transparent : Colors.white.withValues(alpha: 0.55),
          ),
          PositionedDirectional(
            top: MkSpace.sm,
            start: MkSpace.sm,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: MkColors.yellow500,
                borderRadius: MkRadius.all(MkRadius.pill),
                boxShadow: MkShadow.soft,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(offerKindIcon(kind), size: 16, color: MkColors.purple900),
                  const SizedBox(width: 4),
                  Text(offerKindLabel(s, o), style: t.labelLarge?.copyWith(color: MkColors.purple900, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ),
          PositionedDirectional(top: MkSpace.sm, end: MkSpace.sm, child: StatusPill(status: status)),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: MkSpace.md),
      child: MkCard(
        padding: EdgeInsets.zero,
        onTap: () => showMkSheet<void>(context, builder: (ctx) => OfferEditor(offer: o)),
        child: ClipRRect(
          borderRadius: MkRadius.all(MkRadius.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              banner,
              Padding(
                padding: const EdgeInsets.fromLTRB(MkSpace.md, MkSpace.sm, MkSpace.xs, MkSpace.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(o['title'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          if ((o['description'] as String?)?.isNotEmpty ?? false)
                            Text(o['description'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: MkColors.ink2)),
                          const SizedBox(height: MkSpace.xs),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _CostPill(text: cost > 0 ? '${formatPoints(cost)} ${s.points}' : s.tr('ببلاش', 'Free'), coin: cost > 0),
                              InfoChip(
                                icon: o['requiresBooking'] == true ? Icons.event_note_rounded : Icons.storefront_rounded,
                                text: o['requiresBooking'] == true ? s.tr('بحجز', 'Booking') : s.tr('بالمحل', 'Walk-in'),
                              ),
                              InfoChip(icon: Icons.person_rounded, text: s.tr('${o['maxPerCustomer'] ?? 1}× للزبون', '${o['maxPerCustomer'] ?? 1}× per customer')),
                              if (from != null)
                                InfoChip(
                                  icon: Icons.event_rounded,
                                  text: to == null ? '${s.tr('من', 'From')} ${fmtDate(from)}' : '${fmtDate(from)} → ${fmtDate(to)}',
                                ),
                            ],
                          ),
                          const SizedBox(height: MkSpace.xs),
                          Row(
                            children: [
                              _Stat(icon: Icons.mark_email_unread_rounded, value: '${stats['requested'] ?? 0}', label: s.tr('طلبات', 'Requests')),
                              _Stat(icon: Icons.check_circle_rounded, value: '${stats['accepted'] ?? 0}', label: s.tr('مقبول', 'Accepted')),
                              _Stat(icon: Icons.done_all_rounded, value: '${stats['redeemed'] ?? 0}', label: s.tr('مستعمل', 'Used')),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        Switch(value: active, onChanged: _busy ? null : _toggle),
                        Text(active ? s.tr('شغّال', 'Live') : s.tr('موقّف', 'Paused'), style: t.labelSmall?.copyWith(color: active ? MkColors.success : MkColors.ink3)),
                      ],
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

class _CostPill extends StatelessWidget {
  const _CostPill({required this.text, required this.coin});
  final String text;
  final bool coin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: MkColors.yellow50, borderRadius: MkRadius.all(MkRadius.pill), border: Border.all(color: MkColors.yellow200)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (coin) const MkCoin(size: 16) else const Icon(Icons.celebration_rounded, size: 14, color: MkColors.purple700),
          const SizedBox(width: 4),
          Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: MkColors.purple900, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: MkSpace.md),
      child: Tooltip(
        message: label,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: MkColors.ink3),
            const SizedBox(width: 3),
            Text(value, style: t.labelMedium?.copyWith(color: MkColors.ink2)),
          ],
        ),
      ),
    );
  }
}
