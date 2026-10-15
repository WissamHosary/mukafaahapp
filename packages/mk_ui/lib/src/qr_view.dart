import 'package:material_ui/material_ui.dart';
import 'package:qr/qr.dart';

import 'coin.dart';
import 'tokens.dart';

/// Branded QR: soft square modules in a deep purple gradient, rounded finder
/// eyes, and the Mukafaah coin in the middle. The code uses
/// the highest error correction, so the coin never stops it scanning.
class MkQr extends StatelessWidget {
  const MkQr({required this.data, this.size = 260, this.logo = true, super.key});

  final String data;
  final double size;

  /// Shows the Mukafaah coin in the middle.
  final bool logo;

  @override
  Widget build(BuildContext context) {
    final image = QrImage(
      QrCode(payload: QrPayload.fromString(data), errorCorrectLevel: logo ? QrErrorCorrectLevel.high : QrErrorCorrectLevel.medium),
    );
    final coin = size * 0.2;
    return Semantics(
      label: 'QR code',
      image: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            RepaintBoundary(child: CustomPaint(size: Size.square(size), painter: _QrPainter(image, coin: logo ? coin : 0))),
            if (logo)
              Container(
                width: coin,
                height: coin,
                padding: EdgeInsets.all(coin * 0.1),
                decoration: BoxDecoration(color: Colors.white, borderRadius: MkRadius.all(coin * 0.28)),
                child: const MkMCoin(),
              ),
          ],
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.qr, {required this.coin});

  final QrImage qr;

  /// Size of the clear square in the middle for the coin (0 = none).
  final double coin;

  bool _inFinder(int r, int c, int n) {
    bool box(int r0, int c0) => r >= r0 && r < r0 + 7 && c >= c0 && c < c0 + 7;
    return box(0, 0) || box(0, n - 7) || box(n - 7, 0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = qr.moduleCount;
    final cell = size.width / n;
    final dark = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [MkColors.purple900, Color(0xFF4B2370), MkColors.purple900],
      ).createShader(Offset.zero & size);
    final clear = Rect.fromCenter(center: size.center(Offset.zero), width: coin + cell, height: coin + cell);
    final modules = Path();
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (!qr.isDark(r, c) || _inFinder(r, c, n)) continue;
        final rect = Rect.fromLTWH(c * cell, r * cell, cell, cell);
        if (coin > 0 && clear.overlaps(rect.deflate(cell * 0.3))) continue;
        modules.addRRect(RRect.fromRectAndRadius(rect.deflate(cell * 0.06), Radius.circular(cell * 0.28)));
      }
    }
    canvas.drawPath(modules, dark);
    void eye(int r0, int c0) {
      final o = Offset(c0 * cell, r0 * cell);
      final outer = RRect.fromRectAndRadius(o & Size.square(cell * 7), Radius.circular(cell * 2.2));
      final inner = RRect.fromRectAndRadius((o + Offset(cell, cell)) & Size.square(cell * 5), Radius.circular(cell * 1.5));
      canvas.drawDRRect(outer, inner, dark);
      final dot = RRect.fromRectAndRadius((o + Offset(cell * 2, cell * 2)) & Size.square(cell * 3), Radius.circular(cell * 1.1));
      // The eyes stay solid: scanners find the code by them.
      canvas.drawRRect(dot, dark);
    }

    eye(0, 0);
    eye(0, n - 7);
    eye(n - 7, 0);
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.qr != qr || old.coin != coin;
}
