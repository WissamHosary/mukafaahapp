import 'package:flutter_test/flutter_test.dart';
import 'package:mk_core/mk_core.dart';

void main() {
  group('parseToMinor', () {
    test('parses whole and decimal amounts into cents', () {
      expect(parseToMinor('25'), 2500);
      expect(parseToMinor('12.5'), 1250);
      expect(parseToMinor('0.99'), 99);
      expect(parseToMinor('1,200.10'), 120010);
    });

    test('rejects invalid input', () {
      expect(parseToMinor(''), isNull);
      expect(parseToMinor('abc'), isNull);
      expect(parseToMinor('1.234'), isNull);
      expect(parseToMinor('-5'), isNull);
    });
  });

  test('formatPoints groups thousands', () {
    expect(formatPoints(0), '0');
    expect(formatPoints(1250), '1,250');
    expect(formatPoints(1234567), '1,234,567');
    expect(formatPoints(-300), '-300');
  });

  test('formatMinor shows dollars', () {
    expect(formatMinor(2500, 'USD'), r'$25');
    expect(formatMinor(1250, 'USD'), r'$12.50');
  });

  test('newUuid is a v4 uuid and unique', () {
    final a = newUuid();
    final b = newUuid();
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(a), isTrue);
    expect(a == b, isFalse);
  });

  test('strings exist in both languages', () {
    const ar = S('ar');
    const en = S('en');
    expect(ar.collect, isNot(en.collect));
    expect(en.error('INSUFFICIENT_BALANCE'), 'Not enough points');
    expect(en.programType('NETWORK'), 'Closed Network');
  });
}
