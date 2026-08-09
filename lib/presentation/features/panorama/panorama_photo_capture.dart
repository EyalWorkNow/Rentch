import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/presentation/features/panorama/panorama_sweep_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Guided 10-PHOTO 360° capture for an older, non-technical landlord. The user
/// stands in ONE spot, holds the phone VERTICAL at 0.5× ultra-wide, and takes
/// [_shotCount] overlapping stills all around them (~36° apart). The app guides
/// each shot with a rotation progress ring, a "turn ~36° and shoot" prompt and an
/// overlap hint (a sliver of the previous frame), then uploads the photos and runs
/// the EXISTING server OpenCV/pose-assisted stitch into one equirectangular 360,
/// popping a finished [PanoramaSweepResult] (URL + haov/vaov). The caller adds it
/// as a tour node EXACTLY like the sweep result — the tour flow is unchanged.
///
/// Why this replaces video→360: stills are sharp (no motion blur), and sending
/// the KNOWN per-shot yaw lets the server project deterministically (immune to the
/// blank-wall "black hole" cv2.Stitcher failure) for a faithful, seam-free pano.
class PanoramaPhotoCaptureScreen extends StatefulWidget {
  const PanoramaPhotoCaptureScreen({super.key});

  @override
  State<PanoramaPhotoCaptureScreen> createState() =>
      _PanoramaPhotoCaptureScreenState();
}

// 10 shots around a full circle → 36° apart. Ultra-wide (~90° hfov) at 36° steps
// gives a generous ~54° overlap between neighbours — plenty for a clean stitch.
const _shotCount = 10;
const _stepDeg = 360.0 / _shotCount; // 36°
// HDR exposure bracket (EV offsets) captured at each position. -1.3 protects
// bright windows, +1.3 lifts dim corners; the middle is the neutral base. A
// device that ignores offset-while-locked just yields near-identical frames →
// the server fusion is a harmless no-op (no regression).
const _bracketEvs = <double>[-1.3, 0.0, 1.3];
// Default ultra-wide / normal horizontal FOV (the camera plugin doesn't expose
// the real lens FOV). 0.5× ultra-wide is ~90°; 1× back camera ~65°. vfov is
// derived from the captured portrait aspect (tall frame → vfov > hfov).
const _ultraWideHfovDeg = 90.0;
const _normalHfovDeg = 65.0;

class _PanoramaPhotoCaptureScreenState
    extends State<PanoramaPhotoCaptureScreen> {
  CameraController? _cam;
  StreamSubscription<GyroscopeEvent>? _gyro;
  StreamSubscription<AccelerometerEvent>? _accel;
  String? _error;

  bool _building = false; // upload → stitch → poll overlay
  bool _capturing = false; // a takePicture is in flight (debounce the button)
  String _buildMsg = '';
  String? _buildError;

  // Ultra-wide (0.5×). _minZoom null → no ultra-wide reachable (fall back to 1×).
  double? _minZoom;
  bool _ultraWide = false;

  // Gravity-projected yaw integration — identical math to the sweep/video screens
  // so the heading is correct even if the phone is tilted a little.
  final _clock = Stopwatch();
  double _yawDeg = 0; // accumulated |yaw| since the screen opened
  double _spinRate = 0; // deg/s about world-up (for the "hold still" hint)
  int _lastGyroUs = 0;
  double _gx = 0, _gy = -1, _gz = 0; // gravity unit vector; default upright
  double _pitchDeg = 0;

  // Captured shots, kept parallel: file path[i] ↔ yaw[i] ↔ pitch[i]. The target
  // yaw for shot i is i*36°; we record the ACTUAL turned yaw + tilt so the server
  // projects each photo where it really points.
  final List<String> _shotPaths = [];
  final List<double> _shotYaws = [];
  final List<double> _shotPitches = [];
  // HDR: which capture POSITION each frame belongs to. Frames sharing a group are
  // an exposure bracket of the same view; the server Mertens-fuses them into one
  // well-exposed frame (bright windows AND dim interior hold) before projecting.
  final List<int> _shotGroups = [];
  int _positions = 0; // capture positions completed (each = a bracket of frames)
  final _yawNotifier = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _clock.start();
    _init();
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
      // veryHigh stills: sharp input for the stitch. We capture only between
      // turns (the user is still), so the heavier encode never fights motion.
      ctrl =
          CameraController(back, ResolutionPreset.veryHigh, enableAudio: false);
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      // Lock focus/exposure/orientation so all 10 photos share consistent focus,
      // brightness and rotation — the key to a seam-free stitch. Best-effort.
      await _lockCamera(ctrl);
      await _initZoom(ctrl);
      _accel = accelerometerEventStream().listen(_onAccel);
      _gyro = gyroscopeEventStream().listen(_onGyro);
      setState(() => _cam = ctrl);
    } catch (e) {
      debugPrint('panorama photo camera init failed: $e');
      try {
        await ctrl?.dispose();
      } catch (e2) {
        debugPrint('panorama photo dispose after init-fail: $e2');
      }
      if (mounted) {
        setState(() => _error = 'לא ניתן לפתוח את המצלמה. בדקו הרשאות מצלמה.');
      }
    }
  }

  // Lock orientation, focus, then settle + bias exposure NEGATIVE and lock it, so
  // bright windows don't blow out and every shot stays consistent. Reused pattern
  // from the video capture (the AF/AE-lock approach proven there).
  Future<void> _lockCamera(CameraController ctrl) async {
    Future<void> tryLock(String what, Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        debugPrint('panorama photo lock $what failed: $e');
      }
    }

    await tryLock('orientation',
        () => ctrl.lockCaptureOrientation(DeviceOrientation.portraitUp));
    await tryLock('focus', () => ctrl.setFocusMode(FocusMode.locked));
    await tryLock(
        'exposure-auto', () => ctrl.setExposureMode(ExposureMode.auto));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    // Meter + lock at a NEUTRAL base (offset 0) so the whole sphere shares one
    // exposure — the HDR bracket then biases ± around this fixed base per shot.
    await tryLock('exposure-offset', () => ctrl.setExposureOffset(0.0));
    await tryLock(
        'exposure-lock', () => ctrl.setExposureMode(ExposureMode.locked));
  }

  // Prefer 0.5× ultra-wide (wider frame → more overlap → easier stitch). minZoom
  // < 1.0 means the device exposes the ultra-wide via zoom. Fail-soft: no
  // ultra-wide reachable → stay at 1× and tell the user.
  Future<void> _initZoom(CameraController ctrl) async {
    try {
      final minZoom = await ctrl.getMinZoomLevel();
      if (minZoom < 1.0) {
        _minZoom = minZoom;
        _ultraWide = true;
        await ctrl.setZoomLevel(minZoom);
      }
    } catch (e) {
      debugPrint('panorama photo zoom probe failed: $e');
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
      debugPrint('panorama photo setZoom failed: $e');
    }
  }

  void _onAccel(AccelerometerEvent e) {
    final m = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (m < 1e-3) return;
    _gx = e.x / m;
    _gy = e.y / m;
    _gz = e.z / m;
    _pitchDeg = math.asin(_gz.clamp(-1.0, 1.0)) * 180 / math.pi;
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
    _yawDeg += (yawRate * 180 / math.pi * dt).abs();
    _yawNotifier.value = _yawDeg;
  }

  double get _hfovDeg => _ultraWide ? _ultraWideHfovDeg : _normalHfovDeg;

  // Portrait recording → tall frame → vfov > hfov. aspectRatio is w/h, so the
  // vertical factor is 1/aspectRatio.
  double get _vfovDeg {
    final cam = _cam;
    final a =
        (cam != null && cam.value.isInitialized) ? cam.value.aspectRatio : 0.75;
    final factor = (a > 0) ? 1 / a : 4 / 3;
    return (_hfovDeg * factor).clamp(_hfovDeg, 180.0);
  }

  // How far (degrees) the user still needs to turn before the next shot. The
  // target heading for shot i is i*36°; we measure progress off the accumulated
  // gravity-projected yaw so it's robust to a little tilt.
  double get _degToNextShot {
    final target = _positions * _stepDeg;
    return target - _yawDeg;
  }

  Future<void> _takeShot() async {
    final cam = _cam;
    if (cam == null || _capturing || _building) return;
    if (_positions >= _shotCount) return;
    setState(() => _capturing = true);
    final group = _positions;
    // Freeze the heading/tilt for the whole bracket (the user holds still), so all
    // exposures of this position share one pose.
    final yaw = _yawDeg % 360;
    final pitch = _pitchDeg;
    try {
      for (final ev in _bracketEvs) {
        try {
          await cam.setExposureOffset(ev);
          // Let the sensor settle to the new bias before the shot.
          await Future<void>.delayed(const Duration(milliseconds: 220));
        } catch (_) {/* offset unsupported → identical frame, fusion no-ops */}
        final XFile shot = await cam.takePicture();
        _shotPaths.add(shot.path);
        _shotYaws.add(yaw);
        _shotPitches.add(pitch);
        _shotGroups.add(group);
      }
      // Restore the neutral base for the live preview / next position.
      try {
        await cam.setExposureOffset(0.0);
      } catch (_) {}
      _positions++;
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() => _capturing = false);
      if (_positions >= _shotCount) {
        await _build();
      }
    } catch (e) {
      debugPrint('panorama photo takePicture failed: $e');
      if (mounted) {
        setState(() => _capturing = false);
        _toast('הצילום נכשל. נסו שוב.');
      }
    }
  }

  void _undoLast() {
    if (_positions == 0 || _building || _capturing) return;
    // Remove the entire last bracket (all exposures of the last position).
    final lastGroup = _positions - 1;
    setState(() {
      while (_shotGroups.isNotEmpty && _shotGroups.last == lastGroup) {
        _shotPaths.removeLast();
        _shotYaws.removeLast();
        _shotPitches.removeLast();
        _shotGroups.removeLast();
      }
      _positions--;
    });
  }

  // Upload the photos to a fresh job and run the EXISTING server stitch. We send
  // KNOWN per-shot poses (yaw = measured heading, pitch ≈ level, hfov/vfov from
  // the lens) so the server projects deterministically — robust on blank walls
  // and honest about the covered arc (a full ring → 360). Poll until ready, then
  // pop a finished [PanoramaSweepResult].
  Future<void> _build() async {
    setState(() {
      _building = true;
      _buildError = null;
      _buildMsg = 'מתחילים לבנות את הסיור...';
    });

    final hfov = _hfovDeg;
    final vfov = _vfovDeg;
    final poses = <Map<String, double>>[
      for (var i = 0; i < _shotPaths.length; i++)
        {
          'yaw': _shotYaws[i],
          'pitch': _shotPitches[i],
          'hfov': hfov,
          'vfov': vfov,
          // Frames sharing a group are an exposure bracket → server fuses them.
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
        setState(() => _buildMsg =
            'מעלים את התמונות... (${i + 1}/${_shotPaths.length})');
      }

      if (!mounted) return;
      setState(() => _buildMsg = 'בונים את הסיור...');
      await AwsApiClient.instance.startPanoramaStitch(job.jobId);

      const maxPolls = 90; // ~3 min at 2 s
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
      debugPrint('panorama photo build failed: $e');
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

  // Retry the whole capture from scratch (the photos may have been the problem).
  void _retryFromError() {
    setState(() {
      _building = false;
      _buildError = null;
      _buildMsg = '';
      _shotPaths.clear();
      _shotYaws.clear();
      _shotPitches.clear();
      _shotGroups.clear();
      _positions = 0;
      _yawDeg = 0;
      _yawNotifier.value = 0;
      _lastGyroUs = 0;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 3200),
      content: Text(msg),
    ));
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _gyro?.cancel();
    _accel?.cancel();
    _yawNotifier.dispose();
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
          if (_cam != null && _cam!.value.isInitialized)
            _cover(_cam!)
          else if (_error != null)
            _errorState()
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // Live rotation guide: a ring with 10 ticks showing shots taken and the
          // current heading, plus big Hebrew coaching for the next action.
          if (_cam != null && _error == null && !_building)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 56, 12, 0),
                  child: ValueListenableBuilder<double>(
                    valueListenable: _yawNotifier,
                    builder: (_, __, ___) => _guide(),
                  ),
                ),
              ),
            ),

          // Top bar: close + 0.5×/1× toggle.
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
                      onTap: _building ? null : () => Navigator.of(context).pop(),
                      child: _circle(IconsaxPlusLinear.close_circle),
                    ),
                    const Spacer(),
                    if (_minZoom != null && !_building) _zoomToggle(),
                  ],
                ),
              ),
            ),
          ),

          // Overlap hint: a thin sliver of the PREVIOUS shot pinned to the screen
          // edge so the user lines up the next frame with an overlap.
          if (_cam != null && _error == null && !_building && _shotPaths.isNotEmpty)
            _overlapHint(),

          // Bottom: shutter + quality coaching + undo.
          if (_cam != null && _error == null && !_building)
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
                      _qualityLine(),
                      const SizedBox(height: 14),
                      _shutterRow(),
                    ],
                  ),
                ),
              ),
            ),

          if (_building) _buildOverlay(),
        ],
      ),
    );
  }

  Widget _guide() {
    final taken = _positions;
    final done = taken >= _shotCount;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _coachPill(
          done ? 'כל הצילומים הושלמו ✓' : 'צילום $taken מתוך $_shotCount',
          bg: done
              ? Colors.green.withValues(alpha: 0.85)
              : Colors.black.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 12),
        CustomPaint(
          size: const Size(200, 200),
          painter: _ShotRingPainter(
            taken: taken,
            total: _shotCount,
            headingDeg: _yawDeg % 360,
          ),
        ),
      ],
    );
  }

  Widget _qualityLine() {
    String text;
    final tooFast = _spinRate > 30;
    final remaining = _degToNextShot;
    if (_positions == 0) {
      text = 'עמדו במרכז, החזיקו ישר וצלמו את התמונה הראשונה.';
    } else if (_positions >= _shotCount) {
      text = 'מצוין! בונים את הסיור...';
    } else if (tooFast) {
      text = 'החזיקו את הטלפון יציב 🤳 ואז צלמו';
    } else if (remaining > 8) {
      text = 'סובבו ~${remaining.round()}° ימינה — שמרו חפיפה עם הקודם';
    } else {
      text = 'מצוין — צלמו עכשיו 📸';
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

  Widget _shutterRow() {
    return Row(
      children: [
        // Undo last shot (so a bad frame isn't stuck in the sequence).
        SizedBox(
          width: 56,
          child: _shotPaths.isEmpty
              ? const SizedBox.shrink()
              : GestureDetector(
                  onTap: _undoLast,
                  child: _circle(IconsaxPlusLinear.undo),
                ),
        ),
        Expanded(
          child: Center(
            child: GestureDetector(
              onTap: _capturing ? null : _takeShot,
              child: Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 4),
                ),
                child: _capturing
                    ? const Padding(
                        padding: EdgeInsets.all(22),
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: Colors.white),
                      )
                    : Container(
                        margin: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: AppColors.coral,
                          shape: BoxShape.circle,
                        ),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 56),
      ],
    );
  }

  // A narrow sliver of the previous photo pinned to the LEFT edge (RTL → the
  // "previous" side as the user turns right), so they overlap the next frame with
  // the same scene — the visual overlap cue the stitch needs.
  Widget _overlapHint() {
    final prev = _shotPaths.last;
    return Positioned(
      top: 0,
      bottom: 0,
      left: 0,
      width: 46,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.45,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.centerLeft,
              maxWidth: double.infinity,
              child: Image.file(
                // Show the photo's right edge as the overlap reference.
                File(prev),
                fit: BoxFit.fitHeight,
                alignment: Alignment.centerRight,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
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
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              height: 1.3,
              fontWeight: FontWeight.w900),
        ),
      );

  Widget _zoomToggle() {
    return GestureDetector(
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
            Text(
              _ultraWide ? '0.5×' : '1×',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900),
            ),
            const SizedBox(width: 8),
            Text(
              _ultraWide ? 'רחב' : 'רגיל',
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

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

  Widget _errorState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(IconsaxPlusLinear.camera_slash,
                color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            Text(_error ?? 'שגיאת מצלמה',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('סגור'),
            ),
          ],
        ),
      );
}

// Live capture ring: [total] ticks around a circle, [taken] of them filled green;
// a moving dot marks the current heading so the user sees where the next shot
// lands. Turns fully green when all shots are done.
class _ShotRingPainter extends CustomPainter {
  _ShotRingPainter({
    required this.taken,
    required this.total,
    required this.headingDeg,
  });
  final int taken;
  final int total;
  final double headingDeg;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 16;

    // Base ring.
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..color = Colors.white24);

    // Filled arc = fraction of shots taken.
    final frac = (taken / total).clamp(0.0, 1.0);
    final done = taken >= total;
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        2 * math.pi * frac,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round
          ..color = done ? Colors.greenAccent : AppColors.primary);

    // Ticks: one per shot slot. Filled = captured.
    for (var i = 0; i < total; i++) {
      final ang = -math.pi / 2 + (2 * math.pi * i / total);
      final p = c + Offset(math.cos(ang), math.sin(ang)) * r;
      canvas.drawCircle(
          p,
          6,
          Paint()
            ..color =
                i < taken ? Colors.greenAccent : Colors.white.withValues(alpha: 0.6));
    }

    // Heading dot: where the camera currently points on the ring.
    final hAng = -math.pi / 2 + (headingDeg * math.pi / 180);
    final hp = c + Offset(math.cos(hAng), math.sin(hAng)) * r;
    canvas.drawCircle(hp, 9, Paint()..color = AppColors.coral);
    canvas.drawCircle(
        hp,
        9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white);

    // Center label.
    final label = done ? '✓' : '$taken/$total';
    final tp = TextPainter(
      text: TextSpan(
          text: label,
          style: TextStyle(
              color: done ? Colors.greenAccent : Colors.white,
              fontSize: done ? 40 : 30,
              fontWeight: FontWeight.w900)),
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _ShotRingPainter old) =>
      old.taken != taken || old.total != total || old.headingDeg != headingDeg;
}
