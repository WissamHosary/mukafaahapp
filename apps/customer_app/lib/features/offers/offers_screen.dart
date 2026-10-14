import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../../data/api.dart';
import '../common/common.dart';
import '../shops/shop_screen.dart';

/// Offers (book with the shop) and Rewards (spend points at the counter).
class OffersScreen extends ConsumerStatefulWidget {
  const OffersScreen({super.key});

  @override
  ConsumerState<OffersScreen> createState() => _OffersScreenState();
}

class _OffersScreenState extends ConsumerState<OffersScreen> {
  int _tab = 0;
  String? _category;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final catInfo = ref.watch(categoriesProvider).value;
    final cats = <(String?, String)>[
      (null, s.all),
      if (catInfo != null) for (final c in catInfo) (c.key, c.name(s.isAr)) else for (final k in S.categoryKeys) (k, s.category(k)),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(s.offersRewards),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: s.myBookings,
            onPressed: () => context.push('/bookings'),
            icon: const Icon(Icons.event_note_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MkSpace.md),
            child: MkTextTabs<int>(
              items: [(0, s.offers), (1, s.rewards)],
              selected: _tab,
              onSelected: (v) => setState(() => _tab = v),
            ),
          ),
          const SizedBox(height: MkSpace.xs),
          MkChoiceChips<String?>(
            padding: const EdgeInsets.symmetric(horizontal: MkSpace.lg),
            items: cats,
            selected: _category,
            onSelected: (v) => setState(() => _category = v),
          ),
          const SizedBox(height: MkSpace.xs),
          Expanded(child: _tab == 0 ? _offers(s) : _rewards(s)),
        ],
      ),
    );
  }

  Widget _offers(S s) {
    final data = ref.watch(offersProvider(_category));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(offersProvider(_category));
        await ref.read(offersProvider(_category).future);
      },
      child: data.when(
        data: (list) => list.isEmpty
            ? ListView(
                children: [
                  MkEmptyState(
                    icon: Icons.local_offer_rounded,
                    title: s.tr('ما في عروض هون لهلق', 'No offers here yet'),
                    message: s.tr('رجاع شوف قريباً.', 'Check back soon.'),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.xs, MkSpace.lg, MkSpace.xxl),
                itemCount: list.length,
                separatorBuilder: (context, i) => const SizedBox(height: MkSpace.md),
                itemBuilder: (context, i) => MkEntrance(index: i % 6, child: OfferTile(offer: list[i])),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => MkErrorState(title: errorText(s, e), retryLabel: s.retry, onRetry: () => ref.invalidate(offersProvider(_category))),
      ),
    );
  }

  Widget _rewards(S s) {
    final data = ref.watch(rewardsProvider(_category));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(rewardsProvider(_category));
        await ref.read(rewardsProvider(_category).future);
      },
      child: data.when(
        data: (list) => list.isEmpty
            ? ListView(
                children: [
                  MkEmptyState(
                    icon: Icons.redeem_rounded,
                    title: s.tr('ما في مكافآت لهلق', 'No rewards yet'),
                    message: s.tr('المحلات بتضيف هدايا بتنصرف بالنقاط.', 'Shops add gifts you can get with points.'),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.xs, MkSpace.lg, MkSpace.xxl),
                itemCount: list.length,
                separatorBuilder: (context, i) => const SizedBox(height: MkSpace.sm),
                itemBuilder: (context, i) => MkEntrance(index: i % 6, child: RewardTile(reward: list[i], showShop: true)),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => MkErrorState(title: errorText(s, e), retryLabel: s.retry, onRetry: () => ref.invalidate(rewardsProvider(_category))),
      ),
    );
  }
}

/// The customer's booking requests and their status.
class BookingsScreen extends ConsumerWidget {
  const BookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final data = ref.watch(bookingsProvider);

    Color statusColor(String st) => switch (st) {
          'ACCEPTED' => MkColors.success,
          'REQUESTED' => MkColors.warning,
          'REDEEMED' => MkColors.purple700,
          _ => MkColors.ink3,
        };

    return Scaffold(
      appBar: AppBar(title: Text(s.myBookings), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(bookingsProvider);
          await ref.read(bookingsProvider.future);
        },
        child: data.when(
          data: (list) => list.isEmpty
              ? ListView(
                  children: [
                    MkEmptyState(
                      icon: Icons.event_available_rounded,
                      title: s.tr('ما عندك حجوزات', 'No bookings yet'),
                      message: s.tr('احجز عرض من العروض والمكافآت.', 'Book an offer from Offers & Rewards.'),
                      action: s.offers,
                      onAction: () => context.push('/offers'),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(MkSpace.lg),
                  itemCount: list.length,
                  separatorBuilder: (context, i) => const SizedBox(height: MkSpace.sm),
                  itemBuilder: (context, i) {
                    final b = list[i];
                    return MkCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              SizedBox(width: 56, height: 56, child: MkNetImage(url: url(b.offerImageUrl), radius: MkRadius.md, fallbackIcon: Icons.local_offer_rounded)),
                              const SizedBox(width: MkSpace.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(b.offerTitle ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                                    Text(b.businessName ?? '', style: t.bodySmall?.copyWith(color: MkColors.ink2)),
                                    if (b.requestedFor != null)
                                      Text(fmtDateTime(b.requestedFor!), style: t.labelSmall?.copyWith(color: MkColors.ink3)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor(b.status).withValues(alpha: 0.12),
                                  borderRadius: MkRadius.all(MkRadius.pill),
                                ),
                                child: Text(s.bookingStatus(b.status), style: t.labelSmall?.copyWith(color: statusColor(b.status))),
                              ),
                            ],
                          ),
                          if (b.status == 'ACCEPTED') ...[
                            const SizedBox(height: MkSpace.sm),
                            Container(
                              padding: const EdgeInsets.all(MkSpace.sm),
                              decoration: BoxDecoration(color: MkColors.yellow50, borderRadius: MkRadius.all(MkRadius.md)),
                              child: Row(
                                children: [
                                  const Icon(Icons.confirmation_number_rounded, color: MkColors.purple900),
                                  const SizedBox(width: MkSpace.xs),
                                  Expanded(
                                    child: Text(
                                      s.tr('رمز الحجز ${b.code}. اعرض رمزك QR بالمحل.', 'Booking code ${b.code}. Show your QR at the shop.'),
                                      style: t.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (b.status == 'DECLINED' && b.declineReason != null) ...[
                            const SizedBox(height: MkSpace.xs),
                            Text(b.declineReason!, style: t.bodySmall?.copyWith(color: MkColors.danger)),
                          ],
                          if (b.isOpen)
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton(
                                onPressed: () async {
                                  try {
                                    await ref.read(apiProvider).cancelBooking(b.id);
                                    ref.invalidate(bookingsProvider);
                                  } on ApiException catch (e) {
                                    if (context.mounted) MkToast.show(context, s.errorV2(e.code), kind: MkToastKind.error);
                                  }
                                },
                                child: Text(s.tr('إلغاء الحجز', 'Cancel booking'), style: const TextStyle(color: MkColors.danger)),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => MkErrorState(title: errorText(s, e), retryLabel: s.retry, onRetry: () => ref.invalidate(bookingsProvider)),
        ),
      ),
    );
  }
}

/// Keeps the import used for type references in this file.
typedef OfferList = List<Offer>;
