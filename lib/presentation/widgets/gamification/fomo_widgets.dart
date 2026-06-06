import 'dart:async';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/gamification_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

// ─── Collapsible FOMO Badge Base ─────────────────────────────────────────────
class CollapsibleFomoBadge extends StatefulWidget {
  final Widget icon;
  final Widget text;
  final Color backgroundColor;
  final List<Color>? gradientColors;
  final List<BoxShadow>? boxShadow;
  final BoxBorder? border;

  const CollapsibleFomoBadge({
    super.key,
    required this.icon,
    required this.text,
    required this.backgroundColor,
    this.gradientColors,
    this.boxShadow,
    this.border,
  });

  @override
  State<CollapsibleFomoBadge> createState() => _CollapsibleFomoBadgeState();
}

class _CollapsibleFomoBadgeState extends State<CollapsibleFomoBadge> {
  bool _isExpanded = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted) {
        setState(() {
          _isExpanded = false;
        });
      }
    });
  }

  void _toggle() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _startTimer();
      } else {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggle,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
        height: 28,
        padding: EdgeInsets.symmetric(
          horizontal: _isExpanded ? 10 : 6,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          color: widget.gradientColors == null ? widget.backgroundColor : null,
          gradient: widget.gradientColors != null
              ? LinearGradient(
                  colors: widget.gradientColors!,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          borderRadius: BorderRadius.circular(14),
          border: widget.border,
          boxShadow: widget.boxShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            widget.icon,
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: ClipRect(
                child: _isExpanded
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(width: 5),
                          widget.text,
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Animated Icons ─────────────────────────────────────────────────────────

class AnimatedEyeIcon extends StatefulWidget {
  const AnimatedEyeIcon({super.key});

  @override
  State<AnimatedEyeIcon> createState() => _AnimatedEyeIconState();
}

class _AnimatedEyeIconState extends State<AnimatedEyeIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.6 + (_controller.value * 0.4),
          child: const Icon(
            IconsaxPlusLinear.eye,
            color: Colors.white,
            size: 14,
          ),
        );
      },
    );
  }
}

class HeartbeatIcon extends StatefulWidget {
  const HeartbeatIcon({super.key});

  @override
  State<HeartbeatIcon> createState() => _HeartbeatIconState();
}

class _HeartbeatIconState extends State<HeartbeatIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.25), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.25, end: 1.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 55),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: const Icon(
        IconsaxPlusLinear.heart,
        color: Colors.white,
        size: 14,
      ),
    );
  }
}

class SparkleIcon extends StatelessWidget {
  const SparkleIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return const Icon(
      IconsaxPlusLinear.flash_1,
      color: Colors.white,
      size: 14,
    );
  }
}

// ─── Live Viewers Pill ────────────────────────────────────────────────────────
// Shown on swipe card: "5 מסתכלים עכשיו"

class LiveViewersPill extends StatelessWidget {
  const LiveViewersPill({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return CollapsibleFomoBadge(
      icon: const AnimatedEyeIcon(),
      text: Text(
        count == 1 ? 'מסתכל עכשיו' : '$count מסתכלים עכשיו',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: Colors.black.withValues(alpha: 0.55),
    );
  }
}

// ─── Hot Property Badge ───────────────────────────────────────────────────────
// "🔥 מבוקשת" badge on card top-left

class HotPropertyBadge extends StatelessWidget {
  const HotPropertyBadge({super.key, required this.likesCount});
  final int likesCount;

  @override
  Widget build(BuildContext context) {
    return CollapsibleFomoBadge(
      icon: const HeartbeatIcon(),
      text: Text(
        '$likesCount אהבו היום',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      backgroundColor: const Color(0xFFFF5A67),
      gradientColors: const [Color(0xFFFF5A67), Color(0xFFFF8C42)],
      boxShadow: [
        BoxShadow(
          color: const Color(0xFFFF5A67).withValues(alpha: 0.4),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }
}

// ─── New Property Badge ───────────────────────────────────────────────────────

class NewPropertyBadge extends StatelessWidget {
  const NewPropertyBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return CollapsibleFomoBadge(
      icon: const SparkleIcon(),
      text: const Text(
        'חדש · היה מהראשונים',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
      backgroundColor: AppColors.primary,
      boxShadow: [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.4),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }
}

// ─── Match Expiry Timer ───────────────────────────────────────────────────────
// Used in matches_screen on each match card

class MatchExpiryTimer extends StatefulWidget {
  const MatchExpiryTimer({super.key, required this.match});
  final RentalMatch match;

  @override
  State<MatchExpiryTimer> createState() => _MatchExpiryTimerState();
}

class _MatchExpiryTimerState extends State<MatchExpiryTimer> {
  late Timer _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = GamificationService.matchTimeRemaining(widget.match);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining = GamificationService.matchTimeRemaining(widget.match);
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final expiringSoon = GamificationService.isMatchExpiringSoon(widget.match);
    final label = GamificationService.formatMatchCountdown(_remaining);
    final color = expiringSoon ? AppColors.coral : AppColors.textSecondary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          expiringSoon ? Icons.timer_off_outlined : Icons.timer_outlined,
          size: 13,
          color: color,
        ),
        const SizedBox(width: 3),
        Text(
          expiringSoon ? '⚠ פג תוקף בעוד $label' : 'פג תוקף בעוד $label',
          style: TextStyle(
            fontSize: 11,
            fontWeight: expiringSoon ? FontWeight.w700 : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ─── Super Like Countdown (when exhausted) ────────────────────────────────────

class SuperLikeResetTimer extends StatefulWidget {
  const SuperLikeResetTimer({super.key});

  @override
  State<SuperLikeResetTimer> createState() => _SuperLikeResetTimerState();
}

class _SuperLikeResetTimerState extends State<SuperLikeResetTimer> {
  late Timer _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = GamificationService.timeUntilSuperLikeReset();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(
          () => _remaining = GamificationService.timeUntilSuperLikeReset());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF4A6CF7).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF4A6CF7).withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        GamificationService.formatSuperLikeReset(_remaining),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Color(0xFF4A6CF7),
        ),
      ),
    );
  }
}

// ─── FOMO Card Overlay — all badges combined ──────────────────────────────────
// Drop this anywhere inside a property card Stack

class FomoCardOverlay extends StatelessWidget {
  const FomoCardOverlay({
    super.key,
    required this.property,
    required this.likedIds,
  });

  final RentalProperty property;
  final Set<String> likedIds;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DatingProvider>();
    final isGuest = provider.isGuestMode;
    final properties = provider.filteredProperties;
    final isFirst = isGuest && properties.isNotEmpty && property.id == properties.first.id;
    final isSecond = isGuest && properties.length > 1 && property.id == properties[1].id;

    final viewers = isFirst
        ? 245
        : isSecond
            ? 3
            : property.marketSignals.liveViewers;

    final likes = isFirst
        ? 84
        : isSecond
            ? 47
            : property.marketSignals.likesTodayFor(DateTime.now());

    final isNew = isSecond ? true : (isFirst ? false : property.isNewListing);

    if (!isNew && viewers == 0 && likes == 0) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: [
        Positioned(
          top: 92,
          left: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isNew) ...[
                const NewPropertyBadge(),
                const SizedBox(height: 6),
              ],
              if (likes > 0) ...[
                HotPropertyBadge(likesCount: likes),
                const SizedBox(height: 6),
              ],
              if (viewers > 0) LiveViewersPill(count: viewers),
            ],
          ),
        ),
      ],
    );
  }
}
