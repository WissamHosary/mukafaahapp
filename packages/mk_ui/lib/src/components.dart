import 'package:material_ui/material_ui.dart';

import 'brand.dart';
import 'motion.dart';
import 'tokens.dart';

enum MkButtonKind { primary, accent, secondary, ghost, danger }

/// The one button used across both apps.
class MkButton extends StatelessWidget {
  const MkButton({
    required this.label,
    this.onPressed,
    this.kind = MkButtonKind.primary,
    this.icon,
    this.loading = false,
    this.expand = true,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final MkButtonKind kind;
  final IconData? icon;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (kind) {
      MkButtonKind.primary => (MkColors.purple900, Colors.white, null),
      MkButtonKind.accent => (MkColors.yellow500, MkColors.purple900, null),
      MkButtonKind.secondary => (MkColors.surface, MkColors.purple900, MkColors.line),
      MkButtonKind.ghost => (Colors.transparent, MkColors.purple700, null),
      MkButtonKind.danger => (MkColors.dangerBg, MkColors.danger, null),
    };
    final enabled = onPressed != null && !loading;
    final child = AnimatedSwitcher(
      duration: MkMotion.fast,
      child: loading
          ? SizedBox(
              key: const ValueKey('l'),
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
            )
          : Row(
              key: const ValueKey('c'),
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: MkIconSize.md, color: fg), const SizedBox(width: MkSpace.xs)],
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg),
                  ),
                ),
              ],
            ),
    );
    final button = MkPressable(
      onTap: enabled ? onPressed : null,
      child: AnimatedOpacity(
        duration: MkMotion.fast,
        opacity: enabled || loading ? 1 : 0.45,
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: MkSpace.xl),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: MkRadius.all(MkRadius.md),
            border: border == null ? null : Border.all(color: border, width: 1.4),
            boxShadow: kind == MkButtonKind.accent && enabled ? MkShadow.glow : null,
          ),
          child: child,
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

/// Plain surface card.
class MkCard extends StatelessWidget {
  const MkCard({required this.child, this.padding = const EdgeInsets.all(MkSpace.md), this.onTap, this.color, super.key});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? MkColors.surface,
        borderRadius: MkRadius.all(MkRadius.lg),
        border: Border.all(color: MkColors.line),
        boxShadow: MkShadow.soft,
      ),
      child: child,
    );
    return onTap == null ? box : MkPressable(onTap: onTap, child: box);
  }
}

/// Program type pill: In-Store / Shared / Network.
class MkProgramBadge extends StatelessWidget {
  const MkProgramBadge({required this.type, required this.label, this.onDark = false, super.key});

  final String type;
  final String label;
  final bool onDark;

  static Color colorFor(String type) => switch (type) {
        'SHARED' => MkColors.shared,
        'NETWORK' => MkColors.network,
        _ => MkColors.inStore,
      };

  static IconData iconFor(String type) => switch (type) {
        'SHARED' => Icons.sync_alt_rounded,
        'NETWORK' => Icons.hub_rounded,
        _ => Icons.storefront_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final c = onDark ? MkColors.yellow500 : colorFor(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: onDark ? 0.16 : 0.1),
        borderRadius: MkRadius.all(MkRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconFor(type), size: 14, color: c),
          const SizedBox(width: 4),
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c)),
        ],
      ),
    );
  }
}

/// The hero wallet card (purple, swirls, gold coin, animated balance).
class MkWalletCard extends StatelessWidget {
  const MkWalletCard({
    required this.title,
    required this.points,
    required this.pointsLabel,
    this.subtitle,
    this.trailing,
    this.format,
    super.key,
  });

  final String title;
  final int points;
  final String pointsLabel;
  final String? subtitle;
  final Widget? trailing;
  final String Function(int)? format;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ClipRRect(
      borderRadius: MkRadius.all(MkRadius.xl),
      child: Container(
        decoration: const BoxDecoration(boxShadow: MkShadow.lifted),
        child: MkSwirlBackground(
          child: Padding(
            padding: const EdgeInsets.all(MkSpace.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title, style: t.titleSmall?.copyWith(color: const Color(0xFFD8CCE6))),
                    ),
                    if (trailing != null) trailing!,
                  ],
                ),
                const SizedBox(height: MkSpace.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const MkFloat(child: MkCoin(size: 44)),
                    const SizedBox(width: MkSpace.sm),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: AnimatedPoints(
                          value: points,
                          format: format,
                          style: t.displaySmall?.copyWith(color: Colors.white, fontSize: 40),
                        ),
                      ),
                    ),
                    const SizedBox(width: MkSpace.xs),
                    Text(pointsLabel, style: t.titleMedium?.copyWith(color: MkColors.yellow500)),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: MkSpace.sm),
                  Text(subtitle!, style: t.bodySmall?.copyWith(color: const Color(0xFFD8CCE6))),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// KPI tile for dashboards.
class MkStatTile extends StatelessWidget {
  const MkStatTile({required this.label, required this.value, this.icon, this.highlight = false, super.key});

  final String label;
  final String value;
  final IconData? icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(MkSpace.md),
      decoration: BoxDecoration(
        color: highlight ? MkColors.purple900 : MkColors.surface,
        borderRadius: MkRadius.all(MkRadius.lg),
        border: Border.all(color: highlight ? MkColors.purple900 : MkColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: highlight ? MkColors.yellow500 : MkColors.purple500),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelMedium?.copyWith(color: highlight ? const Color(0xFFD8CCE6) : MkColors.ink3),
                ),
              ),
            ],
          ),
          const SizedBox(height: MkSpace.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              textDirection: TextDirection.ltr,
              style: t.headlineSmall?.copyWith(color: highlight ? Colors.white : MkColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class MkSectionHeader extends StatelessWidget {
  const MkSectionHeader({required this.title, this.action, this.onAction, super.key});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: MkSpace.xl, bottom: MkSpace.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.2),
            ),
          ),
          if (action != null)
            MkPressable(
              onTap: onAction ?? () {},
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(action!, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: MkColors.purple700)),
                    Icon(
                      Directionality.of(context) == TextDirection.rtl ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                      size: 18,
                      color: MkColors.purple700,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Rounded square icon used in lists and quick actions.
class MkIconTile extends StatelessWidget {
  const MkIconTile({required this.icon, this.color = MkColors.purple900, this.bg = MkColors.purple100, this.size = 44, super.key});

  final IconData icon;
  final Color color;
  final Color bg;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, borderRadius: MkRadius.all(MkRadius.md)),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// Letter avatar for businesses without a logo yet.
class MkMonogram extends StatelessWidget {
  const MkMonogram({required this.name, this.size = 48, super.key});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [MkColors.purple700, MkColors.purple900],
        ),
        borderRadius: MkRadius.all(MkRadius.md),
      ),
      child: Text(
        letter,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(color: MkColors.yellow500),
      ),
    );
  }
}
