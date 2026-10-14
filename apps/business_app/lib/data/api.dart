import 'dart:convert';

import 'package:mk_core/mk_core.dart';

typedef Json = Map<String, dynamic>;

int _i(Object? v) => (v as num?)?.toInt() ?? 0;

class Business {
  const Business({
    required this.id,
    required this.name,
    required this.category,
    required this.currency,
    required this.programId,
    required this.programType,
    required this.earnPointsPerUnit,
    required this.redeemPointsPerUnit,
    required this.minBillMinor,
    required this.branches,
    required this.memberships,
  });

  factory Business.fromJson(Json j) {
    final p = j['earningProgram'] as Json;
    return Business(
      id: j['id'] as String,
      name: j['name'] as String,
      category: j['category'] as String,
      currency: j['currency'] as String,
      programId: p['id'] as String,
      programType: p['type'] as String,
      earnPointsPerUnit: _i(p['earnPointsPerUnit']),
      redeemPointsPerUnit: _i(p['redeemPointsPerUnit']),
      minBillMinor: _i(p['minBillMinor']),
      branches: [for (final b in j['branches'] as List) (id: (b as Json)['id'] as String, name: b['name'] as String)],
      memberships: [
        for (final m in j['programs'] as List) (type: (m as Json)['type'] as String, name: m['name'] as String),
      ],
    );
  }

  final String id;
  final String name;
  final String category;
  final String currency;
  final String programId;
  final String programType;
  final int earnPointsPerUnit;
  final int redeemPointsPerUnit;
  final int minBillMinor;
  final List<({String id, String name})> branches;
  final List<({String type, String name})> memberships;
}

class Dashboard {
  Dashboard(this.j);
  final Json j;
  Json get totals => j['totals'] as Json;
  String get currency => j['currency'] as String;
  int get billsMinor => _i(totals['billsMinor']);
  int get earnTx => _i(totals['earnTransactions']);
  int get redeemTx => _i(totals['redeemTransactions']);
  int get pointsIssued => _i(totals['pointsIssued']);
  int get prepointsIssued => _i(totals['prepointsIssued']);
  int get pointsRedeemed => _i(totals['pointsRedeemed']);
  int get customers => _i(totals['customers']);
  int get newCustomers => _i(totals['newCustomers']);
  int get returningCustomers => _i(totals['returningCustomers']);
  List<Json> get byCashier => (j['byCashier'] as List).cast<Json>();
  List<Json> get byBranch => (j['byBranch'] as List).cast<Json>();
  List<Json> get daily => (j['daily'] as List).cast<Json>();
  Json get engagement => (j['engagement'] as Json?) ?? const {};
  int get pendingBookings => _i(engagement['pendingBookings']);
  int get acceptedBookings => _i(engagement['acceptedBookings']);
  int get offersUsed => _i(engagement['offersUsed']);
  int get rewardsRedeemed => _i(engagement['rewardsRedeemed']);
  int get whatsappOrders => _i(engagement['whatsappOrders']);
  double get rating => (engagement['rating'] as num?)?.toDouble() ?? 0;
  int get ratingCount => _i(engagement['ratingCount']);
}

class StaffMember {
  StaffMember(this.j);
  final Json j;
  String get id => j['id'] as String;
  String get name => j['name'] as String;
  bool get active => j['active'] as bool;
  String get branchName => j['branchName'] as String;
  Json get limits => j['limits'] as Json;
}

class DeviceCreds {
  const DeviceCreds({required this.id, required this.secret, required this.businessName, required this.branchName});
  final String id;
  final String secret;
  final String businessName;
  final String branchName;
}

class StaffSession {
  const StaffSession({required this.token, required this.id, required this.name, required this.canRedeem});
  final String token;
  final String id;
  final String name;
  final bool canRedeem;
}

class CustomerView {
  CustomerView(this.j);
  final Json j;
  bool get isMember => j['status'] == 'MEMBER';
  String? get displayName => j['displayName'] as String?;
  String? get phoneLast4 => j['phoneLast4'] as String?;
  bool get presentedQr => j['presentedQr'] == true;
  int get prePointsHere => _i(j['prePointsHere']);
  List<Json> get programs => (j['programs'] as List).cast<Json>();
  List<Json> get bookings => ((j['bookings'] as List?) ?? const []).cast<Json>();
  List<Json> get walkInOffers => ((j['walkInOffers'] as List?) ?? const []).cast<Json>();
  List<Json> get rewards => ((j['rewards'] as List?) ?? const []).cast<Json>();

  /// The customer's id (needed by Mukafaah Points redeem), when the server sends it.
  String? get userId => (j['userId'] ?? j['id']) as String?;

  /// v0.7: company-wide Mukafaah Points and whether this shop accepts them.
  int get mukafaahPoints => _i(j['mukafaahPoints']);
  Json get _friends => (j['friends'] as Json?) ?? const {};
  bool get friendsEnabled => _friends['enabled'] == true;
  int get friendsMaxPoints => _i(_friends['maxPoints']);

  /// Points this customer can use here now: their balance, capped per bill.
  int get mukafaahUsable => !friendsEnabled ? 0 : (mukafaahPoints < friendsMaxPoints ? mukafaahPoints : friendsMaxPoints);
}

/// A live alert for the shop (new booking, store order, redeem approved...).
class BizAlert {
  BizAlert(this.j);
  final Json j;
  String get id => '${j['id']}';
  String get kind => (j['kind'] as String?) ?? '';
  String get title => (j['title'] as String?) ?? '';
  String get body => (j['body'] as String?) ?? '';
  String? get refId => j['refId']?.toString();
  DateTime get createdAt => DateTime.tryParse((j['createdAt'] as String?) ?? '')?.toLocal() ?? DateTime.now();
}

/// True when a spend call answered 202: the customer has to approve on their phone.
bool isApprovalPending(Json r) => r['requestId'] != null && (r['status'] ?? 'PENDING') == 'PENDING';

/// Business API (owner and counter surfaces).
class BusinessApi {
  BusinessApi(this.client);
  final ApiClient client;

  // ----- owner auth (same OTP identity as customers) -----
  Future<OtpChallenge> requestOtp(String phone, String locale) async {
    final d = await client.post<Json>(
      '/v1/auth/otp/request',
      auth: false,
      data: {'phone': phone, 'app': 'BUSINESS', 'deviceId': await client.store.deviceId(), 'locale': locale},
    );
    return OtpChallenge(id: d['challengeId'] as String, resendInSec: _i(d['resendInSec']), devCode: d['devCode'] as String?);
  }

  Future<void> verifyOtp(String challengeId, String code) async {
    final d = await client.post<Json>(
      '/v1/auth/otp/verify',
      auth: false,
      data: {'challengeId': challengeId, 'code': code, 'app': 'BUSINESS', 'deviceLabel': 'Mukafaah Business'},
    );
    await client.store.saveTokens(access: d['accessToken'] as String, refresh: d['refreshToken'] as String);
  }

  Future<void> logout() async {
    try {
      await client.post<Json>('/v1/auth/logout');
    } on ApiException {
      // local sign-out always succeeds
    }
    await client.store.clearTokens();
  }

  // ----- owner -----
  Future<Business> me() async => Business.fromJson(await client.get<Json>('/v1/business/manage/me'));

  Future<void> onboard({
    required String name,
    required String category,
    required String branchName,
    required int earnPointsPerUnit,
    required int redeemPointsPerUnit,
  }) =>
      client.post<Json>(
        '/v1/business/onboarding',
        data: {
          'businessName': name,
          'category': category,
          'branchName': branchName,
          'earnPointsPerUnit': earnPointsPerUnit,
          'redeemPointsPerUnit': redeemPointsPerUnit,
        },
      );

  Future<void> updateProgram({required int earn, required int redeem, required int minBillMinor}) =>
      client.put<Json>('/v1/business/manage/program', data: {
        'earnPointsPerUnit': earn,
        'redeemPointsPerUnit': redeem,
        'minBillMinor': minBillMinor,
      });

  /// Categories managed in Mukafaah Manager: key, nameEn, nameAr, emoji, iconUrl.
  Future<List<Json>> categories() async =>
      (await client.get<List<dynamic>>('/v1/public/categories')).map((e) => e as Json).toList();

  Future<void> addBranch(String name) => client.post<Json>('/v1/business/manage/branches', data: {'name': name});

  Future<Dashboard> dashboard({String? from, String? to, String? staffId, String? branchId}) async => Dashboard(
        await client.get<Json>('/v1/business/manage/dashboard', query: {
          if (from != null) 'from': from,
          if (to != null) 'to': to,
          if (staffId != null) 'staffId': staffId,
          if (branchId != null) 'branchId': branchId,
        }),
      );

  Future<List<Json>> transactions() async =>
      (await client.get<List<dynamic>>('/v1/business/manage/transactions')).cast<Json>();

  Future<void> reverse(String txId, String reason) =>
      client.post<Json>('/v1/business/manage/transactions/$txId/reverse', data: {'reason': reason});

  Future<List<StaffMember>> staff() async =>
      (await client.get<List<dynamic>>('/v1/business/manage/staff')).map((e) => StaffMember(e as Json)).toList();

  Future<void> addStaff({required String name, required String branchId, required String pin}) =>
      client.post<Json>('/v1/business/manage/staff', data: {'name': name, 'branchId': branchId, 'pin': pin});

  Future<void> patchStaff(String id, Json patch) => client.patch<Json>('/v1/business/manage/staff/$id', data: patch);

  Future<({String code, String branchName})> pairingCode(String branchId) async {
    final d = await client.post<Json>('/v1/business/manage/pairing-codes', data: {'branchId': branchId});
    return (code: d['code'] as String, branchName: d['branchName'] as String);
  }

  Future<List<Json>> devices() async => (await client.get<List<dynamic>>('/v1/business/manage/devices')).cast<Json>();

  Future<void> revokeDevice(String id) => client.post<Json>('/v1/business/manage/devices/$id/revoke');

  // ----- counter -----
  Future<DeviceCreds> pair(String code, String label) async {
    final d = await client.post<Json>('/v1/business/cashier/pair', auth: false, data: {'code': code, 'label': label});
    return DeviceCreds(
      id: d['deviceId'] as String,
      secret: d['deviceSecret'] as String,
      businessName: d['businessName'] as String,
      branchName: d['branchName'] as String,
    );
  }

  Future<List<({String id, String name})>> counterStaff(DeviceCreds dev) async {
    final d = await client.post<Json>(
      '/v1/business/cashier/device/staff',
      auth: false,
      data: {'deviceId': dev.id, 'deviceSecret': dev.secret},
    );
    return [for (final s in d['staff'] as List) (id: (s as Json)['id'] as String, name: s['name'] as String)];
  }

  /// Username and password from Mukafaah. Owners get a normal session (saved);
  /// workers get a 12-hour counter session ([staff] is set).
  Future<({StaffSession? staff, int expiresInSec, String? businessName, String? branchName})> businessLogin(
    String username,
    String password,
  ) async {
    final d = await client.post<Json>(
      '/v1/auth/business/login',
      auth: false,
      data: {'username': username.trim(), 'password': password, 'deviceLabel': 'Mukafaah Business'},
    );
    if (d['kind'] == 'OWNER') {
      await client.store.saveTokens(access: d['accessToken'] as String, refresh: d['refreshToken'] as String);
      return (staff: null, expiresInSec: 0, businessName: d['businessName'] as String?, branchName: null);
    }
    final st = d['staff'] as Json;
    return (
      staff: StaffSession(token: d['accessToken'] as String, id: st['id'] as String, name: st['name'] as String, canRedeem: st['canRedeem'] == true),
      expiresInSec: _i(d['expiresInSec']),
      businessName: d['businessName'] as String?,
      branchName: d['branchName'] as String?,
    );
  }

  Future<StaffSession> staffLogin(DeviceCreds dev, String staffId, String pin) async {
    final d = await client.post<Json>(
      '/v1/business/cashier/login',
      auth: false,
      data: {'deviceId': dev.id, 'deviceSecret': dev.secret, 'staffId': staffId, 'pin': pin},
    );
    final st = d['staff'] as Json;
    return StaffSession(
      token: d['accessToken'] as String,
      id: st['id'] as String,
      name: st['name'] as String,
      canRedeem: st['canRedeem'] == true,
    );
  }

  Future<CustomerView> lookup({String? phone, String? qr}) async => CustomerView(
        await client.post<Json>('/v1/business/cashier/lookup', data: {if (phone != null) 'phone': phone, if (qr != null) 'qr': qr}),
      );

  Future<int> preview(int billMinor) async =>
      _i((await client.post<Json>('/v1/business/cashier/earn/preview', data: {'billMinor': billMinor}))['points']);

  Future<Json> earn({String? phone, String? qr, required int billMinor, required String idempotencyKey, String? invoiceNo}) =>
      client.post<Json>(
        '/v1/business/cashier/earn',
        idempotent: true,
        idempotencyKey: idempotencyKey,
        data: {
          if (phone != null) 'phone': phone,
          if (qr != null) 'qr': qr,
          'billMinor': billMinor,
          if (invoiceNo != null && invoiceNo.trim().isNotEmpty) 'invoiceNo': invoiceNo.trim(),
        },
      );

  /// Opens Collect / Redeem for the signed-in owner on this phone.
  Future<void> openOwnerCounter() async {
    final d = await client.post<Json>('/v1/business/manage/counter');
    client.counterToken = d['accessToken'] as String;
  }

  /// The shop's loyalty %: points back on every bill (100 points = \$1).
  Future<void> setLoyaltyPercent(int percent, {int? minBillMinor}) =>
      client.put<Json>('/v1/business/manage/program', data: {'earnPercent': percent, if (minBillMinor != null) 'minBillMinor': minBillMinor});

  Future<Json> redeem({required String qr, required String programId, required int points, required String idempotencyKey}) =>
      client.post<Json>(
        '/v1/business/cashier/redeem',
        idempotent: true,
        idempotencyKey: idempotencyKey,
        data: {'qr': qr, 'programId': programId, 'points': points},
      );

  Future<List<Json>> shift() async => (await client.get<List<dynamic>>('/v1/business/cashier/shift')).cast<Json>();

  // ---------- v0.2: shop profile, offers, bookings, rewards, products ----------
  String? url(String? path) => client.resolve(path);

  Future<Json> profile() => client.get<Json>('/v1/business/manage/profile');
  Future<Json> updateProfile(Json patch) => client.patch<Json>('/v1/business/manage/profile', data: patch);

  /// Uploads an image (base64). Purpose 'logo' or 'cover' applies it to the shop right away.
  Future<({String id, String url})> uploadImage(String purpose, List<int> bytes) async {
    final d = await client.post<Json>('/v1/business/manage/media', data: {'purpose': purpose, 'dataBase64': base64Encode(bytes)});
    return (id: d['id'] as String, url: d['url'] as String);
  }

  // ---------- Online store ----------
  Future<Json> storeInfo() => client.get<Json>('/v1/business/manage/store');
  Future<void> setStoreEnabled(bool enabled) => client.put<Json>('/v1/business/manage/store', data: {'enabled': enabled});
  Future<String> createStoreCategory(String name) async =>
      (await client.post<Json>('/v1/business/manage/store/categories', data: {'name': name}))['id'] as String;
  Future<void> patchStoreCategory(String id, Json data) => client.patch<Json>('/v1/business/manage/store/categories/$id', data: data);
  Future<Json> storeProduct(String id) => client.get<Json>('/v1/business/manage/store/products/$id');
  Future<void> createStoreProduct(Json data) => client.post<Json>('/v1/business/manage/store/products', data: data);
  Future<void> patchStoreProduct(String id, Json data) => client.patch<Json>('/v1/business/manage/store/products/$id', data: data);
  Future<List<Json>> storeOrders() async => (await client.get<List<dynamic>>('/v1/business/manage/store/orders')).cast<Json>();
  Future<void> setOrderStatus(String id, String status) =>
      client.post<Json>('/v1/business/manage/store/orders/$id/status', data: {'status': status});

  Future<List<Json>> offers() async => (await client.get<List<dynamic>>('/v1/business/manage/offers')).cast<Json>();
  Future<void> createOffer(Json data) => client.post<Json>('/v1/business/manage/offers', data: data);
  Future<void> patchOffer(String id, Json data) => client.patch<Json>('/v1/business/manage/offers/$id', data: data);

  Future<List<Json>> bookings(String status) async =>
      (await client.get<List<dynamic>>('/v1/business/manage/bookings', query: {'status': status})).cast<Json>();
  Future<Json> bookingSummary() => client.get<Json>('/v1/business/manage/bookings/summary');
  Future<void> acceptBooking(String id) => client.post<Json>('/v1/business/manage/bookings/$id/accept');
  Future<void> declineBooking(String id, String? reason) => client.post<Json>(
        '/v1/business/manage/bookings/$id/decline',
        data: {if (reason != null && reason.trim().length >= 2) 'reason': reason.trim()},
      );

  Future<List<Json>> rewards() async => (await client.get<List<dynamic>>('/v1/business/manage/rewards')).cast<Json>();
  Future<void> createReward(Json data) => client.post<Json>('/v1/business/manage/rewards', data: data);
  Future<void> patchReward(String id, Json data) => client.patch<Json>('/v1/business/manage/rewards/$id', data: data);

  Future<List<Json>> products() async => (await client.get<List<dynamic>>('/v1/business/manage/products')).cast<Json>();
  Future<void> createProduct(Json data) => client.post<Json>('/v1/business/manage/products', data: data);
  Future<void> patchProduct(String id, Json data) => client.patch<Json>('/v1/business/manage/products/$id', data: data);

  Future<List<Json>> orders() async => (await client.get<List<dynamic>>('/v1/business/manage/orders')).cast<Json>();

  // Counter: offers, bookings and rewards (customer's QR required; spending points answers 202 for approval).
  Future<Json> redeemBooking(String id, String qr, String key) =>
      client.post<Json>('/v1/business/cashier/bookings/$id/redeem', idempotent: true, idempotencyKey: key, data: {'qr': qr});
  Future<Json> applyOffer(String id, String qr, String key) =>
      client.post<Json>('/v1/business/cashier/offers/$id/apply', idempotent: true, idempotencyKey: key, data: {'qr': qr});
  Future<Json> redeemReward(String id, String qr, String key) =>
      client.post<Json>('/v1/business/cashier/rewards/$id/redeem', idempotent: true, idempotencyKey: key, data: {'qr': qr});

  // ---------- v0.7: live alerts, redeem approvals, Mukafaah Points ----------
  /// Owner reads `/manage/alerts`, a counter device `/cashier/alerts`. Without [after]
  /// the server only returns the latest cursor, so polling starts from "now".
  Future<({List<BizAlert> alerts, String? cursor})> alerts({required bool owner, String? after}) async {
    final d = await client.get<Json>(
      owner ? '/v1/business/manage/alerts' : '/v1/business/cashier/alerts',
      query: {if (after != null) 'after': after},
    );
    return (
      alerts: [for (final a in (d['alerts'] as List?) ?? const []) BizAlert(a as Json)],
      cursor: d['cursor']?.toString(),
    );
  }

  /// `{ id, status, title, points, result?, error? }`
  Future<Json> redeemRequest(String id) => client.get<Json>('/v1/business/cashier/redeem-requests/$id');
  Future<void> cancelRedeemRequest(String id) => client.post<Json>('/v1/business/cashier/redeem-requests/$id/cancel');

  /// Spends company Mukafaah Points at this shop (always needs the customer's approval).
  Future<Json> mukafaahRedeem({String? userId, String? qr, required int points, int? billMinor, required String key}) =>
      client.post<Json>(
        '/v1/business/cashier/mukafaah/redeem',
        idempotent: true,
        idempotencyKey: key,
        data: {
          if (userId != null) 'userId': userId else if (qr != null) 'qr': qr,
          'points': points,
          if (billMinor != null && billMinor > 0) 'billMinor': billMinor,
        },
      );

  Future<void> voidTx(String txId) => client.post<Json>('/v1/business/cashier/transactions/$txId/void');
}

class OtpChallenge {
  const OtpChallenge({required this.id, required this.resendInSec, this.devCode});
  final String id;
  final int resendInSec;
  final String? devCode;
}
