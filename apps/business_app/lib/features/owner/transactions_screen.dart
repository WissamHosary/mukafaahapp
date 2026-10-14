import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import 'owner_shell.dart';

class TransactionsScreen extends ConsumerWidget {
  const TransactionsScreen({super.key});

  Future<void> _reverse(BuildContext context, WidgetRef ref, String txId) async {
    final s = ref.read(stringsProvider);
    final reason = TextEditingController();
    final ok = await showMkSheet<bool>(
      context,
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.reverse, style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: MkSpace.md),
          TextField(controller: reason, autofocus: true, decoration: InputDecoration(labelText: s.reverseReason)),
          const SizedBox(height: MkSpace.lg),
          MkButton(label: s.confirm, kind: MkButtonKind.danger, onPressed: () => Navigator.pop(ctx, true)),
        ],
      ),
    );
    if (ok != true || reason.text.trim().length < 3) return;
    try {
      await ref.read(apiProvider).reverse(txId, reason.text.trim());
      ref
        ..invalidate(ownerTxProvider)
        ..invalidate(dashboardProvider);
      if (context.mounted) MkToast.show(context, s.reversedOk, kind: MkToastKind.success);
    } on ApiException catch (e) {
      if (context.mounted) MkToast.show(context, s.error(e.code), kind: MkToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final list = ref.watch(ownerTxProvider);
    final currency = ref.watch(businessProvider).value?.currency ?? 'USD';
    return OwnerPage(
      title: s.transactions,
      onRefresh: () => ref.refresh(ownerTxProvider.future),
      child: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => MkErrorState(title: s.noConnection, retryLabel: s.retry, onRetry: () => ref.invalidate(ownerTxProvider)),
        data: (rows) => rows.isEmpty
            ? MkEmptyState(title: s.noData, icon: Icons.receipt_long_rounded)
            : ListView.separated(
                padding: const EdgeInsets.all(MkSpace.lg),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: MkSpace.xs),
                itemBuilder: (context, i) {
                  final r = rows[i];
                  final type = r['type'] as String;
                  final voided = r['voided'] == true;
                  final created = DateTime.parse(r['createdAt'] as String).toLocal();
                  final when =
                      '${created.day}/${created.month} ${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')}';
                  return MkCard(
                    child: Row(
                      children: [
                        MkIconTile(
                          icon: type == 'REDEEM'
                              ? Icons.redeem_rounded
                              : type == 'PREPOINT_EARN'
                                  ? Icons.card_giftcard_rounded
                                  : Icons.add_circle_rounded,
                          bg: voided ? MkColors.line : MkColors.purple50,
                        ),
                        const SizedBox(width: MkSpace.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${r['customer'] ?? ''}  ·  ${r['staffName'] ?? ''}',
                                style: t.titleSmall?.copyWith(decoration: voided ? TextDecoration.lineThrough : null),
                              ),
                              Text(
                                [r['branchName'], when, if (r['invoiceNo'] != null) '#${r['invoiceNo']}'].join(' · '),
                                style: t.bodySmall?.copyWith(color: MkColors.ink3),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${type == 'REDEEM' ? '-' : '+'}${formatPoints(r['points'] as num)}',
                              textDirection: TextDirection.ltr,
                              style: t.titleMedium,
                            ),
                            if ((r['billMinor'] as num) > 0)
                              Text(formatMinor((r['billMinor'] as num).toInt(), currency), style: t.bodySmall),
                          ],
                        ),
                        if (!voided)
                          IconButton(
                            tooltip: s.reverse,
                            onPressed: () => _reverse(context, ref, r['transactionId'] as String),
                            icon: const Icon(Icons.undo_rounded),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(s.reversed, style: t.labelSmall?.copyWith(color: MkColors.danger)),
                          ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
