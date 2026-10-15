import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../../data/api.dart';
import '../lock/biometric.dart';
import 'google_auth.dart';

/// Shown for a moment while the saved session is checked (under the intro).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(backgroundColor: Color(0xFFFBFAFD));
}

/// Where a member lands once signed in and set up: collect waiting points
/// first if there are any, otherwise home. Offers fingerprint / Face ID once.
Future<String> landingAfterSignIn(WidgetRef ref) async {
  final pre = await ref.read(apiProvider).prePoints().catchError((_) => const PrePoints(total: 0, fromBusinesses: []));
  final landing = pre.total > 0 ? '/collect' : '/home';
  final bio = ref.read(biometricsProvider);
  if (!bio.asked && !bio.enabled && await bio.kind() != BioKind.none) return '/signup/unlock?next=$landing';
  return landing;
}

String _profileRoute(AppUser u) => u.isGoogle ? '/signup/name' : '/signup/profile';

class _LangToggle extends ConsumerWidget {
  const _LangToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeProvider);
    return TextButton(
      onPressed: () => ref.read(localeProvider.notifier).set(lang == 'ar' ? 'en' : 'ar'),
      style: TextButton.styleFrom(
        foregroundColor: MkColors.ink2,
        backgroundColor: Colors.white,
        shape: StadiumBorder(side: BorderSide(color: MkColors.line)),
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      child: Text(lang == 'ar' ? 'English' : 'العربية'),
    );
  }
}

// ---------------------------------------------------------------- Welcome

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

/// Google sign-in, used on the welcome and sign-in screens. Members who
/// already finished their profile go straight in.
Future<void> continueWithGoogle(BuildContext context, WidgetRef ref) async {
  final s = ref.read(stringsProvider);
  if (!GoogleAuth.configured) {
    MkToast.show(context, s.tr('التسجيل بحساب Google مش جاهز بعد. استعمل رقم تلفونك.', 'Google sign-in is not set up yet. Use your phone number.'));
    return;
  }
  try {
    final token = await GoogleAuth.idToken();
    if (token == null || !context.mounted) return;
    final r = await ref.read(apiProvider).signInWithGoogle(token, ref.read(localeProvider));
    if (r.user.needsProfile) {
      ref.read(authProvider.notifier).signedIn(r.user, next: '/signup/name?suggest=${Uri.encodeComponent(r.suggestedName ?? '')}');
    } else {
      ref.read(authProvider.notifier).signedIn(r.user, next: await landingAfterSignIn(ref));
    }
  } on ApiException catch (e) {
    if (context.mounted) MkToast.show(context, s.error(e.code), kind: MkToastKind.error);
  } on Object {
    if (context.mounted) {
      MkToast.show(context, s.tr('ما زبط التسجيل بـ Google. جرّب مرة تانية.', 'Google sign-in did not work. Try again.'), kind: MkToastKind.error);
    }
  }
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _google = false;

  Future<void> _withGoogle() async {
    setState(() => _google = true);
    try {
      await continueWithGoogle(context, ref);
    } finally {
      if (mounted) setState(() => _google = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    // Fixed to the screen on every phone: the animation takes whatever height
    // is left, so nothing ever needs scrolling.
    final short = MediaQuery.sizeOf(context).height < 700;
    return Scaffold(
      backgroundColor: MkColors.canvas,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(MkSpace.xl, MkSpace.xs, MkSpace.xl, short ? MkSpace.sm : MkSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  MkEntrance(child: MkLogo(height: short ? 54 : 72)),
                  const Spacer(),
                  const _LangToggle(),
                ],
              ),
              const Expanded(child: MkEntrance(index: 1, child: _OrbitHero())),
              MkEntrance(
                index: 2,
                child: Text(
                  s.tr('مكافآت من كل محل بتحبّه', 'Rewards from every shop you love'),
                  textAlign: TextAlign.center,
                  style: (short ? t.titleLarge : t.headlineSmall)?.copyWith(fontWeight: FontWeight.w800, color: MkColors.ink),
                ),
              ),
              const SizedBox(height: 4),
              MkEntrance(
                index: 3,
                child: Text(
                  s.tr('اجمع نقاط، افتح عروض وادفع أقل، كلّه بمحفظة وحدة.', 'Earn points, unlock offers and pay less, all in one wallet.'),
                  textAlign: TextAlign.center,
                  style: t.bodyMedium?.copyWith(color: MkColors.ink2),
                ),
              ),
              SizedBox(height: short ? MkSpace.sm : MkSpace.lg),
              MkEntrance(
                index: 4,
                child: MkButton(
                  label: s.tr('كمّل بحساب Google', 'Continue with Google'),
                  kind: MkButtonKind.secondary,
                  icon: Icons.mail_outline_rounded,
                  loading: _google,
                  onPressed: _withGoogle,
                ),
              ),
              const SizedBox(height: MkSpace.sm),
              MkEntrance(
                index: 5,
                child: MkButton(
                  label: s.tr('كمّل برقم التلفون', 'Continue with phone number'),
                  icon: Icons.smartphone_rounded,
                  onPressed: () => context.push('/phone'),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(s.tr('عندك حساب؟', 'Already have an account?'), style: t.bodyMedium?.copyWith(color: MkColors.ink2)),
                  TextButton(
                    onPressed: () => context.push('/signin'),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                    child: Text(s.tr('فوت', 'Sign in'), style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w800, color: MkColors.purple700)),
                  ),
                ],
              ),
              Text(
                s.tr('بالمتابعة بتوافق على الشروط وسياسة الخصوصية.', 'By continuing you agree to the Terms and Privacy Policy.'),
                textAlign: TextAlign.center,
                style: t.labelSmall?.copyWith(color: MkColors.ink3),
              ),
              if (AppConfig.isDev)
                Center(
                  child: MkDevServerButton(
                    load: () => ref.read(apiClientProvider).currentServer(),
                    save: (a) => ref.read(apiClientProvider).setDevServer(a),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The welcome animation: category bubbles orbit a 3D Mukafaah wallet card
/// (passing behind and in front of it) and keep sending points into it.
class _OrbitHero extends StatefulWidget {
  const _OrbitHero();

  @override
  State<_OrbitHero> createState() => _OrbitHeroState();
}

class _Fly {
  _Fly(this.from, this.amount, this.start);
  final Offset from;
  final int amount;
  final double start;
}

class _OrbitHeroState extends State<_OrbitHero> with SingleTickerProviderStateMixin {
  static const _bubbles = [
    (Color(0xFFB05A1E), Icons.local_cafe_rounded),
    (Color(0xFFC8463F), Icons.restaurant_rounded),
    (Color(0xFF7446A8), Icons.checkroom_rounded),
    (Color(0xFF2554C7), Icons.devices_rounded),
    (Color(0xFF23307A), Icons.fitness_center_rounded),
    (Color(0xFFC2477A), Icons.spa_rounded),
  ];
  static const _flyTime = 0.9;
  static const _amounts = [40, 60, 85, 120, 150];

  late final Ticker _ticker;
  final _rnd = math.Random();
  final List<_Fly> _flies = [];
  double _t = 0;
  double _lastFly = 0;
  double _bumpAt = -10;
  int _points = 2450;
  Size _size = Size.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => setState(() => _t = d.inMicroseconds / 1e6))..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  ({Offset at, double z}) _pos(int i, Size sz) {
    final a = _t * 0.45 + i * math.pi * 2 / _bubbles.length;
    return (at: Offset(sz.width / 2 + math.cos(a) * sz.width * 0.43, sz.height / 2 + math.sin(a) * sz.height * 0.3), z: math.sin(a));
  }

  void _step() {
    // Land finished flights in the card.
    _flies.removeWhere((f) {
      if (_t - f.start < _flyTime) return false;
      _points += f.amount;
      _bumpAt = _t;
      return true;
    });
    if (_t - _lastFly > 1.5 && _size != Size.zero) {
      _lastFly = _t;
      final front = [for (var i = 0; i < _bubbles.length; i++) if (_pos(i, _size).z > 0.2) i];
      if (front.isNotEmpty) {
        final i = front[_rnd.nextInt(front.length)];
        _flies.add(_Fly(_pos(i, _size).at, _amounts[_rnd.nextInt(_amounts.length)], _t));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    if (still && _ticker.isActive) _ticker.stop();
    final t = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, box) {
        final sz = Size(box.maxWidth, box.maxHeight);
        _size = sz;
        if (!still) _step();
        final cardW = math.min(sz.width * 0.6, sz.height * 0.6 * 1.58);
        final cardH = cardW / 1.58;
        final bubble = (sz.height * 0.2).clamp(34.0, 52.0);
        final bump = Curves.easeOut.transform(((_t - _bumpAt) / 0.5).clamp(0.0, 1.0));
        final bumpScale = 1 + 0.18 * math.sin(bump * math.pi);

        Widget bubbleAt(int i) {
          final p = _pos(i, sz);
          final scale = 0.72 + 0.32 * (p.z + 1) / 2;
          final (color, ic) = _bubbles[i];
          return Positioned(
            left: p.at.dx - bubble / 2,
            top: p.at.dy - bubble / 2,
            child: Opacity(
              opacity: 0.55 + 0.45 * (p.z + 1) / 2,
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: bubble,
                  height: bubble,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 14, offset: Offset(0, 6))],
                  ),
                  child: Icon(ic, color: Colors.white, size: bubble * 0.46),
                ),
              ),
            ),
          );
        }

        final order = [for (var i = 0; i < _bubbles.length; i++) i]..sort((a, b) => _pos(a, sz).z.compareTo(_pos(b, sz).z));
        final back = order.where((i) => _pos(i, sz).z <= 0);
        final front = order.where((i) => _pos(i, sz).z > 0);
        final center = Offset(sz.width / 2, sz.height / 2);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Orbit path with a soft golden glow.
            Center(
              child: Container(
                width: sz.width * 0.86,
                height: sz.height * 0.6,
                decoration: BoxDecoration(
                  shape: BoxShape.rectangle,
                  borderRadius: BorderRadius.all(Radius.elliptical(sz.width * 0.43, sz.height * 0.3)),
                  border: Border.all(color: MkColors.purple500.withValues(alpha: 0.22), width: 1.5),
                  gradient: RadialGradient(colors: [MkColors.yellow500.withValues(alpha: 0.18), MkColors.yellow500.withValues(alpha: 0)]),
                ),
              ),
            ),
            for (final i in back) bubbleAt(i),
            Center(
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0014)
                  ..rotateX(math.cos(_t * 0.55) * 0.16)
                  ..rotateY(math.sin(_t * 0.7) * 0.28),
                child: Container(
                  width: cardW,
                  height: cardH,
                  clipBehavior: Clip.antiAlias,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    borderRadius: MkRadius.all(20),
                    gradient: const RadialGradient(
                      center: Alignment.topRight,
                      radius: 1.6,
                      colors: [Color(0xFF8C5CC4), MkColors.purple700, MkColors.purple900],
                      stops: [0, 0.35, 0.7],
                    ),
                    boxShadow: const [BoxShadow(color: Color(0xCC2C123F), blurRadius: 40, offset: Offset(0, 22), spreadRadius: -18)],
                  ),
                  child: Stack(
                    children: [
                      // A light that follows the tilt.
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment(math.sin(_t * 0.7) * 1.2, -1.2),
                              radius: 1.1,
                              colors: [Colors.white.withValues(alpha: 0.26), Colors.white.withValues(alpha: 0)],
                            ),
                          ),
                        ),
                      ),
                      const Positioned(right: -22, bottom: -30, child: Opacity(opacity: 0.16, child: MkLogo(height: 74, markOnly: true))),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('Mukafaah', style: t.labelSmall?.copyWith(color: Colors.white70)),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(colors: [Color(0xFFFFE97A), MkColors.yellow500, Color(0xFFE5B800)]),
                                  borderRadius: MkRadius.all(MkRadius.pill),
                                ),
                                child: Text('Gold', style: t.labelSmall?.copyWith(color: MkColors.purple900, fontWeight: FontWeight.w900)),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Transform.scale(
                            scale: bumpScale,
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              formatPoints(_points),
                              textDirection: TextDirection.ltr,
                              style: t.headlineMedium?.copyWith(color: MkColors.yellow500, fontWeight: FontWeight.w900, height: 1),
                            ),
                          ),
                          Text('pts', style: t.labelSmall?.copyWith(color: Colors.white70)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            for (final i in front) bubbleAt(i),
            // "+120" chips flying from a shop into the wallet.
            for (final f in _flies)
              Builder(
                builder: (context) {
                  final p = Curves.easeInOutCubic.transform(((_t - f.start) / _flyTime).clamp(0.0, 1.0));
                  final at = Offset.lerp(f.from, center, p)! + Offset(0, -math.sin(p * math.pi) * 30);
                  return Positioned(
                    left: at.dx - 24,
                    top: at.dy - 12,
                    child: Opacity(
                      opacity: (1 - p * p).clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: 1 - 0.45 * p,
                        child: Container(
                          width: 48,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          decoration: BoxDecoration(color: MkColors.yellow500, borderRadius: MkRadius.all(MkRadius.pill), boxShadow: MkShadow.glow),
                          child: Text('+${f.amount}', style: t.labelSmall?.copyWith(color: MkColors.purple900, fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- Shared step layout

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({required this.title, required this.body, required this.child, this.step, this.onBack, this.bottom});

  final String title;
  final String body;
  final Widget child;

  /// 1-based step of 3, or null to hide the step dots.
  final int? step;
  final VoidCallback? onBack;

  /// Pinned under the content (the main button).
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: MkColors.canvas,
      appBar: AppBar(
        backgroundColor: MkColors.canvas,
        leading: onBack == null ? null : BackButton(onPressed: onBack),
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: step == null ? null : _StepDots(step: step!),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(MkSpace.xl, MkSpace.xs, MkSpace.xl, MkSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MkEntrance(child: Text(title, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
                    const SizedBox(height: MkSpace.xs),
                    MkEntrance(index: 1, child: Text(body, style: t.bodyLarge?.copyWith(color: MkColors.ink2))),
                    const SizedBox(height: MkSpace.xl),
                    MkEntrance(index: 2, child: child),
                  ],
                ),
              ),
            ),
            if (bottom != null)
              Padding(padding: const EdgeInsets.fromLTRB(MkSpace.xl, 0, MkSpace.xl, MkSpace.lg), child: bottom),
          ],
        ),
      ),
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 3; i++)
          AnimatedContainer(
            duration: MkMotion.base,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == step ? 26 : 18,
            height: 5,
            decoration: BoxDecoration(
              color: i <= step ? MkColors.purple900 : MkColors.line,
              borderRadius: MkRadius.all(3),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Phone, password and code

/// Why a WhatsApp code is being asked for.
enum OtpPurpose {
  /// A new number: the code creates the account, then a password is chosen.
  signUp,

  /// A member who never set a password: the code signs them in, then they choose one.
  firstPassword,

  /// "Forgot password": the code signs them in, then they choose a new one.
  reset,
}

class OtpArgs {
  const OtpArgs({required this.phone, required this.challenge, this.purpose = OtpPurpose.signUp});
  final String phone;
  final OtpChallenge challenge;
  final OtpPurpose purpose;
}

/// The short pass from the last WhatsApp code, used once to choose a password.
class PasswordPass extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? v) => state = v;
}

final passwordPassProvider = NotifierProvider<PasswordPass, String?>(PasswordPass.new);

/// Sends a WhatsApp code and opens the code screen.
Future<void> _sendCode(BuildContext context, WidgetRef ref, String phone, OtpPurpose purpose) async {
  final ch = await ref.read(apiProvider).requestOtp(phone, ref.read(localeProvider));
  if (!context.mounted) return;
  await context.push('/otp', extra: OtpArgs(phone: phone, challenge: ch, purpose: purpose));
}

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({this.signIn = false, super.key});

  /// Opened from "Already have an account? Sign in".
  final bool signIn;

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _phone = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = ref.read(stringsProvider);
    final digits = _phone.text.trim();
    if (digits.length < 7 || _busy) return;
    setState(() => _busy = true);
    try {
      final st = await ref.read(apiProvider).checkPhone(digits);
      if (!mounted) return;
      if (st.exists && st.hasPassword) {
        // Members who already chose a password just type it.
        await context.push('/password', extra: digits);
      } else {
        if (widget.signIn && !st.exists) {
          MkToast.show(context, s.tr('ما في حساب على هالرقم، رح نعملك واحد جديد', "No account on this number yet, we'll create one"));
        }
        await _sendCode(context, ref, digits, st.exists ? OtpPurpose.firstPassword : OtpPurpose.signUp);
      }
    } on ApiException catch (e) {
      if (mounted) MkToast.show(context, s.error(e.code), kind: MkToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return _StepScaffold(
      step: widget.signIn ? null : 1,
      title: widget.signIn ? s.tr('أهلا فيك من جديد', 'Welcome back') : s.tr('رقم تلفونك', 'Your phone number'),
      body: widget.signIn
          ? s.tr('اكتب رقمك، وبعدين كلمة السر.', 'Enter your number, then your password.')
          : s.tr('إذا رقم جديد، منبعتلك رمز على واتساب لنتأكد إنو إنت.', "If it's a new number, we'll send you a code on WhatsApp to make sure it's you."),
      onBack: () => context.canPop() ? context.pop() : context.go('/welcome'),
      bottom: ListenableBuilder(
        listenable: _phone,
        builder: (context, _) => MkButton(
          label: s.tr('كمّل', 'Continue'),
          loading: _busy,
          onPressed: _phone.text.trim().length >= 7 ? _submit : null,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MkPhoneField(controller: _phone, onSubmitted: (_) => _submit()),
          const SizedBox(height: MkSpace.md),
          const _WhatsAppNote(),
        ],
      ),
    );
  }
}

/// "Codes come on WhatsApp" note with the WhatsApp green.
class _WhatsAppNote extends ConsumerWidget {
  const _WhatsAppNote();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: const Color(0xFFE7F8EE), borderRadius: MkRadius.all(MkRadius.md)),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(color: Color(0xFF25D366), shape: BoxShape.circle),
            child: const Icon(Icons.chat_rounded, color: Colors.white, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              s.tr('رموز التحقق بتوصلك على واتساب، مش رسالة SMS.', 'Verification codes come on WhatsApp, not SMS.'),
              style: t.bodySmall?.copyWith(color: const Color(0xFF14532D), fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Already have an account?": phone number and password on one screen,
/// "Forgot password?" and Google underneath. No WhatsApp code is needed
/// unless the number has no password yet or the password is forgotten.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _phone = TextEditingController();
  final _pw = TextEditingController();
  bool _show = false;
  bool _busy = false;
  bool _sending = false;
  bool _google = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_phone, _pw]) {
      c.addListener(() => setState(() => _error = null));
    }
  }

  @override
  void dispose() {
    _phone.dispose();
    _pw.dispose();
    super.dispose();
  }

  String get _digits => _phone.text.trim();
  bool get _ready => _digits.length >= 7 && _pw.text.isNotEmpty;

  Future<void> _signIn() async {
    if (!_ready || _busy) return;
    final s = ref.read(stringsProvider);
    setState(() => _busy = true);
    try {
      final u = await ref.read(apiProvider).signInWithPassword(_digits, _pw.text);
      final next = u.needsProfile ? _profileRoute(u) : await landingAfterSignIn(ref);
      ref.read(authProvider.notifier).signedIn(u, next: next);
    } on ApiException catch (e) {
      if (!mounted) return;
      unawaited(HapticFeedback.heavyImpact());
      if (e.code == 'LOGIN_INVALID') {
        // A member from before passwords existed: one WhatsApp code, then they choose one.
        final st = await ref.read(apiProvider).checkPhone(_digits).catchError((_) => const PhoneStatus(exists: true, hasPassword: true));
        if (!mounted) return;
        if (!st.exists) {
          setState(() => _error = s.tr('ما في حساب على هالرقم. اعمل حساب جديد.', 'No account on this number. Create a new one.'));
          return;
        }
        if (!st.hasPassword) {
          setState(() => _error = s.tr('هالحساب ما إلو كلمة سر بعد. اضغط "نسيت كلمة السر" لتختار وحدة برمز واتساب.',
              'This account has no password yet. Tap "Forgot password?" to choose one with a WhatsApp code.'));
          return;
        }
      }
      setState(() => _error = s.error(e.code));
    } on Object {
      if (mounted) setState(() => _error = s.somethingWrong);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final s = ref.read(stringsProvider);
    if (_digits.length < 7) {
      setState(() => _error = s.tr('اكتب رقمك أول.', 'Type your phone number first.'));
      return;
    }
    setState(() => _sending = true);
    try {
      final st = await ref.read(apiProvider).checkPhone(_digits);
      if (!mounted) return;
      if (!st.exists) {
        setState(() => _error = s.tr('ما في حساب على هالرقم. اعمل حساب جديد.', 'No account on this number. Create a new one.'));
        return;
      }
      await _sendCode(context, ref, _digits, st.hasPassword ? OtpPurpose.reset : OtpPurpose.firstPassword);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = s.error(e.code));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _withGoogle() async {
    setState(() => _google = true);
    try {
      await continueWithGoogle(context, ref);
    } finally {
      if (mounted) setState(() => _google = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    return _StepScaffold(
      title: s.tr('أهلا فيك من جديد', 'Welcome back'),
      body: s.tr('فوت برقمك وكلمة السر.', 'Sign in with your phone number and password.'),
      onBack: () => context.canPop() ? context.pop() : context.go('/welcome'),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MkButton(label: s.tr('فوت', 'Sign in'), icon: Icons.login_rounded, loading: _busy, onPressed: _ready ? _signIn : null),
          const SizedBox(height: MkSpace.sm),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: MkSpace.sm),
                child: Text(s.tr('أو', 'or'), style: t.labelMedium?.copyWith(color: MkColors.ink3)),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: MkSpace.sm),
          MkButton(
            label: s.tr('فوت بحساب Google', 'Sign in with Google'),
            icon: Icons.mail_outline_rounded,
            kind: MkButtonKind.secondary,
            loading: _google,
            onPressed: _withGoogle,
          ),
          TextButton(
            onPressed: () => context.pushReplacement('/phone'),
            child: Text.rich(
              TextSpan(
                text: s.tr('جديد بمكافأة؟ ', 'New to Mukafaah? '),
                style: t.bodyMedium?.copyWith(color: MkColors.ink2),
                children: [TextSpan(text: s.tr('اعمل حساب', 'Create an account'), style: const TextStyle(fontWeight: FontWeight.w800, color: MkColors.purple700))],
              ),
            ),
          ),
        ],
      ),
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MkPhoneField(controller: _phone),
            const SizedBox(height: MkSpace.sm),
            TextField(
              controller: _pw,
              obscureText: !_show,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _signIn(),
              decoration: InputDecoration(
                hintText: s.tr('كلمة السر', 'Password'),
                prefixIcon: const Icon(Icons.lock_outline_rounded),
                suffixIcon: IconButton(
                  tooltip: _show ? s.tr('خبّي', 'Hide') : s.tr('بيّن', 'Show'),
                  onPressed: () => setState(() => _show = !_show),
                  icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                ),
              ),
            ),
            AnimatedSize(
              duration: MkMotion.base,
              child: _error == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: MkSpace.xs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline_rounded, size: 18, color: MkColors.danger),
                          const SizedBox(width: 6),
                          Expanded(child: Text(_error!, style: t.bodySmall?.copyWith(color: MkColors.danger, fontWeight: FontWeight.w600))),
                        ],
                      ),
                    ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: _sending ? null : _forgot,
                icon: _sending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.help_outline_rounded, size: 18),
                label: Text(s.tr('نسيت كلمة السر؟', 'Forgot password?'), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Members with a password: phone was typed on the previous screen.
class PasswordScreen extends ConsumerStatefulWidget {
  const PasswordScreen({required this.phone, super.key});
  final String phone;

  @override
  ConsumerState<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends ConsumerState<PasswordScreen> {
  final _pw = TextEditingController();
  bool _show = false;
  bool _busy = false;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_pw.text.isEmpty || _busy) return;
    final s = ref.read(stringsProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final u = await ref.read(apiProvider).signInWithPassword(widget.phone, _pw.text);
      final next = u.needsProfile ? _profileRoute(u) : await landingAfterSignIn(ref);
      ref.read(authProvider.notifier).signedIn(u, next: next);
    } on ApiException catch (e) {
      if (!mounted) return;
      unawaited(HapticFeedback.heavyImpact());
      setState(() => _error = s.error(e.code));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final s = ref.read(stringsProvider);
    setState(() => _sending = true);
    try {
      await _sendCode(context, ref, widget.phone, OtpPurpose.reset);
    } on ApiException catch (e) {
      if (mounted) MkToast.show(context, s.error(e.code), kind: MkToastKind.error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final p = widget.phone;
    return _StepScaffold(
      title: s.tr('كلمة السر', 'Your password'),
      body: s.tr('للرقم المنتهي بـ ${p.substring(p.length - 4)}', 'For the number ending ${p.substring(p.length - 4)}'),
      onBack: () => context.pop(),
      bottom: ListenableBuilder(
        listenable: _pw,
        builder: (context, _) => MkButton(
          label: s.tr('فوت', 'Sign in'),
          loading: _busy,
          onPressed: _pw.text.isNotEmpty ? _signIn : null,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _pw,
            autofocus: true,
            obscureText: !_show,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _signIn(),
            decoration: InputDecoration(
              hintText: s.tr('كلمة السر', 'Password'),
              errorText: _error,
              prefixIcon: const Icon(Icons.lock_outline_rounded),
              suffixIcon: IconButton(
                tooltip: _show ? s.tr('خبّي', 'Hide') : s.tr('بيّن', 'Show'),
                onPressed: () => setState(() => _show = !_show),
                icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded),
              ),
            ),
          ),
          const SizedBox(height: MkSpace.sm),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: _sending ? null : _forgot,
              icon: _sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.help_outline_rounded, size: 18),
              label: Text(s.tr('نسيت كلمة السر؟', 'Forgot password?'), style: t.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ),
          Text(
            s.tr('منبعتلك رمز على واتساب وبتختار كلمة سر جديدة.', "We'll send you a WhatsApp code and you choose a new password."),
            textAlign: TextAlign.end,
            style: t.bodySmall?.copyWith(color: MkColors.ink3),
          ),
        ],
      ),
    );
  }
}

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({required this.args, super.key});
  final OtpArgs args;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _field = GlobalKey<MkOtpFieldState>();
  late OtpChallenge _challenge = widget.args.challenge;
  late int _left = _challenge.resendInSec;
  Timer? _timer;
  bool _busy = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _tick();
  }

  void _tick() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left = (_left - 1).clamp(0, 9999));
      if (_left == 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _verify(String code) async {
    if (_busy) return;
    final s = ref.read(stringsProvider);
    setState(() {
      _busy = true;
      _error = false;
    });
    try {
      final r = await ref.read(apiProvider).verifyOtp(_challenge.id, code);
      final after = r.user.needsProfile ? _profileRoute(r.user) : await landingAfterSignIn(ref);
      final choose = widget.args.purpose == OtpPurpose.reset || r.needsPassword;
      ref.read(passwordPassProvider.notifier).set(choose ? r.passwordToken : null);
      final mode = widget.args.purpose == OtpPurpose.reset ? 'reset' : 'new';
      final next = choose ? '/signup/password?mode=$mode&then=${Uri.encodeComponent(after)}' : after;
      ref.read(authProvider.notifier).signedIn(r.user, next: next);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = true);
      _field.currentState?.clear();
      unawaited(HapticFeedback.heavyImpact());
      MkToast.show(context, s.error(e.code), kind: MkToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    final s = ref.read(stringsProvider);
    try {
      final ch = await ref.read(apiProvider).requestOtp(widget.args.phone, ref.read(localeProvider));
      setState(() {
        _challenge = ch;
        _left = ch.resendInSec;
      });
      _tick();
    } on ApiException catch (e) {
      if (mounted) MkToast.show(context, s.error(e.code), kind: MkToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final p = widget.args.phone;
    final last4 = p.length >= 4 ? p.substring(p.length - 4) : p;
    return _StepScaffold(
      step: widget.args.purpose == OtpPurpose.signUp ? 2 : null,
      title: widget.args.purpose == OtpPurpose.reset ? s.tr('غيّر كلمة السر', 'Reset your password') : s.otpTitle,
      body: s.otpBody(last4),
      onBack: () => context.pop(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MkOtpField(key: _field, onCompleted: _verify, error: _error),
          const SizedBox(height: MkSpace.lg),
          if (_busy) const Center(child: CircularProgressIndicator()),
          if (_challenge.devCode != null)
            Container(
              margin: const EdgeInsets.only(top: MkSpace.md),
              padding: const EdgeInsets.all(MkSpace.sm),
              decoration: BoxDecoration(color: MkColors.yellow50, borderRadius: MkRadius.all(MkRadius.md)),
              child: Text('${s.devCode}: ${_challenge.devCode}', textAlign: TextAlign.center),
            ),
          const SizedBox(height: MkSpace.md),
          Center(
            child: _left > 0
                ? Text(s.resendIn(_left), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: MkColors.ink3))
                : TextButton(onPressed: _resend, child: Text(s.tr('ابعت الرمز على واتساب من جديد', 'Send the WhatsApp code again'))),
          ),
        ],
      ),
    );
  }
}

/// Choose a password: right after a WhatsApp code (new member, first time or
/// "forgot password"), or from the account screen with the current one.
class SetPasswordScreen extends ConsumerStatefulWidget {
  const SetPasswordScreen({required this.mode, required this.then, super.key});

  /// new | reset | change
  final String mode;

  /// Where to go once it is saved.
  final String then;

  @override
  ConsumerState<SetPasswordScreen> createState() => _SetPasswordScreenState();
}

class _SetPasswordScreenState extends ConsumerState<SetPasswordScreen> {
  final _current = TextEditingController();
  final _pw = TextEditingController();
  final _again = TextEditingController();
  bool _show = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final c in [_current, _pw, _again]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _current.dispose();
    _pw.dispose();
    _again.dispose();
    super.dispose();
  }

  bool get _change => widget.mode == 'change';
  bool get _long => _pw.text.length >= 8;
  bool get _letter => RegExp('[A-Za-z]').hasMatch(_pw.text);
  bool get _digit => RegExp('[0-9]').hasMatch(_pw.text);
  bool get _same => _pw.text.isNotEmpty && _pw.text == _again.text;
  bool get _ready => _long && _letter && _digit && _same && (!_change || _current.text.isNotEmpty);

  Future<void> _save() async {
    if (!_ready || _busy) return;
    final s = ref.read(stringsProvider);
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).setPassword(
            _pw.text,
            passwordToken: _change ? null : ref.read(passwordPassProvider),
            currentPassword: _change ? _current.text : null,
          );
      ref.read(passwordPassProvider.notifier).set(null);
      final u = ref.read(authProvider).user;
      if (u != null) {
        ref.read(authProvider.notifier).updateUser(
              AppUser(
                id: u.id,
                name: u.name,
                phoneLast4: u.phoneLast4,
                email: u.email,
                gender: u.gender,
                age: u.age,
                signInMethod: u.signInMethod,
                needsProfile: u.needsProfile,
                hasPassword: true,
                avatarUrl: u.avatarUrl,
              ),
            );
      }
      if (!mounted) return;
      MkToast.show(
        context,
        _change ? s.tr('تغيّرت كلمة السر', 'Password changed') : s.tr('انحفظت كلمة السر', 'Password saved'),
        kind: MkToastKind.success,
      );
      context.go(widget.then);
    } on ApiException catch (e) {
      if (mounted) MkToast.show(context, s.error(e.code), kind: MkToastKind.error);
    } on Object {
      if (mounted) MkToast.show(context, s.somethingWrong, kind: MkToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    InputDecoration deco(String hint, IconData icon) => InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon),
          suffixIcon: IconButton(
            tooltip: _show ? s.tr('خبّي', 'Hide') : s.tr('بيّن', 'Show'),
            onPressed: () => setState(() => _show = !_show),
            icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded),
          ),
        );
    Widget rule(bool ok, String label) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              AnimatedSwitcher(
                duration: MkMotion.fast,
                child: Icon(
                  ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  key: ValueKey(ok),
                  size: 18,
                  color: ok ? MkColors.success : MkColors.ink3,
                ),
              ),
              const SizedBox(width: 8),
              Text(label, style: t.bodySmall?.copyWith(color: ok ? MkColors.ink : MkColors.ink3, fontWeight: FontWeight.w600)),
            ],
          ),
        );
    return PopScope(
      // After a WhatsApp code the member is signed in; choosing the password is the way forward.
      canPop: _change,
      child: _StepScaffold(
        title: switch (widget.mode) {
          'reset' => s.tr('كلمة سر جديدة', 'Choose a new password'),
          'change' => s.tr('غيّر كلمة السر', 'Change password'),
          _ => s.tr('اختار كلمة سر', 'Create a password'),
        },
        body: s.tr(
          'إذا طلعت من الحساب، بتفوت برقمك وكلمة السر. إذا نسيتها، منبعتلك رمز على واتساب.',
          'If you sign out, you come back with your number and this password. Forgot it? We send a WhatsApp code.',
        ),
        onBack: _change ? () => context.pop() : null,
        bottom: MkButton(label: s.tr('احفظ كلمة السر', 'Save password'), loading: _busy, onPressed: _ready ? _save : null),
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_change) ...[
                TextField(
                  controller: _current,
                  obscureText: !_show,
                  autofillHints: const [AutofillHints.password],
                  decoration: deco(s.tr('كلمة السر الحالية', 'Current password'), Icons.lock_clock_outlined),
                ),
                const SizedBox(height: MkSpace.sm),
              ],
              TextField(
                controller: _pw,
                autofocus: !_change,
                obscureText: !_show,
                autofillHints: const [AutofillHints.newPassword],
                decoration: deco(s.tr('كلمة السر', 'Password'), Icons.lock_outline_rounded),
              ),
              const SizedBox(height: MkSpace.sm),
              TextField(
                controller: _again,
                obscureText: !_show,
                autofillHints: const [AutofillHints.newPassword],
                onSubmitted: (_) => _save(),
                decoration: deco(s.tr('أعد كتابتها', 'Type it again'), Icons.lock_reset_rounded),
              ),
              const SizedBox(height: MkSpace.sm),
              rule(_long, s.tr('٨ أحرف أو أكتر', '8 characters or more')),
              rule(_letter && _digit, s.tr('أحرف وأرقام', 'Letters and numbers')),
              rule(_same, s.tr('الكلمتين متل بعض', 'Both match')),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Profile (phone members)

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _name = TextEditingController();
  final _age = TextEditingController();
  final _invite = TextEditingController();
  String? _gender;
  bool _inviteOpen = false;
  bool _busy = false;

  /// null = not checked yet, otherwise the result of the live check.
  ({bool valid, String? referrer})? _inviteCheck;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _age]) {
      c.addListener(() => setState(() {}));
    }
    _invite.addListener(_onInvite);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _age.dispose();
    _invite.dispose();
    super.dispose();
  }

  String get _code => _invite.text.trim().toUpperCase();
  int? get _ageN => int.tryParse(_age.text.trim());
  bool get _ageOk => _ageN != null && _ageN! >= 13 && _ageN! <= 100;
  bool get _ready =>
      _name.text.trim().length >= 2 && _ageOk && _gender != null && (_code.isEmpty || _inviteCheck?.valid == true);

  void _onInvite() {
    _debounce?.cancel();
    setState(() => _inviteCheck = null);
    if (_code.length < 5) return;
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final code = _code;
      try {
        final r = await ref.read(apiProvider).checkReferral(code);
        if (mounted && code == _code) setState(() => _inviteCheck = r);
      } on ApiException {
        if (mounted && code == _code) setState(() => _inviteCheck = (valid: false, referrer: null));
      }
    });
  }

  void _stepAge(int d) {
    final n = ((_ageN ?? 24) + d).clamp(13, 100);
    _age.text = '$n';
    unawaited(HapticFeedback.selectionClick());
  }

  Future<void> _review() async {
    final s = ref.read(stringsProvider);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) {
        final t = Theme.of(context).textTheme;
        Widget row(String k, String v) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: MkSpace.md, vertical: 12),
              child: Row(
                children: [
                  Text(k, style: t.bodyMedium?.copyWith(color: MkColors.ink3)),
                  const Spacer(),
                  Flexible(child: Text(v, textAlign: TextAlign.end, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w700))),
                ],
              ),
            );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(MkSpace.xl, 0, MkSpace.xl, MkSpace.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(s.tr('كل شي مزبوط؟', 'Is everything right?'), style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: MkSpace.md),
                DecoratedBox(
                  decoration: BoxDecoration(color: MkColors.canvas, borderRadius: MkRadius.all(MkRadius.lg)),
                  child: Column(
                    children: [
                      row(s.tr('الاسم', 'Name'), _name.text.trim()),
                      row(s.tr('العمر', 'Age'), '${_ageN ?? ''}'),
                      row(s.tr('الجنس', 'Gender'), _gender == 'MALE' ? s.tr('ذكر', 'Male') : s.tr('أنثى', 'Female')),
                      if (_inviteCheck?.valid == true) row(s.tr('دعاك', 'Invited by'), _inviteCheck!.referrer ?? _code),
                    ],
                  ),
                ),
                const SizedBox(height: MkSpace.lg),
                MkButton(
                  label: s.tr('أكّد واعمل الحساب', 'Confirm and create account'),
                  kind: MkButtonKind.accent,
                  onPressed: () => Navigator.of(context).pop(true),
                ),
                const SizedBox(height: MkSpace.xs),
                MkButton(label: s.tr('عدّل', 'Edit'), kind: MkButtonKind.ghost, onPressed: () => Navigator.of(context).pop(false)),
              ],
            ),
          ),
        );
      },
    );
    if (ok ?? false) await _save();
  }

  Future<void> _save() async {
    final s = ref.read(stringsProvider);
    setState(() => _busy = true);
    try {
      final user = await ref.read(apiProvider).completeProfile(
            name: _name.text.trim(),
            age: _ageN,
            gender: _gender,
            referralCode: _inviteCheck?.valid == true ? _code : null,
            locale: ref.read(localeProvider),
          );
      ref.read(authProvider.notifier).updateUser(user);
      if (mounted) context.go('/signup/done${_inviteCheck?.valid == true ? '?invitedBy=${Uri.encodeComponent(_inviteCheck!.referrer ?? '')}' : ''}');
    } on ApiException catch (e) {
      if (mounted) MkToast.show(context, s.error(e.code), kind: MkToastKind.error);
    } on Object {
      // Never fail silently: say so, so the member can try again.
      if (mounted) MkToast.show(context, s.somethingWrong, kind: MkToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final ageErr = _age.text.isNotEmpty && !_ageOk;
    Widget label(String text, [String? extra]) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text.rich(
            TextSpan(
              text: text,
              children: [if (extra != null) TextSpan(text: '  $extra', style: const TextStyle(color: MkColors.ink3, fontWeight: FontWeight.w500))],
            ),
            style: t.labelLarge?.copyWith(color: MkColors.ink2),
          ),
        );
    return _StepScaffold(
      step: 3,
      title: s.tr('خبّرنا عنك', 'Tell us about you'),
      body: s.tr('لتسلّم عليك المحلات وتبعتلك عروض بتناسبك.', 'So shops can greet you and send offers that fit.'),
      bottom: MkButton(label: s.tr('راجع وأكّد', 'Review and confirm'), loading: _busy, onPressed: _ready && !_busy ? _review : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label(s.tr('الاسم الكامل', 'Full name')),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            inputFormatters: [LengthLimitingTextInputFormatter(60)],
            decoration: InputDecoration(hintText: s.tr('مثلاً عمر خليل', 'e.g. Omar Khalil')),
          ),
          const SizedBox(height: MkSpace.lg),
          label(s.tr('العمر', 'Age')),
          Row(
            children: [
              _RoundButton(icon: Icons.remove_rounded, onTap: () => _stepAge(-1), label: s.tr('أصغر', 'Younger')),
              const SizedBox(width: MkSpace.xs),
              Expanded(
                child: TextField(
                  controller: _age,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  decoration: InputDecoration(hintText: '25', errorText: ageErr ? s.tr('لازم يكون عمرك ١٣ أو أكتر.', 'You need to be 13 or older.') : null),
                ),
              ),
              const SizedBox(width: MkSpace.xs),
              _RoundButton(icon: Icons.add_rounded, onTap: () => _stepAge(1), label: s.tr('أكبر', 'Older')),
            ],
          ),
          const SizedBox(height: MkSpace.lg),
          label(s.tr('الجنس', 'Gender')),
          Row(
            children: [
              Expanded(child: _GenderCard(icon: Icons.male_rounded, label: s.tr('ذكر', 'Male'), on: _gender == 'MALE', onTap: () => setState(() => _gender = 'MALE'))),
              const SizedBox(width: MkSpace.sm),
              Expanded(child: _GenderCard(icon: Icons.female_rounded, label: s.tr('أنثى', 'Female'), on: _gender == 'FEMALE', onTap: () => setState(() => _gender = 'FEMALE'))),
            ],
          ),
          const SizedBox(height: MkSpace.lg),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: MkRadius.all(MkRadius.lg),
              border: Border.all(color: MkColors.line, width: 1.4),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.card_giftcard_rounded, color: MkColors.purple700),
                  title: Text(s.tr('عندك رمز دعوة؟', 'Have an invite code?'), style: t.titleSmall),
                  subtitle: Text(s.tr('اختياري', 'Optional'), style: t.labelSmall?.copyWith(color: MkColors.ink3)),
                  trailing: AnimatedRotation(turns: _inviteOpen ? 0.5 : 0, duration: MkMotion.fast, child: const Icon(Icons.expand_more_rounded)),
                  onTap: () => setState(() => _inviteOpen = !_inviteOpen),
                ),
                AnimatedSize(
                  duration: MkMotion.base,
                  curve: Curves.easeOutCubic,
                  child: !_inviteOpen
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(MkSpace.md, 0, MkSpace.md, MkSpace.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextField(
                                controller: _invite,
                                textCapitalization: TextCapitalization.characters,
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                                  LengthLimitingTextInputFormatter(10),
                                ],
                                style: t.titleMedium?.copyWith(letterSpacing: 1.5, fontWeight: FontWeight.w700),
                                decoration: InputDecoration(
                                  hintText: 'LARA25',
                                  suffixIcon: _inviteCheck == null
                                      ? null
                                      : Icon(
                                          _inviteCheck!.valid ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                                          color: _inviteCheck!.valid ? MkColors.success : MkColors.danger,
                                        ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _inviteCheck == null
                                    ? s.tr('صاحبك اللي دعاك بياخد نقاط مكافأة.', 'The friend who invited you gets Mukafaah Points.')
                                    : _inviteCheck!.valid
                                        ? s.tr('${_inviteCheck!.referrer} دعاك. رح ياخد نقاط مكافأة.', '${_inviteCheck!.referrer} invited you. They get bonus points.')
                                        : s.tr('هالرمز مش موجود. صحّحه أو اتركه فاضي.', 'This code does not exist. Fix it or leave it empty.'),
                                style: t.labelMedium?.copyWith(
                                  color: _inviteCheck == null ? MkColors.ink3 : (_inviteCheck!.valid ? MkColors.success : MkColors.danger),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap, required this.label});
  final IconData icon;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: MkPressable(
          onTap: onTap,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: MkColors.purple50, borderRadius: MkRadius.all(MkRadius.md)),
            child: Icon(icon, color: MkColors.purple900),
          ),
        ),
      );
}

class _GenderCard extends StatelessWidget {
  const _GenderCard({required this.icon, required this.label, required this.on, required this.onTap});
  final IconData icon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: on,
      label: label,
      child: MkPressable(
        onTap: () {
          unawaited(HapticFeedback.selectionClick());
          onTap();
        },
        child: AnimatedContainer(
          duration: MkMotion.fast,
          height: 64,
          decoration: BoxDecoration(
            color: on ? MkColors.purple50 : Colors.white,
            borderRadius: MkRadius.all(MkRadius.lg),
            border: Border.all(color: on ? MkColors.purple900 : MkColors.line, width: on ? 2 : 1.4),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: MkColors.purple500),
              const SizedBox(width: MkSpace.xs),
              Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Name (Google members)

class CallMeScreen extends ConsumerStatefulWidget {
  const CallMeScreen({this.suggested, super.key});
  final String? suggested;

  @override
  ConsumerState<CallMeScreen> createState() => _CallMeScreenState();
}

class _CallMeScreenState extends ConsumerState<CallMeScreen> {
  late final _name = TextEditingController(text: widget.suggested ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2 || _busy) return;
    final s = ref.read(stringsProvider);
    setState(() => _busy = true);
    try {
      final user = await ref.read(apiProvider).completeProfile(name: name, locale: ref.read(localeProvider));
      ref.read(authProvider.notifier).updateUser(user);
      if (mounted) context.go('/signup/done');
    } on ApiException catch (e) {
      if (mounted) MkToast.show(context, s.error(e.code), kind: MkToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final email = ref.watch(authProvider).user?.email;
    return Scaffold(
      backgroundColor: MkColors.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MkSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: MkSpace.xl),
              MkEntrance(
                child: Center(
                  child: ListenableBuilder(
                    listenable: _name,
                    builder: (context, _) => MkMonogram(name: _name.text.trim().isEmpty ? 'M' : _name.text.trim(), size: 72),
                  ),
                ),
              ),
              if (email != null) ...[
                const SizedBox(height: MkSpace.xs),
                Text(email, textAlign: TextAlign.center, style: t.labelMedium?.copyWith(color: MkColors.ink3)),
              ],
              const SizedBox(height: MkSpace.lg),
              MkEntrance(
                index: 1,
                child: Text(
                  s.tr('شو بتحب نناديك؟', 'What should we call you?'),
                  textAlign: TextAlign.center,
                  style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: MkSpace.xs),
              MkEntrance(
                index: 2,
                child: Text(
                  s.tr('هيك رح تسلّم عليك المحلات والتطبيق.', 'This is how shops and the app will greet you.'),
                  textAlign: TextAlign.center,
                  style: t.bodyLarge?.copyWith(color: MkColors.ink2),
                ),
              ),
              const SizedBox(height: MkSpace.xl),
              MkEntrance(
                index: 3,
                child: TextField(
                  controller: _name,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.words,
                  inputFormatters: [LengthLimitingTextInputFormatter(60)],
                  style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                  decoration: InputDecoration(hintText: s.tr('اسمك', 'Your name')),
                  onSubmitted: (_) => _save(),
                ),
              ),
              const Spacer(),
              ListenableBuilder(
                listenable: _name,
                builder: (context, _) => MkButton(
                  label: s.continueLabel,
                  loading: _busy,
                  onPressed: _name.text.trim().length >= 2 ? _save : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Account ready

class SignupDoneScreen extends ConsumerStatefulWidget {
  const SignupDoneScreen({this.invitedBy, super.key});
  final String? invitedBy;

  @override
  ConsumerState<SignupDoneScreen> createState() => _SignupDoneScreenState();
}

class _SignupDoneScreenState extends ConsumerState<SignupDoneScreen> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(HapticFeedback.mediumImpact());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    setState(() => _busy = true);
    final next = await landingAfterSignIn(ref);
    if (mounted) context.go(next);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final name = (ref.watch(authProvider).user?.name ?? '').trim().split(RegExp(r'\s+')).first;
    final joinPoints = ref.watch(mukafaahProvider).value?.rules.where((r) => r.code == 'SIGNUP').firstOrNull?.points;
    return Scaffold(
      backgroundColor: MkColors.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MkSpace.xl),
          child: Column(
            children: [
              const Spacer(),
              SizedBox.square(
                dimension: 180,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, child) => CustomPaint(painter: _RingsPainter(_c.value), child: child),
                  child: Center(
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.2, end: 1),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.elasticOut,
                      builder: (context, v, child) => Transform.scale(scale: v, child: child),
                      child: Container(
                        width: 110,
                        height: 110,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(center: Alignment(-0.3, -0.4), colors: [Color(0xFFFFF2A6), MkColors.yellow500, Color(0xFFD9AE00)], stops: [0, 0.45, 1]),
                        ),
                        child: Text(
                          joinPoints == null ? '' : '+${formatPoints(joinPoints)}',
                          style: t.headlineSmall?.copyWith(color: MkColors.purple900, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: MkSpace.lg),
              MkEntrance(
                index: 1,
                child: Text(
                  name.isEmpty ? s.tr('أهلا فيك بمكافأة', 'Welcome to Mukafaah') : s.tr('أهلا فيك بمكافأة يا $name', 'Welcome to Mukafaah, $name'),
                  textAlign: TextAlign.center,
                  style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: MkSpace.xs),
              MkEntrance(
                index: 2,
                child: Text(
                  s.tr('محفظتك جاهزة. وهيدي هدية صغيرة لتبلّش.', "Your wallet is ready. Here's a little something to start."),
                  textAlign: TextAlign.center,
                  style: t.bodyLarge?.copyWith(color: MkColors.ink2),
                ),
              ),
              const SizedBox(height: MkSpace.md),
              if (joinPoints != null)
                _Pill(text: s.tr('${formatPoints(joinPoints)} نقطة مكافأة لأنك انضميت', '${formatPoints(joinPoints)} Mukafaah Points for joining')),
              if ((widget.invitedBy ?? '').isNotEmpty)
                _Pill(text: s.tr('${widget.invitedBy} أخد نقاط لأنو دعاك', '${widget.invitedBy} got points for inviting you')),
              const Spacer(),
              MkButton(label: s.continueLabel, loading: _busy, onPressed: _next),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: MkColors.successBg, borderRadius: MkRadius.all(MkRadius.pill)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_rounded, size: 16, color: MkColors.success),
            const SizedBox(width: 6),
            Flexible(child: Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: MkColors.success, fontWeight: FontWeight.w700))),
          ],
        ),
      );
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    for (final k in [t, (t + 0.5) % 1]) {
      canvas.drawCircle(
        c,
        size.width * (0.3 + 0.32 * k),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = MkColors.yellow500.withValues(alpha: (1 - k) * 0.8),
      );
    }
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t;
}

// ---------------------------------------------------------------- Fingerprint / Face ID offer

class UnlockOfferScreen extends ConsumerStatefulWidget {
  const UnlockOfferScreen({required this.next, super.key});
  final String next;

  @override
  ConsumerState<UnlockOfferScreen> createState() => _UnlockOfferScreenState();
}

class _UnlockOfferScreenState extends ConsumerState<UnlockOfferScreen> {
  bool _busy = false;

  Future<void> _enable() async {
    final s = ref.read(stringsProvider);
    final bio = ref.read(biometricsProvider);
    setState(() => _busy = true);
    final ok = await bio.check(s.tr('شغّل الفتح بالبصمة أو الوجه', 'Turn on fingerprint or Face ID unlock'));
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    await bio.setEnabled(true);
    if (!mounted) return;
    MkToast.show(context, s.tr('تشغّل الفتح السريع', 'Quick unlock is on'), kind: MkToastKind.success);
    context.go(widget.next);
  }

  Future<void> _skip() async {
    await ref.read(biometricsProvider).markAsked();
    if (mounted) context.go(widget.next);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final face = ref.watch(bioKindProvider).value == BioKind.face;
    Widget point(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_rounded, size: 20, color: MkColors.success),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: t.bodyMedium?.copyWith(color: MkColors.ink2))),
            ],
          ),
        );
    return Scaffold(
      backgroundColor: MkColors.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MkSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              MkEntrance(
                child: Center(
                  child: MkFloat(
                    child: Container(
                      width: 128,
                      height: 128,
                      decoration: BoxDecoration(color: MkColors.purple50, borderRadius: MkRadius.all(40)),
                      child: Icon(face ? Icons.face : Icons.fingerprint, size: 72, color: MkColors.purple900),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: MkSpace.xl),
              MkEntrance(
                index: 1,
                child: Text(
                  face ? s.tr('افتح محفظتك بـ Face ID', 'Open your wallet with Face ID') : s.tr('افتح محفظتك ببصمتك', 'Open your wallet with your fingerprint'),
                  textAlign: TextAlign.center,
                  style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: MkSpace.xs),
              MkEntrance(
                index: 2,
                child: Text(
                  s.tr('المرة الجاية، لمسة أو نظرة وبتفوت.', 'Next time, one touch or glance and you are in.'),
                  textAlign: TextAlign.center,
                  style: t.bodyLarge?.copyWith(color: MkColors.ink2),
                ),
              ),
              const SizedBox(height: MkSpace.lg),
              MkEntrance(
                index: 3,
                child: Column(
                  children: [
                    point(s.tr('ما في رمز تكتبه كل ما تفتح التطبيق.', 'No code to type every time you open the app.')),
                    point(s.tr('إذا حدا تاني مسك تلفونك، نقاطك بتضل مقفولة.', 'If someone else picks up your phone, your points stay locked.')),
                    point(s.tr('بصمتك أو وجهك ما بيطلعوا من تلفونك أبداً.', 'Your fingerprint or face never leaves your phone.')),
                  ],
                ),
              ),
              const Spacer(),
              MkButton(
                label: face ? s.tr('استعمل Face ID', 'Use Face ID') : s.tr('استعمل البصمة', 'Use fingerprint'),
                icon: face ? Icons.face : Icons.fingerprint,
                loading: _busy,
                onPressed: _enable,
              ),
              const SizedBox(height: MkSpace.xs),
              MkButton(label: s.tr('مش هلّق', 'Not now'), kind: MkButtonKind.ghost, onPressed: _busy ? null : _skip),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lets the account screen show and change the quick unlock setting.
Future<void> toggleQuickUnlock(BuildContext context, WidgetRef ref, bool on) async {
  final s = ref.read(stringsProvider);
  final bio = ref.read(biometricsProvider);
  if (!on) {
    await bio.setEnabled(false);
    return;
  }
  if (await bio.kind() == BioKind.none) {
    if (context.mounted) {
      MkToast.show(context, s.tr('ضيف بصمة أو وجه بإعدادات تلفونك أوّل.', "Add a fingerprint or face in your phone's settings first."));
    }
    return;
  }
  if (await bio.check(s.tr('شغّل الفتح السريع', 'Turn on quick unlock'))) await bio.setEnabled(true);
}
