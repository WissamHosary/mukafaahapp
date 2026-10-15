import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../common/common.dart';

/// Centre tab, one screen with no scrolling: the member card (balance, phone
/// number, tier, transfer), invite code, Mukafaah Points and the customer's
/// own member QR. The QR is created once
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

    final memberCode = qr.value?.memberCode ?? '';
    // The number they signed up with; Google members without one see their member code.
    final cardNumber = (user?.phone?.isNotEmpty ?? false)
        ? user!.phone!
        : (user?.phoneLast4 != null ? '•••• ${user!.phoneLast4}' : (memberCode.isEmpty ? '•••• •••• ••••' : _groups(memberCode)));

    Future<void> copy(String text) async {
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) MkToast.show(context, s.copied, kind: MkToastKind.success);
    }

    return Scaffold(
      appBar: AppBar(title: Text(s.wallet), centerTitle: true, automaticallyImplyLeading: false, toolbarHeight: 48),
      // One screen, no scrolling: the card, two small tiles and the QR share
      // the height, and the QR takes whatever is left (it shrinks on small phones).
      body: LayoutBuilder(
        builder: (context, box) {
          const side = MkSpace.lg;
          final w = box.maxWidth - side * 2;
          final cardW = math.min(w, box.maxHeight * 0.4 * 85.6 / 54);
          return Padding(
            padding: const EdgeInsets.fromLTRB(side, 2, side, MkSpace.sm),
            child: Column(
              children: [
                MkEntrance(
                  child: SizedBox(
                    width: cardW,
                    child: _MemberCard(
                      name: name.isEmpty ? s.appName : name,
                      number: cardNumber,
                      tier: tier,
                      tierLabel: s.tier(tier),
                      points: home?.balancePoints ?? 0,
                      showBalance: _showBalance,
                      onToggleBalance: () => setState(() => _showBalance = !_showBalance),
                      onTier: () => context.push('/tier'),
                      transferLabel: s.transferPoints,
                      onTransfer: () => context.push('/transfer'),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                MkEntrance(
                  index: 1,
                  child: Row(
                    children: [
                      Expanded(
                        child: _MiniTile(
                          leading: const Icon(Icons.card_giftcard_rounded, size: 20, color: MkColors.purple700),
                          label: s.referralNumber,
                          value: home?.referralCode ?? '—',
                          trailing: const Icon(Icons.copy_rounded, size: 15, color: MkColors.ink3),
                          onTap: home?.referralCode == null ? null : () => copy(home!.referralCode!),
                        ),
                      ),
                      const SizedBox(width: MkSpace.sm),
                      Expanded(
                        child: _MiniTile(
                          leading: const MkCoin(size: 26),
                          label: s.tr('نقاط مكافأة', 'Mukafaah Points'),
                          value: formatPoints(wallet?.mukafaahPoints ?? 0),
                          gold: true,
                          onTap: () => context.push('/mukafaah'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // ---------- Member QR: fills the rest of the screen ----------
                Expanded(
                  child: MkEntrance(
                    index: 2,
                    child: LayoutBuilder(
                      builder: (context, area) {
                        const frame = 10.0 + 10.0; // gold ring + white inset
                        const caption = 34.0;
                        final q = math.max(120.0, math.min(260.0, math.min(area.maxWidth, area.maxHeight - caption) - frame * 2));
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                borderRadius: MkRadius.all(30),
                                gradient: const SweepGradient(
                                  colors: [MkColors.yellow500, Color(0xFFE0A800), MkColors.purple500, MkColors.purple900, MkColors.yellow500],
                                ),
                                boxShadow: const [BoxShadow(color: Color(0x332C123F), blurRadius: 26, offset: Offset(0, 12))],
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: MkRadius.all(23)),
                                child: AnimatedSwitcher(
                                  duration: MkMotion.slow,
                                  switchInCurve: MkMotion.emphasized,
                                  transitionBuilder: (child, a) => FadeTransition(
                                    opacity: a,
                                    child: ScaleTransition(scale: Tween<double>(begin: 0.9, end: 1).animate(a), child: child),
                                  ),
                                  child: qr.when(
                                    data: (v) => MkQr(key: ValueKey(v.payload), data: v.payload, size: q),
                                    loading: () => SizedBox.square(key: const ValueKey('l'), dimension: q, child: const Center(child: CircularProgressIndicator())),
                                    error: (e, _) => SizedBox.square(
                                      key: const ValueKey('e'),
                                      dimension: q,
                                      child: Center(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.wifi_off_rounded, color: MkColors.ink3, size: 30),
                                            const SizedBox(height: MkSpace.xs),
                                            Text(errorText(s, e), textAlign: TextAlign.center, maxLines: 3, style: t.bodySmall?.copyWith(color: MkColors.ink2)),
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
                            const SizedBox(height: 10),
                            GestureDetector(
                              onTap: memberCode.isEmpty ? null : () => copy(memberCode),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.verified_user_rounded, size: 15, color: MkColors.success),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      s.tr('اعرضه للكاشير مع كل شراء', 'Show it at the cashier with every purchase'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: t.bodySmall?.copyWith(color: MkColors.ink3),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Small tile under the card: invite code, Mukafaah Points.
class _MiniTile extends StatelessWidget {
  const _MiniTile({required this.leading, required this.label, required this.value, this.trailing, this.onTap, this.gold = false});

  final Widget leading;
  final String label;
  final String value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool gold;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: onTap != null,
      label: '$label $value',
      child: MkPressable(
        onTap: onTap,
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: gold ? null : Colors.white,
            gradient: gold ? const LinearGradient(colors: [MkColors.yellow50, Color(0xFFFFF0A8)]) : null,
            borderRadius: MkRadius.all(MkRadius.lg),
            boxShadow: MkShadow.soft,
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.labelSmall?.copyWith(color: MkColors.ink3)),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 0.6, color: MkColors.purple900),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
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

/// The member card, drawn like a real bank card (85.6 x 54 mm): deep purple
/// with a fine guilloche pattern, a gold chip, contactless mark, the member
/// member's phone number in raised digits, a Transfer button, and two Mukafaah coins as the brand mark.
class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.name,
    required this.number,
    required this.tier,
    required this.tierLabel,
    required this.points,
    required this.showBalance,
    required this.onToggleBalance,
    required this.onTier,
    required this.transferLabel,
    required this.onTransfer,
  });

  final String name;

  /// The member's phone number, printed like a card number.
  final String number;
  final String transferLabel;
  final VoidCallback onTransfer;
  final String tier;
  final String tierLabel;
  final int points;
  final bool showBalance;
  final VoidCallback onToggleBalance;
  final VoidCallback onTier;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
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
                          Row(
                            children: [
                              Expanded(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Text(
                                    number,
                                    textDirection: TextDirection.ltr,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      color: const Color(0xFFF1E9F8),
                                      fontSize: u * 5.6,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: u * 0.5,
                                      shadows: raised,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: u * 2),
                              // Transfer points, right on the card.
                              Semantics(
                                button: true,
                                label: transferLabel,
                                child: MkPressable(
                                  onTap: onTransfer,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(horizontal: u * 3, vertical: u * 1.6),
                                    decoration: BoxDecoration(
                                      color: MkColors.yellow500,
                                      borderRadius: MkRadius.all(MkRadius.pill),
                                      boxShadow: const [BoxShadow(color: Color(0x66FBD404), blurRadius: 12, offset: Offset(0, 3))],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.swap_horiz_rounded, size: u * 4.6, color: MkColors.purple900),
                                        SizedBox(width: u * 1.2),
                                        Text(
                                          transferLabel,
                                          style: TextStyle(color: MkColors.purple900, fontWeight: FontWeight.w800, fontSize: u * 3.4),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
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
