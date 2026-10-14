import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../../data/api.dart';
import '../common/common.dart';

/// Watches for spends a cashier started (points, offers, rewards, Mukafaah
/// Points) and asks the customer to approve them. Points only leave the wallet
/// after the customer taps Approve, so a copied QR can't be used to spend them.
class RedeemApprovalsHost extends ConsumerStatefulWidget {
  const RedeemApprovalsHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<RedeemApprovalsHost> createState() => _RedeemApprovalsHostState();
}

class _RedeemApprovalsHostState extends ConsumerState<RedeemApprovalsHost> with WidgetsBindingObserver {
  static const _every = Duration(seconds: 5);
  Timer? _timer;
  bool _busy = false;
  String? _showing;
  final _seen = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(_every, (_) => _check());
    unawaited(_check());
  }

  Future<void> _check() async {
    if (_busy || _showing != null || !mounted) return;
    _busy = true;
    try {
      final list = await ref.read(apiProvider).pendingRedeemRequests();
      final next = list.where((r) => !_seen.contains(r.id) && r.expiresAt.isAfter(DateTime.now())).firstOrNull;
      if (next != null && mounted) await _show(next);
    } catch (_) {
      // Offline or signed out: try again on the next tick.
    } finally {
      _busy = false;
    }
  }

  Future<void> _show(RedeemRequest r) async {
    _seen.add(r.id);
    _showing = r.id;
    unawaited(HapticFeedback.mediumImpact());
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => _ApprovalSheet(request: r),
    );
    _showing = null;
    if (!mounted) return;
    final s = ref.read(stringsProvider);
    switch (result) {
      case 'APPROVED':
        MkToast.show(context, s.tr('تمّت الموافقة. تهنّى!', 'Approved. Enjoy!'), kind: MkToastKind.success);
      case 'DECLINED':
        MkToast.show(context, s.tr('رفضت. ما انصرفت ولا نقطة.', 'Declined. No points were used.'));
      case 'EXPIRED':
        MkToast.show(context, s.tr('انتهى وقت الطلب.', 'This request expired.'), kind: MkToastKind.error);
      case final String err when err.startsWith('FAILED'):
        MkToast.show(context, s.tr('ما زبط الصرف. جرّب مرة تانية.', 'Could not redeem. Please try again.'), kind: MkToastKind.error);
    }
    ref
      ..invalidate(walletProvider)
      ..invalidate(homeProvider)
      ..invalidate(mukafaahProvider)
      ..invalidate(transactionsProvider);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// "Cedar Cafe wants to redeem 250 points": shop, what it is, a countdown ring,
/// and Approve / Decline.
class _ApprovalSheet extends ConsumerStatefulWidget {
  const _ApprovalSheet({required this.request});
  final RedeemRequest request;

  @override
  ConsumerState<_ApprovalSheet> createState() => _ApprovalSheetState();
}

class _ApprovalSheetState extends ConsumerState<_ApprovalSheet> {
  late Timer _tick;
  late final int _total = widget.request.expiresAt.difference(DateTime.now()).inSeconds.clamp(1, 600);
  int _left = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _left = _secondsLeft();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left = _secondsLeft());
      if (_left <= 0) {
        _tick.cancel();
        Navigator.of(context).pop('EXPIRED');
      }
    });
  }

  int _secondsLeft() => widget.request.expiresAt.difference(DateTime.now()).inSeconds.clamp(0, 600);

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  Future<void> _decide(bool approve) async {
    setState(() => _busy = true);
    final api = ref.read(apiProvider);
    try {
      if (approve) {
        final r = await api.approveRedeem(widget.request.id);
        if (!mounted) return;
        Navigator.of(context).pop(r.status == 'APPROVED' ? 'APPROVED' : r.status == 'EXPIRED' ? 'EXPIRED' : 'FAILED:${r.error ?? ''}');
      } else {
        await api.declineRedeem(widget.request.id);
        if (!mounted) return;
        Navigator.of(context).pop('DECLINED');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      MkToast.show(context, errorText(ref.read(stringsProvider), e), kind: MkToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final r = widget.request;
    final what = switch (r.kind) {
      'REWARD' => s.tr('مكافأة', 'Reward'),
      'OFFER' || 'BOOKING' => s.tr('عرض', 'Offer'),
      'MUKAFAAH' => s.tr('خصم بنقاط مكافأة', 'Discount with Mukafaah Points'),
      _ => s.tr('خصم على فاتورتك', 'Discount on your bill'),
    };
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(MkSpace.sm),
        padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.sm, MkSpace.lg, MkSpace.lg),
        decoration: BoxDecoration(color: Colors.white, borderRadius: MkRadius.all(MkRadius.xl), boxShadow: MkShadow.lifted),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: MkColors.line, borderRadius: MkRadius.all(MkRadius.pill))),
            const SizedBox(height: MkSpace.md),
            Row(
              children: [
                SizedBox.square(
                  dimension: 52,
                  child: ClipRRect(
                    borderRadius: MkRadius.all(MkRadius.md),
                    child: MkNetImage(url: url(r.shopLogoUrl), fallbackName: r.shopName, cacheWidth: 156),
                  ),
                ),
                const SizedBox(width: MkSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.shopName, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      Text(
                        r.kind == 'MUKAFAAH'
                            ? s.tr('بدّو يصرف من نقاط مكافأة تبعك', 'wants to use your Mukafaah Points')
                            : s.tr('بدّو يصرف من نقاطك', 'wants to redeem your points'),
                        style: t.bodySmall?.copyWith(color: MkColors.ink3),
                      ),
                    ],
                  ),
                ),
                _Countdown(left: _left, total: _total),
              ],
            ),
            const SizedBox(height: MkSpace.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(MkSpace.md),
              decoration: BoxDecoration(color: MkColors.purple50, borderRadius: MkRadius.all(MkRadius.lg)),
              child: Column(
                children: [
                  Text(what, style: t.labelMedium?.copyWith(color: MkColors.ink3)),
                  const SizedBox(height: 2),
                  Text(r.title, textAlign: TextAlign.center, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: MkSpace.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(color: MkColors.yellow500, borderRadius: MkRadius.all(MkRadius.pill)),
                    child: Text(
                      '${formatPoints(r.points)} ${s.tr('نقطة', 'points')}${r.valueMinor > 0 ? ' · ${formatMinor(r.valueMinor, 'USD')}' : ''}',
                      style: t.labelLarge?.copyWith(color: MkColors.purple900, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: MkSpace.md),
            Row(
              children: [
                Expanded(
                  child: MkButton(
                    label: s.tr('رفض', 'Decline'),
                    kind: MkButtonKind.secondary,
                    onPressed: _busy ? null : () => _decide(false),
                  ),
                ),
                const SizedBox(width: MkSpace.sm),
                Expanded(
                  child: MkButton(
                    label: s.tr('موافق', 'Approve'),
                    kind: MkButtonKind.accent,
                    icon: Icons.check_rounded,
                    loading: _busy,
                    onPressed: _busy ? null : () => _decide(true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: MkSpace.xs),
            Text(
              s.tr('وافق بس إذا إنت هلّق بـ ${r.shopName}.', 'Only approve if you are at ${r.shopName} right now.'),
              textAlign: TextAlign.center,
              style: t.labelSmall?.copyWith(color: MkColors.ink3),
            ),
          ],
        ),
      ),
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.left, required this.total});
  final int left;
  final int total;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 46,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(end: total == 0 ? 0 : left / total),
            duration: const Duration(milliseconds: 900),
            builder: (context, v, _) => CircularProgressIndicator(
              value: v,
              strokeWidth: 3.5,
              color: MkColors.purple500,
              backgroundColor: MkColors.purple100,
            ),
          ),
          Text('${left}s', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
