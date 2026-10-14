import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../features/account/account_screen.dart';
import '../features/auth/auth_screens.dart';
import '../features/home/home_screen.dart';
import '../features/map/map_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/offers/offers_screen.dart';
import '../features/points/points_screen.dart';
import '../features/prepoints/collect_screen.dart';
import '../features/shell/shell.dart';
import '../features/shops/shop_screen.dart';
import '../features/shops/shops_screen.dart';
import '../features/store/store_screens.dart';
import '../features/tier/tier_screen.dart';
import '../features/mukafaah/mukafaah_screen.dart';
import '../features/transfer/transfer_screen.dart';
import '../features/wallet/wallet_screen.dart';
import 'providers.dart';

CustomTransitionPage<void> _fade(GoRouterState s, Widget child) => CustomTransitionPage<void>(
      key: s.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 260),
      transitionsBuilder: (context, a, _, c) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOutCubic),
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.03), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: c,
        ),
      ),
    );

final routerProvider = Provider<GoRouter>((ref) {
  final status = ValueNotifier<AuthStatus>(ref.read(authProvider).status);
  ref
    ..listen(authProvider, (_, next) => status.value = next.status)
    ..onDispose(status.dispose);

  const publicPaths = {'/welcome', '/phone', '/otp'};

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: status,
    redirect: (context, state) {
      final s = status.value;
      final path = state.matchedLocation;
      if (s == AuthStatus.unknown) return path == '/splash' ? null : '/splash';
      if (s == AuthStatus.signedOut) return publicPaths.contains(path) ? null : '/welcome';
      // New members finish their profile before anything else.
      final user = ref.read(authProvider).user;
      if (user != null && user.needsProfile && !path.startsWith('/signup')) {
        return ref.read(authProvider).next ?? (user.isGoogle ? '/signup/name' : '/signup/profile');
      }
      if (path == '/splash' || publicPaths.contains(path)) return ref.read(authProvider).next ?? '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', pageBuilder: (c, s) => _fade(s, const SplashScreen())),
      GoRoute(path: '/welcome', pageBuilder: (c, s) => _fade(s, const WelcomeScreen())),
      GoRoute(path: '/phone', pageBuilder: (c, s) => _fade(s, const PhoneScreen())),
      GoRoute(
        path: '/otp',
        pageBuilder: (c, s) => _fade(s, OtpScreen(args: s.extra! as OtpArgs)),
      ),
      GoRoute(path: '/signup/profile', pageBuilder: (c, s) => _fade(s, const ProfileSetupScreen())),
      GoRoute(
        path: '/signup/name',
        pageBuilder: (c, s) => _fade(s, CallMeScreen(suggested: s.uri.queryParameters['suggest'])),
      ),
      GoRoute(
        path: '/signup/done',
        pageBuilder: (c, s) => _fade(s, SignupDoneScreen(invitedBy: s.uri.queryParameters['invitedBy'])),
      ),
      GoRoute(
        path: '/signup/unlock',
        pageBuilder: (c, s) => _fade(s, UnlockOfferScreen(next: s.uri.queryParameters['next'] ?? '/home')),
      ),
      GoRoute(path: '/collect', pageBuilder: (c, s) => _fade(s, const CollectScreen())),
      GoRoute(path: '/shop/:id', pageBuilder: (c, s) => _fade(s, ShopScreen(id: s.pathParameters['id']!))),
      GoRoute(path: '/shop/:id/store', pageBuilder: (c, s) => _fade(s, StoreScreen(shopId: s.pathParameters['id']!))),
      GoRoute(
        path: '/shop/:id/product/:pid',
        pageBuilder: (c, s) => _fade(s, ProductScreen(shopId: s.pathParameters['id']!, productId: s.pathParameters['pid']!)),
      ),
      GoRoute(path: '/cart', pageBuilder: (c, s) => _fade(s, const CartScreen())),
      GoRoute(
        path: '/category/:key',
        pageBuilder: (c, s) => _fade(s, ShopsScreen(category: s.pathParameters['key'], standalone: true)),
      ),
      GoRoute(path: '/points', pageBuilder: (c, s) => _fade(s, const PointsScreen())),
      GoRoute(path: '/offers', pageBuilder: (c, s) => _fade(s, const OffersScreen())),
      GoRoute(path: '/bookings', pageBuilder: (c, s) => _fade(s, const BookingsScreen())),
      GoRoute(path: '/tier', pageBuilder: (c, s) => _fade(s, const TierScreen())),
      GoRoute(path: '/transfer', pageBuilder: (c, s) => _fade(s, const TransferScreen())),
      GoRoute(path: '/mukafaah', pageBuilder: (c, s) => _fade(s, const MukafaahScreen())),
      GoRoute(path: '/notifications', pageBuilder: (c, s) => _fade(s, const NotificationsScreen())),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (c, s) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/map', builder: (c, s) => const MapScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/wallet', builder: (c, s) => const WalletScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/shops', builder: (c, s) => const ShopsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (c, s) => const AccountScreen())]),
        ],
      ),
    ],
  );
});
