import 'dart:math' as math;
import 'package:dating_app/core/ui/platform_fx.dart';
import 'dart:ui';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared "מהיר ↔ מותאם אישית" speed mode, persisted so the chat and the voice
/// screen stay in sync.
///
/// - immediate = true  → purely on-device (SmartSearch + the 40 inference rules +
///   local ranking). Nothing waits on the network/LLM.
/// - immediate = false → the full personalisation pipeline (LLM enrich +
///   community-fit cohort + warm reply) runs in the background and refines.
class SpeedMode {
  static const prefKey = 'etti_immediate_mode';

  /// The single source of truth, so the chat and the voice screen stay in sync
  /// live (toggle in one → reflected in the other immediately).
  static final ValueNotifier<bool> immediate = ValueNotifier<bool>(false);

  static Future<void> init() async {
    try {
      immediate.value =
          (await SharedPreferences.getInstance()).getBool(prefKey) ?? false;
    } catch (_) {}
  }

  static Future<void> set(bool v) async {
    immediate.value = v;
    try {
      await (await SharedPreferences.getInstance()).setBool(prefKey, v);
    } catch (_) {}
  }
}

/// A two-segment slider — **🎯 מותאם אישית ↔ ⚡ מהיר** — styled IDENTICALLY to the
/// discover "גלה" pill selector (glass pill, sliding gradient thumb, iconsax icons).
class SpeedModeSlider extends StatelessWidget {
  SpeedModeSlider({
    super.key,
    required this.immediate,
    required this.onChanged,
    this.width = 300,
    this.darkGlass = false,
  });

  /// true = fast/immediate mode; false = personalization mode.
  final bool immediate;
  final ValueChanged<bool> onChanged;
  final double width;
  final bool darkGlass;

  @override
  Widget build(BuildContext context) {
    const h = 52.0;
    const pad = 5.0;
    final inner = math.max(0.0, width - pad * 2);
    final half = inner / 2;
    // Visual order left→right: [מותאם אישית, מהיר]. Thumb over the selected half.
    final thumbLeft = immediate ? half : 0.0;

    return SizedBox(
      width: width,
      height: h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: darkGlass
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.12),
                    Colors.white.withValues(alpha: 0.04),
                    Colors.white.withValues(alpha: 0.08),
                  ],
                )
              : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withValues(alpha: 0.96),
                    AppColors.primaryLight2.withValues(alpha: 0.94),
                    AppColors.slate50.withValues(alpha: 0.98),
                  ],
                ),
          border: Border.all(
            color: darkGlass
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.78),
            width: darkGlass ? 1.2 : 1.4,
          ),
          boxShadow: darkGlass
              ? []
              : [
                  BoxShadow(
                    color: AppColors.navy.withValues(alpha: 0.10),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.14),
                    blurRadius: 18,
                    offset: const Offset(0, 5),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(14), sigmaY: PlatformFx.blurSigma(14)),
            child: Padding(
              padding: const EdgeInsets.all(pad),
              child: Directionality(
                textDirection: TextDirection.ltr,
                // Clip the sliding thumb's glow to the pill (Android/Impeller
                // doesn't contain child shadows via an ancestor ClipRRect over a
                // BackdropFilter — same fix as the discover _PillSelector).
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      left: thumbLeft,
                      width: half,
                      top: 0,
                      bottom: 0,
                      child: _SpeedThumb(),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _seg(
                            icon: IconsaxPlusBold.magicpen,
                            label: 'מותאם אישית',
                            selected: !immediate,
                            onTap: () => onChanged(false),
                            darkGlass: darkGlass,
                          ),
                        ),
                        Expanded(
                          child: _seg(
                            icon: IconsaxPlusBold.flash,
                            label: 'מהיר',
                            selected: immediate,
                            onTap: () => onChanged(true),
                            darkGlass: darkGlass,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _seg({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required bool darkGlass,
  }) {
    final inactiveColor = darkGlass
        ? Colors.white.withValues(alpha: 0.45)
        : AppColors.textSecondary.withValues(alpha: 0.84);
    final selectedShadow = [
      Shadow(
        color: AppColors.navy.withValues(alpha: 0.22),
        offset: const Offset(0, 1),
        blurRadius: 5,
      ),
    ];
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          scale: selected ? 1.03 : 1,
          // Inset so the label+icon stay INSIDE the coloured thumb on Android too.
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: selected ? Colors.white : inactiveColor,
                    shadows: selected ? selectedShadow : null,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
                      color: selected ? Colors.white : inactiveColor,
                      shadows: selected ? selectedShadow : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
        ),
      ),
    );
  }
}

class _SpeedThumb extends StatelessWidget {
  _SpeedThumb();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(23),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          // Accent-driven so the whole track re-tints when the theme accent swaps
          // (was a fixed cyan→teal→blue gradient that half-ignored the theme).
          colors: [AppColors.primaryLight, AppColors.primary, AppColors.primaryDark],
          stops: const [0, 0.52, 1],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.30), width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 13,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(23),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.30),
                    Colors.white.withValues(alpha: 0.05),
                    Colors.black.withValues(alpha: 0.07),
                  ],
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 6,
            start: 12,
            width: 38,
            height: 14,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.48),
                    Colors.white.withValues(alpha: 0.02),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
