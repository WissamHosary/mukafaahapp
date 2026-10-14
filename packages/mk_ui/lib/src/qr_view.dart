import 'package:material_ui/material_ui.dart';
import 'package:qr/qr.dart';

import 'tokens.dart';

/// Branded QR: rounded purple modules and finder eyes. Nothing sits on top of the
/// code, so every module is visible to the cashier's scanner.
class MkQr extends StatelessWidget {
  const MkQr({required this.data, this.size = 260, super.key});

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final image = QrImage(QrCode(payload: QrPayload.fromString(data), errorCorrectLevel: QrErrorCorrectLevel.medium));
    return Semantics(
      label: 'QR code',
      image: true,
      child: CustomPaint(size: Size.square(size), painter: _QrPainter(image)),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.qr);

  final QrImage qr;

  bool _inFinder(int r, int c, int n) {
    bool box(int r0, int c0) => r >= r0 && r < r0 + 7 && c >= c0 && c < c0 + 7;
    return box(0, 0) || box(0, n - 7) || box(n - 7, 0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = qr.moduleCount;
    final cell = size.width / n;
    final dark = Paint()..color = MkColors.purple900;
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (!qr.isDark(r, c) || _inFinder(r, c, n)) continue;
        final rect = Rect.fromLTWH(c * cell, r * cell, cell, cell).deflate(cell * 0.08);
        canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.35)), dark);
      }
    }
    void eye(int r0, int c0) {
      final o = Offset(c0 * cell, r0 * cell);
      final outer = RRect.fromRectAndRadius(o & Size.square(cell * 7), Radius.circular(cell * 2));
      final inner = RRect.fromRectAndRadius((o + Offset(cell, cell)) & Size.square(cell * 5), Radius.circular(cell * 1.4));
      canvas.drawDRRect(outer, inner, dark);
      final dot = RRect.fromRectAndRadius((o + Offset(cell * 2, cell * 2)) & Size.square(cell * 3), Radius.circular(cell));
      canvas.drawRRect(dot, Paint()..color = MkColors.purple900);
    }

    eye(0, 0);
    eye(0, n - 7);
    eye(n - 7, 0);
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.qr != qr;
}
