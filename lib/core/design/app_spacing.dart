import 'package:flutter/widgets.dart';

/// Spacing scale — the app's de-facto 4px rhythm, codified. Prefer these over
/// magic numbers so global spacing changes happen in one place.
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16; // default page / card inset
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;

  /// Standard horizontal page inset used across screens.
  static const EdgeInsets pageInset = EdgeInsets.symmetric(horizontal: md);

  /// Standard card interior padding.
  static const EdgeInsets cardInset = EdgeInsets.all(md);

  // Vertical gaps (for Columns).
  static const SizedBox vXs = SizedBox(height: xs);
  static const SizedBox vSm = SizedBox(height: sm);
  static const SizedBox vMd = SizedBox(height: md);
  static const SizedBox vLg = SizedBox(height: lg);

  // Horizontal gaps (for Rows).
  static const SizedBox hXs = SizedBox(width: xs);
  static const SizedBox hSm = SizedBox(width: sm);
  static const SizedBox hMd = SizedBox(width: md);
}
