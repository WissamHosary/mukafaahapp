import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../alerts/alerts.dart';

/// Owner Mode navigation: a purple rail on wide screens (Windows/tablets),
/// a bottom bar on phones. The live alerts poller (chime + popup) lives here so it
/// keeps running across every owner tab.
class OwnerShell extends ConsumerWidget {
  const OwnerShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  static const _paths = ['/owner/collect', '/owner/redeem', '/owner/bookings', '/owner/transactions', '/owner/settings'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final found = _paths.indexWhere(location.startsWith);
    // Team, orders, dashboard and the loyalty % live under More.
    final index = found < 0 ? 4 : found;
    final pending = (ref.watch(bookingSummaryProvider).value?['requested'] as num?)?.toInt() ?? 0;
    Widget bell(IconData icon) => Badge(
          isLabelVisible: pending > 0,
          label: Text('$pending'),
          child: Icon(icon),
        );
    final items = [
      (const Icon(Icons.add_card_rounded), s.tr('جمع', 'Collect')),
      (const Icon(Icons.redeem_rounded), s.tr('صرف', 'Redeem')),
      (bell(Icons.event_note_rounded), s.tr('الحجوزات', 'Bookings')),
      (const Icon(Icons.receipt_long_rounded), s.tr('الفواتير', 'Bills')),
      (const Icon(Icons.menu_rounded), s.tr('المزيد', 'More')),
    ];
    void go(int i) => context.go(_paths[i]);
    final wide = MediaQuery.sizeOf(context).width >= 840;

    if (wide) {
      return AlertsPoller(owner: true, child: Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: go,
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: MkSpace.lg),
                child: MkLogo(height: 64, onDark: true),
              ),
              destinations: [
                for (final it in items) NavigationRailDestination(icon: it.$1, label: Text(it.$2)),
              ],
            ),
            Expanded(child: child),
          ],
        ),
      ));
    }
    return AlertsPoller(
      owner: true,
      child: Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: go,
          destinations: [for (final it in items) NavigationDestination(icon: it.$1, label: it.$2)],
        ),
      ),
    );
  }
}

/// Page frame shared by owner screens: title row, constrained width on desktop.
class OwnerPage extends StatelessWidget {
  const OwnerPage({required this.title, required this.child, this.actions = const [], this.onRefresh, this.fab, super.key});

  final String title;
  final Widget child;
  final List<Widget> actions;
  final Future<void> Function()? onRefresh;
  final Widget? fab;

  @override
  Widget build(BuildContext context) {
    final body = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: child),
    );
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: [...actions, const AlertsBell(owner: true), const SizedBox(width: MkSpace.xxs)]),
      body: onRefresh == null ? body : RefreshIndicator(onRefresh: onRefresh!, child: body),
      floatingActionButton: fab,
    );
  }
}
