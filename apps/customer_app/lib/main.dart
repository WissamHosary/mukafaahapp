import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_ui/mk_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/providers.dart';
import 'app/router.dart';
import 'features/lock/lock_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const MukafaahApp(),
    ),
  );
}

class MukafaahApp extends ConsumerWidget {
  const MukafaahApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeProvider);
    return MaterialApp.router(
      title: 'Mukafaah',
      debugShowCheckedModeBanner: false,
      theme: MkTheme.light(),
      routerConfig: ref.watch(routerProvider),
      locale: Locale(lang),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      // Brand intro plays once over the app while it starts up.
      // Fingerprint / Face ID lock (when turned on) sits under the intro.
      builder: (context, child) => MaterialUiCompatibilityBridge(child: MkIntroGate(child: AppLockGate(child: child!))),
    );
  }
}
