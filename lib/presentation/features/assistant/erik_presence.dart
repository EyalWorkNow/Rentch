import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The four expressive states of Erik's presence. The screen derives one of
/// these from its real state (mic on, TTS speaking, live partial, processing).
enum ErikState { idle, listening, thinking, speaking }

/// ───────────────────────────────────────────────────────────────────────────
/// Erik PRESENCE — the emotional heart of the assistant.
///
/// A clean, premium "AI voice orb": a soft luminous sphere built from a smooth
/// radial-gradient core, layered translucent glow halos, a glossy highlight and
/// elegant gentle motion. Audio-reactive via [soundLevel]. Pure Canvas, app
/// palette (accent passed in so it always honours AppColors — teal or black).
///
/// States read clearly:
///   • idle      — slow calm breathing (gentle scale + soft glow pulse).
///   • listening — audio-reactive concentric ripples + the core scaling to the
///                 voice; warm and energized.
///   • thinking  — a smooth sweeping highlight rotating around the orb.
///   • speaking  — a rhythmic, confident pulse.
///
/// One widget drives every appearance of Erik: the header mark, the welcome
/// hero, and the big call orb — only [size] and [state] change.
/// ───────────────────────────────────────────────────────────────────────────
class ErikPresence extends StatefulWidget {
  const ErikPresence({
    super.key,
    required this.size,
    required this.state,
    required this.accent,
    required this.accentGlow,
    this.soundLevel,
    this.showRing = true,
  });

  final double size;
  final ErikState state;
  final Color accent;
  final Color accentGlow;

  /// Smoothed/raw mic amplitude notifier (-2..10-ish range, like speech_to_text).
  final ValueListenable<double>? soundLevel;

  /// The rotating energy ring (off for the tiny header mark).
  final bool showRing;

  @override
  State<ErikPresence> createState() => _ErikPresenceState();
}

class _ErikPresenceState extends State<ErikPresence>
    with TickerProviderStateMixin {
  // Long, seamless morph loop that is always running.
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
  )..repeat();

  // A faster loop used for the ring rotation and speaking shimmer.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  )..repeat();

  double _level = 0.0;

  @override
  void dispose() {
    _morph.dispose();
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The blob lives inside a larger field so its glow/ring aren't clipped.
    final field = widget.size * 1.85;
    final notifier = widget.soundLevel ?? const _Zero();
    return SizedBox(
      width: field,
      height: field,
      child: ValueListenableBuilder<double>(
        valueListenable: notifier,
        builder: (context, raw, _) {
          final target = ((raw + 2.0) / 12.0).clamp(0.0, 1.0);
          // Snap up fast on sound, ease down slowly — reactive yet smooth.
          final k = target > _level ? 0.5 : 0.12;
          _level += (target - _level) * k;
          return AnimatedBuilder(
            animation: Listenable.merge([_morph, _spin]),
            builder: (context, _) {
              return CustomPaint(
                size: Size(field, field),
                painter: _PresencePainter(
                  t: _morph.value,
                  spin: _spin.value,
                  level: _level,
                  state: widget.state,
                  accent: widget.accent,
                  accentGlow: widget.accentGlow,
                  showRing: widget.showRing,
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _Zero extends ValueListenable<double> {
  const _Zero();
  @override
  double get value => 0.0;
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}

class _PresencePainter extends CustomPainter {
  _PresencePainter({
    required this.t,
    required this.spin,
    required this.level,
    required this.state,
    required this.accent,
    required this.accentGlow,
    required this.showRing,
  });

  final double t; // 0..1 seamless breathing loop
  final double spin; // 0..1 seamless rotation loop
  final double level; // 0..1 smoothed audio amplitude
  final ErikState state;
  final Color accent;
  final Color accentGlow;
  final bool showRing;

  // A single warm spark used to inject life into the highlight; the orb's hue
  // is otherwise driven entirely by the passed-in accent (teal or black).
  static const _spark = Color(0xFFFFFFFF);
  static const _warm = Color(0xFFFFC9A3);

  bool get _listening => state == ErikState.listening;
  bool get _speaking => state == ErikState.speaking;
  bool get _thinking => state == ErikState.thinking;
  bool get _active => state != ErikState.idle;

  static const double _tau = 2 * math.pi;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final s = size.shortestSide;
    final base = s * 0.27;

    // ── Breathing & state-driven scale. Always alive, never jittery. ──
    final breath = math.sin(t * _tau); // -1..1 calm sine
    double scale = 1.0 + 0.035 * breath; // idle: gentle breathing

    if (_listening) {
      // The sphere swells toward the voice — energized and responsive.
      scale += 0.06 + level * 0.22;
    } else if (_speaking) {
      // A confident rhythmic pulse, a touch faster than the breath clock.
      final beat = math.sin(t * _tau * 3).abs();
      scale += 0.05 + 0.10 * beat + level * 0.10;
    } else if (_thinking) {
      // Calm and steady — motion comes from the sweeping shimmer, not scale.
      scale += 0.02 * math.sin(t * _tau * 1.5);
    }

    final r = base * scale;

    // ── Warm shift while listening to invite speech (subtle). ──
    final warmth = _listening ? (0.18 + level * 0.22).clamp(0.0, 0.4) : 0.0;
    Color tint(Color x) => Color.lerp(x, _warm, warmth)!;
    final acc = tint(accent);
    final accG = tint(accentGlow);

    // 1 ── Outer bloom halo — soft, wide, breathes with the state. ──
    final haloAlpha = (_active ? 0.26 : 0.16) + level * 0.18 +
        (_speaking ? 0.06 * math.sin(t * _tau * 3).abs() : 0.0);
    final haloR = r * 2.4;
    canvas.drawCircle(
      c,
      haloR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            accG.withValues(alpha: haloAlpha.clamp(0.0, 0.6)),
            acc.withValues(alpha: haloAlpha.clamp(0.0, 0.6) * 0.45),
            Colors.transparent,
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: haloR))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 24),
    );

    // 2 ── Listening ripples — concentric rings expanding outward from the orb.
    if (_listening) {
      _paintRipples(canvas, c, r, accG);
    }

    // 3 ── Mid glow ring (bloom) hugging the sphere for a luminous edge. ──
    final midR = r * 1.5;
    canvas.drawCircle(
      c,
      midR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.transparent,
            accG.withValues(alpha: 0.20 + level * 0.18),
            Colors.transparent,
          ],
          stops: const [0.55, 0.78, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: midR))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // 4 ── The sphere body — a smooth radial-gradient core, lit from upper-left
    // so it reads as a real 3-D ball. ──
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 1.1,
          colors: [
            Color.lerp(accG, _spark, 0.55)!,
            accG,
            acc,
            Color.lerp(acc, Colors.black, 0.55)!,
          ],
          stops: const [0.0, 0.32, 0.66, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // 5 ── Inner core light — a soft luminous heart that pulses. ──
    final corePulse = _speaking
        ? 0.55 + 0.45 * math.sin(t * _tau * 3).abs()
        : 0.5 + 0.5 * (0.5 + 0.5 * breath);
    final coreC = Offset(c.dx - r * 0.12, c.dy - r * 0.14);
    canvas.drawCircle(
      coreC,
      r * 0.72,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            _spark.withValues(
                alpha: (0.22 + 0.30 * corePulse + level * 0.25).clamp(0.0, 0.8)),
            accG.withValues(alpha: 0.10),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: coreC, radius: r * 0.72))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // 6 ── Thinking shimmer — a smooth sweeping band of light rotating around
    // the sphere. Clipped to the body so it reads as a surface sweep. ──
    if (_thinking) {
      _paintShimmer(canvas, c, r);
    }

    // 7 ── Glossy specular highlight — a small soft white catch-light. ──
    final hl = Offset(c.dx - r * 0.34, c.dy - r * 0.40);
    canvas.drawCircle(
      hl,
      r * 0.30,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _spark.withValues(alpha: 0.85),
            _spark.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: hl, radius: r * 0.30))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    // A faint secondary rim light on the lower-right for roundness.
    final rim = Offset(c.dx + r * 0.42, c.dy + r * 0.46);
    canvas.drawCircle(
      rim,
      r * 0.5,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            accG.withValues(alpha: 0.18),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: rim, radius: r * 0.5))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    // 8 ── A thin luminous orbit ring (skipped for the tiny header mark). ──
    if (showRing) {
      final ringR = r * 1.16;
      canvas.drawCircle(
        c,
        ringR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * (0.018 + level * 0.02)
          ..color = accG.withValues(
              alpha: (_active ? 0.4 : 0.22) + level * 0.2)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  /// Listening: concentric ripples that expand outward and fade — driven by the
  /// rotation clock so multiple rings are always in flight.
  void _paintRipples(Canvas canvas, Offset c, double r, Color color) {
    const rings = 3;
    final energy = (0.35 + level * 0.65).clamp(0.0, 1.0);
    for (var i = 0; i < rings; i++) {
      final phase = (spin + i / rings) % 1.0; // 0..1 expanding
      final rr = r * (1.0 + phase * (0.7 + level * 0.6));
      final fade = (1.0 - phase) * energy;
      if (fade <= 0.01) continue;
      canvas.drawCircle(
        c,
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.04 * (1.0 - phase * 0.5)
          ..color = color.withValues(alpha: (fade * 0.5).clamp(0.0, 0.5))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
    }
  }

  /// Thinking: a soft sweeping highlight that rotates around the sphere,
  /// clipped to the body so it looks like light gliding over a surface.
  void _paintShimmer(Canvas canvas, Offset c, double r) {
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));
    final rot = spin * _tau;
    final rect = Rect.fromCircle(center: c, radius: r * 1.1);
    canvas.drawCircle(
      c,
      r * 1.1,
      Paint()
        ..shader = SweepGradient(
          transform: GradientRotation(rot),
          colors: [
            Colors.transparent,
            _spark.withValues(alpha: 0.0),
            _spark.withValues(alpha: 0.30),
            _spark.withValues(alpha: 0.0),
            Colors.transparent,
          ],
          stops: const [0.0, 0.30, 0.42, 0.54, 1.0],
        ).createShader(rect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PresencePainter old) =>
      old.t != t ||
      old.spin != spin ||
      old.level != level ||
      old.state != state ||
      old.accent != accent ||
      old.accentGlow != accentGlow ||
      old.showRing != showRing;
}

/// A live, audio-reactive waveform bar visualizer used in the voice-call view.
/// Symmetric "spindle" envelope, driven by the same morph clock + mic level so
/// it feels alive even before audio arrives.
class ErikWaveform extends StatelessWidget {
  const ErikWaveform({
    super.key,
    required this.t,
    required this.level,
    required this.active,
    required this.color,
    this.bars = 42,
    this.height = 56,
    this.idleColor,
  });

  final double t; // 0..1 clock
  final double level; // 0..1 amplitude
  final bool active;
  final Color color;
  final Color? idleColor;
  final int bars;
  final double height;

  @override
  Widget build(BuildContext context) {
    final idle = idleColor ?? color.withValues(alpha: 0.30);
    return SizedBox(
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(bars, (index) {
          final mid = (bars - 1) / 2;
          final dist = (index - mid).abs() / mid;
          final envelope = 1 - dist * dist; // taller in the middle
          final phase = (t + index * 0.045) % 1;
          final wave = 0.3 + 0.7 * math.sin(phase * math.pi).abs();
          final amp = active ? (0.35 + level * 0.65) : 0.18;
          final h = 4 + height * 0.9 * wave * envelope * amp;
          return Container(
            width: 3,
            height: h,
            margin: const EdgeInsets.symmetric(horizontal: 1.8),
            decoration: BoxDecoration(
              color: (active ? color : idle)
                  .withValues(alpha: active ? 0.85 : 0.4),
              borderRadius: BorderRadius.circular(99),
            ),
          );
        }),
      ),
    );
  }
}
