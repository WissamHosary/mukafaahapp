// Mukafaah Manager - in-browser demo API.
// Answers every /v1 call the Manager makes with realistic demo data kept in memory,
// so the Manager can be clicked through with no server. A reload resets everything.
// Built into a single page by tools/manager-demo/build.py.
(function () {
  'use strict';
  const realFetch = window.fetch.bind(window);
  const uid = () => 'xxxxxxxx-xxxx-4xxx-8xxx-xxxxxxxxxxxx'.replace(/x/g, () => ((Math.random() * 16) | 0).toString(16));
  const now = () => new Date().toISOString();
  const daysAgo = (d) => new Date(Date.now() - d * 864e5).toISOString();
  const LOGO = window.MK_DEMO_LOGO || '';

  // Coloured placeholder pictures (SVG), so banners and products look real.
  const pic = (a, b, label) => 'data:image/svg+xml;utf8,' + encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" width="800" height="400" viewBox="0 0 800 400"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${a}"/><stop offset="1" stop-color="${b}"/></linearGradient></defs><rect width="800" height="400" fill="url(#g)"/><circle cx="660" cy="80" r="150" fill="#fff" opacity=".08"/><circle cx="120" cy="360" r="120" fill="#fff" opacity=".06"/>${label ? `<text x="48" y="340" font-family="Arial,sans-serif" font-size="44" font-weight="700" fill="#fff" opacity=".9">${label}</text>` : ''}</svg>`);
  const mono = (bg, txt) => 'data:image/svg+xml;utf8,' + encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200"><rect width="200" height="200" rx="40" fill="${bg}"/><text x="100" y="124" text-anchor="middle" font-family="Arial,sans-serif" font-size="72" font-weight="700" fill="#fff">${txt}</text></svg>`);

  const media = {}; // id -> url (uploads during the demo)
  const week = (o, c) => [0, 1, 2, 3, 4, 5, 6].map((i) => (i === 6 ? null : { open: o, close: c }));

  const cats = [
    ['RESTAURANTS_CAFES', 'Restaurants & Coffee Shops', 'مطاعم ومقاهي'], ['FASHION', 'Fashion', 'أزياء'], ['BEAUTY', 'Beauty & Spa', 'تجميل'],
    ['FITNESS', 'Fitness & Sports', 'رياضة'], ['GIFTS', 'Gifts & Flowers', 'هدايا'], ['SWEETS', 'Sweets & Bakery', 'حلويات'],
  ].map(([key, nameEn, nameAr], i) => ({ key, nameEn, nameAr, emoji: null, iconId: null, iconUrl: null, sort: i * 10, active: true, shops: 0 }));

  const mkShop = (name, category, city, color, initials, extra = {}) => {
    const id = uid();
    return {
      row: {
        id, name, category, city, status: 'ACTIVE', listed: true, featured: false, featuredSort: 0, programType: 'IN_STORE', programName: null,
        earnPercent: 10, logoUrl: mono(color, initials), coverUrl: pic(color, '#2C123F'), owner: '•••• ' + String(1000 + Math.floor(Math.random() * 8999)),
        whatsapp: true, visits30d: 20 + Math.floor(Math.random() * 300), offers: 1, adminNote: null, friendsEnabled: false, friendsMaxPoints: 0,
        storeEnabled: false, createdAt: daysAgo(40 + Math.floor(Math.random() * 60)), ...extra,
      },
      detail: {
        description: `${name} in ${city}.`, whatsapp: '+961 70 123 456', instagram: name.toLowerCase().replace(/[^a-z]/g, ''), facebook: null, tiktok: null,
        website: null, phone: '+961 1 234 567', hours: null, openingHours: week('09:00', '22:00'), temporarilyClosed: false, address: 'Main street, ' + city,
        lat: 33.8938 + Math.random() * 0.02, lng: 35.5018 + Math.random() * 0.02, allowTransfer: true, pointsPerDollar: 10,
        storePickup: true, storeDelivery: true, deliveryFeeMinor: 300, freeDeliveryOverMinor: 5000, minOrderMinor: 1000, deliveryNote: 'Beirut only, 1-2 hours',
        owner: { name: 'Rami Haddad', phone: '+961 70 123 456' }, branches: [{ id: uid(), name: 'Main' }], minBillMinor: 0,
        banners: [{ id: uid(), url: pic(color, '#E9B800'), caption: null }, { id: uid(), url: pic('#2C123F', color), caption: null }],
      },
    };
  };
  const SH = [
    mkShop('Cedar Cafe', 'RESTAURANTS_CAFES', 'Hamra', '#6B3FA0', 'CC', { friendsEnabled: true, friendsMaxPoints: 500, storeEnabled: true, featured: true }),
    mkShop('Grill House', 'RESTAURANTS_CAFES', 'Achrafieh', '#C2410C', 'GH', { programType: 'SHARED', programName: 'Hamra Food Circle' }),
    mkShop('Maison Lina', 'FASHION', 'Verdun', '#0F766E', 'ML', { storeEnabled: true, friendsEnabled: true, friendsMaxPoints: 800 }),
    mkShop('Glow Studio', 'BEAUTY', 'Achrafieh', '#BE185D', 'GS', { programType: 'NETWORK', programName: 'Beirut Network' }),
    mkShop('Iron Gym', 'FITNESS', 'Jounieh', '#1D4ED8', 'IG'),
    mkShop('Saida Sweets', 'SWEETS', 'Saida', '#B45309', 'SS', { status: 'PAUSED', listed: false }),
  ];
  const shops = SH.map((s) => s.row);
  const detail = Object.fromEntries(SH.map((s) => [s.row.id, s.detail]));
  const byId = (id) => shops.find((s) => s.id === id);
  cats.forEach((c) => { c.shops = shops.filter((s) => s.category === c.key).length; });

  const banners = [
    { id: uid(), titleEn: 'Earn at every visit', titleAr: 'اكسب مع كل زيارة', subtitleEn: '10% back in points', subtitleAr: null, imageId: null, imageUrl: pic('#2C123F', '#6B3FA0'), style: 'PURPLE', actionType: 'NONE', actionValue: null, startsAt: null, endsAt: null, sort: 10, active: true },
    { id: uid(), titleEn: 'Mukafaah Friends', titleAr: 'أصدقاء مكافأة', subtitleEn: 'Spend Mukafaah points at partner shops', subtitleAr: null, imageId: null, imageUrl: pic('#E9B800', '#B45309'), style: 'GOLD', actionType: 'SHOP', actionValue: shops[0].id, startsAt: null, endsAt: null, sort: 20, active: true },
  ];
  const sections = [['CATEGORIES', 'Categories'], ['BANNERS', 'Banners'], ['FEATURED_SHOPS', 'Featured shops'], ['NEW_OFFERS', 'New offers'], ['NEARBY_SHOPS', 'Near you']]
    .map(([type, titleEn], i) => ({ id: uid(), type, titleEn, titleAr: null, categoryKey: null, shopIds: [], maxItems: 12, sort: i, active: true }));
  const offers = [
    { id: uid(), title: 'Free espresso with breakfast', businessName: 'Cedar Cafe', imageUrl: null, kind: 'FREE_ITEM', pointsCost: 0, requiresBooking: true, status: 'ACTIVE', hidden: false, validTo: null, bookings: 4 },
    { id: uid(), title: '20% off the mixed grill', businessName: 'Grill House', imageUrl: null, kind: 'DISCOUNT', pointsCost: 0, requiresBooking: false, status: 'ACTIVE', hidden: false, validTo: daysAgo(-20), bookings: 0 },
    { id: uid(), title: 'Facial for 1,500 points', businessName: 'Glow Studio', imageUrl: null, kind: 'POINTS', pointsCost: 1500, requiresBooking: true, status: 'ACTIVE', hidden: false, validTo: null, bookings: 2 },
  ];
  let settings = { tiers: { GOLD: 2500, PLATINUM: 10000 }, transfer: { minPoints: 10, dailyMaxPoints: 20000, dailyMaxCount: 10, minTier: 'GOLD' }, referral: { windowDays: 14 }, support: { whatsapp: '+961 70 000 000', instagram: 'mukafaah.app' }, defaults: { earnPercent: 10 }, home: {} };
  let tiers = [
    { code: 'SILVER', name: 'Silver', nameAr: 'فضي', minSpendMinor: 0, bonusPoints: 0, color: '#9AA0A6', perks: 'Earn points at every shop', active: true, customers: 1320 },
    { code: 'GOLD', name: 'Gold', nameAr: 'ذهبي', minSpendMinor: 20000, bonusPoints: 100, color: '#E9B800', perks: 'Send points to friends', active: true, customers: 410 },
    { code: 'PLATINUM', name: 'Platinum', nameAr: 'بلاتيني', minSpendMinor: 200000, bonusPoints: 300, color: '#5B2BD6', perks: 'Exclusive offers', active: true, customers: 72 },
  ];
  const accounts = [
    { userId: 'u-owner', name: 'Demo Owner', phoneLast4: '0000', role: 'OWNER', active: true, shops: [], createdAt: daysAgo(90) },
    { userId: uid(), name: 'Nadim Khoury', phoneLast4: '3456', role: 'SHOP', active: true, shops: [{ id: shops[0].id, name: shops[0].name }], createdAt: daysAgo(10) },
  ];
  const rules = [
    { code: 'SIGNUP', title: 'Download the app and join', points: 100, active: true },
    { code: 'REFERRAL', title: 'Invite a friend who joins', points: 200, active: true },
    { code: 'FIRST_BILL', title: 'Your first bill at any shop', points: 50, active: false },
  ];
  const customers = [['Lara Haddad', 'FEMALE', 27, 'GOLD', 2400], ['Karim Nassar', 'MALE', 34, 'SILVER', 650], ['Maya Saad', 'FEMALE', 22, 'PLATINUM', 9100], ['Omar Fakhry', 'MALE', 41, 'SILVER', 120], ['Rita Khalil', 'FEMALE', 30, 'GOLD', 3300]]
    .map(([name, gender, age, tier, balance], i) => ({ id: uid(), name, phone: `+961 70 ${100 + i * 37} ${200 + i * 11}`, email: null, gender, age, hasPassword: i % 2 === 0, referralCode: 'MK' + (4821 + i), balance, lifetime: balance * 3, tier, visits: 3 + i * 4, createdAt: daysAgo(5 + i * 9) }));
  const programs = [
    { id: uid(), type: 'SHARED', name: 'Hamra Food Circle', description: 'Earn at one, spend at all', active: true, earnPercent: 10, outstandingPoints: 48200, members: [shops[0], shops[1]].map((s) => ({ shopId: s.id, name: s.name, category: s.category, city: s.city, logoUrl: s.logoUrl, maxPercent: 100, maxPoints: null, joinedAt: daysAgo(30) })) },
    { id: uid(), type: 'NETWORK', name: 'Beirut Network', description: null, active: true, earnPercent: 8, outstandingPoints: 120400, members: [shops[3], shops[4]].map((s) => ({ shopId: s.id, name: s.name, category: s.category, city: s.city, logoUrl: s.logoUrl, maxPercent: 50, maxPoints: 1500, joinedAt: daysAgo(20) })) },
  ];

  // Per-shop catalog
  const store = {}, orders = {}, offersOf = {}, rewardsOf = {}, reviews = {}, staff = {};
  for (const s of shops) {
    const c1 = uid(), c2 = uid();
    const prods = s.category === 'FASHION'
      ? [['Linen shirt', 4500, 5900, '#0F766E', [{ name: 'Size', values: ['S', 'M', 'L'] }, { name: 'Colour', values: ['White', 'Sand', 'Olive'] }]], ['Silk scarf', 2500, null, '#BE185D', []]]
      : [['House blend 250g', 1200, null, '#6B3FA0', [{ name: 'Grind', values: ['Whole bean', 'Espresso', 'Filter'] }]], ['Cedar mug', 900, 1200, '#2C123F', [{ name: 'Colour', values: ['Black', 'White'] }]]];
    store[s.id] = {
      enabled: s.storeEnabled, hasWhatsapp: true,
      categories: [{ id: c1, name: s.category === 'FASHION' ? 'Shirts' : 'Coffee', imageUrl: pic('#6B3FA0', '#2C123F'), imageId: null, sort: 0 }, { id: c2, name: 'Accessories', imageUrl: null, imageId: null, sort: 1 }],
      products: prods.map(([name, priceMinor, compareAtMinor, color, options], i) => {
        const variants = [];
        const combos = options.reduce((acc, o) => acc.flatMap((a) => o.values.map((v) => [...a, v])), [[]]);
        if (options.length) combos.forEach((ov, j) => variants.push({ id: uid(), optionValues: ov, priceMinor: priceMinor + (j % 3) * 200, stock: (j * 3) % 7, active: true }));
        return { id: uid(), name, description: 'A favourite at ' + s.name + '. Made with care, ready the same day.', categoryId: i ? c2 : c1, priceMinor, maxPriceMinor: variants.length ? Math.max(...variants.map((v) => v.priceMinor)) : priceMinor, compareAtMinor, imageIds: [], imageUrls: [pic(color, '#E9B800')], trackStock: true, stock: variants.length ? null : 8, options, variants, available: true, featured: i === 0 };
      }),
    };
    orders[s.id] = s.storeEnabled ? [
      { id: uid(), code: 'K7P2Q', status: 'NEW', fulfilment: 'DELIVERY', address: 'Hamra, Bliss st, bldg 12', items: [{ qty: 2, name: store[s.id].products[0].name, variant: 'M / White', priceMinor: 4700 }], subtotalMinor: 9400, deliveryFeeMinor: 0, totalMinor: 9400, note: 'Ring twice', createdAt: daysAgo(0.05), customer: 'Lara Haddad', phone: '+961 70 111 555' },
      { id: uid(), code: 'M3X8T', status: 'CONFIRMED', fulfilment: 'PICKUP', address: null, items: [{ qty: 1, name: store[s.id].products[1].name, variant: null, priceMinor: 900 }], subtotalMinor: 900, deliveryFeeMinor: 0, totalMinor: 900, note: null, createdAt: daysAgo(1.2), customer: 'Karim Nassar', phone: '+961 71 222 333' },
    ] : [];
    offersOf[s.id] = [{ id: uid(), title: 'Free espresso', description: 'With any breakfast', terms: null, imageUrl: null, kind: 'FREE_ITEM', discountPercent: null, pointsCost: 0, savingMinor: 250, requiresBooking: true, maxPerCustomer: 1, totalLimit: null, validFrom: daysAgo(10).slice(0, 10), validTo: null, status: 'ACTIVE', hiddenByAdmin: false, stats: { requested: 1, accepted: 2, redeemed: 7 } }];
    rewardsOf[s.id] = [{ id: uid(), title: 'Free croissant', description: null, imageUrl: null, pointsCost: 300, valueMinor: 300, stock: null, status: 'ACTIVE', redeemed: 14 }, { id: uid(), title: 'Gift box', description: null, imageUrl: null, pointsCost: 1500, valueMinor: 1500, stock: 5, status: 'ACTIVE', redeemed: 2 }];
    reviews[s.id] = [['Lara Haddad', 5], ['Karim Nassar', 4], ['Maya Saad', 5], ['Omar Fakhry', 3]].map(([name, stars], i) => ({ userId: uid(), name, stars, comment: null, hidden: false, at: daysAgo(i * 3 + 1) }));
    const br = detail[s.id].branches[0];
    staff[s.id] = { staff: [{ id: uid(), name: 'Rami', active: true, branchId: br.id, branchName: br.name, limits: { canRedeem: true, maxBillMinor: 100000 } }], devices: [{ id: uid(), label: 'Counter 1', status: 'ACTIVE', branch_name: br.name, last_seen_at: daysAgo(0.1) }], branches: detail[s.id].branches };
  }
  const allOrders = () => shops.flatMap((s) => (orders[s.id] || []).map((o) => ({ ...o, shopId: s.id, shopName: s.name })));

  function report(shopId) {
    let seed = 7; const rnd = (a, b) => { seed = (seed * 9301 + 49297) % 233280; return a + Math.floor((seed / 233280) * (b - a)); };
    const d = new Date(); const ym = d.toISOString().slice(0, 7); const days = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
    const daily = Array.from({ length: days }, (_, i) => ({ date: `${ym}-${String(i + 1).padStart(2, '0')}`, bills: rnd(5, 40), billsMinor: rnd(20000, 90000), pointsIssued: rnd(2000, 9000), pointsRedeemed: rnd(200, 4000), newCustomers: rnd(0, 12), orders: rnd(0, 5) }));
    const k = { newCustomers: 120, activeCustomers: 430, bills: 812, billsMinor: 2245000, pointsIssued: 224500, prepointsIssued: 12000, pointsRedeemed: 83000, redemptions: 210, rewardsRedeemed: 64, bookingsUsed: 33, walkinOffersUsed: 21, bookingsRequested: 58, bookingsAccepted: 44, orders: 37, ordersMinor: 124500, ordersCompleted: 29, newShops: 3, avgBillMinor: 2765 };
    const prev = Object.fromEntries(Object.entries(k).map(([a, v]) => [a, Math.round(v * 0.82)]));
    return {
      month: ym, prevMonth: ym, shopId: shopId || null, kpis: k, prev, totals: { customers: 1802, activeShops: shops.filter((s) => s.status === 'ACTIVE').length, outstandingPoints: 540000 }, daily,
      heatmap: Array.from({ length: 7 }, () => Array.from({ length: 24 }, (_, h) => (h >= 8 && h <= 22 ? rnd(0, 10) : 0))),
      categories: cats.slice(0, 4).map((c, i) => ({ key: c.key, name: c.nameEn, bills: 400 - i * 80, billsMinor: 1200000 - i * 250000, pointsIssued: 1 })),
      shops: shops.map((x, i) => ({ id: x.id, name: x.name, category: x.category, status: x.status, earnPercent: x.earnPercent, bills: 300 - i * 30, billsMinor: 900000 - i * 90000, pointsIssued: 90000 - i * 9000, pointsRedeemed: 30000 - i * 3000, redeemRate: 33, customers: 120 - i * 10, orders: x.storeEnabled ? 5 : 0, ordersMinor: x.storeEnabled ? 30000 : 0, offersUsed: 12, rewardsRedeemed: 8, rating: 4.6 - i * 0.1 })),
      cashiers: [{ name: 'Rami', shop: shops[0].name, bills: 140, billsMinor: 400000, pointsIssued: 40000 }, { name: 'Maya', shop: shops[2].name, bills: 96, billsMinor: 310000, pointsIssued: 31000 }],
      tiers: { SILVER: 1320, GOLD: 410, PLATINUM: 72 },
    };
  }

  const shopCard = (s) => ({ ...s, offers: (offersOf[s.id] || []).length });
  const upload = (b) => { const id = uid(); media[id] = b?.dataBase64 || LOGO; return { id, url: media[id] }; };
  const err = (status, code) => ({ status, body: { code } });

  // ---------- router ----------
  function handle(m, path, q, b) {
    const A = '/v1/admin/';
    if (path === '/v1/auth/otp/request') return { challengeId: uid(), devCode: '123456' };
    if (path === '/v1/auth/otp/verify') return { accessToken: 'demo-' + uid(), refreshToken: 'demo-' + uid() };
    if (path === '/v1/auth/refresh') return { accessToken: 'demo-' + uid(), refreshToken: 'demo-' + uid() };
    if (path === '/v1/auth/logout') return { ok: true };
    if (!path.startsWith(A)) return err(404, 'NOT_FOUND');
    const p = path.slice(A.length).split('/');

    switch (p[0]) {
      case 'me': return { userId: 'u-owner', name: 'Demo Owner', phoneLast4: '0000', role: 'OWNER', shops: [] };
      case 'overview': {
        const all = allOrders();
        return { shops: shops.length, liveShops: shops.filter((s) => s.status === 'ACTIVE' && s.listed).length, users: 1802, newUsers7d: 46, issued30d: 224500, redeemed30d: 83000, bills30dMinor: 2245000, liveOffers: offers.filter((o) => !o.hidden).length, pendingBookings: 3, orders30d: all.length, newOrders: all.filter((o) => o.status === 'NEW').length,
          recentOrders: all.sort((a, z) => z.createdAt.localeCompare(a.createdAt)).slice(0, 6).map((o) => ({ id: o.id, code: o.code, status: o.status, totalMinor: o.totalMinor, fulfilment: o.fulfilment, createdAt: o.createdAt, shopId: o.shopId, shopName: o.shopName })),
          topShops: shops.slice(0, 5).map((s) => ({ id: s.id, name: s.name, visits: s.visits30d, billsMinor: s.visits30d * 2400 })) };
      }
      case 'media': return upload(b);
      case 'categories':
        if (!p[1]) { if (m === 'GET') return cats; if (cats.some((c) => c.key === b.key)) return err(409, 'CATEGORY_EXISTS'); cats.push({ iconUrl: b.iconId ? media[b.iconId] : null, shops: 0, sort: 999, active: true, ...b }); return { key: b.key }; }
        { const i = cats.findIndex((c) => c.key === p[1]); if (m === 'DELETE') cats.splice(i, 1); else Object.assign(cats[i], b, b.iconId ? { iconUrl: media[b.iconId] } : {}); return { ok: true }; }
      case 'banners':
        if (!p[1]) { if (m === 'GET') return banners; const d = { id: uid(), imageUrl: b.imageId ? media[b.imageId] : null, sort: 999, active: true, ...b }; banners.push(d); return { id: d.id }; }
        { const i = banners.findIndex((x) => x.id === p[1]); if (m === 'DELETE') banners.splice(i, 1); else Object.assign(banners[i], b, b.imageId ? { imageUrl: media[b.imageId] } : {}); return { ok: true }; }
      case 'sections':
        if (!p[1]) { if (m === 'GET') return sections; const d = { id: uid(), sort: 999, active: true, ...b }; sections.push(d); return { id: d.id }; }
        { const i = sections.findIndex((x) => x.id === p[1]); if (m === 'DELETE') sections.splice(i, 1); else Object.assign(sections[i], b); return { ok: true }; }
      case 'reorder': { const L = { banners, sections }[b.type]; if (L) L.sort((x, y) => b.ids.indexOf(x.id) - b.ids.indexOf(y.id)); return { ok: true }; }
      case 'offers': if (p[1]) { Object.assign(offers.find((o) => o.id === p[1]) || {}, b); return { ok: true }; } return offers;
      case 'rewards': return shops.flatMap((s) => rewardsOf[s.id].map((r) => ({ ...r, businessName: s.name })));
      case 'customers': return customers;
      case 'settings': if (p[1]) { settings[p[1]] = b; return { ok: true }; } return settings;
      case 'tiers': if (m === 'PUT') { tiers = b.tiers.map((t) => ({ ...t, customers: (tiers.find((x) => x.code === t.code) || {}).customers || 0 })); } return { tiers };
      case 'admins': return accounts.map((a) => ({ userId: a.userId, role: a.role, active: a.active, name: a.name, phone: '•••• ' + a.phoneLast4 }));
      case 'accounts':
        if (!p[1]) {
          if (m === 'GET') return { accounts };
          const d = { userId: uid(), name: b.name || 'New member', phoneLast4: String(b.phone || '').replace(/\D/g, '').slice(-4) || '0000', role: b.role || 'SHOP', active: true, shops: (b.shopIds || []).map((id) => ({ id, name: byId(id)?.name })), createdAt: now() };
          accounts.push(d); return d;
        }
        { const a = accounts.find((x) => x.userId === p[1]); if (a) Object.assign(a, b, b.shopIds ? { shops: b.shopIds.map((id) => ({ id, name: byId(id)?.name })) } : {}); return a || { ok: true }; }
      case 'mukafaah':
        if (p[1] === 'grant') return { ok: true, balance: 450 };
        if (p[1] === 'rules') { Object.assign(rules.find((r) => r.code === p[2]) || {}, b); return { ok: true }; }
        return { rules, totals: { issued: 52400, redeemed: 11150, outstanding: 41250 }, friends: shops.filter((s) => s.friendsEnabled).map((s) => ({ id: s.id, name: s.name, friendsEnabled: true, maxPoints: s.friendsMaxPoints, redeemedPoints: 3200 })) };
      case 'programs': {
        if (!p[1]) {
          if (m === 'GET') return { programs, shops: shops.filter((s) => s.programType === 'IN_STORE').map((s) => ({ id: s.id, name: s.name, category: s.category, logoUrl: s.logoUrl, programType: s.programType, programName: null })) };
          const d = { id: uid(), active: true, outstandingPoints: 0, members: [], earnPercent: 10, description: null, ...b }; programs.push(d); return { id: d.id };
        }
        const g = programs.find((x) => x.id === p[1]);
        if (p[2] === 'members' && g) {
          if (m === 'DELETE') { g.members = g.members.filter((x) => x.shopId !== p[3]); const s = byId(p[3]); if (s) { s.programType = 'IN_STORE'; s.programName = null; } }
          else { const s = byId(p[3]); const ex = g.members.find((x) => x.shopId === p[3]); if (ex) Object.assign(ex, b); else if (s) { g.members.push({ shopId: s.id, name: s.name, category: s.category, city: s.city, logoUrl: s.logoUrl, maxPercent: 100, maxPoints: null, joinedAt: now(), ...b }); s.programType = g.type; s.programName = g.name; } }
          return { ok: true };
        }
        if (g && m === 'DELETE') programs.splice(programs.indexOf(g), 1); else if (g) Object.assign(g, b);
        return { ok: true };
      }
      case 'logins':
        if (p[1] === 'check') { const u = q.get('username') || ''; return { valid: /^[a-z0-9._]{3,}$/.test(u), available: !/taken|cedar\.cafe/.test(u) }; }
        return { ok: true };
      case 'reports': return report(q.get('shopId'));
      case 'shops': return shopRoute(m, p.slice(1), q, b);
    }
    return err(404, 'NOT_FOUND');
  }

  function shopRoute(m, p, q, b) {
    if (!p.length) {
      if (m === 'GET') return shops.map(shopCard);
      const r = mkShop(b.name, b.category, b.city || 'Beirut', '#6B3FA0', (b.name || 'N').slice(0, 2).toUpperCase(), { createdAt: now(), visits30d: 0, earnPercent: b.earnPercent ?? 10, logoUrl: b.logoId ? media[b.logoId] : null, coverUrl: b.coverId ? media[b.coverId] : null, storeEnabled: !!b.storeEnabled });
      r.detail.banners = []; Object.assign(r.detail, { description: b.description ?? null, address: b.address ?? null, whatsapp: b.whatsapp ?? null, instagram: b.instagram ?? null, lat: b.lat ?? null, lng: b.lng ?? null });
      shops.unshift(r.row); detail[r.row.id] = r.detail;
      store[r.row.id] = { enabled: !!b.storeEnabled, hasWhatsapp: !!b.whatsapp, categories: [], products: [] }; orders[r.row.id] = []; offersOf[r.row.id] = []; rewardsOf[r.row.id] = []; reviews[r.row.id] = [];
      staff[r.row.id] = { staff: [], devices: [], branches: r.detail.branches };
      return { id: r.row.id };
    }
    const id = p[0], s = byId(id), d = detail[id];
    if (!s) return err(404, 'NOT_FOUND');
    const rest = p.slice(1);
    const sub = rest[0];
    if (!sub) {
      if (m === 'GET') return { ...s, ...d, storeEnabled: s.storeEnabled };
      Object.assign(s, b); if (b.logoId) s.logoUrl = media[b.logoId]; if (b.coverId) s.coverUrl = media[b.coverId];
      if ('storeEnabled' in b) store[id].enabled = b.storeEnabled;
      return { ok: true };
    }
    switch (sub) {
      case 'profile': Object.assign(d, b); ['name', 'category', 'city', 'listed'].forEach((k) => { if (k in b) s[k] = b[k]; }); if (b.logoId) s.logoUrl = media[b.logoId]; if (b.coverId) s.coverUrl = media[b.coverId]; return { ok: true };
      case 'friends': s.friendsEnabled = !!b.enabled; s.friendsMaxPoints = b.maxPoints ?? s.friendsMaxPoints; return { ok: true };
      case 'media': return upload(b);
      case 'banners':
        if (m === 'POST') { const x = { id: uid(), url: b.dataBase64 || (b.mediaId && media[b.mediaId]) || LOGO, caption: b.caption ?? null }; d.banners.push(x); return x; }
        if (rest[1] === 'order') { d.banners.sort((x, y) => b.ids.indexOf(x.id) - b.ids.indexOf(y.id)); return { ok: true }; }
        d.banners = d.banners.filter((x) => x.id !== rest[1]); return { ok: true };
      case 'reviews':
        if (m === 'GET') return reviews[id];
        Object.assign(reviews[id].find((r) => r.userId === rest[1]) || {}, b); return { ok: true };
      case 'offers':
        if (m === 'GET') return offersOf[id];
        if (m === 'POST') { offersOf[id].unshift({ id: uid(), status: 'ACTIVE', hiddenByAdmin: false, stats: { requested: 0, accepted: 0, redeemed: 0 }, imageUrl: b.imageId ? media[b.imageId] : null, ...b }); return { id: offersOf[id][0].id }; }
        Object.assign(offersOf[id].find((o) => o.id === rest[1]) || {}, b, b.imageId ? { imageUrl: media[b.imageId] } : {}); return { ok: true };
      case 'rewards':
        if (m === 'GET') return rewardsOf[id];
        if (m === 'POST') { rewardsOf[id].unshift({ id: uid(), status: 'ACTIVE', redeemed: 0, imageUrl: b.imageId ? media[b.imageId] : null, ...b }); return { id: rewardsOf[id][0].id }; }
        Object.assign(rewardsOf[id].find((o) => o.id === rest[1]) || {}, b, b.imageId ? { imageUrl: media[b.imageId] } : {}); return { ok: true };
      case 'bookings':
        return q.get('status') === 'REQUESTED' || !q.get('status') ? [{ id: uid(), code: 'ABC123', status: 'REQUESTED', offerTitle: 'Free espresso', customerName: 'Lara Haddad', requestedFor: null, partySize: 2, createdAt: daysAgo(0.2) }] : [];
      case 'store': return storeRoute(m, id, rest.slice(1), b);
      case 'orders':
        if (m === 'GET') return orders[id];
        Object.assign(orders[id].find((o) => o.id === rest[1]) || {}, { status: b.status }); return { ok: true };
      case 'staff':
        if (m === 'GET') return staff[id];
        if (m === 'POST') { const br = staff[id].branches.find((x) => x.id === b.branchId) || staff[id].branches[0]; staff[id].staff.push({ id: uid(), active: true, branchName: br?.name, limits: { canRedeem: true }, ...b }); return { ok: true }; }
        Object.assign(staff[id].staff.find((x) => x.id === rest[1]) || {}, b); return { ok: true };
      case 'branches': { const br = { id: uid(), name: b.name }; d.branches.push(br); return br; }
      case 'pairing-codes': return { code: Math.random().toString(36).slice(2, 10).toUpperCase(), branchName: d.branches[0].name };
      case 'devices': { const dv = staff[id].devices.find((x) => x.id === rest[1]); if (dv) dv.status = 'REVOKED'; return { ok: true }; }
      case 'bills': return [['EARN', 2500, 250, 'Lara Haddad', 'INV-1001'], ['EARN', 4200, 420, 'Karim Nassar', 'INV-1002'], ['REDEEM', 0, -300, 'Maya Saad', null]].map(([type, billMinor, points, customer, invoiceNo], i) => ({ type, billMinor, points, createdAt: daysAgo(i * 0.4), voided: false, staffName: 'Rami', customer, invoiceNo, refType: null }));
      case 'logins':
        if (m === 'GET') return { owner: { id: uid(), username: s.name.toLowerCase().replace(/[^a-z]/g, '') + '.owner', active: true, lastLoginAt: daysAgo(1), name: d.owner.name, phoneLast4: '3456' }, ownerName: d.owner.name, workers: staff[id].staff.map((w, i) => ({ staffId: w.id, loginId: i ? null : uid(), name: w.name, username: i ? null : 'counter.' + w.name.toLowerCase(), active: w.active, canRedeem: true, hasPin: false, branchId: w.branchId, branchName: w.branchName, lastLoginAt: null })), branches: d.branches };
        if (rest[1] === 'workers' && m === 'POST' && !rest[2]) { const br = d.branches[0]; const w = { id: uid(), name: b.name || 'Worker', active: true, branchId: b.branchId || br.id, branchName: br.name, limits: { canRedeem: !!b.canRedeem } }; staff[id].staff.push(w); return { ok: true, staffId: w.id }; }
        return { ok: true };
    }
    return { ok: true, id: uid() };
  }

  function storeRoute(m, id, p, b) {
    const st = store[id];
    const card = (x) => ({ id: x.id, name: x.name, priceMinor: x.priceMinor, maxPriceMinor: x.maxPriceMinor, compareAtMinor: x.compareAtMinor, imageUrl: x.imageUrls[0] || null, inStock: true, hasVariants: x.variants.length > 0, options: x.options, trackStock: x.trackStock, stock: x.stock, available: x.available, featured: x.featured, categoryId: x.categoryId });
    if (!p.length) {
      if (m === 'GET') return { enabled: st.enabled, hasWhatsapp: st.hasWhatsapp, newOrders: (orders[id] || []).filter((o) => o.status === 'NEW').length, categories: st.categories.map((c) => ({ ...c, products: st.products.filter((x) => x.categoryId === c.id).length })), products: st.products.map(card) };
      Object.assign(st, b); if ('enabled' in b) byId(id).storeEnabled = b.enabled; return { ok: true };
    }
    if (p[0] === 'categories') {
      if (m === 'POST') { const c = { id: uid(), name: b.name, imageId: b.imageId || null, imageUrl: b.imageId ? media[b.imageId] : null, sort: st.categories.length }; st.categories.push(c); return c; }
      const c = st.categories.find((x) => x.id === p[1]);
      if (m === 'DELETE') { st.categories = st.categories.filter((x) => x !== c); return { ok: true }; }
      Object.assign(c || {}, b, b.imageId ? { imageUrl: media[b.imageId] } : {}); return { ok: true };
    }
    if (p[0] === 'products') {
      const fill = (x) => {
        if (b.imageIds) x.imageUrls = b.imageIds.map((i) => media[i]).filter(Boolean);
        x.variants = (x.variants || []).map((v) => ({ id: v.id || uid(), active: true, ...v }));
        const prices = x.variants.length ? x.variants.map((v) => v.priceMinor ?? x.priceMinor) : [x.priceMinor];
        x.maxPriceMinor = Math.max(...prices);
        return x;
      };
      if (m === 'GET') return st.products.find((x) => x.id === p[1]);
      if (m === 'POST') { const x = fill({ id: uid(), imageUrls: [], options: [], variants: [], available: true, featured: false, trackStock: false, stock: null, compareAtMinor: null, ...b }); st.products.unshift(x); return { id: x.id }; }
      const x = st.products.find((y) => y.id === p[1]); if (x) fill(Object.assign(x, b)); return { ok: true };
    }
    return { ok: true };
  }

  window.fetch = async function (input, init = {}) {
    const url = new URL(typeof input === 'string' ? input : input.url, location.href);
    if (!url.pathname.startsWith('/v1/')) return realFetch(input, init);
    const m = (init.method || 'GET').toUpperCase();
    let b = null; try { b = init.body ? JSON.parse(init.body) : null; } catch { b = null; }
    await new Promise((r) => setTimeout(r, 120 + Math.random() * 180));
    let out;
    try { out = handle(m, url.pathname, url.searchParams, b || {}); } catch (e) { console.error('[demo api]', m, url.pathname, e); out = { status: 500, body: { code: 'DEMO_ERROR' } }; }
    const isErr = out && typeof out === 'object' && 'status' in out && 'body' in out && Object.keys(out).length === 2;
    const status = isErr ? out.status : 200;
    const body = isErr ? out.body : out ?? { ok: true };
    if (status >= 400) console.warn('[demo api]', status, m, url.pathname);
    return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
  };
})();
