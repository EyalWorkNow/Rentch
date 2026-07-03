import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Shared liquid-glass orb — the AI presence for both אתי (tenant search) and
/// אריק (landlord). A frosted glass dome with heavy-blurred colour balls beneath
/// it (refraction / dispersion / frost / depth via `shaders/liquid_glass.frag`).
/// Self-contained: loads the shader, drives its own clock, clips to the circle.
///
/// [level] (0..1) is the speaking/activity intensity → ball size / speed / colour.
class LiquidGlassOrb extends StatefulWidget {
  const LiquidGlassOrb({
    super.key,
    this.size = 175,
    this.level = 0.3,
    this.speaking = false,
  });

  final double size;
  final double level;

  /// While the agent is SPEAKING, the orb pulses with a speech-like envelope
  /// (colours + size change with the voice) instead of using a static [level].
  final bool speaking;

  @override
  State<LiquidGlassOrb> createState() => _LiquidGlassOrbState();
}

class _LiquidGlassOrbState extends State<LiquidGlassOrb>
    with SingleTickerProviderStateMixin {
  final ValueNotifier<double> _clock = ValueNotifier(0);
  late final Ticker _ticker;
  ui.FragmentShader? _glass;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((el) => _clock.value = el.inMicroseconds / 1e6)
      ..start();
    _load();
  }

  Future<void> _load() async {
    try {
      final prog =
          await ui.FragmentProgram.fromAsset('shaders/liquid_glass.frag');
      if (mounted) setState(() => _glass = prog.fragmentShader());
    } catch (_) {
      // keep the painted fallback
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    _glass?.dispose();
    super.dispose();
  }

  // Lively, non-uniform envelope that reads like speech cadence (layered sines).
  double _speechEnvelope(double t) {
    final e = 0.6 +
        0.24 * math.sin(t * 7.0) +
        0.12 * math.sin(t * 13.0 + 1.3) +
        0.08 * math.sin(t * 19.0 + 2.1);
    return e.clamp(0.35, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: _glass != null
          ? ValueListenableBuilder<double>(
              valueListenable: _clock,
              builder: (_, t, __) => CustomPaint(
                painter: _LiquidGlassPainter(
                    shader: _glass!,
                    time: t,
                    level: widget.speaking ? _speechEnvelope(t) : widget.level),
              ),
            )
          : ValueListenableBuilder<double>(
              valueListenable: _clock,
              builder: (_, t, __) =>
                  CustomPaint(painter: _FallbackOrbPainter(t: t)),
            ),
    );
  }
}

// Feeds the GLSL shader its uniforms each frame.
class _LiquidGlassPainter extends CustomPainter {
  _LiquidGlassPainter({
    required this.shader,
    required this.time,
    required this.level,
  });

  final ui.FragmentShader shader;
  final double time;
  final double level;

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time)
      ..setFloat(3, level.clamp(0.0, 1.0));
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_LiquidGlassPainter old) =>
      old.time != time || old.level != level;
}

// Painted fallback for platforms where the fragment shader can't load: a soft
// frosted disc with a few blurred colour lobes.
class _FallbackOrbPainter extends CustomPainter {
  _FallbackOrbPainter({required this.t});
  final double t;
  static const _cols = [
    Color(0xFF17C7D1),
    Color(0xFF6675FF),
    Color(0xFFFF6B85),
    Color(0xFFFFC957),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2;
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    canvas.drawCircle(
        c, r, Paint()..color = const Color(0x3323404A)); // #23404A @ 20%
    for (int i = 0; i < 4; i++) {
      final a = t * 0.3 + i * 1.57;
      final pos = c + Offset(0.35 * r * (i.isEven ? 1 : -1) * 0.6, 0) +
          Offset(0.28 * r * (i / 3 - 0.5), 0.28 * r * ((i % 2) - 0.5));
      canvas.drawCircle(
        pos,
        r * 0.5,
        Paint()
          ..color = _cols[i].withValues(alpha: 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 26),
      );
      // reference `a` so the fallback drifts subtly
      canvas.translate(0.001 * a, 0);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FallbackOrbPainter old) => old.t != t;
}
