import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The four expressive states of Erik's presence. The screen derives one of
/// these from its real state (mic on, TTS speaking, live partial, processing).
enum ErikState { idle, listening, thinking, speaking }

/// ───────────────────────────────────────────────────────────────────────────
/// Erik PRESENCE — the emotional heart of the assistant.
///
/// A living "AI orb": an asymmetric blob that constantly loses its shape — far
/// more when it hears or speaks — rendered as a flowing field of dots
/// (phyllotaxis) that deform with the surface, lit from within, wrapped by a
/// slowly rotating energy ring. Audio-reactive via [soundLevel]. Pure Canvas,
/// app palette (accent passed in so it always honours AppColors).
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

  final double t; // 0..1 seamless morph loop
  final double spin; // 0..1 seamless ring loop
  final double level; // 0..1 smoothed audio amplitude
  final ErikState state;
  final Color accent;
  final Color accentGlow;
  final bool showRing;

  // Cool palette for the dot field's depth gradient.
  static const _bright = Color(0xFFB8FBFF);
  static const _blue = Color(0xFF4A6CF7);
  static const _coral = Color(0xFFFF5A67);
  static const _deep = Color(0xFF06303A);

  bool get _listening => state == ErikState.listening;
  bool get _speaking => state == ErikState.speaking;
  bool get _thinking => state == ErikState.thinking;
  bool get _active => state != ErikState.idle;

  static const int _dotCount = 150;
  static final List<_PolarDot> _dots = _build();
  static List<_PolarDot> _build() {
    final out = <_PolarDot>[];
    const golden = 2.399963229; // golden angle (rad)
    for (var i = 0; i < _dotCount; i++) {
      final rho = math.sqrt(i / _dotCount) * 1.14;
      out.add(_PolarDot(golden * i, rho, (i * 53) % 100 / 100.0));
    }
    return out;
  }

  double get _tau => 2 * math.pi;

  // Multi-harmonic organic noise → big asymmetric lobes. Seamless over t∈[0,1].
  double _noise(double a) {
    final p = t * _tau;
    return 0.50 * math.sin(2 * a + p) +
        0.34 * math.sin(3 * a - 2 * p + 1.3) +
        0.22 * math.sin(5 * a + 3 * p + 0.5) +
        0.14 * math.sin(7 * a - p * 1.5 + 0.6);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final s = size.shortestSide;
    final base = s * 0.26;

    // It is ALWAYS morphing; state drives it harder so the orb visibly reacts.
    double deform = 0.16 + 0.05 * math.sin(t * _tau * 1.5);
    if (_thinking) deform += 0.05 + 0.04 * math.sin(t * _tau * 4).abs();
    if (_speaking) deform += 0.14 * (0.4 + 0.6 * math.sin(t * _tau * 5).abs());
    if (_listening) deform += 0.16 + level * 0.6;
    deform += level * 0.35;

    // Warm-shift toward coral while listening to a voice — invites speech.
    final warm = _listening ? (0.4 + level * 0.4).clamp(0.0, 0.85) : 0.0;
    Color mix(Color x) => Color.lerp(x, _coral, warm)!;

    final breathe = 1 + 0.05 * math.sin(t * _tau) + level * 0.12;
    final baseR = base * breathe;

    double blobR(double a) => baseR * (1 + deform * _noise(a));

    // 1 ── Ambient glow.
    final glowR = baseR * 2.2;
    canvas.drawCircle(
      c,
      glowR,
      Paint()
        ..shader = RadialGradient(
          colors: [
            mix(accent).withValues(alpha: (_active ? 0.30 : 0.16) + level * 0.20),
            mix(_blue).withValues(alpha: 0.08),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: glowR))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );

    // 2 ── Rotating energy ring — a thin orbit of light that speeds up with the
    // conversation. Skipped for the small header mark.
    if (showRing) {
      _paintRing(canvas, c, baseR, mix);
    }

    // 3 ── Soft luminous body under the dots (follows the morph).
    final bodyPath = _blobPath(c, blobR);
    canvas.drawPath(
      bodyPath,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.25, -0.3),
          colors: [
            mix(accentGlow).withValues(alpha: 0.55),
            mix(accent).withValues(alpha: 0.40),
            _deep.withValues(alpha: 0.55),
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: baseR * 1.2))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    // 4 ── The dot field — texture that flows with the surface.
    final dotPaint = Paint();
    for (final d in _dots) {
      final r = d.rho * blobR(d.angle);
      final pos = Offset(
        c.dx + r * math.cos(d.angle),
        c.dy + r * math.sin(d.angle),
      );
      final Color col = d.rho < 0.5
          ? Color.lerp(_bright, accent, d.rho * 2)!
          : Color.lerp(accent, _blue, ((d.rho - 0.5) / 0.64).clamp(0.0, 1.0))!;
      final twinkle = 0.65 + 0.35 * math.sin(t * _tau * 3 + d.seed * _tau);
      final edgeFade = d.rho > 1.0 ? (1.15 - d.rho) / 0.15 : 1.0;
      final op =
          ((1.0 - d.rho * 0.45) * twinkle * edgeFade * (_active ? 1.0 : 0.85))
              .clamp(0.0, 1.0);
      final dotR = s * 0.0095 * (1.15 - 0.45 * d.rho) * (1 + level * 0.25);
      dotPaint.color = mix(col).withValues(alpha: op);
      canvas.drawCircle(pos, math.max(0.4, dotR), dotPaint);
    }

    // 5 ── Inner light — a soft pulsing glow from the core (lights the dots).
    final pulse = 0.5 +
        0.5 * math.sin(t * _tau * (_speaking ? 5 : 2)).abs() +
        level * 0.4;
    final lc = Offset(c.dx - baseR * 0.1, c.dy - baseR * 0.12);
    canvas.drawCircle(
      lc,
      baseR * 0.7,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            _bright.withValues(alpha: (0.30 + 0.32 * pulse).clamp(0.0, 0.75)),
            mix(accent).withValues(alpha: 0.10),
            Colors.transparent,
          ],
        ).createShader(Rect.fromCircle(center: lc, radius: baseR * 0.7))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
    );
  }

  /// A thin, luminous orbit. Its sweep direction & speed read the state:
  /// idle = slow drift, thinking = a single chasing comet, listening/speaking =
  /// a brighter full ring that breathes with [level].
  void _paintRing(Canvas canvas, Offset c, double baseR, Color Function(Color) mix) {
    final ringR = baseR * 1.32;
    final rot = spin * _tau * (_thinking ? 2.4 : 1.0);
    final rect = Rect.fromCircle(center: c, radius: ringR);

    if (_thinking) {
      // A chasing comet arc — Erik is working.
      final sweep = _tau * 0.32;
      canvas.drawArc(
        rect,
        rot,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = baseR * 0.07
          ..shader = SweepGradient(
            startAngle: rot,
            endAngle: rot + sweep,
            colors: [Colors.transparent, mix(accentGlow).withValues(alpha: 0.9)],
          ).createShader(rect)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      return;
    }

    // Full breathing ring; brighter & thicker when active.
    final activeBoost = _active ? (0.55 + level * 0.35) : 0.22;
    canvas.drawCircle(
      c,
      ringR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = baseR * (0.045 + level * 0.03)
        ..color = mix(accentGlow).withValues(alpha: activeBoost.clamp(0.0, 0.85))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, _active ? 4 : 2),
    );
    // A bright travelling highlight along the ring.
    final hx = c.dx + ringR * math.cos(rot);
    final hy = c.dy + ringR * math.sin(rot);
    canvas.drawCircle(
      Offset(hx, hy),
      baseR * (0.10 + level * 0.05),
      Paint()
        ..color = _bright.withValues(alpha: _active ? 0.85 : 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  Path _blobPath(Offset c, double Function(double a) radius) {
    const n = 96;
    final pts = List<Offset>.generate(n, (i) {
      final a = (i / n) * _tau;
      final r = radius(a);
      return Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a));
    });
    final path = Path();
    final start = Offset(
        (pts[0].dx + pts[n - 1].dx) / 2, (pts[0].dy + pts[n - 1].dy) / 2);
    path.moveTo(start.dx, start.dy);
    for (var i = 0; i < n; i++) {
      final cur = pts[i];
      final next = pts[(i + 1) % n];
      path.quadraticBezierTo(
          cur.dx, cur.dy, (cur.dx + next.dx) / 2, (cur.dy + next.dy) / 2);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _PresencePainter old) =>
      old.t != t ||
      old.spin != spin ||
      old.level != level ||
      old.state != state ||
      old.accent != accent ||
      old.showRing != showRing;
}

class _PolarDot {
  const _PolarDot(this.angle, this.rho, this.seed);
  final double angle;
  final double rho;
  final double seed;
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
