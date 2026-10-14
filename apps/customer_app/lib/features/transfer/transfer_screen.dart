import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../common/common.dart';

/// Send points from one shop balance to another Mukafaah member.
class TransferScreen extends ConsumerStatefulWidget {
  const TransferScreen({super.key});

  @override
  ConsumerState<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends ConsumerState<TransferScreen> {
  final _to = TextEditingController();
  final _points = TextEditingController();
  final _note = TextEditingController();
  String? _programId;
  ({String? name, String last4})? _recipient;
  String? _recipientError;
  Timer? _debounce;
  bool _busy = false;
  final String _key = newUuid();
  int? _sent;

  @override
  void dispose() {
    _debounce?.cancel();
    _to.dispose();
    _points.dispose();
    _note.dispose();
    super.dispose();
  }

  void _lookup(String v) {
    _debounce?.cancel();
    setState(() {
      _recipient = null;
      _recipientError = null;
    });
    if (v.trim().length < 5) return;
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final s = ref.read(stringsProvider);
      try {
        final r = await ref.read(apiProvider).recipient(v.trim());
        if (mounted && _to.text == v) setState(() => _recipient = r);
      } on ApiException catch (e) {
        if (mounted && _to.text == v) setState(() => _recipientError = s.errorV2(e.code));
      }
    });
  }

  Future<void> _send() async {
    final s = ref.read(stringsProvider);
    final pts = int.tryParse(_points.text.trim()) ?? 0;
    if (_programId == null || pts <= 0 || _recipient == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.transferPoints),
        content: Text(
          s.tr(
            'رح تبعت ${formatPoints(pts)} نقطة لـ ${_recipient!.name ?? ''} (•••• ${_recipient!.last4}). ما فيك ترجعهم.',
            "You'll send ${formatPoints(pts)} points to ${_recipient!.name ?? ''} (•••• ${_recipient!.last4}). This can't be undone.",
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.confirm)),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).transfer(to: _to.text.trim(), programId: _programId!, points: pts, note: _note.text.trim(), key: _key);
      refreshBalances(ref);
      HapticFeedback.mediumImpact();
      setState(() => _sent = pts);
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
    final wallet = ref.watch(walletProvider);
    final programs = (wallet.value?.programs ?? const []).where((p) => p.balance > 0).toList();
    final selected = programs.where((p) => p.programId == _programId).firstOrNull;
    final pts = int.tryParse(_points.text.trim()) ?? 0;
    final valid = selected != null && _recipient != null && pts >= 10 && pts <= selected.balance;

    if (_sent != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Padding(
          padding: const EdgeInsets.all(MkSpace.xl),
          child: Center(
            child: MkSuccessView(
              title: s.tr('انبعتوا ${formatPoints(_sent!)} نقطة', '${formatPoints(_sent!)} points sent'),
              subtitle: _recipient?.name,
              action: s.done,
              onAction: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(s.transferPoints), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(MkSpace.lg),
        children: [
          Text(s.tr('من أي رصيد؟', 'From which balance?'), style: t.titleMedium),
          const SizedBox(height: MkSpace.xs),
          if (wallet.isLoading) const LinearProgressIndicator(),
          if (!wallet.isLoading && programs.isEmpty)
            MkCard(child: Text(s.tr('ما عندك نقاط تبعتها لهلق.', "You don't have points to send yet."))),
          for (final p in programs)
            Padding(
              padding: const EdgeInsets.only(bottom: MkSpace.xs),
              child: MkCard(
                color: p.programId == _programId ? MkColors.purple50 : null,
                onTap: () => setState(() => _programId = p.programId),
                child: Row(
                  children: [
                    MkMonogram(name: p.name, size: 40),
                    const SizedBox(width: MkSpace.sm),
                    Expanded(child: Text(p.name, style: t.titleSmall)),
                    Text(formatPoints(p.balance), style: t.titleMedium?.copyWith(color: MkColors.purple700)),
                    const SizedBox(width: MkSpace.xs),
                    Icon(
                      p.programId == _programId ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                      color: MkColors.purple700,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: MkSpace.md),
          Text(s.tr('لمين؟', 'To whom?'), style: t.titleMedium),
          const SizedBox(height: MkSpace.xs),
          TextField(
            controller: _to,
            onChanged: _lookup,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: s.tr('رقم التلفون أو رمز الدعوة', 'Phone number or referral code'),
              prefixIcon: const Icon(Icons.person_search_rounded),
            ),
          ),
          const SizedBox(height: MkSpace.xs),
          if (_recipient != null)
            Row(
              children: [
                const Icon(Icons.verified_rounded, color: MkColors.success, size: 18),
                const SizedBox(width: 4),
                Text('${_recipient!.name ?? ''}  •••• ${_recipient!.last4}', style: t.bodyMedium?.copyWith(color: MkColors.success)),
              ],
            ),
          if (_recipientError != null) Text(_recipientError!, style: t.bodySmall?.copyWith(color: MkColors.danger)),
          const SizedBox(height: MkSpace.md),
          Text(s.tr('كم نقطة؟', 'How many points?'), style: t.titleMedium),
          const SizedBox(height: MkSpace.xs),
          TextField(
            controller: _points,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '100',
              suffixText: s.points,
              helperText: selected == null ? null : s.tr('متوفر: ${formatPoints(selected.balance)}', 'Available: ${formatPoints(selected.balance)}'),
            ),
          ),
          const SizedBox(height: MkSpace.sm),
          TextField(
            controller: _note,
            maxLength: 120,
            decoration: InputDecoration(hintText: s.tr('رسالة (اختياري)', 'Message (optional)')),
          ),
          const SizedBox(height: MkSpace.md),
          MkButton(label: s.tr('ابعت النقاط', 'Send points'), icon: Icons.send_rounded, kind: MkButtonKind.accent, loading: _busy, onPressed: valid ? _send : null),
          const SizedBox(height: MkSpace.sm),
          Text(
            s.tr(
              'النقاط بتنصرف بنفس المحل. التحويل بيفتح من المستوى الذهبي. الحد اليومي ٢٠٬٠٠٠ نقطة.',
              'Points stay usable at the same shop. Sending unlocks at Gold. Daily limit 20,000 points.',
            ),
            textAlign: TextAlign.center,
            style: t.bodySmall?.copyWith(color: MkColors.ink3),
          ),
        ],
      ),
    );
  }
}

/// Keeps the shared helpers import used (formatting lives there).
String transferMoney(int minor) => money(minor);
