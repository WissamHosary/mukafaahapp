import 'package:material_ui/material_ui.dart';

/// Brand palette taken from the Mukafaah identity (logo and social posts).
abstract final class MkColors {
  // Brand
  static const purple900 = Color(0xFF2C123F); // logo purple
  static const purple800 = Color(0xFF3A1A55);
  static const purple700 = Color(0xFF4B2370);
  static const purple500 = Color(0xFF7446A8);
  static const purple100 = Color(0xFFEDE5F6);
  static const purple50 = Color(0xFFF7F3FB);
  static const yellow500 = Color(0xFFFBD404); // signature yellow
  static const yellow600 = Color(0xFFE9C200);
  static const yellow200 = Color(0xFFFFEB80);
  static const yellow50 = Color(0xFFFFFBE6);

  // Neutrals (warm, slightly purple-tinted)
  static const ink = Color(0xFF1C1024);
  static const ink2 = Color(0xFF4E4458);
  static const ink3 = Color(0xFF857B8E);
  static const line = Color(0xFFE8E2EE);
  static const surface = Color(0xFFFFFFFF);
  static const canvas = Color(0xFFFAF8FC);

  // Semantic
  static const success = Color(0xFF17895E);
  static const successBg = Color(0xFFE5F6EE);
  static const danger = Color(0xFFC8303F);
  static const dangerBg = Color(0xFFFCE9EB);
  static const warning = Color(0xFFB86E00);
  static const warningBg = Color(0xFFFFF3DD);

  // Program type colors
  static const inStore = purple700;
  static const shared = Color(0xFF0E7C86);
  static const network = Color(0xFFB0507A);
}

abstract final class MkSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

abstract final class MkRadius {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;
  static BorderRadius all(double r) => BorderRadius.circular(r);
}

/// Shared motion tokens: every animation in the apps uses these.
abstract final class MkMotion {
  static const fast = Duration(milliseconds: 140);
  static const base = Duration(milliseconds: 240);
  static const slow = Duration(milliseconds: 420);
  static const count = Duration(milliseconds: 900);
  static const stagger = Duration(milliseconds: 55);
  static const Curve enter = Curves.easeOutCubic;
  static const Curve exit = Curves.easeInCubic;
  static const Curve emphasized = Curves.easeOutBack;
  static const Curve standard = Curves.easeInOutCubic;
}

abstract final class MkShadow {
  static const soft = [
    BoxShadow(color: Color(0x142C123F), blurRadius: 18, offset: Offset(0, 6)),
  ];
  static const lifted = [
    BoxShadow(color: Color(0x262C123F), blurRadius: 28, offset: Offset(0, 12)),
  ];
  static const glow = [
    BoxShadow(color: Color(0x55FBD404), blurRadius: 24, offset: Offset(0, 8)),
  ];
}

abstract final class MkIconSize {
  static const double sm = 18;
  static const double md = 22;
  static const double lg = 28;
  static const double xl = 40;
}
