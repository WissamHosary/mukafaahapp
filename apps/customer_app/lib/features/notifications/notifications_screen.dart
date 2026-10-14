import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../common/common.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the list marks everything as read (after it loads).
    Future<void>.delayed(const Duration(milliseconds: 600), () async {
      try {
        await ref.read(apiProvider).readAllNotifications();
        ref.invalidate(homeProvider);
      } on Object {
        // Not important if this fails; it retries next time.
      }
    });
  }

  IconData _icon(String kind) => switch (kind) {
        'EARN' => Icons.toll_rounded,
        'REDEEM' || 'REWARD' => Icons.redeem_rounded,
        'TRANSFER_IN' => Icons.swap_horiz_rounded,
        'BOOKING_ACCEPTED' => Icons.event_available_rounded,
        'BOOKING_DECLINED' => Icons.event_busy_rounded,
        'OFFER_USED' => Icons.local_offer_rounded,
        'REFERRAL' => Icons.group_add_rounded,
        _ => Icons.notifications_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final data = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.notifications), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(notificationsProvider);
          await ref.read(notificationsProvider.future);
        },
        child: data.when(
          data: (list) => list.isEmpty
              ? ListView(
                  children: [
                    MkEmptyState(
                      icon: Icons.notifications_none_rounded,
                      title: s.tr('ما في إشعارات', 'No notifications'),
                      message: s.tr('رح نخبرك لما تربح نقاط أو ينقبل حجزك.', "We'll tell you when you earn points or a booking is accepted."),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(MkSpace.lg),
                  itemCount: list.length,
                  separatorBuilder: (context, i) => const SizedBox(height: MkSpace.xs),
                  itemBuilder: (context, i) {
                    final n = list[i];
                    return MkCard(
                      color: n.read ? null : MkColors.purple50,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          MkIconTile(icon: _icon(n.kind), size: 40),
                          const SizedBox(width: MkSpace.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(n.title, style: t.titleSmall),
                                if (n.body != null) Text(n.body!, style: t.bodySmall?.copyWith(color: MkColors.ink2)),
                                const SizedBox(height: 2),
                                Text(fmtDateTime(n.createdAt), style: t.labelSmall?.copyWith(color: MkColors.ink3, fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ),
                          if (!n.read)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(top: 6),
                              decoration: const BoxDecoration(color: MkColors.danger, shape: BoxShape.circle),
                            ),
                        ],
                      ),
                    );
                  },
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => MkErrorState(title: errorText(s, e), retryLabel: s.retry, onRetry: () => ref.invalidate(notificationsProvider)),
        ),
      ),
    );
  }
}
