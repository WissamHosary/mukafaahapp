import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mk_core/mk_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/api.dart';

final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError());
final storeProvider = Provider<SecureStore>((ref) => SecureStore());

final apiClientProvider = Provider<ApiClient>((ref) {
  final c = ApiClient(
    store: ref.watch(storeProvider),
    app: 'BUSINESS',
    onSessionExpired: () => ref.read(sessionProvider.notifier).ownerSignedOut(),
  );
  c.language = ref.read(localeProvider);
  return c;
});

final apiProvider = Provider<BusinessApi>((ref) => BusinessApi(ref.watch(apiClientProvider)));

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

// ---------- Session: which mode this device runs in, and who is signed in ----------
/// owner: the shop owner's phone. worker: a worker signed in with their own
/// username. counter: a shared counter tablet paired with a code.
enum AppMode { none, owner, worker, counter }

enum OwnerStatus { unknown, signedOut, needsBusiness, ready }

class BizSession {
  const BizSession({
    this.loaded = false,
    this.mode = AppMode.none,
    this.owner = OwnerStatus.unknown,
    this.device,
    this.staff,
    this.workerShop,
    this.workerBranch,
  });

  final bool loaded;
  final String? workerShop;
  final String? workerBranch;
  final AppMode mode;
  final OwnerStatus owner;
  final DeviceCreds? device;

  /// Cashier session lives only in memory: every app start needs the PIN again.
  final StaffSession? staff;

  BizSession copy({
    bool? loaded,
    AppMode? mode,
    OwnerStatus? owner,
    DeviceCreds? device,
    bool clearDevice = false,
    StaffSession? staff,
    bool clearStaff = false,
    String? workerShop,
    String? workerBranch,
  }) =>
      BizSession(
        loaded: loaded ?? this.loaded,
        mode: mode ?? this.mode,
        owner: owner ?? this.owner,
        device: clearDevice ? null : (device ?? this.device),
        staff: clearStaff ? null : (staff ?? this.staff),
        workerShop: workerShop ?? this.workerShop,
        workerBranch: workerBranch ?? this.workerBranch,
      );
}

class SessionNotifier extends Notifier<BizSession> {
  static const _modeKey = 'mk.biz.mode';
  static const _devKey = 'mk.biz.device';
  static const _workerKey = 'mk.biz.worker';

  SecureStore get _store => ref.read(storeProvider);

  @override
  BizSession build() {
    Future.microtask(_restore);
    return const BizSession();
  }

  Future<void> _restore() async {
    final mode = switch (await _store.read(_modeKey)) {
      'owner' => AppMode.owner,
      'worker' => AppMode.worker,
      'counter' => AppMode.counter,
      _ => AppMode.none,
    };
    DeviceCreds? device;
    final raw = await _store.read(_devKey);
    if (raw != null) {
      final p = raw.split('\u0001');
      if (p.length == 4) device = DeviceCreds(id: p[0], secret: p[1], businessName: p[2], branchName: p[3]);
    }
    StaffSession? worker;
    if (mode == AppMode.worker) {
      // A worker stays signed in until their 12-hour session ends.
      final w = (await _store.read(_workerKey))?.split('\u0001');
      if (w != null && w.length == 5 && (DateTime.tryParse(w[4])?.isAfter(DateTime.now()) ?? false)) {
        worker = StaffSession(token: w[0], id: w[1], name: w[2], canRedeem: w[3] == '1');
        ref.read(apiClientProvider).staffToken = worker.token;
      }
    }
    state = state.copy(loaded: true, mode: mode, device: device, staff: worker);
    if (mode == AppMode.owner) await refreshOwner();
  }

  /// Signs in with the username and password Mukafaah gave the shop. Owners go
  /// to the owner app, workers straight to the counter.
  Future<void> signIn(String username, String password) async {
    final r = await ref.read(apiProvider).businessLogin(username, password);
    if (r.staff == null) {
      ref.read(apiClientProvider).staffToken = null;
      await _store.write(_workerKey, null);
      await chooseMode(AppMode.owner);
      return;
    }
    final st = r.staff!;
    final until = DateTime.now().add(Duration(seconds: r.expiresInSec - 60));
    await _store.write(_workerKey, [st.token, st.id, st.name, st.canRedeem ? '1' : '0', until.toIso8601String()].join('\u0001'));
    await _store.write(_modeKey, 'worker');
    ref.read(apiClientProvider).staffToken = st.token;
    state = state.copy(mode: AppMode.worker, staff: st, workerShop: r.businessName, workerBranch: r.branchName);
  }

  Future<void> chooseMode(AppMode mode) async {
    await _store.write(_modeKey, switch (mode) {
      AppMode.owner => 'owner',
      AppMode.worker => 'worker',
      AppMode.counter => 'counter',
      AppMode.none => null,
    });
    state = state.copy(mode: mode, owner: mode == AppMode.owner ? OwnerStatus.unknown : state.owner);
    if (mode == AppMode.owner) await refreshOwner();
  }

  /// Decides whether the owner is signed out, needs onboarding, or is ready.
  Future<void> refreshOwner() async {
    if (await _store.accessToken == null) {
      state = state.copy(owner: OwnerStatus.signedOut);
      return;
    }
    try {
      await ref.read(apiProvider).me();
      state = state.copy(owner: OwnerStatus.ready);
    } on ApiException catch (e) {
      if (e.code == 'NO_BUSINESS') {
        state = state.copy(owner: OwnerStatus.needsBusiness);
      } else if (e.isNetwork) {
        state = state.copy(owner: OwnerStatus.ready);
      } else {
        state = state.copy(owner: OwnerStatus.signedOut);
      }
    }
  }

  void ownerSignedOut() {
    ref.read(apiClientProvider).counterToken = null;
    if (state.owner != OwnerStatus.signedOut) state = state.copy(owner: OwnerStatus.signedOut);
  }

  Future<void> ownerLogout() async {
    ref.read(apiClientProvider).counterToken = null;
    await ref.read(apiProvider).logout();
    state = state.copy(owner: OwnerStatus.signedOut);
  }

  Future<void> savePairedDevice(DeviceCreds d) async {
    await _store.write(_devKey, [d.id, d.secret, d.businessName, d.branchName].join('\u0001'));
    state = state.copy(device: d, clearStaff: true);
  }

  Future<void> unpair() async {
    await _store.write(_devKey, null);
    ref.read(apiClientProvider).staffToken = null;
    state = state.copy(clearDevice: true, clearStaff: true);
  }

  void staffSignedIn(StaffSession s) {
    ref.read(apiClientProvider).staffToken = s.token;
    state = state.copy(staff: s);
  }

  void lockCounter() {
    ref.read(apiClientProvider).staffToken = null;
    if (state.mode == AppMode.worker) unawaited(_store.write(_workerKey, null));
    state = state.copy(clearStaff: true);
  }

  Future<void> switchMode() async {
    ref.read(apiClientProvider).staffToken = null;
    await _store.write(_modeKey, null);
    state = state.copy(mode: AppMode.none, clearStaff: true);
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, BizSession>(SessionNotifier.new);

// ---------- Owner server state ----------
final businessProvider = FutureProvider<Business>((ref) => ref.watch(apiProvider).me());
final staffListProvider = FutureProvider<List<StaffMember>>((ref) => ref.watch(apiProvider).staff());
final devicesProvider = FutureProvider<List<Json>>((ref) => ref.watch(apiProvider).devices());
final ownerTxProvider = FutureProvider<List<Json>>((ref) => ref.watch(apiProvider).transactions());

/// Dashboard range: 0 = today, 7 or 30 days.
class RangeNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void set(int days) => state = days;
}

final dashboardRangeProvider = NotifierProvider<RangeNotifier, int>(RangeNotifier.new);

String _d(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

final dashboardProvider = FutureProvider<Dashboard>((ref) {
  final days = ref.watch(dashboardRangeProvider);
  final api = ref.watch(apiProvider);
  if (days == 0) return api.dashboard();
  final now = DateTime.now();
  return api.dashboard(from: _d(now.subtract(Duration(days: days - 1))), to: _d(now));
});

// ---------- Counter ----------
final shiftProvider = FutureProvider<List<Json>>((ref) => ref.watch(apiProvider).shift());

// ---------- v0.2: shop profile, offers, bookings, rewards, products ----------
final profileProvider = FutureProvider<Json>((ref) => ref.watch(apiProvider).profile());

/// Shop categories from Mukafaah Manager; the built-in list is used until they load.
final categoriesProvider = FutureProvider<List<Json>>((ref) => ref.watch(apiProvider).categories());

/// (key, label) pairs for category pickers.
List<(String, String)> categoryChoices(S s, List<Json>? cats) => cats == null || cats.isEmpty
    ? [for (final k in S.categoryKeys) (k, s.category(k))]
    : [
        for (final c in cats)
          (
            c['key'] as String,
            '${(c['emoji'] as String?) ?? ''} ${(s.isAr ? c['nameAr'] : c['nameEn']) as String? ?? c['key']}'.trim(),
          ),
      ];
final ownerOffersProvider = FutureProvider<List<Json>>((ref) => ref.watch(apiProvider).offers());
final ownerBookingsProvider = FutureProvider.family<List<Json>, String>((ref, st) => ref.watch(apiProvider).bookings(st));
final bookingSummaryProvider = FutureProvider<Json>((ref) => ref.watch(apiProvider).bookingSummary());
final ownerRewardsProvider = FutureProvider<List<Json>>((ref) => ref.watch(apiProvider).rewards());
final productsProvider = FutureProvider<List<Json>>((ref) => ref.watch(apiProvider).products());
/// Opens the owner's own Collect / Redeem session (once per sign-in; reopened after 12 h).
final ownerCounterProvider = FutureProvider<void>((ref) => ref.watch(apiProvider).openOwnerCounter());

final ordersProvider = FutureProvider<List<Json>>((ref) => ref.watch(apiProvider).storeOrders());

/// The shop's online store: on/off, categories and products.
final storeInfoProvider = FutureProvider<Json>((ref) => ref.watch(apiProvider).storeInfo());

/// Builds a full image URL from a server path.
final mediaUrlProvider = Provider<String? Function(String?)>((ref) => ref.watch(apiProvider).url);
