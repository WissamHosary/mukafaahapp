// Arabic (default) and English strings for both apps.
// Lebanese-friendly Modern Standard Arabic, matching the brand's tone.
// ignore_for_file: public_member_api_docs

class S {
  const S(this.lang);

  final String lang;
  bool get isAr => lang == 'ar';
  String tr(String ar, String en) => isAr ? ar : en;

  // ---------- Common ----------
  String get appName => tr('مكافأة', 'Mukafaah');
  String get points => tr('نقطة', 'pts');
  String get pointsWord => tr('نقاط', 'Points');
  String get continueLabel => tr('متابعة', 'Continue');
  String get save => tr('حفظ', 'Save');
  String get cancel => tr('إلغاء', 'Cancel');
  String get confirm => tr('تأكيد', 'Confirm');
  String get done => tr('تم', 'Done');
  String get retry => tr('إعادة المحاولة', 'Try again');
  String get close => tr('إغلاق', 'Close');
  String get language => tr('اللغة', 'Language');
  String get arabic => 'العربية';
  String get english => 'English';
  String get logout => tr('تسجيل الخروج', 'Sign out');
  String get logoutAll => tr('الخروج من كل الأجهزة', 'Sign out of all devices');
  String get somethingWrong => tr('حصل خطأ', 'Something went wrong');
  String get noConnection => tr('ما في اتصال بالسيرفر', "Can't reach Mukafaah");
  String get noConnectionHint => tr('تأكد من الإنترنت وجرّب مرة ثانية', 'Check your connection and try again');
  String get today => tr('اليوم', 'Today');
  String get last7 => tr('٧ أيام', '7 days');
  String get last30 => tr('٣٠ يوم', '30 days');
  String get inStore => tr('داخل المتجر', 'In-Store');
  String get shared => tr('مشترك', 'Shared');
  String get network => tr('شبكة مغلقة', 'Closed Network');
  String programType(String t) => switch (t) { 'SHARED' => shared, 'NETWORK' => network, _ => inStore };

  // ---------- Auth ----------
  String get welcomeTitle => tr('اربح وين ما كنت\nبمحفظة وحدة', 'Earn everywhere.\nOne wallet.');
  String get welcomeBody => tr('نقاط، عروض ومكافآت من كل محلاتك المفضلة بمكان واحد.', 'Points, offers and rewards from your favourite places, in one app.');
  String get getStarted => tr('يلا نبلش', 'Get started');
  String get phoneTitle => tr('شو رقم تلفونك؟', "What's your phone number?");
  String get phoneBody => tr('رح نبعتلك رمز تحقق برسالة.', "We'll text you a verification code.");
  String get otpTitle => tr('أدخل رمز التحقق', 'Enter the code');
  String otpBody(String last4) => tr('بعتنالك رمز من ٦ أرقام على واتساب، للرقم المنتهي بـ $last4', 'We sent a 6-digit code on WhatsApp to the number ending $last4');
  String resendIn(int s) => tr('إعادة الإرسال بعد $s ث', 'Resend in ${s}s');
  String get resend => tr('إعادة إرسال الرمز', 'Resend code');
  String get devCode => tr('رمز التجربة', 'Test code');
  String get nameTitle => tr('شو اسمك؟', "What's your name?");
  String get nameBody => tr('رح يظهر للمحلات اللي بتزورها.', 'Shops you visit will see it.');
  String get nameHint => tr('الاسم', 'Your name');

  // ---------- Errors by API code ----------
  String error(String code) => switch (code) {
        'NETWORK' || 'TIMEOUT' => noConnection,
        'OTP_INVALID' => tr('الرمز غلط أو انتهت صلاحيته', 'Wrong or expired code'),
        'OTP_TOO_MANY_ATTEMPTS' => tr('محاولات كثيرة، اطلب رمز جديد', 'Too many attempts, request a new code'),
        'OTP_COOLDOWN' => tr('استنى شوي قبل ما تطلب رمز جديد', 'Please wait before requesting a new code'),
        'OTP_LIMIT_PHONE' || 'OTP_LIMIT_IP' || 'OTP_LIMIT_DEVICE' => tr('طلبات كثيرة، جرّب بعد شوي', 'Too many requests, try again later'),
        'VALIDATION_FAILED' => tr('تأكد من المعلومات', 'Please check the details'),
        'LOGIN_INVALID' => tr('الرقم أو كلمة السر غلط', 'Wrong phone number or password'),
        'LOGIN_LOCKED' => tr('محاولات كثيرة. جرّب بعد ١٥ دقيقة أو غيّر كلمة السر برمز واتساب', 'Too many tries. Wait 15 minutes or reset it with a WhatsApp code'),
        'LOGIN_LIMIT_IP' || 'CHECK_LIMIT' => tr('طلبات كثيرة، جرّب بعد شوي', 'Too many requests, try again later'),
        'PASSWORD_WRONG' => tr('كلمة السر الحالية غلط', 'Current password is wrong'),
        'PASSWORD_CODE_NEEDED' => tr('أكّد رقمك برمز واتساب أول', 'Confirm your number with a WhatsApp code first'),
        'OTP_SEND_FAILED' => tr('ما قدرنا نبعت الرمز على واتساب، جرّب كمان مرة', "Couldn't send the code on WhatsApp, try again"),
        'INSUFFICIENT_BALANCE' => tr('النقاط مش كافية', 'Not enough points'),
        'STAFF_LIMIT_BILL' => tr('الفاتورة أعلى من الحد المسموح إلك', 'Bill is above your limit'),
        'STAFF_LIMIT_TX' => tr('النقاط أعلى من حدك للفاتورة', 'Points exceed your per-bill limit'),
        'STAFF_LIMIT_DAY' => tr('وصلت للحد اليومي', 'Daily limit reached'),
        'PREPOINTS_LIMIT_PHONE' => tr('وصل هالرقم للحد اليومي للنقاط المسبقة', 'Daily Pre-Points limit reached for this number'),
        'NO_POINTS' => tr('هالفاتورة ما بتجيب نقاط', 'This bill earns no points'),
        'QR_EXPIRED' => tr('الرمز انتهى، خلي الزبون يحدّثه', 'QR expired, ask the customer to refresh it'),
        'QR_INVALID' => tr('هيدا مش رمز مكافأة', 'Not a Mukafaah QR'),
        'QR_ALREADY_USED' => tr('الرمز مستعمل، خلي الزبون يعرض رمز جديد', 'QR already used, ask for a fresh one'),
        'NOT_ACCEPTED_HERE' => tr('هالنقاط ما بتنصرف بهالمحل', "These points can't be used here"),
        'REDEEM_NOT_ALLOWED' => tr('ما عندك صلاحية الصرف', "You're not allowed to redeem"),
        'PIN_INVALID' => tr('الرمز السري غلط', 'Wrong PIN'),
        'STAFF_LOCKED' => tr('الحساب مقفول ١٥ دقيقة', 'Locked for 15 minutes'),
        'PAIRING_CODE_INVALID' => tr('رمز الربط غلط أو منتهي', 'Pairing code is wrong or expired'),
        'DEVICE_NOT_PAIRED' => tr('هالجهاز مش مربوط', 'This device is not paired'),
        'VOID_WINDOW_PASSED' => tr('انتهت مدة الإلغاء، اطلب من المالك', 'Void window passed, ask the owner'),
        'ALREADY_REVERSED' => tr('العملية ملغاة من قبل', 'Already reversed'),
        'BUSINESS_EXISTS' => tr('عندك محل من قبل', 'You already have a business'),
        'UNAUTHORIZED' => tr('انتهت الجلسة، سجّل دخول من جديد', 'Session ended, please sign in again'),
        _ => somethingWrong,
      };

  // ---------- Customer ----------
  String hello(String? name) => name == null || name.isEmpty ? tr('أهلا', 'Hello') : tr('أهلا $name', 'Hello $name');
  String get totalBalance => tr('رصيدك الكلي', 'Your total balance');
  String get home => tr('الرئيسية', 'Home');
  String get wallet => tr('المحفظة', 'Wallet');
  String get myQr => tr('رمزي', 'My QR');
  String get explore => tr('اكتشف', 'Explore');
  String get account => tr('حسابي', 'Account');
  String get yourPrograms => tr('برامجك', 'Your programs');
  String get recentActivity => tr('آخر العمليات', 'Recent activity');
  String get seeAll => tr('عرض الكل', 'See all');
  String get noActivityTitle => tr('بلّش اربح نقاط', 'Start earning points');
  String get noActivityBody => tr('اعرض رمزك عند الكاشير بأي محل مشترك بمكافأة.', 'Show your QR at the counter of any Mukafaah shop.');
  String get noProgramsTitle => tr('محفظتك فاضية لهلق', 'Your wallet is empty for now');
  String usableAt(int n) => tr('بينصرف بـ $n محل', 'Usable at $n ${n == 1 ? 'place' : 'places'}');
  String get qrTitle => tr('اعرض هالرمز للكاشير', 'Show this to the cashier');
  String qrRefresh(int s) => tr('بيتجدد بعد $s ث', 'Refreshes in ${s}s');
  String get qrHint => tr('الرمز بيتغير كل شوي لحمايتك. ما حدا بيقدر يستعمل لقطة شاشة.', 'The code changes often to protect you. Screenshots won’t work.');
  String get prePointsTitle => tr('عندك نقاط ناطرتك!', 'Points are waiting for you!');
  String prePointsBody(int p) => tr('جمعت $p نقطة قبل ما تنزّل التطبيق. اضغط جمع لتصير بمحفظتك.', 'You earned $p points before joining. Tap Collect to add them to your wallet.');
  String get collect => tr('جمع النقاط', 'Collect');
  String collected(int p) => tr('انضافوا $p نقطة لمحفظتك', '$p points added to your wallet');
  String fromBusinesses(String list) => tr('من: $list', 'From: $list');
  String get pendingBanner => tr('عندك نقاط مسبقة جاهزة للجمع', 'You have Pre-Points ready to collect');
  String get earned => tr('ربحت', 'Earned');
  String get redeemed => tr('صرفت', 'Redeemed');
  String get collectedTx => tr('نقاط مسبقة', 'Pre-Points collected');
  String get reversed => tr('ملغاة', 'Reversed');
  String txLabel(String type) => switch (type) {
        'EARN' => earned,
        'REDEEM' => redeemed,
        'PREPOINT_CLAIM' => collectedTx,
        'VOID' || 'REVERSAL' => reversed,
        _ => type,
      };
  String get exploreTitle => tr('محلات على مكافأة', 'Places on Mukafaah');
  String earnRate(int perUnit) => tr('$perUnit نقطة لكل \$١', '$perUnit pts per \$1');
  String get noBusinesses => tr('ما في محلات لهلق', 'No places yet');
  String get phone => tr('الهاتف', 'Phone');
  String get profile => tr('الملف الشخصي', 'Profile');
  String get security => tr('الأمان', 'Security');
  String get version => tr('الإصدار', 'Version');

  // ---------- Business ----------
  String get businessApp => tr('مكافأة للأعمال', 'Mukafaah Business');
  String get chooseMode => tr('كيف بدك تستعمل الجهاز؟', 'How will you use this device?');
  String get ownerMode => tr('أنا صاحب المحل', "I'm the owner");
  String get ownerModeBody => tr('لوحة التحكم، الإعدادات، الموظفين والتقارير', 'Dashboard, settings, staff and reports');
  String get counterMode => tr('جهاز الكاشير', 'Counter device');
  String get counterModeBody => tr('سجّل النقاط للزباين بسرعة', 'Give and redeem points fast');
  String get setupBusiness => tr('عرّفنا على محلك', 'Tell us about your business');
  String get businessName => tr('اسم المحل', 'Business name');
  String get categoryLabel => tr('الفئة', 'Category');
  String get branchName => tr('اسم الفرع', 'Branch name');
  String get mainBranch => tr('الفرع الرئيسي', 'Main branch');
  String get earnRateLabel => tr('نقاط لكل \$١', 'Points per \$1');
  String get redeemRateLabel => tr('نقاط مقابل \$١ خصم', 'Points for \$1 discount');
  String get minBillLabel => tr('أقل فاتورة (\$)', 'Minimum bill (\$)');
  String get createBusiness => tr('إنشاء المحل', 'Create business');
  String categoryName(String c) => switch (c) {
        'RESTAURANT' => tr('مطعم', 'Restaurant'),
        'CAFE' => tr('مقهى', 'Café'),
        'RETAIL' => tr('تجزئة', 'Retail'),
        'FASHION' => tr('أزياء', 'Fashion'),
        'BEAUTY' => tr('تجميل', 'Beauty'),
        'GROCERY' => tr('سوبرماركت', 'Grocery'),
        'PHARMACY' => tr('صيدلية', 'Pharmacy'),
        'SERVICES' => tr('خدمات', 'Services'),
        _ => tr('غير ذلك', 'Other'),
      };
  String get dashboard => tr('لوحة التحكم', 'Dashboard');
  String get transactions => tr('العمليات', 'Transactions');
  String get team => tr('الفريق', 'Team');
  String get settings => tr('الإعدادات', 'Settings');
  String get billsEntered => tr('مجموع الفواتير', 'Bills entered');
  String get txCount => tr('عدد العمليات', 'Transactions');
  String get pointsIssued => tr('نقاط ممنوحة', 'Points issued');
  String get pointsRedeemed => tr('نقاط مصروفة', 'Points redeemed');
  String get prePointsIssued => tr('نقاط مسبقة', 'Pre-Points issued');
  String get customers => tr('زباين', 'Customers');
  String get newCustomers => tr('زباين جدد', 'New customers');
  String get returningCustomers => tr('زباين راجعين', 'Returning');
  String get cashierPerformance => tr('أداء الكاشير', 'Cashier performance');
  String get byBranch => tr('حسب الفرع', 'By branch');
  String get activity => tr('النشاط', 'Activity');
  String get noData => tr('ما في بيانات لهالفترة', 'No data for this period');
  String get reverse => tr('إلغاء العملية', 'Reverse');
  String get reverseReason => tr('سبب الإلغاء', 'Reason for reversal');
  String get reversedOk => tr('انلغت العملية', 'Transaction reversed');
  String get staff => tr('الموظفين', 'Staff');
  String get addCashier => tr('إضافة كاشير', 'Add cashier');
  String get cashierName => tr('اسم الكاشير', 'Cashier name');
  String get pin => tr('رمز سري (٤-٦ أرقام)', 'PIN (4-6 digits)');
  String get branch => tr('الفرع', 'Branch');
  String get limits => tr('الحدود والصلاحيات', 'Limits & permissions');
  String get maxBill => tr('أعلى فاتورة (\$)', 'Max bill (\$)');
  String get maxPointsTx => tr('أعلى نقاط للفاتورة', 'Max points per bill');
  String get maxPointsDay => tr('أعلى نقاط باليوم', 'Max points per day');
  String get canRedeem => tr('مسموح يصرف نقاط', 'Can redeem points');
  String get voidWindow => tr('مدة الإلغاء (دقائق)', 'Void window (minutes)');
  String get active => tr('فعّال', 'Active');
  String get devices => tr('أجهزة الكاشير', 'Counter devices');
  String get pairDevice => tr('ربط جهاز كاشير', 'Pair a counter device');
  String get pairingCodeTitle => tr('رمز الربط', 'Pairing code');
  String pairingCodeBody(String branch) => tr('أدخل هالرمز على جهاز الكاشير بفرع $branch خلال ١٠ دقائق.', 'Enter this code on the counter device at $branch within 10 minutes.');
  String get revoke => tr('إلغاء الربط', 'Revoke');
  String get loyaltyProgram => tr('برنامج الولاء', 'Loyalty program');
  String get branches => tr('الفروع', 'Branches');
  String get addBranch => tr('إضافة فرع', 'Add branch');
  String get saved => tr('انحفظ', 'Saved');
  String get programMemberships => tr('البرامج المشترك فيها', 'Program memberships');
  String get exampleEarn => tr('مثال: فاتورة \$٢٠', 'Example: \$20 bill');

  // ---------- Cashier ----------
  String get pairTitle => tr('ربط جهاز الكاشير', 'Pair this counter');
  String get pairBody => tr('اطلب من صاحب المحل رمز الربط من تطبيق مكافأة للأعمال.', 'Ask the owner for a pairing code from Mukafaah Business.');
  String get pairingCode => tr('رمز الربط', 'Pairing code');
  String get deviceLabel => tr('اسم الجهاز', 'Device name');
  String get whoIsWorking => tr('مين عالكاشير؟', "Who's at the counter?");
  String get enterPin => tr('أدخل رمزك السري', 'Enter your PIN');
  String get counterHint => tr('امسح رمز الزبون أو اكتب رقم تلفونه', "Scan the customer's QR or type their phone");
  String get scanQr => tr('امسح الرمز', 'Scan QR');
  String get search => tr('بحث', 'Search');
  String get billAmount => tr('قيمة الفاتورة', 'Bill amount');
  String get givePoints => tr('أعطي نقاط', 'Give points');
  String willEarn(int p) => tr('رح يربح $p نقطة', 'Will earn $p pts');
  String get redeem => tr('صرف نقاط', 'Redeem');
  String get pointsToRedeem => tr('عدد النقاط للصرف', 'Points to redeem');
  String discountValue(String v) => tr('خصم $v', '$v off');
  String get memberOnApp => tr('مشترك بمكافأة', 'Mukafaah member');
  String get notOnApp => tr('مش مشترك بعد: رح تنحفظ كنقاط مسبقة', 'Not on the app yet: saved as Pre-Points');
  String get prePointsHere => tr('نقاط مسبقة هون', 'Pre-Points here');
  String get balanceHere => tr('رصيده هون', 'Balance here');
  String get presentedQr => tr('عرض رمزه', 'Showed QR');
  String pointsGiven(int p) => tr('انضافوا $p نقطة', '$p points added');
  String pointsRedeemedMsg(int p) => tr('انصرفوا $p نقطة', '$p points redeemed');
  String newBalance(int p) => tr('الرصيد الجديد: $p', 'New balance: $p');
  String get nextCustomer => tr('الزبون التالي', 'Next customer');
  String get myShift => tr('ورديتي', 'My shift');
  String get voidTx => tr('إلغاء', 'Void');
  String get lock => tr('قفل', 'Lock');
  String get redeemNeedsQr => tr('الصرف بيحتاج رمز الزبون الحي', 'Redeeming needs the customer’s live QR');
  String get unpair => tr('فك ربط الجهاز', 'Unpair device');

  // ---------- Shops, offers, tiers (v0.2) ----------
  String category(String key) => switch (key) {
        'RESTAURANTS_CAFES' => tr('مطاعم ومقاهي', 'Restaurants & Coffee Shops'),
        'FOOD_DRINKS' => tr('أكل ومشروبات', 'Food & Drinks'),
        'FASHION' => tr('أزياء وإكسسوارات', 'Fashion & Accessories'),
        'ELECTRONICS' => tr('إلكترونيات وتكنولوجيا', 'Electronics & Technology'),
        'FITNESS' => tr('رياضة ولياقة', 'Fitness & Sports'),
        'BEAUTY_WELLNESS' => tr('جمال وعناية', 'Beauty & Wellness'),
        'ENTERTAINMENT' => tr('ترفيه وتسلية', 'Entertainment & Leisure'),
        'GIFTS' => tr('هدايا وإكسسوارات', 'Gifts & Accessories'),
        'RETAIL' => tr('تسوّق', 'Retail'),
        'SERVICES' => tr('خدمات', 'Services'),
        _ => tr('غير ذلك', 'Other'),
      };
  static const categoryKeys = [
    'RESTAURANTS_CAFES',
    'FOOD_DRINKS',
    'FASHION',
    'ELECTRONICS',
    'FITNESS',
    'BEAUTY_WELLNESS',
    'ENTERTAINMENT',
    'GIFTS',
    'RETAIL',
    'SERVICES',
    'OTHER',
  ];
  String tier(String key) => switch (key) {
        'GOLD' => tr('ذهبي', 'Gold'),
        'PLATINUM' => tr('بلاتيني', 'Platinum'),
        _ => tr('فضي', 'Silver'),
      };
  String get balancePoints => tr('رصيد النقاط', 'Balance Points');
  String get totalSaving => tr('مجموع التوفير', 'Total Saving');
  String get viewPoints => tr('نقاطي', 'View Points');
  String get offersRewards => tr('العروض والمكافآت', 'Offers & Rewards');
  String get offers => tr('العروض', 'Offers');
  String get rewards => tr('المكافآت', 'Rewards');
  String get categories => tr('الفئات', 'Categories');
  String get featuredShops => tr('محلات مميزة', 'Featured shops');
  String get shops => tr('المحلات', 'Shops');
  String get map => tr('الخريطة', 'Map');
  String get visitShop => tr('زور المحل', 'Visit Shop');
  String pointsBack(String pct) => tr('نقاط مرتجعة: $pct%', 'Points back: $pct%');
  String get noAddress => tr('ما في عنوان', 'No address yet');
  String shopsAvailable(int n) => tr('المحلات المتوفرة ($n)', 'Shops Available ($n)');
  String get all => tr('الكل', 'All');
  String get book => tr('احجز', 'Book');
  String validity(String from, String to) => tr('صالح: $from - $to', 'Validity: $from - $to');
  String get history => tr('السجل', 'History');
  String get totalEarned => tr('مجموع الربح', 'Total Earned');
  String get totalUsed => tr('مجموع المصروف', 'Total Used');
  String get searchShops => tr('ابحث عن محل', 'Search shops');
  String get notifications => tr('الإشعارات', 'Notifications');
  String get tierStatus => tr('مستوى العضوية', 'Tier Status');
  String get transferPoints => tr('تحويل نقاط', 'Transfer Points');
  String get referralNumber => tr('رمز الدعوة', 'Referral Number');
  String get profileSettings => tr('الملف والإعدادات', 'Profile & Settings');
  String get copied => tr('انسخ', 'Copied');
  String get myBookings => tr('حجوزاتي', 'My bookings');
  String bookingStatus(String st) => switch (st) {
        'REQUESTED' => tr('بانتظار المحل', 'Waiting for the shop'),
        'ACCEPTED' => tr('مقبول', 'Accepted'),
        'DECLINED' => tr('مرفوض', 'Declined'),
        'CANCELLED' => tr('ملغى', 'Cancelled'),
        'REDEEMED' => tr('مستعمل', 'Used'),
        _ => tr('منتهي', 'Expired'),
      };
  String get sentTx => tr('نقاط مرسلة', 'Points sent');
  String get receivedTx => tr('نقاط مستلمة', 'Points received');
  String txLabel2(String type, int points) => switch (type) {
        'EARN' => tr('ربح نقاط', 'Points earned'),
        'PREPOINT_CLAIM' => collectedTx,
        'REDEEM' => tr('صرف نقاط', 'Points redeemed'),
        'TRANSFER' => points > 0 ? receivedTx : sentTx,
        'VOID' || 'REVERSAL' => reversed,
        _ => type,
      };
  String errorV2(String code) => switch (code) {
        'OFFER_UNAVAILABLE' => tr('العرض مش متوفر', 'This offer is no longer available'),
        'BOOKING_EXISTS' => tr('عندك حجز لهالعرض', 'You already booked this offer'),
        'OFFER_LIMIT_REACHED' => tr('استعملت هالعرض', 'This offer was already used'),
        'OFFER_SOLD_OUT' => tr('العرض خلص', 'This offer is fully booked'),
        'NO_BOOKING_NEEDED' => tr('ما بدو حجز، اعرض رمزك بالمحل', 'No booking needed, show your QR at the shop'),
        'RECIPIENT_NOT_FOUND' => tr('ما في عضو بهالرقم أو الرمز', 'No member with this number or code'),
        'TRANSFER_DISABLED' => tr('هالمحل ما بيسمح بتحويل نقاطه', "This shop doesn't allow sending its points"),
        'TIER_REQUIRED' => tr('التحويل بيفتح بالمستوى الذهبي', 'Sending points unlocks at Gold'),
        'TRANSFER_DAILY_LIMIT' => tr('وصلت لحد التحويل اليومي', 'Daily sending limit reached'),
        'TRANSFER_TOO_SMALL' => tr('أقل تحويل ١٠ نقاط', 'Send at least 10 points'),
        'REFERRAL_NOT_FOUND' => tr('رمز الدعوة غلط', 'This invite code does not exist'),
        'REFERRAL_USED' => tr('استعملت رمز دعوة من قبل', 'You already used an invite code'),
        'REFERRAL_EXPIRED' => tr('رمز الدعوة بينفع أول ١٤ يوم بس', 'Invite codes work in your first 14 days only'),
        'RATE_AFTER_VISIT' => tr('فيك تقيّم بعد أول زيارة', 'You can rate after your first visit'),
        'NO_WHATSAPP' => tr('المحل ما حط رقم واتساب', 'This shop has no WhatsApp number yet'),
        'PRODUCT_UNAVAILABLE' => tr('في غرض مش متوفر', 'An item is no longer available'),
        'BOOKING_NOT_PENDING' => tr('الحجز انعالج من قبل', 'This booking was already handled'),
        'BOOKING_NOT_ACCEPTED' => tr('الحجز مش مقبول', 'This booking is not accepted'),
        'BOOKING_OTHER_CUSTOMER' => tr('الحجز لزبون تاني', 'This booking belongs to another customer'),
        'REWARD_UNAVAILABLE' => tr('المكافأة مش متوفرة', 'This reward is not available'),
        'REWARD_OUT_OF_STOCK' => tr('المكافأة خلصت', 'This reward is out of stock'),
        'IMAGE_TOO_LARGE' => tr('الصورة كبيرة كتير', 'Image is too large'),
        'IMAGE_TYPE' => tr('استعمل صورة JPG أو PNG', 'Use a JPG or PNG image'),
        _ => error(code),
      };
}
