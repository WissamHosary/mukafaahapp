import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../../data/api.dart';
import 'owner_shell.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final range = ref.watch(dashboardRangeProvider);
    final dash = ref.watch(dashboardProvider);
    final biz = ref.watch(businessProvider);
    return OwnerPage(
      title: biz.value?.name ?? s.dashboard,
      onRefresh: () => ref.refresh(dashboardProvider.future),
      child: ListView(
        padding: const EdgeInsets.all(MkSpace.lg),
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final r in [(0, s.today), (7, s.last7), (30, s.last30)])
                ChoiceChip(
                  label: Text(r.$2),
                  selected: range == r.$1,
                  onSelected: (_) => ref.read(dashboardRangeProvider.notifier).set(r.$1),
                ),
            ],
          ),
          const SizedBox(height: MkSpace.md),
          dash.when(
            loading: () => MkSkeleton(loading: true, child: _Body(d: Dashboard(_emptyJson), s: s)),
            error: (e, _) => MkErrorState(
              title: s.noConnection,
              retryLabel: s.retry,
              onRetry: () => ref.invalidate(dashboardProvider),
            ),
            data: (d) => _Body(d: d, s: s),
          ),
        ],
      ),
    );
  }
}

const Map<String, dynamic> _emptyJson = {
  'currency': 'USD',
  'totals': <String, dynamic>{},
  'byCashier': <dynamic>[],
  'byBranch': <dynamic>[],
  'daily': <dynamic>[],
};

class _Body extends StatelessWidget {
  const _Body({required this.d, required this.s});
  final Dashboard d;
  final S s;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final w = MediaQuery.sizeOf(context).width;
    final cols = w >= 1100 ? 4 : (w >= 700 ? 3 : 2);
    final tiles = [
      MkStatTile(label: s.billsEntered, value: formatMinor(d.billsMinor, d.currency), icon: Icons.payments_rounded, highlight: true),
      MkStatTile(label: s.txCount, value: formatPoints(d.earnTx + d.redeemTx), icon: Icons.receipt_long_rounded),
      MkStatTile(label: s.pointsIssued, value: formatPoints(d.pointsIssued), icon: Icons.add_circle_rounded),
      MkStatTile(label: s.pointsRedeemed, value: formatPoints(d.pointsRedeemed), icon: Icons.redeem_rounded),
      MkStatTile(label: s.prePointsIssued, value: formatPoints(d.prepointsIssued), icon: Icons.card_giftcard_rounded),
      MkStatTile(label: s.customers, value: formatPoints(d.customers), icon: Icons.people_alt_rounded),
      MkStatTile(label: s.newCustomers, value: formatPoints(d.newCustomers), icon: Icons.person_add_alt_1_rounded),
      MkStatTile(label: s.returningCustomers, value: formatPoints(d.returningCustomers), icon: Icons.replay_rounded),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: MkSpace.sm,
          crossAxisSpacing: MkSpace.sm,
          childAspectRatio: 1.7,
          children: [for (var i = 0; i < tiles.length; i++) MkEntrance(index: i, child: tiles[i])],
        ),
        if (d.pendingBookings > 0) ...[
          const SizedBox(height: MkSpace.md),
          MkCard(
            color: MkColors.yellow500,
            onTap: () => context.go('/owner/bookings'),
            child: Row(
              children: [
                const MkIconTile(icon: Icons.event_note_rounded, bg: MkColors.purple900, color: MkColors.yellow500),
                const SizedBox(width: MkSpace.sm),
                Expanded(
                  child: Text(
                    s.tr('${d.pendingBookings} حجز ناطر موافقتك', '${d.pendingBookings} bookings waiting for you'),
                    style: t.titleSmall?.copyWith(color: MkColors.purple900),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: MkColors.purple900),
              ],
            ),
          ),
        ],
        MkSectionHeader(title: s.tr('العروض والتفاعل', 'Offers & engagement')),
        GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: MkSpace.sm,
          crossAxisSpacing: MkSpace.sm,
          childAspectRatio: 1.7,
          children: [
            MkStatTile(label: s.tr('عروض مستعملة', 'Offers used'), value: formatPoints(d.offersUsed), icon: Icons.local_offer_rounded),
            MkStatTile(label: s.tr('مكافآت مصروفة', 'Rewards redeemed'), value: formatPoints(d.rewardsRedeemed), icon: Icons.redeem_rounded),
            MkStatTile(label: s.tr('حجوزات مقبولة', 'Accepted bookings'), value: formatPoints(d.acceptedBookings), icon: Icons.event_available_rounded),
            MkStatTile(label: s.tr('طلبات واتساب', 'WhatsApp orders'), value: formatPoints(d.whatsappOrders), icon: Icons.chat_rounded),
            MkStatTile(
              label: s.tr('التقييم (${d.ratingCount})', 'Rating (${d.ratingCount})'),
              value: d.ratingCount == 0 ? '—' : '${d.rating} ★',
              icon: Icons.star_rounded,
            ),
          ],
        ),
        if (d.daily.length > 1) ...[
          MkSectionHeader(title: s.activity),
          MkCard(child: SizedBox(height: 160, child: _Bars(values: [for (final x in d.daily) (x['transactions'] as num).toInt()]))),
        ],
        MkSectionHeader(title: s.cashierPerformance),
        if (d.byCashier.isEmpty)
          MkCard(child: Padding(padding: const EdgeInsets.all(MkSpace.md), child: Text(s.noData, style: t.bodyMedium)))
        else
          MkCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final c in d.byCashier)
                  ListTile(
                    leading: MkMonogram(name: c['name'] as String, size: 40),
                    title: Text(c['name'] as String, style: t.titleSmall),
                    subtitle: Text(
                      '${s.txCount}: ${c['transactions']} · ${s.pointsIssued}: ${formatPoints(c['pointsIssued'] as num)}',
                    ),
                    trailing: Text(
                      formatMinor((c['billsMinor'] as num).toInt(), d.currency),
                      textDirection: TextDirection.ltr,
                      style: t.titleMedium,
                    ),
                  ),
              ],
            ),
          ),
        if (d.byBranch.length > 1) ...[
          MkSectionHeader(title: s.byBranch),
          MkCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final b in d.byBranch)
                  ListTile(
                    leading: const MkIconTile(icon: Icons.storefront_rounded, size: 40),
                    title: Text(b['name'] as String),
                    subtitle: Text('${s.txCount}: ${b['transactions']}'),
                    trailing: Text(formatMinor((b['billsMinor'] as num).toInt(), d.currency), textDirection: TextDirection.ltr),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: MkSpace.xxl),
      ],
    );
  }
}

/// Minimal bar chart in brand colours (no chart library needed for this view).
class _Bars extends StatelessWidget {
  const _Bars({required this.values});
  final List<int> values;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: MkMotion.slow,
        curve: MkMotion.enter,
        builder: (context, t, _) => CustomPaint(painter: _BarsPainter(values, t), size: Size.infinite),
      );
}

class _BarsPainter extends CustomPainter {
  _BarsPainter(this.values, this.t);
  final List<int> values;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final maxV = math.max(1, values.reduce(math.max));
    final gap = 6.0;
    final w = (size.width - gap * (values.length - 1)) / values.length;
    for (var i = 0; i < values.length; i++) {
      final h = (values[i] / maxV) * (size.height - 8) * t;
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(i * (w + gap), size.height - h, w, h),
        const Radius.circular(6),
      );
      canvas.drawRRect(r, Paint()..color = i == values.length - 1 ? MkColors.yellow500 : MkColors.purple700);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) => old.t != t || old.values != values;
}
