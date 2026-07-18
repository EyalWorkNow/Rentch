import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/presentation/features/panorama/panorama_sweep_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// STREET-VIEW-STYLE full-sphere capture. The user stands in ONE spot and the
/// app floats target dots on a virtual sphere all around them (a full 360×180
/// ball). They turn/tilt the phone to bring a dot into the centre reticle; when
/// the aim locks on a dot the app AUTO-captures an HDR bracket there and the dot
/// turns green — until the whole ball is filled. Each shot carries its KNOWN
/// yaw/pitch pose, so the existing server pose-assisted projection builds a true
/// equirectangular 360 (poles included) — no on-device stitching, no foreign lib.
///
/// This is the capture UX Google's Photo Sphere has and that no open-source drop-in
/// provides for full-sphere; we build it on the pose pipeline the app already owns.
///
/// SIMULATOR NOTE: with no camera/gyro, drag anywhere to aim and dots auto-capture
/// as a visual demo (no real photo, no server build) so the feel is verifiable.
class PanoramaSphereCaptureScreen extends StatefulWidget {
  const PanoramaSphereCaptureScreen({super.key});

  @override
  State<PanoramaSphereCaptureScreen> createState() =>
      _PanoramaSphereCaptureScreenState();
}

// HDR exposure bracket per target (identical to the photo path): -1.3 protects
// bright windows, +1.3 lifts dim corners, middle is the neutral base.
const _bracketEvs = <double>[-1.3, 0.0, 1.3];
// iPhone 0.5× ultra-wide is really ~100–106° horizontal (NOT 90°). The old 90°
// made the dots slide at the wrong rate vs the world ("everything moves"). This
// is the FOV-calibration knob — nudge if dots lead/lag the scene on a device.
const _ultraWideHfovDeg = 102.0;
const _normalHfovDeg = 66.0;
// Aim is "locked on" a dot within this great-circle angle; then a short dwell
// (holding still on it) fires the capture. A touch more forgiving now that there
// are fewer, wider-spaced targets.
const _lockDeg = 13.0;
const _dwellMs = 450;
const _maxSpinForCapture = 26.0; // deg/s — must be fairly still to fire
// Low-pass factor for the displayed/aiming pose. Lower = smoother but laggier.
// This is the main cure for the "gyro רועד" jitter: raw sensor noise is filtered
// so the dots glide instead of shaking.
const _poseSmoothing = 0.16;

class _Target {
  _Target(this.yaw, this.pitch);
  final double yaw; // 0..360 heading
  final double pitch; // -90..90
  bool captured = false;
}

class _PanoramaSphereCaptureScreenState
    extends State<PanoramaSphereCaptureScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cam;
  bool _hasCamera = false; // false on the simulator → demo mode
  StreamSubscription<GyroscopeEvent>? _gyro;
  StreamSubscription<AccelerometerEvent>? _accel;
  Ticker? _ticker;

  double? _minZoom;
  bool _ultraWide = false;

  bool _building = false;
  bool _capturing = false;
  String _buildMsg = '';
  String? _buildError;

  // Pose. Yaw is a SIGNED accumulation (can turn either way) normalised to
  // 0..360 for targeting; pitch comes straight off gravity. Same gravity-
  // projected-yaw math as the other capture screens (robust to a little tilt).
  final _clock = Stopwatch();
  double _yawDeg = 0;
  double _pitchDeg = 0;
  double _spinRate = 0;
  int _lastGyroUs = 0;
  double _gx = 0, _gy = -1, _gz = 0;

  // Smoothed pose ACTUALLY used for aiming + drawing. Raw sensor values are
  // low-passed into these so the dots glide instead of shaking (the "gyro רועד"
  // complaint). Capture also reads these so jitter can't false-trigger a shot.
  double _dispHeading = 0;
  double _dispPitch = 0;
  bool _poseInit = false;

  // The target sphere + captured frames (kept parallel like the photo screen).
  final List<_Target> _targets = [];
  final List<String> _shotPaths = [];
  final List<double> _shotYaws = [];
  final List<double> _shotPitches = [];
  final List<int> _shotGroups = [];
  int _groups = 0;

  // Auto-capture dwell tracking.
  int? _lockedIdx;
  int _lockedSinceMs = 0;

  // Drives the overlay repaint each frame without setState churn.
  final _frame = ValueNotifier<int>(0);

  int get _capturedCount => _targets.where((t) => t.captured).length;
  double get _headingDeg => (_yawDeg % 360 + 360) % 360;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _clock.start();
    _buildTargets();
    // Guard the sensor streams: on a device without them (or in tests) the app
    // still runs in drag-to-aim mode instead of crashing.
    try {
      _accel = accelerometerEventStream().listen(_onAccel, onError: (_) {});
      _gyro = gyroscopeEventStream().listen(_onGyro, onError: (_) {});
    } catch (e) {
      debugPrint('sphere sensors unavailable: $e');
    }
    _ticker = createTicker(_onTick)..start();
    _init();
  }

  // A ball of targets: a dense middle ring + upper/lower rings + the two poles.
  // Ultra-wide (~90°) at these spacings gives generous overlap for the stitch.
  void _buildTargets() {
    void ring(double pitch, int n, double offset) {
      for (var i = 0; i < n; i++) {
        _targets.add(_Target((offset + 360.0 * i / n) % 360, pitch));
      }
    }

    // Fewer, wider-spaced targets: the ~102° ultra-wide covers a lot per shot,
    // so 6 around the horizon still overlap generously. Fewer positions → less
    // turning → less accumulated drift, and a calmer, faster capture.
    ring(0, 6, 0); // horizon — every 60°
    ring(40, 4, 45); // up — staggered
    ring(-40, 4, 45); // down — staggered
    _targets.add(_Target(0, 80)); // zenith (near straight up)
    _targets.add(_Target(0, -80)); // nadir (near straight down)
  }

  Future<void> _init() async {
    CameraController? ctrl;
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw StateError('no camera');
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      ctrl =
          CameraController(back, ResolutionPreset.veryHigh, enableAudio: false);
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      await _lockCamera(ctrl);
      await _initZoom(ctrl);
      setState(() {
        _cam = ctrl;
        _hasCamera = true;
      });
    } catch (e) {
      // No camera (simulator) → DEMO MODE: keep the sphere UX fully interactive
      // with drag-to-aim + simulated capture, so the feel is verifiable.
      debugPrint('sphere capture: no camera → demo mode ($e)');
      try {
        await ctrl?.dispose();
      } catch (_) {}
      if (mounted) setState(() => _hasCamera = false);
    }
  }

  Future<void> _lockCamera(CameraController ctrl) async {
    Future<void> tryLock(String what, Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        debugPrint('sphere lock $what failed: $e');
      }
    }

    await tryLock('orientation',
        () => ctrl.lockCaptureOrientation(DeviceOrientation.portraitUp));
    await tryLock('focus', () => ctrl.setFocusMode(FocusMode.locked));
    await tryLock('exposure-auto',
        () => ctrl.setExposureMode(ExposureMode.auto));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    await tryLock('exposure-offset', () => ctrl.setExposureOffset(0.0));
    await tryLock(
        'exposure-lock', () => ctrl.setExposureMode(ExposureMode.locked));
  }

  Future<void> _initZoom(CameraController ctrl) async {
    try {
      final minZoom = await ctrl.getMinZoomLevel();
      if (minZoom < 1.0) {
        _minZoom = minZoom;
        _ultraWide = true;
        await ctrl.setZoomLevel(minZoom);
      }
    } catch (e) {
      debugPrint('sphere zoom probe failed: $e');
      _minZoom = null;
    }
  }

  Future<void> _toggleUltraWide() async {
    final cam = _cam;
    final mz = _minZoom;
    if (cam == null || mz == null) return;
    final next = !_ultraWide;
    try {
      await cam.setZoomLevel(next ? mz : 1.0);
      setState(() => _ultraWide = next);
    } catch (e) {
      debugPrint('sphere setZoom failed: $e');
    }
  }

  void _onAccel(AccelerometerEvent e) {
    final m = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (m < 1e-3) return;
    // Low-pass the gravity vector itself (accelerometer is noisy) → steadier
    // pitch AND a steadier world-up for the yaw projection.
    const a = 0.2;
    _gx += (e.x / m - _gx) * a;
    _gy += (e.y / m - _gy) * a;
    _gz += (e.z / m - _gz) * a;
    final gm = math.sqrt(_gx * _gx + _gy * _gy + _gz * _gz);
    if (gm > 1e-3) {
      _pitchDeg = math.asin((_gz / gm).clamp(-1.0, 1.0)) * 180 / math.pi;
    }
  }

  void _onGyro(GyroscopeEvent e) {
    final now = _clock.elapsedMicroseconds;
    final last = _lastGyroUs;
    _lastGyroUs = now;
    if (last == 0) {
      _spinRate = 0;
      return;
    }
    final dt = (now - last) / 1e6;
    final yawRate = e.x * _gx + e.y * _gy + e.z * _gz; // rad/s about world-up
    _spinRate = yawRate.abs() * 180 / math.pi;
    _yawDeg += yawRate * 180 / math.pi * dt; // SIGNED
  }

  double get _hfovDeg => _ultraWide ? _ultraWideHfovDeg : _normalHfovDeg;

  double get _vfovDeg {
    final cam = _cam;
    final a =
        (cam != null && cam.value.isInitialized) ? cam.value.aspectRatio : 0.75;
    final factor = (a > 0) ? 1 / a : 4 / 3;
    return (_hfovDeg * factor).clamp(_hfovDeg, 180.0);
  }

  // Great-circle angle (deg) between the current (smoothed) aim and a target.
  double _angTo(_Target t) {
    final p1 = _dispPitch * math.pi / 180, p2 = t.pitch * math.pi / 180;
    final dyaw = _wrap180(t.yaw - _dispHeading) * math.pi / 180;
    final c =
        (math.sin(p1) * math.sin(p2) + math.cos(p1) * math.cos(p2) * math.cos(dyaw))
            .clamp(-1.0, 1.0);
    return math.acos(c) * 180 / math.pi;
  }

  // Per-frame: manage lock-on dwell and fire the auto-capture.
  void _onTick(Duration _) {
    _frame.value++; // repaint the overlay
    // Low-pass the raw pose into the displayed/aiming pose every frame → the
    // dots glide instead of jittering with sensor noise.
    if (!_poseInit) {
      _dispHeading = _headingDeg;
      _dispPitch = _pitchDeg;
      _poseInit = true;
    } else {
      _dispHeading =
          (_dispHeading + _wrap180(_headingDeg - _dispHeading) * _poseSmoothing +
                  360) %
              360;
      _dispPitch += (_pitchDeg - _dispPitch) * _poseSmoothing;
    }
    if (_building || _capturing) return;

    // Nearest uncaptured target within the lock cone.
    int? near;
    var best = _lockDeg;
    for (var i = 0; i < _targets.length; i++) {
      if (_targets[i].captured) continue;
      final d = _angTo(_targets[i]);
      if (d < best) {
        best = d;
        near = i;
      }
    }

    final nowMs = _clock.elapsedMilliseconds;
    if (near == null || _spinRate > _maxSpinForCapture) {
      _lockedIdx = null;
      return;
    }
    if (near != _lockedIdx) {
      _lockedIdx = near;
      _lockedSinceMs = nowMs;
      return;
    }
    if (nowMs - _lockedSinceMs >= _dwellMs) {
      _lockedIdx = null;
      _captureTarget(near);
    }
  }

  Future<void> _captureTarget(int idx) async {
    if (_capturing || _building) return;
    _capturing = true;
    final t = _targets[idx];
    final group = _groups;
    // Freeze the pose for the whole bracket at the smoothed (stable) aim.
    final yaw = _dispHeading;
    final pitch = _dispPitch;
    final cam = _cam;
    try {
      if (_hasCamera && cam != null) {
        for (final ev in _bracketEvs) {
          try {
            await cam.setExposureOffset(ev);
            await Future<void>.delayed(const Duration(milliseconds: 220));
          } catch (_) {}
          final XFile shot = await cam.takePicture();
          _shotPaths.add(shot.path);
          _shotYaws.add(yaw);
          _shotPitches.add(pitch);
          _shotGroups.add(group);
        }
        try {
          await cam.setExposureOffset(0.0);
        } catch (_) {}
      } else {
        // DEMO (simulator): no real frame — just mark the dot filled.
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      t.captured = true;
      _groups++;
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _capturing = false);
      if (_capturedCount >= _targets.length) await _finish();
    } catch (e) {
      debugPrint('sphere capture failed: $e');
      if (mounted) setState(() => _capturing = false);
    }
  }

  // Drag-to-aim: works as a manual fallback (and the only aim on the simulator,
  // where there is no gyro). Additive with the gyro on a real device.
  void _onPan(DragUpdateDetails d) {
    final w = MediaQuery.of(context).size.width.clamp(1.0, 4000.0);
    _yawDeg += d.delta.dx / w * _hfovDeg; // drag right → look right
    _pitchDeg = (_pitchDeg - d.delta.dy / w * _hfovDeg).clamp(-90.0, 90.0);
  }

  Future<void> _finish() async {
    // Simulator/demo: nothing to stitch — celebrate and close.
    if (!_hasCamera || _shotPaths.isEmpty) {
      _toast('הכדור הושלם ✓ — במכשיר אמיתי זה נבנה עכשיו ל-360° מלא.');
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await _build();
  }

  Future<void> _build() async {
    setState(() {
      _building = true;
      _buildError = null;
      _buildMsg = 'מתחילים לבנות את הסיור...';
    });

    final hfov = _hfovDeg, vfov = _vfovDeg;
    final poses = <Map<String, double>>[
      for (var i = 0; i < _shotPaths.length; i++)
        {
          'yaw': _shotYaws[i],
          'pitch': _shotPitches[i],
          'hfov': hfov,
          'vfov': vfov,
          'group': _shotGroups[i].toDouble(),
        },
    ];

    try {
      final groupId = 'draft_${DateTime.now().millisecondsSinceEpoch}';
      final job = await AwsApiClient.instance.createPanoramaJob(
        propertyId: groupId,
        frameCount: _shotPaths.length,
        poses: poses,
      );
      if (job == null) {
        _failBuild('לא הצלחנו להתחיל את העיבוד. בדקו את החיבור לאינטרנט.');
        return;
      }
      if (!mounted) return;
      setState(() => _buildMsg = 'מעלים את התמונות...');
      for (var i = 0; i < _shotPaths.length; i++) {
        final ok = await AwsApiClient.instance
            .uploadToPresignedUrl(job.uploadUrls[i], _shotPaths[i]);
        if (!ok) {
          _failBuild('ההעלאה נכשלה. בדקו את החיבור ונסו שוב.');
          return;
        }
        if (!mounted) return;
        setState(() =>
            _buildMsg = 'מעלים את התמונות... (${i + 1}/${_shotPaths.length})');
      }
      if (!mounted) return;
      setState(() => _buildMsg = 'בונים את הסיור...');
      await AwsApiClient.instance.startPanoramaStitch(job.jobId);

      const maxPolls = 90;
      for (var i = 0; i < maxPolls; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        final status = await AwsApiClient.instance.getPanorama(job.jobId);
        if (status == null) continue;
        if (status.status == 'ready' && status.imageUrl.isNotEmpty) {
          if (!mounted) return;
          Navigator.of(context).pop(PanoramaSweepResult(
            imageUrl: status.imageUrl,
            haov: status.haov,
            vaov: status.vaov,
            poses: poses,
          ));
          return;
        }
        if (status.status == 'failed') {
          _failBuild('העיבוד נכשל. נסו לצלם שוב, לאט ובאור טוב.');
          return;
        }
      }
      _failBuild('העיבוד לוקח יותר מדי זמן. נסו שוב מאוחר יותר.');
    } catch (e) {
      debugPrint('sphere build failed: $e');
      _failBuild('משהו השתבש. בדקו את החיבור ונסו שוב.');
    }
  }

  void _failBuild(String msg) {
    if (!mounted) return;
    setState(() {
      _buildError = msg;
      _building = true;
    });
  }

  void _retryFromError() {
    setState(() {
      _building = false;
      _buildError = null;
      _buildMsg = '';
      _shotPaths.clear();
      _shotYaws.clear();
      _shotPitches.clear();
      _shotGroups.clear();
      _groups = 0;
      for (final t in _targets) {
        t.captured = false;
      }
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 2600),
      content: Text(msg),
    ));
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _ticker?.dispose();
    _gyro?.cancel();
    _accel?.cancel();
    _frame.dispose();
    _cam?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onPanUpdate: _building ? null : _onPan,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Live camera, or a demo backdrop on the simulator.
            if (_hasCamera && _cam != null && _cam!.value.isInitialized)
              _cover(_cam!)
            else
              const _DemoBackdrop(),

            // The floating target sphere + centre reticle (the whole point).
            if (!_building)
              Positioned.fill(
                child: RepaintBoundary(
                  child: ValueListenableBuilder<int>(
                    valueListenable: _frame,
                    builder: (_, __, ___) => CustomPaint(
                      painter: _SphereTargetsPainter(
                        targets: _targets,
                        headingDeg: _dispHeading,
                        pitchDeg: _dispPitch,
                        hfovDeg: _hfovDeg,
                        vfovDeg: _vfovDeg,
                        lockedIdx: _lockedIdx,
                      ),
                    ),
                  ),
                ),
              ),

            // Top bar.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap:
                            _building ? null : () => Navigator.of(context).pop(),
                        child: _circle(IconsaxPlusLinear.close_circle),
                      ),
                      const Spacer(),
                      if (_minZoom != null && !_building) _zoomToggle(),
                    ],
                  ),
                ),
              ),
            ),

            // Coverage ball + progress + coaching.
            if (!_building)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 52, 12, 0),
                    child: ValueListenableBuilder<int>(
                      valueListenable: _frame,
                      builder: (_, __, ___) => _hud(),
                    ),
                  ),
                ),
              ),

            // Bottom coaching + manual capture (backup if auto-lock won't fire).
            if (!_building)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _coachLine(),
                        const SizedBox(height: 12),
                        _manualCaptureHint(),
                      ],
                    ),
                  ),
                ),
              ),

            if (_capturing) const _CaptureFlash(),
            if (_building) _buildOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _hud() {
    final done = _capturedCount >= _targets.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _coachPill(
          done
              ? 'הכדור הושלם ✓'
              : 'צולמו $_capturedCount מתוך ${_targets.length}',
          bg: done
              ? Colors.green.withValues(alpha: 0.85)
              : Colors.black.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 12),
        CustomPaint(
          size: const Size(132, 132),
          painter: _CoverageBallPainter(
            targets: _targets,
            headingDeg: _dispHeading,
            pitchDeg: _dispPitch,
          ),
        ),
      ],
    );
  }

  Widget _coachLine() {
    String text;
    final done = _capturedCount >= _targets.length;
    // Direction to the nearest uncaptured target, to guide the turn.
    _Target? next;
    var best = 1e9;
    for (final t in _targets) {
      if (t.captured) continue;
      final d = _angTo(t);
      if (d < best) {
        best = d;
        next = t;
      }
    }
    if (done) {
      text = 'מצוין! בונים את הסיור...';
    } else if (_spinRate > _maxSpinForCapture) {
      text = 'האטו — החזיקו יציב על הנקודה';
    } else if (best < _lockDeg) {
      text = 'החזיקו רגע... ננעל ומצלם 📸';
    } else if (next != null) {
      final dyaw = _wrap180(next.yaw - _dispHeading);
      final dpitch = next.pitch - _dispPitch;
      final dir = dpitch > 20
          ? 'הרימו את הטלפון למעלה ☝️'
          : dpitch < -20
              ? 'הטו את הטלפון למטה 👇'
              : dyaw > 0
                  ? 'סובבו ימינה ➡️'
                  : 'סובבו שמאלה ⬅️';
      text = 'כוונו את הנקודה למרכז — $dir';
    } else {
      text = 'כוונו את הנקודה הזוהרת אל המרכז';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              height: 1.4,
              fontWeight: FontWeight.w700)),
    );
  }

  // Backup: if the phone can't quite lock (or the user wants control), tap to
  // capture the nearest target manually.
  Widget _manualCaptureHint() {
    return GestureDetector(
      onTap: _capturing
          ? null
          : () {
              int? near;
              var best = _lockDeg * 2.2; // more forgiving for a manual tap
              for (var i = 0; i < _targets.length; i++) {
                if (_targets[i].captured) continue;
                final d = _angTo(_targets[i]);
                if (d < best) {
                  best = d;
                  near = i;
                }
              }
              if (near != null) {
                _captureTarget(near);
              } else {
                _toast('כוונו קרוב יותר לנקודה לא-מצולמת');
              }
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white54),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(IconsaxPlusLinear.camera, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text('צלמו את הנקודה שבמרכז',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlay() {
    final hasError = _buildError != null;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.92),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  hasError
                      ? IconsaxPlusLinear.warning_2
                      : IconsaxPlusBold.gallery,
                  color: hasError ? AppColors.coral : AppColors.primary,
                  size: 64,
                ),
                const SizedBox(height: 22),
                Text(
                  hasError ? 'לא הצלחנו לבנות את הסיור' : 'בונים את הסיור...',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                Text(
                  hasError
                      ? _buildError!
                      : '$_buildMsg\n\nאפשר להמתין כמה רגעים — אל תסגרו את המסך.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 17, height: 1.5),
                ),
                const SizedBox(height: 28),
                if (hasError) ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _retryFromError,
                      icon: const Icon(IconsaxPlusBold.refresh),
                      label: const Text('צלם מחדש',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 18)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('סגור',
                        style: TextStyle(color: Colors.white70, fontSize: 16)),
                  ),
                ] else
                  const CircularProgressIndicator(color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _coachPill(String text, {required Color bg}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                height: 1.3,
                fontWeight: FontWeight.w900)),
      );

  Widget _zoomToggle() => GestureDetector(
        onTap: _toggleUltraWide,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_ultraWide ? '0.5×' : '1×',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900)),
              const SizedBox(width: 8),
              Text(_ultraWide ? 'רחב' : 'רגיל',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );

  Widget _circle(IconData icon) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      );

  Widget _cover(CameraController cam) {
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
}

double _wrap180(double deg) {
  var d = (deg + 180) % 360;
  if (d < 0) d += 360;
  return d - 180;
}

// A subtle animated gradient stand-in for the camera on the simulator, so the
// target sphere reads clearly in the demo.
class _DemoBackdrop extends StatelessWidget {
  const _DemoBackdrop();
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.center,
          radius: 1.1,
          colors: [AppColors.inkSoft, AppColors.ink],
        ),
      ),
      child: const Center(
        child: Text('מצב הדגמה (סימולטור)\nגררו כדי לכוון',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white24, fontSize: 14, height: 1.5)),
      ),
    );
  }
}

class _CaptureFlash extends StatelessWidget {
  const _CaptureFlash();
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 6),
          ),
        ),
      );
}

/// Draws every target projected into the camera view from the current aim, plus
/// the centre reticle. Captured = green ✓; the one being locked = a growing coral
/// ring; others = white dots. Off-screen targets are hinted by an edge chevron.
class _SphereTargetsPainter extends CustomPainter {
  _SphereTargetsPainter({
    required this.targets,
    required this.headingDeg,
    required this.pitchDeg,
    required this.hfovDeg,
    required this.vfovDeg,
    required this.lockedIdx,
  });
  final List<_Target> targets;
  final double headingDeg, pitchDeg, hfovDeg, vfovDeg;
  final int? lockedIdx;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final halfH = hfovDeg / 2, halfV = vfovDeg / 2;

    _Target? nearestOff;
    var nearestOffAng = 1e9;

    for (var i = 0; i < targets.length; i++) {
      final t = targets[i];
      final dyaw = _wrap180(t.yaw - headingDeg);
      final dpitch = t.pitch - pitchDeg;
      final onScreen = dyaw.abs() < halfH && dpitch.abs() < halfV;
      if (!onScreen) {
        if (!t.captured) {
          final ang = dyaw.abs() + dpitch.abs();
          if (ang < nearestOffAng) {
            nearestOffAng = ang;
            nearestOff = t;
          }
        }
        continue;
      }
      final x = c.dx + (dyaw / halfH) * (size.width / 2);
      final y = c.dy - (dpitch / halfV) * (size.height / 2);
      final p = Offset(x, y);

      if (t.captured) {
        canvas.drawCircle(p, 15, Paint()..color = Colors.greenAccent.withValues(alpha: 0.9));
        _check(canvas, p);
      } else if (i == lockedIdx) {
        // Locking on: pulsing coral ring.
        canvas.drawCircle(
            p,
            22,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4
              ..color = AppColors.coral);
        canvas.drawCircle(p, 10, Paint()..color = AppColors.coral);
      } else {
        canvas.drawCircle(p, 13,
            Paint()..color = Colors.white.withValues(alpha: 0.85));
        canvas.drawCircle(
            p,
            13,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = Colors.black.withValues(alpha: 0.4));
      }
    }

    // Centre reticle.
    final locked = lockedIdx != null;
    canvas.drawCircle(
        c,
        30,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = (locked ? AppColors.coral : Colors.white)
              .withValues(alpha: 0.9));
    canvas.drawCircle(c, 3, Paint()..color = Colors.white);

    // Edge chevron toward the nearest off-screen uncaptured target.
    if (nearestOff != null) {
      final dyaw = _wrap180(nearestOff.yaw - headingDeg);
      final dpitch = nearestOff.pitch - pitchDeg;
      final ang = math.atan2(-dpitch, dyaw);
      final rr = math.min(size.width, size.height) / 2 - 42;
      final ep = c + Offset(math.cos(ang), math.sin(ang)) * rr;
      final tri = Path();
      const s = 16.0;
      tri.moveTo(ep.dx + math.cos(ang) * s, ep.dy + math.sin(ang) * s);
      tri.lineTo(ep.dx + math.cos(ang + 2.5) * s, ep.dy + math.sin(ang + 2.5) * s);
      tri.lineTo(ep.dx + math.cos(ang - 2.5) * s, ep.dy + math.sin(ang - 2.5) * s);
      tri.close();
      canvas.drawPath(tri, Paint()..color = AppColors.coral.withValues(alpha: 0.9));
    }
  }

  void _check(Canvas canvas, Offset p) {
    final path = Path()
      ..moveTo(p.dx - 6, p.dy)
      ..lineTo(p.dx - 1.5, p.dy + 5)
      ..lineTo(p.dx + 7, p.dy - 5);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = Colors.black87);
  }

  @override
  bool shouldRepaint(covariant _SphereTargetsPainter old) => true;
}

/// A small orthographic "globe" of all target dots that rotates with the phone's
/// heading and fills green as targets are captured — the "ball filling up".
class _CoverageBallPainter extends CustomPainter {
  _CoverageBallPainter({
    required this.targets,
    required this.headingDeg,
    required this.pitchDeg,
  });
  final List<_Target> targets;
  final double headingDeg, pitchDeg;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 8;

    // Globe outline.
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white24);

    final yaw0 = headingDeg * math.pi / 180;
    for (final t in targets) {
      final ty = t.yaw * math.pi / 180 - yaw0;
      final tp = t.pitch * math.pi / 180;
      // 3D on unit sphere, then orthographic (viewer looks along +z = heading).
      final x = math.cos(tp) * math.sin(ty);
      final y = -math.sin(tp);
      final z = math.cos(tp) * math.cos(ty);
      final p = c + Offset(x * r, y * r);
      final front = z >= 0;
      final color = t.captured
          ? Colors.greenAccent
          : Colors.white.withValues(alpha: front ? 0.8 : 0.25);
      canvas.drawCircle(p, front ? 3.5 : 2.5,
          Paint()..color = t.captured ? color : color);
    }

    // "You are here" marker at the front centre.
    canvas.drawCircle(
        c + Offset(0, 0), 0, Paint()..color = Colors.transparent);
  }

  @override
  bool shouldRepaint(covariant _CoverageBallPainter old) => true;
}
