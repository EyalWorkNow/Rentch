import 'dart:math';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/gamification_service.dart';
import 'package:flutter/material.dart';

class TrustScoreBadge extends StatelessWidget {
  const TrustScoreBadge({super.key, required this.score});

  final int score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(48, 48),
                  painter: _ArcPainter(score: score),
                ),
                Text(
                  '$score',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: _scoreColor(score),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ציון דייר',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                GamificationService.trustScoreLabel(score),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _scoreColor(score),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _scoreColor(int s) {
    if (s >= 80) return AppColors.success;
    if (s >= 60) return AppColors.primary;
    if (s >= 40) return AppColors.warning;
    return AppColors.coral;
  }
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter({required this.score});
  final int score;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 4;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r);

    final trackPaint = Paint()
      ..color = AppColors.borderLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    final arcPaint = Paint()
      ..color = _color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    const startAngle = -pi * 0.8;
    const sweepTotal = pi * 1.6;

    canvas.drawArc(rect, startAngle, sweepTotal, false, trackPaint);
    canvas.drawArc(rect, startAngle, sweepTotal * (score / 100), false, arcPaint);
  }

  Color get _color {
    if (score >= 80) return AppColors.success;
    if (score >= 60) return AppColors.primary;
    if (score >= 40) return AppColors.warning;
    return AppColors.coral;
  }

  @override
  bool shouldRepaint(_ArcPainter old) => old.score != score;
}
