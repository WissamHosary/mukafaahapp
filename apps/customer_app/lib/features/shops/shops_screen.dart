import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      ('popular', s.tr('الأكثر زيارة', 'Most popular')),
      ('rating', s.tr('الأعلى تقييم', 'Top rated')),
      ('points', s.tr('وين عندي نقاط', 'Where I have points')),
      ('newest', s.tr('الأحدث', 'Newest')),
      ('name', s.tr('بالاسم', 'Name')),
    ];
    final picked = await showMkSheet<String>(
      context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.tr('ترتيب', 'Sort'), style: Theme.of(ctx).textTheme.titleLarge),
          const SizedBox(height: MkSpace.sm),
          for (final o in options)
            ListTile(
              title: Text(o.$2),
              trailing: _q.sort == o.$1 ? const Icon(Icons.check_rounded, color: MkColors.purple700) : null,
              onTap: () => Navigator.of(ctx).pop(o.$1),
            ),
        ],
      ),
    );
    if (picked != null) setState(() => _q = _q.copy(sort: picked));
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

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        automaticallyImplyLeading: widget.standalone,
        actions: [
          IconButton(
            tooltip: s.map,
            onPressed: () => showMkSheet<void>(
              context,
              builder: (ctx) => Text(
                s.tr(
                  'العضوية:\n• داخل المتجر: بتربح وبتصرف بنفس المحل.\n• مشترك: بتربح بمحل وبتصرف بمحلات تانية مشتركة.\n• شبكة: نقاط وحدة لكل فروع المجموعة.',
                  'Programs:\n• In-Store: earn and redeem at the same shop.\n• Shared: earn at one shop, redeem at partner shops.\n• Network: one balance across a group of branches.',
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
                    OutlinedButton.icon(
                      onPressed: _sortSheet,
                      icon: const Icon(Icons.sort_rounded, size: 18),
                      label: Text(s.tr('ترتيب', 'Sort')),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: MkSpace.md),
              sliver: SliverToBoxAdapter(
                child: MkTextTabs<String?>(
                  items: [
                    (null, s.all),
                    ('IN_STORE', s.inStore),
                    ('SHARED', s.shared),
                    ('NETWORK', s.tr('شبكة', 'Network')),
                  ],
                  selected: _q.type,
                  onSelected: (v) => setState(() => _q = v == null ? _q.copy(clearType: true) : _q.copy(type: v)),
                ),
              ),
            ),
            if (widget.category == null)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 108,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.xs, MkSpace.lg, 0),
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
              padding: const EdgeInsets.fromLTRB(MkSpace.lg, MkSpace.md, MkSpace.lg, MkSpace.sm),
              sliver: SliverToBoxAdapter(
                child: Text(s.shopsAvailable(data.value?.total ?? 0), style: t.titleMedium),
              ),
            ),
            ...data.when(
              data: (d) => d.shops.isEmpty
                  ? [
                      SliverToBoxAdapter(
                        child: MkEmptyState(
                          icon: Icons.search_off_rounded,
                          title: s.tr('ما في محلات هون', 'No shops here yet'),
                          message: s.tr('جرّب فلتر تاني.', 'Try another filter.'),
                        ),
                      ),
                    ]
                  : [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(MkSpace.lg, 0, MkSpace.lg, MkSpace.xxl),
                        sliver: SliverGrid(
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 220,
                            mainAxisExtent: 244,
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
                const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(MkSpace.xxl), child: Center(child: CircularProgressIndicator())),
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
