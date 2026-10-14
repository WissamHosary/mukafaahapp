import 'package:flutter_map/flutter_map.dart';
import 'package:material_ui/material_ui.dart';

/// OpenStreetMap tiles softened for Mukafaah: less saturated and a little
/// brighter, with a faint violet tint, so the brand pins stand out.
const ColorFilter kMukafaahMapFilter = ColorFilter.matrix(<double>[
  0.685, 0.286, 0.029, 0, 8, //
  0.085, 0.886, 0.029, 0, 4, //
  0.085, 0.286, 0.629, 0, 16, //
  0, 0, 0, 1, 0, //
]);

/// The street map layer used everywhere in the app.
TileLayer mukafaahTiles() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'app.mukafaah.mukafaah_customer',
      maxNativeZoom: 19,
      tileBuilder: (context, tile, _) => ColorFiltered(colorFilter: kMukafaahMapFilter, child: tile),
    );

/// Shop pin: a teardrop in [color] holding [child] (usually the shop logo).
class MkMapPin extends StatelessWidget {
  const MkMapPin({required this.color, required this.child, this.size = 44, super.key});
  final Color color;
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 1.23,
      child: CustomPaint(
        painter: _TeardropPainter(color),
        child: Padding(
          padding: EdgeInsets.fromLTRB(size * .11, size * .11, size * .11, size * .34),
          child: ClipOval(child: child),
        ),
      ),
    );
  }
}

class _TeardropPainter extends CustomPainter {
  _TeardropPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final r = w / 2;
    final path = Path()
      ..moveTo(r, size.height)
      ..cubicTo(r - 6, size.height - 10, 0, r + 12, 0, r)
      ..arcToPoint(Offset(w, r), radius: Radius.circular(r))
      ..cubicTo(w, r + 12, r + 6, size.height - 10, r, size.height)
      ..close();
    canvas.drawShadow(path, const Color(0x662C123F), 4, false);
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawCircle(Offset(r, r), r - 3, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_TeardropPainter old) => old.color != color;
}
