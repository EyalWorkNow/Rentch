import 'package:flutter/material.dart';

class RentchIcon extends StatefulWidget {
  const RentchIcon(
    this.icon, {
    super.key,
    this.size,
    this.fill,
    this.weight,
    this.grade,
    this.opticalSize,
    this.color,
    this.shadows,
    this.semanticLabel,
    this.textDirection,
    this.applyTextScaling,
    this.blendMode,
  });

  final IconData? icon;
  final double? size;
  final double? fill;
  final double? weight;
  final double? grade;
  final double? opticalSize;
  final Color? color;
  final List<Shadow>? shadows;
  final String? semanticLabel;
  final TextDirection? textDirection;
  final bool? applyTextScaling;
  final BlendMode? blendMode;

  @override
  State<RentchIcon> createState() => _RentchIconState();
}

class _RentchIconState extends State<RentchIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.92, end: 1.06), weight: 58),
      TweenSequenceItem(tween: Tween(begin: 1.06, end: 1.0), weight: 42),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant RentchIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.icon != widget.icon ||
        oldWidget.color != widget.color ||
        oldWidget.size != widget.size) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        child: Icon(
          widget.icon,
          size: widget.size,
          fill: widget.fill,
          weight: widget.weight,
          grade: widget.grade,
          opticalSize: widget.opticalSize,
          color: widget.color,
          shadows: widget.shadows,
          semanticLabel: widget.semanticLabel,
          textDirection: widget.textDirection,
          applyTextScaling: widget.applyTextScaling,
          blendMode: widget.blendMode,
        ),
      ),
    );
  }
}
