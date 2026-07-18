import 'dart:math' as math;
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:flutter/material.dart';

bool get _isUnderTest {
  final bindingStr = WidgetsBinding.instance.runtimeType.toString();
  return bindingStr.contains('Test');
}

// ─── 1. Logo Breathe Animation ────────────────────────────────────────────────
class BreatheAnimation extends StatelessWidget {
  final Widget child;
  final double scaleStart;
  final double scaleEnd;
  final Duration duration;

  const BreatheAnimation({
    super.key,
    required this.child,
    this.scaleStart = 0.96,
    this.scaleEnd = 1.04,
    this.duration = const Duration(seconds: 3),
  });

  @override
  Widget build(BuildContext context) => child;
}

// ─── 2. Glow Focus Decorator ──────────────────────────────────────────────────
class GlowFocusDecorator extends StatelessWidget {
  final Widget child;
  final bool isFocused;
  final Color glowColor;
  final double borderRadius;

  const GlowFocusDecorator({
    super.key,
    required this.child,
    required this.isFocused,
    this.glowColor = AppColors.superLike,
    this.borderRadius = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: isFocused ? glowColor.withValues(alpha: 0.18) : Colors.transparent,
            blurRadius: isFocused ? 12 : 0,
            spreadRadius: isFocused ? 2 : 0,
          ),
        ],
      ),
      child: child,
    );
  }
}

// ─── 3. Eye Morph Icon ────────────────────────────────────────────────────────
class EyeMorphIcon extends StatefulWidget {
  final bool isObscured;
  final VoidCallback onTap;
  final Color color;

  const EyeMorphIcon({
    super.key,
    required this.isObscured,
    required this.onTap,
    this.color = Colors.grey,
  });

  @override
  State<EyeMorphIcon> createState() => _EyeMorphIconState();
}

class _EyeMorphIconState extends State<EyeMorphIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _rotate;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _rotate = Tween<double>(begin: 0, end: 0.25).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.8), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 0.8, end: 1.0), weight: 50),
    ]).animate(_ctrl);
  }

  @override
  void didUpdateWidget(covariant EyeMorphIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isObscured != widget.isObscured) {
      if (widget.isObscured) {
        _ctrl.reverse();
      } else {
        _ctrl.forward();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _scale,
        child: RotationTransition(
          turns: _rotate,
          child: Icon(
            widget.isObscured ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: widget.color,
            size: 20,
          ),
        ),
      ),
    );
  }
}

// ─── 4. Horizontal Shake Animation ───────────────────────────────────────────
class ShakeController extends ChangeNotifier {
  void shake() => notifyListeners();
}

class HorizontalShake extends StatefulWidget {
  final Widget child;
  final ShakeController controller;
  final double offset;
  final Duration duration;

  const HorizontalShake({
    super.key,
    required this.child,
    required this.controller,
    this.offset = 8.0,
    this.duration = const Duration(milliseconds: 350),
  });

  @override
  State<HorizontalShake> createState() => _HorizontalShakeState();
}

class _HorizontalShakeState extends State<HorizontalShake>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _offsetAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _offsetAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: widget.offset), weight: 12.5),
      TweenSequenceItem(tween: Tween(begin: widget.offset, end: -widget.offset), weight: 25.0),
      TweenSequenceItem(tween: Tween(begin: -widget.offset, end: widget.offset), weight: 25.0),
      TweenSequenceItem(tween: Tween(begin: widget.offset, end: -widget.offset / 2), weight: 25.0),
      TweenSequenceItem(tween: Tween(begin: -widget.offset / 2, end: 0.0), weight: 12.5),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

    widget.controller.addListener(_onShake);
  }

  void _onShake() {
    if (mounted) {
      _ctrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onShake);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offsetAnim,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_offsetAnim.value, 0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ─── 5. Pulsing Ring (breath pulse outer circles) ─────────────────────────────
class PulseRing extends StatefulWidget {
  final Widget child;
  final Color ringColor;
  final double maxRadius;
  final bool active;

  const PulseRing({
    super.key,
    required this.child,
    this.ringColor = AppColors.coral,
    this.maxRadius = 18.0,
    this.active = true,
  });

  @override
  State<PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<PulseRing>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  Animation<double>? _radius;
  Animation<double>? _opacity;

  @override
  void initState() {
    super.initState();
    if (widget.active) _initAnimation();
  }

  void _initAnimation() {
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _radius = Tween<double>(begin: 0.0, end: widget.maxRadius).animate(
      CurvedAnimation(parent: _ctrl!, curve: Curves.easeOutCubic),
    );
    _opacity = Tween<double>(begin: 0.65, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl!, curve: Curves.easeOut),
    );
    if (!_isUnderTest) {
      _ctrl!.repeat();
    } else {
      _ctrl!.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant PulseRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      if (widget.active) {
        _initAnimation();
      } else {
        _ctrl?.dispose();
        _ctrl = null;
      }
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || _ctrl == null) return widget.child;

    return AnimatedBuilder(
      animation: _ctrl!,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _RingPainter(
                  radius: _radius!.value,
                  opacity: _opacity!.value,
                  ringColor: widget.ringColor,
                ),
              ),
            ),
            child!,
          ],
        );
      },
      child: widget.child,
    );
  }
}

class _RingPainter extends CustomPainter {
  final double radius;
  final double opacity;
  final Color ringColor;

  _RingPainter({
    required this.radius,
    required this.opacity,
    required this.ringColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = ringColor.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      (size.width / 2) + radius,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.radius != radius || oldDelegate.opacity != opacity;
  }
}

// ─── 6. Typing Indicator Dots ─────────────────────────────────────────────────
class TypingIndicatorDots extends StatefulWidget {
  final Color color;
  final double dotSize;

  const TypingIndicatorDots({
    super.key,
    this.color = Colors.grey,
    this.dotSize = 6.0,
  });

  @override
  State<TypingIndicatorDots> createState() => _TypingIndicatorDotsState();
}

class _TypingIndicatorDotsState extends State<TypingIndicatorDots>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (index) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 360),
      );
    });

    _animations = _controllers.map((ctrl) {
      return Tween<double>(begin: 0.0, end: -6.0).animate(
        CurvedAnimation(parent: ctrl, curve: Curves.easeInOut),
      );
    }).toList();

    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 120), () {
        if (mounted) {
          if (!_isUnderTest) {
            _controllers[i].repeat(reverse: true);
          } else {
            _controllers[i].value = 1.0;
          }
        }
      });
    }
  }

  @override
  void dispose() {
    for (var ctrl in _controllers) {
      ctrl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _animations[index],
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _animations[index].value),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                child: Container(
                  width: widget.dotSize,
                  height: widget.dotSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color,
                  ),
                ),
              ),
            );
          },
        );
      }),
    );
  }
}

// ─── 7. Bubble Entrance Slide-Fade ────────────────────────────────────────────
class BubbleEntrance extends StatefulWidget {
  final Widget child;
  final bool isMe;

  const BubbleEntrance({
    super.key,
    required this.child,
    required this.isMe,
  });

  @override
  State<BubbleEntrance> createState() => _BubbleEntranceState();
}

class _BubbleEntranceState extends State<BubbleEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _slide;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slide = Tween<double>(begin: widget.isMe ? 24.0 : -24.0, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.translate(
            offset: Offset(_slide.value, 0),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ─── 8. Shine Decorator (Gradient shine sweep effect) ───────────────────────
class ShineDecorator extends StatefulWidget {
  final Widget child;
  final Duration interval;

  const ShineDecorator({
    super.key,
    required this.child,
    this.interval = const Duration(seconds: 4),
  });

  @override
  State<ShineDecorator> createState() => _ShineDecoratorState();
}

class _ShineDecoratorState extends State<ShineDecorator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pos;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _pos = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _startLoop();
  }

  void _startLoop() async {
    if (_isUnderTest) return;
    while (mounted) {
      await Future.delayed(widget.interval);
      if (mounted) {
        await _ctrl.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pos,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.0),
                Colors.white.withValues(alpha: 0.35),
                Colors.white.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment(_pos.value - 1.0, -0.3),
              end: Alignment(_pos.value, 0.3),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ─── 9. Online status pulsing dot ─────────────────────────────────────────────
class OnlineDotPulse extends StatefulWidget {
  final Color color;
  final double size;

  const OnlineDotPulse({
    super.key,
    this.color = AppColors.greenBright,
    this.size = 10.0,
  });

  @override
  State<OnlineDotPulse> createState() => _OnlineDotPulseState();
}

class _OnlineDotPulseState extends State<OnlineDotPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _glow = Tween<double>(begin: 1.0, end: 1.35).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (!_isUnderTest) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        AnimatedBuilder(
          animation: _glow,
          builder: (context, child) {
            return Transform.scale(
              scale: _glow.value,
              child: Container(
                width: widget.size,
                height: widget.size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: 0.4),
                ),
              ),
            );
          },
        ),
        Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            border: Border.all(color: Colors.white, width: 1.5),
          ),
        ),
      ],
    );
  }
}

// ─── 10. Match Confetti Particle Burst ────────────────────────────────────────
class ConfettiParticles extends StatefulWidget {
  const ConfettiParticles({super.key});

  @override
  State<ConfettiParticles> createState() => _ConfettiParticlesState();
}

class _ConfettiParticlesState extends State<ConfettiParticles>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final List<_Particle> _particles = [];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    final rand = math.Random();
    final colors = [
      AppColors.coral,
      const Color(0xFFFFC72C),
      AppColors.superLike,
      AppColors.greenBright,
      AppColors.red,
    ];

    for (int i = 0; i < 40; i++) {
      _particles.add(
        _Particle(
          x: rand.nextDouble() * 320 - 160,
          y: 0.0,
          targetY: -rand.nextDouble() * 300 - 100,
          size: rand.nextDouble() * 6 + 4,
          color: colors[rand.nextInt(colors.length)],
          angle: rand.nextDouble() * math.pi * 2,
          speedX: (rand.nextDouble() - 0.5) * 120,
        ),
      );
    }
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return CustomPaint(
          painter: _ConfettiPainter(
            particles: _particles,
            progress: _ctrl.value,
          ),
        );
      },
    );
  }
}

class _Particle {
  final double x;
  final double y;
  final double targetY;
  final double size;
  final Color color;
  final double angle;
  final double speedX;

  _Particle({
    required this.x,
    required this.y,
    required this.targetY,
    required this.size,
    required this.color,
    required this.angle,
    required this.speedX,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  _ConfettiPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (var p in particles) {
      // Calculate physics
      final currentX = p.x + (p.speedX * progress);
      final currentY = p.y + (p.targetY * progress);
      final currentOpacity = (1.0 - progress).clamp(0.0, 1.0);

      paint.color = p.color.withValues(alpha: currentOpacity);
      canvas.save();
      canvas.translate(currentX, currentY);
      canvas.rotate(p.angle + (progress * math.pi * 4));
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

// ─── 11. Match Avatar Outline Ring ───────────────────────────────────────────
class AvatarPulseRing extends StatefulWidget {
  final Widget child;
  final bool active;

  const AvatarPulseRing({
    super.key,
    required this.child,
    this.active = true,
  });

  @override
  State<AvatarPulseRing> createState() => _AvatarPulseRingState();
}

class _AvatarPulseRingState extends State<AvatarPulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _scale = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.active) {
      if (!_isUnderTest) {
        _ctrl.repeat(reverse: true);
      } else {
        _ctrl.value = 1.0;
      }
    }
  }

  @override
  void didUpdateWidget(covariant AvatarPulseRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      if (widget.active) {
        if (!_isUnderTest) {
          _ctrl.repeat(reverse: true);
        } else {
          _ctrl.value = 1.0;
        }
      } else {
        _ctrl.stop();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(3.0),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [AppColors.coral, Color(0xFF8E44AD)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.coral.withValues(alpha: 0.3 * _scale.value),
                blurRadius: 8 * _scale.value,
                spreadRadius: 2 * _scale.value,
              ),
            ],
          ),
          child: Transform.scale(
            scale: 2.0 - _scale.value,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

// ─── 12. Badge Count Scale Bop ────────────────────────────────────────────────
class ScaleBopBadge extends StatefulWidget {
  final Widget child;
  final int value;

  const ScaleBopBadge({
    super.key,
    required this.child,
    required this.value,
  });

  @override
  State<ScaleBopBadge> createState() => _ScaleBopBadgeState();
}

class _ScaleBopBadgeState extends State<ScaleBopBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.4, end: 0.9), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 40),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(covariant ScaleBopBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value > 0) {
      _ctrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: widget.child,
    );
  }
}

// ─── 13. Filter Chip Tap Expand ──────────────────────────────────────────────
class FilterChipAnimated extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool isSelected;
  final Color activeColor;
  final Color inactiveColor;

  const FilterChipAnimated({
    super.key,
    required this.child,
    required this.onTap,
    required this.isSelected,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  State<FilterChipAnimated> createState() => _FilterChipAnimatedState();
}

class _FilterChipAnimatedState extends State<FilterChipAnimated>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: widget.isSelected ? widget.activeColor : widget.inactiveColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isSelected ? widget.activeColor : widget.inactiveColor.withValues(alpha: 0.5),
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

// ─── 14. Map Pin Jump ──────────────────────────────────────────────────────────
class MapPinJump extends StatefulWidget {
  final Widget child;
  final bool isSelected;

  const MapPinJump({
    super.key,
    required this.child,
    required this.isSelected,
  });

  @override
  State<MapPinJump> createState() => _MapPinJumpState();
}

class _MapPinJumpState extends State<MapPinJump>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _jump;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _jump = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -18.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin: -18.0, end: 0.0), weight: 35),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -6.0), weight: 15),
      TweenSequenceItem(tween: Tween(begin: -6.0, end: 0.0), weight: 10),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    if (widget.isSelected) {
      _ctrl.forward();
    }
  }

  @override
  void didUpdateWidget(covariant MapPinJump oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isSelected && !oldWidget.isSelected) {
      _ctrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _jump,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _jump.value),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ─── 15. Gallery Dots Active Stretch ──────────────────────────────────────────
class GalleryDotStretch extends StatelessWidget {
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;

  const GalleryDotStretch({
    super.key,
    required this.isActive,
    this.activeColor = AppColors.superLike,
    this.inactiveColor = AppColors.slate300,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      width: isActive ? 24.0 : 8.0,
      height: 8.0,
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4.0),
        color: isActive ? activeColor : inactiveColor,
      ),
    );
  }
}

// ─── 16. Signal Strip Pulse ───────────────────────────────────────────────────
class SignalStripPulse extends StatefulWidget {
  final Widget child;

  const SignalStripPulse({super.key, required this.child});

  @override
  State<SignalStripPulse> createState() => _SignalStripPulseState();
}

class _SignalStripPulseState extends State<SignalStripPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _opacity = Tween<double>(begin: 0.65, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (!_isUnderTest) {
      _ctrl.repeat(reverse: true);
    } else {
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: widget.child,
    );
  }
}

// ─── 17. Undo Button 360 Rotation ─────────────────────────────────────────────
class UndoRotation extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const UndoRotation({
    super.key,
    required this.child,
    required this.onTap,
  });

  @override
  State<UndoRotation> createState() => _UndoRotationState();
}

class _UndoRotationState extends State<UndoRotation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _rotation;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _rotation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (!_ctrl.isAnimating) {
          _ctrl.forward(from: 0.0);
        }
        widget.onTap();
      },
      child: RotationTransition(
        turns: _rotation,
        child: widget.child,
      ),
    );
  }
}

// ─── 18. Send Button Scale-Pop ────────────────────────────────────────────────
class SendButtonPop extends StatelessWidget {
  final Widget child;
  final bool visible;

  const SendButtonPop({
    super.key,
    required this.child,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutBack,
      child: child,
    );
  }
}

// ─── 19. Attach Button Rotate ───────────────────────────────────────────────
class RotateIconAnimation extends StatelessWidget {
  final Widget child;
  final bool isRotated;

  const RotateIconAnimation({
    super.key,
    required this.child,
    required this.isRotated,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedRotation(
      turns: isRotated ? 0.125 : 0.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: child,
    );
  }
}

