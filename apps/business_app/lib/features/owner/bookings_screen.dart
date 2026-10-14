import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import 'owner_shell.dart';
import 'owner_widgets.dart';

/// Booking requests from customers: accept or decline; history of the rest.
class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({super.key});

  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends ConsumerState<BookingsScreen> {
  String _status = 'REQUESTED';
  final Set<String> _busy = {};

  void _refresh() {
    ref
      ..invalidate(ownerBookingsProvider)
      ..invalidate(bookingSummaryProvider)
      ..invalidate(dashboardProvider)
      ..invalidate(ownerOffersProvider);
  }

  Future<void> _accept(String id) async {
    final s = ref.read(stringsProvider);
    setState(() => _busy.add(id));
    try {
      await ref.read(apiProvider).acceptBooking(id);
      _refresh();
      if (mounted) MkToast.show(context, s.tr('انقبل الحجز وانبعت إشعار للزبون', 'Accepted. The customer was notified.'), kind: MkToastKind.success);
    } on ApiException catch (e) {
      if (mounted) MkToast.show(context, s.errorV2(e.code), kind: MkToastKind.error);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _decline(String id) async {
    final s = ref.read(stringsProvider);
    final ctl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.tr('رفض الحجز', 'Decline booking')),
        content: TextField(
          controller: ctl,
          maxLength: 200,
          decoration: InputDecoration(hintText: s.tr('السبب (اختياري)، مثلاً: محجوز كامل', 'Reason (optional), e.g. fully booked')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MkColors.danger),
            onPressed: () => Navigator.pop(ctx, ctl.text),
            child: Text(s.tr('رفض', 'Decline')),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (reason == null) return;
    setState(() => _busy.add(id));
    try {
      await ref.read(apiProvider).declineBooking(id, reason);
      _refresh();
    } on ApiException catch (e) {
      if (mounted) MkToast.show(context, s.errorV2(e.code), kind: MkToastKind.error);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final summary = ref.watch(bookingSummaryProvider).value;
    final data = ref.watch(ownerBookingsProvider(_status));
    final requested = (summary?['requested'] as num?)?.toInt() ?? 0;
    final accepted = (summary?['accepted'] as num?)?.toInt() ?? 0;

    return OwnerPage(
      title: s.tr('الحجوزات', 'Bookings'),
      actions: [
        TextButton.icon(
          onPressed: () => context.go('/owner/orders'),
          icon: const Icon(Icons.shopping_bag_rounded),
          label: Text(s.tr('طلبات المتجر', 'Store orders')),
        ),
      ],
      onRefresh: () async => _refresh(),
      child: ListView(
        padding: const EdgeInsets.all(MkSpace.lg),
        children: [
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: 'REQUESTED', label: Text(s.tr('طلبات ($requested)', 'Requests ($requested)'))),
              ButtonSegment(value: 'ACCEPTED', label: Text(s.tr('مقبولة ($accepted)', 'Accepted ($accepted)'))),
              ButtonSegment(value: 'HISTORY', label: Text(s.tr('السجل', 'History'))),
            ],
            selected: {_status},
            onSelectionChanged: (v) => setState(() => _status = v.first),
          ),
          const SizedBox(height: MkSpace.md),
          data.when(
            loading: () => const Padding(padding: EdgeInsets.all(MkSpace.xxl), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => MkErrorState(title: s.noConnection, retryLabel: s.retry, onRetry: _refresh),
            data: (list) {
              if (list.isEmpty) {
                return MkEmptyState(
                  icon: Icons.event_note_rounded,
                  title: _status == 'REQUESTED' ? s.tr('ما في طلبات جديدة', 'No new requests') : s.tr('ما في شي هون', 'Nothing here yet'),
                  message: s.tr('لما الزباين يحجزوا عروضك بتبيّن هون.', 'When customers book your offers they show up here.'),
                );
              }
              return Column(
                children: [
                  for (final b in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: MkSpace.sm),
                      child: MkCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                SizedBox(
                                  width: 54,
                                  height: 54,
                                  child: MkNetImage(url: url(b['offerImageUrl'] as String?), radius: MkRadius.md, fallbackIcon: Icons.local_offer_rounded),
                                ),
                                const SizedBox(width: MkSpace.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text((b['offerTitle'] ?? '') as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                                      Text(
                                        '${b['customerName'] ?? s.tr('زبون', 'Customer')} · •••• ${b['customerLast4'] ?? ''}',
                                        style: t.bodySmall?.copyWith(color: MkColors.ink2),
                                      ),
                                    ],
                                  ),
                                ),
                                StatusPill(status: b['status'] as String),
                              ],
                            ),
                            const SizedBox(height: MkSpace.sm),
                            Wrap(
                              spacing: MkSpace.xs,
                              runSpacing: MkSpace.xs,
                              children: [
                                InfoChip(
                                  icon: Icons.schedule_rounded,
                                  text: b['requestedFor'] == null
                                      ? s.tr('أي وقت', 'Any time')
                                      : fmtDateTime(DateTime.parse(b['requestedFor'] as String).toLocal()),
                                ),
                                if (b['partySize'] != null) InfoChip(icon: Icons.groups_rounded, text: '${b['partySize']}'),
                                InfoChip(icon: Icons.confirmation_number_rounded, text: (b['code'] ?? '') as String),
                                if ((b['pointsCost'] as num? ?? 0) > 0)
                                  InfoChip(icon: Icons.toll_rounded, text: '${formatPoints(b['pointsCost'] as num)} ${s.points}'),
                              ],
                            ),
                            if (b['note'] != null) ...[
                              const SizedBox(height: MkSpace.xs),
                              Text('“${b['note']}”', style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                            ],
                            if (b['declineReason'] != null) ...[
                              const SizedBox(height: MkSpace.xs),
                              Text(b['declineReason'] as String, style: t.bodySmall?.copyWith(color: MkColors.danger)),
                            ],
                            if (b['status'] == 'REQUESTED') ...[
                              const SizedBox(height: MkSpace.sm),
                              Row(
                                children: [
                                  Expanded(
                                    child: MkButton(
                                      label: s.tr('رفض', 'Decline'),
                                      kind: MkButtonKind.danger,
                                      onPressed: _busy.contains(b['id']) ? null : () => _decline(b['id'] as String),
                                    ),
                                  ),
                                  const SizedBox(width: MkSpace.sm),
                                  Expanded(
                                    child: MkButton(
                                      label: s.tr('قبول', 'Accept'),
                                      icon: Icons.check_rounded,
                                      kind: MkButtonKind.accent,
                                      loading: _busy.contains(b['id']),
                                      onPressed: () => _accept(b['id'] as String),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (b['status'] == 'ACCEPTED') ...[
                              const SizedBox(height: MkSpace.xs),
                              Text(
                                s.tr('الكاشير بيكمّل الحجز لما الزبون يعرض رمزه.', 'The cashier completes it when the customer shows their QR.'),
                                style: t.bodySmall?.copyWith(color: MkColors.ink3),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: MkSpace.xxl),
        ],
      ),
    );
  }
}
