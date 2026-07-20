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

  static Color? customPrimary;

  /// Switches the brand accent to match [role] ('broker' → black, else teal/custom).
  /// Sources the values from [BrandPalette] (the single source of truth).
  static void applyRole(String role) {
    final palette = BrandPalette.forRole(role);
    if (customPrimary != null && role != 'broker') {
      primary = customPrimary!;
      final hsl = HSLColor.fromColor(primary);
      primaryDark = hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).toColor();
      primaryLight = hsl.withLightness((hsl.lightness + 0.15).clamp(0.0, 1.0)).toColor();
      primaryLight2 = hsl.withLightness(0.97).toColor();
    } else {
      primary = palette.primary;
      primaryDark = palette.primaryDark;
      primaryLight = palette.primaryLight;
      primaryLight2 = palette.primaryLight2;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  //  THE SWAP CONTRACT — read before adding ANY colour
  //  ───────────────────────────────────────────────────────────────────────
  //  ONLY these follow the account accent (they re-tint on applyRole / picker):
  //      primary · primaryDark · primaryLight · primaryLight2 · accentGlow() ·
  //      accentSoft() · accentBg
  //  Use them for anything BRAND — buttons, active/selected states, focus
  //  rings, accent gradients, brand glows, the "on" side of a toggle.
  //
  //  EVERYTHING ELSE below (semantic · neutral · brand-const) is FIXED and must
  //  NOT move when the accent swaps: a success tick stays green, an error stays
  //  red, a score stays on its traffic-scale, a scrim stays black — by design.
  //  That is what makes "swap the theme" behave correctly per colour TYPE.
  // ═══════════════════════════════════════════════════════════════════════

  /// Brand accent at [o] opacity — for glows/large fills that must re-tint with
  /// the account. Non-const on purpose (tracks the swappable [primary]).
  static Color accentGlow([double o = 0.25]) => primary.withValues(alpha: o);

  /// Brand accent as a soft wash (borders/hover). Re-tints with the account.
  static Color accentSoft([double o = 0.12]) => primary.withValues(alpha: o);

  /// Faint brand-tinted surface (chips/section fills). Re-tints with the account.
  static Color get accentBg => primaryLight2;

  /// True when the live accent is the broker (premium black) identity. Screens
  /// that branch broker-vs-default styling MUST use this instead of comparing
  /// [primary] to a hardcoded `Color(0xFF000000)` — otherwise the branch breaks
  /// the moment the palette is re-skinned or a custom accent happens to be dark.
  static bool get isBrokerAccent => primary == BrandPalette.broker.primary;

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

  // ── FIXED semantic scales (meaning-carrying — never swap) ───────────────
  // Each has a solid tone, a darker tone, and a soft background tint so a
  // status pill/badge/banner needs zero raw literals.
  static const Color successDeep = Color(0xFF15803D); // strong-positive / high score
  static const Color successBg = Color(0xFFECFDF5);
  static const Color warningDeep = Color(0xFFC2410C); // burnt-orange caution / mixed
  static const Color warningBg = Color(0xFFFEF3C7);
  static const Color danger = Color(0xFFE11D48); // rose-red alert
  static const Color dangerDeep = Color(0xFFB91C1C);
  static const Color dangerSoft = Color(0xFFFCA5A5);
  static const Color info = Color(0xFF2563EB); // informational blue
  static const Color infoDeep = Color(0xFF1D4ED8);
  static const Color sky = Color(0xFF38B6FF); // bright action/save cyan-blue
  static const Color pink = Color(0xFFEC4899); // categorical accent (charts/tags)
  static const Color carrot = Color(0xFFE67E22); // warm highlight (streaks/FOMO)

  // Neighbourhood/price SCORE tiers — a fixed traffic-scale, brand-independent.
  static const Color scoreStrong = successDeep; // ≥80
  static const Color scoreGood = infoDeep;       // 60–79
  static const Color scoreMixed = warningDeep;   // 40–59

  // ── FIXED neutral scrims (overlays over media — always neutral) ─────────
  static const Color scrim = Color(0x40000000);
  static const Color scrimStrong = Color(0x66000000);
  static const Color scrimSoft = Color(0x1F000000);
  static const Color inkVeil = Color(0x0A072946); // faint navy wash
  static const Color navyMid = Color(0xFF0D3D60); // mid navy for dark headers
  static const Color navyShadow = Color(0x26072946); // soft navy drop-shadow

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
  // FIXED brand-teal consts (kept const for identity/entry screens that must
  // stay teal). For anything that should FOLLOW the accent, use primary /
  // primaryLight / primaryDark / primaryLight2 directly — not these.
  static const Color tealBrand = Color(0xFF059669);
  static const Color tealBright = Color(0xFF34D399);
  static const Color tealDark = Color(0xFF047857);
  static const Color tealLight = Color(0xFF10B981);
  static const Color tealPale = Color(0xFFECFDF5);
  static const Color violet = Color(0xFF8B5CF6);
  static const Color yellowPale = Color(0xFFFEF08A);
}
