import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../auth/auth_screens.dart';
import '../common/common.dart';
import '../lock/biometric.dart';

/// Profile & Settings: tier, name, referral code, invites, language, bookings,
/// join as merchant, support and sign-out.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  Future<void> _logout(WidgetRef ref, {bool all = false}) async {
    await ref.read(authProvider.notifier).logout(all: all);
    ref
      ..invalidate(walletProvider)
      ..invalidate(transactionsProvider)
      ..invalidate(prePointsProvider)
      ..invalidate(homeProvider)
      ..invalidate(tierProvider)
      ..invalidate(referralProvider);
    ref.read(cartProvider.notifier).clear();
  }

  Future<void> _editName(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final ctl = TextEditingController(text: ref.read(authProvider).user?.name ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.nameTitle),
        content: TextField(controller: ctl, autofocus: true, maxLength: 60, decoration: InputDecoration(hintText: s.nameHint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: Text(s.save)),
        ],
      ),
    );
    ctl.dispose();
    if (name == null || name.isEmpty) return;
    try {
      final u = await ref.read(apiProvider).updateProfile(name: name);
      ref.read(authProvider.notifier).updateUser(u);
      ref.invalidate(homeProvider);
    } on ApiException catch (e) {
      if (context.mounted) MkToast.show(context, s.errorV2(e.code), kind: MkToastKind.error);
    }
  }

  Future<void> _enterCode(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final ctl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.tr('عندك رمز دعوة؟', 'Have an invite code?')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: 'AB12CD3'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: Text(s.confirm)),
        ],
      ),
    );
    ctl.dispose();
    if (code == null || code.isEmpty) return;
    try {
      await ref.read(apiProvider).useReferral(code);
      ref.invalidate(referralProvider);
      if (context.mounted) MkToast.show(context, s.saved, kind: MkToastKind.success);
    } on ApiException catch (e) {
      if (context.mounted) MkToast.show(context, s.errorV2(e.code), kind: MkToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final user = ref.watch(authProvider).user;
    final lang = ref.watch(localeProvider);
    // Support contacts are set in Mukafaah Manager; WhatsApp is digits only for wa.me links.
    final home = ref.watch(homeProvider).value;
    final supportWhatsapp = (home?.supportWhatsapp ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    final supportInstagram = (home?.supportInstagram ?? '').trim().isEmpty ? 'mukafaah.app' : home!.supportInstagram!.trim();
    final tier = ref.watch(tierProvider).value;
    final referral = ref.watch(referralProvider).value;

    Widget tile(IconData icon, String title, VoidCallback onTap, {String? sub, Color? color}) => ListTile(
          leading: MkIconTile(icon: icon, size: 38, color: color ?? MkColors.purple900),
          title: Text(title, style: TextStyle(color: color)),
          subtitle: sub == null ? null : Text(sub),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        );

    return Scaffold(
      appBar: AppBar(title: Text(s.profileSettings), centerTitle: true, automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.all(MkSpace.lg),
        children: [
          MkCard(
            onTap: () => context.push('/tier'),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.workspace_premium_rounded, color: MkTierChip.colors(tier?.tier ?? 'SILVER').$1, size: 34),
                    const SizedBox(width: MkSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.tr('المستوى الحالي', 'Current Tier'), style: t.labelMedium?.copyWith(color: MkColors.ink3)),
                          Text(tierName(s, tier?.current?.name, tier?.tier ?? 'SILVER'), style: t.titleLarge),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(s.tr('مجموع مشترياتك', 'Total spent'), style: t.labelMedium?.copyWith(color: MkColors.ink3)),
                        Text(money(tier?.lifetimeSpendMinor ?? 0), style: t.titleLarge),
                      ],
                    ),
                  ],
                ),
                if (tier?.nextCode != null) ...[
                  const SizedBox(height: MkSpace.sm),
                  ClipRRect(
                    borderRadius: MkRadius.all(MkRadius.pill),
                    child: LinearProgressIndicator(
                      value: tier!.progress,
                      minHeight: 6,
                      backgroundColor: MkColors.purple50,
                      color: MkColors.yellow600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: MkSpace.md),
          MkCard(
            child: Row(
              children: [
                MkMonogram(name: user?.name ?? 'M', size: 52),
                const SizedBox(width: MkSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.name ?? '', style: t.titleLarge),
                      Text(
                        user?.phoneLast4 == null ? (user?.email ?? '') : '+961 ${maskPhone(user?.phoneLast4)}',
                        textDirection: TextDirection.ltr,
                        style: t.bodySmall?.copyWith(color: MkColors.ink3),
                      ),
                      if (referral != null)
                        GestureDetector(
                          onTap: () async {
                            await Clipboard.setData(ClipboardData(text: referral.code));
                            if (context.mounted) MkToast.show(context, s.copied, kind: MkToastKind.success);
                          },
                          child: Text('${s.referralNumber}: ${referral.code}', style: t.labelMedium?.copyWith(color: MkColors.purple700)),
                        ),
                    ],
                  ),
                ),
                IconButton(onPressed: () => _editName(context, ref), icon: const Icon(Icons.edit_rounded, color: MkColors.purple700)),
              ],
            ),
          ),
          MkSectionHeader(title: s.tr('دعوة الأصحاب', 'Invite friends')),
          MkCard(
            color: MkColors.yellow50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s.tr('شارك رمزك مع أصحابك. بيدخلوه أول ما يسجلوا.', 'Share your code with friends. They enter it when they join.'),
                  style: t.bodyMedium,
                ),
                const SizedBox(height: MkSpace.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        referral?.code ?? '—',
                        style: t.headlineSmall?.copyWith(letterSpacing: 2, color: MkColors.purple900),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: referral == null
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(
                                  text: s.tr(
                                    'انضم لمكافأة واستعمل رمز الدعوة تبعي: ${referral.code}',
                                    'Join Mukafaah and use my invite code: ${referral.code}',
                                  ),
                                ),
                              );
                              if (context.mounted) MkToast.show(context, s.copied, kind: MkToastKind.success);
                            },
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: Text(s.tr('نسخ', 'Copy')),
                    ),
                  ],
                ),
                if (referral != null)
                  Text(
                    s.tr('دعيت ${referral.invitedCount} شخص', 'You invited ${referral.invitedCount}'),
                    style: t.bodySmall?.copyWith(color: MkColors.ink2),
                  ),
                if (referral?.canEnterCode ?? false)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: () => _enterCode(context, ref),
                      child: Text(s.tr('عندي رمز دعوة', 'I have an invite code')),
                    ),
                  ),
                if (referral?.referredBy != null)
                  Text(s.tr('دعاك: ${referral!.referredBy}', 'Invited by ${referral!.referredBy}'), style: t.bodySmall),
              ],
            ),
          ),
          MkSectionHeader(title: s.tr('إعدادات الحساب', 'Account Settings')),
          MkCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                tile(Icons.event_note_rounded, s.myBookings, () => context.push('/bookings')),
                tile(Icons.notifications_rounded, s.notifications, () => context.push('/notifications')),
                tile(Icons.history_rounded, s.history, () => context.push('/points')),
                tile(Icons.swap_horiz_rounded, s.transferPoints, () => context.push('/transfer')),
                ListTile(
                  leading: const MkIconTile(icon: Icons.language_rounded, size: 38),
                  title: Text(s.language),
                  trailing: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: 'ar', label: Text(s.arabic)),
                      ButtonSegment(value: 'en', label: Text(s.english)),
                    ],
                    selected: {lang},
                    onSelectionChanged: (v) async {
                      final l = v.first;
                      await ref.read(localeProvider.notifier).set(l);
                      await ref.read(apiProvider).updateProfile(locale: l).then((_) {}, onError: (_) {});
                      ref.invalidate(tierProvider);
                    },
                  ),
                ),
              ],
            ),
          ),
          MkSectionHeader(title: s.tr('الدعم', 'Support')),
          MkCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                tile(
                  Icons.storefront_rounded,
                  s.tr('انضم كتاجر', 'Join As Merchant'),
                  () => showMkSheet<void>(
                    context,
                    builder: (ctx) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(s.tr('عندك محل؟', 'Own a shop?'), style: Theme.of(ctx).textTheme.titleLarge),
                        const SizedBox(height: MkSpace.xs),
                        Text(
                          s.tr(
                            'نزّل تطبيق مكافأة للأعمال، سجّل بنفس رقمك واعمل محلك بدقيقة: نقاط، عروض، حجوزات وطلبات واتساب.',
                            'Get the Mukafaah Business app, sign in with this same number and set up your shop in a minute: points, offers, bookings and WhatsApp orders.',
                          ),
                        ),
                        const SizedBox(height: MkSpace.md),
                        MkButton(
                          label: supportWhatsapp.isEmpty ? s.tr('راسلنا عالإنستغرام', 'Message us on Instagram') : s.tr('احكينا عالواتساب', 'Talk to us on WhatsApp'),
                          icon: Icons.chat_rounded,
                          kind: MkButtonKind.accent,
                          onPressed: () => launchUrl(
                            Uri.parse(
                              supportWhatsapp.isEmpty
                                  ? 'https://www.instagram.com/$supportInstagram/'
                                  : 'https://wa.me/$supportWhatsapp?text=${Uri.encodeComponent('Mukafaah merchant')}',
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (supportWhatsapp.isNotEmpty)
                  tile(
                    Icons.support_agent_rounded,
                    s.tr('مساعدة', 'Help'),
                    () => launchUrl(Uri.parse('https://wa.me/$supportWhatsapp'), mode: LaunchMode.externalApplication),
                  ),
                tile(Icons.photo_camera_rounded, 'Instagram', () => launchUrl(Uri.parse('https://www.instagram.com/$supportInstagram/'), mode: LaunchMode.externalApplication)),
              ],
            ),
          ),
          MkSectionHeader(title: s.security),
          MkCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                const _QuickUnlockTile(),
                if (!(user?.isGoogle ?? false))
                  tile(
                    Icons.password_rounded,
                    (user?.hasPassword ?? false) ? s.tr('غيّر كلمة السر', 'Change password') : s.tr('اختار كلمة سر', 'Create a password'),
                    () => context.push('/signup/password?mode=${(user?.hasPassword ?? false) ? 'change' : 'new'}&then=/profile'),
                    sub: s.tr('لترجع تفوت برقمك وكلمة السر', 'To sign back in with your number and password'),
                  ),
                tile(Icons.logout_rounded, s.logout, () => _logout(ref)),
                tile(Icons.devices_rounded, s.logoutAll, () => _logout(ref, all: true), color: MkColors.danger),
              ],
            ),
          ),
          const SizedBox(height: MkSpace.xxl),
          Center(child: Text('${s.appName} · v0.8 · ${AppConfig.env}', style: t.bodySmall?.copyWith(color: MkColors.ink3))),
        ],
      ),
    );
  }
}

/// "Unlock with fingerprint / Face ID" switch. Hidden on phones without either.
class _QuickUnlockTile extends ConsumerWidget {
  const _QuickUnlockTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final kind = ref.watch(bioKindProvider).value ?? BioKind.none;
    if (kind == BioKind.none) return const SizedBox.shrink();
    final on = ref.watch(bioEnabledProvider);
    final face = kind == BioKind.face;
    return SwitchListTile(
      secondary: Icon(face ? Icons.face : Icons.fingerprint, color: MkColors.purple700),
      title: Text(face ? s.tr('افتح بـ Face ID', 'Unlock with Face ID') : s.tr('افتح بالبصمة', 'Unlock with fingerprint')),
      subtitle: Text(
        on ? s.tr('بينطلب كل ما تفتح التطبيق.', 'Asked every time you open the app.') : s.tr('مطفي', 'Off'),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: MkColors.ink3),
      ),
      value: on,
      activeTrackColor: MkColors.success,
      onChanged: (v) => toggleQuickUnlock(context, ref, v),
    );
  }
}
