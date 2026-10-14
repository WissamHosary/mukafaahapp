import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart' show AssetSource, AudioPlayer;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../../data/api.dart';
import '../owner/owner_widgets.dart';

// ---------------------------------------------------------------- Feed (bell)
class AlertsFeedState {
  const AlertsFeedState({this.items = const [], this.unread = 0});

  /// Newest first.
  final List<BizAlert> items;
  final int unread;
}

/// Recent alerts for the bell. Filled by [AlertsPoller].
class AlertsFeed extends Notifier<AlertsFeedState> {
  @override
  AlertsFeedState build() => const AlertsFeedState();

  /// [fresh] comes from the server newest last.
  void add(List<BizAlert> fresh) {
    final known = {for (final a in state.items) a.id};
    final news = [for (final a in fresh.reversed) if (!known.contains(a.id)) a];
    if (news.isEmpty) return;
    state = AlertsFeedState(
      items: [...news, ...state.items].take(40).toList(),
      unread: state.unread + news.length,
    );
  }

  void markRead() {
    if (state.unread != 0) state = AlertsFeedState(items: state.items);
  }
}

final alertsFeedProvider = NotifierProvider<AlertsFeed, AlertsFeedState>(AlertsFeed.new);

// ---------------------------------------------------------------- Look & routes
({IconData icon, Color color}) alertStyle(String kind) => switch (kind) {
      'BOOKING' => (icon: Icons.event_available_rounded, color: MkColors.yellow500),
      'ORDER' => (icon: Icons.shopping_bag_rounded, color: const Color(0xFF8FD3FF)),
      'REDEEM_APPROVED' => (icon: Icons.verified_rounded, color: const Color(0xFF5FE0A6)),
      'REDEEM_DECLINED' => (icon: Icons.block_rounded, color: const Color(0xFFFF8A95)),
      'RATING' => (icon: Icons.star_rounded, color: MkColors.yellow500),
      'OFFER_USED' => (icon: Icons.local_offer_rounded, color: MkColors.yellow200),
      _ => (icon: Icons.notifications_active_rounded, color: Colors.white),
    };

String alertKindLabel(S s, String kind) => switch (kind) {
      'BOOKING' => s.tr('حجز جديد', 'New booking'),
      'ORDER' => s.tr('طلب من المتجر', 'Store order'),
      'REDEEM_APPROVED' => s.tr('الزبون وافق', 'Customer approved'),
      'REDEEM_DECLINED' => s.tr('الزبون رفض', 'Customer declined'),
      'RATING' => s.tr('تقييم جديد', 'New rating'),
      'OFFER_USED' => s.tr('عرض انستعمل', 'Offer used'),
      _ => s.tr('تنبيه', 'Alert'),
    };

/// Where "Open" goes for the owner.
String? ownerAlertRoute(BizAlert a) => switch (a.kind) {
      'BOOKING' => '/owner/bookings',
      'ORDER' => '/owner/orders',
      'RATING' => '/owner/dashboard',
      'REDEEM_APPROVED' || 'REDEEM_DECLINED' || 'OFFER_USED' => '/owner/transactions',
      _ => null,
    };

/// Where "Open" goes on a counter device (cashiers only see their own shift).
String? counterAlertRoute(BizAlert a) =>
    a.kind == 'REDEEM_APPROVED' || a.kind == 'REDEEM_DECLINED' || a.kind == 'OFFER_USED' ? '/counter/shift' : null;

void _openRoute(BuildContext context, bool owner, String route) {
  if (owner) {
    context.go(route);
  } else {
    context.push(route);
  }
}

// ---------------------------------------------------------------- Poller
/// Polls the shop's alerts every 6 s while the app is in the foreground. Each new
/// alert plays a chime, buzzes, and slides in a popup card from the top.
/// Mount once per shell: [owner] = owner app, otherwise a cashier counter device.
class AlertsPoller extends ConsumerStatefulWidget {
  const AlertsPoller({required this.owner, required this.child, super.key});

  final bool owner;
  final Widget child;

  @override
  ConsumerState<AlertsPoller> createState() => _AlertsPollerState();
}

class _AlertsPollerState extends ConsumerState<AlertsPoller> with WidgetsBindingObserver {
  static const _every = Duration(seconds: 6);
  static const _maxPopups = 3;

  Timer? _timer;
  String? _cursor;
  bool _inFlight = false;
  bool _foreground = true;
  final List<BizAlert> _popups = [];
  AudioPlayer? _player;
  DateTime _lastChime = DateTime.fromMillisecondsSinceEpoch(0);

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
    _player?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    _foreground = fg;
    if (fg) {
      _start();
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(_every, (_) => _tick());
    unawaited(_tick());
  }

  Future<void> _tick() async {
    if (_inFlight || !_foreground || !mounted) return;
    _inFlight = true;
    try {
      final first = _cursor == null;
      final r = await ref.read(apiProvider).alerts(owner: widget.owner, after: _cursor);
      if (!mounted) return;
      // A shop with no alerts yet has no cursor: start from 0 so the first one is not missed.
      _cursor = r.cursor ?? _cursor ?? '0';
      if (first || r.alerts.isEmpty) return;
      _present(r.alerts);
    } on Object {
      // Quiet: the next tick tries again.
    } finally {
      _inFlight = false;
    }
  }

  void _present(List<BizAlert> fresh) {
    ref.read(alertsFeedProvider.notifier).add(fresh);
    if (widget.owner) _refreshOwnerData(fresh);
    // Newest first; at most three cards on screen.
    final batch = fresh.reversed.take(_maxPopups).toList();
    setState(() {
      for (final a in batch.reversed) {
        _popups
          ..removeWhere((p) => p.id == a.id)
          ..insert(0, a);
      }
      while (_popups.length > _maxPopups) {
        _popups.removeLast();
      }
    });
    unawaited(_chime());
    unawaited(HapticFeedback.heavyImpact());
  }

  /// Keeps the owner's lists fresh without a manual pull-to-refresh.
  void _refreshOwnerData(List<BizAlert> fresh) {
    final kinds = {for (final a in fresh) a.kind};
    if (kinds.contains('BOOKING')) {
      ref
        ..invalidate(bookingSummaryProvider)
        ..invalidate(ownerBookingsProvider);
    }
    if (kinds.contains('ORDER')) ref.invalidate(ordersProvider);
    if (kinds.any((k) => k.startsWith('REDEEM') || k == 'OFFER_USED')) ref.invalidate(ownerTxProvider);
  }

  Future<void> _chime() async {
    final now = DateTime.now();
    if (now.difference(_lastChime) < const Duration(milliseconds: 1500)) return;
    _lastChime = now;
    try {
      final p = _player ??= AudioPlayer();
      await p.stop();
      await p.play(AssetSource('sounds/alert.wav'));
    } on Object {
      // No sound available (muted, tests): the popup still shows.
    }
  }

  void _dismiss(String id) {
    if (!mounted) return;
    setState(() => _popups.removeWhere((p) => p.id == id));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_popups.isNotEmpty)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(MkSpace.sm, MkSpace.xs, MkSpace.sm, 0),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final (i, a) in _popups.indexed)
                            AlertPopup(
                              key: ValueKey('alert-${a.id}'),
                              alert: a,
                              s: s,
                              depth: i,
                              route: widget.owner ? ownerAlertRoute(a) : counterAlertRoute(a),
                              onOpen: (route) {
                                _dismiss(a.id);
                                ref.read(alertsFeedProvider.notifier).markRead();
                                _openRoute(context, widget.owner, route);
                              },
                              onDismiss: () => _dismiss(a.id),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Popup card
/// Slides in from the top with a little overshoot, shows an 8 s life bar, and
/// slides away (or swipe it sideways).
class AlertPopup extends StatefulWidget {
  const AlertPopup({
    required this.alert,
    required this.s,
    required this.onDismiss,
    required this.onOpen,
    this.route,
    this.depth = 0,
    super.key,
  });

  final BizAlert alert;
  final S s;
  final int depth;
  final String? route;
  final void Function(String route) onOpen;
  final VoidCallback onDismiss;

  @override
  State<AlertPopup> createState() => _AlertPopupState();
}

class _AlertPopupState extends State<AlertPopup> with TickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this, duration: MkMotion.slow, reverseDuration: MkMotion.base);
  late final AnimationController _life = AnimationController(vsync: this, duration: const Duration(seconds: 8));
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _in.forward();
    _pulse.repeat();
    _life
      ..addStatusListener((st) {
        if (st == AnimationStatus.completed) _close();
      })
      ..forward();
  }

  @override
  void dispose() {
    _in.dispose();
    _life.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    await _in.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final a = widget.alert;
    final st = alertStyle(a.kind);
    final reduce = MediaQuery.disableAnimationsOf(context);
    final slide = Tween<Offset>(begin: const Offset(0, -1.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _in, curve: MkMotion.emphasized, reverseCurve: MkMotion.exit));
    final scale = 1 - widget.depth * 0.04;

    final icon = SizedBox.square(
      dimension: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (!reduce)
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) {
                final v = Curves.easeOut.transform(_pulse.value);
                return Container(
                  width: 40 + 16 * v,
                  height: 40 + 16 * v,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: st.color.withValues(alpha: 0.6 * (1 - v)), width: 2),
                  ),
                );
              },
            ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(shape: BoxShape.circle, color: st.color.withValues(alpha: 0.18)),
            child: Icon(st.icon, color: st.color, size: 22),
          ),
        ],
      ),
    );

    final card = Container(
      margin: const EdgeInsets.only(bottom: MkSpace.xs),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [MkColors.purple900, MkColors.purple700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: MkRadius.all(MkRadius.lg),
        border: Border.all(color: st.color.withValues(alpha: 0.35)),
        boxShadow: MkShadow.lifted,
      ),
      child: ClipRRect(
        borderRadius: MkRadius.all(MkRadius.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(MkSpace.sm, MkSpace.sm, MkSpace.xxs, MkSpace.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  icon,
                  const SizedBox(width: MkSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alertKindLabel(widget.s, a.kind).toUpperCase(),
                          style: t.labelSmall?.copyWith(color: st.color, letterSpacing: 0.8, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          a.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                        if (a.body.isNotEmpty)
                          Text(
                            a.body,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: t.bodySmall?.copyWith(color: const Color(0xFFD8CCE6)),
                          ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      IconButton(
                        tooltip: widget.s.close,
                        visualDensity: VisualDensity.compact,
                        onPressed: _close,
                        icon: const Icon(Icons.close_rounded, color: Color(0xFFD8CCE6), size: 20),
                      ),
                      if (widget.route != null)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: MkSpace.xs),
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: MkColors.yellow500,
                              foregroundColor: MkColors.purple900,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: MkSpace.sm),
                            ),
                            onPressed: () => widget.onOpen(widget.route!),
                            child: Text(widget.s.tr('افتح', 'Open')),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: _life,
              builder: (context, _) => LinearProgressIndicator(
                value: 1 - _life.value,
                minHeight: 3,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(st.color),
              ),
            ),
          ],
        ),
      ),
    );

    return Dismissible(
      key: ValueKey('swipe-${a.id}'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => widget.onDismiss(),
      child: SlideTransition(
        position: slide,
        child: FadeTransition(
          opacity: _in,
          child: AnimatedScale(
            scale: scale,
            duration: MkMotion.base,
            curve: MkMotion.enter,
            child: GestureDetector(
              onTap: widget.route == null ? null : () => widget.onOpen(widget.route!),
              child: card,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Bell
/// Bell with an unread badge; opens the list of recent alerts. It gives a little
/// ring whenever new alerts arrive.
class AlertsBell extends ConsumerWidget {
  const AlertsBell({required this.owner, this.onDark = false, super.key});

  final bool owner;
  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final feed = ref.watch(alertsFeedProvider);
    final color = onDark ? Colors.white : MkColors.purple900;
    final bell = Icon(
      feed.unread > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
      color: feed.unread > 0 && onDark ? MkColors.yellow500 : color,
    );
    return IconButton(
      tooltip: s.tr('التنبيهات', 'Alerts'),
      onPressed: () => _openList(context, ref),
      icon: Badge(
        isLabelVisible: feed.unread > 0,
        backgroundColor: MkColors.danger,
        label: Text(feed.unread > 99 ? '99+' : '${feed.unread}'),
        child: feed.unread == 0 || MediaQuery.disableAnimationsOf(context)
            ? bell
            : TweenAnimationBuilder<double>(
                key: ValueKey(feed.unread),
                tween: Tween<double>(begin: 1, end: 0),
                duration: const Duration(milliseconds: 900),
                builder: (context, v, child) => Transform.rotate(
                  angle: math.sin(v * math.pi * 6) * 0.35 * v,
                  alignment: Alignment.topCenter,
                  child: child,
                ),
                child: bell,
              ),
      ),
    );
  }

  Future<void> _openList(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final items = ref.read(alertsFeedProvider).items;
    ref.read(alertsFeedProvider.notifier).markRead();
    final route = await showMkSheet<String>(
      context,
      builder: (ctx) {
        final t = Theme.of(ctx).textTheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const MkIconTile(icon: Icons.notifications_active_rounded, size: 40),
                const SizedBox(width: MkSpace.sm),
                Expanded(child: Text(s.tr('التنبيهات', 'Alerts'), style: t.titleLarge)),
              ],
            ),
            const SizedBox(height: MkSpace.md),
            if (items.isEmpty)
              MkEmptyState(
                icon: Icons.notifications_none_rounded,
                title: s.tr('ما في تنبيهات بعد', 'No alerts yet'),
                message: s.tr(
                  'الحجوزات والطلبات وموافقات الزباين بتطلع هون فوراً.',
                  'New bookings, store orders and customer approvals pop up here right away.',
                ),
              )
            else
              for (final (i, a) in items.indexed)
                MkEntrance(
                  index: i,
                  child: _AlertRow(
                    alert: a,
                    s: s,
                    onTap: (owner ? ownerAlertRoute(a) : counterAlertRoute(a)) == null
                        ? null
                        : () => Navigator.of(ctx).pop(owner ? ownerAlertRoute(a) : counterAlertRoute(a)),
                  ),
                ),
          ],
        );
      },
    );
    if (route != null && context.mounted) _openRoute(context, owner, route);
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert, required this.s, this.onTap});

  final BizAlert alert;
  final S s;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final st = alertStyle(alert.kind);
    // The popup colors are tuned for dark purple; on white use the brand ink.
    final tint = switch (alert.kind) {
      'REDEEM_APPROVED' => MkColors.success,
      'REDEEM_DECLINED' => MkColors.danger,
      'ORDER' => MkColors.shared,
      _ => MkColors.purple700,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: MkSpace.xs),
      child: MkCard(
        onTap: onTap,
        padding: const EdgeInsets.all(MkSpace.sm),
        child: Row(
          children: [
            MkIconTile(icon: st.icon, size: 40, color: tint, bg: tint.withValues(alpha: 0.1)),
            const SizedBox(width: MkSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(alert.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
                  if (alert.body.isNotEmpty)
                    Text(alert.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: MkColors.ink2)),
                  Text(
                    '${alertKindLabel(s, alert.kind)} · ${fmtDateTime(alert.createdAt)}',
                    style: t.labelSmall?.copyWith(color: MkColors.ink3),
                  ),
                ],
              ),
            ),
            if (onTap != null) const Icon(Icons.chevron_right_rounded, color: MkColors.ink3),
          ],
        ),
      ),
    );
  }
}
