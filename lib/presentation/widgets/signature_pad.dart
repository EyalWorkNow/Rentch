import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:flutter/material.dart';

/// Controls a [SignaturePad]: clear the canvas, query emptiness, and export the
/// drawn signature as a transparent PNG.
class SignaturePadController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];
  Size _size = Size.zero;

  List<List<Offset>> get strokes => _strokes;
  bool get isEmpty => _strokes.every((s) => s.length < 2);

  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  /// Notifies listeners after a stroke completes (the pad updates emptiness UI).
  void notifyChanged() => notifyListeners();

  /// Renders the strokes to a PNG (transparent background). Returns null if the
  /// pad is empty.
  Future<Uint8List?> exportPng({double scale = 2.0}) async {
    if (isEmpty || _size == Size.zero) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale);
    final paint = Paint()
      ..color = const Color(0xFF0F2A43)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in _strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (_size.width * scale).round(),
      (_size.height * scale).round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }
}

/// A finger/stylus signature canvas.
class SignaturePad extends StatefulWidget {
  const SignaturePad({super.key, required this.controller, this.height = 180});

  final SignaturePadController controller;
  final double height;

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  List<Offset> _current = [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, widget.height);
        widget.controller._size = size; // remember size for PNG export
        return GestureDetector(
          onPanStart: (d) {
            _current = [d.localPosition];
            widget.controller.strokes.add(_current);
            setState(() {});
          },
          onPanUpdate: (d) {
            setState(() => _current.add(d.localPosition));
          },
          onPanEnd: (_) => widget.controller.notifyChanged(),
          child: Container(
            height: widget.height,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: CustomPaint(
                painter: _SignaturePainter(widget.controller.strokes),
                size: size,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes);
  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF0F2A43)
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final p in stroke.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
