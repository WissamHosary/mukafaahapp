import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';

/// The cashier's own transactions only. No business totals here by design.
class ShiftScreen extends ConsumerWidget {
  const ShiftScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final list = ref.watch(shiftProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.myShift)),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => MkErrorState(title: s.noConnection, retryLabel: s.retry, onRetry: () => ref.invalidate(shiftProvider)),
        data: (rows) => rows.isEmpty
            ? MkEmptyState(title: s.noData, icon: Icons.history_rounded)
            : ListView.separated(
                padding: const EdgeInsets.all(MkSpace.lg),
                itemCount: rows.length,
                separatorBuilder: (_, _) => const SizedBox(height: MkSpace.xs),
                itemBuilder: (context, i) {
                  final r = rows[i];
                  final d = DateTime.parse(r['createdAt'] as String).toLocal();
                  final redeem = r['type'] == 'REDEEM';
                  final voided = r['voided'] == true;
                  return MkCard(
                    child: Row(
                      children: [
                        MkIconTile(icon: redeem ? Icons.redeem_rounded : Icons.add_circle_rounded, size: 40),
                        const SizedBox(width: MkSpace.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${maskPhone(r['phoneLast4'] as String?)}  ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
                                textDirection: TextDirection.ltr,
                                style: t.titleSmall?.copyWith(decoration: voided ? TextDecoration.lineThrough : null),
                              ),
                              if ((r['billMinor'] as num) > 0)
                                Text(formatMinor((r['billMinor'] as num).toInt(), r['currency'] as String), style: t.bodySmall),
                            ],
                          ),
                        ),
                        Text('${redeem ? '-' : '+'}${formatPoints(r['points'] as num)}', style: t.titleMedium),
                        if (r['canVoid'] == true)
                          TextButton(
                            onPressed: () async {
                              try {
                                await ref.read(apiProvider).voidTx(r['transactionId'] as String);
                                ref.invalidate(shiftProvider);
                              } on ApiException catch (e) {
                                if (context.mounted) MkToast.show(context, s.error(e.code), kind: MkToastKind.error);
                              }
                            },
                            child: Text(s.voidTx, style: const TextStyle(color: MkColors.danger)),
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
