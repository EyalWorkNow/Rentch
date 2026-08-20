import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Ultra-Modern Rounded 4-point AI Sparkle Stars icon (Google Gemini / Apple Intelligence style).
/// Features rounded tips, no border stroke, animated shifting multicolor gradient fill inside
/// the stars, and a dynamic glowing aura.
class AiSparkleAnimatedIcon extends StatefulWidget {
  const AiSparkleAnimatedIcon({
    super.key,
    this.size = 34.0,
    this.isSelected = false,
  });

  final double size;
  final bool isSelected;

  @override
  State<AiSparkleAnimatedIcon> createState() => _AiSparkleAnimatedIconState();
}

class _AiSparkleAnimatedIconState extends State<AiSparkleAnimatedIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
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
        final progress = _controller.value;
        // Non-stop smooth breathing scale
        final pulse = 1.0 + 0.08 * math.sin(progress * 2 * math.pi);
        // Non-stop subtle rotation sway
        final rotation = 0.06 * math.sin(progress * 2 * math.pi);

        return Transform.rotate(
          angle: rotation,
          child: Transform.scale(
            scale: widget.isSelected ? pulse * 1.16 : pulse,
            child: CustomPaint(
              size: Size(widget.size, widget.size),
              painter: _AiSparklePainter(
                progress: progress,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AiSparklePainter extends CustomPainter {
  _AiSparklePainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;

    // Shifting neon color spectrum cycling endlessly inside the star
    final colors = const [
      Color(0xFF818CF8), // Electric Indigo
      Color(0xFFC084FC), // Neon Purple
      Color(0xFFF472B6), // Hot Pink
      Color(0xFF38BDF8), // Electric Cyan
      Color(0xFF34D399), // Emerald
      Color(0xFFFBBF24), // Amber Gold
      Color(0xFF818CF8), // Loop back
    ];

    final rect = Rect.fromLTWH(0, 0, w, h);

    // Rotating sweep gradient applied directly INSIDE the star fill & glow
    final starGradient = SweepGradient(
      center: Alignment.center,
      startAngle: 0,
      endAngle: math.pi * 2,
      colors: colors,
      transform: GradientRotation(progress * math.pi * 2),
    );

    // Orbital 3D drop-shadow motion offset
    final double shadowDx = math.cos(progress * 2 * math.pi * 1.5) * 2.5;
    final double shadowDy = math.sin(progress * 2 * math.pi * 1.5) * 2.5;
    final Offset shadowOffset = Offset(shadowDx, shadowDy);

    // 1. Soft wide outer drop shadow glow
    final outerGlowPaint = Paint()
      ..shader = starGradient.createShader(rect)
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.32);

    // 2. Crisp focused inner drop shadow glow
    final innerGlowPaint = Paint()
      ..shader = starGradient.createShader(rect)
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.16);

    // 3. Shifting multi-color gradient fill INSIDE the star (NO STROKE!)
    final starFillPaint = Paint()
      ..shader = starGradient.createShader(rect)
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Main 4-point Sparkle Star (Top-Left, prominent size, rounded corners)
    final bigCenter = Offset(w * 0.38, h * 0.38);
    final bigRadius = w * 0.42;
    final bigStarPath = _draw4PointSparkleRounded(bigCenter, bigRadius);

    // Medium 4-point Sparkle Star (Bottom-Right, breathing micro-pulse, rounded corners)
    final mediumPulse = 1.0 + 0.15 * math.sin((progress + 0.25) * math.pi * 4);
    final mediumCenter = Offset(w * 0.74, h * 0.72);
    final mediumRadius = w * 0.21 * mediumPulse;
    final mediumStarPath = _draw4PointSparkleRounded(mediumCenter, mediumRadius);

    // Tiny 3rd Sparkle Star (Top-Right, async twinkle, rounded corners)
    final tinyTwinkle = (0.5 + 0.5 * math.sin((progress + 0.6) * math.pi * 6)).clamp(0.4, 1.1);
    final tinyCenter = Offset(w * 0.76, h * 0.26);
    final tinyRadius = w * 0.11 * tinyTwinkle;
    final tinyStarPath = _draw4PointSparkleRounded(tinyCenter, tinyRadius);

    final combinedPath = Path()
      ..addPath(bigStarPath, Offset.zero)
      ..addPath(mediumStarPath, Offset.zero)
      ..addPath(tinyStarPath, Offset.zero);

    // Draw orbiting outer drop-shadow glow (layer 1)
    canvas.save();
    canvas.translate(shadowOffset.dx, shadowOffset.dy);
    canvas.drawPath(combinedPath, outerGlowPaint);
    canvas.restore();

    // Draw orbiting inner drop-shadow glow (layer 2)
    canvas.save();
    canvas.translate(shadowOffset.dx * 0.5, shadowOffset.dy * 0.5);
    canvas.drawPath(combinedPath, innerGlowPaint);
    canvas.restore();

    // Draw multi-color animated gradient star fill (NO STROKE!)
    canvas.drawPath(combinedPath, starFillPaint);
  }

  /// Draws a 4-pointed sparkle star with smoothly rounded tips
  Path _draw4PointSparkleRounded(Offset center, double radius) {
    final Path path = Path();
    final double cx = center.dx;
    final double cy = center.dy;

    // Corner rounding factor (~12% of radius for soft modern tips)
    final double cr = radius * 0.14;

    // Tip points & approach points
    // Top tip
    final topApproachLeft = Offset(cx - cr, cy - radius + cr);
    final topTip = Offset(cx, cy - radius);
    final topApproachRight = Offset(cx + cr, cy - radius + cr);

    // Right tip
    final rightApproachTop = Offset(cx + radius - cr, cy - cr);
    final rightTip = Offset(cx + radius, cy);
    final rightApproachBottom = Offset(cx + radius - cr, cy + cr);

    // Bottom tip
    final bottomApproachRight = Offset(cx + cr, cy + radius - cr);
    final bottomTip = Offset(cx, cy + radius);
    final bottomApproachLeft = Offset(cx - cr, cy + radius - cr);

    // Left tip
    final leftApproachBottom = Offset(cx - radius + cr, cy + cr);
    final leftTip = Offset(cx - radius, cy);
    final leftApproachTop = Offset(cx - radius + cr, cy - cr);

    // Build path with rounded tip arcs and concave side curves
    path.moveTo(topApproachRight.dx, topApproachRight.dy);

    // Curve to Right tip approach
    path.quadraticBezierTo(cx, cy, rightApproachTop.dx, rightApproachTop.dy);
    // Rounded Right tip
    path.quadraticBezierTo(rightTip.dx, rightTip.dy, rightApproachBottom.dx, rightApproachBottom.dy);

    // Curve to Bottom tip approach
    path.quadraticBezierTo(cx, cy, bottomApproachRight.dx, bottomApproachRight.dy);
    // Rounded Bottom tip
    path.quadraticBezierTo(bottomTip.dx, bottomTip.dy, bottomApproachLeft.dx, bottomApproachLeft.dy);

    // Curve to Left tip approach
    path.quadraticBezierTo(cx, cy, leftApproachBottom.dx, leftApproachBottom.dy);
    // Rounded Left tip
    path.quadraticBezierTo(leftTip.dx, leftTip.dy, leftApproachTop.dx, leftApproachTop.dy);

    // Curve to Top tip approach
    path.quadraticBezierTo(cx, cy, topApproachLeft.dx, topApproachLeft.dy);
    // Rounded Top tip
    path.quadraticBezierTo(topTip.dx, topTip.dy, topApproachRight.dx, topApproachRight.dy);

    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _AiSparklePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Animated Gradient Ring for the AI Button Container in the Navbar
class AiNavCircleDecoration extends StatefulWidget {
  const AiNavCircleDecoration({
    super.key,
    required this.child,
    required this.isSelected,
    required this.size,
  });

  final Widget child;
  final bool isSelected;
  final double size;

  @override
  State<AiNavCircleDecoration> createState() => _AiNavCircleDecorationState();
}

class _AiNavCircleDecorationState extends State<AiNavCircleDecoration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
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
        final progress = _controller.value;
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _AiCircleBorderPainter(
            progress: progress,
            isSelected: widget.isSelected,
          ),
          child: widget.child,
        );
      },
    );
  }
}

class _AiCircleBorderPainter extends CustomPainter {
  _AiCircleBorderPainter({required this.progress, required this.isSelected});

  final double progress;
  final bool isSelected;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final colors = const [
      Color(0xFF6366F1), // Indigo
      Color(0xFFA855F7), // Purple
      Color(0xFFEC4899), // Pink
      Color(0xFF38BDF8), // Sky Blue
      Color(0xFF6366F1), // Loop back
    ];

    final gradient = SweepGradient(
      center: Alignment.center,
      startAngle: 0,
      endAngle: math.pi * 2,
      colors: colors,
      transform: GradientRotation(progress * math.pi * 2),
    );

    final rect = Rect.fromCircle(center: center, radius: radius);

    if (isSelected) {
      final glowPaint = Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0);
      canvas.drawCircle(center, radius - 1.5, glowPaint);
    }

    final borderPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelected ? 2.2 : 1.8;

    canvas.drawCircle(center, radius - 1.0, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _AiCircleBorderPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isSelected != isSelected;
  }
}
