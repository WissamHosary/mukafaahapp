import 'dart:async';

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

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _google = false;

  Future<void> _withGoogle() async {
    final s = ref.read(stringsProvider);
    if (!GoogleAuth.configured) {
      MkToast.show(context, s.tr('التسجيل بحساب Google مش جاهز بعد. استعمل رقم تلفونك.', 'Google sign-in is not set up yet. Use your phone number.'));
      return;
    }
    setState(() => _google = true);
    try {
      final token = await GoogleAuth.idToken();
      if (token == null || !mounted) return;
      final r = await ref.read(apiProvider).signInWithGoogle(token, ref.read(localeProvider));
      if (r.user.needsProfile) {
        ref.read(authProvider.notifier).signedIn(r.user, next: '/signup/name?suggest=${Uri.encodeComponent(r.suggestedName ?? '')}');
      } else {
        ref.read(authProvider.notifier).signedIn(r.user, next: await landingAfterSignIn(ref));
      }
    } on ApiException catch (e) {
      if (mounted) MkToast.show(context, s.error(e.code), kind: MkToastKind.error);
    } on Object {
      if (mounted) MkToast.show(context, s.tr('ما زبط التسجيل بـ Google. جرّب مرة تانية.', 'Google sign-in did not work. Try again.'), kind: MkToastKind.error);
    } finally {
      if (mounted) setState(() => _google = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: MkColors.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(MkSpace.xl, MkSpace.sm, MkSpace.xl, MkSpace.lg),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - MkSpace.sm - MkSpace.lg),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(alignment: AlignmentDirectional.centerEnd, child: _LangToggle()),
                    const MkEntrance(child: Center(child: MkLogo(height: 104))),
                    const SizedBox(height: MkSpace.md),
                    const MkEntrance(index: 1, child: _WalletHero()),
                    const SizedBox(height: MkSpace.lg),
                    MkEntrance(
                      index: 2,
                      child: Text(
                        s.tr('مكافآت من كل محل بتحبّه', 'Rewards from every shop you love'),
                        textAlign: TextAlign.center,
                        style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: MkColors.ink),
                      ),
                    ),
                    const SizedBox(height: MkSpace.xs),
                    MkEntrance(
                      index: 3,
                      child: Text(
                        s.tr('اجمع نقاط، افتح عروض وادفع أقل، كلّه بمحفظة وحدة.', 'Earn points, unlock offers and pay less, all in one wallet.'),
                        textAlign: TextAlign.center,
                        style: t.bodyLarge?.copyWith(color: MkColors.ink2),
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(height: MkSpace.lg),
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
                    const SizedBox(height: MkSpace.sm),
                    Text(
                      s.tr('بالمتابعة بتوافق على الشروط وسياسة الخصوصية.', 'By continuing you agree to the Terms and Privacy Policy.'),
                      textAlign: TextAlign.center,
                      style: t.labelSmall?.copyWith(color: MkColors.ink3),
                    ),
                    if (AppConfig.isDev) ...[
                      const SizedBox(height: MkSpace.xs),
                      MkDevServerButton(
                        load: () => ref.read(apiClientProvider).currentServer(),
                        save: (a) => ref.read(apiClientProvider).setDevServer(a),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Two tilted wallet cards and floating coins.
class _WalletHero extends StatelessWidget {
  const _WalletHero();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SizedBox(
      height: 190,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Transform.translate(
            offset: const Offset(28, -10),
            child: Transform.rotate(
              angle: 0.12,
              child: Container(
                width: 230,
                height: 140,
                decoration: BoxDecoration(color: MkColors.yellow500, borderRadius: MkRadius.all(22)),
              ),
            ),
          ),
          MkFloat(
            child: Transform.rotate(
              angle: -0.1,
              child: Container(
                width: 236,
                height: 146,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: MkRadius.all(22),
                  gradient: const RadialGradient(
                    center: Alignment.topRight,
                    radius: 1.4,
                    colors: [MkColors.purple500, MkColors.purple900],
                    stops: [0, 0.62],
                  ),
                  boxShadow: MkShadow.lifted,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mukafaah', style: t.labelMedium?.copyWith(color: Colors.white70)),
                    const Spacer(),
                    Text('2,450', style: t.headlineMedium?.copyWith(color: MkColors.yellow500, fontWeight: FontWeight.w900)),
                    Text('Gold · 7 shops', style: t.labelSmall?.copyWith(color: Colors.white70)),
                  ],
                ),
              ),
            ),
          ),
          const PositionedDirectional(start: 8, top: 14, child: MkFloat(amplitude: 8, child: MkCoin(size: 38))),
          const PositionedDirectional(end: 14, bottom: 4, child: MkFloat(amplitude: 5, child: MkCoin(size: 30))),
        ],
      ),
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

// ---------------------------------------------------------------- Phone and code

class OtpArgs {
  const OtpArgs({required this.phone, required this.challenge});
  final String phone;
  final OtpChallenge challenge;
}

class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

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
      final ch = await ref.read(apiProvider).requestOtp(digits, ref.read(localeProvider));
      if (!mounted) return;
      await context.push('/otp', extra: OtpArgs(phone: digits, challenge: ch));
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
      step: 1,
      title: s.tr('رقم تلفونك', 'Your phone number'),
      body: s.tr('رح نبعتلك رمز من ٦ أرقام لنتأكد إنو إنت.', "We'll text you a 6-digit code to make sure it's you."),
      onBack: () => context.canPop() ? context.pop() : context.go('/welcome'),
      bottom: ListenableBuilder(
        listenable: _phone,
        builder: (context, _) => MkButton(
          label: s.tr('ابعت الرمز', 'Send code'),
          loading: _busy,
          onPressed: _phone.text.trim().length >= 7 ? _submit : null,
        ),
      ),
      child: MkPhoneField(controller: _phone, onSubmitted: (_) => _submit()),
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
      final next = r.user.needsProfile ? _profileRoute(r.user) : await landingAfterSignIn(ref);
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
      step: 2,
      title: s.otpTitle,
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
                : TextButton(onPressed: _resend, child: Text(s.resend)),
          ),
        ],
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
