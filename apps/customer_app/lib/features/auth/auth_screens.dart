import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../../data/api.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: MkColors.purple900,
      body: Center(child: MkEntrance(child: MkLogo(height: 150, onDark: true))),
    );
  }
}

class _LangToggle extends ConsumerWidget {
  const _LangToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeProvider);
    return TextButton(
      onPressed: () => ref.read(localeProvider.notifier).set(lang == 'ar' ? 'en' : 'ar'),
      style: TextButton.styleFrom(foregroundColor: Colors.white),
      child: Text(lang == 'ar' ? 'English' : 'العربية'),
    );
  }
}

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: MkSwirlBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(MkSpace.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Align(alignment: AlignmentDirectional.centerEnd, child: _LangToggle()),
                const Spacer(),
                const MkEntrance(child: Center(child: MkLogo(height: 130, onDark: true))),
                const SizedBox(height: MkSpace.xxl),
                MkEntrance(
                  index: 2,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      MkFloat(child: MkCoin(size: 46)),
                      SizedBox(width: MkSpace.md),
                      MkFloat(amplitude: 8, child: MkCoin(size: 62)),
                      SizedBox(width: MkSpace.md),
                      MkFloat(amplitude: 5, child: MkCoin(size: 38)),
                    ],
                  ),
                ),
                const Spacer(),
                MkEntrance(
                  index: 3,
                  child: Text(
                    s.welcomeTitle,
                    textAlign: TextAlign.center,
                    style: t.headlineMedium?.copyWith(color: Colors.white),
                  ),
                ),
                const SizedBox(height: MkSpace.sm),
                MkEntrance(
                  index: 4,
                  child: Text(
                    s.welcomeBody,
                    textAlign: TextAlign.center,
                    style: t.bodyLarge?.copyWith(color: const Color(0xFFD8CCE6)),
                  ),
                ),
                const SizedBox(height: MkSpace.xxl),
                MkEntrance(
                  index: 5,
                  child: MkButton(
                    label: s.getStarted,
                    kind: MkButtonKind.accent,
                    onPressed: () => context.go('/phone'),
                  ),
                ),
                if (AppConfig.isDev) ...[
                  const SizedBox(height: MkSpace.sm),
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
    );
  }
}

class _StepScaffold extends StatelessWidget {
  const _StepScaffold({required this.title, required this.body, required this.child, this.onBack});

  final String title;
  final String body;
  final Widget child;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: onBack == null ? null : BackButton(onPressed: onBack),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(MkSpace.xl, MkSpace.xs, MkSpace.xl, MkSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MkEntrance(child: Text(title, style: t.headlineMedium)),
              const SizedBox(height: MkSpace.xs),
              MkEntrance(index: 1, child: Text(body, style: t.bodyLarge?.copyWith(color: MkColors.ink2))),
              const SizedBox(height: MkSpace.xxl),
              MkEntrance(index: 2, child: child),
            ],
          ),
        ),
      ),
    );
  }
}

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
      title: s.phoneTitle,
      body: s.phoneBody,
      onBack: () => context.go('/welcome'),
      child: Column(
        children: [
          MkPhoneField(controller: _phone, onSubmitted: (_) => _submit()),
          const SizedBox(height: MkSpace.xl),
          ListenableBuilder(
            listenable: _phone,
            builder: (context, _) => MkButton(
              label: s.continueLabel,
              loading: _busy,
              onPressed: _phone.text.trim().length >= 7 ? _submit : null,
            ),
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
      final api = ref.read(apiProvider);
      final r = await api.verifyOtp(_challenge.id, code);
      var next = '/home';
      if (r.user.name == null || r.user.name!.isEmpty) {
        next = '/name';
      } else {
        final pre = await api.prePoints().catchError((_) => const PrePoints(total: 0, fromBusinesses: []));
        if (pre.total > 0) next = '/collect';
      }
      ref.read(authProvider.notifier).signedIn(r.user, next: next);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = true);
      _field.currentState?.clear();
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

class NameScreen extends ConsumerStatefulWidget {
  const NameScreen({super.key});

  @override
  ConsumerState<NameScreen> createState() => _NameScreenState();
}

class _NameScreenState extends ConsumerState<NameScreen> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _busy) return;
    final s = ref.read(stringsProvider);
    setState(() => _busy = true);
    try {
      final api = ref.read(apiProvider);
      final user = await api.updateProfile(name: name, locale: ref.read(localeProvider));
      ref.read(authProvider.notifier).updateUser(user);
      final pre = await api.prePoints().catchError((_) => const PrePoints(total: 0, fromBusinesses: []));
      if (mounted) context.go(pre.total > 0 ? '/collect' : '/home');
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
      title: s.nameTitle,
      body: s.nameBody,
      child: Column(
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(hintText: s.nameHint),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: MkSpace.xl),
          ListenableBuilder(
            listenable: _name,
            builder: (context, _) => MkButton(
              label: s.continueLabel,
              loading: _busy,
              onPressed: _name.text.trim().isEmpty ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}
