import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../features/counter/counter_screen.dart';
import '../features/counter/counter_setup.dart';
import '../features/counter/shift_screen.dart';
import '../features/owner/bookings_screen.dart';
import '../features/owner/catalog_screen.dart';
import '../features/owner/dashboard_screen.dart';
import '../features/owner/orders_screen.dart';
import '../features/owner/offers_screen.dart';
import '../features/owner/owner_counter.dart';
import '../features/owner/store_screen.dart';
import '../features/owner/shop_profile_screen.dart';
import '../features/owner/owner_auth.dart';
import '../features/owner/owner_shell.dart';
import '../features/owner/settings_screen.dart';
import '../features/owner/team_screen.dart';
import '../features/owner/transactions_screen.dart';
import '../features/start/start_screens.dart';
import 'providers.dart';

CustomTransitionPage<void> _fade(GoRouterState s, Widget child) => CustomTransitionPage<void>(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 240),
      transitionsBuilder: (context, a, _, c) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOutCubic),
        child: c,
      ),
    );

final routerProvider = Provider<GoRouter>((ref) {
  final tick = ValueNotifier<int>(0);
  ref
    ..listen(sessionProvider, (_, _) => tick.value++)
    ..onDispose(tick.dispose);

  String? redirect(BuildContext context, GoRouterState state) {
    final s = ref.read(sessionProvider);
    final path = state.matchedLocation;
    if (!s.loaded) return path == '/splash' ? null : '/splash';
    switch (s.mode) {
      case AppMode.none:
        return path == '/signin' ? null : '/signin';
      case AppMode.owner:
        switch (s.owner) {
          case OwnerStatus.unknown:
            return path == '/splash' ? null : '/splash';
          case OwnerStatus.signedOut:
            return path == '/signin' || path.startsWith('/owner/login') ? null : '/signin';
          case OwnerStatus.needsBusiness:
            return path == '/owner/onboard' ? null : '/owner/onboard';
          case OwnerStatus.ready:
            return path.startsWith('/owner/') && !path.startsWith('/owner/login') && path != '/owner/onboard'
                ? null
                : '/owner/collect';
        }
      case AppMode.worker:
        if (s.staff == null) return path == '/signin' ? null : '/signin';
        return path == '/counter' || path == '/counter/shift' ? null : '/counter';
      case AppMode.counter:
        if (s.device == null) return path == '/counter/pair' ? null : '/counter/pair';
        if (s.staff == null) return path == '/counter/login' ? null : '/counter/login';
        return path == '/counter' || path == '/counter/shift' ? null : '/counter';
    }
    // ignore: dead_code
    return null;
  }

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: tick,
    redirect: redirect,
    routes: [
      GoRoute(path: '/splash', pageBuilder: (c, s) => _fade(s, const SplashScreen())),
      GoRoute(path: '/mode', pageBuilder: (c, s) => _fade(s, const ModeScreen())),
      GoRoute(path: '/signin', pageBuilder: (c, s) => _fade(s, const SignInScreen())),
      GoRoute(path: '/owner/login', pageBuilder: (c, s) => _fade(s, const OwnerLoginScreen())),
      GoRoute(path: '/owner/onboard', pageBuilder: (c, s) => _fade(s, const OnboardScreen())),
      ShellRoute(
        builder: (context, state, child) => OwnerShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/owner/collect', pageBuilder: (c, s) => _fade(s, const OwnerCounterScreen(mode: CounterMode.collect))),
          GoRoute(path: '/owner/redeem', pageBuilder: (c, s) => _fade(s, const OwnerCounterScreen(mode: CounterMode.redeem))),
          GoRoute(path: '/owner/dashboard', pageBuilder: (c, s) => _fade(s, const DashboardScreen())),
          GoRoute(path: '/owner/transactions', pageBuilder: (c, s) => _fade(s, const TransactionsScreen())),
          GoRoute(path: '/owner/team', pageBuilder: (c, s) => _fade(s, const TeamScreen())),
          GoRoute(path: '/owner/settings', pageBuilder: (c, s) => _fade(s, const SettingsScreen())),
          GoRoute(path: '/owner/bookings', pageBuilder: (c, s) => _fade(s, const BookingsScreen())),
          GoRoute(path: '/owner/catalog', pageBuilder: (c, s) => _fade(s, const CatalogScreen())),
          GoRoute(path: '/owner/profile', pageBuilder: (c, s) => _fade(s, const ShopProfileScreen())),
          GoRoute(path: '/owner/orders', pageBuilder: (c, s) => _fade(s, const OrdersScreen())),
          GoRoute(path: '/owner/offers', pageBuilder: (c, s) => _fade(s, const OffersScreen())),
        ],
      ),
      GoRoute(path: '/owner/store/product', pageBuilder: (c, s) => _fade(s, StoreProductEditor(productId: s.extra as String?))),
      GoRoute(path: '/counter/pair', pageBuilder: (c, s) => _fade(s, const PairScreen())),
      GoRoute(path: '/counter/login', pageBuilder: (c, s) => _fade(s, const StaffLoginScreen())),
      GoRoute(path: '/counter', pageBuilder: (c, s) => _fade(s, const CounterScreen())),
      GoRoute(path: '/counter/shift', pageBuilder: (c, s) => _fade(s, const ShiftScreen())),
    ],
  );
});
