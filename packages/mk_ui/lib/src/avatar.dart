import 'package:material_ui/material_ui.dart';

import 'catalog_widgets.dart';
import 'coin.dart';
import 'tokens.dart';

/// A member's picture: their photo when they added one, otherwise the
/// Mukafaah avatar for their gender (MALE / FEMALE), or the Mukafaah coin.
class MkAvatar extends StatelessWidget {
  const MkAvatar({this.photoUrl, this.gender, this.size = 52, this.ring = true, super.key});

  final String? photoUrl;
  final String? gender;
  final double size;

  /// Gold ring around the picture.
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final inner = photoUrl != null && photoUrl!.isNotEmpty
        ? MkNetImage(url: photoUrl, fallbackIcon: Icons.person_rounded, cacheWidth: (size * 3).round())
        : CustomPaint(painter: _MukafaahAvatar(gender));
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(ring ? size * 0.045 : 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: ring ? const LinearGradient(colors: [Color(0xFFFFE97A), MkColors.yellow500, Color(0xFFE0A800)]) : null,
      ),
      child: ClipOval(child: SizedBox.expand(child: inner)),
    );
  }
}

/// The Mukafaah avatars: a friendly face in a gold Mukafaah top with the M coin
/// on the chest. Drawn with shapes, so they stay sharp and weigh nothing.
class _MukafaahAvatar extends CustomPainter {
  _MukafaahAvatar(this.gender);
  final String? gender;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    Offset p(double x, double y) => Offset(x * s, y * s);
    final bg = Offset.zero & size;
    canvas.drawRect(
      bg,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0, -0.3),
          radius: 0.9,
          colors: [Color(0xFF8C5CC4), MkColors.purple700, MkColors.purple900],
          stops: [0, 0.55, 1],
        ).createShader(bg),
    );
    if (gender != 'MALE' && gender != 'FEMALE') {
      paintMukafaahCoin(canvas, p(0.5, 0.5), s * 0.32);
      return;
    }
    final female = gender == 'FEMALE';
    const hair = Color(0xFF3A2216);
    const skin = Color(0xFFF1C49B);
    const skinShade = Color(0xFFDDA67C);

    // Long hair behind the head and shoulders.
    if (female) {
      canvas.drawPath(
        Path()
          ..moveTo(s * 0.24, s * 0.42)
          ..quadraticBezierTo(s * 0.2, s * 0.18, s * 0.5, s * 0.15)
          ..quadraticBezierTo(s * 0.8, s * 0.18, s * 0.76, s * 0.42)
          ..lineTo(s * 0.8, s * 0.8)
          ..lineTo(s * 0.2, s * 0.8)
          ..close(),
        Paint()..color = hair,
      );
    }
    // Shoulders in the gold Mukafaah top.
    final body = Path()
      ..moveTo(s * 0.1, s * 1.02)
      ..quadraticBezierTo(s * 0.12, s * 0.7, s * 0.5, s * 0.68)
      ..quadraticBezierTo(s * 0.88, s * 0.7, s * 0.9, s * 1.02)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE97A), MkColors.yellow500, Color(0xFFE0A800)],
        ).createShader(Rect.fromLTWH(0, s * 0.68, s, s * 0.34)),
    );
    // Neck and collar.
    canvas
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(s * 0.44, s * 0.55, s * 0.12, s * 0.16), Radius.circular(s * 0.04)), Paint()..color = skinShade)
      ..drawPath(
        Path()
          ..moveTo(s * 0.38, s * 0.69)
          ..quadraticBezierTo(s * 0.5, s * 0.8, s * 0.62, s * 0.69)
          ..quadraticBezierTo(s * 0.5, s * 0.74, s * 0.38, s * 0.69)
          ..close(),
        Paint()..color = MkColors.purple900.withValues(alpha: 0.85),
      );
    // The M coin on the chest.
    paintMukafaahCoin(canvas, p(0.66, 0.86), s * 0.075);
    // Head.
    canvas.drawOval(Rect.fromCenter(center: p(0.5, 0.42), width: s * 0.36, height: s * 0.4), Paint()..color = skin);
    // Ears.
    canvas
      ..drawCircle(p(0.32, 0.44), s * 0.035, Paint()..color = skinShade)
      ..drawCircle(p(0.68, 0.44), s * 0.035, Paint()..color = skinShade);
    // Hair on top.
    if (female) {
      canvas.drawPath(
        Path()
          ..moveTo(s * 0.3, s * 0.42)
          ..quadraticBezierTo(s * 0.3, s * 0.2, s * 0.52, s * 0.21)
          ..quadraticBezierTo(s * 0.72, s * 0.22, s * 0.7, s * 0.42)
          ..quadraticBezierTo(s * 0.6, s * 0.3, s * 0.44, s * 0.31)
          ..quadraticBezierTo(s * 0.36, s * 0.33, s * 0.3, s * 0.42)
          ..close(),
        Paint()..color = hair,
      );
      // Gold hair clip.
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: p(0.63, 0.29), width: s * 0.09, height: s * 0.04), Radius.circular(s * 0.02)),
        Paint()..color = MkColors.yellow500,
      );
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(s * 0.31, s * 0.4)
          ..quadraticBezierTo(s * 0.29, s * 0.2, s * 0.5, s * 0.2)
          ..quadraticBezierTo(s * 0.72, s * 0.2, s * 0.69, s * 0.4)
          ..quadraticBezierTo(s * 0.66, s * 0.31, s * 0.56, s * 0.31)
          ..quadraticBezierTo(s * 0.44, s * 0.33, s * 0.36, s * 0.3)
          ..quadraticBezierTo(s * 0.33, s * 0.33, s * 0.31, s * 0.4)
          ..close(),
        Paint()..color = hair,
      );
    }
    // Face: eyes, cheeks, smile.
    final ink = Paint()..color = const Color(0xFF2A1A12);
    canvas
      ..drawOval(Rect.fromCenter(center: p(0.43, 0.44), width: s * 0.035, height: s * 0.045), ink)
      ..drawOval(Rect.fromCenter(center: p(0.57, 0.44), width: s * 0.035, height: s * 0.045), ink)
      ..drawCircle(p(0.395, 0.505), s * 0.03, Paint()..color = const Color(0x55E86A7A))
      ..drawCircle(p(0.605, 0.505), s * 0.03, Paint()..color = const Color(0x55E86A7A))
      ..drawArc(
        Rect.fromCenter(center: p(0.5, 0.5), width: s * 0.12, height: s * 0.08),
        0.25,
        2.64,
        false,
        Paint()
          ..color = const Color(0xFF7A3A2A)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.018
          ..strokeCap = StrokeCap.round,
      );
  }

  @override
  bool shouldRepaint(_MukafaahAvatar old) => old.gender != gender;
}
