/// Formatting helpers. Amounts travel as integer minor units (cents); never doubles in logic.
String formatPoints(num value) {
  final neg = value < 0;
  final s = value.abs().round().toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return '${neg ? '-' : ''}$out';
}

String formatMinor(int minor, String currency) {
  final major = minor ~/ 100;
  final cents = (minor % 100).toString().padLeft(2, '0');
  final symbol = currency == 'USD' ? r'$' : '$currency ';
  return '$symbol${formatPoints(major)}${cents == '00' ? '' : '.$cents'}';
}

/// Parses a typed amount like "12.5" into minor units (1250). Returns null when invalid.
int? parseToMinor(String input) {
  final t = input.trim().replaceAll(',', '');
  if (t.isEmpty) return null;
  final m = RegExp(r'^(\d{1,9})(?:\.(\d{0,2}))?$').firstMatch(t);
  if (m == null) return null;
  final major = int.parse(m.group(1)!);
  final frac = (m.group(2) ?? '').padRight(2, '0');
  return major * 100 + int.parse(frac.isEmpty ? '0' : frac);
}

String maskPhone(String? last4) => last4 == null ? '' : '•••• $last4';
