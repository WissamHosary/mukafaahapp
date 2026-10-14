import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../common/common.dart';

/// Centre tab: membership card (balance, referral number, tier, transfer),
/// Mukafaah Points, and the customer's own member QR. The QR is created once
/// per member and never changes; spending points always needs the customer's
/// approval in the app, so the code is safe to show.
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  bool _showBalance = true;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final home = ref.watch(homeProvider).value;
    final wallet = ref.watch(walletProvider).value;
    final qr = ref.watch(memberQrProvider);
    final user = ref.watch(authProvider).user;
    final name = (home?.name ?? user?.name ?? '').toUpperCase();
    final tier = home?.tier ?? 'SILVER';
    const soft = Color(0xFFD8CCE6);

    return Scaffold(
      appBar: AppBar(title: Text(s.wallet), centerTitle: true, automaticallyImplyLeading: false),
      body: RefreshIndicator(
        color: MkColors.purple900,
        onRefresh: () async {
          refreshBalances(ref);
          if (qr.hasError) ref.invalidate(memberQrProvider);
          await ref.read(walletProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.xs, MkSpace.lg, MkSpace.xxl),
          children: [
            // ---------- Membership card ----------
            MkEntrance(
              child: ClipRRect(
                borderRadius: MkRadius.all(MkRadius.xl),
                child: Container(
                  decoration: const BoxDecoration(boxShadow: MkShadow.lifted),
                  child: MkSwirlBackground(
                    color: MkColors.purple700,
                    child: Padding(
                      padding: const EdgeInsets.all(MkSpace.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name.isEmpty ? s.appName : name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.titleMedium?.copyWith(color: Colors.white, letterSpacing: 0.6),
                                ),
                              ),
                              MkTierChip(tier: tier, label: s.tier(tier), onTap: () => context.push('/tier')),
                            ],
                          ),
                          const SizedBox(height: MkSpace.md),
                          Text(s.balancePoints, style: t.labelMedium?.copyWith(color: soft)),
                          GestureDetector(
                            onTap: () => setState(() => _showBalance = !_showBalance),
                            child: AnimatedSwitcher(
                              duration: MkMotion.base,
                              child: _showBalance
                                  ? AnimatedPoints(
                                      key: const ValueKey('b'),
                                      value: home?.balancePoints ?? 0,
                                      format: formatPoints,
                                      style: t.headlineMedium?.copyWith(color: Colors.white),
                                    )
                                  : Text('••••', key: const ValueKey('h'), style: t.headlineMedium?.copyWith(color: Colors.white)),
                            ),
                          ),
                          const SizedBox(height: MkSpace.md),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.referralNumber, style: t.labelMedium?.copyWith(color: soft)),
                                    GestureDetector(
                                      onTap: () async {
                                        final code = home?.referralCode;
                                        if (code == null) return;
                                        await Clipboard.setData(ClipboardData(text: code));
                                        if (context.mounted) MkToast.show(context, s.copied, kind: MkToastKind.success);
                                      },
                                      child: Row(
                                        children: [
                                          Text(home?.referralCode ?? '—', style: t.titleLarge?.copyWith(color: Colors.white, letterSpacing: 1.2)),
                                          const SizedBox(width: 6),
                                          const Icon(Icons.copy_rounded, size: 16, color: soft),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _TransferButton(label: s.transferPoints, onTap: () => context.push('/transfer')),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: MkSpace.sm),
            // ---------- Mukafaah Points ----------
            MkEntrance(
              index: 1,
              child: _MukafaahCard(points: wallet?.mukafaahPoints ?? 0, onTap: () => context.push('/mukafaah')),
            ),
            const SizedBox(height: MkSpace.xl),
            // ---------- Member QR ----------
            Text(s.tr('رمزك الخاص', 'Your member QR'), textAlign: TextAlign.center, style: t.headlineSmall),
            const SizedBox(height: 4),
            Text(
              s.tr('اعرض هالرمز للكاشير مع كل شراء', 'Show this code at the cashier with every purchase'),
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(color: MkColors.ink3),
            ),
            const SizedBox(height: MkSpace.lg),
            Center(
              child: CustomPaint(
                foregroundPainter: _CornersPainter(),
                child: Container(
                  padding: const EdgeInsets.all(MkSpace.lg),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: MkRadius.all(MkRadius.xl),
                    border: Border.all(color: MkColors.purple100, width: 2),
                    boxShadow: MkShadow.lifted,
                  ),
                  child: AnimatedSwitcher(
                    duration: MkMotion.slow,
                    switchInCurve: MkMotion.emphasized,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(scale: Tween<double>(begin: 0.9, end: 1).animate(a), child: child),
                    ),
                    child: qr.when(
                      data: (q) => MkQr(key: ValueKey(q.payload), data: q.payload, size: 224),
                      loading: () => const SizedBox.square(
                        key: ValueKey('l'),
                        dimension: 224,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, _) => SizedBox.square(
                        key: const ValueKey('e'),
                        dimension: 224,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.wifi_off_rounded, color: MkColors.ink3, size: 32),
                              const SizedBox(height: MkSpace.xs),
                              Text(errorText(s, e), textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: MkColors.ink2)),
                              const SizedBox(height: MkSpace.sm),
                              MkButton(label: s.retry, onPressed: () => ref.invalidate(memberQrProvider), expand: false),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: MkSpace.md),
            if ((qr.value?.memberCode ?? '').isNotEmpty)
              MkEntrance(
                index: 2,
                child: Column(
                  children: [
                    Text(s.tr('رقم العضوية', 'Member code'), style: t.labelMedium?.copyWith(color: MkColors.ink3)),
                    const SizedBox(height: 2),
                    GestureDetector(
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: qr.value!.memberCode));
                        if (context.mounted) MkToast.show(context, s.copied, kind: MkToastKind.success);
                      },
                      child: Text(
                        _groups(qr.value!.memberCode),
                        textDirection: TextDirection.ltr,
                        style: t.titleLarge?.copyWith(
                          color: MkColors.purple900,
                          letterSpacing: 2.4,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: MkSpace.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.verified_user_rounded, size: 18, color: MkColors.success),
                const SizedBox(width: MkSpace.xs),
                Expanded(
                  child: Text(
                    s.tr(
                      'هالرمز إلك وحدك وما بيتغير. الكاشير بيمسحه ليزيدلك نقاط، وأي صرف نقاط بيحتاج موافقتك من التطبيق.',
                      'This code is yours alone and never changes. The cashier scans it to add points, and spending points always needs your approval in the app.',
                    ),
                    style: t.bodySmall?.copyWith(color: MkColors.ink3, height: 1.4),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "ABCDEFGHJKLM" -> "ABCD EFGH JKLM".
String _groups(String code) {
  final b = StringBuffer();
  for (var i = 0; i < code.length; i++) {
    if (i > 0 && i % 4 == 0) b.write(' ');
    b.write(code[i]);
  }
  return b.toString();
}

class _TransferButton extends StatelessWidget {
  const _TransferButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: MkPressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 14, 8),
          decoration: BoxDecoration(
            color: MkColors.yellow500,
            borderRadius: MkRadius.all(MkRadius.pill),
            boxShadow: MkShadow.glow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.swap_horiz_rounded, size: 18, color: MkColors.purple900),
              const SizedBox(width: 6),
              Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: MkColors.purple900)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wallet row for company points, opening the Mukafaah Points page.
class _MukafaahCard extends ConsumerWidget {
  const _MukafaahCard({required this.points, required this.onTap});

  final int points;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      button: true,
      label: s.tr('نقاط مكافأة', 'Mukafaah Points'),
      child: MkPressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(MkSpace.md),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: AlignmentDirectional.centerStart,
              end: AlignmentDirectional.centerEnd,
              colors: [MkColors.yellow50, Colors.white],
            ),
            borderRadius: MkRadius.all(MkRadius.lg),
            border: Border.all(color: const Color(0xFFF6E7A1)),
            boxShadow: MkShadow.soft,
          ),
          child: Row(
            children: [
              const MkFloat(amplitude: 3, child: MkCoin(size: 42)),
              const SizedBox(width: MkSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.tr('نقاط مكافأة', 'Mukafaah Points'), style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    Text(
                      s.tr('بتنصرف بمحلات أصدقاء مكافأة', 'Spend them at Mukafaah Friends shops'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.bodySmall?.copyWith(color: MkColors.ink3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: MkSpace.xs),
              AnimatedPoints(
                value: points,
                format: formatPoints,
                style: t.titleLarge?.copyWith(color: MkColors.purple900, fontWeight: FontWeight.w900),
              ),
              Icon(rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, color: MkColors.ink3),
            ],
          ),
        ),
      ),
    );
  }
}

/// Yellow corner brackets around the QR card, like a scanner frame.
class _CornersPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const inset = -7.0;
    const len = 26.0;
    const r = 14.0;
    final p = Paint()
      ..color = MkColors.yellow500
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromLTRB(inset, inset, size.width - inset, size.height - inset);
    void corner(Offset o, double sx, double sy) {
      final path = Path()
        ..moveTo(o.dx, o.dy + sy * len)
        ..lineTo(o.dx, o.dy + sy * r)
        ..quadraticBezierTo(o.dx, o.dy, o.dx + sx * r, o.dy)
        ..lineTo(o.dx + sx * len, o.dy);
      canvas.drawPath(path, p);
    }

    corner(rect.topLeft, 1, 1);
    corner(rect.topRight, -1, 1);
    corner(rect.bottomLeft, 1, -1);
    corner(rect.bottomRight, -1, -1);
  }

  @override
  bool shouldRepaint(_CornersPainter old) => false;
}
