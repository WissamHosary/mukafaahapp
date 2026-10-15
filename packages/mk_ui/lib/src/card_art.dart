import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Pieces of the Mukafaah member card, shared by the welcome screen.

/// Gold EMV-style chip.
class MkCardChip extends StatelessWidget {
  const MkCardChip({required this.width, super.key});
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: width * 0.76,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(width * 0.17),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFE97A), Color(0xFFD9A400), Color(0xFFFFE38A)],
          stops: [0, 0.6, 1],
        ),
        border: Border.all(color: const Color(0x59785000)),
      ),
      child: CustomPaint(painter: _ChipLines()),
    );
  }
}

class _ChipLines extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x8C785000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final w = size.width, h = size.height;
    canvas
      ..drawLine(Offset(0, h * 0.34), Offset(w, h * 0.34), p)
      ..drawLine(Offset(0, h * 0.66), Offset(w, h * 0.66), p)
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(w * 0.3, h * 0.2, w * 0.7, h * 0.8), Radius.circular(w * 0.08)), p);
  }

  @override
  bool shouldRepaint(_ChipLines old) => false;
}

/// Fine wavy gold security lines, like on a bank card.
class MkGuilloche extends CustomPainter {
  const MkGuilloche();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0x21FBD404);
    for (var k = 0; k < 14; k++) {
      final path = Path();
      for (var x = 0.0; x <= size.width; x += 6) {
        final y = size.height * (0.15 + k * 0.055) + math.sin(x / size.width * math.pi * 3 + k * 0.5) * size.height * 0.07;
        x == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(MkGuilloche old) => false;
}
