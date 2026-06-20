import 'package:flutter/material.dart';

class ScaleBounce extends StatefulWidget {
  const ScaleBounce({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDownTo = 0.95,
    this.duration = const Duration(milliseconds: 100),
    this.reverseDuration = const Duration(milliseconds: 180),
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scaleDownTo;
  final Duration duration;
  final Duration reverseDuration;

  @override
  State<ScaleBounce> createState() => _ScaleBounceState();
}

class _ScaleBounceState extends State<ScaleBounce> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: widget.duration,
      reverseDuration: widget.reverseDuration,
    );
    _scale = Tween<double>(begin: 1.0, end: widget.scaleDownTo).animate(
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
    if (widget.onTap == null) {
      return widget.child;
    }
    return GestureDetector(
      // Fire onTap IMMEDIATELY on tap-up. The press animation plays back
      // independently — never await it: a TickerFuture completes with
      // TickerCanceled if the controller is disposed/interrupted mid-animation
      // (e.g. a rebuild from the tap itself), which would silently swallow the
      // tap. Since every interactive control in the app is a ScaleBounce, that
      // failure mode looks like "nothing is tappable".
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        widget.onTap?.call();
        if (mounted) _ctrl.reverse();
      },
      onTapCancel: () => _ctrl.reverse(),
      behavior: HitTestBehavior.opaque,
      child: ScaleTransition(
        scale: _scale,
        child: widget.child,
      ),
    );
  }
}
