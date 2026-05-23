import 'package:flutter/material.dart';

class AppColors {
  // Rentch brand palette (from SVG logo)
  static const Color primary = Color(0xFF13BEC9);      // teal
  static const Color primaryDark = Color(0xFF0D96A0);
  static const Color primaryLight = Color(0xFF5AD4DC);
  static const Color navy = Color(0xFF072946);          // dark navy
  static const Color coral = Color(0xFFFF5A67);         // coral/reject

  // Semantic
  static const Color like = Color(0xFF13BEC9);
  static const Color pass = Color(0xFFFF5A67);
  static const Color superLike = Color(0xFF4A6CF7);

  // Backgrounds
  static const Color background = Color(0xFFF2F7FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color cardBackground = Color(0xFFFFFFFF);

  // Text
  static const Color textPrimary = Color(0xFF072946);
  static const Color textSecondary = Color(0xFF5B7A99);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textDisabled = Color(0xFF9EB5C8);

  // Borders / dividers
  static const Color borderLight = Color(0xFFD8E8F0);
  static const Color divider = Color(0xFFE8F0F5);
  static const Color shadow = Color(0x18072946);

  // Legacy aliases (keep old code building)
  static const Color primaryLight2 = Color(0xFFE6F9FB);
  static const Color secondary = Color(0xFFFF5A67);
  static const Color success = Color(0xFF27AE60);
  static const Color warning = Color(0xFFF39C12);
  static const Color error = Color(0xFFFF5A67);
}
