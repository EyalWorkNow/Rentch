import 'package:flutter/widgets.dart';

/// Corner-radius scale — the values the UI already clusters on. `pill` is the
/// single fully-rounded convention (replaces the inconsistent 99 / 100 / 999).
abstract final class AppRadii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double pill = 999;

  static BorderRadius get brSm => BorderRadius.circular(sm);
  static BorderRadius get brMd => BorderRadius.circular(md);
  static BorderRadius get brLg => BorderRadius.circular(lg);
  static BorderRadius get brXl => BorderRadius.circular(xl);
  static BorderRadius get brXxl => BorderRadius.circular(xxl);
  static BorderRadius get brPill => BorderRadius.circular(pill);
}
