import 'dart:math' as math;

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
            // ---------- Membership card (made to look like a real bank card) ----------
            MkEntrance(
              child: _MemberCard(
                name: name.isEmpty ? s.appName : name,
                code: qr.value?.memberCode ?? '',
                tier: tier,
                tierLabel: s.tier(tier),
                points: home?.balancePoints ?? 0,
                showBalance: _showBalance,
                onToggleBalance: () => setState(() => _showBalance = !_showBalance),
                onTier: () => context.push('/tier'),
              ),
            ),
            const SizedBox(height: MkSpace.sm),
            MkEntrance(
              index: 1,
              child: Row(
                children: [
                  Expanded(
                    child: MkPressable(
                      onTap: () async {
                        final code = home?.referralCode;
                        if (code == null) return;
                        await Clipboard.setData(ClipboardData(text: code));
                        if (context.mounted) MkToast.show(context, s.copied, kind: MkToastKind.success);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: MkRadius.all(MkRadius.lg), boxShadow: MkShadow.soft),
                        child: Row(
                          children: [
                            const Icon(Icons.card_giftcard_rounded, size: 20, color: MkColors.purple700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.referralNumber, style: t.labelSmall?.copyWith(color: MkColors.ink3)),
                                  Text(home?.referralCode ?? '—', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                                ],
                              ),
                            ),
                            const Icon(Icons.copy_rounded, size: 16, color: MkColors.ink3),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: MkSpace.sm),
                  _TransferButton(label: s.transferPoints, onTap: () => context.push('/transfer')),
                ],
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
              child: Container(
                padding: const EdgeInsets.all(MkSpace.md),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: MkRadius.all(28),
                  boxShadow: const [BoxShadow(color: Color(0x262C123F), blurRadius: 30, offset: Offset(0, 14))],
                ),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: MkRadius.all(20),
                    border: Border.all(color: MkColors.purple100, width: 1.5),
                  ),
                  child: AnimatedSwitcher(
                    duration: MkMotion.slow,
                    switchInCurve: MkMotion.emphasized,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(scale: Tween<double>(begin: 0.9, end: 1).animate(a), child: child),
                    ),
                    child: qr.when(
                      data: (q) => MkQr(key: ValueKey(q.payload), data: q.payload, size: 232),
                      loading: () => const SizedBox.square(
                        key: ValueKey('l'),
                        dimension: 232,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, _) => SizedBox.square(
                        key: const ValueKey('e'),
                        dimension: 232,
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

/// The member card, drawn like a real bank card (85.6 x 54 mm): deep purple
/// with a fine guilloche pattern, a gold chip, contactless mark, the member
/// number in raised digits, and two Mukafaah coins as the brand mark.
class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.name,
    required this.code,
    required this.tier,
    required this.tierLabel,
    required this.points,
    required this.showBalance,
    required this.onToggleBalance,
    required this.onTier,
  });

  final String name;
  final String code;
  final String tier;
  final String tierLabel;
  final int points;
  final bool showBalance;
  final VoidCallback onToggleBalance;
  final VoidCallback onTier;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final digits = code.isEmpty ? '•••• •••• ••••' : _groups(code);
    const raised = [Shadow(color: Color(0x99000000), offset: Offset(0, 1.2), blurRadius: 1), Shadow(color: Color(0x40FFFFFF), offset: Offset(0, -0.6))];
    return AspectRatio(
      aspectRatio: 85.6 / 54,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: MkRadius.all(20),
          boxShadow: const [BoxShadow(color: Color(0x662C123F), blurRadius: 30, offset: Offset(0, 16), spreadRadius: -6)],
        ),
        child: ClipRRect(
          borderRadius: MkRadius.all(20),
          child: MkShine(
            period: const Duration(seconds: 7),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF14081F), Color(0xFF2C123F), Color(0xFF55297F)],
                      stops: [0, 0.5, 1],
                    ),
                  ),
                ),
                const RepaintBoundary(child: CustomPaint(painter: _Guilloche())),
                LayoutBuilder(
                  builder: (context, box) {
                    final u = box.maxWidth / 100;
                    return Padding(
                      padding: EdgeInsets.fromLTRB(u * 6, u * 5, u * 6, u * 5),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              MkLogo(height: u * 9, onDark: true),
                              const Spacer(),
                              MkTierChip(tier: tier, label: tierLabel, onTap: onTier),
                            ],
                          ),
                          const Spacer(),
                          Row(
                            children: [
                              _Chip(width: u * 12),
                              SizedBox(width: u * 3),
                              Icon(Icons.contactless_outlined, color: Colors.white70, size: u * 7),
                              const Spacer(),
                              GestureDetector(
                                onTap: onToggleBalance,
                                behavior: HitTestBehavior.opaque,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('POINTS', style: t.labelSmall?.copyWith(color: Colors.white54, letterSpacing: 1.4, fontSize: u * 2.6)),
                                    AnimatedSwitcher(
                                      duration: MkMotion.base,
                                      child: showBalance
                                          ? AnimatedPoints(
                                              key: const ValueKey('b'),
                                              value: points,
                                              format: formatPoints,
                                              style: t.titleLarge?.copyWith(color: MkColors.yellow500, fontWeight: FontWeight.w900, fontSize: u * 6),
                                            )
                                          : Text('••••', key: const ValueKey('h'), style: t.titleLarge?.copyWith(color: MkColors.yellow500, fontSize: u * 6)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: u * 3),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              digits,
                              textDirection: TextDirection.ltr,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                color: const Color(0xFFF1E9F8),
                                fontSize: u * 6.4,
                                fontWeight: FontWeight.w600,
                                letterSpacing: u * 0.9,
                                shadows: raised,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                          SizedBox(height: u * 2.5),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('MEMBER', style: t.labelSmall?.copyWith(color: Colors.white54, letterSpacing: 1.4, fontSize: u * 2.6)),
                                    Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: Colors.white, fontSize: u * 4, fontWeight: FontWeight.w700, letterSpacing: u * 0.4, shadows: raised),
                                    ),
                                  ],
                                ),
                              ),
                              // Brand mark: two overlapping Mukafaah coins.
                              SizedBox(
                                width: u * 16,
                                height: u * 10,
                                child: Stack(
                                  children: [
                                    PositionedDirectional(start: 0, top: 0, child: MkMCoin(size: u * 10)),
                                    PositionedDirectional(end: 0, top: 0, child: Opacity(opacity: 0.88, child: MkMCoin(size: u * 10))),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Gold EMV-style chip.
class _Chip extends StatelessWidget {
  const _Chip({required this.width});
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: width * 0.76,
      decoration: BoxDecoration(
        borderRadius: MkRadius.all(width * 0.16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE9A0), Color(0xFFE2B33A), Color(0xFFB8862B)],
        ),
      ),
      child: CustomPaint(painter: _ChipLines()),
    );
  }
}

class _ChipLines extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x997A5414)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    final w = size.width, h = size.height;
    canvas
      ..drawLine(Offset(0, h * 0.34), Offset(w * 0.32, h * 0.34), p)
      ..drawLine(Offset(0, h * 0.66), Offset(w * 0.32, h * 0.66), p)
      ..drawLine(Offset(w * 0.68, h * 0.34), Offset(w, h * 0.34), p)
      ..drawLine(Offset(w * 0.68, h * 0.66), Offset(w, h * 0.66), p)
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.32, h * 0.18, w * 0.68, h * 0.82), Radius.circular(w * 0.08)), p)
      ..drawLine(Offset(w * 0.5, 0), Offset(w * 0.5, h * 0.18), p)
      ..drawLine(Offset(w * 0.5, h * 0.82), Offset(w * 0.5, h), p);
  }

  @override
  bool shouldRepaint(_ChipLines old) => false;
}

/// Fine wavy security lines, like on a bank card. Painted once.
class _Guilloche extends CustomPainter {
  const _Guilloche();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = const Color(0x1FC9A8F0);
    for (var k = 0; k < 14; k++) {
      final path = Path();
      for (var x = 0.0; x <= size.width; x += 6) {
        final y = size.height * (0.15 + k * 0.055) + math.sin(x / size.width * math.pi * 3 + k * 0.5) * size.height * 0.07;
        x == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(path, p);
    }
    // A soft gold glow in the corner.
    canvas.drawCircle(
      Offset(size.width * 0.95, size.height * 0.05),
      size.width * 0.45,
      Paint()
        ..shader = RadialGradient(colors: [MkColors.yellow500.withValues(alpha: 0.16), MkColors.yellow500.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: Offset(size.width * 0.95, size.height * 0.05), radius: size.width * 0.45)),
    );
  }

  @override
  bool shouldRepaint(_Guilloche old) => false;
}
