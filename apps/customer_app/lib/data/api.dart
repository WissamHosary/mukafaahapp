import 'package:mk_core/mk_core.dart';

// ---------- Models (immutable, parsed from server JSON) ----------

class AppUser {
  const AppUser({
    required this.id,
    this.name,
    this.phoneLast4,
    this.email,
    this.gender,
    this.age,
    this.signInMethod = 'PHONE',
    this.needsProfile = false,
    this.hasPassword = false,
  });
  factory AppUser.fromJson(Map<String, dynamic> j, {bool? needsProfile}) => AppUser(
        id: j['id'] as String,
        name: j['name'] as String?,
        phoneLast4: j['phoneLast4'] as String?,
        email: j['email'] as String?,
        gender: j['gender'] as String?,
        age: (j['age'] as num?)?.toInt(),
        signInMethod: j['signInMethod'] as String? ?? (j['email'] != null && j['phoneLast4'] == null ? 'GOOGLE' : 'PHONE'),
        needsProfile: needsProfile ?? j['needsProfile'] as bool? ?? false,
        hasPassword: j['hasPassword'] as bool? ?? false,
      );
  final String id;
  final String? name;
  final String? phoneLast4;

  /// The Gmail address for members who joined with Google.
  final String? email;

  /// MALE or FEMALE.
  final String? gender;
  final int? age;

  /// PHONE or GOOGLE.
  final String signInMethod;

  /// True until the member finishes the sign-up profile.
  final bool needsProfile;

  /// Phone members sign back in with their number and this password.
  final bool hasPassword;

  bool get isGoogle => signInMethod == 'GOOGLE';
}

/// What the phone screen learns before deciding: password or WhatsApp code.
class PhoneStatus {
  const PhoneStatus({required this.exists, required this.hasPassword});
  final bool exists;
  final bool hasPassword;
}

/// Result of a WhatsApp code: signed in, plus a short pass to choose a password.
class OtpResult {
  const OtpResult({required this.user, required this.isNew, required this.needsPassword, this.passwordToken});
  final AppUser user;
  final bool isNew;
  final bool needsPassword;
  final String? passwordToken;
}

class OtpChallenge {
  const OtpChallenge({required this.id, required this.resendInSec, this.devCode});
  final String id;
  final int resendInSec;
  final String? devCode;
}

class ProgramBalance {
  const ProgramBalance({
    required this.programId,
    required this.type,
    required this.name,
    required this.balance,
    required this.usableAt,
  });
  factory ProgramBalance.fromJson(Map<String, dynamic> j) => ProgramBalance(
        programId: j['programId'] as String,
        type: j['type'] as String,
        name: j['name'] as String,
        balance: (j['balance'] as num).toInt(),
        usableAt: ((j['usableAt'] as List?) ?? const [])
            .map((e) => (e as Map)['name'].toString())
            .toList(),
      );
  final String programId;
  final String type;
  final String name;
  final int balance;
  final List<String> usableAt;
}

class Wallet {
  const Wallet({required this.total, required this.programs, this.mukafaahPoints = 0});
  final int total;
  final List<ProgramBalance> programs;

  /// Company points from Mukafaah (referrals, joining, tasks), spendable at Mukafaah Friends shops.
  final int mukafaahPoints;

  /// Shop balances only (the platform program is shown separately).
  List<ProgramBalance> get shopPrograms => programs.where((p) => p.type != 'PLATFORM').toList();
}

class WalletTx {
  const WalletTx({
    required this.id,
    required this.type,
    required this.points,
    required this.programName,
    required this.createdAt,
    this.businessName,
  });
  factory WalletTx.fromJson(Map<String, dynamic> j) => WalletTx(
        id: j['id'] as String,
        type: j['type'] as String,
        points: (j['points'] as num).toInt(),
        programName: j['programName'] as String,
        businessName: j['businessName'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String).toLocal(),
      );
  final String id;
  final String type;
  final int points;
  final String programName;
  final String? businessName;
  final DateTime createdAt;
}

class PrePoints {
  const PrePoints({required this.total, required this.fromBusinesses});
  final int total;
  final List<String> fromBusinesses;
}

class BusinessSummary {
  const BusinessSummary({required this.id, required this.name, required this.category, required this.programs});
  factory BusinessSummary.fromJson(Map<String, dynamic> j) => BusinessSummary(
        id: j['id'] as String,
        name: j['name'] as String,
        category: j['category'] as String,
        programs: ((j['programs'] as List?) ?? const [])
            .map((e) => (type: (e as Map)['type'] as String, earn: (e['earnPointsPerUnit'] as num).toInt()))
            .toList(),
      );
  final String id;
  final String name;
  final String category;
  final List<({String type, int earn})> programs;
}


// ---------- v0.2: shops, offers, rewards, bookings, history, tiers ----------
typedef Json = Map<String, dynamic>;

int _i(Object? v) => (v as num?)?.toInt() ?? 0;
double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
String? _s(Object? v) => v?.toString();
DateTime _dt(Object? v) => DateTime.tryParse(v?.toString() ?? '')?.toLocal() ?? DateTime.now();

class ShopCard {
  const ShopCard({
    required this.id,
    required this.name,
    required this.category,
    required this.programId,
    required this.programType,
    required this.earnPercent,
    this.pointsPerDollar = 100,
    required this.rating,
    required this.ratingCount,
    required this.myPoints,
    required this.offersCount,
    required this.featured,
    required this.hasWhatsapp,
    this.description,
    this.address,
    this.city,
    this.lat,
    this.lng,
    this.logoUrl,
    this.coverUrl,
    this.distanceKm,
  });
  factory ShopCard.fromJson(Json j) => ShopCard(
        id: j['id'] as String,
        name: j['name'] as String,
        category: j['category'] as String,
        programId: j['programId'] as String,
        programType: j['programType'] as String,
        earnPercent: _d(j['earnPercent']),
        pointsPerDollar: (j['pointsPerDollar'] as num?)?.toInt() ?? 100,
        rating: _d(j['rating']),
        ratingCount: _i(j['ratingCount']),
        myPoints: _i(j['myPoints']),
        offersCount: _i(j['offersCount']),
        featured: j['featured'] == true,
        hasWhatsapp: j['hasWhatsapp'] == true,
        description: _s(j['description']),
        address: _s(j['address']),
        city: _s(j['city']),
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        logoUrl: _s(j['logoUrl']),
        coverUrl: _s(j['coverUrl']),
        distanceKm: (j['distanceKm'] as num?)?.toDouble(),
      );
  final String id;
  final String name;
  final String category;
  final String programId;
  final String programType;
  final double earnPercent;

  /// Points worth \$1 at this shop.
  final int pointsPerDollar;
  final double rating;
  final int ratingCount;
  final int myPoints;
  final int offersCount;
  final bool featured;
  final bool hasWhatsapp;
  final String? description;
  final String? address;
  final String? city;
  final double? lat;
  final double? lng;
  final String? logoUrl;
  final String? coverUrl;

  /// How far the shop is from the member, when the app knows where they are.
  final double? distanceKm;

  String get place => [address, city].whereType<String>().where((e) => e.isNotEmpty).join(', ');
  String get earnText => earnPercent == earnPercent.roundToDouble() ? earnPercent.toStringAsFixed(0) : earnPercent.toStringAsFixed(1);
}

class Offer {
  const Offer({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.title,
    required this.kind,
    required this.pointsCost,
    required this.savingMinor,
    required this.requiresBooking,
    required this.validFrom,
    this.businessCategory,
    this.businessLogoUrl,
    this.description,
    this.terms,
    this.imageUrl,
    this.discountPercent,
    this.validTo,
    this.myOpenBooking,
    this.distanceKm,
    this.isNear = false,
  });
  factory Offer.fromJson(Json j) => Offer(
        id: j['id'] as String,
        businessId: j['businessId'] as String,
        businessName: (j['businessName'] ?? '') as String,
        businessCategory: _s(j['businessCategory']),
        businessLogoUrl: _s(j['businessLogoUrl']),
        title: j['title'] as String,
        description: _s(j['description']),
        terms: _s(j['terms']),
        imageUrl: _s(j['imageUrl']),
        kind: (j['kind'] ?? 'DEAL') as String,
        discountPercent: (j['discountPercent'] as num?)?.toInt(),
        pointsCost: _i(j['pointsCost']),
        savingMinor: _i(j['savingMinor']),
        requiresBooking: j['requiresBooking'] != false,
        validFrom: (j['validFrom'] ?? '') as String,
        validTo: _s(j['validTo']),
        myOpenBooking: _s(j['myOpenBooking']),
        distanceKm: (j['distanceKm'] as num?)?.toDouble(),
        isNear: j['isNear'] == true,
      );
  final String id;
  final String businessId;
  final String businessName;
  final String? businessCategory;
  final String? businessLogoUrl;
  final String title;
  final String? description;
  final String? terms;
  final String? imageUrl;
  final String kind;
  final int? discountPercent;
  final int pointsCost;
  final int savingMinor;
  final bool requiresBooking;
  final String validFrom;
  final String? validTo;
  final String? myOpenBooking;
  final double? distanceKm;

  /// Within a few km of the member (shown first).
  final bool isNear;
}

class Reward {
  const Reward({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.title,
    required this.pointsCost,
    required this.valueMinor,
    required this.myPoints,
    required this.canAfford,
    this.description,
    this.imageUrl,
    this.businessLogoUrl,
    this.distanceKm,
    this.isNear = false,
  });
  factory Reward.fromJson(Json j) => Reward(
        id: j['id'] as String,
        businessId: j['businessId'] as String,
        businessName: (j['businessName'] ?? '') as String,
        businessLogoUrl: _s(j['businessLogoUrl']),
        title: j['title'] as String,
        description: _s(j['description']),
        imageUrl: _s(j['imageUrl']),
        pointsCost: _i(j['pointsCost']),
        valueMinor: _i(j['valueMinor']),
        myPoints: _i(j['myPoints']),
        canAfford: j['canAfford'] == true,
        distanceKm: (j['distanceKm'] as num?)?.toDouble(),
        isNear: j['isNear'] == true,
      );
  final String id;
  final String businessId;
  final String businessName;
  final String? businessLogoUrl;
  final String title;
  final String? description;
  final String? imageUrl;
  final int pointsCost;
  final int valueMinor;
  final int myPoints;
  final bool canAfford;
  final double? distanceKm;
  final bool isNear;
}

class Product {
  const Product({required this.id, required this.name, required this.priceMinor, required this.available, this.description, this.imageUrl});
  factory Product.fromJson(Json j) => Product(
        id: j['id'] as String,
        name: j['name'] as String,
        description: _s(j['description']),
        priceMinor: _i(j['priceMinor']),
        imageUrl: _s(j['imageUrl']),
        available: j['available'] != false,
      );
  final String id;
  final String name;
  final String? description;
  final int priceMinor;
  final String? imageUrl;
  final bool available;
}

// ---------- Shop store (optional per shop) ----------

class StoreOption {
  const StoreOption({required this.name, required this.values});
  factory StoreOption.fromJson(Json j) => StoreOption(
        name: j['name'] as String,
        values: ((j['values'] as List?) ?? const []).map((e) => e.toString()).toList(),
      );
  final String name;
  final List<String> values;
}

class StoreVariant {
  const StoreVariant({
    required this.id,
    required this.optionValues,
    required this.priceMinor,
    required this.inStock,
    this.compareAtMinor,
    this.stock,
    this.imageUrl,
  });
  factory StoreVariant.fromJson(Json j) => StoreVariant(
        id: j['id'] as String,
        optionValues: ((j['optionValues'] as List?) ?? const []).map((e) => e.toString()).toList(),
        priceMinor: _i(j['priceMinor']),
        compareAtMinor: j['compareAtMinor'] == null ? null : _i(j['compareAtMinor']),
        stock: j['stock'] == null ? null : _i(j['stock']),
        inStock: j['inStock'] != false,
        imageUrl: _s(j['imageUrl']),
      );
  final String id;
  final List<String> optionValues;
  final int priceMinor;
  final int? compareAtMinor;
  final int? stock;
  final bool inStock;
  final String? imageUrl;

  String get label => optionValues.join(' / ');
}

class StoreProduct {
  const StoreProduct({
    required this.id,
    required this.name,
    required this.priceMinor,
    required this.maxPriceMinor,
    required this.inStock,
    this.description,
    this.categoryId,
    this.compareAtMinor,
    this.imageUrls = const [],
    this.trackStock = false,
    this.stock,
    this.options = const [],
    this.variants = const [],
    this.featured = false,
  });
  factory StoreProduct.fromJson(Json j) => StoreProduct(
        id: j['id'] as String,
        name: j['name'] as String,
        description: _s(j['description']),
        categoryId: _s(j['categoryId']),
        priceMinor: _i(j['priceMinor']),
        maxPriceMinor: _i(j['maxPriceMinor'] ?? j['priceMinor']),
        compareAtMinor: j['compareAtMinor'] == null ? null : _i(j['compareAtMinor']),
        imageUrls: ((j['imageUrls'] as List?) ?? const []).whereType<String>().toList(),
        trackStock: j['trackStock'] == true,
        stock: j['stock'] == null ? null : _i(j['stock']),
        inStock: j['inStock'] != false,
        options: ((j['options'] as List?) ?? const []).map((e) => StoreOption.fromJson(e as Json)).toList(),
        variants: ((j['variants'] as List?) ?? const []).map((e) => StoreVariant.fromJson(e as Json)).toList(),
        featured: j['featured'] == true,
      );
  final String id;
  final String name;
  final String? description;
  final String? categoryId;

  /// Lowest price (variants can cost more, up to [maxPriceMinor]).
  final int priceMinor;
  final int maxPriceMinor;

  /// "Was" price shown crossed out.
  final int? compareAtMinor;
  final List<String> imageUrls;
  final bool trackStock;
  final int? stock;
  final bool inStock;
  final List<StoreOption> options;
  final List<StoreVariant> variants;
  final bool featured;

  bool get hasVariants => options.isNotEmpty;
  String? get imageUrl => imageUrls.isEmpty ? null : imageUrls.first;

  /// The variant matching the chosen values, if any.
  StoreVariant? variantFor(List<String?> chosen) {
    if (chosen.any((v) => v == null)) return null;
    for (final v in variants) {
      var ok = v.optionValues.length == chosen.length;
      for (var i = 0; ok && i < chosen.length; i++) {
        ok = v.optionValues[i] == chosen[i];
      }
      if (ok) return v;
    }
    return null;
  }
}

class StoreData {
  const StoreData({required this.shopName, required this.canOrder, required this.categories, required this.products});
  factory StoreData.fromJson(Json j) => StoreData(
        shopName: (j['shopName'] ?? '') as String,
        canOrder: j['canOrder'] == true,
        categories: ((j['categories'] as List?) ?? const [])
            .map((e) => (id: (e as Map)['id'] as String, name: e['name'] as String))
            .toList(),
        products: ((j['products'] as List?) ?? const []).map((e) => StoreProduct.fromJson(e as Json)).toList(),
      );
  final String shopName;
  final bool canOrder;
  final List<({String id, String name})> categories;
  final List<StoreProduct> products;
}

class ShopDetail {
  const ShopDetail({
    required this.card,
    required this.offers,
    required this.rewards,
    required this.products,
    required this.branches,
    required this.canRate,
    this.instagram,
    this.storeEnabled = false,
    this.myStars,
    this.myComment,
    this.social = const ShopSocial(),
    this.hours,
    this.banners = const [],
    this.reviews = const [],
    this.starCounts = const [0, 0, 0, 0, 0],
  });
  factory ShopDetail.fromJson(Json j) => ShopDetail(
        card: ShopCard.fromJson(j),
        instagram: _s(j['instagram']),
        social: ShopSocial.fromJson((j['social'] as Map?)?.cast<String, dynamic>() ?? {'instagram': j['instagram']}),
        hours: _s(j['hours']),
        banners: ((j['banners'] as List?) ?? const [])
            .map((e) => (url: (e as Map)['url'] as String?, caption: _s(e['caption'])))
            .where((b) => b.url != null)
            .map((b) => ShopBanner(url: b.url!, caption: b.caption))
            .toList(),
        reviews: ((j['reviews'] as List?) ?? const []).map((e) => ShopReview.fromJson(e as Json)).toList(),
        starCounts: ((j['starCounts'] as List?) ?? const [0, 0, 0, 0, 0]).map((e) => (e as num).toInt()).toList(),
        myComment: _s((j['myRating'] as Map?)?['comment']),
        storeEnabled: j['storeEnabled'] == true,
        branches: ((j['branches'] as List?) ?? const []).map((e) => e.toString()).toList(),
        offers: ((j['offers'] as List?) ?? const []).map((e) => Offer.fromJson(e as Json)).toList(),
        rewards: ((j['rewards'] as List?) ?? const []).map((e) => Reward.fromJson(e as Json)).toList(),
        products: ((j['products'] as List?) ?? const []).map((e) => Product.fromJson(e as Json)).toList(),
        myStars: ((j['myRating'] as Map?)?['stars'] as num?)?.toInt(),
        canRate: j['canRate'] == true,
      );
  final ShopCard card;
  final String? instagram;

  /// The shop has an online store (products, variants, WhatsApp orders).
  final bool storeEnabled;
  final List<String> branches;
  final List<Offer> offers;
  final List<Reward> rewards;
  final List<Product> products;
  final int? myStars;
  final String? myComment;
  final bool canRate;
  final ShopSocial social;
  final String? hours;
  final List<ShopBanner> banners;
  final List<ShopReview> reviews;

  /// How many reviews gave 1, 2, 3, 4 and 5 stars.
  final List<int> starCounts;
}

class ShopSocial {
  const ShopSocial({this.instagram, this.facebook, this.tiktok, this.website, this.whatsapp, this.phone});
  factory ShopSocial.fromJson(Json j) => ShopSocial(
        instagram: _s(j['instagram']),
        facebook: _s(j['facebook']),
        tiktok: _s(j['tiktok']),
        website: _s(j['website']),
        whatsapp: _s(j['whatsapp']),
        phone: _s(j['phone']),
      );
  final String? instagram;
  final String? facebook;
  final String? tiktok;
  final String? website;
  final String? whatsapp;
  final String? phone;

  bool get isEmpty => [instagram, facebook, tiktok, website, whatsapp, phone].every((x) => x == null || x.isEmpty);
}

class ShopBanner {
  const ShopBanner({required this.url, this.caption});
  final String url;
  final String? caption;
}

class ShopReview {
  const ShopReview({required this.name, required this.stars, required this.at, this.comment, this.mine = false});
  factory ShopReview.fromJson(Json j) => ShopReview(
        name: j['name'] as String? ?? '',
        stars: (j['stars'] as num).toInt(),
        comment: _s(j['comment']),
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        mine: j['mine'] == true,
      );
  final String name;
  final int stars;
  final String? comment;
  final DateTime at;
  final bool mine;
}

class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.type,
    required this.points,
    required this.createdAt,
    this.businessName,
    this.businessLogoUrl,
    this.counterpartName,
    this.detail,
  });
  factory ActivityItem.fromJson(Json j) => ActivityItem(
        id: j['id'] as String,
        type: j['type'] as String,
        points: _i(j['points']),
        createdAt: _dt(j['createdAt']),
        businessName: _s(j['businessName']),
        businessLogoUrl: _s(j['businessLogoUrl']),
        counterpartName: _s(j['counterpartName']),
        detail: _s(j['detail']),
      );
  final String id;
  final String type;
  final int points;
  final DateTime createdAt;
  final String? businessName;
  final String? businessLogoUrl;
  final String? counterpartName;
  final String? detail;
}

class HomeData {
  const HomeData({
    required this.tier,
    required this.balancePoints,
    required this.totalSavingMinor,
    required this.pendingPrePoints,
    required this.unreadNotifications,
    required this.categories,
    required this.featured,
    required this.sections,
    required this.offers,
    required this.recent,
    this.banners = const [],
    this.bannerLayout = 'UNO',
    this.blocks = const [],
    this.supportWhatsapp,
    this.supportInstagram,
    this.lifetimePoints = 0,
    this.tierMin = 0,
    this.nextTier,
    this.nextTierMin,
    this.name,
    this.referralCode,
  });
  factory HomeData.fromJson(Json j) => HomeData(
        name: _s(j['name']),
        referralCode: _s(j['referralCode']),
        tier: (j['tier'] ?? 'SILVER') as String,
        balancePoints: _i(j['balancePoints']),
        totalSavingMinor: _i(j['totalSavingMinor']),
        pendingPrePoints: _i(j['pendingPrePoints']),
        unreadNotifications: _i(j['unreadNotifications']),
        categories: ((j['categories'] as List?) ?? const []).map((e) => CategoryInfo.fromJson(e as Json)).toList(),
        banners: ((j['banners'] as List?) ?? const []).map((e) => HomeBanner.fromJson(e as Json)).toList(),
        blocks: ((j['blocks'] as List?) ?? const []).map((e) => HomeBlock.fromJson(e as Json)).toList(),
        supportWhatsapp: _s((j['support'] as Map?)?['whatsapp']),
        bannerLayout: _layout(j['bannerLayout']),
        lifetimePoints: _i((j['tierProgress'] as Map?)?['lifetime']),
        tierMin: _i((j['tierProgress'] as Map?)?['currentMin']),
        nextTier: _s((j['tierProgress'] as Map?)?['nextTier']),
        nextTierMin: (j['tierProgress'] as Map?)?['nextMin'] == null ? null : _i((j['tierProgress'] as Map)['nextMin']),
        supportInstagram: _s((j['support'] as Map?)?['instagram']),
        featured: ((j['featured'] as List?) ?? const []).map((e) => ShopCard.fromJson(e as Json)).toList(),
        sections: ((j['sections'] as List?) ?? const [])
            .map(
              (e) => (
                category: (e as Map)['category'] as String,
                shops: ((e['shops'] as List?) ?? const []).map((x) => ShopCard.fromJson(x as Json)).toList(),
              ),
            )
            .toList(),
        offers: ((j['offers'] as List?) ?? const []).map((e) => Offer.fromJson(e as Json)).toList(),
        recent: ((j['recent'] as List?) ?? const []).map((e) => ActivityItem.fromJson(e as Json)).toList(),
      );
  final String? name;
  final String? referralCode;
  final String tier;
  final int balancePoints;
  final int totalSavingMinor;
  final int pendingPrePoints;
  final int unreadNotifications;
  final List<CategoryInfo> categories;

  /// Banners and home blocks come from Mukafaah Manager, in the order set there.
  final List<HomeBanner> banners;

  /// UNO (one wide banner per slide), DUO (two side by side) or TRIO (one tall + two stacked).
  final String bannerLayout;
  final List<HomeBlock> blocks;

  /// Support contacts set in Mukafaah Manager (may be empty).
  final String? supportWhatsapp;
  final String? supportInstagram;

  /// Tier progress for the points card.
  final int lifetimePoints;
  final int tierMin;
  final String? nextTier;
  final int? nextTierMin;

  /// 0..1 progress from the current tier to the next (1 when at the top tier).
  double get tierProgress {
    final n = nextTierMin;
    if (n == null || n <= tierMin) return 1;
    return ((lifetimePoints - tierMin) / (n - tierMin)).clamp(0.0, 1.0);
  }

  final List<ShopCard> featured;
  final List<({String category, List<ShopCard> shops})> sections;
  final List<Offer> offers;
  final List<ActivityItem> recent;
}

String _layout(Object? v) {
  final x = v?.toString().toUpperCase();
  return x == 'DUO' || x == 'TRIO' ? x! : 'UNO';
}

/// A category managed in Mukafaah Manager (name, logo and colour).
class CategoryInfo {
  const CategoryInfo({required this.key, required this.nameEn, required this.nameAr, this.emoji, this.iconUrl, this.color, this.count = 0});
  factory CategoryInfo.fromJson(Json j) => CategoryInfo(
        key: j['key'] as String,
        nameEn: (j['nameEn'] ?? j['key']) as String,
        nameAr: (j['nameAr'] ?? j['nameEn'] ?? j['key']) as String,
        emoji: _s(j['emoji']),
        iconUrl: _s(j['iconUrl']),
        color: _s(j['color']),
        count: _i(j['count']),
      );
  final String key;
  final String nameEn;
  final String nameAr;
  final String? emoji;

  /// Server path of the logo uploaded in Mukafaah Manager.
  final String? iconUrl;

  /// Hex colour like "#7446A8" set in Mukafaah Manager (may be null).
  final String? color;
  final int count;

  String name(bool ar) => ar ? nameAr : nameEn;
}

/// A home carousel banner from Mukafaah Manager.
class HomeBanner {
  const HomeBanner({
    required this.id,
    required this.style,
    required this.actionType,
    this.titleEn,
    this.titleAr,
    this.subtitleEn,
    this.subtitleAr,
    this.imageUrl,
    this.actionValue,
  });
  factory HomeBanner.fromJson(Json j) => HomeBanner(
        id: j['id'] as String,
        style: (j['style'] ?? 'PURPLE') as String,
        actionType: (j['actionType'] ?? 'NONE') as String,
        titleEn: _s(j['titleEn']),
        titleAr: _s(j['titleAr']),
        subtitleEn: _s(j['subtitleEn']),
        subtitleAr: _s(j['subtitleAr']),
        imageUrl: _s(j['imageUrl']),
        actionValue: _s(j['actionValue']),
      );
  final String id;
  final String style;
  final String actionType;
  final String? titleEn;
  final String? titleAr;
  final String? subtitleEn;
  final String? subtitleAr;
  final String? imageUrl;
  final String? actionValue;

  /// Falls back to the other language when one is empty.
  String? title(bool ar) => ar ? (titleAr ?? titleEn) : (titleEn ?? titleAr);
  String? subtitle(bool ar) => ar ? (subtitleAr ?? subtitleEn) : (subtitleEn ?? subtitleAr);
}

/// One section of the home screen, configured in Mukafaah Manager.
class HomeBlock {
  const HomeBlock({
    required this.id,
    required this.type,
    this.titleEn,
    this.titleAr,
    this.categoryKey,
    this.layout = 'ROW',
    this.shops = const [],
    this.offers = const [],
    this.rewards = const [],
  });
  factory HomeBlock.fromJson(Json j) => HomeBlock(
        id: j['id'] as String,
        type: j['type'] as String,
        layout: _s(j['layout']) ?? (j['type'] == 'FEATURED_SHOPS' ? 'CAROUSEL' : j['type'] == 'DISCOVER_SHOPS' ? 'GRID' : 'ROW'),
        titleEn: _s(j['titleEn']),
        titleAr: _s(j['titleAr']),
        categoryKey: _s(j['categoryKey']),
        shops: ((j['shops'] as List?) ?? const []).map((e) => ShopCard.fromJson(e as Json)).toList(),
        offers: ((j['offers'] as List?) ?? const []).map((e) => Offer.fromJson(e as Json)).toList(),
        rewards: ((j['rewards'] as List?) ?? const []).map((e) => Reward.fromJson(e as Json)).toList(),
      );
  final String id;

  /// CATEGORIES, FEATURED_SHOPS, DISCOVER_SHOPS, NEW_OFFERS, CATEGORY_SHOPS, PICKED_SHOPS, REWARDS or RECENT_ACTIVITY.
  final String type;

  /// How a shop section looks, chosen in Mukafaah Manager: CAROUSEL, GRID or ROW.
  final String layout;
  final String? titleEn;
  final String? titleAr;
  final String? categoryKey;
  final List<ShopCard> shops;
  final List<Offer> offers;
  final List<Reward> rewards;

  String? title(bool ar) => ar ? (titleAr ?? titleEn) : (titleEn ?? titleAr);
}

class Booking {
  const Booking({
    required this.id,
    required this.offerId,
    required this.businessId,
    required this.status,
    required this.code,
    required this.createdAt,
    this.requestedFor,
    this.partySize,
    this.note,
    this.declineReason,
    this.offerTitle,
    this.offerImageUrl,
    this.businessName,
    this.businessLogoUrl,
    this.pointsCost,
  });
  factory Booking.fromJson(Json j) => Booking(
        id: j['id'] as String,
        offerId: j['offerId'] as String,
        businessId: j['businessId'] as String,
        status: j['status'] as String,
        code: (j['code'] ?? '') as String,
        createdAt: _dt(j['createdAt']),
        requestedFor: j['requestedFor'] == null ? null : _dt(j['requestedFor']),
        partySize: (j['partySize'] as num?)?.toInt(),
        note: _s(j['note']),
        declineReason: _s(j['declineReason']),
        offerTitle: _s(j['offerTitle']),
        offerImageUrl: _s(j['offerImageUrl']),
        businessName: _s(j['businessName']),
        businessLogoUrl: _s(j['businessLogoUrl']),
        pointsCost: (j['pointsCost'] as num?)?.toInt(),
      );
  final String id;
  final String offerId;
  final String businessId;
  final String status;
  final String code;
  final DateTime createdAt;
  final DateTime? requestedFor;
  final int? partySize;
  final String? note;
  final String? declineReason;
  final String? offerTitle;
  final String? offerImageUrl;
  final String? businessName;
  final String? businessLogoUrl;
  final int? pointsCost;

  bool get isOpen => status == 'REQUESTED' || status == 'ACCEPTED';
}

class HistoryData {
  const HistoryData({required this.totalEarned, required this.totalUsed, required this.items});
  final int totalEarned;
  final int totalUsed;
  final List<ActivityItem> items;
}

/// One membership tier, configured in Mukafaah Manager (spend based).
class TierLevel {
  const TierLevel({
    required this.code,
    required this.name,
    required this.minSpendMinor,
    required this.bonusPoints,
    this.color,
    this.perks = const [],
  });
  factory TierLevel.fromJson(Json j) {
    final p = j['perks'];
    final perks = p is List
        ? p.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
        : (p?.toString() ?? '')
            .split(RegExp(r'[\n;]'))
            .map((e) => e.replaceFirst(RegExp(r'^[\s\-\u2022*]+'), '').trim())
            .where((e) => e.isNotEmpty)
            .toList();
    return TierLevel(
      code: (j['code'] ?? 'SILVER').toString(),
      name: _s(j['name']) ?? (j['code'] ?? '').toString(),
      minSpendMinor: _i(j['minSpendMinor']),
      bonusPoints: _i(j['bonusPoints']),
      color: _s(j['color']),
      perks: perks,
    );
  }
  final String code;
  final String name;
  final int minSpendMinor;

  /// Mukafaah Points granted once when the customer reaches this tier.
  final int bonusPoints;

  /// Hex colour like "#E9B800".
  final String? color;
  final List<String> perks;
}

/// GET /v1/customer/tier: the customer's tier from total spend, and every tier.
class TierData {
  const TierData({
    required this.tier,
    required this.lifetimeSpendMinor,
    required this.tiers,
    this.nextCode,
    this.nextName,
    this.nextMinSpendMinor,
    this.remainingMinor,
    this.achievements = const [],
  });
  factory TierData.fromJson(Json j, bool ar) {
    final nx = j['next'] as Map?;
    return TierData(
      tier: (j['tier'] ?? 'SILVER').toString(),
      lifetimeSpendMinor: _i(j['lifetimeSpendMinor']),
      tiers: ((j['tiers'] as List?) ?? const []).map((e) => TierLevel.fromJson((e as Map).cast<String, dynamic>())).toList()
        ..sort((a, b) => a.minSpendMinor.compareTo(b.minSpendMinor)),
      nextCode: _s(nx?['code']),
      nextName: _s(nx?['name']),
      nextMinSpendMinor: nx?['minSpendMinor'] == null ? null : _i(nx!['minSpendMinor']),
      remainingMinor: nx?['remainingMinor'] == null ? null : _i(nx!['remainingMinor']),
      // Older servers sent achievements; shown only when present.
      achievements: ((j['achievements'] as List?) ?? const []).map((e) {
        final m = e as Map;
        return (
          key: (m['key'] ?? '').toString(),
          done: m['done'] == true,
          progress: _i(m['progress']),
          goal: _i(m['goal']),
          title: ((m['title'] as Map?)?[ar ? 'ar' : 'en'] ?? '').toString(),
        );
      }).toList(),
    );
  }
  final String tier;
  final int lifetimeSpendMinor;
  final List<TierLevel> tiers;
  final String? nextCode;
  final String? nextName;
  final int? nextMinSpendMinor;
  final int? remainingMinor;
  final List<({String key, bool done, int progress, int goal, String title})> achievements;

  TierLevel? get current => tiers.where((t) => t.code == tier).firstOrNull;
  TierLevel? get next => nextCode == null ? null : tiers.where((t) => t.code == nextCode).firstOrNull;

  /// Minimum spend of the current tier.
  int get currentMin => current?.minSpendMinor ?? 0;

  /// 0..1 progress in spend from the current tier to the next (1 at the top tier).
  double get progress {
    final n = nextMinSpendMinor;
    if (n == null || n <= currentMin) return 1;
    return ((lifetimeSpendMinor - currentMin) / (n - currentMin)).clamp(0.0, 1.0);
  }

  /// Amount still to spend to reach the next tier.
  int get toNextMinor => remainingMinor ?? ((nextMinSpendMinor ?? lifetimeSpendMinor) - lifetimeSpendMinor).clamp(0, 1 << 30);
}

// ---------- v0.7: member QR, redeem approvals, Mukafaah Points ----------

/// The customer's fixed member QR. Created once per user and never changes.
class MemberQr {
  const MemberQr({required this.payload, required this.memberCode});
  final String payload;
  final String memberCode;
}

/// A spend started by a cashier that waits for the customer's approval.
class RedeemRequest {
  const RedeemRequest({
    required this.id,
    required this.kind,
    required this.title,
    required this.points,
    required this.valueMinor,
    required this.shopName,
    required this.expiresAt,
    this.shopId,
    this.shopLogoUrl,
  });
  factory RedeemRequest.fromJson(Json j) {
    final shop = (j['shop'] as Map?) ?? const {};
    return RedeemRequest(
      id: j['id'].toString(),
      kind: (j['kind'] ?? 'POINTS').toString(),
      title: (j['title'] ?? '').toString(),
      points: _i(j['points']),
      valueMinor: _i(j['valueMinor']),
      shopId: _s(shop['id']),
      shopName: (shop['name'] ?? '').toString(),
      shopLogoUrl: _s(shop['logoUrl']),
      expiresAt: DateTime.tryParse(j['expiresAt']?.toString() ?? '')?.toLocal() ?? DateTime.now().add(const Duration(minutes: 2)),
    );
  }
  final String id;

  /// POINTS, OFFER, REWARD, BOOKING or MUKAFAAH.
  final String kind;
  final String title;
  final int points;
  final int valueMinor;
  final String? shopId;
  final String shopName;
  final String? shopLogoUrl;
  final DateTime expiresAt;
}

/// GET /v1/customer/mukafaah: company points, how to earn them and where to spend them.
class MukafaahData {
  const MukafaahData({required this.balance, required this.rules, required this.friends, required this.history});
  factory MukafaahData.fromJson(Json j) => MukafaahData(
        balance: _i(j['balance']),
        rules: ((j['rules'] as List?) ?? const [])
            .map((e) => (code: ((e as Map)['code'] ?? '').toString(), title: (e['title'] ?? '').toString(), points: _i(e['points'])))
            .toList(),
        friends: ((j['friends'] as List?) ?? const []).map((e) {
          final m = e as Map;
          return (
            id: m['id'].toString(),
            name: (m['name'] ?? '').toString(),
            logoUrl: _s(m['logoUrl']),
            category: _s(m['category']),
            maxPoints: _i(m['maxPoints']),
          );
        }).toList(),
        history: ((j['history'] as List?) ?? const []).map((e) {
          final m = e as Map;
          return (
            id: m['id'].toString(),
            type: (m['type'] ?? '').toString(),
            points: _i(m['points']),
            title: _s(m['title']),
            createdAt: _dt(m['createdAt']),
          );
        }).toList(),
      );
  final int balance;
  final List<({String code, String title, int points})> rules;
  final List<({String id, String name, String? logoUrl, String? category, int maxPoints})> friends;
  final List<({String id, String type, int points, String? title, DateTime createdAt})> history;
}

class Referral {
  const Referral({required this.code, required this.invitedCount, required this.canEnterCode, this.referredBy});
  final String code;
  final int invitedCount;
  final bool canEnterCode;
  final String? referredBy;
}

class AppNotification {
  const AppNotification({required this.id, required this.kind, required this.title, required this.read, required this.createdAt, this.body});
  factory AppNotification.fromJson(Json j) => AppNotification(
        id: j['id'] as String,
        kind: j['kind'] as String,
        title: j['title'] as String,
        body: _s(j['body']),
        read: j['read'] == true,
        createdAt: _dt(j['createdAt']),
      );
  final String id;
  final String kind;
  final String title;
  final String? body;
  final bool read;
  final DateTime createdAt;
}

/// Filters for the Shops tab.
class ShopQuery {
  const ShopQuery({this.q = '', this.category, this.type, this.sort = 'popular'});
  final String q;
  final String? category;
  final String? type;
  final String sort;

  ShopQuery copy({String? q, String? category, bool clearCategory = false, String? type, bool clearType = false, String? sort}) =>
      ShopQuery(
        q: q ?? this.q,
        category: clearCategory ? null : (category ?? this.category),
        type: clearType ? null : (type ?? this.type),
        sort: sort ?? this.sort,
      );

  @override
  bool operator ==(Object other) =>
      other is ShopQuery && other.q == q && other.category == category && other.type == type && other.sort == sort;

  @override
  int get hashCode => Object.hash(q, category, type, sort);
}

/// All customer API calls. The server is the source of truth for every number.
class CustomerApi {
  CustomerApi(this.client);
  final ApiClient client;

  Future<OtpChallenge> requestOtp(String phone, String locale) async {
    final d = await client.post<Map<String, dynamic>>(
      '/v1/auth/otp/request',
      auth: false,
      data: {'phone': phone, 'app': 'CUSTOMER', 'deviceId': await client.store.deviceId(), 'locale': locale},
    );
    return OtpChallenge(
      id: d['challengeId'] as String,
      resendInSec: (d['resendInSec'] as num).toInt(),
      devCode: d['devCode'] as String?,
    );
  }

  Future<OtpResult> verifyOtp(String challengeId, String code) async {
    final d = await client.post<Map<String, dynamic>>(
      '/v1/auth/otp/verify',
      auth: false,
      data: {'challengeId': challengeId, 'code': code, 'app': 'CUSTOMER', 'deviceLabel': 'Mukafaah app'},
    );
    await client.store.saveTokens(access: d['accessToken'] as String, refresh: d['refreshToken'] as String);
    return OtpResult(
      user: AppUser.fromJson(d['user'] as Map<String, dynamic>, needsProfile: d['needsProfile'] as bool? ?? false),
      isNew: d['isNew'] as bool,
      needsPassword: d['needsPassword'] as bool? ?? false,
      passwordToken: d['passwordToken'] as String?,
    );
  }

  /// Is this number already a member, and do they have a password?
  Future<PhoneStatus> checkPhone(String phone) async {
    final d = await client.post<Map<String, dynamic>>('/v1/auth/phone/check', auth: false, data: {'phone': phone});
    return PhoneStatus(exists: d['exists'] as bool? ?? false, hasPassword: d['hasPassword'] as bool? ?? false);
  }

  /// Members who signed out come back with their phone number and password.
  Future<AppUser> signInWithPassword(String phone, String password) async {
    final d = await client.post<Map<String, dynamic>>(
      '/v1/auth/password/login',
      auth: false,
      data: {'phone': phone, 'password': password, 'app': 'CUSTOMER', 'deviceLabel': 'Mukafaah app'},
    );
    await client.store.saveTokens(access: d['accessToken'] as String, refresh: d['refreshToken'] as String);
    return AppUser.fromJson(d['user'] as Map<String, dynamic>, needsProfile: d['needsProfile'] as bool? ?? false);
  }

  /// Choose a password: after a WhatsApp code ([passwordToken]) or with the current one.
  Future<void> setPassword(String password, {String? passwordToken, String? currentPassword}) => client.post<Json>(
        '/v1/auth/password',
        data: {
          'password': password,
          if (passwordToken != null) 'passwordToken': passwordToken,
          if (currentPassword != null) 'currentPassword': currentPassword,
        },
      );

  /// Signs in with the ID token Google gave the app. The server checks it with Google.
  Future<({AppUser user, bool isNew, String? suggestedName})> signInWithGoogle(String idToken, String locale) async {
    final d = await client.post<Map<String, dynamic>>(
      '/v1/auth/google',
      auth: false,
      data: {'idToken': idToken, 'app': 'CUSTOMER', 'deviceLabel': 'Mukafaah app', 'locale': locale},
    );
    await client.store.saveTokens(access: d['accessToken'] as String, refresh: d['refreshToken'] as String);
    final u = Map<String, dynamic>.from(d['user'] as Map)..['signInMethod'] = 'GOOGLE';
    return (
      user: AppUser.fromJson(u, needsProfile: d['needsProfile'] as bool? ?? false),
      isNew: d['isNew'] as bool,
      suggestedName: d['suggestedName'] as String?,
    );
  }

  /// Finishes sign-up: name (always), age and gender (phone members), and an
  /// optional invite code. Saved together or not at all.
  Future<AppUser> completeProfile({
    required String name,
    int? age,
    String? gender,
    String? referralCode,
    String? locale,
  }) async =>
      AppUser.fromJson(
        await client.post<Map<String, dynamic>>(
          '/v1/customer/profile',
          data: {
            'name': name,
            if (age != null) 'age': age,
            if (gender != null) 'gender': gender,
            if (referralCode != null && referralCode.isNotEmpty) 'referralCode': referralCode,
            if (locale != null) 'locale': locale,
          },
        ),
      );

  /// Checks an invite code while it is typed (does not use it).
  Future<({bool valid, String? referrer})> checkReferral(String code) async {
    final d = await client.get<Map<String, dynamic>>('/v1/customer/referral/check', query: {'code': code});
    return (valid: d['valid'] as bool? ?? false, referrer: d['referrer'] as String?);
  }

  Future<AppUser> me() async => AppUser.fromJson(await client.get<Map<String, dynamic>>('/v1/customer/me'));

  Future<AppUser> updateProfile({String? name, String? locale}) async => AppUser.fromJson(
        await client.patch<Map<String, dynamic>>(
          '/v1/customer/me',
          data: {if (name != null) 'name': name, if (locale != null) 'locale': locale},
        ),
      );

  Future<Wallet> wallet() async {
    final d = await client.get<Map<String, dynamic>>('/v1/customer/wallet');
    return Wallet(
      total: (d['totalPoints'] as num).toInt(),
      programs: (d['programs'] as List).map((e) => ProgramBalance.fromJson(e as Map<String, dynamic>)).toList(),
      mukafaahPoints: _i(d['mukafaahPoints']),
    );
  }

  Future<List<WalletTx>> transactions({int limit = 30}) async {
    final d = await client.get<List<dynamic>>('/v1/customer/wallet/transactions', query: {'limit': limit});
    return d.map((e) => WalletTx.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<PrePoints> prePoints() async {
    final d = await client.get<Map<String, dynamic>>('/v1/customer/prepoints');
    final names = <String>{};
    for (final it in d['items'] as List) {
      for (final b in ((it as Map)['fromBusinesses'] as List? ?? const [])) {
        names.add(b.toString());
      }
    }
    return PrePoints(total: (d['totalPoints'] as num).toInt(), fromBusinesses: names.toList());
  }

  Future<int> collectPrePoints() async {
    final d = await client.post<Map<String, dynamic>>('/v1/customer/prepoints/collect', idempotent: true);
    return (d['collectedPoints'] as num).toInt();
  }

  /// The customer's fixed member QR (`MKF2:<memberCode>`). It never changes.
  Future<MemberQr> memberQr() async {
    try {
      final d = await client.get<Json>('/v1/customer/qr');
      return MemberQr(payload: d['payload'] as String, memberCode: (d['memberCode'] ?? '').toString());
    } on ApiException catch (e) {
      // Older server without the fixed QR: fall back to the token endpoint.
      if (e.status != 404) rethrow;
      final d = await client.post<Json>('/v1/customer/qr/token');
      final payload = (d['payload'] ?? d['token']) as String;
      return MemberQr(payload: payload, memberCode: payload.startsWith('MKF2:') ? payload.substring(5) : '');
    }
  }

  Future<List<RedeemRequest>> pendingRedeemRequests() async {
    final d = await client.get<Json>('/v1/customer/redeem-requests/pending');
    return ((d['requests'] as List?) ?? const []).map((e) => RedeemRequest.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  /// Approves a cashier's spend. Returns APPROVED, FAILED, EXPIRED or DECLINED, with the error when it failed.
  Future<({String status, String? error})> approveRedeem(String id) async {
    final d = await client.post<Json>('/v1/customer/redeem-requests/$id/approve');
    return (status: (d['status'] ?? '').toString(), error: _s(d['error']));
  }

  Future<void> declineRedeem(String id) => client.post<Json>('/v1/customer/redeem-requests/$id/decline');

  Future<MukafaahData> mukafaah() async => MukafaahData.fromJson(await client.get<Json>('/v1/customer/mukafaah'));

  Future<List<BusinessSummary>> businesses() async {
    final d = await client.get<List<dynamic>>('/v1/customer/businesses');
    return d.map((e) => BusinessSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  // ---------- v0.2 ----------
  String? url(String? path) => client.resolve(path);

  /// With the member's location (when allowed) nearby shops come first.
  Future<HomeData> home({double? lat, double? lng}) async => HomeData.fromJson(
        await client.get<Json>('/v1/customer/home', query: {if (lat != null) 'lat': lat, if (lng != null) 'lng': lng}),
      );

  Future<List<CategoryInfo>> categories() async =>
      (await client.get<List<dynamic>>('/v1/customer/categories')).map((e) => CategoryInfo.fromJson(e as Json)).toList();

  Future<({int total, List<ShopCard> shops})> shops(ShopQuery q) async {
    final d = await client.get<Json>(
      '/v1/customer/shops',
      query: {
        if (q.q.isNotEmpty) 'q': q.q,
        if (q.category != null) 'category': q.category,
        if (q.type != null) 'type': q.type,
        'sort': q.sort,
      },
    );
    return (
      total: _i(d['total']),
      shops: ((d['shops'] as List?) ?? const []).map((e) => ShopCard.fromJson(e as Json)).toList(),
    );
  }

  Future<ShopDetail> shop(String id) async => ShopDetail.fromJson(await client.get<Json>('/v1/customer/shops/$id'));

  Future<void> rate(String shopId, int stars, {String? comment}) => client.put<Json>(
        '/v1/customer/shops/$shopId/rating',
        data: {'stars': stars, if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim()},
      );

  /// Places near the member come first (isNear), then every other offer in Mukafaah.
  Future<List<Offer>> offers({String? category, double? lat, double? lng}) async {
    final d = await client.get<List<dynamic>>(
      '/v1/customer/offers',
      query: {if (category != null) 'category': category, if (lat != null) 'lat': lat, if (lng != null) 'lng': lng},
    );
    return d.map((e) => Offer.fromJson(e as Json)).toList();
  }

  Future<List<Reward>> rewards({String? category, double? lat, double? lng}) async {
    final d = await client.get<List<dynamic>>(
      '/v1/customer/rewards',
      query: {if (category != null) 'category': category, if (lat != null) 'lat': lat, if (lng != null) 'lng': lng},
    );
    return d.map((e) => Reward.fromJson(e as Json)).toList();
  }

  Future<Booking> book(String offerId, {DateTime? at, int? partySize, String? note}) async => Booking.fromJson(
        await client.post<Json>(
          '/v1/customer/offers/$offerId/book',
          data: {
            if (at != null) 'requestedFor': at.toUtc().toIso8601String(),
            if (partySize != null) 'partySize': partySize,
            if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          },
        ),
      );

  Future<List<Booking>> bookings() async =>
      (await client.get<List<dynamic>>('/v1/customer/bookings')).map((e) => Booking.fromJson(e as Json)).toList();

  Future<void> cancelBooking(String id) => client.post<Json>('/v1/customer/bookings/$id/cancel');

  Future<HistoryData> history({String filter = 'all', String q = ''}) async {
    final d = await client.get<Json>('/v1/customer/history', query: {'filter': filter, if (q.isNotEmpty) 'q': q});
    return HistoryData(
      totalEarned: _i(d['totalEarned']),
      totalUsed: _i(d['totalUsed']),
      items: ((d['items'] as List?) ?? const []).map((e) => ActivityItem.fromJson(e as Json)).toList(),
    );
  }

  Future<TierData> tier(bool ar) async => TierData.fromJson(await client.get<Json>('/v1/customer/tier'), ar);

  Future<({String? name, String last4})> recipient(String to) async {
    final d = await client.get<Json>('/v1/customer/transfer/recipient', query: {'to': to});
    return (name: _s(d['name']), last4: (d['phoneLast4'] ?? '') as String);
  }

  Future<int> transfer({required String to, required String programId, required int points, String? note, required String key}) async {
    final d = await client.post<Json>(
      '/v1/customer/transfer',
      idempotent: true,
      idempotencyKey: key,
      data: {'to': to, 'programId': programId, 'points': points, if (note != null && note.isNotEmpty) 'note': note},
    );
    return _i(d['newBalance']);
  }

  Future<Referral> referral() async {
    final d = await client.get<Json>('/v1/customer/referral');
    return Referral(
      code: (d['code'] ?? '') as String,
      invitedCount: _i(d['invitedCount']),
      canEnterCode: d['canEnterCode'] == true,
      referredBy: _s(d['referredBy']),
    );
  }

  Future<void> useReferral(String code) => client.post<Json>('/v1/customer/referral', data: {'code': code});

  Future<List<AppNotification>> notifications() async =>
      (await client.get<List<dynamic>>('/v1/customer/notifications')).map((e) => AppNotification.fromJson(e as Json)).toList();

  Future<void> readAllNotifications() => client.post<Json>('/v1/customer/notifications/read-all');

  Future<StoreData> store(String shopId) async => StoreData.fromJson(await client.get<Json>('/v1/customer/shops/$shopId/store'));

  Future<StoreProduct> storeProduct(String shopId, String productId) async =>
      StoreProduct.fromJson(await client.get<Json>('/v1/customer/shops/$shopId/products/$productId'));

  /// Prices and stock are checked by the server; returns the WhatsApp link to send.
  Future<({String url, int totalMinor, String code})> order(
    String shopId,
    List<({String productId, String? variantId, int qty})> items, {
    required bool delivery,
    String? address,
    String? note,
    ({String name, String phone})? contact,
    ({String area, String street, String? building, String? landmark, double? lat, double? lng})? place,
  }) async {
    String? opt(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    final d = await client.post<Json>(
      '/v1/customer/shops/$shopId/order',
      data: {
        'items': [
          for (final it in items) {'productId': it.productId, if (it.variantId != null) 'variantId': it.variantId, 'qty': it.qty},
        ],
        'fulfilment': delivery ? 'DELIVERY' : 'PICKUP',
        if (delivery && opt(address) != null) 'address': opt(address),
        if (opt(note) != null) 'note': opt(note),
        if (contact != null) 'contact': {'name': contact.name.trim(), 'phone': contact.phone.trim()},
        if (delivery && place != null)
          'delivery': {
            'area': place.area.trim(),
            'street': place.street.trim(),
            if (opt(place.building) != null) 'building': opt(place.building),
            if (opt(place.landmark) != null) 'landmark': opt(place.landmark),
            if (place.lat != null && place.lng != null) ...{'lat': place.lat, 'lng': place.lng},
          },
      },
    );
    return (url: d['whatsappUrl'] as String, totalMinor: _i(d['totalMinor']), code: (d['code'] ?? '') as String);
  }

  Future<void> logout({bool all = false}) async {
    try {
      await client.post<Map<String, dynamic>>(all ? '/v1/auth/logout-all' : '/v1/auth/logout');
    } on ApiException {
      // Signing out locally must always succeed.
    }
    await client.store.clearTokens();
  }
}
