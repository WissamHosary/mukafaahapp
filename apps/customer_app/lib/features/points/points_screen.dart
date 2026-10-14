import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../common/common.dart';

/// Points: history with totals and filters, plus balances per shop.
class PointsScreen extends ConsumerStatefulWidget {
  const PointsScreen({super.key});

  @override
  ConsumerState<PointsScreen> createState() => _PointsScreenState();
}

class _PointsScreenState extends ConsumerState<PointsScreen> {
  String _filter = 'all';
  String _q = '';
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(_tab == 0 ? s.history : s.tr('رصيدي بالمحلات', 'My balances')), centerTitle: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: MkSpace.md),
            child: MkTextTabs<int>(
              items: [(0, s.history), (1, s.tr('الرصيد', 'Balances'))],
              selected: _tab,
              onSelected: (v) => setState(() => _tab = v),
            ),
          ),
          Expanded(child: _tab == 0 ? _history(s) : const _Balances()),
        ],
      ),
    );
  }

  Widget _history(S s) {
    final t = Theme.of(context).textTheme;
    final data = ref.watch(historyProvider(_filter));
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(historyProvider(_filter));
        await ref.read(historyProvider(_filter).future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.sm, MkSpace.lg, MkSpace.xxl),
        children: [
          Row(
            children: [
              Expanded(child: MkSummaryTile(label: s.totalEarned, value: '+${formatPoints(data.value?.totalEarned ?? 0)}')),
              const SizedBox(width: MkSpace.sm),
              Expanded(
                child: MkSummaryTile(label: s.totalUsed, value: '-${formatPoints(data.value?.totalUsed ?? 0)}', positive: false),
              ),
            ],
          ),
          const SizedBox(height: MkSpace.md),
          MkSearchField(hint: s.searchShops, onChanged: (v) => setState(() => _q = v.trim().toLowerCase())),
          const SizedBox(height: MkSpace.sm),
          MkChoiceChips<String>(
            items: [('all', s.all), ('earned', s.earned), ('used', s.tr('مصروف', 'Used'))],
            selected: _filter,
            onSelected: (v) => setState(() => _filter = v),
          ),
          const SizedBox(height: MkSpace.sm),
          data.when(
            data: (h) {
              final items = _q.isEmpty
                  ? h.items
                  : h.items.where((x) => (x.businessName ?? x.counterpartName ?? '').toLowerCase().contains(_q)).toList();
              if (items.isEmpty) {
                return MkEmptyState(title: s.noActivityTitle, message: s.noActivityBody);
              }
              return MkCard(
                padding: const EdgeInsets.symmetric(horizontal: MkSpace.md, vertical: MkSpace.xs),
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      ActivityTile(item: items[i]),
                    ],
                  ],
                ),
              );
            },
            loading: () => const Padding(padding: EdgeInsets.all(MkSpace.xxl), child: Center(child: CircularProgressIndicator())),
            error: (e, _) => MkErrorState(
              title: errorText(s, e),
              retryLabel: s.retry,
              onRetry: () => ref.invalidate(historyProvider(_filter)),
            ),
          ),
          const SizedBox(height: MkSpace.xs),
          Text(
            s.tr('١٠٠ نقطة = \$١ خصم بالمحل', '100 points = \$1 off at the shop'),
            textAlign: TextAlign.center,
            style: t.bodySmall?.copyWith(color: MkColors.ink3),
          ),
        ],
      ),
    );
  }
}

class _Balances extends ConsumerWidget {
  const _Balances();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final wallet = ref.watch(walletProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(walletProvider);
        await ref.read(walletProvider.future);
      },
      child: wallet.when(
        data: (w) => ListView(
          padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.sm, MkSpace.lg, MkSpace.xxl),
          children: [
            MkWalletCard(title: s.totalBalance, points: w.total, pointsLabel: s.points, format: formatPoints),
            const SizedBox(height: MkSpace.md),
            if (w.programs.isEmpty) MkEmptyState(title: s.noProgramsTitle, message: s.noActivityBody),
            for (final p in w.programs)
              Padding(
                padding: const EdgeInsets.only(bottom: MkSpace.sm),
                child: MkCard(
                  child: Row(
                    children: [
                      MkMonogram(name: p.name, size: 44),
                      const SizedBox(width: MkSpace.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, style: t.titleSmall),
                            const SizedBox(height: 2),
                            MkProgramBadge(type: p.type, label: s.programType(p.type)),
                            const SizedBox(height: 2),
                            Text(s.usableAt(p.usableAt.length), style: t.bodySmall?.copyWith(color: MkColors.ink3)),
                          ],
                        ),
                      ),
                      Text(formatPoints(p.balance), style: t.titleLarge?.copyWith(color: MkColors.purple700)),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: MkSpace.sm),
            MkButton(
              label: s.transferPoints,
              icon: Icons.swap_horiz_rounded,
              kind: MkButtonKind.secondary,
              onPressed: () => context.push('/transfer'),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => MkErrorState(title: errorText(s, e), retryLabel: s.retry, onRetry: () => ref.invalidate(walletProvider)),
      ),
    );
  }
}
