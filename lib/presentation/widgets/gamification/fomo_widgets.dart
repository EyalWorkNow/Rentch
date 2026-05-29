import 'dart:async';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/gamification_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter/material.dart';

// ─── Live Viewers Pill ────────────────────────────────────────────────────────
// Shown on swipe card: "5 מסתכלים עכשיו"

class LiveViewersPill extends StatefulWidget {
  const LiveViewersPill({super.key, required this.count});
  final int count;

  @override
  State<LiveViewersPill> createState() => _LiveViewersPillState();
}

class _LiveViewersPillState extends State<LiveViewersPill>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _opacity = Tween(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: _opacity,
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Color(0xFF27AE60),
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '${widget.count} מסתכלים עכשיו',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF5A67), Color(0xFFFF8C42)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF5A67).withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🔥', style: TextStyle(fontSize: 11)),
          const SizedBox(width: 3),
          Text(
            '$likesCount אהבו היום',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── New Property Badge ───────────────────────────────────────────────────────

class NewPropertyBadge extends StatelessWidget {
  const NewPropertyBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Text(
        '✨ חדש — היה מהראשונים',
        style: TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
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
    final isHot = GamificationService.isHotProperty(property, likedIds);
    final isNew = GamificationService.isNewProperty(property);
    final viewers = GamificationService.simulateLiveViewers(property);
    final likes = GamificationService.simulateLikesCount(property);

    return Stack(
      children: [
        // Below the top icon row (agency badge + dots + save button ends ~50px)
        Positioned(
          top: 62,
          left: 12,
          child: isNew
              ? const NewPropertyBadge()
              : isHot
                  ? HotPropertyBadge(likesCount: likes)
                  : const SizedBox.shrink(),
        ),
        // Live viewers counter — below the badge when shown
        Positioned(
          top: (isNew || isHot) ? 94 : 62,
          left: 12,
          child: LiveViewersPill(count: viewers),
        ),
      ],
    );
  }
}
