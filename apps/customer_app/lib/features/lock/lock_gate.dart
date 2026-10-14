import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import 'biometric.dart';

/// Locks the wallet behind fingerprint / Face ID when the member turned it on:
/// every time the app opens, and when they come back after more than
/// [_awayLimit] in another app. The app stays loaded underneath, so unlocking
/// is instant.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  static const _awayLimit = Duration(seconds: 30);

  bool _locked = false;
  bool _decided = false;
  bool _built = false;
  DateTime? _leftAt;

  void _set(VoidCallback fn) => _built && mounted ? setState(fn) : fn();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listenManual<AuthState>(authProvider, (prev, next) {
      if (next.status == AuthStatus.signedOut) {
        _set(() => _locked = false);
        _decided = true;
        return;
      }
      // Cold start: lock as soon as we know someone is signed in.
      if (!_decided && next.status == AuthStatus.signedIn) {
        _decided = true;
        if (ref.read(biometricsProvider).enabled) _set(() => _locked = true);
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _leftAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (left == null || _locked) return;
      final signedIn = ref.read(authProvider).status == AuthStatus.signedIn;
      if (signedIn && ref.read(biometricsProvider).enabled && DateTime.now().difference(left) > _awayLimit) {
        _set(() => _locked = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _built = true;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Hidden from touch and screen readers while locked.
        ExcludeSemantics(excluding: _locked, child: IgnorePointer(ignoring: _locked, child: widget.child)),
        if (_locked) _LockScreen(onUnlocked: () => _set(() => _locked = false)),
      ],
    );
  }
}

class _LockScreen extends ConsumerStatefulWidget {
  const _LockScreen({required this.onUnlocked});
  final VoidCallback onUnlocked;

  @override
  ConsumerState<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<_LockScreen> {
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    // Ask straight away, but not on top of the opening animation.
    if (MkIntroGate.playing.value) {
      MkIntroGate.playing.addListener(_afterIntro);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
    }
  }

  void _afterIntro() {
    if (MkIntroGate.playing.value) return;
    MkIntroGate.playing.removeListener(_afterIntro);
    if (mounted) unawaited(_unlock());
  }

  @override
  void dispose() {
    MkIntroGate.playing.removeListener(_afterIntro);
    super.dispose();
  }

  Future<void> _unlock() async {
    if (_busy || !mounted) return;
    final s = ref.read(stringsProvider);
    setState(() => _busy = true);
    final ok = await ref.read(biometricsProvider).check(s.tr('افتح محفظة مكافأة', 'Unlock your Mukafaah wallet'));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failed = !ok;
    });
    if (ok) {
      unawaited(HapticFeedback.lightImpact());
      widget.onUnlocked();
    }
  }

  Future<void> _signInAgain() async {
    await ref.read(authProvider.notifier).logout();
    widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final user = ref.watch(authProvider).user;
    final first = (user?.name ?? '').trim().split(RegExp(r'\s+')).first;
    final face = ref.watch(bioKindProvider).value == BioKind.face;
    final method = face ? 'Face ID' : s.tr('البصمة', 'fingerprint');
    return Material(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -1),
            radius: 1.5,
            colors: [MkColors.purple700, MkColors.purple900],
            stops: [0, 0.6],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(MkSpace.xl),
            child: Column(
              children: [
                const SizedBox(height: MkSpace.xl),
                const MkEntrance(child: MkLogo(height: 70, markOnly: true)),
                const SizedBox(height: MkSpace.lg),
                MkEntrance(
                  index: 1,
                  child: CircleAvatar(
                    radius: 34,
                    backgroundColor: Colors.white.withValues(alpha: 0.12),
                    child: Text(
                      first.isEmpty ? 'M' : first[0].toUpperCase(),
                      style: t.headlineMedium?.copyWith(color: MkColors.yellow500, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(height: MkSpace.md),
                MkEntrance(
                  index: 2,
                  child: Text(
                    first.isEmpty ? s.tr('أهلا فيك من جديد', 'Welcome back') : s.tr('أهلا فيك من جديد، $first', 'Welcome back, $first'),
                    textAlign: TextAlign.center,
                    style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: MkSpace.xs),
                Text(
                  _failed ? s.tr('ما زبط. جرّب مرة تانية.', 'That did not work. Try again.') : s.tr('محفظتك مقفولة.', 'Your wallet is locked.'),
                  style: t.bodyLarge?.copyWith(color: _failed ? MkColors.yellow200 : const Color(0xFFD8CCE6)),
                ),
                const Spacer(),
                Semantics(
                  button: true,
                  label: s.tr('افتح باستعمال $method', 'Unlock with $method'),
                  child: MkPressable(
                    onTap: _busy ? null : _unlock,
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.10),
                        borderRadius: MkRadius.all(28),
                        border: Border.all(color: MkColors.yellow500.withValues(alpha: 0.4), width: 2),
                      ),
                      child: Icon(face ? Icons.face : Icons.fingerprint, size: 54, color: MkColors.yellow500),
                    ),
                  ),
                ),
                const SizedBox(height: MkSpace.sm),
                Text(
                  s.tr('افتح باستعمال $method', 'Unlock with $method'),
                  style: t.titleSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _busy ? null : _signInAgain,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  child: Text(
                    user?.isGoogle ?? false
                        ? s.tr('فوت من جديد بحساب Google', 'Sign in again with Google')
                        : s.tr('استعمل رقم تلفوني بدالها', 'Use my phone number instead'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
