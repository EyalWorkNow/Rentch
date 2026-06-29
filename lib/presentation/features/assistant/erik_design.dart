import 'package:dating_app/core/constants/app_colors.dart';
import 'package:flutter/material.dart';

/// ───────────────────────────────────────────────────────────────────────────
/// Erik design system — the single source of truth for the "אריק" assistant.
///
/// This is a deliberately small, cohesive token layer so the whole feature
/// (text chat + the premium voice-call) feels like one designed object. Spacing,
/// radii, the type scale, motion, surfaces and glows all live here.
///
/// THE ACCENT IS NEVER HARD-CODED. It always flows from [AppColors] (which is
/// auto-black for brokers and teal for everyone else). For that reason every
/// accent token is a getter — never `const` a widget that reads one.
/// ───────────────────────────────────────────────────────────────────────────
class ErikTokens {
  ErikTokens._();

  // ── Canvas (the calm "night" surface Erik lives on) ──────────────────────
  static const Color bgDeep = Color(0xFF041C2F); // deepest navy
  static const Color bgMid = Color(0xFF0B2F4D); // lifted navy (centre glow)
  static const Color bgVeil = Color(0xFF072946); // sheet/veil navy

  // ── Ink ──────────────────────────────────────────────────────────────────
  static const Color ink = Colors.white; // primary text on dark
  static const Color inkSoft = Color(0xFFE6EEF6); // softened body copy
  static const Color navyText = Color(0xFF072946); // dark text on light surfaces
  static const Color muted = Color(0xFFA6BDD2); // secondary text
  static const Color faint = Color(0xFF7E9BB6); // tertiary / hints

  // ── Surfaces (glassmorphism) ───────────────────────────────────────────────
  static const Color assistantSurface = Color(0x1A5AD4DC);
  static const Color panel = Color(0x140E3358);
  static const Color card = Color(0x14FFFFFF);
  static const Color glassHi = Color(0x1AFFFFFF);
  static const Color glassLo = Color(0x0AFFFFFF);
  static const Color line = Color(0x24FFFFFF);
  static const Color lineStrong = Color(0x3DFFFFFF);

  // ── Status colours ─────────────────────────────────────────────────────────
  static const Color online = Color(0xFF4ADE80);
  static const Color danger = Color(0xFFE5484D);

  // ── Accent — ALWAYS from AppColors (getters, never const) ──────────────────
  static Color get accent => AppColors.primary;
  static Color get accentGlow => AppColors.primaryLight;
  static Color get userSurface => AppColors.primary;
  static List<Color> get accentSweep => [AppColors.primaryLight, AppColors.primary];

  // ── Spacing scale (4-based) ────────────────────────────────────────────────
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s7 = 28;
  static const double s8 = 32;

  // ── Radii ──────────────────────────────────────────────────────────────────
  static const double rSm = 12;
  static const double rMd = 16;
  static const double rLg = 20;
  static const double rXl = 26;
  static const double rPill = 999;

  // ── Motion — durations & curves (one vocabulary for the feature) ───────────
  static const Duration mFast = Duration(milliseconds: 200);
  static const Duration mBase = Duration(milliseconds: 320);
  static const Duration mSlow = Duration(milliseconds: 460);
  static const Duration mEnter = Duration(milliseconds: 540);
  static const Duration mBreath = Duration(milliseconds: 2600);
  static const Curve easeOut = Curves.easeOutCubic;
  static const Curve emphasized = Curves.easeOutBack;
  static const Curve spring = Curves.easeOutBack;

  // ── Type scale (large & legible — older landlords & agents) ────────────────
  static const TextStyle display = TextStyle(
    color: ink,
    fontSize: 31,
    height: 1.12,
    fontWeight: FontWeight.w900,
    letterSpacing: 0.2,
  );
  static const TextStyle title = TextStyle(
    color: ink,
    fontSize: 21,
    fontWeight: FontWeight.w900,
    letterSpacing: 0.2,
  );
  static const TextStyle heading = TextStyle(
    color: ink,
    fontSize: 16.5,
    fontWeight: FontWeight.w900,
    height: 1.2,
  );
  static const TextStyle body = TextStyle(
    color: inkSoft,
    fontSize: 17.5,
    height: 1.58,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle bodyMuted = TextStyle(
    color: muted,
    fontSize: 16,
    height: 1.6,
    fontWeight: FontWeight.w600,
  );
  static const TextStyle label = TextStyle(
    color: ink,
    fontSize: 15,
    fontWeight: FontWeight.w800,
  );
  static const TextStyle caption = TextStyle(
    color: muted,
    fontSize: 12.5,
    fontWeight: FontWeight.w700,
  );

  // ── Reusable decorations ───────────────────────────────────────────────────

  /// Soft glass card / panel.
  static BoxDecoration glass({
    double radius = rLg,
    Color? border,
    bool elevated = false,
  }) {
    return BoxDecoration(
      color: card,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border ?? line),
      boxShadow: elevated
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ]
          : null,
    );
  }

  /// Accent-tinted glow shadow (used on active controls / the live header).
  static List<BoxShadow> accentShadow({double opacity = 0.30, double blur = 26}) {
    return [
      BoxShadow(
        color: accent.withValues(alpha: opacity),
        blurRadius: blur,
        offset: const Offset(0, 10),
      ),
    ];
  }
}

/// A soft circular brand glow used in the ambient background and behind the orb.
class ErikAmbientGlow extends StatelessWidget {
  const ErikAmbientGlow({super.key, required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, Colors.transparent]),
      ),
    );
  }
}

/// One-shot fade + slide-up entrance, shared across bubbles, cards and the
/// voice-call surfaces so everything enters with the same gentle motion.
class ErikFadeInUp extends StatefulWidget {
  const ErikFadeInUp({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 16,
  });
  final Widget child;
  final Duration delay;
  final double offset;

  @override
  State<ErikFadeInUp> createState() => _ErikFadeInUpState();
}

class _ErikFadeInUpState extends State<ErikFadeInUp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: ErikTokens.mEnter);
  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: ErikTokens.easeOut);

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      builder: (context, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _a.value) * widget.offset),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
