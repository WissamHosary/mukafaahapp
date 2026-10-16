import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../../data/api.dart';
import '../common/common.dart';

/// All shops with search, sort, program type tabs and category filter.
/// Also used for a single category (opened from home).
class ShopsScreen extends ConsumerStatefulWidget {
  const ShopsScreen({this.category, this.standalone = false, super.key});

  final String? category;

  /// True when pushed on top of the tabs (shows a back button).
  final bool standalone;

  @override
  ConsumerState<ShopsScreen> createState() => _ShopsScreenState();
}

class _ShopsScreenState extends ConsumerState<ShopsScreen> {
  late ShopQuery _q = ShopQuery(category: widget.category);
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearch(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _q = _q.copy(q: v.trim()));
    });
  }

  Future<void> _sortSheet() async {
    final s = ref.read(stringsProvider);
    final options = [
      ('popular', s.tr('الأكثر زيارة', 'Most popular'), Icons.local_fire_department_rounded),
      ('name', s.tr('من أ إلى ي', 'A to Z'), Icons.sort_by_alpha_rounded),
      ('name_desc', s.tr('من ي إلى أ', 'Z to A'), Icons.sort_by_alpha_rounded),
      ('nearest', s.tr('الأقرب لإلي', 'Nearest'), Icons.near_me_rounded),
      ('points', s.tr('وين عندي نقاط أكتر', 'Most points'), Icons.toll_rounded),
      ('rating', s.tr('الأعلى تقييم', 'Top rated'), Icons.star_rounded),
      ('friends', s.tr('أصدقاء مكافأة أولاً', 'Mukafaah Friends first'), Icons.verified_rounded),
    ];
    final picked = await showMkSheet<String>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.tr('ترتيب المحلات', 'Sort shops'), style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: MkSpace.sm),
          for (final o in options)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: o.$1 == 'friends'
                  ? const MkFriendsBadge(size: 26)
                  : Icon(o.$3, color: _q.sort == o.$1 ? MkColors.purple700 : MkColors.ink3),
              title: Text(o.$2, style: TextStyle(fontWeight: _q.sort == o.$1 ? FontWeight.w800 : FontWeight.w500)),
              trailing: _q.sort == o.$1 ? const Icon(Icons.check_circle_rounded, color: MkColors.purple700) : null,
              onTap: () => Navigator.of(ctx).pop(o.$1),
            ),
        ],
      ),
    );
    if (picked == null) return;
    if (picked == 'nearest') {
      // Nearest needs the location: ask once, here, when the member chose it.
      try {
        var p = await Geolocator.checkPermission();
        if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
      } on Object {
        // No location: the list falls back to popular.
      }
      ref.invalidate(myLocationProvider);
      final at = await ref.read(myLocationProvider.future);
      if (!mounted) return;
      if (at == null) MkToast.show(context, s.tr('ما قدرنا نعرف موقعك', "We couldn't get your location"));
      setState(() => _q = _q.copy(sort: picked, lat: at?.lat, lng: at?.lng));
      return;
    }
    setState(() => _q = _q.copy(sort: picked));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final data = ref.watch(shopsProvider(_q));
    final cats = ref.watch(categoriesProvider).value;
    final title = widget.category != null ? categoryName(s, cats, widget.category!) : s.shops;
    // Categories, names and icons come from Mukafaah Manager; built-in list until they load.
    final catList = cats ??
        [for (final k in S.categoryKeys) CategoryInfo(key: k, nameEn: s.category(k), nameAr: s.category(k))];
    final mediaUrl = ref.watch(mediaUrlProvider);
    final tabs = [
      (null, s.tr('الكل', 'All'), MkColors.purple700),
      ('IN_STORE', s.inStore, MkColors.inStore),
      ('SHARED', s.shared, MkColors.shared),
      ('NETWORK', s.tr('شبكة', 'Network'), MkColors.network),
    ];
    final info = switch (_q.type) {
      'IN_STORE' => s.tr('بتجمع وبتصرف نقاطك بنفس المحل.', 'Collect and spend your points at the same shop.'),
      'SHARED' => s.tr('نفس النقاط بكل محلات المجموعة: اشتري من محل واصرفها كلها بتاني.', 'Same points at every shop in the group: buy at one, spend them all at another.'),
      'NETWORK' => s.tr('نقاط وحدة بكل المجموعة، وكل محل بيحدد قديش بيقبل منها.', 'One balance across the group; each shop sets how much of it you can use.'),
      _ => null,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        automaticallyImplyLeading: widget.standalone,
        actions: [
          IconButton(
            tooltip: s.tr('كيف بتشتغل النقاط', 'How points work'),
            onPressed: () => showMkSheet<void>(
              context,
              builder: (ctx) => Text(
                s.tr(
                  'كيف بتشتغل النقاط:\n\n• داخل المحل: بتجمع وبتصرف بنفس المحل.\n\n• مشترك: نفس النقاط بكل محلات المجموعة. بتشتري من محل وبتصرفها كلها بمحل تاني.\n\n• شبكة: نقاط وحدة بكل المجموعة، بس كل محل بيحدد قديش بيقبل منها بكل زيارة (مثلاً نصّ نقاطك).\n\n• علامة مكافأة جنب اسم المحل: المحل من أصدقاء مكافأة وبيقبل نقاط مكافأة.',
                  'How points work:\n\n• In-Store: collect and spend at the same shop.\n\n• Shared: the same points at every shop in the group. Buy at one shop, spend all of them at another.\n\n• Network: one balance across the group, but each shop decides how much of it you can use per visit (for example half your points).\n\n• The Mukafaah mark next to a name: the shop is a Mukafaah Friend and accepts Mukafaah Points.',
                ),
                style: Theme.of(ctx).textTheme.bodyLarge,
              ),
            ),
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(shopsProvider(_q));
          await ref.read(shopsProvider(_q).future);
        },
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.xs, MkSpace.lg, 0),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(child: MkSearchField(hint: s.search, controller: _search, onChanged: _onSearch)),
                    const SizedBox(width: MkSpace.xs),
                    _SortButton(label: s.tr('ترتيب', 'Sort'), active: _q.sort != 'popular', onTap: _sortSheet),
                  ],
                ),
              ),
            ),
            // All / In-Store / Shared / Network.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(MkSpace.md, MkSpace.sm, MkSpace.md, 0),
                child: _TypeTabs(
                  tabs: tabs,
                  selected: _q.type,
                  onSelected: (v) => setState(() => _q = v == null ? _q.copy(clearType: true) : _q.copy(type: v)),
                ),
              ),
            ),
            if (info != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.xs, MkSpace.lg, 0),
                  child: Text(info, style: t.bodySmall?.copyWith(color: MkColors.ink2)),
                ),
              ),
            // Categories.
            if (widget.category == null)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 112,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.sm, MkSpace.lg, 0),
                    scrollDirection: Axis.horizontal,
                    itemCount: catList.length,
                    separatorBuilder: (context, i) => const SizedBox(width: MkSpace.xs),
                    itemBuilder: (context, i) {
                      final c = catList[i];
                      final k = c.key;
                      return MkCategoryTile(
                        categoryKey: k,
                        label: c.name(s.isAr),
                        emoji: c.emoji,
                        iconUrl: mediaUrl(c.iconUrl),
                        selected: _q.category == k,
                        onTap: () => setState(
                          () => _q = _q.category == k ? _q.copy(clearCategory: true) : _q.copy(category: k),
                        ),
                      );
                    },
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.sm, MkSpace.lg, MkSpace.sm),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Text(s.shopsAvailable(data.value?.total ?? 0), style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                    const Spacer(),
                    if (_q.category != null || _q.type != null || _q.sort != 'popular')
                      TextButton(
                        onPressed: () => setState(() => _q = ShopQuery(category: widget.category, q: _q.q)),
                        child: Text(s.tr('مسح', 'Clear')),
                      ),
                  ],
                ),
              ),
            ),
            ...data.when(
              data: (d) => d.shops.isEmpty
                  ? [
                      SliverToBoxAdapter(
                        child: MkEmptyState(
                          icon: Icons.storefront_rounded,
                          title: s.tr('قريباً', 'Coming soon'),
                          message: s.tr('ما في محلات هون بعد. جرّب فلتر تاني.', 'No shops here yet. Try another filter.'),
                        ),
                      ),
                    ]
                  : [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(MkSpace.lg, 0, MkSpace.lg, MkSpace.xxl),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 220,
                            mainAxisExtent: 262,
                            crossAxisSpacing: MkSpace.sm,
                            mainAxisSpacing: MkSpace.sm,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, i) => MkStagger(index: i % 8, child: ShopCardTile(shop: d.shops[i])),
                            childCount: d.shops.length,
                          ),
                        ),
                      ),
                    ],
              loading: () => [
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: MkSpace.lg),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      mainAxisExtent: 262,
                      crossAxisSpacing: MkSpace.sm,
                      mainAxisSpacing: MkSpace.sm,
                    ),
                    delegate: SliverChildBuilderDelegate((context, i) => DecoratedBox(decoration: BoxDecoration(color: MkColors.purple50, borderRadius: MkRadius.all(MkRadius.lg))), childCount: 4),
                  ),
                ),
              ],
              error: (e, _) => [
                SliverToBoxAdapter(
                  child: MkErrorState(title: errorText(s, e), retryLabel: s.retry, onRetry: () => ref.invalidate(shopsProvider(_q))),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MkPressable(
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? MkColors.purple900 : Colors.white,
          borderRadius: MkRadius.all(MkRadius.md),
          border: Border.all(color: active ? MkColors.purple900 : MkColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded, size: 18, color: active ? MkColors.yellow500 : MkColors.ink),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: active ? Colors.white : MkColors.ink)),
          ],
        ),
      ),
    );
  }
}

/// All / In-Store / Shared / Network with a sliding underline.
class _TypeTabs extends StatelessWidget {
  const _TypeTabs({required this.tabs, required this.selected, required this.onSelected});
  final List<(String?, String, Color)> tabs;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final idx = math.max(0, tabs.indexWhere((x) => x.$1 == selected));
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth / tabs.length;
        final rtl = Directionality.of(context) == TextDirection.rtl;
        return SizedBox(
          height: 44,
          child: Stack(
            children: [
              Positioned(left: 0, right: 0, bottom: 0, child: Container(height: 1, color: MkColors.line)),
              AnimatedPositioned(
                duration: MkMotion.base,
                curve: MkMotion.emphasized,
                bottom: 0,
                left: (rtl ? tabs.length - 1 - idx : idx) * w + w * 0.2,
                width: w * 0.6,
                height: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: tabs[idx].$3, borderRadius: MkRadius.all(2)),
                ),
              ),
              Row(
                children: [
                  for (final x in tabs)
                    Expanded(
                      child: Semantics(
                        selected: x.$1 == selected,
                        button: true,
                        child: InkWell(
                          onTap: () => onSelected(x.$1),
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: MkMotion.base,
                              style: (t.labelLarge ?? const TextStyle()).copyWith(
                                color: x.$1 == selected ? x.$3 : MkColors.ink3,
                                fontWeight: x.$1 == selected ? FontWeight.w800 : FontWeight.w600,
                              ),
                              child: Text(x.$2, maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
