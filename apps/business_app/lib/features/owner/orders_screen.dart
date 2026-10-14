import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../../data/api.dart';
import 'owner_shell.dart';
import 'owner_widgets.dart';

/// Store orders customers sent to the shop's WhatsApp. The owner confirms them
/// here (tracked stock goes down), marks them ready and completed, or cancels.
/// Payment happens at pickup or delivery, never in the app.
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});

  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  String _filter = 'OPEN';
  String? _busy;

  Future<void> _set(Json o, String status) async {
    final s = ref.read(stringsProvider);
    setState(() => _busy = o['id'] as String);
    try {
      await ref.read(apiProvider).setOrderStatus(o['id'] as String, status);
      ref
        ..invalidate(ordersProvider)
        ..invalidate(storeInfoProvider);
      if (mounted) MkToast.show(context, s.tr('تم التحديث وانبعت إشعار للزبون', 'Updated. The customer was notified.'), kind: MkToastKind.success);
    } on Object catch (e) {
      if (mounted) showApiError(context, s, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    String label(String st) => switch (st) {
          'NEW' => s.tr('جديد', 'New'),
          'CONFIRMED' => s.tr('مؤكد', 'Confirmed'),
          'READY' => s.tr('جاهز', 'Ready'),
          'COMPLETED' => s.tr('تم', 'Completed'),
          _ => s.tr('ملغى', 'Cancelled'),
        };
    Color color(String st) => switch (st) {
          'NEW' => MkColors.warning,
          'CONFIRMED' => MkColors.purple700,
          'READY' => MkColors.success,
          'COMPLETED' => MkColors.ink3,
          _ => MkColors.danger,
        };
    const open = {'NEW', 'CONFIRMED', 'READY'};
    return OwnerPage(
      title: s.tr('طلبات المتجر', 'Store orders'),
      onRefresh: () async => ref.invalidate(ordersProvider),
      child: ref.watch(ordersProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => MkErrorState(title: s.noConnection, retryLabel: s.retry, onRetry: () => ref.invalidate(ordersProvider)),
            data: (all) {
              final openCount = all.where((o) => open.contains(o['status'])).length;
              final list = all.where((o) => _filter == 'OPEN' ? open.contains(o['status']) : !open.contains(o['status'])).toList();
              return ListView(
                padding: const EdgeInsets.all(MkSpace.lg),
                children: [
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: 'OPEN', label: Text(s.tr('مفتوحة ($openCount)', 'Open ($openCount)'))),
                      ButtonSegment(value: 'DONE', label: Text(s.tr('منتهية', 'Done'))),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (v) => setState(() => _filter = v.first),
                  ),
                  const SizedBox(height: MkSpace.md),
                  if (list.isEmpty)
                    MkEmptyState(
                      icon: Icons.receipt_long_rounded,
                      title: s.tr('ما في طلبات هون', 'No orders here'),
                      message: s.tr('لما الزبون يبعت طلب من متجرك، بيبيّن هون وعالواتساب.', 'When a customer sends an order from your store, it shows here and on WhatsApp.'),
                    ),
                  for (final o in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: MkSpace.sm),
                      child: MkCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text('#${o['code'] ?? '—'} · ${o['customer'] ?? ''}', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: color(o['status'] as String).withValues(alpha: 0.12),
                                    borderRadius: MkRadius.all(MkRadius.pill),
                                  ),
                                  child: Text(label(o['status'] as String), style: t.labelSmall?.copyWith(color: color(o['status'] as String))),
                                ),
                              ],
                            ),
                            Text(
                              '${fmtDateTime(DateTime.parse(o['createdAt'] as String).toLocal())} · '
                              '${o['fulfilment'] == 'DELIVERY' ? s.tr('توصيل', 'Delivery') : s.tr('استلام', 'Pickup')}',
                              style: t.labelSmall?.copyWith(color: MkColors.ink3),
                            ),
                            if (o['address'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.location_on_rounded, size: 16, color: MkColors.purple700),
                                    const SizedBox(width: 4),
                                    Expanded(child: Text(o['address'] as String, style: t.bodySmall)),
                                  ],
                                ),
                              ),
                            if (o['contactPhone'] != null || o['customerPhone'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.call_rounded, size: 16, color: MkColors.purple700),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        [
                                          if (o['contactName'] != null) '${o['contactName']}',
                                          if (o['contactPhone'] != null) '${o['contactPhone']}',
                                          if (o['customerPhone'] != null) s.tr('موثّق: ${o['customerPhone']}', 'Verified: ${o['customerPhone']}'),
                                        ].join(' · '),
                                        style: t.bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            if (o['mapUrl'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(
                                  children: [
                                    const Icon(Icons.map_rounded, size: 16, color: MkColors.purple700),
                                    const SizedBox(width: 4),
                                    Expanded(child: SelectableText('${o['mapUrl']}', style: t.bodySmall?.copyWith(color: MkColors.purple700))),
                                  ],
                                ),
                              ),
                            const Divider(height: MkSpace.lg),
                            for (final it in ((o['items'] as List?) ?? const []).cast<Map<dynamic, dynamic>>())
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    Text('${it['qty']}×', style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: MkColors.purple700)),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(it['variant'] == null ? '${it['name']}' : '${it['name']} (${it['variant']})', style: t.bodyMedium)),
                                    Text(formatMinor(((it['priceMinor'] as num) * (it['qty'] as num)).toInt(), 'USD'), style: t.bodyMedium),
                                  ],
                                ),
                              ),
                            const Divider(height: MkSpace.lg),
                            Row(
                              children: [
                                Expanded(child: Text(s.tr('المجموع', 'Total'), style: t.titleSmall)),
                                Text(
                                  formatMinor((o['totalMinor'] as num).toInt(), 'USD'),
                                  style: t.titleMedium?.copyWith(color: MkColors.purple900, fontWeight: FontWeight.w800),
                                ),
                              ],
                            ),
                            if (o['note'] != null) ...[
                              const SizedBox(height: MkSpace.xs),
                              Text('“${o['note']}”', style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic, color: MkColors.ink2)),
                            ],
                            if (open.contains(o['status'])) ...[
                              const SizedBox(height: MkSpace.sm),
                              Row(
                                children: [
                                  Expanded(
                                    child: MkButton(
                                      label: s.tr('إلغاء', 'Cancel'),
                                      kind: MkButtonKind.ghost,
                                      onPressed: _busy != null ? null : () => _set(o, 'CANCELLED'),
                                    ),
                                  ),
                                  const SizedBox(width: MkSpace.sm),
                                  Expanded(
                                    flex: 2,
                                    child: MkButton(
                                      loading: _busy == o['id'],
                                      kind: MkButtonKind.accent,
                                      label: switch (o['status']) {
                                        'NEW' => s.tr('تأكيد الطلب', 'Confirm order'),
                                        'CONFIRMED' => s.tr('جاهز', 'Mark ready'),
                                        _ => s.tr('تم التسليم', 'Mark completed'),
                                      },
                                      onPressed: _busy != null
                                          ? null
                                          : () => _set(
                                                o,
                                                switch (o['status']) {
                                                  'NEW' => 'CONFIRMED',
                                                  'CONFIRMED' => 'READY',
                                                  _ => 'COMPLETED',
                                                },
                                              ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
    );
  }
}
