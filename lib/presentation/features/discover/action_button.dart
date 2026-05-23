import 'package:dating_app/core/constants/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

// Order: ♥ Heart (left, largest) | ★ Star (center) | ✕ X (right)
class ActionButtons extends StatelessWidget {
  const ActionButtons({
    super.key,
    required this.onSwipeLeft,
    required this.onSwipeRight,
    required this.onSuperLike,
  });

  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;
  final VoidCallback onSuperLike;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ♥ Heart — like (left, largest)
          _ActionButton(
            icon: IconsaxPlusBold.heart,
            tooltip: 'אהבתי דירה',
            iconColor: Colors.white,
            backgroundColor: AppColors.primary,
            size: 72,
            iconSize: 30,
            onPressed: () {
              HapticFeedback.mediumImpact();
              onSwipeRight();
            },
            shadowColor: AppColors.primary,
          ),
          // ★ Star — super like (center)
          _ActionButton(
            icon: IconsaxPlusBold.star_1,
            tooltip: 'סופר לייק',
            iconColor: Colors.white,
            backgroundColor: const Color(0xFF4A6CF7),
            size: 56,
            iconSize: 24,
            onPressed: () {
              HapticFeedback.lightImpact();
              onSuperLike();
            },
            shadowColor: const Color(0xFF4A6CF7),
          ),
          // ✕ X — pass (right)
          _ActionButton(
            icon: IconsaxPlusBold.close_circle,
            tooltip: 'דלג על דירה',
            iconColor: Colors.white,
            backgroundColor: AppColors.coral,
            size: 62,
            iconSize: 26,
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
              color: widget.backgroundColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color:
                      (widget.shadowColor ?? widget.backgroundColor).withValues(alpha: 0.38),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(widget.icon, size: widget.iconSize, color: widget.iconColor),
          ),
        ),
      ),
    );
  }
}
