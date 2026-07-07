import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The assistant orb that lives in אתי's nav circle: a FIXED-size dark disc with
/// three soft colour blobs that drift, pulse (grow/shrink) and shift hue slowly
/// inside it. The orb itself never resizes — only the blobs move.
class NavAssistantOrb extends StatefulWidget {
  const NavAssistantOrb({super.key, required this.size});

  final double size;

  @override
  State<NavAssistantOrb> createState() => _NavAssistantOrbState();
}

class _NavAssistantOrbState extends State<NavAssistantOrb>
    with SingleTickerProviderStateMixin {
  // A long period → the motion is gentle, never frantic.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => CustomPaint(
              painter: _OrbPainter(_c.value),
              size: Size.square(widget.size),
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.t);

  /// 0..1 progress that loops.
  final double t;

  // Base hues for the three blobs (teal / violet / pink), each drifts over time.
  static const _baseHues = [180.0, 275.0, 330.0];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final center = Offset(s / 2, s / 2);
    final tau = 2 * math.pi;

    final disc = Rect.fromCircle(center: center, radius: s / 2);

    // Dark sphere base (a subtle radial so it reads as a ball, not a flat disc).
    canvas.drawCircle(
      center,
      s / 2,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF3B3F63), Color(0xFF14162A)],
          stops: [0.0, 1.0],
        ).createShader(disc),
    );

    // Blobs are drawn additively INSIDE a clipped layer, so overlaps glow and
    // nothing spills past the sphere. (Drawing straight to the canvas with a
    // blend mode + no layer rendered nothing — this is the fix.)
    canvas.save();
    canvas.clipPath(Path()..addOval(disc));
    canvas.saveLayer(disc, Paint());
    for (var i = 0; i < 3; i++) {
      final phase = i * (tau / 3);
      // Drift: the blob centre wanders on a slow Lissajous path inside the disc.
      final drift = s * 0.19;
      final bc = Offset(
        center.dx + drift * math.cos(tau * t + phase) * 0.9,
        center.dy + drift * math.sin(tau * t * 0.8 + phase * 1.3),
      );

      // Pulse: grow/shrink gently.
      final pulse = 0.5 + 0.5 * math.sin(tau * t * 3 + phase);
      final radius = s * (0.36 + 0.13 * pulse);

      // Hue drifts slowly around its base so colours keep shifting.
      final hue = (_baseHues[i] + t * 70) % 360;
      final color = HSVColor.fromAHSV(1, hue, 0.85, 1.0).toColor();

      canvas.drawCircle(
        bc,
        radius,
        Paint()
          ..blendMode = BlendMode.plus
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.05)
          ..shader = RadialGradient(
            colors: [color, color.withValues(alpha: 0.0)],
            stops: const [0.0, 1.0],
          ).createShader(Rect.fromCircle(center: bc, radius: radius)),
      );
    }
    canvas.restore(); // saveLayer
    canvas.restore(); // clip

    // A soft inner rim so the disc still reads as a glassy sphere.
    canvas.drawCircle(
      center,
      s / 2 - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.035
        ..color = Colors.white.withValues(alpha: 0.14),
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.t != t;
}
