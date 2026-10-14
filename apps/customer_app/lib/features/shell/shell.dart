import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../approvals/approvals.dart';

/// Bottom navigation with the QR as the raised centre action.
class AppShell extends ConsumerWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    void go(int i) => shell.goBranch(i, initialLocation: i == shell.currentIndex);
    // Spend approvals pop up on any tab.
    return RedeemApprovalsHost(
      child: Scaffold(
      body: shell,
      bottomNavigationBar: MkFloatingNav(
        selected: shell.currentIndex,
        onSelect: go,
        centerIndex: 2,
        centerIcon: Icons.qr_code_2_rounded,
        centerLabel: s.myQr,
        items: [
          (index: 0, icon: Icons.home_rounded, label: s.home),
          (index: 1, icon: Icons.location_on_rounded, label: s.map),
          (index: 3, icon: Icons.storefront_rounded, label: s.shops),
          (index: 4, icon: Icons.person_rounded, label: s.account),
        ],
      ),
    ),
    );
  }
}
