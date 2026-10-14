import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../../data/api.dart';
import 'owner_counter.dart';
import 'owner_shell.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final biz = ref.watch(businessProvider);
    final lang = ref.watch(localeProvider);
    return OwnerPage(
      title: s.settings,
      child: biz.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => MkErrorState(title: s.noConnection, retryLabel: s.retry, onRetry: () => ref.invalidate(businessProvider)),
        data: (b) => ListView(
          padding: const EdgeInsets.all(MkSpace.lg),
          children: [
            const MkEntrance(child: OffersEntryCard()),
            const SizedBox(height: MkSpace.sm),
            MkSectionHeader(title: s.tr('نسبة الولاء', 'Loyalty %')),
            _LoyaltyCard(b: b),
            MkSectionHeader(title: s.tr('المحل', 'Shop')),
            MkCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const MkIconTile(icon: Icons.insights_rounded, size: 40),
                    title: Text(s.tr('إحصائيات المحل', 'Shop stats')),
                    subtitle: Text(s.tr('الفواتير والنقاط اليوم وهالشهر', 'Bills and points today and this month')),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.go('/owner/dashboard'),
                  ),
                  ListTile(
                    leading: const MkIconTile(icon: Icons.local_offer_rounded, size: 40, bg: MkColors.yellow50),
                    title: Text(s.tr('العروض والخصومات', 'Offers & discounts')),
                    subtitle: Text(s.tr('اعمل عروض وخصومات ووقّفها وقت ما بدك', 'Create, pause and resume deals and discounts')),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.go('/owner/offers'),
                  ),
                  ListTile(
                    leading: const MkIconTile(icon: Icons.shopping_bag_rounded, size: 40),
                    title: Text(s.tr('طلبات المتجر', 'Store orders')),
                    subtitle: Text(s.tr('أكّد طلبات الواتساب', 'Confirm WhatsApp orders')),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.go('/owner/orders'),
                  ),
                  ListTile(
                    leading: const MkIconTile(icon: Icons.groups_rounded, size: 40),
                    title: Text(s.team),
                    subtitle: Text(s.tr('الكاشيرية وأجهزة الكاشير', 'Cashiers and counter devices')),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.go('/owner/team'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MkSpace.sm),
            MkCard(
              color: MkColors.purple50,
              child: Row(
                children: [
                  const Icon(Icons.support_agent_rounded, color: MkColors.purple700),
                  const SizedBox(width: MkSpace.sm),
                  Expanded(
                    child: Text(
                      s.tr(
                        'ملف المحل، الصور، المكافآت والمتجر بتديرهم مكافأة. احكينا لأي تعديل.',
                        'Your shop profile, photos, rewards and online store are managed by Mukafaah. Contact us for any change.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: MkColors.ink2),
                    ),
                  ),
                ],
              ),
            ),
            MkSectionHeader(title: s.programMemberships),
            MkCard(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final m in b.memberships) MkProgramBadge(type: m.type, label: '${s.programType(m.type)} · ${m.name}')],
              ),
            ),
            MkSectionHeader(title: s.branches, action: s.addBranch, onAction: () => _addBranch(context, ref)),
            MkCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final br in b.branches)
                    ListTile(leading: const MkIconTile(icon: Icons.storefront_rounded, size: 40), title: Text(br.name)),
                ],
              ),
            ),
            MkSectionHeader(title: s.language),
            MkCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (final l in ['ar', 'en'])
                    ListTile(
                      title: Text(l == 'ar' ? s.arabic : s.english),
                      trailing: lang == l ? const Icon(Icons.check_rounded, color: MkColors.purple900) : null,
                      onTap: () => ref.read(localeProvider.notifier).set(l),
                    ),
                ],
              ),
            ),
            const SizedBox(height: MkSpace.xl),
            MkButton(
              label: s.logout,
              kind: MkButtonKind.secondary,
              icon: Icons.logout_rounded,
              onPressed: () => ref.read(sessionProvider.notifier).ownerLogout(),
            ),
            const SizedBox(height: MkSpace.xs),
            MkButton(
              label: s.counterMode,
              kind: MkButtonKind.ghost,
              icon: Icons.swap_horiz_rounded,
              onPressed: () => ref.read(sessionProvider.notifier).switchMode(),
            ),
            const SizedBox(height: MkSpace.xxl),
          ],
        ),
      ),
    );
  }

  Future<void> _addBranch(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final name = TextEditingController();
    await showMkSheet<void>(
      context,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.addBranch, style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: MkSpace.md),
          TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: s.branchName)),
          const SizedBox(height: MkSpace.lg),
          MkButton(
            label: s.save,
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await ref.read(apiProvider).addBranch(name.text.trim());
              ref.invalidate(businessProvider);
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ],
      ),
    );
  }
}

/// The shop's loyalty %: points back on every bill. The owner sets it here.
class _LoyaltyCard extends ConsumerStatefulWidget {
  const _LoyaltyCard({required this.b});
  final Business b;

  @override
  ConsumerState<_LoyaltyCard> createState() => _LoyaltyCardState();
}

class _LoyaltyCardState extends ConsumerState<_LoyaltyCard> {
  late double _pct = (widget.b.redeemPointsPerUnit == 0 ? 0 : widget.b.earnPointsPerUnit * 100 / widget.b.redeemPointsPerUnit).roundToDouble().clamp(0.0, 100.0);
  late final double _max = _pct > 50 ? 100 : 50;
  bool _busy = false;

  Future<void> _save() async {
    final s = ref.read(stringsProvider);
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).setLoyaltyPercent(_pct.round());
      ref.invalidate(businessProvider);
      if (mounted) MkToast.show(context, s.tr('صار الزباين ياخدوا ${_pct.round()}% نقاط', 'Customers now get ${_pct.round()}% back in points'), kind: MkToastKind.success);
    } on ApiException catch (e) {
      if (mounted) MkToast.show(context, s.errorV2(e.code), kind: MkToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final p = _pct.round();
    return MkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(s.tr('النقاط المرتجعة من كل فاتورة', 'Points back on every bill'), style: t.bodyMedium)),
              Text('$p%', style: t.headlineMedium?.copyWith(color: MkColors.purple700, fontWeight: FontWeight.w800)),
            ],
          ),
          Slider(value: _pct, max: _max, divisions: _max.toInt(), label: '$p%', onChanged: (v) => setState(() => _pct = v)),
          Text(
            s.tr('مثال: فاتورة \$٢٠ ← ${formatPoints(20 * p)} نقطة (١٠٠ نقطة = \$١ خصم)', 'Example: a \$20 bill → ${formatPoints(20 * p)} points (100 points = \$1 off)'),
            style: t.bodySmall?.copyWith(color: MkColors.ink3),
          ),
          const SizedBox(height: MkSpace.md),
          MkButton(label: s.save, icon: Icons.check_rounded, kind: MkButtonKind.accent, loading: _busy, onPressed: _save),
        ],
      ),
    );
  }
}
