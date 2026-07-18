import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Typography root: font family, a numeric type scale, semantic weights, and a
/// handful of named text styles. The family is set once on the theme (main.dart)
/// and inherited — use [family]/[familyFallback] only when overriding explicitly.
abstract final class AppType {
  static const String family = 'SF Hebrew Rounded';
  static const List<String> familyFallback = ['SF Pro Rounded', 'Rubik'];

  // Type scale (the sizes the UI already uses).
  static const double display = 28;
  static const double h1 = 22;
  static const double h2 = 20;
  static const double h3 = 17;
  static const double title = 15;
  static const double body = 14;
  static const double bodySm = 13;
  static const double caption = 12;
  static const double label = 11;
  static const double micro = 10;

  // Semantic weight aliases.
  static const FontWeight black = FontWeight.w900;
  static const FontWeight heavy = FontWeight.w800;
  static const FontWeight bold = FontWeight.w700;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight regular = FontWeight.w400;

  // Named styles (navy default ink). Colours come from the token root.
  static const TextStyle pageTitle =
      TextStyle(fontSize: h1, fontWeight: black, color: AppColors.navy);
  static const TextStyle sectionTitle =
      TextStyle(fontSize: h3, fontWeight: heavy, color: AppColors.navy);
  static const TextStyle cardTitle =
      TextStyle(fontSize: title, fontWeight: heavy, color: AppColors.navy);
  static const TextStyle bodyText =
      TextStyle(fontSize: body, fontWeight: medium, color: AppColors.navy);
  static const TextStyle secondaryText =
      TextStyle(fontSize: caption, fontWeight: medium, color: AppColors.textSecondary);
  static const TextStyle labelText =
      TextStyle(fontSize: label, fontWeight: bold, color: AppColors.textSecondary);
}
