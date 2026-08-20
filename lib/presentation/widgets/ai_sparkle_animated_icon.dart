import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Ultra-Premium Animated 4-point AI Sparkle Stars icon (Google Gemini / Apple Intelligence style).
/// Features 3 crisp solid white 4-point sparkle stars with a subtle dark background stroke,
/// an orbital multi-color glowing drop shadow, and dynamic shimmer motion.
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

    // Rich vibrant neon color spectrum cycling endlessly
    final colors = const [
      Color(0xFF6366F1), // Electric Indigo
      Color(0xFFA855F7), // Neon Purple
      Color(0xFFEC4899), // Hot Magenta
      Color(0xFF38BDF8), // Electric Cyan
      Color(0xFF10B981), // Emerald
      Color(0xFFF59E0B), // Amber Gold
      Color(0xFF6366F1), // Loop back
    ];

    final rect = Rect.fromLTWH(-w * 0.3, -h * 0.3, w * 1.6, h * 1.6);

    // Rotating sweep gradient for the glowing drop shadow
    final glowGradient = SweepGradient(
      center: Alignment.center,
      startAngle: 0,
      endAngle: math.pi * 2,
      colors: colors,
      transform: GradientRotation(progress * math.pi * 2),
    );

    // Orbital 3D drop-shadow motion offset
    final double shadowDx = math.cos(progress * 2 * math.pi * 1.5) * 3.2;
    final double shadowDy = math.sin(progress * 2 * math.pi * 1.5) * 3.2;
    final Offset shadowOffset = Offset(shadowDx, shadowDy);

    // 1. Soft wide outer drop shadow glow
    final outerGlowPaint = Paint()
      ..shader = glowGradient.createShader(rect)
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.35);

    // 2. Crisp focused inner drop shadow glow
    final innerGlowPaint = Paint()
      ..shader = glowGradient.createShader(rect)
      ..style = PaintingStyle.fill
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.18);

    // 3. Dark background stroke paint (creates crisp border around white stars)
    final bgStrokePaint = Paint()
      ..color = const Color(0xFF0B0F19)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // 4. Pure solid white star fill paint
    final whiteFillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Main 4-point Sparkle Star (Top-Left, prominent size)
    final bigCenter = Offset(w * 0.38, h * 0.38);
    final bigRadius = w * 0.42;
    final bigStarPath = _draw4PointSparkle(bigCenter, bigRadius);

    // Medium 4-point Sparkle Star (Bottom-Right, breathing micro-pulse)
    final mediumPulse = 1.0 + 0.15 * math.sin((progress + 0.25) * math.pi * 4);
    final mediumCenter = Offset(w * 0.74, h * 0.72);
    final mediumRadius = w * 0.21 * mediumPulse;
    final mediumStarPath = _draw4PointSparkle(mediumCenter, mediumRadius);

    // Tiny 3rd Sparkle Star (Top-Right, async twinkle)
    final tinyTwinkle = (0.5 + 0.5 * math.sin((progress + 0.6) * math.pi * 6)).clamp(0.4, 1.1);
    final tinyCenter = Offset(w * 0.76, h * 0.26);
    final tinyRadius = w * 0.11 * tinyTwinkle;
    final tinyStarPath = _draw4PointSparkle(tinyCenter, tinyRadius);

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

    // Draw dark background stroke around the stars
    canvas.drawPath(combinedPath, bgStrokePaint);

    // Draw solid white stars on top
    canvas.drawPath(combinedPath, whiteFillPaint);
  }

  Path _draw4PointSparkle(Offset center, double radius) {
    final Path path = Path();
    final double cx = center.dx;
    final double cy = center.dy;

    final top = Offset(cx, cy - radius);
    final right = Offset(cx + radius, cy);
    final bottom = Offset(cx, cy + radius);
    final left = Offset(cx - radius, cy);

    path.moveTo(top.dx, top.dy);
    path.quadraticBezierTo(cx, cy, right.dx, right.dy);
    path.quadraticBezierTo(cx, cy, bottom.dx, bottom.dy);
    path.quadraticBezierTo(cx, cy, left.dx, left.dy);
    path.quadraticBezierTo(cx, cy, top.dx, top.dy);
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
