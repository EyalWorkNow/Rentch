import 'package:flutter/material.dart';

class AppColors {
  // Rently brand palette (from SVG logo). The four brand-accent colours are
  // RUNTIME-SWAPPABLE by account type: brokers (מתווך) get an indigo identity
  // app-wide. They are non-const on purpose — call [applyRole] on login / role
  // change, then rebuild the tree so every widget repaints in the new accent.
  static Color primary = const Color(0xFF13BEC9);      // teal
  static Color primaryDark = const Color(0xFF0D96A0);
  static Color primaryLight = const Color(0xFF5AD4DC);

  /// Switches the brand accent to match [role] ('broker' → indigo, else teal).
  static void applyRole(String role) {
    if (role == 'broker') {
      primary = const Color(0xFF6C5CE7);
      primaryDark = const Color(0xFF5346C9);
      primaryLight = const Color(0xFF9D90FF);
      primaryLight2 = const Color(0xFFEEEBFF);
    } else {
      primary = const Color(0xFF13BEC9);
      primaryDark = const Color(0xFF0D96A0);
      primaryLight = const Color(0xFF5AD4DC);
      primaryLight2 = const Color(0xFFE6F9FB);
    }
  }

  static const Color navy = Color(0xFF072946);          // dark navy
  static const Color coral = Color(0xFFFF5A67);         // coral/reject

  // Semantic
  static const Color like = Color(0xFF13BEC9);
  static const Color pass = Color(0xFFFF5A67);
  static const Color superLike = Color(0xFF4A6CF7);

  // Backgrounds
  static const Color background = Color(0xFFFFFFFF);
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
  static Color primaryLight2 = const Color(0xFFE6F9FB);
  static const Color secondary = Color(0xFFFF5A67);
  static const Color success = Color(0xFF27AE60);
  static const Color warning = Color(0xFFF39C12);
  static const Color error = Color(0xFFFF5A67);
}
