import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  // Plain, under the opening animation.
  @override
  Widget build(BuildContext context) => const Scaffold(backgroundColor: Color(0xFFFBFAFD));
}

class LangToggle extends ConsumerWidget {
  const LangToggle({this.onDark = false, super.key});
  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeProvider);
    return TextButton(
      onPressed: () => ref.read(localeProvider.notifier).set(lang == 'ar' ? 'en' : 'ar'),
      style: TextButton.styleFrom(foregroundColor: onDark ? Colors.white : MkColors.purple700),
      child: Text(lang == 'ar' ? 'English' : 'العربية'),
    );
  }
}

/// First launch: is this the owner's device or a counter device?
class ModeScreen extends ConsumerWidget {
  const ModeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    Widget option(int i, IconData icon, String title, String body, AppMode mode, bool accent) => MkEntrance(
          index: i,
          child: MkPressable(
            onTap: () => ref.read(sessionProvider.notifier).chooseMode(mode),
            child: Container(
              padding: const EdgeInsets.all(MkSpace.lg),
              decoration: BoxDecoration(
                color: accent ? MkColors.yellow500 : Colors.white.withValues(alpha: 0.08),
                borderRadius: MkRadius.all(MkRadius.lg),
                border: Border.all(color: accent ? MkColors.yellow500 : Colors.white24),
              ),
              child: Row(
                children: [
                  MkIconTile(
                    icon: icon,
                    size: 52,
                    bg: accent ? MkColors.purple900 : MkColors.yellow500,
                    color: accent ? MkColors.yellow500 : MkColors.purple900,
                  ),
                  const SizedBox(width: MkSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: t.titleMedium?.copyWith(color: accent ? MkColors.purple900 : Colors.white)),
                        Text(
                          body,
                          style: t.bodySmall?.copyWith(color: accent ? MkColors.purple800 : const Color(0xFFD8CCE6)),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: accent ? MkColors.purple900 : Colors.white),
                ],
              ),
            ),
          ),
        );

    return Scaffold(
      body: MkSwirlBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(MkSpace.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(alignment: AlignmentDirectional.centerEnd, child: LangToggle(onDark: true)),
                    const Spacer(),
                    const MkEntrance(child: Center(child: MkLogo(height: 120, onDark: true))),
                    const SizedBox(height: MkSpace.xs),
                    Center(child: Text(s.businessApp, style: t.titleMedium?.copyWith(color: MkColors.yellow500))),
                    const Spacer(),
                    Text(s.chooseMode, style: t.titleLarge?.copyWith(color: Colors.white)),
                    const SizedBox(height: MkSpace.md),
                    option(1, Icons.space_dashboard_rounded, s.ownerMode, s.ownerModeBody, AppMode.owner, true),
                    const SizedBox(height: MkSpace.sm),
                    option(2, Icons.point_of_sale_rounded, s.counterMode, s.counterModeBody, AppMode.counter, false),
                    const SizedBox(height: MkSpace.md),
                    if (AppConfig.isDev)
                      MkDevServerButton(
                        load: () => ref.read(apiClientProvider).currentServer(),
                        save: (a) => ref.read(apiClientProvider).setDevServer(a),
                      ),
                    const SizedBox(height: MkSpace.sm),
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

/// Sign in with the username and password Mukafaah created for the shop.
/// Owners land on the owner app, workers on the counter.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  final _passFocus = FocusNode();
  bool _show = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final c in [_user, _pass]) {
      c.addListener(() => setState(() => _error = null));
    }
  }

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _user.text.trim().isEmpty || _pass.text.isEmpty) return;
    final s = ref.read(stringsProvider);
    setState(() => _busy = true);
    try {
      await ref.read(sessionProvider.notifier).signIn(_user.text, _pass.text);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = switch (e.code) {
            'LOGIN_INVALID' => s.tr('اسم المستخدم أو كلمة السر غلط.', 'Wrong username or password.'),
            'LOGIN_LOCKED' => s.tr('محاولات كتير غلط. جرّب بعد ١٥ دقيقة.', 'Too many wrong tries. Try again in 15 minutes.'),
            'LOGIN_DISABLED' => s.tr('هالحساب موقّف. احكي مع مكافأة.', 'This account is switched off. Contact Mukafaah.'),
            _ => s.error(e.code),
          });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: MkColors.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.all(MkSpace.xl),
              children: [
                const Align(alignment: AlignmentDirectional.centerEnd, child: LangToggle()),
                const SizedBox(height: MkSpace.md),
                const MkEntrance(child: Center(child: MkLogo(height: 104))),
                const SizedBox(height: MkSpace.xs),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(color: MkColors.purple900, borderRadius: MkRadius.all(MkRadius.pill)),
                    child: Text('Business', style: t.labelLarge?.copyWith(color: MkColors.yellow500, fontWeight: FontWeight.w800, letterSpacing: 1)),
                  ),
                ),
                const SizedBox(height: MkSpace.xl),
                MkEntrance(
                  index: 1,
                  child: Text(s.tr('أهلا فيك', 'Welcome'), style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 4),
                MkEntrance(
                  index: 2,
                  child: Text(
                    s.tr('فوت باسم المستخدم وكلمة السر اللي عطيتك ياهم مكافأة.', 'Sign in with the username and password Mukafaah gave you.'),
                    style: t.bodyLarge?.copyWith(color: MkColors.ink2),
                  ),
                ),
                const SizedBox(height: MkSpace.lg),
                AutofillGroup(
                  child: Column(
                    children: [
                      TextField(
                        controller: _user,
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.visiblePassword,
                        onSubmitted: (_) => _passFocus.requestFocus(),
                        decoration: InputDecoration(
                          labelText: s.tr('اسم المستخدم', 'Username'),
                          hintText: 'cedar.cafe',
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                        ),
                      ),
                      const SizedBox(height: MkSpace.sm),
                      TextField(
                        controller: _pass,
                        focusNode: _passFocus,
                        obscureText: !_show,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: s.tr('كلمة السر', 'Password'),
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            tooltip: _show ? s.tr('خبّي', 'Hide') : s.tr('فرجيني', 'Show'),
                            onPressed: () => setState(() => _show = !_show),
                            icon: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedSize(
                  duration: MkMotion.base,
                  child: _error == null
                      ? const SizedBox(height: MkSpace.md)
                      : Container(
                          width: double.infinity,
                          margin: const EdgeInsets.symmetric(vertical: MkSpace.sm),
                          padding: const EdgeInsets.all(MkSpace.sm),
                          decoration: BoxDecoration(color: MkColors.dangerBg, borderRadius: MkRadius.all(MkRadius.md)),
                          child: Text(_error!, style: t.bodyMedium?.copyWith(color: MkColors.danger, fontWeight: FontWeight.w600)),
                        ),
                ),
                ListenableBuilder(
                  listenable: Listenable.merge([_user, _pass]),
                  builder: (context, _) => MkButton(
                    label: s.tr('فوت', 'Sign in'),
                    icon: Icons.login_rounded,
                    loading: _busy,
                    onPressed: _user.text.trim().isNotEmpty && _pass.text.isNotEmpty ? _submit : null,
                  ),
                ),
                const SizedBox(height: MkSpace.lg),
                MkCard(
                  color: MkColors.purple50,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded, color: MkColors.purple700, size: 20),
                      const SizedBox(width: MkSpace.xs),
                      Expanded(
                        child: Text(
                          s.tr(
                            'مكافأة بتعمل حسابات المحلات والموظفين. إذا ما عندك حساب أو نسيت كلمة السر، احكي مع مكافأة.',
                            'Mukafaah creates accounts for shops and their workers. No account or forgot your password? Contact Mukafaah.',
                          ),
                          style: t.bodySmall?.copyWith(color: MkColors.ink2),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: MkSpace.sm),
                TextButton.icon(
                  onPressed: () => ref.read(sessionProvider.notifier).chooseMode(AppMode.counter),
                  icon: const Icon(Icons.tablet_rounded, size: 18),
                  label: Text(s.tr('جهاز كاشير مشترك؟ اربطه برمز', 'Shared counter tablet? Pair it with a code')),
                ),
                if (AppConfig.isDev)
                  MkDevServerButton(
                    load: () => ref.read(apiClientProvider).currentServer(),
                    save: (a) => ref.read(apiClientProvider).setDevServer(a),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
