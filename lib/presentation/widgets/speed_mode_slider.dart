import 'package:dating_app/core/constants/app_colors.dart';
import 'package:flutter/material.dart';
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

/// A compact two-segment slider: **🎯 מותאם אישית ↔ ⚡ מהיר**. The selected
/// segment slides under an animated accent pill.
class SpeedModeSlider extends StatelessWidget {
  const SpeedModeSlider({
    super.key,
    required this.immediate,
    required this.onChanged,
    this.width = 208,
  });

  /// true = fast/immediate mode; false = personalization mode.
  final bool immediate;
  final ValueChanged<bool> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    const h = 34.0;
    // Self-contained (opaque) so it looks IDENTICAL on the light chat and the
    // dark voice screen.
    const base = Color(0xFFECECF3);
    final idle = AppColors.textSecondary;
    return SizedBox(
      width: width,
      height: h,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(h / 2),
              ),
            ),
            // Sliding accent pill — right segment (RTL) is "מותאם", left is "מהיר".
            AnimatedAlign(
              alignment:
                  immediate ? Alignment.centerLeft : Alignment.centerRight,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: Container(
                width: width / 2,
                height: h,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(h / 2),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.35),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                _seg('🎯 מותאם אישית', !immediate, idle, () => onChanged(false)),
                _seg('⚡ מהיר', immediate, idle, () => onChanged(true)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _seg(String label, bool selected, Color idle, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : idle,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
