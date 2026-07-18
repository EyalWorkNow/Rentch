import 'package:flutter/material.dart';

import 'brand_palette.dart';

class AppColors {
  // Rently brand palette (from SVG logo). The four brand-accent colours are
  // RUNTIME-SWAPPABLE by account type: brokers (מתווך) get an indigo identity
  // app-wide. They are non-const on purpose — call [applyRole] on login / role
  // change, then rebuild the tree so every widget repaints in the new accent.
  // The concrete hex values live in ONE place — [BrandPalette] — so the accent
  // can be re-skinned there without drift between this and the theme builder.
  static Color primary = BrandPalette.teal.primary;      // teal
  static Color primaryDark = BrandPalette.teal.primaryDark;
  static Color primaryLight = BrandPalette.teal.primaryLight;

  /// Switches the brand accent to match [role] ('broker' → black, else teal).
  /// Sources the values from [BrandPalette] (the single source of truth).
  static void applyRole(String role) {
    final palette = BrandPalette.forRole(role);
    primary = palette.primary;
    primaryDark = palette.primaryDark;
    primaryLight = palette.primaryLight;
    primaryLight2 = palette.primaryLight2;
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
  static Color primaryLight2 = BrandPalette.teal.primaryLight2;
  static const Color secondary = Color(0xFFFF5A67);
  static const Color success = Color(0xFF27AE60);
  static const Color warning = Color(0xFFF39C12);
  static const Color error = Color(0xFFFF5A67);

  // Neutral / slate scale — the ad-hoc grays scattered across screens, codified
  // (these are the Tailwind-slate values the UI already uses as one-off literals).
  // Migrate `Color(0xFF..)` grays to these so neutrals change in one place.
  static const Color slate50 = Color(0xFFF8FAFC); // near-white surfaces
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate200 = Color(0xFFE2E8F0); // hairline borders
  static const Color slate300 = Color(0xFFCBD5E1);
  static const Color slate400 = Color(0xFF94A3B8); // muted icons
  static const Color slate500 = Color(0xFF64748B); // secondary text
  static const Color slate700 = Color(0xFF334155);
  static const Color slate900 = Color(0xFF0F172A); // near-black ink
  static const Color mist = Color(0xFFD0EDF0); // teal-tinted inactive track

  // ── Curated colour pick-list (extend these to re-skin the app) ─────────
  static const Color amber = Color(0xFFF59E0B);
  static const Color amberDark = Color(0xFFCA8A04);
  static const Color amberDeep = Color(0xFF854D0E);
  static const Color blue = Color(0xFF2563EB);
  static const Color border = Color(0xFFE2ECF1);
  static const Color cloud = Color(0xFFF5F7FA);
  static const Color emerald = Color(0xFF10B981);
  static const Color green = Color(0xFF16A34A);
  static const Color greenBright = Color(0xFF22C55E);
  static const Color indigoDeep = Color(0xFF1E3A8A);
  static const Color ink = Color(0xFF0F172A);
  static const Color inkSoft = Color(0xFF1E293B);
  static const Color navyDeep = Color(0xFF06243A);
  static const Color purple = Color(0xFF6C5CE7);
  static const Color red = Color(0xFFEF4444);
  static const Color slate600 = Color(0xFF475569);
  static const Color tealBrand = Color(0xFF13BEC9);
  static const Color tealBright = Color(0xFF7CE0E6);
  static const Color tealDark = Color(0xFF0D96A0);
  static const Color tealLight = Color(0xFF5AD4DC);
  static const Color tealPale = Color(0xFFE6F9FB);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color yellowPale = Color(0xFFFEF08A);
}
