import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../alerts/alerts.dart';
import '../counter/counter_screen.dart';

/// Collect and Redeem on the owner's own phone (same counter as the cashiers),
/// under a slim bar with the Offers shortcut and the alerts bell.
class OwnerCounterScreen extends ConsumerWidget {
  const OwnerCounterScreen({required this.mode, super.key});
  final CounterMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final counter = ref.watch(ownerCounterProvider).when(
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(
            body: MkErrorState(
              title: s.noConnection,
              retryLabel: s.retry,
              onRetry: () => ref.invalidate(ownerCounterProvider),
            ),
          ),
          data: (_) => CounterScreen(key: ValueKey(mode), mode: mode, embedded: true),
        );
    return ColoredBox(
      color: MkColors.surface,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _OwnerCounterBar(mode: mode),
            Expanded(child: counter),
          ],
        ),
      ),
    );
  }
}

class _OwnerCounterBar extends ConsumerWidget {
  const _OwnerCounterBar({required this.mode});
  final CounterMode mode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final name = ref.watch(businessProvider).value?.name ?? '';
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(MkSpace.md, MkSpace.xs, MkSpace.xxs, MkSpace.xs),
      decoration: const BoxDecoration(
        color: MkColors.surface,
        border: Border(bottom: BorderSide(color: MkColors.line)),
      ),
      child: Row(
        children: [
          const MkLogo(height: 34, markOnly: true),
          const SizedBox(width: MkSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  mode == CounterMode.collect ? s.tr('جمع الفاتورة', 'Collect invoice') : s.tr('صرف النقاط', 'Redeem points'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (name.isNotEmpty)
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: MkColors.ink3)),
              ],
            ),
          ),
          const OffersPill(),
          const AlertsBell(owner: true),
        ],
      ),
    );
  }
}

/// Bright yellow "Offers" shortcut for the owner's counter bar.
class OffersPill extends ConsumerWidget {
  const OffersPill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final compact = MediaQuery.sizeOf(context).width < 360;
    return Semantics(
      button: true,
      label: s.tr('العروض والخصومات', 'Offers & discounts'),
      child: MkPressable(
        onTap: () => context.go('/owner/offers'),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [MkColors.yellow500, MkColors.yellow600]),
            borderRadius: MkRadius.all(MkRadius.pill),
            boxShadow: MkShadow.glow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_offer_rounded, size: 18, color: MkColors.purple900),
              if (!compact) ...[
                const SizedBox(width: 6),
                Text(
                  s.tr('العروض', 'Offers'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(color: MkColors.purple900, fontWeight: FontWeight.w800),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Big entry card for Offers & discounts (top of the More tab).
class OffersEntryCard extends ConsumerWidget {
  const OffersEntryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final live = ref.watch(ownerOffersProvider).value?.where((o) => o['status'] == 'ACTIVE').length;
    return MkPressable(
      onTap: () => context.go('/owner/offers'),
      child: Container(
        padding: const EdgeInsets.all(MkSpace.lg),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [MkColors.purple900, MkColors.purple700],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: MkRadius.all(MkRadius.xl),
          boxShadow: MkShadow.lifted,
        ),
        child: Row(
          children: [
            const MkFloat(
              amplitude: 4,
              child: MkIconTile(icon: Icons.local_offer_rounded, size: 56, bg: MkColors.yellow500, color: MkColors.purple900),
            ),
            const SizedBox(width: MkSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.tr('العروض والخصومات', 'Offers & discounts'),
                    style: t.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    live == null
                        ? s.tr('اعمل عروض وخصومات بتظهر للزباين', 'Create deals and discounts customers see in the app')
                        : s.tr('$live عرض شغّال هلّق', '$live live right now'),
                    style: t.bodySmall?.copyWith(color: const Color(0xFFD8CCE6)),
                  ),
                ],
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(color: MkColors.yellow500, shape: BoxShape.circle),
              child: const Icon(Icons.arrow_forward_rounded, color: MkColors.purple900, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
