import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dchs_motion_sensors/dchs_motion_sensors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:path_provider/path_provider.dart';

/// AR-guided 360° capture, Photo-Sphere style: the user sweeps the phone to align
/// a centre reticle with floating target dots; each aligned target auto-captures
/// a frame. Frames are then composed (by heading) into an equirectangular-ish
/// panorama and the file path is returned via Navigator.pop.
///
/// NOTE: on-device only. The FOV / alignment constants below are calibration
/// knobs — real phones vary, so they may need per-device tuning. The compose
/// step is a best-effort heading-indexed stitch (no feature blending); for true
/// seamless quality use a native Photo Sphere or server-side stitching.
class StreetViewCaptureScreen extends StatefulWidget {
  const StreetViewCaptureScreen({super.key, this.label = ''});
  final String label;

  @override
  State<StreetViewCaptureScreen> createState() =>
      _StreetViewCaptureScreenState();
}

class _Target {
  _Target(this.yaw, this.pitch);
  final double yaw; // degrees, 0..360
  final double pitch; // degrees
  bool done = false;
}

class _Frame {
  _Frame(this.path, this.yaw, this.pitch);
  final String path;
  final double yaw;
  final double pitch;
}

class _StreetViewCaptureScreenState extends State<StreetViewCaptureScreen> {
  // ── calibration knobs (per-device tuning may be needed) ──────────────────────
  static const double _hFovDeg = 55; // horizontal field of view of the preview
  static const double _vFovDeg = 70; // vertical FOV (portrait)
  static const double _alignYawDeg = 7; // alignment tolerance
  static const double _alignPitchDeg = 9;
  static const Duration _holdToCapture = Duration(milliseconds: 450);

  CameraController? _cam;
  Future<void>? _camInit;
  String? _error;

  final _orientation = ValueNotifier<List<double>>([0, 0]); // [yawDeg, pitchDeg]
  StreamSubscription? _orientSub;

  final List<_Target> _targets = [];
  final List<_Frame> _frames = [];

  int? _holdingTarget; // index currently aligned
  DateTime? _holdStart;
  bool _capturing = false;
  bool _composing = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _buildTargets();
    _initCamera();
    _initSensors();
  }

  void _buildTargets() {
    // a horizontal ring (every 30°) plus an upper and lower band for fuller cover
    for (var y = 0; y < 360; y += 30) {
      _targets.add(_Target(y.toDouble(), 0));
    }
    for (var y = 0; y < 360; y += 60) {
      _targets.add(_Target(y.toDouble(), 32));
      _targets.add(_Target(y.toDouble(), -32));
    }
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      _camInit = ctrl.initialize();
      await _camInit;
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() => _cam = ctrl);
    } catch (e) {
      if (mounted) setState(() => _error = 'לא ניתן לפתוח את המצלמה');
    }
  }

  void _initSensors() {
    motionSensors.absoluteOrientationUpdateInterval =
        Duration.microsecondsPerSecond ~/ 60;
    _orientSub = motionSensors.absoluteOrientation.listen((e) {
      final yaw = (e.yaw * 180 / math.pi) % 360;
      final pitch = e.pitch * 180 / math.pi;
      _orientation.value = [yaw < 0 ? yaw + 360 : yaw, pitch];
      _maybeAutoCapture(_orientation.value[0], _orientation.value[1]);
    });
  }

  static double _normDelta(double a) {
    var d = a % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  void _maybeAutoCapture(double yaw, double pitch) {
    if (_capturing || _composing) return;
    // find nearest undone target within tolerance
    int? best;
    double bestScore = double.infinity;
    for (var i = 0; i < _targets.length; i++) {
      final t = _targets[i];
      if (t.done) continue;
      final dy = _normDelta(t.yaw - yaw).abs();
      final dp = (t.pitch - pitch).abs();
      if (dy < _alignYawDeg && dp < _alignPitchDeg) {
        final score = dy + dp;
        if (score < bestScore) {
          bestScore = score;
          best = i;
        }
      }
    }
    if (best == null) {
      _holdingTarget = null;
      _holdStart = null;
      return;
    }
    if (_holdingTarget != best) {
      _holdingTarget = best;
      _holdStart = DateTime.now();
      return;
    }
    if (_holdStart != null &&
        DateTime.now().difference(_holdStart!) >= _holdToCapture) {
      _capture(best);
    }
  }

  Future<void> _capture(int targetIndex, {bool manual = false}) async {
    final cam = _cam;
    if (cam == null || _capturing || _composing) return;
    _capturing = true;
    try {
      final shot = await cam.takePicture();
      final t = _targets[targetIndex];
      _frames.add(_Frame(shot.path, t.yaw, t.pitch));
      t.done = true;
      HapticFeedback.mediumImpact();
      if (mounted) setState(() {});
    } catch (_) {
      // ignore a failed frame; the user can re-align
    } finally {
      _holdingTarget = null;
      _holdStart = null;
      _capturing = false;
    }
  }

  void _manualCapture() {
    final o = _orientation.value;
    // snap the current direction to the nearest undone target (or any nearest)
    int best = 0;
    double bestScore = double.infinity;
    for (var i = 0; i < _targets.length; i++) {
      final t = _targets[i];
      final score =
          _normDelta(t.yaw - o[0]).abs() + (t.pitch - o[1]).abs() + (t.done ? 90 : 0);
      if (score < bestScore) {
        bestScore = score;
        best = i;
      }
    }
    _capture(best, manual: true);
  }

  int get _doneCount => _targets.where((t) => t.done).length;

  Future<void> _finish() async {
    if (_frames.length < 3 || _composing) return;
    setState(() => _composing = true);
    try {
      final path = await _composePanorama(_frames);
      if (!mounted) return;
      Navigator.of(context).pop(path);
    } catch (_) {
      if (mounted) setState(() => _composing = false);
    }
  }

  // Best-effort heading-indexed stitch: place each frame by its yaw into a 2:1
  // canvas (full height). No feature blending — rough but viewable.
  Future<String> _composePanorama(List<_Frame> frames) async {
    const w = 4096, h = 2048;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder,
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    canvas.drawRect(
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = Colors.black);

    final sorted = [...frames]..sort((a, b) => a.yaw.compareTo(b.yaw));
    final frameW = w * (_hFovDeg / 360.0) * 1.25; // slight overlap

    for (final f in sorted) {
      final img = await _decode(f.path);
      if (img == null) continue;
      final cx = (f.yaw / 360.0) * w;
      // vertical placement by pitch (0 = centre)
      final cy = h / 2 - (f.pitch / 180.0) * h;
      final dst = Rect.fromCenter(
        center: Offset(cx, cy),
        width: frameW,
        height: h.toDouble() * 0.7,
      );
      final src = Rect.fromLTWH(
          0, 0, img.width.toDouble(), img.height.toDouble());
      canvas.drawImageRect(img, src, dst, Paint());
      // wrap-around copies near the seam
      if (cx < frameW) {
        canvas.drawImageRect(
            img, src, dst.shift(Offset(w.toDouble(), 0)), Paint());
      }
      if (cx > w - frameW) {
        canvas.drawImageRect(
            img, src, dst.shift(Offset(-w.toDouble(), 0)), Paint());
      }
      img.dispose();
    }

    final picture = recorder.endRecording();
    final outImg = await picture.toImage(w, h);
    final bytes = await outImg.toByteData(format: ui.ImageByteFormat.png);
    outImg.dispose();
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/pano_${DateTime.now().microsecondsSinceEpoch}.png');
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    return file.path;
  }

  Future<ui.Image?> _decode(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _orientSub?.cancel();
    _orientation.dispose();
    _cam?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // camera preview (cover)
          if (_cam != null && _cam!.value.isInitialized)
            _coverPreview(_cam!)
          else if (_error != null)
            _errorState()
          else
            const Center(
                child: CircularProgressIndicator(color: Colors.white)),

          // AR guidance overlay (dots + reticle), repaints with orientation only
          if (_cam != null && _error == null)
            Positioned.fill(
              child: ValueListenableBuilder<List<double>>(
                valueListenable: _orientation,
                builder: (_, o, __) => CustomPaint(
                  painter: _GuidancePainter(
                    targets: _targets,
                    yaw: o[0],
                    pitch: o[1],
                    hFov: _hFovDeg,
                    vFov: _vFovDeg,
                    accent: AppColors.primary,
                    holdingTarget: _holdingTarget,
                  ),
                ),
              ),
            ),

          // top bar + progress
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    _circle(IconsaxPlusLinear.close_circle,
                        () => Navigator.of(context).pop()),
                    const Spacer(),
                    _ProgressPill(done: _doneCount, total: _targets.length),
                    const Spacer(),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
            ),
          ),

          // bottom instructions + controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _composing
                            ? 'מרכיב את הסיור…'
                            : 'כוון את העיגול שבמרכז אל הנקודות — הן יצולמו לבד',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _circle(IconsaxPlusLinear.camera, _manualCapture,
                            big: true),
                        _DoneButton(
                          enabled: _frames.length >= 3 && !_composing,
                          composing: _composing,
                          onTap: _finish,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _coverPreview(CameraController cam) {
    final size = MediaQuery.of(context).size;
    return ClipRect(
      child: OverflowBox(
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.width,
            height: size.width * cam.value.aspectRatio,
            child: CameraPreview(cam),
          ),
        ),
      ),
    );
  }

  Widget _errorState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(IconsaxPlusLinear.camera_slash,
                color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            Text(_error ?? 'שגיאת מצלמה',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('סגור'),
            ),
          ],
        ),
      );

  Widget _circle(IconData icon, VoidCallback onTap, {bool big = false}) {
    final d = big ? 64.0 : 40.0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          color: big ? Colors.white : Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
          border: big ? Border.all(color: AppColors.primary, width: 3) : null,
        ),
        child: Icon(icon,
            color: big ? AppColors.primary : Colors.white, size: big ? 28 : 20),
      ),
    );
  }
}

// Projects target dots onto the preview from the device orientation, draws the
// centre reticle, and highlights the dot being aligned/held.
class _GuidancePainter extends CustomPainter {
  _GuidancePainter({
    required this.targets,
    required this.yaw,
    required this.pitch,
    required this.hFov,
    required this.vFov,
    required this.accent,
    required this.holdingTarget,
  });

  final List<_Target> targets;
  final double yaw, pitch, hFov, vFov;
  final Color accent;
  final int? holdingTarget;

  static double _normDelta(double a) {
    var d = a % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2, cy = size.height / 2;

    for (var i = 0; i < targets.length; i++) {
      final t = targets[i];
      final dYaw = _normDelta(t.yaw - yaw);
      final dPitch = t.pitch - pitch;
      if (dYaw.abs() > hFov || dPitch.abs() > vFov) continue; // off-screen

      final x = cx + (dYaw / hFov) * (size.width / 2);
      final y = cy - (dPitch / vFov) * (size.height / 2);

      final aligned = i == holdingTarget;
      final paint = Paint()
        ..style = PaintingStyle.fill
        ..color = t.done
            ? accent.withValues(alpha: 0.9)
            : (aligned ? Colors.white : Colors.white.withValues(alpha: 0.5));
      final r = t.done ? 9.0 : (aligned ? 16.0 : 11.0);
      canvas.drawCircle(Offset(x, y), r, paint);
      if (!t.done) {
        canvas.drawCircle(
            Offset(x, y),
            r + 3,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = Colors.white.withValues(alpha: 0.6));
      }
      if (t.done) {
        canvas.drawCircle(Offset(x, y), 3, Paint()..color = Colors.white);
      }
    }

    // centre reticle
    final reticle = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = accent;
    canvas.drawCircle(Offset(cx, cy), 26, reticle);
    canvas.drawCircle(Offset(cx, cy), 3, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(covariant _GuidancePainter old) =>
      old.yaw != yaw || old.pitch != pitch || old.holdingTarget != holdingTarget;
}

class _ProgressPill extends StatelessWidget {
  const _ProgressPill({required this.done, required this.total});
  final int done, total;

  @override
  Widget build(BuildContext context) {
    final pct = total == 0 ? 0.0 : done / total;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              value: pct,
              strokeWidth: 3,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          Text('$done/$total',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13)),
        ],
      ),
    );
  }
}

class _DoneButton extends StatelessWidget {
  const _DoneButton({
    required this.enabled,
    required this.composing,
    required this.onTap,
  });
  final bool enabled, composing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: enabled ? AppColors.primary : Colors.white24,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
      onPressed: enabled ? onTap : null,
      icon: composing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : const Icon(IconsaxPlusLinear.tick_circle),
      label: Text(composing ? 'מרכיב…' : 'סיום',
          style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}
