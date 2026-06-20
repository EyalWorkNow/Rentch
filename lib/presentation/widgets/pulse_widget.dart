import 'package:flutter/material.dart';

class PulseWidget extends StatefulWidget {
  const PulseWidget({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1400),
    this.scaleUpTo = 1.15,
  });

  final Widget child;
  final Duration duration;
  final double scaleUpTo;

  @override
  State<PulseWidget> createState() => _PulseWidgetState();
}

class _PulseWidgetState extends State<PulseWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: widget.scaleUpTo).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: Curves.easeInOut,
      ),
    );
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
