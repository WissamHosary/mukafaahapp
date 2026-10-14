import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../../data/api.dart';
import '../common/common.dart';

/// Mukafaah Points: company points for joining, referrals, first bill and tier
/// bonuses, spendable at Mukafaah Friends shops up to each shop's limit per bill.
class MukafaahScreen extends ConsumerWidget {
  const MukafaahScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final data = ref.watch(mukafaahProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.tr('نقاط مكافأة', 'Mukafaah Points')), centerTitle: true),
      body: RefreshIndicator(
        color: MkColors.purple900,
        onRefresh: () async {
          ref.invalidate(mukafaahProvider);
          await ref.read(mukafaahProvider.future);
        },
        child: data.when(
          data: (d) => _Body(d: d),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 120),
              MkErrorState(title: errorText(s, e), retryLabel: s.retry, onRetry: () => ref.invalidate(mukafaahProvider)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.d});
  final MukafaahData d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final done = {for (final h in d.history) h.type};
    return ListView(
      padding: const EdgeInsets.fromLTRB(MkSpace.md, MkSpace.sm, MkSpace.md, MkSpace.xxl),
      children: [
        MkEntrance(
          child: Container(
            padding: const EdgeInsets.all(MkSpace.lg),
            decoration: BoxDecoration(
              borderRadius: MkRadius.all(MkRadius.xl),
              gradient: const RadialGradient(
                center: Alignment.topRight,
                radius: 1.4,
                colors: [MkColors.purple500, MkColors.purple900],
              ),
              boxShadow: MkShadow.lifted,
            ),
            child: Column(
              children: [
                const MkFloat(child: MkCoin(size: 56)),
                const SizedBox(height: MkSpace.sm),
                Text(s.tr('نقاط مكافأة', 'Mukafaah Points'), style: t.labelLarge?.copyWith(color: const Color(0xFFD8CCE6))),
                Text(
                  formatPoints(d.balance),
                  style: t.displaySmall?.copyWith(color: MkColors.yellow500, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  s.tr(
                    'بتسوى ${formatMinor(d.balance, 'USD')} بمحلات أصدقاء مكافأة',
                    'Worth ${formatMinor(d.balance, 'USD')} at Mukafaah Friends shops',
                  ),
                  textAlign: TextAlign.center,
                  style: t.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: MkSpace.lg),
        MkSectionHeader(title: s.tr('كيف بتربحها', 'How to earn them')),
        MkCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (final (i, r) in d.rules.indexed)
                MkEntrance(
                  index: i,
                  child: ListTile(
                    leading: _Dot(done: done.contains(r.code) && r.code != 'REFERRAL', icon: _ruleIcon(r.code)),
                    title: Text(r.title, style: t.titleSmall),
                    trailing: Text('+${formatPoints(r.points)}', style: t.titleSmall?.copyWith(color: MkColors.purple700, fontWeight: FontWeight.w800)),
                  ),
                ),
              ListTile(
                leading: const _Dot(done: false, icon: Icons.workspace_premium_rounded),
                title: Text(s.tr('وصّل لمستوى أعلى', 'Reach a higher tier'), style: t.titleSmall),
                subtitle: Text(s.tr('كل مستوى إلو مكافأة', 'Each tier has a bonus'), style: t.labelSmall?.copyWith(color: MkColors.ink3)),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/tier'),
              ),
            ],
          ),
        ),
        const SizedBox(height: MkSpace.lg),
        MkSectionHeader(title: s.tr('وين بتصرفها', 'Where to spend them')),
        if (d.friends.isEmpty)
          MkCard(child: Text(s.tr('ما في محلات بعد.', 'No Friends shops yet.'), style: t.bodyMedium?.copyWith(color: MkColors.ink3)))
        else
          for (final (i, f) in d.friends.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: MkSpace.xs),
              child: MkEntrance(
                index: i,
                child: MkCard(
                  onTap: () => context.push('/shop/${f.id}'),
                  padding: const EdgeInsets.all(MkSpace.sm),
                  child: Row(
                    children: [
                      SizedBox.square(
                        dimension: 44,
                        child: ClipRRect(
                          borderRadius: MkRadius.all(MkRadius.md),
                          child: MkNetImage(url: url(f.logoUrl), fallbackName: f.name, cacheWidth: 132),
                        ),
                      ),
                      const SizedBox(width: MkSpace.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                            Text(
                              s.tr('لحد ${formatPoints(f.maxPoints)} نقطة بكل فاتورة', 'Up to ${formatPoints(f.maxPoints)} points per bill'),
                              style: t.labelSmall?.copyWith(color: MkColors.ink3),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: MkColors.ink3),
                    ],
                  ),
                ),
              ),
            ),
        const SizedBox(height: MkSpace.lg),
        MkSectionHeader(title: s.tr('السجل', 'History')),
        MkCard(
          padding: EdgeInsets.zero,
          child: d.history.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(MkSpace.md),
                  child: Text(s.tr('ما في شي بعد.', 'Nothing yet.'), style: t.bodyMedium?.copyWith(color: MkColors.ink3)),
                )
              : Column(
                  children: [
                    for (final h in d.history)
                      ListTile(
                        leading: _Dot(done: h.points > 0, icon: h.points > 0 ? Icons.add_rounded : Icons.remove_rounded, minus: h.points < 0),
                        title: Text(h.title ?? h.type, style: t.titleSmall),
                        subtitle: Text(fmtDate(h.createdAt), style: t.labelSmall?.copyWith(color: MkColors.ink3)),
                        trailing: Text(
                          '${h.points > 0 ? '+' : '−'}${formatPoints(h.points.abs())}',
                          style: t.titleSmall?.copyWith(color: h.points > 0 ? MkColors.success : MkColors.danger, fontWeight: FontWeight.w800),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  static IconData _ruleIcon(String code) => switch (code) {
        'SIGNUP' => Icons.download_done_rounded,
        'REFERRAL' => Icons.group_add_rounded,
        'FIRST_BILL' => Icons.receipt_long_rounded,
        _ => Icons.bolt_rounded,
      };
}

class _Dot extends StatelessWidget {
  const _Dot({required this.done, required this.icon, this.minus = false});
  final bool done;
  final bool minus;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = minus
        ? (const Color(0xFFFCE9EB), MkColors.danger)
        : done
            ? (const Color(0xFFE5F6EE), MkColors.success)
            : (const Color(0xFFFFF6CC), MkColors.purple900);
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: bg, borderRadius: MkRadius.all(MkRadius.md)),
      child: Icon(done && !minus ? Icons.check_rounded : icon, size: 20, color: fg),
    );
  }
}
