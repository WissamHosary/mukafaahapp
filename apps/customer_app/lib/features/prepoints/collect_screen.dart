import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';

/// Pre-Points: points a shop gave to this phone number before the customer
/// joined. One tap moves them into the wallet; the shop does not approve again.
class CollectScreen extends ConsumerStatefulWidget {
  const CollectScreen({super.key});

  @override
  ConsumerState<CollectScreen> createState() => _CollectScreenState();
}

class _CollectScreenState extends ConsumerState<CollectScreen> {
  bool _busy = false;
  int? _collected;

  Future<void> _collect() async {
    final s = ref.read(stringsProvider);
    setState(() => _busy = true);
    try {
      final n = await ref.read(apiProvider).collectPrePoints();
      refreshBalances(ref);
      setState(() => _collected = n);
    } on ApiException catch (e) {
      if (mounted) MkToast.show(context, s.error(e.code), kind: MkToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final pre = ref.watch(prePointsProvider);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MkSpace.xl),
          child: _collected != null
              ? Center(
                  child: MkSuccessView(
                    title: s.collected(_collected!),
                    action: s.continueLabel,
                    onAction: () => context.go('/home'),
                  ),
                )
              : pre.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => MkErrorState(
                    title: s.noConnection,
                    retryLabel: s.retry,
                    onRetry: () => ref.invalidate(prePointsProvider),
                  ),
                  data: (p) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),
                      const MkEntrance(child: Center(child: MkFloat(child: MkCoin(size: 120)))),
                      const SizedBox(height: MkSpace.xxl),
                      MkEntrance(
                        index: 2,
                        child: Text(s.prePointsTitle, textAlign: TextAlign.center, style: t.headlineMedium),
                      ),
                      const SizedBox(height: MkSpace.sm),
                      MkEntrance(
                        index: 3,
                        child: Text(
                          s.prePointsBody(p.total),
                          textAlign: TextAlign.center,
                          style: t.bodyLarge?.copyWith(color: MkColors.ink2),
                        ),
                      ),
                      const SizedBox(height: MkSpace.lg),
                      MkEntrance(
                        index: 4,
                        child: Center(
                          child: AnimatedPoints(
                            value: p.total,
                            format: formatPoints,
                            style: t.displaySmall?.copyWith(color: MkColors.purple900),
                          ),
                        ),
                      ),
                      if (p.fromBusinesses.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: MkSpace.xs),
                          child: Text(
                            s.fromBusinesses(p.fromBusinesses.join('، ')),
                            textAlign: TextAlign.center,
                            style: t.bodyMedium?.copyWith(color: MkColors.ink3),
                          ),
                        ),
                      const Spacer(),
                      MkButton(
                        label: s.collect,
                        kind: MkButtonKind.accent,
                        icon: Icons.redeem_rounded,
                        loading: _busy,
                        onPressed: p.total > 0 ? _collect : null,
                      ),
                      const SizedBox(height: MkSpace.xs),
                      MkButton(label: s.close, kind: MkButtonKind.ghost, onPressed: () => context.go('/home')),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
