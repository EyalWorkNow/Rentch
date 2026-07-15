import 'dart:ui';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/ui/platform_fx.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/animations/micro_animations.dart';

// Order: ✕ X (left) | 3D Tour (center) | ♥ Heart (right, largest)
class ActionButtons extends StatelessWidget {
  const ActionButtons({
    super.key,
    required this.onSwipeLeft,
    required this.onSwipeRight,
    required this.onVirtualTour,
  });

  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;
  final VoidCallback onVirtualTour;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 56),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ♥ Heart — like (right in RTL, matches swipe right direction)
          PulseRing(
            ringColor: AppColors.primary,
            maxRadius: 10.0,
            active: true,
            child: _ActionButton(
              icon: IconsaxPlusBold.heart,
              tooltip: 'אהבתי דירה',
              iconColor: AppColors.primary,
              backgroundColor: Colors.white,
              size: 72,
              iconSize: 34,
              onPressed: () {
                HapticFeedback.mediumImpact();
                onSwipeRight();
              },
              shadowColor: AppColors.primary,
            ),
          ),

          // 3D Tour (center)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ActionButton(
                icon: Icons.view_in_ar_rounded,
                tooltip: 'פתח סיור תלת־ממדי',
                iconColor: const Color(0xFF072946),
                backgroundColor: Colors.white,
                size: 56,
                iconSize: 26,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  onVirtualTour();
                },
                shadowColor: const Color(0xFF072946),
              ),
              const SizedBox(height: 6),
              Text(
                '3D',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Colors.white.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),

          // ✕ X — pass (left in RTL, matches swipe left direction)
          _ActionButton(
            icon: Icons.close_rounded,
            tooltip: 'דלג על דירה',
            iconColor: AppColors.coral,
            backgroundColor: Colors.white,
            size: 62,
            iconSize: 30,
            onPressed: () {
              HapticFeedback.lightImpact();
              onSwipeLeft();
            },
            shadowColor: AppColors.coral,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.icon,
    required this.tooltip,
    required this.iconColor,
    required this.backgroundColor,
    required this.size,
    required this.iconSize,
    required this.onPressed,
    this.shadowColor,
  });

  final IconData icon;
  final String tooltip;
  final Color iconColor;
  final Color backgroundColor;
  final double size;
  final double iconSize;
  final VoidCallback? onPressed;
  final Color? shadowColor;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark3d = widget.iconColor == const Color(0xFF072946);
    final actualIconColor = isDark3d ? Colors.white : widget.iconColor;

    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) async {
          await _ctrl.reverse();
          widget.onPressed?.call();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: (widget.shadowColor ?? Colors.black)
                      .withValues(alpha: 0.16),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipOval(
              child: BackdropFilter(
                // Very heavy glass blur. Routed through PlatformFx so iOS gets
                // the full heavy look while Android/Impeller (where this sits
                // over the animating deck) is trimmed enough to stay smooth.
                filter: ImageFilter.blur(
                    sigmaX: PlatformFx.blurSigma(34),
                    sigmaY: PlatformFx.blurSigma(34)),
                child: Container(
                  decoration: BoxDecoration(
                    // Dark GRAY (not black), with relative transparency so the
                    // heavy blur reads as frosted glass.
                    color: const Color(0xFF2C2C2E).withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Icon(
                      widget.icon,
                      size: widget.iconSize,
                      color: actualIconColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
