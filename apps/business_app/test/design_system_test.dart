import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mk_ui/mk_ui.dart';

Widget _wrap(Widget child, {TextDirection dir = TextDirection.ltr}) => MaterialApp(
      theme: MkTheme.light(),
      home: Directionality(textDirection: dir, child: Scaffold(body: Center(child: child))),
    );

void main() {
  testWidgets('MkButton calls onPressed and is disabled without it', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(MkButton(label: 'Give points', onPressed: () => taps++)));
    await tester.tap(find.text('Give points'));
    await tester.pumpAndSettle();
    expect(taps, 1);

    await tester.pumpWidget(_wrap(const MkButton(label: 'Disabled')));
    await tester.tap(find.text('Disabled'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('MkPinDots renders in RTL', (tester) async {
    await tester.pumpWidget(_wrap(const MkPinDots(length: 6, filled: 2), dir: TextDirection.rtl));
    expect(find.byType(MkPinDots), findsOneWidget);
  });

  testWidgets('AnimatedPoints settles on the server value', (tester) async {
    await tester.pumpWidget(_wrap(const AnimatedPoints(value: 1250)));
    await tester.pumpAndSettle();
    expect(find.text('1250'), findsOneWidget);
  });

  testWidgets('MkQr paints a code', (tester) async {
    await tester.pumpWidget(_wrap(const MkQr(data: 'MKF2:ABCDEFGH2345', size: 200)));
    expect(find.byType(MkQr), findsOneWidget);
  });
}
