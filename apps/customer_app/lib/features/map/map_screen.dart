import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../data/api.dart';
import '../common/common.dart';

/// Shops within this distance of the customer keep the brand colour; farther ones are muted.
const double kNearKm = 5;

enum _Loc { idle, asking, on, denied, deniedForever, serviceOff }

/// Shops on a real street map: branded pins with each shop's logo, search,
/// category filter and a swipeable shop strip that stays in sync with the map.
/// With the customer's permission it shows where they are, sorts shops by
/// distance and mutes the pins that are far away.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> with TickerProviderStateMixin {
  static const _lebanon = LatLng(33.8547, 35.8623);
  final _map = MapController();
  final _strip = PageController(viewportFraction: 0.86);
  String? _selectedId;
  String? _category;
  String _q = '';
  bool _search = false;
  AnimationController? _anim;
  LatLng? _me;
  _Loc _loc = _Loc.idle;

  @override
  void initState() {
    super.initState();
    // If the customer already allowed location, show it straight away (no prompt).
    Geolocator.checkPermission().then((p) {
      if (mounted && (p == LocationPermission.whileInUse || p == LocationPermission.always)) _locate(ask: false);
    }).catchError((Object _) {});
  }

  /// Asks for permission when needed, then centres the map on the customer.
  Future<void> _locate({bool ask = true}) async {
    setState(() => _loc = _Loc.asking);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _loc = _Loc.serviceOff);
        return;
      }
      var p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied && ask) p = await Geolocator.requestPermission();
      if (p == LocationPermission.deniedForever) {
        if (mounted) setState(() => _loc = _Loc.deniedForever);
        return;
      }
      if (p != LocationPermission.whileInUse && p != LocationPermission.always) {
        if (mounted) setState(() => _loc = ask ? _Loc.denied : _Loc.idle);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      if (!mounted) return;
      final me = LatLng(pos.latitude, pos.longitude);
      setState(() {
        _me = me;
        _loc = _Loc.on;
      });
      _fly(me, 12.5);
    } catch (_) {
      if (mounted) setState(() => _loc = _me == null ? _Loc.idle : _Loc.on);
    }
  }

  /// Kilometres from the customer to [x], or null when location is off.
  double? _km(ShopCard x) =>
      _me == null ? null : Geolocator.distanceBetween(_me!.latitude, _me!.longitude, x.lat!, x.lng!) / 1000;

  @override
  void dispose() {
    _anim?.dispose();
    _strip.dispose();
    _map.dispose();
    super.dispose();
  }

  /// Smoothly flies the camera to [to] at [zoom].
  void _fly(LatLng to, double zoom) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _map.move(to, zoom);
      return;
    }
    final from = _map.camera.center;
    final z0 = _map.camera.zoom;
    _anim?.dispose();
    final c = _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
    final a = CurvedAnimation(parent: c, curve: Curves.easeInOutCubic);
    c.addListener(() {
      final v = a.value;
      _map.move(
        LatLng(from.latitude + (to.latitude - from.latitude) * v, from.longitude + (to.longitude - from.longitude) * v),
        z0 + (zoom - z0) * v,
      );
    });
    c.forward();
  }

  void _select(List<ShopCard> shops, ShopCard x, {bool fromStrip = false}) {
    setState(() => _selectedId = x.id);
    _fly(LatLng(x.lat!, x.lng!), math.max(_map.camera.zoom, 14));
    if (!fromStrip && _strip.hasClients) {
      final i = shops.indexWhere((e) => e.id == x.id);
      if (i >= 0) _strip.animateToPage(i, duration: MkMotion.slow, curve: MkMotion.standard);
    }
  }

  void _fitAll(List<ShopCard> shops) {
    if (shops.isEmpty) {
      _fly(_lebanon, 8.6);
      return;
    }
    if (shops.length == 1) {
      _fly(LatLng(shops.first.lat!, shops.first.lng!), 14);
      return;
    }
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: [for (final x in shops) LatLng(x.lat!, x.lng!)],
        padding: const EdgeInsets.fromLTRB(60, 180, 60, 260),
        maxZoom: 15,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final data = ref.watch(shopsProvider(const ShopQuery(sort: 'name')));
    final catInfo = ref.watch(categoriesProvider).value;
    final located = (data.value?.shops ?? const <ShopCard>[]).where((x) => x.lat != null && x.lng != null).toList();
    final shops = located
        .where((x) => (_category == null || x.category == _category) && (_q.isEmpty || x.name.toLowerCase().contains(_q.toLowerCase())))
        .toList();
    // Nearest first once we know where the customer is.
    if (_me != null) shops.sort((a, b) => _km(a)!.compareTo(_km(b)!));
    final nearCount = _me == null ? 0 : shops.where((x) => _km(x)! <= kNearKm).length;
    final cats = <String>{for (final x in located) x.category}.toList();
    final selected = shops.where((x) => x.id == _selectedId).firstOrNull;
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: _lebanon,
              initialZoom: 8.6,
              minZoom: 6,
              maxZoom: 19,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              onTap: (_, _) => setState(() => _selectedId = null),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'app.mukafaah.mukafaah_customer',
                maxNativeZoom: 19,
              ),
              if (_me != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _me!,
                      radius: kNearKm * 1000,
                      useRadiusInMeter: true,
                      color: const Color(0x142563EB),
                      borderColor: const Color(0x662563EB),
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_me != null) Marker(point: _me!, width: 64, height: 64, child: const _MeDot()),
                  // Selected pin last so it draws on top.
                  for (final x in [...shops.where((e) => e.id != _selectedId), ?selected])
                    Marker(
                      point: LatLng(x.lat!, x.lng!),
                      width: 120,
                      height: 86,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        onTap: () => _select(shops, x),
                        child: _ShopPin(
                          selected: x.id == _selectedId,
                          far: (_km(x) ?? 0) > kNearKm,
                          logoUrl: url(x.logoUrl),
                          name: x.name,
                          badge: '${x.earnText}%',
                        ),
                      ),
                    ),
                ],
              ),
              RichAttributionWidget(
                alignment: AttributionAlignment.bottomLeft,
                attributions: [TextSourceAttribution('OpenStreetMap contributors')],
              ),
            ],
          ),
          // Search and filters over the map.
          Positioned(
            left: MkSpace.md,
            right: MkSpace.md,
            top: top + MkSpace.sm,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 52,
                  padding: const EdgeInsetsDirectional.only(start: MkSpace.md, end: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: MkRadius.all(MkRadius.pill),
                    boxShadow: const [BoxShadow(color: Color(0x262C123F), blurRadius: 20, offset: Offset(0, 6))],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded, color: MkColors.ink3),
                      const SizedBox(width: MkSpace.xs),
                      Expanded(
                        child: _search
                            ? TextField(
                                autofocus: true,
                                decoration: InputDecoration.collapsed(hintText: s.tr('دوّر عن محل', 'Search shops')),
                                onChanged: (v) => setState(() => _q = v.trim()),
                              )
                            : GestureDetector(
                                onTap: () => setState(() => _search = true),
                                child: Text(
                                  _me == null
                                      ? s.tr('${shops.length} محل على الخريطة', '${shops.length} shops on the map')
                                      : s.tr('$nearCount محل ضمن ${kNearKm.toInt()} كلم', '$nearCount shops within ${kNearKm.toInt()} km'),
                                  style: t.bodyLarge?.copyWith(color: MkColors.ink2),
                                ),
                              ),
                      ),
                      if (data.isLoading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      if (_search)
                        IconButton(
                          onPressed: () => setState(() {
                            _search = false;
                            _q = '';
                          }),
                          icon: const Icon(Icons.close_rounded),
                        ),
                    ],
                  ),
                ),
                if (cats.length > 1) ...[
                  const SizedBox(height: MkSpace.xs),
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final c in [null, ...cats])
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 6),
                            child: MkPressable(
                              onTap: () => setState(() {
                                _category = c;
                                _selectedId = null;
                              }),
                              child: AnimatedContainer(
                                duration: MkMotion.fast,
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: _category == c ? MkColors.purple900 : Colors.white,
                                  borderRadius: MkRadius.all(MkRadius.pill),
                                  boxShadow: MkShadow.soft,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (c != null) ...[
                                      Icon(MkCategory.icon(c), size: 16, color: _category == c ? MkColors.yellow500 : MkColors.purple700),
                                      const SizedBox(width: 6),
                                    ],
                                    Text(
                                      c == null ? s.all : categoryName(s, catInfo, c),
                                      style: t.labelLarge?.copyWith(color: _category == c ? Colors.white : MkColors.ink),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Map controls.
          PositionedDirectional(
            end: MkSpace.md,
            bottom: shops.isEmpty ? MkSpace.lg : 196,
            child: Container(
              decoration: BoxDecoration(color: Colors.white, borderRadius: MkRadius.all(MkRadius.md), boxShadow: MkShadow.soft),
              child: Column(
                children: [
                  IconButton(
                    tooltip: s.tr('تكبير', 'Zoom in'),
                    onPressed: () => _fly(_map.camera.center, math.min(_map.camera.zoom + 1, 19)),
                    icon: const Icon(Icons.add_rounded),
                  ),
                  const SizedBox(width: 28, child: Divider(height: 1)),
                  IconButton(
                    tooltip: s.tr('تصغير', 'Zoom out'),
                    onPressed: () => _fly(_map.camera.center, math.max(_map.camera.zoom - 1, 6)),
                    icon: const Icon(Icons.remove_rounded),
                  ),
                  const SizedBox(width: 28, child: Divider(height: 1)),
                  IconButton(
                    tooltip: s.tr('موقعي', 'My location'),
                    onPressed: _me == null ? _locate : () => _fly(_me!, math.max(_map.camera.zoom, 13)),
                    icon: _loc == _Loc.asking
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(_me == null ? Icons.location_searching_rounded : Icons.my_location_rounded, color: const Color(0xFF2563EB)),
                  ),
                  const SizedBox(width: 28, child: Divider(height: 1)),
                  IconButton(
                    tooltip: s.tr('كل المحلات', 'Show all shops'),
                    onPressed: () => _fitAll(shops),
                    icon: const Icon(Icons.zoom_out_map_rounded, color: MkColors.purple700),
                  ),
                ],
              ),
            ),
          ),
          // Near / far legend once location is on.
          if (_me != null)
            PositionedDirectional(
              start: MkSpace.md,
              bottom: shops.isEmpty ? MkSpace.lg : 196,
              child: MkEntrance(child: _Legend(s: s)),
            ),
          // Location prompt (or what to do when it's off).
          if (_me == null && _loc != _Loc.asking)
            Positioned(
              left: MkSpace.md,
              right: 76,
              bottom: shops.isEmpty ? MkSpace.lg : 196,
              child: MkEntrance(
                child: _LocationCard(
                  loc: _loc,
                  s: s,
                  onAllow: _locate,
                  onSettings: () => _loc == _Loc.serviceOff ? Geolocator.openLocationSettings() : Geolocator.openAppSettings(),
                ),
              ),
            ),
          // Swipeable shop strip, synced with the pins.
          if (shops.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: MkSpace.sm,
              height: 176,
              child: PageView.builder(
                controller: _strip,
                itemCount: shops.length,
                onPageChanged: (i) => _select(shops, shops[i], fromStrip: true),
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: _ShopStripCard(shop: shops[i], selected: shops[i].id == _selectedId, km: _km(shops[i])),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Map pin: a white teardrop holding the shop's logo, purple when idle and
/// gold when selected, with the shop name and points-back under the selected one.
class _ShopPin extends StatelessWidget {
  const _ShopPin({required this.selected, required this.logoUrl, required this.name, required this.badge, this.far = false});
  final bool selected;

  /// Farther than [kNearKm] from the customer: drawn grey and see-through.
  final bool far;
  final String? logoUrl;
  final String name;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final ring = selected ? MkColors.yellow500 : far ? const Color(0xFFA9A3B2) : MkColors.purple900;
    final pin = AnimatedScale(
      scale: selected ? 1.15 : 1,
      duration: MkMotion.base,
      curve: MkMotion.emphasized,
      alignment: Alignment.bottomCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44,
            height: 54,
            child: CustomPaint(
              painter: _TeardropPainter(ring),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(5, 5, 5, 15),
                child: ClipOval(child: MkNetImage(url: logoUrl, fallbackName: name, cacheWidth: 120)),
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: selected ? 1 : 0,
            duration: MkMotion.base,
            child: Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: MkColors.purple900, borderRadius: MkRadius.all(MkRadius.pill)),
              child: Text(
                badge,
                style: const TextStyle(color: MkColors.yellow500, fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
    return AnimatedOpacity(opacity: far && !selected ? 0.72 : 1, duration: MkMotion.base, child: pin);
  }
}

class _TeardropPainter extends CustomPainter {
  _TeardropPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final r = w / 2;
    final path = Path()
      ..moveTo(r, size.height)
      ..cubicTo(r - 6, size.height - 10, 0, r + 12, 0, r)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..cubicTo(w, r + 12, r + 6, size.height - 10, r, size.height)
      ..close();
    canvas.drawShadow(path, const Color(0x662C123F), 4, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawCircle(Offset(r, r), r - 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_TeardropPainter old) => old.color != color;
}

/// Compact shop card for the strip under the map.
class _ShopStripCard extends ConsumerWidget {
  const _ShopStripCard({required this.shop, required this.selected, this.km});
  final ShopCard shop;
  final bool selected;

  /// Distance from the customer, when location is on.
  final double? km;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    return AnimatedContainer(
      duration: MkMotion.base,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MkRadius.all(MkRadius.lg),
        border: Border.all(color: selected ? MkColors.yellow500 : Colors.transparent, width: 2),
        boxShadow: const [BoxShadow(color: Color(0x332C123F), blurRadius: 24, offset: Offset(0, 8))],
      ),
      clipBehavior: Clip.antiAlias,
      child: MkPressable(
        onTap: () => context.push('/shop/${shop.id}'),
        child: Row(
          children: [
            SizedBox(width: 110, child: MkNetImage(url: url(shop.coverUrl), fallbackIcon: MkCategory.icon(shop.category), cacheWidth: 330)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(shop.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded, size: 15, color: Color(0xFFF5B400)),
                        Text(' ${shop.rating == 0 ? '–' : shop.rating.toStringAsFixed(1)}', style: t.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                        Text(' (${shop.ratingCount})', style: t.labelSmall?.copyWith(color: MkColors.ink3)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [if (km != null) _fmtKm(km!), shop.place.isEmpty ? s.noAddress : shop.place].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelSmall?.copyWith(color: MkColors.ink3, fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: MkColors.yellow500, borderRadius: MkRadius.all(MkRadius.pill)),
                          child: Text(
                            s.tr('${shop.earnText}% نقاط', '${shop.earnText}% back'),
                            style: t.labelSmall?.copyWith(color: MkColors.purple900, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const Spacer(),
                        IconButton.filledTonal(
                          tooltip: s.tr('الاتجاهات', 'Directions'),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => launchUrl(
                            Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${shop.lat},${shop.lng}'),
                            mode: LaunchMode.externalApplication,
                          ),
                          icon: const Icon(Icons.directions_rounded, size: 20),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _fmtKm(double km) => km < 1 ? '${(km * 1000).round()} m' : '${km < 10 ? km.toStringAsFixed(1) : km.round()} km';

/// The customer's position: a blue dot with a soft pulse.
class _MeDot extends StatefulWidget {
  const _MeDot();

  @override
  State<_MeDot> createState() => _MeDotState();
}

class _MeDotState extends State<_MeDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'You are here',
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 18 + 46 * _c.value,
              height: 18 + 46 * _c.value,
              decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF2563EB).withValues(alpha: 0.35 * (1 - _c.value))),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2563EB),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [BoxShadow(color: Color(0x662563EB), blurRadius: 8)],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.s});
  final S s;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget row(Color c, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: t.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
          ],
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: MkRadius.all(MkRadius.md), boxShadow: MkShadow.soft),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          row(MkColors.purple900, s.tr('ضمن ${kNearKm.toInt()} كلم', 'Within ${kNearKm.toInt()} km')),
          const SizedBox(height: 4),
          row(const Color(0xFFA9A3B2), s.tr('أبعد', 'Farther')),
        ],
      ),
    );
  }
}

/// Asks the customer to share their location, or explains how to turn it on.
class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.loc, required this.s, required this.onAllow, required this.onSettings});
  final _Loc loc;
  final S s;
  final VoidCallback onAllow;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final off = loc == _Loc.deniedForever || loc == _Loc.serviceOff;
    final title = switch (loc) {
      _Loc.serviceOff => s.tr('الموقع مطفّى', 'Location is off'),
      _Loc.deniedForever || _Loc.denied => s.tr('ما في إذن للموقع', 'Location not allowed'),
      _ => s.tr('شوف شو قريب منك', "See what's near you"),
    };
    final body = switch (loc) {
      _Loc.serviceOff => s.tr('شغّل الموقع بالإعدادات لتشوف المسافات.', 'Turn it on in Settings to see distances.'),
      _Loc.deniedForever => s.tr('اسمح بالموقع لمكافأة من الإعدادات.', 'Allow location for Mukafaah in Settings.'),
      _Loc.denied => s.tr('منستعمله بس لنرتّب المحلات حسب المسافة.', 'We only use it to sort shops by distance.'),
      _ => s.tr('اسمح بالموقع لتلاقي أقرب المحلات.', 'Allow location to find the closest shops.'),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: MkRadius.all(MkRadius.lg),
        boxShadow: const [BoxShadow(color: Color(0x332C123F), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: const Color(0xFFDBEAFE), borderRadius: MkRadius.all(MkRadius.md)),
            child: Icon(off ? Icons.location_off_rounded : Icons.my_location_rounded, color: const Color(0xFF2563EB)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(body, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.labelSmall?.copyWith(color: MkColors.ink3)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: off ? onSettings : onAllow,
            style: FilledButton.styleFrom(
              backgroundColor: MkColors.yellow500,
              foregroundColor: MkColors.purple900,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: Text(off ? s.tr('الإعدادات', 'Settings') : s.tr('اسمح', 'Allow')),
          ),
        ],
      ),
    );
  }
}
