import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../../data/api.dart';
import '../common/common.dart';

/// Membership tiers by total spend: the current tier, progress in dollars to the
/// next one, and every tier with its minimum spend, Mukafaah Points bonus and perks.
class TierScreen extends ConsumerWidget {
  const TierScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final data = ref.watch(tierProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.tierStatus),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: s.tr('كيف بتشتغل المستويات', 'How tiers work'),
            onPressed: () => showMkSheet<void>(
              context,
              builder: (ctx) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.tr('كيف بتشتغل المستويات', 'How tiers work'), style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: MkSpace.sm),
                  Text(_howText(s), style: Theme.of(ctx).textTheme.bodyLarge?.copyWith(color: MkColors.ink2)),
                ],
              ),
            ),
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: MkColors.purple900,
        onRefresh: () async {
          ref.invalidate(tierProvider);
          await ref.read(tierProvider.future);
        },
        child: data.when(
          data: (d) => _TierBody(d: d),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              const SizedBox(height: 120),
              MkErrorState(title: errorText(s, e), retryLabel: s.retry, onRetry: () => ref.invalidate(tierProvider)),
            ],
          ),
        ),
      ),
    );
  }
}

String _howText(S s) => s.tr(
      'مستواك بيطلع مع مجموع مشترياتك بمحلات مكافأة، وما بينزل لما تصرف نقاط. كل مستوى جديد بيعطيك مكافأة نقاط مكافأة لمرة وحدة، وميزات أكتر.',
      'Your tier grows with your total spend at Mukafaah shops and never drops when you use points. '
          'Every new tier gives you a one-time Mukafaah Points bonus and more perks.',
    );

Color _tierColor(TierLevel? l, String code) => mkHexColor(l?.color) ?? MkTierChip.colors(code).$1;

class _TierBody extends ConsumerWidget {
  const _TierBody({required this.d});

  final TierData d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final currentIndex = d.tiers.indexWhere((x) => x.code == d.tier);
    return ListView(
      padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.xs, MkSpace.lg, MkSpace.xxl),
      children: [
        MkEntrance(child: _TierHero(d: d)),
        if (d.tiers.isNotEmpty) ...[
          MkSectionHeader(title: s.tr('كل المستويات', 'All tiers')),
          for (var i = 0; i < d.tiers.length; i++)
            MkStagger(
              index: i + 1,
              child: _TierStep(
                level: d.tiers[i],
                reached: currentIndex >= 0 && i <= currentIndex,
                current: i == currentIndex,
                last: i == d.tiers.length - 1,
                nextReached: currentIndex >= 0 && i + 1 <= currentIndex,
              ),
            ),
        ],
        if (d.achievements.isNotEmpty) ...[
          MkSectionHeader(title: s.tr('الإنجازات', 'Achievements')),
          for (final a in d.achievements)
            Padding(
              padding: const EdgeInsets.only(bottom: MkSpace.xs),
              child: MkCard(
                child: Row(
                  children: [
                    MkIconTile(
                      icon: a.done ? Icons.emoji_events_rounded : Icons.lock_outline_rounded,
                      bg: a.done ? MkColors.yellow50 : MkColors.purple50,
                      color: a.done ? MkColors.warning : MkColors.ink3,
                    ),
                    const SizedBox(width: MkSpace.sm),
                    Expanded(child: Text(a.title, style: t.titleSmall)),
                    Text('${a.progress}/${a.goal}', style: t.labelMedium),
                  ],
                ),
              ),
            ),
        ],
        const SizedBox(height: MkSpace.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline_rounded, size: 18, color: MkColors.ink3),
            const SizedBox(width: MkSpace.xs),
            Expanded(child: Text(_howText(s), style: t.bodySmall?.copyWith(color: MkColors.ink3, height: 1.4))),
          ],
        ),
      ],
    );
  }
}

/// Dark hero card: medal in the tier colour, total spend counting up and an
/// animated bar in dollars to the next tier.
class _TierHero extends ConsumerWidget {
  const _TierHero({required this.d});

  final TierData d;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final cur = d.current;
    final next = d.next;
    final color = _tierColor(cur, d.tier);
    final nextColor = next == null ? color : _tierColor(next, next.code);
    const soft = Color(0xFFD8CCE6);
    return ClipRRect(
      borderRadius: MkRadius.all(MkRadius.xl),
      child: Container(
        decoration: const BoxDecoration(boxShadow: MkShadow.lifted),
        child: MkSwirlBackground(
          child: Padding(
            padding: const EdgeInsets.all(MkSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    MkFloat(
                      amplitude: 4,
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            center: const Alignment(-0.3, -0.4),
                            colors: [Color.lerp(color, Colors.white, 0.45) ?? color, color],
                          ),
                          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 22, offset: const Offset(0, 8))],
                        ),
                        child: Icon(Icons.workspace_premium_rounded, size: 34, color: mkOnColor(color)),
                      ),
                    ),
                    const SizedBox(width: MkSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.tr('مستواك الحالي', 'Your tier'), style: t.labelMedium?.copyWith(color: soft)),
                          Text(
                            tierName(s, cur?.name, d.tier),
                            style: t.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MkSpace.lg),
                Text(s.tr('مجموع مشترياتك', 'Total spent'), style: t.labelMedium?.copyWith(color: soft)),
                AnimatedPoints(
                  value: d.lifetimeSpendMinor,
                  format: money,
                  style: t.displaySmall?.copyWith(color: Colors.white, fontSize: 34),
                ),
                const SizedBox(height: MkSpace.md),
                ClipRRect(
                  borderRadius: MkRadius.all(MkRadius.pill),
                  child: SizedBox(
                    height: 10,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: d.progress),
                      duration: const Duration(milliseconds: 1200),
                      curve: MkMotion.enter,
                      builder: (context, v, _) => Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: Colors.white.withValues(alpha: 0.12)),
                          FractionallySizedBox(
                            alignment: AlignmentDirectional.centerStart,
                            widthFactor: v,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [MkColors.yellow500, nextColor]),
                                borderRadius: MkRadius.all(MkRadius.pill),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                if (next != null)
                  Row(
                    children: [
                      Text(money(d.currentMin), style: t.labelSmall?.copyWith(color: soft)),
                      const Spacer(),
                      Text(money(next.minSpendMinor), style: t.labelSmall?.copyWith(color: soft)),
                    ],
                  ),
                const SizedBox(height: MkSpace.sm),
                if (next == null)
                  Row(
                    children: [
                      const Icon(Icons.celebration_rounded, color: MkColors.yellow500, size: 20),
                      const SizedBox(width: MkSpace.xs),
                      Expanded(
                        child: Text(
                          s.tr('وصلت لأعلى مستوى. استمتع بكل الميزات!', "You've reached the top tier. Enjoy every perk!"),
                          style: t.bodyMedium?.copyWith(color: Colors.white),
                        ),
                      ),
                    ],
                  )
                else ...[
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: s.tr('اصرف ', 'Spend ')),
                        TextSpan(
                          text: money(d.toNextMinor),
                          style: const TextStyle(color: MkColors.yellow500, fontWeight: FontWeight.w800),
                        ),
                        TextSpan(text: s.tr(' كمان لتوصل ${tierName(s, next.name, next.code)}', ' more to reach ${tierName(s, next.name, next.code)}')),
                      ],
                    ),
                    style: t.bodyLarge?.copyWith(color: Colors.white),
                  ),
                  if (next.bonusPoints > 0) ...[
                    const SizedBox(height: MkSpace.xs),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Container(
                        padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 12, 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: MkRadius.all(MkRadius.pill),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const MkCoin(size: 22),
                            const SizedBox(width: 6),
                            Text(
                              s.tr(
                                'مكافأة +${formatPoints(next.bonusPoints)} نقطة مكافأة',
                                '+${formatPoints(next.bonusPoints)} Mukafaah Points bonus',
                              ),
                              style: t.labelMedium?.copyWith(color: MkColors.yellow500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One tier on the ladder: a node on a vertical line and a card with its details.
class _TierStep extends ConsumerWidget {
  const _TierStep({
    required this.level,
    required this.reached,
    required this.current,
    required this.last,
    required this.nextReached,
  });

  final TierLevel level;
  final bool reached;
  final bool current;
  final bool last;
  final bool nextReached;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final color = _tierColor(level, level.code);
    final deep = Color.lerp(color, MkColors.ink, 0.3) ?? color;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                const SizedBox(height: 14),
                _Node(color: color, reached: reached, current: current),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 3,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: nextReached ? color : MkColors.line,
                        borderRadius: MkRadius.all(MkRadius.pill),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: MkSpace.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: MkSpace.sm),
              child: Container(
                padding: const EdgeInsets.all(MkSpace.md),
                decoration: BoxDecoration(
                  color: current ? Color.lerp(color, Colors.white, 0.88) : MkColors.surface,
                  borderRadius: MkRadius.all(MkRadius.lg),
                  border: Border.all(color: current ? color : MkColors.line, width: current ? 1.6 : 1),
                  boxShadow: current
                      ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))]
                      : MkShadow.soft,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tierName(s, level.name, level.code),
                            style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: reached ? MkColors.ink : MkColors.ink2),
                          ),
                        ),
                        if (current)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(color: deep, borderRadius: MkRadius.all(MkRadius.pill)),
                            child: Text(s.tr('إنت هون', "You're here"), style: t.labelSmall?.copyWith(color: Colors.white)),
                          )
                        else if (reached)
                          const Icon(Icons.check_circle_rounded, color: MkColors.success, size: 20),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      level.minSpendMinor == 0
                          ? s.tr('أول مستوى، من أول فاتورة', 'Starting tier, from your first bill')
                          : s.tr(
                              'لما يوصل مجموع مشترياتك ${money(level.minSpendMinor)}',
                              'When your total spend reaches ${money(level.minSpendMinor)}',
                            ),
                      style: t.bodySmall?.copyWith(color: MkColors.ink3),
                    ),
                    if (level.bonusPoints > 0) ...[
                      const SizedBox(height: MkSpace.xs),
                      Row(
                        children: [
                          const MkCoin(size: 20),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              s.tr(
                                '+${formatPoints(level.bonusPoints)} نقطة مكافأة هدية',
                                '+${formatPoints(level.bonusPoints)} Mukafaah Points gift',
                              ),
                              style: t.labelMedium?.copyWith(color: MkColors.purple700, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (level.perks.isNotEmpty) ...[
                      const SizedBox(height: MkSpace.xs),
                      for (final p in level.perks)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                reached ? Icons.check_rounded : Icons.lock_outline_rounded,
                                size: 16,
                                color: reached ? deep : MkColors.ink3,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(p, style: t.bodySmall?.copyWith(color: reached ? MkColors.ink2 : MkColors.ink3)),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tier node: check when reached, a softly pulsing medal for the current tier, a lock ahead.
class _Node extends StatefulWidget {
  const _Node({required this.color, required this.reached, required this.current});

  final Color color;
  final bool reached;
  final bool current;

  @override
  State<_Node> createState() => _NodeState();
}

class _NodeState extends State<_Node> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.current && !MediaQuery.disableAnimationsOf(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    final core = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.reached ? c : MkColors.purple50,
        border: Border.all(color: widget.reached ? Colors.white : MkColors.line, width: 2),
        boxShadow: widget.reached ? [BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))] : null,
      ),
      child: Icon(
        widget.current
            ? Icons.workspace_premium_rounded
            : widget.reached
                ? Icons.check_rounded
                : Icons.lock_rounded,
        size: 16,
        color: widget.reached ? mkOnColor(c) : MkColors.ink3,
      ),
    );
    if (!widget.current) return SizedBox(width: 44, height: 44, child: Center(child: core));
    return SizedBox(
      width: 44,
      height: 44,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 30 + 14 * _c.value,
              height: 30 + 14 * _c.value,
              decoration: BoxDecoration(shape: BoxShape.circle, color: c.withValues(alpha: 0.35 * (1 - _c.value))),
            ),
            child!,
          ],
        ),
        child: core,
      ),
    );
  }
}
