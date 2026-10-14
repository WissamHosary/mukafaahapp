import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../../data/api.dart';
import '../start/start_screens.dart';

/// Centered card layout that works on phones and wide Windows screens.
class AuthFrame extends StatelessWidget {
  const AuthFrame({required this.child, this.onBack, super.key});
  final Widget child;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: onBack == null ? null : BackButton(onPressed: onBack),
        actions: const [LangToggle()],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(MkSpace.xl),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: child),
          ),
        ),
      ),
    );
  }
}

class OwnerLoginScreen extends ConsumerStatefulWidget {
  const OwnerLoginScreen({super.key});

  @override
  ConsumerState<OwnerLoginScreen> createState() => _OwnerLoginScreenState();
}

class _OwnerLoginScreenState extends ConsumerState<OwnerLoginScreen> {
  final _phone = TextEditingController();
  final _otpKey = GlobalKey<MkOtpFieldState>();
  OtpChallenge? _challenge;
  bool _busy = false;
  bool _error = false;
  int _left = 0;
  Timer? _timer;

  @override
  void dispose() {
    _phone.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer(int secs) {
    _left = secs;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _left = (_left - 1).clamp(0, 9999));
      if (_left == 0) t.cancel();
    });
  }

  Future<void> _request() async {
    final s = ref.read(stringsProvider);
    if (_phone.text.trim().length < 7 || _busy) return;
    setState(() => _busy = true);
    try {
      final ch = await ref.read(apiProvider).requestOtp(_phone.text.trim(), ref.read(localeProvider));
      setState(() {
        _challenge = ch;
        _error = false;
      });
      _startTimer(ch.resendInSec);
    } on ApiException catch (e) {
      if (mounted) MkToast.show(context, s.error(e.code), kind: MkToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify(String code) async {
    final s = ref.read(stringsProvider);
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).verifyOtp(_challenge!.id, code);
      await ref.read(sessionProvider.notifier).refreshOwner();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = true);
      _otpKey.currentState?.clear();
      MkToast.show(context, s.error(e.code), kind: MkToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final ch = _challenge;
    return AuthFrame(
      onBack: ch != null
          ? () => setState(() => _challenge = null)
          : () => ref.read(sessionProvider.notifier).switchMode(),
      child: AnimatedSwitcher(
        duration: MkMotion.base,
        child: ch == null
            ? Column(
                key: const ValueKey('phone'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: MkLogo(height: 90)),
                  const SizedBox(height: MkSpace.xl),
                  Text(s.phoneTitle, style: t.headlineMedium),
                  const SizedBox(height: MkSpace.xs),
                  Text(s.phoneBody, style: t.bodyLarge?.copyWith(color: MkColors.ink2)),
                  const SizedBox(height: MkSpace.xl),
                  MkPhoneField(controller: _phone, onSubmitted: (_) => _request()),
                  const SizedBox(height: MkSpace.lg),
                  MkButton(label: s.continueLabel, loading: _busy, onPressed: _request),
                ],
              )
            : Column(
                key: const ValueKey('otp'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(s.otpTitle, style: t.headlineMedium),
                  const SizedBox(height: MkSpace.xs),
                  Text(s.otpBody(_phone.text.length >= 4 ? _phone.text.substring(_phone.text.length - 4) : ''),
                      style: t.bodyLarge?.copyWith(color: MkColors.ink2)),
                  const SizedBox(height: MkSpace.xl),
                  MkOtpField(key: _otpKey, onCompleted: _verify, error: _error),
                  if (_busy) const Padding(padding: EdgeInsets.all(MkSpace.md), child: Center(child: CircularProgressIndicator())),
                  if (ch.devCode != null)
                    Container(
                      margin: const EdgeInsets.only(top: MkSpace.md),
                      padding: const EdgeInsets.all(MkSpace.sm),
                      decoration: BoxDecoration(color: MkColors.yellow50, borderRadius: MkRadius.all(MkRadius.md)),
                      child: Text('${s.devCode}: ${ch.devCode}', textAlign: TextAlign.center),
                    ),
                  const SizedBox(height: MkSpace.md),
                  Center(
                    child: _left > 0
                        ? Text(s.resendIn(_left), style: t.bodyMedium?.copyWith(color: MkColors.ink3))
                        : TextButton(onPressed: _request, child: Text(s.resend)),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Signed in, but no shop on this phone: shops are added by Mukafaah.
class OnboardScreen extends ConsumerWidget {
  const OnboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    return AuthFrame(
      onBack: () => ref.read(sessionProvider.notifier).ownerLogout(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MkEntrance(child: Text(s.tr('محلك مش على مكافأة بعد', "Your shop isn't on Mukafaah yet"), style: t.headlineMedium)),
          const SizedBox(height: MkSpace.md),
          Text(
            s.tr(
              'فريق مكافأة بيضيف المحلات. احكينا وبنضيف محلك على رقمك هيدا، وبعدها بتفوت عالتطبيق مباشرة.',
              'The Mukafaah team adds every shop. Contact us and we will add yours with this phone number; then you sign in here straight away.',
            ),
            style: t.bodyLarge?.copyWith(color: MkColors.ink2),
          ),
          const SizedBox(height: MkSpace.xl),
          MkButton(
            label: s.tr('جرّب مرة تانية', 'Check again'),
            icon: Icons.refresh_rounded,
            kind: MkButtonKind.accent,
            onPressed: () => ref.read(sessionProvider.notifier).refreshOwner(),
          ),
          const SizedBox(height: MkSpace.xs),
          MkButton(label: s.logout, kind: MkButtonKind.ghost, onPressed: () => ref.read(sessionProvider.notifier).ownerLogout()),
        ],
      ),
    );
  }
}
