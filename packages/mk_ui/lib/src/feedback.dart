import 'package:material_ui/material_ui.dart';
import 'package:skeletonizer/skeletonizer.dart';

import 'brand.dart';
import 'components.dart';
import 'motion.dart';
import 'tokens.dart';

enum MkToastKind { info, success, error }

abstract final class MkToast {
  static void show(BuildContext context, String message, {MkToastKind kind = MkToastKind.info}) {
    final (icon, color) = switch (kind) {
      MkToastKind.success => (Icons.check_circle_rounded, MkColors.yellow500),
      MkToastKind.error => (Icons.error_rounded, const Color(0xFFFF8A95)),
      MkToastKind.info => (Icons.info_rounded, Colors.white),
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: MkSpace.sm),
              Expanded(child: Text(message)),
            ],
          ),
          duration: const Duration(seconds: 3),
        ),
      );
  }
}

/// Branded empty state with a floating coin.
class MkEmptyState extends StatelessWidget {
  const MkEmptyState({required this.title, this.message, this.action, this.onAction, this.icon, super.key});

  final String title;
  final String? message;
  final String? action;
  final VoidCallback? onAction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MkSpace.xxl),
        child: MkEntrance(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MkFloat(
                child: icon == null
                    ? const MkCoin(size: 72)
                    : MkIconTile(icon: icon!, size: 72, bg: MkColors.yellow50, color: MkColors.purple900),
              ),
              const SizedBox(height: MkSpace.lg),
              Text(title, textAlign: TextAlign.center, style: t.titleLarge),
              if (message != null) ...[
                const SizedBox(height: MkSpace.xs),
                Text(message!, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: MkColors.ink2)),
              ],
              if (action != null) ...[
                const SizedBox(height: MkSpace.xl),
                MkButton(label: action!, onPressed: onAction, expand: false, kind: MkButtonKind.accent),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class MkErrorState extends StatelessWidget {
  const MkErrorState({required this.title, required this.retryLabel, this.onRetry, this.message, super.key});

  final String title;
  final String? message;
  final String retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MkEmptyState(
      icon: Icons.wifi_off_rounded,
      title: title,
      message: message,
      action: retryLabel,
      onAction: onRetry,
    );
  }
}

/// Wrap real widgets to show them as a shimmering skeleton while loading.
class MkSkeleton extends StatelessWidget {
  const MkSkeleton({required this.loading, required this.child, super.key});

  final bool loading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      enabled: loading,
      effect: const ShimmerEffect(baseColor: MkColors.purple50, highlightColor: Colors.white),
      child: child,
    );
  }
}

/// Branded modal bottom sheet.
Future<T?> showMkSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(MkSpace.xl, 0, MkSpace.xl, MkSpace.xl),
        child: builder(ctx),
      ),
    ),
  );
}

/// Full-screen success moment.
class MkSuccessView extends StatelessWidget {
  const MkSuccessView({required this.title, this.subtitle, this.action, this.onAction, this.extra, super.key});

  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const MkSuccessMark(size: 110),
        const SizedBox(height: MkSpace.lg),
        MkEntrance(index: 3, child: Text(title, textAlign: TextAlign.center, style: t.headlineSmall)),
        if (subtitle != null)
          MkEntrance(
            index: 4,
            child: Padding(
              padding: const EdgeInsets.only(top: MkSpace.xs),
              child: Text(subtitle!, textAlign: TextAlign.center, style: t.bodyLarge?.copyWith(color: MkColors.ink2)),
            ),
          ),
        if (extra != null) ...[const SizedBox(height: MkSpace.lg), extra!],
        if (action != null) ...[
          const SizedBox(height: MkSpace.xl),
          MkButton(label: action!, onPressed: onAction),
        ],
      ],
    );
  }
}
