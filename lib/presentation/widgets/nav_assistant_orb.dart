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

    // Dark base disc so the gaps read like the rest of the navbar.
    canvas.drawCircle(
      center,
      s / 2,
      Paint()..color = const Color(0xFF141625),
    );

    for (var i = 0; i < 3; i++) {
      final phase = i * (tau / 3);
      // Drift: the blob centre wanders on a slow Lissajous path inside the disc.
      final drift = s * 0.17;
      final bx = center.dx +
          drift * math.cos(tau * t + phase) * 0.9;
      final by = center.dy +
          drift * math.sin(tau * t * 0.8 + phase * 1.3);
      final bc = Offset(bx, by);

      // Pulse: grow/shrink gently (≈ one breath every ~8s).
      final pulse = 0.5 + 0.5 * math.sin(tau * t * 3 + phase);
      final radius = s * (0.30 + 0.12 * pulse);

      // Hue drifts slowly around its base so colours keep shifting.
      final hue = (_baseHues[i] + t * 70) % 360;
      final color = HSVColor.fromAHSV(1, hue, 0.72, 1.0).toColor();

      final paint = Paint()
        ..blendMode = BlendMode.screen // additive glow where blobs overlap
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.06)
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0.0)],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: bc, radius: radius));
      canvas.drawCircle(bc, radius, paint);
    }

    // A soft inner rim so the disc still reads as a glassy sphere.
    canvas.drawCircle(
      center,
      s / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.04
        ..color = Colors.white.withValues(alpha: 0.10),
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.t != t;
}
