import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mk_core/mk_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/api.dart';
import '../features/auth/google_auth.dart';

/// Overridden in main() after SharedPreferences loads.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());

final storeProvider = Provider<SecureStore>((ref) => SecureStore());

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    store: ref.watch(storeProvider),
    app: 'CUSTOMER',
    onSessionExpired: () => ref.read(authProvider.notifier).signedOut(),
  );
  client.language = ref.read(localeProvider);
  return client;
});

final apiProvider = Provider<CustomerApi>((ref) => CustomerApi(ref.watch(apiClientProvider)));

// ---------- Language ----------
class LocaleNotifier extends Notifier<String> {
  @override
  String build() => ref.read(prefsProvider).getString('lang') ?? 'ar';

  Future<void> set(String lang) async {
    state = lang;
    ref.read(apiClientProvider).language = lang;
    await ref.read(prefsProvider).setString('lang', lang);
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, String>(LocaleNotifier.new);
final stringsProvider = Provider<S>((ref) => S(ref.watch(localeProvider)));

// ---------- Session ----------
enum AuthStatus { unknown, signedOut, signedIn }

class AuthState {
  const AuthState(this.status, {this.user, this.next});
  final AuthStatus status;
  final AppUser? user;

  /// Where to land right after signing in (name step, Pre-Points collect, or home).
  final String? next;
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(_restore);
    return const AuthState(AuthStatus.unknown);
  }

  Future<void> _restore() async {
    final token = await ref.read(storeProvider).accessToken;
    if (token == null) {
      state = const AuthState(AuthStatus.signedOut);
      return;
    }
    try {
      final user = await ref.read(apiProvider).me();
      state = AuthState(AuthStatus.signedIn, user: user);
    } on ApiException catch (e) {
      // Offline at launch: keep the session; screens show their own retry.
      state = e.isNetwork
          ? const AuthState(AuthStatus.signedIn)
          : const AuthState(AuthStatus.signedOut);
    }
  }

  void signedIn(AppUser user, {String next = '/home'}) =>
      state = AuthState(AuthStatus.signedIn, user: user, next: next);

  void updateUser(AppUser user) => state = AuthState(state.status, user: user);

  void signedOut() {
    if (state.status != AuthStatus.signedOut) state = const AuthState(AuthStatus.signedOut);
  }

  Future<void> logout({bool all = false}) async {
    await ref.read(apiProvider).logout(all: all);
    // The next person to sign in on this phone chooses for themselves.
    await ref.read(prefsProvider).remove('bio.enabled');
    await ref.read(prefsProvider).remove('bio.asked');
    await GoogleAuth.signOut();
    signedOut();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

// ---------- Server state (never modified locally; invalidated after mutations) ----------
final walletProvider = FutureProvider<Wallet>((ref) => ref.watch(apiProvider).wallet());
final transactionsProvider = FutureProvider<List<WalletTx>>((ref) => ref.watch(apiProvider).transactions());
final prePointsProvider = FutureProvider<PrePoints>((ref) => ref.watch(apiProvider).prePoints());
final businessesProvider = FutureProvider<List<BusinessSummary>>((ref) => ref.watch(apiProvider).businesses());

final homeProvider = FutureProvider<HomeData>((ref) => ref.watch(apiProvider).home());

/// Categories managed in Mukafaah Manager (names, emoji, icons, order).
final categoriesProvider = FutureProvider<List<CategoryInfo>>((ref) => ref.watch(apiProvider).categories());
final shopsProvider = FutureProvider.family<({int total, List<ShopCard> shops}), ShopQuery>(
  (ref, q) => ref.watch(apiProvider).shops(q),
);
final shopProvider = FutureProvider.family<ShopDetail, String>((ref, id) => ref.watch(apiProvider).shop(id));
final offersProvider = FutureProvider.family<List<Offer>, String?>((ref, c) => ref.watch(apiProvider).offers(category: c));
final rewardsProvider = FutureProvider.family<List<Reward>, String?>((ref, c) => ref.watch(apiProvider).rewards(category: c));
final bookingsProvider = FutureProvider<List<Booking>>((ref) => ref.watch(apiProvider).bookings());
final historyProvider = FutureProvider.family<HistoryData, String>((ref, f) => ref.watch(apiProvider).history(filter: f));
final tierProvider = FutureProvider<TierData>((ref) => ref.watch(apiProvider).tier(ref.watch(localeProvider) == 'ar'));
final referralProvider = FutureProvider<Referral>((ref) => ref.watch(apiProvider).referral());
final notificationsProvider = FutureProvider<List<AppNotification>>((ref) => ref.watch(apiProvider).notifications());

/// The fixed member QR: fetched once and kept for the session (it never changes).
final memberQrProvider = FutureProvider<MemberQr>((ref) => ref.watch(apiProvider).memberQr());

/// Mukafaah Points page: balance, how to earn, Friends shops and history.
final mukafaahProvider = FutureProvider<MukafaahData>((ref) => ref.watch(apiProvider).mukafaah());

/// Builds a full image URL from a server path.
final mediaUrlProvider = Provider<String? Function(String?)>((ref) => ref.watch(apiProvider).url);

/// Refresh everything that depends on balances after a points-moving action.
void refreshBalances(WidgetRef ref) {
  ref
    ..invalidate(walletProvider)
    ..invalidate(transactionsProvider)
    ..invalidate(prePointsProvider)
    ..invalidate(homeProvider)
    ..invalidate(categoriesProvider)
    ..invalidate(historyProvider)
    ..invalidate(tierProvider)
    ..invalidate(mukafaahProvider)
    ..invalidate(shopProvider)
    ..invalidate(shopsProvider)
    ..invalidate(rewardsProvider);
}

// ---------- Store ----------
final shopStoreProvider = FutureProvider.family<StoreData, String>((ref, shopId) => ref.watch(apiProvider).store(shopId));
final storeProductProvider = FutureProvider.family<StoreProduct, ({String shopId, String productId})>(
  (ref, k) => ref.watch(apiProvider).storeProduct(k.shopId, k.productId),
);

// ---------- Cart (one shop at a time; sent to the shop on WhatsApp) ----------
class CartLine {
  const CartLine({
    required this.productId,
    required this.name,
    required this.priceMinor,
    required this.qty,
    this.variantId,
    this.variantLabel,
    this.imageUrl,
    this.maxQty,
  });
  final String productId;
  final String? variantId;
  final String name;
  final String? variantLabel;
  final int priceMinor;
  final String? imageUrl;
  final int qty;

  /// Known stock limit, if the shop tracks stock.
  final int? maxQty;

  String get key => variantId == null ? productId : '$productId|$variantId';
  CartLine withQty(int q) => CartLine(
        productId: productId,
        variantId: variantId,
        name: name,
        variantLabel: variantLabel,
        priceMinor: priceMinor,
        imageUrl: imageUrl,
        qty: q,
        maxQty: maxQty,
      );
}

class CartState {
  const CartState({this.shopId, this.shopName, this.lines = const []});
  final String? shopId;
  final String? shopName;
  final List<CartLine> lines;

  int get count => lines.fold(0, (a, l) => a + l.qty);
  int get totalMinor => lines.fold(0, (a, l) => a + l.priceMinor * l.qty);
}

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  /// Adds [line]. Returns false when the cart holds another shop's items.
  bool add(String shopId, String shopName, CartLine line) {
    if (state.shopId != null && state.shopId != shopId && state.count > 0) return false;
    final lines = [...(state.shopId == shopId ? state.lines : const <CartLine>[])];
    final i = lines.indexWhere((l) => l.key == line.key);
    if (i >= 0) {
      final q = lines[i].qty + line.qty;
      lines[i] = lines[i].withQty(line.maxQty == null ? q : q.clamp(1, line.maxQty!));
    } else {
      lines.add(line);
    }
    state = CartState(shopId: shopId, shopName: shopName, lines: lines);
    return true;
  }

  void setQty(String key, int qty) {
    final lines = [
      for (final l in state.lines)
        if (l.key != key) l else if (qty > 0) l.withQty(l.maxQty == null ? qty : qty.clamp(1, l.maxQty!)),
    ];
    state = CartState(shopId: lines.isEmpty ? null : state.shopId, shopName: lines.isEmpty ? null : state.shopName, lines: lines);
  }

  void clear() => state = const CartState();
}

final cartProvider = NotifierProvider<CartNotifier, CartState>(CartNotifier.new);
