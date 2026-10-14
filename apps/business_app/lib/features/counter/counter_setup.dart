import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../owner/owner_auth.dart';

class PairScreen extends ConsumerStatefulWidget {
  const PairScreen({super.key});

  @override
  ConsumerState<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends ConsumerState<PairScreen> {
  final _code = TextEditingController();
  final _label = TextEditingController(text: 'Counter 1');
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final s = ref.read(stringsProvider);
    if (_code.text.trim().length != 8) return;
    setState(() => _busy = true);
    try {
      final d = await ref.read(apiProvider).pair(_code.text.trim().toUpperCase(), _label.text.trim());
      await ref.read(sessionProvider.notifier).savePairedDevice(d);
    } on ApiException catch (e) {
      if (mounted) MkToast.show(context, s.error(e.code), kind: MkToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    return AuthFrame(
      onBack: () => ref.read(sessionProvider.notifier).switchMode(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MkEntrance(child: Center(child: MkIconTile(icon: Icons.point_of_sale_rounded, size: 72, bg: MkColors.yellow50))),
          const SizedBox(height: MkSpace.lg),
          Text(s.pairTitle, style: t.headlineMedium, textAlign: TextAlign.center),
          const SizedBox(height: MkSpace.xs),
          Text(s.pairBody, style: t.bodyLarge?.copyWith(color: MkColors.ink2), textAlign: TextAlign.center),
          const SizedBox(height: MkSpace.xl),
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _code,
              autofocus: true,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(8),
              ],
              style: t.headlineSmall?.copyWith(letterSpacing: 6),
              decoration: InputDecoration(hintText: 'ABCD2345', labelText: s.pairingCode),
              onSubmitted: (_) => _pair(),
            ),
          ),
          const SizedBox(height: MkSpace.sm),
          TextField(controller: _label, decoration: InputDecoration(labelText: s.deviceLabel)),
          const SizedBox(height: MkSpace.xl),
          MkButton(label: s.continueLabel, loading: _busy, onPressed: _pair),
        ],
      ),
    );
  }
}

class StaffLoginScreen extends ConsumerStatefulWidget {
  const StaffLoginScreen({super.key});

  @override
  ConsumerState<StaffLoginScreen> createState() => _StaffLoginScreenState();
}

class _StaffLoginScreenState extends ConsumerState<StaffLoginScreen> {
  List<({String id, String name})>? _staff;
  ({String id, String name})? _selected;
  String _pin = '';
  bool _error = false;
  bool _busy = false;
  String? _loadError;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final dev = ref.read(sessionProvider).device!;
    try {
      final list = await ref.read(apiProvider).counterStaff(dev);
      setState(() {
        _staff = list;
        _loadError = null;
        if (list.length == 1) _selected = list.first;
      });
    } on ApiException catch (e) {
      if (e.code == 'DEVICE_NOT_PAIRED') {
        await ref.read(sessionProvider.notifier).unpair();
        return;
      }
      setState(() => _loadError = e.code);
    }
  }

  Future<void> _key(String k) async {
    if (_busy || _pin.length >= 6) return;
    setState(() {
      _pin += k;
      _error = false;
    });
  }

  Future<void> _submit() async {
    final s = ref.read(stringsProvider);
    final sel = _selected;
    if (sel == null || _pin.length < 4) return;
    setState(() => _busy = true);
    try {
      final session = await ref.read(apiProvider).staffLogin(ref.read(sessionProvider).device!, sel.id, _pin);
      ref.read(sessionProvider.notifier).staffSignedIn(session);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _pin = '';
      });
      MkToast.show(context, s.error(e.code), kind: MkToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final dev = ref.watch(sessionProvider).device;
    return KeyboardListener(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (e) {
        if (e is! KeyDownEvent || _selected == null) return;
        final ch = e.character;
        if (ch != null && RegExp(r'^\d$').hasMatch(ch)) _key(ch);
        if (e.logicalKey == LogicalKeyboardKey.backspace && _pin.isNotEmpty) {
          setState(() => _pin = _pin.substring(0, _pin.length - 1));
        }
        if (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) _submit();
      },
      child: AuthFrame(
        onBack: _selected != null && (_staff?.length ?? 0) > 1
            ? () => setState(() {
                  _selected = null;
                  _pin = '';
                })
            : () => ref.read(sessionProvider.notifier).switchMode(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: MkLogo(height: 72)),
            const SizedBox(height: MkSpace.sm),
            Text('${dev?.businessName ?? ''} · ${dev?.branchName ?? ''}', textAlign: TextAlign.center, style: t.titleSmall),
            const SizedBox(height: MkSpace.xl),
            if (_loadError != null)
              MkErrorState(title: s.error(_loadError!), retryLabel: s.retry, onRetry: _load)
            else if (_staff == null)
              const Center(child: CircularProgressIndicator())
            else if (_selected == null) ...[
              Text(s.whoIsWorking, style: t.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: MkSpace.lg),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: MkSpace.sm,
                runSpacing: MkSpace.sm,
                children: [
                  for (final st in _staff!)
                    MkPressable(
                      onTap: () => setState(() => _selected = st),
                      child: Container(
                        width: 130,
                        padding: const EdgeInsets.all(MkSpace.md),
                        decoration: BoxDecoration(
                          color: MkColors.surface,
                          borderRadius: MkRadius.all(MkRadius.lg),
                          border: Border.all(color: MkColors.line),
                        ),
                        child: Column(children: [MkMonogram(name: st.name, size: 52), const SizedBox(height: 8), Text(st.name)]),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: MkSpace.xl),
              TextButton(onPressed: () => ref.read(sessionProvider.notifier).unpair(), child: Text(s.unpair)),
            ] else ...[
              Text('${_selected!.name}\n${s.enterPin}', style: t.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: MkSpace.lg),
              MkPinDots(length: 6, filled: _pin.length, error: _error),
              const SizedBox(height: MkSpace.lg),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: MkKeypad(
                  onKey: _key,
                  onBackspace: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)),
                ),
              ),
              const SizedBox(height: MkSpace.md),
              MkButton(label: s.continueLabel, loading: _busy, onPressed: _pin.length >= 4 ? _submit : null),
            ],
          ],
        ),
      ),
    );
  }
}
