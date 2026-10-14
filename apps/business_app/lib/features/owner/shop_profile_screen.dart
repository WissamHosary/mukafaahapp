import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';
import '../../data/api.dart';
import 'owner_shell.dart';
import 'owner_widgets.dart';

/// How the shop looks in the customer app: photos, category, description,
/// contact, location on the map, and points back ("deduction factor").
class ShopProfileScreen extends ConsumerWidget {
  const ShopProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return OwnerPage(
      title: s.tr('ملف المحل', 'Shop profile'),
      child: ref.watch(profileProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => MkErrorState(title: s.noConnection, retryLabel: s.retry, onRetry: () => ref.invalidate(profileProvider)),
            data: (p) => _ProfileForm(key: ValueKey(p['id']), p: p),
          ),
    );
  }
}

class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.p, super.key});
  final Json p;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  late final _name = TextEditingController(text: widget.p['name'] as String? ?? '');
  late final _desc = TextEditingController(text: widget.p['description'] as String? ?? '');
  late final _whatsapp = TextEditingController(text: widget.p['whatsapp'] as String? ?? '');
  late final _instagram = TextEditingController(text: widget.p['instagram'] as String? ?? '');
  late final _address = TextEditingController(text: widget.p['address'] as String? ?? '');
  late final _city = TextEditingController(text: widget.p['city'] as String? ?? '');
  late String _category = widget.p['category'] as String? ?? 'OTHER';
  /// Read only: Mukafaah Manager sets each shop's points-back %.
  late final int _earn = ((widget.p['earnPercent'] as num?) ?? 0).round();
  late bool _listed = widget.p['listed'] != false;
  late bool _transfer = widget.p['allowTransfer'] != false;
  late LatLng? _loc = widget.p['lat'] == null ? null : LatLng((widget.p['lat'] as num).toDouble(), (widget.p['lng'] as num).toDouble());
  bool _busy = false;
  String? _uploading;

  @override
  void dispose() {
    for (final c in [_name, _desc, _whatsapp, _instagram, _address, _city]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _upload(String purpose) async {
    final s = ref.read(stringsProvider);
    final bytes = await pickImageBytes(maxWidth: purpose == 'logo' ? 600 : 1600);
    if (bytes == null) return;
    setState(() => _uploading = purpose);
    try {
      await ref.read(apiProvider).uploadImage(purpose, bytes);
      ref.invalidate(profileProvider);
    } on Object catch (e) {
      if (mounted) showApiError(context, s, e);
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Future<void> _pickLocation() async {
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(builder: (_) => _LocationPicker(initial: _loc)),
    );
    if (picked != null) setState(() => _loc = picked);
  }

  Future<void> _save() async {
    final s = ref.read(stringsProvider);
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).updateProfile({
        'name': _name.text.trim(),
        'description': opt(_desc),
        'category': _category,
        'whatsapp': opt(_whatsapp),
        'instagram': opt(_instagram),
        'address': opt(_address),
        'city': opt(_city),
        'lat': _loc?.latitude,
        'lng': _loc?.longitude,
        'listed': _listed,
        'allowTransfer': _transfer,
      });
      ref
        ..invalidate(profileProvider)
        ..invalidate(businessProvider);
      if (mounted) MkToast.show(context, s.saved, kind: MkToastKind.success);
    } on Object catch (e) {
      if (mounted) showApiError(context, s, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final t = Theme.of(context).textTheme;
    final url = ref.watch(mediaUrlProvider);
    final p = widget.p;
    final example = 20 * _earn;
    final categories = categoryChoices(s, ref.watch(categoriesProvider).value);
    return ListView(
      padding: const EdgeInsets.all(MkSpace.lg),
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            ImagePickBox(
              url: url(p['coverUrl'] as String?),
              busy: _uploading == 'cover',
              label: s.tr('صورة الغلاف', 'Cover photo'),
              aspectRatio: 16 / 7,
              onTap: () => _upload('cover'),
            ),
            PositionedDirectional(
              start: MkSpace.md,
              bottom: -40,
              child: Container(
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 4), boxShadow: MkShadow.soft),
                child: ImagePickBox(
                  url: url(p['logoUrl'] as String?),
                  busy: _uploading == 'logo',
                  label: s.tr('اللوغو', 'Logo'),
                  circle: true,
                  onTap: () => _upload('logo'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 52),
        TextField(controller: _name, maxLength: 80, decoration: InputDecoration(labelText: s.tr('اسم المحل', 'Shop name'))),
        DropdownButtonFormField<String>(
          // Rebuilt when the category list arrives from the server.
          key: ValueKey(categories.length),
          initialValue: categories.any((c) => c.$1 == _category) ? _category : null,
          decoration: InputDecoration(labelText: s.tr('الفئة', 'Category')),
          items: [
            for (final (key, label) in categories) DropdownMenuItem(value: key, child: Text(label)),
          ],
          onChanged: (v) => setState(() => _category = v ?? _category),
        ),
        const SizedBox(height: MkSpace.sm),
        TextField(controller: _desc, maxLength: 600, maxLines: 3, minLines: 2, decoration: InputDecoration(labelText: s.tr('عن المحل', 'About the shop'))),
        MkSectionHeader(title: s.tr('النقاط المرتجعة', 'Points back')),
        MkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text(s.tr('نسبة من كل فاتورة بترجع نقاط', 'Share of every bill given back as points'), style: t.bodyMedium)),
                  Text('$_earn%', style: t.headlineSmall?.copyWith(color: MkColors.purple700)),
                ],
              ),
              const SizedBox(height: MkSpace.xs),
              Row(
                children: [
                  const Icon(Icons.lock_rounded, size: 14, color: MkColors.ink3),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      s.tr('بتحددها مكافأة. لتغييرها احكي فريق مكافأة.', 'Set by Mukafaah. Contact the Mukafaah team to change it.'),
                      style: t.labelSmall?.copyWith(color: MkColors.ink3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: MkSpace.xs),
              Text(
                s.tr(
                  'مثال: فاتورة \$٢٠ ← $example نقطة (١٠٠ نقطة = \$١ خصم)',
                  'Example: a \$20 bill → $example points (100 points = \$1 off)',
                ),
                style: t.bodySmall?.copyWith(color: MkColors.ink3),
              ),
            ],
          ),
        ),
        MkSectionHeader(title: s.tr('التواصل', 'Contact')),
        TextField(
          controller: _whatsapp,
          keyboardType: TextInputType.phone,
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
          decoration: InputDecoration(
            labelText: s.tr('واتساب للطلبات', 'WhatsApp for orders'),
            hintText: '+961 70 123 456',
            prefixIcon: const Icon(Icons.chat_rounded),
          ),
        ),
        const SizedBox(height: MkSpace.sm),
        TextField(
          controller: _instagram,
          decoration: const InputDecoration(labelText: 'Instagram', hintText: '@yourshop', prefixIcon: Icon(Icons.camera_alt_rounded)),
        ),
        MkSectionHeader(title: s.tr('الموقع', 'Location')),
        TextField(controller: _address, decoration: InputDecoration(labelText: s.tr('العنوان', 'Address'), hintText: s.tr('شارع الحمرا', 'Hamra Street'))),
        const SizedBox(height: MkSpace.sm),
        TextField(controller: _city, decoration: InputDecoration(labelText: s.tr('المدينة', 'City'), hintText: s.tr('بيروت', 'Beirut'))),
        const SizedBox(height: MkSpace.sm),
        MkCard(
          onTap: _pickLocation,
          child: Row(
            children: [
              MkIconTile(icon: _loc == null ? Icons.add_location_alt_rounded : Icons.location_on_rounded),
              const SizedBox(width: MkSpace.sm),
              Expanded(
                child: Text(
                  _loc == null
                      ? s.tr('حدد المحل عالخريطة', 'Pin your shop on the map')
                      : '${_loc!.latitude.toStringAsFixed(5)}, ${_loc!.longitude.toStringAsFixed(5)}',
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
        MkSectionHeader(title: s.tr('الظهور', 'Visibility')),
        MkCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SwitchListTile(
                value: _listed,
                onChanged: (v) => setState(() => _listed = v),
                title: Text(s.tr('بيبيّن بتطبيق الزباين', 'Show in the customer app')),
              ),
              SwitchListTile(
                value: _transfer,
                onChanged: (v) => setState(() => _transfer = v),
                title: Text(s.tr('الزباين فيهن يحولوا نقاطك لبعض', 'Customers can send your points to each other')),
              ),
            ],
          ),
        ),
        const SizedBox(height: MkSpace.lg),
        MkButton(label: s.save, icon: Icons.check_rounded, kind: MkButtonKind.accent, loading: _busy, onPressed: _save),
        const SizedBox(height: MkSpace.xxl),
      ],
    );
  }
}

class _LocationPicker extends ConsumerStatefulWidget {
  const _LocationPicker({this.initial});
  final LatLng? initial;

  @override
  ConsumerState<_LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends ConsumerState<_LocationPicker> {
  late LatLng? _point = widget.initial;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.tr('اضغط على مكان المحل', 'Tap where your shop is'))),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: widget.initial ?? const LatLng(33.8938, 35.5018),
              initialZoom: widget.initial == null ? 12 : 16,
              onTap: (_, ll) => setState(() => _point = ll),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'app.mukafaah.mukafaah_business',
              ),
              if (_point != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _point!,
                      width: 44,
                      height: 52,
                      alignment: Alignment.topCenter,
                      child: const Icon(Icons.location_on_rounded, size: 48, color: MkColors.purple900),
                    ),
                  ],
                ),
              SimpleAttributionWidget(source: Text('OpenStreetMap contributors')),
            ],
          ),
          Positioned(
            left: MkSpace.lg,
            right: MkSpace.lg,
            bottom: MkSpace.xl,
            child: SafeArea(
              child: MkButton(
                label: s.tr('استعمل هالموقع', 'Use this location'),
                kind: MkButtonKind.accent,
                onPressed: _point == null ? null : () => Navigator.of(context).pop(_point),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
