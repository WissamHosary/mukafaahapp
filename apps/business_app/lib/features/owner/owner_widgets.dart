import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_core/mk_core.dart';
import 'package:mk_ui/mk_ui.dart';

import '../../app/providers.dart';

String _two(int n) => n.toString().padLeft(2, '0');

String fmtDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

String fmtDateTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${fmtDate(d)} · ${_two(h)}:${_two(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
}

String isoDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// Picks a photo from the gallery, resized for upload. Returns null if cancelled.
Future<Uint8List?> pickImageBytes({double maxWidth = 1600}) async {
  final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: maxWidth, imageQuality: 82);
  if (x == null) return null;
  return x.readAsBytes();
}

class StatusPill extends ConsumerWidget {
  const StatusPill({required this.status, super.key});
  final String status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final (label, color) = switch (status) {
      'REQUESTED' => (s.tr('جديد', 'New'), MkColors.warning),
      'ACCEPTED' => (s.tr('مقبول', 'Accepted'), MkColors.success),
      'DECLINED' => (s.tr('مرفوض', 'Declined'), MkColors.danger),
      'CANCELLED' => (s.tr('ملغى', 'Cancelled'), MkColors.ink3),
      'REDEEMED' => (s.tr('مستعمل', 'Used'), MkColors.purple700),
      'ACTIVE' => (s.tr('فعّال', 'Active'), MkColors.success),
      'PAUSED' => (s.tr('موقّف', 'Paused'), MkColors.warning),
      'HIDDEN' => (s.tr('مخفي من مكافأة', 'Hidden by Mukafaah'), MkColors.danger),
      _ => (s.tr('منتهي', 'Expired'), MkColors.ink3),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: MkRadius.all(MkRadius.pill)),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
    );
  }
}

class InfoChip extends StatelessWidget {
  const InfoChip({required this.icon, required this.text, super.key});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: MkColors.purple50, borderRadius: MkRadius.all(MkRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: MkColors.purple700),
          const SizedBox(width: 4),
          Text(text, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

/// Image box: shows the current picture (or a placeholder) and picks a new one on tap.
class ImagePickBox extends StatelessWidget {
  const ImagePickBox({
    required this.onTap,
    this.url,
    this.bytes,
    this.label,
    this.aspectRatio = 16 / 9,
    this.circle = false,
    this.busy = false,
    super.key,
  });

  final String? url;
  final Uint8List? bytes;
  final String? label;
  final double aspectRatio;
  final bool circle;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final img = bytes != null
        ? Image.memory(bytes!, fit: BoxFit.cover)
        : url != null
            ? MkNetImage(url: url)
            : Container(
                color: MkColors.purple50,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_photo_alternate_rounded, color: MkColors.purple500, size: 32),
                    if (label != null) ...[
                      const SizedBox(height: 4),
                      Text(label!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: MkColors.purple700)),
                    ],
                  ],
                ),
              );
    final box = Stack(
      fit: StackFit.expand,
      children: [
        img,
        if (busy) const ColoredBox(color: Color(0x88FFFFFF), child: Center(child: CircularProgressIndicator())),
        if (!busy && (url != null || bytes != null))
          const PositionedDirectional(
            bottom: 6,
            end: 6,
            child: CircleAvatar(radius: 14, backgroundColor: Colors.white, child: Icon(Icons.edit_rounded, size: 16, color: MkColors.purple900)),
          ),
      ],
    );
    return MkPressable(
      onTap: busy ? null : onTap,
      child: circle
          ? SizedBox(width: 92, height: 92, child: ClipOval(child: box))
          : AspectRatio(aspectRatio: aspectRatio, child: ClipRRect(borderRadius: MkRadius.all(MkRadius.lg), child: box)),
    );
  }
}

/// "12.50" <-> 1250 helpers for price fields.
String minorToText(int? minor) {
  if (minor == null || minor == 0) return '';
  final major = minor ~/ 100;
  final cents = minor % 100;
  return cents == 0 ? '$major' : '$major.${cents.toString().padLeft(2, '0')}';
}

/// Shows an error toast with the translated API error.
void showApiError(BuildContext context, S s, Object e) {
  MkToast.show(context, e is ApiException ? s.errorV2(e.code) : s.somethingWrong, kind: MkToastKind.error);
}
