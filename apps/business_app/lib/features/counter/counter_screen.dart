import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/providers.dart';
import '../../data/api.dart';
import '../alerts/alerts.dart';

/// The counter, in two sections:
/// - Collect: scan or type the phone -> type the invoice amount (and number) -> give points.
/// - Redeem: scan the customer's QR -> see their points -> redeem points, a reward or an offer.
/// Keyboard-first; a USB/Bluetooth scanner "types" the QR payload followed by Enter.
/// [embedded] is the owner's own phone (inside the owner app, no cashier header).
enum CounterMode { collect, redeem }

class CounterScreen extends ConsumerStatefulWidget {
  const CounterScreen({this.mode, this.embedded = false, super.key});

  /// Fixed section; null shows a Collect / Redeem switch (cashier device).
  final CounterMode? mode;
  final bool embedded;

  @override
  ConsumerState<CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends ConsumerState<CounterScreen> {
  final _lookupCtl = TextEditingController();
  final _billCtl = TextEditingController();
  final _invoiceCtl = TextEditingController();
  late CounterMode _mode = widget.mode ?? CounterMode.collect;
  final _lookupFocus = FocusNode();
  final _billFocus = FocusNode();

  String? _phone;
  String? _qr;
  CustomerView? _customer;
  int? _previewPoints;
  bool _busy = false;
  String? _idemKey;
  Json? _result;
  Timer? _debounce;
  Timer? _resetTimer;

  // v0.7: spending points waits for the customer's approval on their phone.
  _Pending? _pending;
  Timer? _pollTimer;
  bool _polling = false;
  BusinessApi? _pendingApi;
  _Outcome? _failure;

  @override
  void dispose() {
    for (final c in [_lookupCtl, _billCtl, _invoiceCtl]) {
      c.dispose();
    }
    _lookupFocus.dispose();
    _billFocus.dispose();
    _debounce?.cancel();
    _resetTimer?.cancel();
    _pollTimer?.cancel();
    // Leaving the counter mid-approval: withdraw the request so it can't be approved later.
    final p = _pending;
    if (p != null) unawaited(_pendingApi?.cancelRedeemRequest(p.id).catchError((Object _) {}));
    super.dispose();
  }

  S get s => ref.read(stringsProvider);

  /// Counter copy for QR errors: the member QR is fixed now, so never ask for a "fresh" one.
  String _err(String code) => switch (code) {
        'QR_EXPIRED' || 'QR_ALREADY_USED' => s.tr('اطلب من الزبون يورجيك رمزه', 'Ask the customer to show their QR'),
        'NOT_A_FRIEND' => s.tr('محلّك مش من أصدقاء مكافأة بعد', 'Your shop is not a Mukafaah Friend yet'),
        'OVER_LIMIT' => s.tr('أكتر من الحد المسموح لكل فاتورة', 'More than the limit per bill'),
        'INSUFFICIENT_POINTS' || 'INSUFFICIENT_BALANCE' => s.tr('نقاط الزبون ما بتكفي', "The customer doesn't have enough points"),
        _ => s.errorV2(code),
      };

  void _reset() {
    _resetTimer?.cancel();
    _stopPending();
    setState(() {
      _phone = null;
      _qr = null;
      _customer = null;
      _previewPoints = null;
      _idemKey = null;
      _result = null;
      _failure = null;
      _lookupCtl.clear();
      _billCtl.clear();
      _invoiceCtl.clear();
    });
    _lookupFocus.requestFocus();
  }

  void _toastError(ApiException e) {
    // The owner's counter session lasts 12 hours; open a fresh one when it ends.
    if (widget.embedded && e.status == 401) ref.invalidate(ownerCounterProvider);
    MkToast.show(context, _err(e.code), kind: MkToastKind.error);
  }

  static final _qrPattern = RegExp(r'^MKF\d+:');

  Future<void> _lookup(String raw) async {
    final v = raw.trim();
    if (v.isEmpty || _busy) return;
    // MKF2: fixed member QR (v0.7); MKF1: older rotating tokens still work.
    final isQr = _qrPattern.hasMatch(v);
    setState(() => _busy = true);
    try {
      final c = await ref.read(apiProvider).lookup(phone: isQr ? null : v, qr: isQr ? v : null);
      setState(() {
        _customer = c;
        _qr = isQr ? v : null;
        _phone = isQr ? null : v;
        _idemKey = newUuid();
      });
      if (_mode == CounterMode.collect) _billFocus.requestFocus();
    } on ApiException catch (e) {
      _toastError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Reloads balances for the customer on screen (after a declined or failed request).
  Future<void> _refreshCustomer() async {
    if (_qr == null && _phone == null) return;
    try {
      final c = await ref.read(apiProvider).lookup(phone: _phone, qr: _qr);
      if (mounted && _customer != null) setState(() => _customer = c);
    } on ApiException {
      // keep what is on screen
    }
  }

  void _onBillChanged(String v) {
    _debounce?.cancel();
    final minor = parseToMinor(v);
    _idemKey = newUuid(); // a different amount is a different request
    if (minor == null || minor == 0) {
      setState(() => _previewPoints = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      try {
        final p = await ref.read(apiProvider).preview(minor);
        if (mounted && parseToMinor(_billCtl.text) == minor) setState(() => _previewPoints = p);
      } on ApiException {
        // preview is informational; the earn call is authoritative
      }
    });
  }

  Future<void> _earn() async {
    final minor = parseToMinor(_billCtl.text);
    if (_customer == null || minor == null || minor == 0 || _busy) return;
    setState(() => _busy = true);
    try {
      final r = await ref.read(apiProvider).earn(
            phone: _phone,
            qr: _qr,
            billMinor: minor,
            idempotencyKey: _idemKey ??= newUuid(),
            invoiceNo: _invoiceCtl.text,
          );
      _showSuccess(r);
    } on ApiException catch (e) {
      _toastError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------- results & approvals
  void _showSuccess(Json view) {
    HapticFeedback.mediumImpact();
    ref.invalidate(shiftProvider);
    _resetTimer?.cancel();
    setState(() {
      _result = view;
      _failure = null;
    });
    _resetTimer = Timer(Duration(seconds: view['approved'] == true ? 8 : 6), () {
      if (mounted) _reset();
    });
  }

  /// Every spend call ends here: 200 = done now (free), 202 = wait for the customer.
  void _handleSpend(Json r, {required String title, required int points, required Json Function(Json result) success}) {
    if (!isApprovalPending(r)) {
      _showSuccess(success(r));
      return;
    }
    final now = DateTime.now();
    final exp = DateTime.tryParse((r['expiresAt'] as String?) ?? '')?.toLocal();
    // Device clocks drift; fall back to the server's 2 minutes when the time looks off.
    final sane = exp != null && exp.isAfter(now) && exp.difference(now) <= const Duration(minutes: 3);
    _pendingApi = ref.read(apiProvider);
    HapticFeedback.selectionClick();
    setState(() {
      _failure = null;
      _pending = _Pending(
        id: '${r['requestId']}',
        title: (r['title'] as String?) ?? title,
        points: (r['points'] as num?)?.toInt() ?? points,
        startedAt: now,
        expiresAt: sane ? exp! : now.add(const Duration(seconds: 120)),
        success: success,
      );
    });
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollPending());
  }

  void _stopPending() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _pending = null;
    _pendingApi = null;
  }

  void _fail(_Outcome o) {
    HapticFeedback.heavyImpact();
    setState(() => _failure = o);
    unawaited(_refreshCustomer());
  }

  _Outcome _outcomeFor(String status, String? error) => switch (status) {
        'DECLINED' => _Outcome(
            icon: Icons.do_not_disturb_on_rounded,
            color: MkColors.danger,
            title: s.tr('الزبون رفض الطلب', 'The customer declined'),
            message: s.tr('ما انخصم شي من نقاطه.', 'No points were taken.'),
          ),
        'EXPIRED' => _Outcome(
            icon: Icons.timer_off_rounded,
            color: MkColors.warning,
            title: s.tr('انتهى الوقت', 'The request expired'),
            message: s.tr('الزبون ما وافق خلال دقيقتين. فيك تبعت الطلب من جديد.', "The customer didn't approve within 2 minutes. You can send it again."),
          ),
        _ => _Outcome(
            icon: Icons.error_rounded,
            color: MkColors.danger,
            title: s.tr('ما زبط الصرف', "The redeem didn't go through"),
            message: error == null || error.isEmpty ? s.somethingWrong : _err(error),
          ),
      };

  Future<void> _pollPending() async {
    final p = _pending;
    if (p == null || _polling || !mounted) return;
    _polling = true;
    try {
      final r = await ref.read(apiProvider).redeemRequest(p.id);
      if (!mounted || _pending?.id != p.id) return;
      final status = (r['status'] as String?) ?? 'PENDING';
      final error = r['error'] as String?;
      switch (status) {
        case 'PENDING':
          return;
        case 'APPROVED':
          _stopPending();
          _showSuccess({...p.success((r['result'] as Json?) ?? const {}), 'approved': true});
        case 'DECLINED' when error == 'CANCELLED':
          _stopPending();
          setState(() {});
        default:
          _stopPending();
          _fail(_outcomeFor(status, error));
      }
    } on ApiException {
      // Network blips: keep polling until the server answers.
    } finally {
      _polling = false;
    }
  }

  Future<void> _cancelPending() async {
    final p = _pending;
    if (p == null) return;
    _stopPending();
    setState(() {});
    final api = ref.read(apiProvider);
    try {
      await api.cancelRedeemRequest(p.id);
      if (mounted) MkToast.show(context, s.tr('انلغى الطلب', 'Request cancelled'));
    } on ApiException {
      // Too late to cancel? The customer may have just approved: check before saying anything.
      try {
        final r = await api.redeemRequest(p.id);
        if (!mounted) return;
        if (r['status'] == 'APPROVED') {
          _showSuccess({...p.success((r['result'] as Json?) ?? const {}), 'approved': true});
        } else {
          MkToast.show(context, s.tr('انلغى الطلب', 'Request cancelled'));
        }
      } on ApiException catch (e) {
        if (mounted) _toastError(e);
      }
    }
  }

  // ---------------------------------------------------------------- redeem flows
  Future<void> _redeem() async {
    final c = _customer;
    final qr = _qr;
    if (c == null || qr == null) return;
    final eligible = c.programs.where((p) => p['canRedeemHere'] == true && (p['balance'] as num) > 0).toList();
    if (eligible.isEmpty) return;
    var program = eligible.first;
    final pts = TextEditingController();
    final key = newUuid();
    final ok = await showMkSheet<bool>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final t = Theme.of(ctx).textTheme;
          final n = int.tryParse(pts.text) ?? 0;
          final per = (program['pointsPerUnitDiscount'] as num).toInt();
          final discount = per == 0 ? 0 : (n * 100) ~/ per;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.redeem, style: t.titleLarge),
              const SizedBox(height: MkSpace.md),
              if (eligible.length > 1)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final p in eligible)
                      ChoiceChip(
                        label: Text('${s.programType(p['type'] as String)} · ${formatPoints(p['balance'] as num)}'),
                        selected: identical(program, p),
                        onSelected: (_) => setSt(() => program = p),
                      ),
                  ],
                ),
              const SizedBox(height: MkSpace.sm),
              Text('${s.balanceHere}: ${formatPoints(program['balance'] as num)} ${s.points}', style: t.bodyMedium),
              const SizedBox(height: MkSpace.sm),
              TextField(
                controller: pts,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(labelText: s.pointsToRedeem),
                onChanged: (_) => setSt(() {}),
                onSubmitted: (_) => Navigator.pop(ctx, true),
              ),
              const SizedBox(height: MkSpace.xs),
              if (n > 0) Text(s.discountValue(formatMinor(discount, 'USD')), style: t.titleMedium?.copyWith(color: MkColors.success)),
              const SizedBox(height: MkSpace.sm),
              _ApprovalNote(s: s),
              const SizedBox(height: MkSpace.lg),
              MkButton(
                label: s.tr('ابعت للزبون يوافق', 'Send to customer to approve'),
                icon: Icons.phonelink_ring_rounded,
                kind: MkButtonKind.accent,
                onPressed: n > 0 && n <= (program['balance'] as num) ? () => Navigator.pop(ctx, true) : null,
              ),
            ],
          );
        },
      ),
    );
    final n = int.tryParse(pts.text) ?? 0;
    if (ok != true || n <= 0 || n > (program['balance'] as num)) return;
    final per = (program['pointsPerUnitDiscount'] as num).toInt();
    setState(() => _busy = true);
    try {
      final r = await ref.read(apiProvider).redeem(
            qr: qr,
            programId: program['programId'] as String,
            points: n,
            idempotencyKey: key,
          );
      _handleSpend(
        r,
        title: s.redeem,
        points: n,
        success: (res) {
          final p = (res['points'] as num?)?.toInt() ?? n;
          final disc = (res['discountMinor'] as num?)?.toInt() ?? (per == 0 ? 0 : (p * 100) ~/ per);
          final nb = (res['newBalance'] as num?)?.toInt();
          return {
            'title': s.pointsRedeemedMsg(p),
            'subtitle': [s.discountValue(formatMinor(disc, (res['currency'] as String?) ?? 'USD')), if (nb != null) s.newBalance(nb)].join(' · '),
          };
        },
      );
    } on ApiException catch (e) {
      _toastError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Completes a booking, applies a walk-in offer or redeems a reward (needs the customer's QR).
  Future<void> _perk(String kind, Json item) async {
    final qr = _qr;
    if (qr == null || _busy) return;
    final api = ref.read(apiProvider);
    final id = item['id'] as String;
    final title = (item['offerTitle'] ?? item['title'] ?? '') as String;
    final cost = (item['pointsCost'] as num?)?.toInt() ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(
          cost > 0
              ? s.tr(
                  'رح نبعت للزبون يوافق على ${formatPoints(cost)} نقطة من تلفونه.',
                  'The customer will approve ${formatPoints(cost)} points on their phone.',
                )
              : s.tr('تأكيد استعمال العرض؟', 'Confirm using this offer?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(cost > 0 ? s.tr('ابعت', 'Send') : s.confirm)),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final key = newUuid();
      final r = switch (kind) {
        'booking' => await api.redeemBooking(id, qr, key),
        'offer' => await api.applyOffer(id, qr, key),
        _ => await api.redeemReward(id, qr, key),
      };
      _handleSpend(
        r,
        title: title,
        points: cost,
        success: (res) {
          final nb = (res['newBalance'] as num?)?.toInt();
          return {
            'title': kind == 'reward' ? s.tr('انصرفت المكافأة', 'Reward redeemed') : s.tr('انطبّق العرض', 'Offer applied'),
            'subtitle': [title, if (cost > 0) '-${formatPoints(cost)} ${s.points}', if (nb != null) s.newBalance(nb)].join(' · '),
          };
        },
      );
    } on ApiException catch (e) {
      if (widget.embedded && e.status == 401) ref.invalidate(ownerCounterProvider);
      if (mounted) MkToast.show(context, _err(e.code), kind: MkToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Company Mukafaah Points spent at a Mukafaah Friend shop (capped per bill).
  Future<void> _mukafaah() async {
    final c = _customer;
    if (c == null || _busy) return;
    final max = c.mukafaahUsable;
    if (max <= 0) return;
    final pts = TextEditingController();
    final bill = TextEditingController(text: _billCtl.text);
    final key = newUuid();
    final chips = <int>{for (final v in [100, 250, 500, 1000]) if (v < max) v, max}.toList()..sort();
    final ok = await showMkSheet<bool>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final t = Theme.of(ctx).textTheme;
          final n = int.tryParse(pts.text) ?? 0;
          final valid = n > 0 && n <= max;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const MkCoin(size: 36),
                  const SizedBox(width: MkSpace.sm),
                  Expanded(child: Text(s.tr('نقاط مكافأة', 'Mukafaah Points'), style: t.titleLarge)),
                ],
              ),
              const SizedBox(height: MkSpace.xs),
              Text(
                s.tr(
                  'رصيد الزبون ${formatPoints(c.mukafaahPoints)} · لحد ${formatPoints(c.friendsMaxPoints)} بكل فاتورة',
                  'Customer has ${formatPoints(c.mukafaahPoints)} · up to ${formatPoints(c.friendsMaxPoints)} per bill',
                ),
                style: t.bodyMedium?.copyWith(color: MkColors.ink2),
              ),
              const SizedBox(height: MkSpace.md),
              Wrap(
                spacing: MkSpace.xs,
                runSpacing: MkSpace.xs,
                children: [
                  for (final v in chips)
                    ChoiceChip(
                      label: Text(v == max ? '${s.tr('الحد', 'Max')} · ${formatPoints(v)}' : formatPoints(v)),
                      selected: n == v,
                      selectedColor: MkColors.yellow500,
                      showCheckmark: false,
                      onSelected: (_) => setSt(() => pts.text = '$v'),
                    ),
                ],
              ),
              const SizedBox(height: MkSpace.sm),
              Directionality(
                textDirection: TextDirection.ltr,
                child: TextField(
                  controller: pts,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: t.headlineSmall,
                  decoration: InputDecoration(
                    labelText: s.pointsToRedeem,
                    errorText: n > max ? s.tr('الحد ${formatPoints(max)}', 'Max ${formatPoints(max)}') : null,
                  ),
                  onChanged: (_) => setSt(() {}),
                ),
              ),
              const SizedBox(height: MkSpace.sm),
              Directionality(
                textDirection: TextDirection.ltr,
                child: TextField(
                  controller: bill,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  decoration: InputDecoration(labelText: s.tr('قيمة الفاتورة (اختياري)', 'Bill amount (optional)'), prefixText: r'$ '),
                ),
              ),
              const SizedBox(height: MkSpace.xs),
              AnimatedSwitcher(
                duration: MkMotion.base,
                child: n > 0
                    ? Text(
                        s.discountValue(formatMinor(n, 'USD')),
                        key: ValueKey(n),
                        style: t.titleMedium?.copyWith(color: MkColors.success),
                      )
                    : const SizedBox(height: 24),
              ),
              const SizedBox(height: MkSpace.sm),
              _ApprovalNote(s: s),
              const SizedBox(height: MkSpace.lg),
              MkButton(
                label: s.tr('ابعت للزبون يوافق', 'Send to customer to approve'),
                icon: Icons.phonelink_ring_rounded,
                kind: MkButtonKind.accent,
                onPressed: valid ? () => Navigator.pop(ctx, true) : null,
              ),
            ],
          );
        },
      ),
    );
    final n = int.tryParse(pts.text) ?? 0;
    final billMinor = parseToMinor(bill.text);
    if (ok != true || n <= 0 || n > max || !mounted) return;
    if (c.userId == null && _qr == null) {
      MkToast.show(context, s.tr('اطلب من الزبون يورجيك رمزه', 'Ask the customer to show their QR'), kind: MkToastKind.error);
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await ref.read(apiProvider).mukafaahRedeem(userId: c.userId, qr: _qr, points: n, billMinor: billMinor, key: key);
      _handleSpend(
        r,
        title: s.tr('نقاط مكافأة', 'Mukafaah Points'),
        points: n,
        success: (res) {
          final p = (res['points'] as num?)?.toInt() ?? n;
          final nb = (res['newBalance'] as num?)?.toInt();
          return {
            'title': s.tr('انصرفوا ${formatPoints(p)} نقطة مكافأة', '${formatPoints(p)} Mukafaah Points redeemed'),
            'subtitle': [s.discountValue(formatMinor(p, 'USD')), if (nb != null) s.newBalance(nb)].join(' · '),
          };
        },
      );
    } on ApiException catch (e) {
      _toastError(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onEscape() {
    if (_pending != null) {
      _cancelPending();
    } else {
      _reset();
    }
  }

  Future<void> _scan() async {
    final value = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _ScannerPage()));
    if (value != null) {
      _lookupCtl.text = value;
      await _lookup(value);
    }
  }

  bool get _canScanWithCamera {
    final p = Theme.of(context).platform;
    return p == TargetPlatform.android || p == TargetPlatform.iOS;
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);
    final session = ref.watch(sessionProvider);
    final t = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final collect = _mode == CounterMode.collect;
    // The owner on their own phone can always redeem; cashiers need permission.
    final canRedeem = widget.embedded || session.staff?.canRedeem == true;

    final header = Container(
      padding: const EdgeInsets.symmetric(horizontal: MkSpace.lg, vertical: MkSpace.sm),
      color: MkColors.purple900,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const MkLogo(height: 40, onDark: true),
            const SizedBox(width: MkSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.device?.businessName ?? session.workerShop ?? '', style: t.titleSmall?.copyWith(color: Colors.white)),
                  Text(
                    [session.device?.branchName ?? session.workerBranch, session.staff?.name].whereType<String>().where((x) => x.isNotEmpty).join(' · '),
                    style: t.bodySmall?.copyWith(color: const Color(0xFFD8CCE6)),
                  ),
                ],
              ),
            ),
            const AlertsBell(owner: false, onDark: true),
            TextButton.icon(
              onPressed: () => context.push('/counter/shift'),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.history_rounded),
              label: Text(strings.myShift),
            ),
            IconButton(
              // A worker on their own phone signs out; a shared counter just locks.
              tooltip: session.mode == AppMode.worker ? strings.tr('تسجيل خروج', 'Sign out') : strings.lock,
              onPressed: () => ref.read(sessionProvider.notifier).lockCounter(),
              icon: Icon(session.mode == AppMode.worker ? Icons.logout_rounded : Icons.lock_rounded, color: MkColors.yellow500),
            ),
          ],
        ),
      ),
    );

    final modeSwitch = widget.mode != null
        ? null
        : SegmentedButton<CounterMode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: CounterMode.collect, icon: const Icon(Icons.receipt_long_rounded), label: Text(strings.tr('جمع الفاتورة', 'Collect invoice'))),
              ButtonSegment(value: CounterMode.redeem, icon: const Icon(Icons.redeem_rounded), label: Text(strings.tr('صرف النقاط', 'Redeem'))),
            ],
            selected: {_mode},
            onSelectionChanged: (v) {
              _reset();
              setState(() => _mode = v.first);
            },
          );

    final lookup = MkCard(
      padding: const EdgeInsets.all(MkSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              MkIconTile(icon: collect ? Icons.receipt_long_rounded : Icons.redeem_rounded, size: 40),
              const SizedBox(width: MkSpace.sm),
              Expanded(
                child: Text(
                  collect ? strings.tr('جمع الفاتورة', 'Collect invoice') : strings.tr('صرف النقاط', 'Redeem points'),
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: MkSpace.xs),
          Text(
            collect
                ? strings.counterHint
                : strings.tr('امسح رمز الزبون لتشوف نقاطه وتصرفلو', "Scan the customer's QR to see their points and redeem"),
            style: t.bodyMedium?.copyWith(color: MkColors.ink2),
          ),
          const SizedBox(height: MkSpace.md),
          Row(
            children: [
              Expanded(
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: TextField(
                    controller: _lookupCtl,
                    focusNode: _lookupFocus,
                    autofocus: true,
                    enabled: _result == null,
                    style: t.titleLarge,
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: '70 123 456'),
                    onSubmitted: _lookup,
                  ),
                ),
              ),
              const SizedBox(width: MkSpace.sm),
              if (_canScanWithCamera)
                SizedBox(
                  width: 140,
                  child: MkButton(label: strings.scanQr, icon: Icons.qr_code_scanner_rounded, kind: MkButtonKind.accent, onPressed: _scan),
                )
              else
                SizedBox(
                  width: 120,
                  child: MkButton(label: strings.search, onPressed: () => _lookup(_lookupCtl.text), loading: _busy && _customer == null),
                ),
            ],
          ),
          if (_customer != null) ...[
            const SizedBox(height: MkSpace.lg),
            MkEntrance(child: _CustomerCard(c: _customer!, s: strings)),
            if (!collect && _customer!.isMember && (_customer!.bookings.isNotEmpty || _customer!.walkInOffers.isNotEmpty || _customer!.rewards.isNotEmpty))
              MkEntrance(
                index: 1,
                child: _PerksPanel(
                  c: _customer!,
                  s: strings,
                  hasQr: _qr != null,
                  canRedeem: canRedeem,
                  onUse: _perk,
                ),
              ),
          ],
        ],
      ),
    );

    final billing = MkCard(
      padding: const EdgeInsets.all(MkSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(strings.billAmount, style: t.titleMedium),
          const SizedBox(height: MkSpace.md),
          TextField(
            controller: _invoiceCtl,
            enabled: _customer != null && _result == null,
            maxLength: 40,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: strings.tr('رقم الفاتورة (اختياري)', 'Invoice number (optional)'),
              prefixIcon: const Icon(Icons.tag_rounded),
              counterText: '',
            ),
            onSubmitted: (_) => _billFocus.requestFocus(),
          ),
          const SizedBox(height: MkSpace.sm),
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _billCtl,
              focusNode: _billFocus,
              enabled: _customer != null && _result == null,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              style: t.displaySmall,
              decoration: const InputDecoration(prefixText: r'$ ', hintText: '0.00'),
              onChanged: _onBillChanged,
              onSubmitted: (_) => _earn(),
            ),
          ),
          const SizedBox(height: MkSpace.md),
          AnimatedSwitcher(
            duration: MkMotion.base,
            child: _previewPoints == null
                ? const SizedBox(height: 32)
                : Row(
                    key: ValueKey(_previewPoints),
                    children: [
                      const MkCoin(size: 28),
                      const SizedBox(width: MkSpace.xs),
                      Text(strings.willEarn(_previewPoints!), style: t.titleLarge?.copyWith(color: MkColors.purple700)),
                    ],
                  ),
          ),
          const SizedBox(height: MkSpace.lg),
          MkButton(
            label: strings.givePoints,
            icon: Icons.add_circle_rounded,
            kind: MkButtonKind.accent,
            loading: _busy && _customer != null,
            onPressed: _customer != null && (_previewPoints ?? 0) > 0 ? _earn : null,
          ),
          const SizedBox(height: MkSpace.xs),
          if (_customer != null) MkButton(label: strings.cancel, kind: MkButtonKind.ghost, onPressed: _reset),
        ],
      ),
    );

    final redeemCard = MkCard(
      padding: const EdgeInsets.all(MkSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(strings.tr('صرف نقاط كخصم', 'Redeem points as a discount'), style: t.titleMedium),
          const SizedBox(height: MkSpace.xs),
          Text(
            strings.tr('١٠٠ نقطة = \$١ خصم. الزبون بيوافق من تلفونه.', '100 points = \$1 off. The customer approves it on their phone.'),
            style: t.bodySmall?.copyWith(color: MkColors.ink3),
          ),
          const SizedBox(height: MkSpace.md),
          if (_customer == null)
            Text(strings.tr('امسح الرمز أول.', 'Scan the QR first.'), style: t.bodyMedium?.copyWith(color: MkColors.ink2))
          else if (!_customer!.isMember)
            Text(strings.tr('هالرقم مش مسجّل بالتطبيق بعد.', "This number isn't on the app yet."), style: t.bodyMedium?.copyWith(color: MkColors.ink2))
          else if (_customer!.presentedQr != true)
            Text(_askForQr(strings), style: t.bodyMedium?.copyWith(color: MkColors.warning))
          else if (!canRedeem)
            Text(strings.tr('ما عندك صلاحية تصرف.', "You don't have permission to redeem."), style: t.bodyMedium?.copyWith(color: MkColors.danger))
          else
            MkButton(label: strings.redeem, icon: Icons.redeem_rounded, kind: MkButtonKind.accent, onPressed: _redeem),
          const SizedBox(height: MkSpace.xs),
          if (_customer != null) MkButton(label: strings.cancel, kind: MkButtonKind.ghost, onPressed: _reset),
        ],
      ),
    );
    final c = _customer;
    final showMukafaah = !collect && c != null && c.isMember && c.mukafaahUsable > 0;
    final side = collect
        ? billing
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showMukafaah && c != null) ...[
                MkEntrance(child: _MukafaahCard(c: c, s: strings, enabled: canRedeem && !_busy, onUse: _mukafaah)),
                const SizedBox(height: MkSpace.md),
              ],
              redeemCard,
            ],
          );

    final result = _result == null
        ? null
        : MkCard(
            padding: const EdgeInsets.all(MkSpace.xl),
            child: _result!['title'] != null
                ? MkSuccessView(
                    title: _result!['title'] as String,
                    subtitle: _result!['subtitle'] as String?,
                    extra: _result!['approved'] == true ? _ApprovedChip(s: strings) : null,
                    action: strings.nextCustomer,
                    onAction: _reset,
                  )
                : MkSuccessView(
                    // Earning (no approval needed).
                    title: strings.pointsGiven(((_result!['points'] as num?) ?? 0).toInt()),
                    subtitle: strings.newBalance(((_result!['newBalance'] as num?) ?? 0).toInt()),
                    action: strings.nextCustomer,
                    onAction: _reset,
                  ),
          );

    // One state at a time, cross-faded: the counter, waiting for approval, a failure, or success.
    final pending = _pending;
    final failure = _failure;
    final (String stateKey, Widget? focus) = pending != null
        ? (
            'wait-${pending.id}',
            MkCard(
              padding: const EdgeInsets.all(MkSpace.xl),
              child: _ApprovalWaiting(pending: pending, s: strings, onCancel: _cancelPending),
            ),
          )
        : failure != null
            ? (
                'fail',
                MkCard(
                  padding: const EdgeInsets.all(MkSpace.xl),
                  child: _OutcomeView(
                    o: failure,
                    s: strings,
                    onBack: () => setState(() => _failure = null),
                    onNext: _reset,
                  ),
                ),
              )
            : (result != null ? ('done', result) : ('main', null));

    final screen = Scaffold(
      body: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _onEscape},
        child: Column(
          children: [
            if (!widget.embedded) header,
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(MkSpace.lg),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: AnimatedSwitcher(
                      duration: MkMotion.slow,
                      switchInCurve: MkMotion.enter,
                      switchOutCurve: MkMotion.exit,
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: ScaleTransition(scale: Tween<double>(begin: 0.96, end: 1).animate(a), child: child),
                      ),
                      child: KeyedSubtree(
                        key: ValueKey(stateKey),
                        child: focus != null
                        ? ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: focus)
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (modeSwitch != null) ...[modeSwitch, const SizedBox(height: MkSpace.md)],
                              if (wide)
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: lookup),
                                    const SizedBox(width: MkSpace.lg),
                                    Expanded(child: side),
                                  ],
                                )
                              else ...[lookup, const SizedBox(height: MkSpace.md), side],
                            ],
                          ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    // Counter devices get live alerts here; the owner's poller lives in the owner shell.
    return widget.embedded ? screen : AlertsPoller(owner: false, child: screen);
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.c, required this.s});
  final CustomerView c;
  final S s;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final title = c.displayName ?? maskPhone(c.phoneLast4);
    return Container(
      padding: const EdgeInsets.all(MkSpace.md),
      decoration: BoxDecoration(
        color: c.isMember ? MkColors.purple50 : MkColors.yellow50,
        borderRadius: MkRadius.all(MkRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MkMonogram(name: c.displayName ?? '#', size: 44),
              const SizedBox(width: MkSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleMedium, textDirection: c.displayName == null ? TextDirection.ltr : null),
                    Text(
                      c.isMember ? (c.presentedQr ? s.presentedQr : s.memberOnApp) : s.notOnApp,
                      style: t.bodySmall?.copyWith(color: c.isMember ? MkColors.purple700 : MkColors.warning),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: MkSpace.sm),
          for (final p in c.programs)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  MkProgramBadge(type: p['type'] as String, label: s.programType(p['type'] as String)),
                  const SizedBox(width: MkSpace.xs),
                  Expanded(child: Text(p['name'] as String, overflow: TextOverflow.ellipsis)),
                  Text(
                    '${formatPoints(p['balance'] as num)} ${s.points}',
                    textDirection: TextDirection.ltr,
                    style: t.titleSmall,
                  ),
                ],
              ),
            ),
          if (!c.isMember && c.prePointsHere > 0)
            Padding(
              padding: const EdgeInsets.only(top: MkSpace.xs),
              child: Text('${s.prePointsHere}: ${formatPoints(c.prePointsHere)}', style: t.labelLarge),
            ),
        ],
      ),
    );
  }
}

class _ScannerPage extends StatefulWidget {
  const _ScannerPage();

  @override
  State<_ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<_ScannerPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_done) return;
              final v = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
              if (v == null) return;
              _done = true;
              Navigator.of(context).pop(v);
            },
          ),
          IgnorePointer(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: MkColors.yellow500, width: 4),
                borderRadius: MkRadius.all(MkRadius.lg),
              ),
            ),
          ),
        ],
      ),
    );
  }
}


/// Accepted bookings, walk-in offers and rewards for the customer at the counter.
class _PerksPanel extends StatelessWidget {
  const _PerksPanel({required this.c, required this.s, required this.hasQr, required this.canRedeem, required this.onUse});

  final CustomerView c;
  final S s;
  final bool hasQr;
  final bool canRedeem;
  final Future<void> Function(String kind, Json item) onUse;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget row({required IconData icon, required String title, String? sub, required String action, VoidCallback? onTap, bool highlight = false}) =>
        Container(
          margin: const EdgeInsets.only(top: MkSpace.xs),
          padding: const EdgeInsets.all(MkSpace.sm),
          decoration: BoxDecoration(
            color: highlight ? MkColors.yellow50 : MkColors.purple50,
            borderRadius: MkRadius.all(MkRadius.md),
          ),
          child: Row(
            children: [
              Icon(icon, color: MkColors.purple700),
              const SizedBox(width: MkSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                    if (sub != null) Text(sub, style: t.bodySmall?.copyWith(color: MkColors.ink2)),
                  ],
                ),
              ),
              FilledButton(onPressed: onTap, child: Text(action)),
            ],
          ),
        );
    String cost(Json x) {
      final n = (x['pointsCost'] as num?)?.toInt() ?? 0;
      return n > 0 ? '${formatPoints(n)} ${s.points}' : s.tr('ببلاش', 'Free');
    }

    final enabled = hasQr && canRedeem;
    return Padding(
      padding: const EdgeInsets.only(top: MkSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.tr('عروض ومكافآت الزبون', "Customer's offers & rewards"), style: t.titleMedium),
          if (!hasQr)
            Text(_askForQr(s), style: t.bodySmall?.copyWith(color: MkColors.ink3)),
          for (final b in c.bookings)
            row(
              icon: Icons.event_available_rounded,
              title: (b['offerTitle'] ?? '') as String,
              sub: '${s.tr('حجز', 'Booking')} ${b['code']} · ${cost(b)}',
              action: s.tr('تم', 'Complete'),
              highlight: true,
              onTap: enabled ? () => onUse('booking', b) : null,
            ),
          for (final o in c.walkInOffers)
            row(
              icon: Icons.local_offer_rounded,
              title: o['title'] as String,
              sub: o['usedUp'] == true ? s.tr('استعملو من قبل', 'Already used') : cost(o),
              action: s.tr('طبّق', 'Apply'),
              onTap: enabled && o['canUse'] == true ? () => onUse('offer', o) : null,
            ),
          for (final w in c.rewards)
            row(
              icon: Icons.redeem_rounded,
              title: w['title'] as String,
              sub: cost(w),
              action: s.redeem,
              onTap: enabled && w['canAfford'] == true ? () => onUse('reward', w) : null,
            ),
        ],
      ),
    );
  }
}

String _askForQr(S s) => s.tr('اطلب من الزبون يورجيك رمزه', 'Ask the customer to show their QR');

// ---------------------------------------------------------------- v0.7 approvals
/// A spend request waiting for the customer's approval on their phone.
class _Pending {
  _Pending({
    required this.id,
    required this.title,
    required this.points,
    required this.startedAt,
    required this.expiresAt,
    required this.success,
  });

  final String id;
  final String title;
  final int points;
  final DateTime startedAt;
  final DateTime expiresAt;

  /// Builds the success card from the approved request's result.
  final Json Function(Json result) success;
}

class _Outcome {
  const _Outcome({required this.icon, required this.color, required this.title, required this.message});
  final IconData icon;
  final Color color;
  final String title;
  final String message;
}

/// Small reminder under the redeem sheets: points move only after the customer approves.
class _ApprovalNote extends StatelessWidget {
  const _ApprovalNote({required this.s});
  final S s;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(MkSpace.sm),
      decoration: BoxDecoration(color: MkColors.purple50, borderRadius: MkRadius.all(MkRadius.md)),
      child: Row(
        children: [
          const Icon(Icons.phonelink_lock_rounded, color: MkColors.purple700, size: 20),
          const SizedBox(width: MkSpace.xs),
          Expanded(
            child: Text(
              s.tr('الزبون بيوصله طلب على تلفونه وبيوافق قبل ما تنخصم النقاط.', 'The customer gets a request on their phone and approves it before any points are taken.'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: MkColors.ink2),
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovedChip extends StatelessWidget {
  const _ApprovedChip({required this.s});
  final S s;

  @override
  Widget build(BuildContext context) {
    return MkEntrance(
      index: 5,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: MkColors.successBg, borderRadius: MkRadius.all(MkRadius.pill)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.verified_rounded, size: 18, color: MkColors.success),
            const SizedBox(width: 6),
            Text(
              s.tr('الزبون وافق من تلفونه', 'Approved on the customer’s phone'),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: MkColors.success),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Waiting for the customer to approve on their phone": a phone with pulsing
/// rings, a live countdown to expiry, and Cancel.
class _ApprovalWaiting extends StatefulWidget {
  const _ApprovalWaiting({required this.pending, required this.s, required this.onCancel});

  final _Pending pending;
  final S s;
  final VoidCallback onCancel;

  @override
  State<_ApprovalWaiting> createState() => _ApprovalWaitingState();
}

class _ApprovalWaitingState extends State<_ApprovalWaiting> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final p = widget.pending;
    final t = Theme.of(context).textTheme;
    final reduce = MediaQuery.disableAnimationsOf(context);
    final total = p.expiresAt.difference(p.startedAt).inSeconds.clamp(1, 600);
    final left = p.expiresAt.difference(DateTime.now()).inSeconds.clamp(0, total);
    final mmss = '${left ~/ 60}:${(left % 60).toString().padLeft(2, '0')}';
    final urgent = left <= 20;

    final phone = SizedBox.square(
      dimension: 190,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              if (!reduce)
                for (var i = 0; i < 3; i++)
                  Builder(
                    builder: (context) {
                      final v = (_pulse.value + i / 3) % 1;
                      final size = 96 + 90 * Curves.easeOut.transform(v);
                      return Container(
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: MkColors.purple500.withValues(alpha: 0.10 * (1 - v)),
                          border: Border.all(color: MkColors.purple500.withValues(alpha: 0.45 * (1 - v)), width: 2),
                        ),
                      );
                    },
                  ),
              Transform.translate(
                offset: Offset(0, reduce ? 0 : math.sin(_pulse.value * math.pi * 2) * 4),
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [MkColors.purple900, MkColors.purple700],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: MkShadow.lifted,
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(Icons.phone_iphone_rounded, size: 50, color: Colors.white),
                      // A little yellow "tap" bouncing on the screen of the phone.
                      Transform.scale(
                        scale: reduce ? 1 : 0.8 + 0.3 * math.sin(_pulse.value * math.pi * 4).abs(),
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: const BoxDecoration(color: MkColors.yellow500, shape: BoxShape.circle, boxShadow: MkShadow.glow),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    final dots = reduce ? '…' : '.' * (1 + (_pulse.value * 6).floor() % 3);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        phone,
        const SizedBox(height: MkSpace.md),
        Text(
          s.tr('ناطرين الزبون يوافق من تلفونه', 'Waiting for the customer to approve on their phone'),
          textAlign: TextAlign.center,
          style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: MkSpace.xs),
        Text(
          [p.title, if (p.points > 0) '-${formatPoints(p.points)} ${s.points}'].join(' · '),
          textAlign: TextAlign.center,
          style: t.titleMedium?.copyWith(color: MkColors.purple700),
        ),
        const SizedBox(height: MkSpace.xs),
        Text(
          s.tr('خلّيه يفتح تطبيق مكافأة ويكبس "موافق"', 'Ask them to open the Mukafaah app and tap Approve'),
          textAlign: TextAlign.center,
          style: t.bodyMedium?.copyWith(color: MkColors.ink2),
        ),
        const SizedBox(height: MkSpace.lg),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: MkSpace.md, vertical: MkSpace.xs),
          decoration: BoxDecoration(
            color: urgent ? MkColors.warningBg : MkColors.purple50,
            borderRadius: MkRadius.all(MkRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 22,
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(end: left / total),
                  duration: const Duration(milliseconds: 900),
                  builder: (context, v, _) => CircularProgressIndicator(
                    value: v,
                    strokeWidth: 3,
                    backgroundColor: MkColors.line,
                    color: urgent ? MkColors.warning : MkColors.purple700,
                  ),
                ),
              ),
              const SizedBox(width: MkSpace.xs),
              Text(
                left == 0 ? s.tr('عم يخلص الوقت$dots', 'Expiring$dots') : '${s.tr('بينتهي بعد', 'Expires in')} $mmss',
                textDirection: left == 0 ? null : TextDirection.ltr,
                style: t.titleSmall?.copyWith(color: urgent ? MkColors.warning : MkColors.purple900),
              ),
            ],
          ),
        ),
        const SizedBox(height: MkSpace.xl),
        MkButton(label: s.tr('إلغاء الطلب', 'Cancel request'), icon: Icons.close_rounded, kind: MkButtonKind.secondary, onPressed: widget.onCancel),
      ],
    );
  }
}

/// Declined / expired / failed: a clear message with a way back.
class _OutcomeView extends StatelessWidget {
  const _OutcomeView({required this.o, required this.s, required this.onBack, required this.onNext});

  final _Outcome o;
  final S s;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 650),
          curve: Curves.elasticOut,
          builder: (context, v, child) => Transform.scale(scale: v, child: child),
          child: Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(shape: BoxShape.circle, color: o.color.withValues(alpha: 0.12)),
            child: Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(shape: BoxShape.circle, color: o.color),
                child: Icon(o.icon, color: Colors.white, size: 38),
              ),
            ),
          ),
        ),
        const SizedBox(height: MkSpace.lg),
        MkEntrance(index: 2, child: Text(o.title, textAlign: TextAlign.center, style: t.headlineSmall)),
        const SizedBox(height: MkSpace.xs),
        MkEntrance(
          index: 3,
          child: Text(o.message, textAlign: TextAlign.center, style: t.bodyLarge?.copyWith(color: MkColors.ink2)),
        ),
        const SizedBox(height: MkSpace.xl),
        MkButton(label: s.tr('رجوع للزبون', 'Back to customer'), icon: Icons.replay_rounded, kind: MkButtonKind.accent, onPressed: onBack),
        const SizedBox(height: MkSpace.xs),
        MkButton(label: s.nextCustomer, kind: MkButtonKind.ghost, onPressed: onNext),
      ],
    );
  }
}

/// Distinct golden card for company Mukafaah Points at a Mukafaah Friend shop.
class _MukafaahCard extends StatelessWidget {
  const _MukafaahCard({required this.c, required this.s, required this.enabled, required this.onUse});

  final CustomerView c;
  final S s;
  final bool enabled;
  final VoidCallback onUse;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ClipRRect(
      borderRadius: MkRadius.all(MkRadius.lg),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [MkColors.yellow500, MkColors.yellow200],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: MkShadow.glow,
        ),
        child: Stack(
          children: [
            PositionedDirectional(
              top: -30,
              end: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.25)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(MkSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const MkFloat(amplitude: 3, child: MkCoin(size: 44)),
                      const SizedBox(width: MkSpace.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.tr('نقاط مكافأة', 'Mukafaah Points'),
                              style: t.titleMedium?.copyWith(color: MkColors.purple900, fontWeight: FontWeight.w800),
                            ),
                            Text(
                              s.tr('لحد ${formatPoints(c.friendsMaxPoints)} بكل فاتورة', 'up to ${formatPoints(c.friendsMaxPoints)} per bill'),
                              style: t.bodySmall?.copyWith(color: MkColors.purple700),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          AnimatedPoints(
                            value: c.mukafaahPoints,
                            format: (n) => formatPoints(n),
                            style: t.headlineSmall?.copyWith(color: MkColors.purple900, fontWeight: FontWeight.w800),
                          ),
                          Text('≈ ${formatMinor(c.mukafaahPoints, 'USD')}', style: t.labelMedium?.copyWith(color: MkColors.purple700)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: MkSpace.md),
                  MkButton(
                    label: s.tr('استعمل نقاط مكافأة', 'Use Mukafaah Points'),
                    icon: Icons.stars_rounded,
                    onPressed: enabled ? onUse : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
