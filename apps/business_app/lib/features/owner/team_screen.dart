import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../../data/api.dart';
import 'owner_shell.dart';

class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final staff = ref.watch(staffListProvider);
    final devices = ref.watch(devicesProvider);
    final biz = ref.watch(businessProvider).value;
    return OwnerPage(
      title: s.team,
      onRefresh: () async {
        ref
          ..invalidate(staffListProvider)
          ..invalidate(devicesProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(MkSpace.lg),
        children: [
          MkSectionHeader(title: s.staff, action: s.addCashier, onAction: biz == null ? null : () => _addStaff(context, ref, biz)),
          staff.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => MkErrorState(title: s.noConnection, retryLabel: s.retry, onRetry: () => ref.invalidate(staffListProvider)),
            data: (list) => list.isEmpty
                ? MkCard(
                    child: Row(
                      children: [
                        const MkIconTile(icon: Icons.person_add_alt_1_rounded),
                        const SizedBox(width: MkSpace.sm),
                        Expanded(child: Text(s.addCashier, style: t.titleSmall)),
                        if (biz != null)
                          MkButton(label: s.addCashier, expand: false, onPressed: () => _addStaff(context, ref, biz)),
                      ],
                    ),
                  )
                : MkCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (final m in list)
                          ListTile(
                            leading: MkMonogram(name: m.name, size: 40),
                            title: Text(m.name),
                            subtitle: Text(
                              '${m.branchName} · ${s.maxPointsDay}: ${formatPoints(m.limits['maxPointsDay'] as num)}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!m.active) Text(s.revoke, style: t.labelSmall?.copyWith(color: MkColors.danger)),
                                const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                            onTap: () => _editLimits(context, ref, m),
                          ),
                      ],
                    ),
                  ),
          ),
          MkSectionHeader(title: s.devices, action: s.pairDevice, onAction: biz == null ? null : () => _pair(context, ref, biz)),
          devices.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
            data: (list) => MkCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  if (list.isEmpty)
                    ListTile(
                      leading: const MkIconTile(icon: Icons.point_of_sale_rounded),
                      title: Text(s.pairDevice),
                      onTap: biz == null ? null : () => _pair(context, ref, biz),
                    ),
                  for (final d in list)
                    ListTile(
                      leading: const MkIconTile(icon: Icons.point_of_sale_rounded),
                      title: Text(d['label'] as String),
                      subtitle: Text('${d['branch_name']} · ${d['status']}'),
                      trailing: d['status'] == 'ACTIVE'
                          ? TextButton(
                              onPressed: () async {
                                await ref.read(apiProvider).revokeDevice(d['id'] as String);
                                ref.invalidate(devicesProvider);
                              },
                              child: Text(s.revoke, style: const TextStyle(color: MkColors.danger)),
                            )
                          : null,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: MkSpace.xxl),
        ],
      ),
    );
  }

  Future<void> _addStaff(BuildContext context, WidgetRef ref, Business biz) async {
    final s = ref.read(stringsProvider);
    final name = TextEditingController();
    final pin = TextEditingController();
    var branchId = biz.branches.first.id;
    await showMkSheet<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.addCashier, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: MkSpace.md),
            TextField(controller: name, autofocus: true, decoration: InputDecoration(labelText: s.cashierName)),
            const SizedBox(height: MkSpace.sm),
            TextField(
              controller: pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              decoration: InputDecoration(labelText: s.pin),
            ),
            if (biz.branches.length > 1) ...[
              const SizedBox(height: MkSpace.sm),
              Wrap(
                spacing: 8,
                children: [
                  for (final b in biz.branches)
                    ChoiceChip(label: Text(b.name), selected: branchId == b.id, onSelected: (_) => setSt(() => branchId = b.id)),
                ],
              ),
            ],
            const SizedBox(height: MkSpace.lg),
            MkButton(
              label: s.save,
              onPressed: () async {
                try {
                  await ref.read(apiProvider).addStaff(name: name.text.trim(), branchId: branchId, pin: pin.text);
                  ref.invalidate(staffListProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                } on ApiException catch (e) {
                  if (ctx.mounted) MkToast.show(ctx, s.error(e.code), kind: MkToastKind.error);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editLimits(BuildContext context, WidgetRef ref, StaffMember m) async {
    final s = ref.read(stringsProvider);
    final l = m.limits;
    final maxBill = TextEditingController(text: ((l['maxBillMinor'] as num) ~/ 100).toString());
    final maxTx = TextEditingController(text: '${l['maxPointsTx']}');
    final maxDay = TextEditingController(text: '${l['maxPointsDay']}');
    final voidWin = TextEditingController(text: '${l['voidWindowMin']}');
    final newPin = TextEditingController();
    var canRedeem = l['canRedeem'] == true;
    var active = m.active;
    final digits = [FilteringTextInputFormatter.digitsOnly];
    await showMkSheet<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('${m.name} · ${s.limits}', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: MkSpace.md),
            for (final f in [(maxBill, s.maxBill), (maxTx, s.maxPointsTx), (maxDay, s.maxPointsDay), (voidWin, s.voidWindow)])
              Padding(
                padding: const EdgeInsets.only(bottom: MkSpace.sm),
                child: TextField(
                  controller: f.$1,
                  keyboardType: TextInputType.number,
                  inputFormatters: digits,
                  decoration: InputDecoration(labelText: f.$2),
                ),
              ),
            TextField(
              controller: newPin,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [...digits, LengthLimitingTextInputFormatter(6)],
              decoration: InputDecoration(labelText: s.pin),
            ),
            SwitchListTile(value: canRedeem, onChanged: (v) => setSt(() => canRedeem = v), title: Text(s.canRedeem)),
            SwitchListTile(value: active, onChanged: (v) => setSt(() => active = v), title: Text(s.active)),
            const SizedBox(height: MkSpace.md),
            MkButton(
              label: s.save,
              onPressed: () async {
                try {
                  await ref.read(apiProvider).patchStaff(m.id, {
                    'maxBillMinor': (int.tryParse(maxBill.text) ?? 0) * 100,
                    'maxPointsTx': int.tryParse(maxTx.text) ?? 0,
                    'maxPointsDay': int.tryParse(maxDay.text) ?? 0,
                    'voidWindowMin': int.tryParse(voidWin.text) ?? 0,
                    'canRedeem': canRedeem,
                    'active': active,
                    if (newPin.text.length >= 4) 'pin': newPin.text,
                  });
                  ref.invalidate(staffListProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                } on ApiException catch (e) {
                  if (ctx.mounted) MkToast.show(ctx, s.error(e.code), kind: MkToastKind.error);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pair(BuildContext context, WidgetRef ref, Business biz) async {
    final s = ref.read(stringsProvider);
    try {
      final r = await ref.read(apiProvider).pairingCode(biz.branches.first.id);
      if (!context.mounted) return;
      await showMkSheet<void>(
        context,
        builder: (ctx) {
          final t = Theme.of(ctx).textTheme;
          return Column(
            children: [
              const MkIconTile(icon: Icons.point_of_sale_rounded, size: 64, bg: MkColors.yellow50),
              const SizedBox(height: MkSpace.md),
              Text(s.pairingCodeTitle, style: t.titleLarge),
              const SizedBox(height: MkSpace.md),
              SelectableText(
                r.code,
                textDirection: TextDirection.ltr,
                style: t.displaySmall?.copyWith(letterSpacing: 6, color: MkColors.purple900),
              ),
              const SizedBox(height: MkSpace.sm),
              Text(s.pairingCodeBody(r.branchName), textAlign: TextAlign.center, style: t.bodyMedium),
              const SizedBox(height: MkSpace.lg),
              MkButton(
                label: s.done,
                onPressed: () {
                  ref.invalidate(devicesProvider);
                  Navigator.pop(ctx);
                },
              ),
            ],
          );
        },
      );
    } on ApiException catch (e) {
      if (context.mounted) MkToast.show(context, s.error(e.code), kind: MkToastKind.error);
    }
  }
}
