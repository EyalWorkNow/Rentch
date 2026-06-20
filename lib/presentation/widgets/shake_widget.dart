import 'package:flutter/material.dart';

class ShakeWidget extends StatefulWidget {
  const ShakeWidget({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 300),
    this.deltaX = 8.0,
    this.curve = Curves.elasticIn,
  });

  final Widget child;
  final Duration duration;
  final double deltaX;
  final Curve curve;

  @override
  State<ShakeWidget> createState() => ShakeWidgetState();
}

class ShakeWidgetState extends State<ShakeWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.duration,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void shake() {
    _controller.forward(from: 0.0);
  }

  double _getTranslation(double value) {
    // Shakes left and right 3 times
    // We use a sine wave to compute offset
    final double offset = widget.deltaX * (1.0 - value) * (1.0 - value) * 
        (3.14159 * 6 * value).hashCode.toDouble(); // fallback placeholder, wait sine wave is cleaner:
    // math.sin(6 * math.pi * value)
    // Let's use a standard mathematical sine:
    final waveValue = (value * 6 * 3.141592653589793);
    final double sine = _sine(waveValue);
    return widget.deltaX * sine * (1.0 - value);
  }

  double _sine(double val) {
    // Taylor series approximation of sin(x) for simplicity without importing dart:math
    // sin(x) = x - x^3/6 + x^5/120 - x^7/5040
    // Normalize to [-pi, pi]
    var x = val % (2 * 3.141592653589793);
    if (x > 3.141592653589793) x -= 2 * 3.141592653589793;
    final x3 = x * x * x;
    final x5 = x3 * x * x;
    return x - (x3 / 6.0) + (x5 / 120.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final double dx = _getTranslation(_controller.value);
        return Transform.translate(
          offset: Offset(dx, 0.0),
          child: child,
        );
      },
    );
  }
}
