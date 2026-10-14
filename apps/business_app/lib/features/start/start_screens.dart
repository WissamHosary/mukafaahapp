import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: MkColors.purple900,
        body: Center(child: MkEntrance(child: MkLogo(height: 140, onDark: true))),
      );
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
