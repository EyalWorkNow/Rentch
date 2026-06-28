import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:image/image.dart' as img;
import 'package:sensors_plus/sensors_plus.dart';

/// What the guided sweep returns to the caller: a finished, server-stitched
/// equirectangular panorama already living at a network URL, plus the angle of
/// view the stitch reported. The caller adds this straight as a tour node — no
/// extra upload, no gallery. Null pop = the user backed out without finishing.
class PanoramaSweepResult {
  const PanoramaSweepResult({
    required this.imageUrl,
    required this.haov,
    required this.vaov,
    this.poses = const [],
  });

  final String imageUrl;
  final double haov;
  final double vaov;

  /// Per-frame capture pose, PARALLEL to the uploaded frames (poses[i] ↔ f{i}),
  /// each `{yaw, pitch, hfov, vfov}` in DEGREES. Empty when poses weren't sent.
  final List<Map<String, double>> poses;
}

/// Guided in-app horizontal 360° sweep. The user does three passes — middle,
/// tilted up, tilted down — and the app silently samples overlapping frames as
/// they turn. When they finish, the screen runs the WHOLE server stitch itself
/// (create job → upload frames → start OpenCV stitch → poll until ready) behind
/// a progress overlay, and pops a finished [PanoramaSweepResult] (a stitched
/// equirectangular panorama URL + its angle of view). The caller adds it as a
/// tour node directly — there is no gallery and no second upload step.
///
/// Capture is **gyroscope-gated**: a frame is kept once the phone has actually
/// rotated ~one step (360° / framesInRow), NOT on a fixed timer — so the sweep
/// can't finish before the user completes a turn. Falls back to a timer if no
/// gyro is available.
///
/// Why no zenith/nadir rows: cv2.Stitcher (PANORAMA mode) can only register a
/// horizontal cylinder; straight-up/down frames share no overlap and break the
/// stitch. True top/bottom needs a sensor-driven equirectangular pipeline (later).
class PanoramaSweepCaptureScreen extends StatefulWidget {
  const PanoramaSweepCaptureScreen({super.key});

  @override
  State<PanoramaSweepCaptureScreen> createState() =>
      _PanoramaSweepCaptureScreenState();
}

class _Row {
  const _Row(this.title, this.hint, this.frames);
  final String title;
  final String hint;
  final int frames;
}

// 42 frames over 3 horizontal rows. stepDeg per row = 360 / frames.
const _rows = <_Row>[
  _Row('שורה אמצעית', 'החזק את הטלפון ישר (אנכית) וסובב סיבוב מלא במקום', 18),
  _Row('שורה עליונה', 'הטה מעט כלפי מעלה (~30°) וסובב שוב סיבוב מלא', 12),
  _Row('שורה תחתונה', 'הטה מעט כלפי מטה (~30°) וסובב שוב סיבוב מלא', 12),
];

const _total = 42; // sum of _rows[].frames — keep in sync
const _sampleEveryMs = 700; // timer fallback only (no gyro)

// Per-row tilt (pitch) in DEGREES, parallel to _rows: middle 0, up +30, down −30.
// Matches the row hints ("הטה מעט כלפי מעלה/מטה (~30°)") and the horizon guide.
const _rowPitchDeg = <double>[0, 30, -30];
// Camera horizontal field of view in degrees. The `camera` plugin doesn't expose
// it, so use a sane default for a typical phone back camera. Tunable here; vfov is
// derived per-frame from the captured aspect (vfov = hfov * frameHeight/frameWidth).
const _defaultHfovDeg = 65.0;
// Gate capture on a near-STILL phone: above this the frame is smeared. Tight
// (was 90) because we now measure true world-yaw rate, so frames land between
// turns instead of mid-motion.
const _maxSpinDegPerSec = 14;
const _minStepGapMs = 120; // encode back-pressure floor between captures

class _PanoramaSweepCaptureScreenState
    extends State<PanoramaSweepCaptureScreen> {
  CameraController? _cam;
  StreamSubscription<GyroscopeEvent>? _gyro;
  StreamSubscription<AccelerometerEvent>? _accel;
  String? _error;
  // Stitch phase (after capture): a full-screen "building your tour" overlay.
  bool _stitching = false;
  String _stitchMsg = '';
  String? _stitchError; // set → show retry, never a crash or silent gallery
  bool _running = false; // actively sampling the current row
  bool _converting = false; // a frame is mid-encode (drop stream frames)
  bool _flash = false; // brief visual cue per captured frame (no shutter sound)
  int _rowIndex = 0;
  int _rowDone = 0; // frames captured in the current row
  final List<String> _frames = []; // all rows
  // Capture pose per kept frame, PARALLEL to _frames (poses[i] ↔ _frames[i]):
  // {yaw, pitch, hfov, vfov} in degrees. Sent to the backend for deterministic
  // pose-assisted stitching instead of fragile feature-matching.
  final List<Map<String, double>> _poses = [];
  final _clock = Stopwatch();
  int _lastSampleMs = 0;

  // gyro yaw integration (per row)
  double _yawDeg = 0; // |accumulated| yaw since this row started
  double _lastCaptureYaw = 0; // yaw at the previous captured frame
  double _spinRate = 0; // deg/s about world-up (for too-fast / stalled hints)
  int _lastGyroUs = 0;
  // Gravity unit vector in device frame, from the accelerometer. Lets us project
  // the gyro onto world-up so yaw is correct even when the phone is tilted ~30°.
  double _gx = 0, _gy = -1, _gz = 0; // default: upright portrait (gravity ≈ -Y)
  int _runStartMs = 0; // when the current row's sweep started
  bool _gotGyro = false; // any gyro event ever seen
  final _yawNotifier = ValueNotifier<double>(0); // drives the live ring/hint

  double get _stepDeg => 360 / _rows[_rowIndex].frames;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    // Lock portrait for a stable preview/UI. Yaw no longer assumes an upright
    // phone: we project the gyro onto the gravity (world-up) axis (_onAccel).
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.portraitUp]);
    _clock.start();
    // Self-check the gravity-projection math: a pure horizontal turn of an
    // upright portrait phone (gyro = +Y, gravity = -Y) must project to a yaw
    // rate of magnitude 1 (full turn registers), while a screen-normal twist
    // (gyro = +Z) must project to ~0 (the old buggy axis).
    assert(() {
      double dot(List<double> a, List<double> b) =>
          a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
      final gravity = [0.0, -1.0, 0.0]; // upright portrait
      final yawCapture = dot([0.0, 1.0, 0.0], gravity).abs(); // turning
      final spinNormal = dot([0.0, 0.0, 1.0], gravity).abs(); // screen twist
      return (yawCapture - 1).abs() < 1e-9 && spinNormal < 1e-9;
    }());
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
      // veryHigh for crisp stitch input. We capture only when near-still (the
      // tight spin gate), so the heavier YUV→JPEG encode doesn't fight a moving
      // preview. ponytail: encode on the main isolate; if it janks, → compute().
      ctrl =
          CameraController(back, ResolutionPreset.veryHigh, enableAudio: false);
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      // Lock focus + exposure + orientation so frames don't hunt/refocus or
      // re-expose mid-sweep — the biggest source of blur and seams. Each lock
      // is best-effort: some devices reject one mode but the rest still help.
      await _lockCamera(ctrl);
      await ctrl.startImageStream(_onFrame);
      _gyro = gyroscopeEventStream().listen(_onGyro);
      _accel = accelerometerEventStream().listen(_onAccel);
      setState(() => _cam = ctrl);
    } catch (e) {
      debugPrint('panorama camera init failed: $e');
      // Dispose the half-built controller so the failure doesn't leak it.
      try {
        await ctrl?.dispose();
      } catch (e2) {
        debugPrint('panorama controller dispose after init-fail: $e2');
      }
      if (mounted) {
        setState(() => _error = 'לא ניתן לפתוח את המצלמה. בדוק הרשאות מצלמה.');
      }
    }
  }

  // Best-effort focus/exposure/orientation lock. Wrapped per-call: a device that
  // rejects one mode still gets the others, and we never abort init over it.
  Future<void> _lockCamera(CameraController ctrl) async {
    Future<void> tryLock(String what, Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        debugPrint('panorama lock $what failed: $e');
      }
    }

    await tryLock('orientation',
        () => ctrl.lockCaptureOrientation(DeviceOrientation.portraitUp));
    await tryLock('focus', () => ctrl.setFocusMode(FocusMode.locked));
    await tryLock('exposure', () => ctrl.setExposureMode(ExposureMode.locked));
  }

  // Track gravity (world-up) in the device frame so we can find the true yaw
  // axis regardless of tilt. The accelerometer at rest reads ≈ +g along up, so
  // its unit vector IS the world-up direction expressed in device coordinates.
  void _onAccel(AccelerometerEvent e) {
    final m = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (m < 1e-3) return; // free-fall / bogus sample — keep last good gravity
    _gx = e.x / m;
    _gy = e.y / m;
    _gz = e.z / m;
  }

  // Integrate angular velocity about WORLD-UP. The yaw rate is the component of
  // the gyro vector along the gravity unit vector: yawRate = gyro · gravityUnit.
  // For an upright portrait phone gravity ≈ -Y, so this picks up e.y (a real
  // horizontal turn), NOT e.z (screen-normal, ≈0 during a turn → the old ~3×
  // under-count). Stays correct when tilted ~30° for rows 2/3, where any single
  // fixed axis under-counts by ~cos30°.
  void _onGyro(GyroscopeEvent e) {
    _gotGyro = true;
    final now = _clock.elapsedMicroseconds;
    final last = _lastGyroUs;
    _lastGyroUs = now;
    if (!_running || last == 0) {
      _spinRate = 0;
      return;
    }
    final dt = (now - last) / 1e6;
    // dot(gyro, gravityUnit) — angular velocity (rad/s) about world-up.
    final yawRate = e.x * _gx + e.y * _gy + e.z * _gz;
    _spinRate = yawRate.abs() * 180 / math.pi;
    _yawDeg += (yawRate * 180 / math.pi * dt).abs(); // abs → direction-agnostic
    _yawNotifier.value = _yawDeg;
  }

  void _onFrame(CameraImage image) async {
    if (!_running || _converting) return;
    final row = _rows[_rowIndex];
    if (_rowDone >= row.frames) return;

    final sinceSample = _clock.elapsedMilliseconds - _lastSampleMs;
    // If no gyro showed up within 1.5s, degrade to the old timer gate.
    final useTimer =
        !_gotGyro && (_clock.elapsedMilliseconds - _runStartMs) > 1500;
    if (useTimer) {
      if (sinceSample < _sampleEveryMs) return;
    } else {
      if (_spinRate > _maxSpinDegPerSec) return; // too fast → blurry
      if (_yawDeg - _lastCaptureYaw < _stepDeg) return; // not turned enough
      if (sinceSample < _minStepGapMs) return; // encode back-pressure
    }

    _converting = true;
    try {
      final jpg = _encode(image);
      final file = File(
          '${Directory.systemTemp.path}/pano_${_frames.length}_${_clock.elapsedMicroseconds}.jpg');
      await file.writeAsBytes(jpg);
      _frames.add(file.path);
      // Record the pose for THIS frame, kept strictly parallel to _frames. yaw is
      // the gravity-projected heading the ring uses; pitch is the row tilt; vfov
      // is derived from the captured portrait aspect (h>w → vfov > hfov).
      final aspect = image.width == 0 ? 1.0 : image.height / image.width;
      _poses.add({
        'yaw': (_yawDeg % 360 + 360) % 360,
        'pitch': _rowPitchDeg[_rowIndex],
        'hfov': _defaultHfovDeg,
        'vfov': _defaultHfovDeg * aspect,
      });
      assert(_poses.length == _frames.length,
          'pose/frame misalignment: ${_poses.length} poses vs ${_frames.length} frames');
      _lastCaptureYaw = _yawDeg;
      _lastSampleMs = _clock.elapsedMilliseconds;
      HapticFeedback.lightImpact();
      if (mounted) {
        setState(() {
          _rowDone++;
          _flash = true;
        });
        Future.delayed(const Duration(milliseconds: 120), () {
          if (mounted) setState(() => _flash = false);
        });
        if (_rowDone >= row.frames) setState(() => _running = false);
      }
    } catch (e) {
      debugPrint('panorama frame encode/write skipped: $e'); // drop, keep sweeping
    } finally {
      _converting = false;
    }
  }

  void _runRow() {
    if (_cam == null) return;
    _yawDeg = 0;
    _lastCaptureYaw = 0;
    _lastGyroUs = 0;
    _runStartMs = _clock.elapsedMilliseconds;
    _yawNotifier.value = 0;
    setState(() => _running = true);
  }

  void _nextRow() {
    if (_rowIndex < _rows.length - 1) {
      setState(() {
        _rowIndex++;
        _rowDone = 0;
      });
    }
  }

  // Done sweeping → build the panorama on the server, then pop the finished
  // result. Needs a few frames to register a 360 cylinder; below that we coach
  // the user to keep turning rather than ship a broken stitch.
  Future<void> _finish() async {
    _running = false;
    if (_frames.length < 6) {
      // Reuse the error overlay (with its "נסה שוב" that returns to capture) to
      // coach them to keep turning instead of shipping a broken stitch.
      setState(() {
        _stitchError =
            'צריך עוד תמונות כדי לבנות סיבוב שלם. סובב עוד קצת ונסה שוב.';
        _stitching = true;
      });
      return;
    }
    await _stitchAndReturn();
  }

  // Full server stitch, fully in-app: create job → upload every frame → start
  // the OpenCV stitch → poll until ready. Any failure surfaces a clear Hebrew
  // message + "נסה שוב"; it NEVER drops the user into the gallery or crashes.
  Future<void> _stitchAndReturn() async {
    // Stop the live camera work so encoding doesn't fight the uploads.
    setState(() {
      _running = false;
      _stitching = true;
      _stitchError = null;
      _stitchMsg = 'מתחילים לבנות את הסיור...';
    });
    final frames = List<String>.from(_frames);
    // Snapshot poses parallel to the frame snapshot so f{i} ↔ poses[i] survives
    // any later mutation. Asserted equal-length before we send them on.
    final poses = List<Map<String, double>>.from(_poses);
    assert(poses.length == frames.length,
        'pose/frame misalignment at stitch: ${poses.length} vs ${frames.length}');
    try {
      // A property doesn't exist yet while the landlord is still filling the
      // draft, so group this job under a one-off id; the server only uses it as
      // a folder key for the frames.
      final groupId = 'draft_${DateTime.now().millisecondsSinceEpoch}';
      final job = await AwsApiClient.instance.createPanoramaJob(
        propertyId: groupId,
        frameCount: frames.length,
        poses: poses,
      );
      if (job == null || job.uploadUrls.length < frames.length) {
        _failStitch('לא הצלחנו להתחיל את העיבוד. בדוק את החיבור לאינטרנט.');
        return;
      }

      for (var i = 0; i < frames.length; i++) {
        if (!mounted) return;
        setState(() => _stitchMsg = 'מעלים תמונות... ${i + 1}/${frames.length}');
        final ok = await AwsApiClient.instance
            .uploadToPresignedUrl(job.uploadUrls[i], frames[i]);
        if (!ok) {
          _failStitch('ההעלאה נכשלה באמצע. בדוק את החיבור ונסה שוב.');
          return;
        }
      }

      if (!mounted) return;
      setState(() => _stitchMsg = 'מחברים את התמונות לסיבוב מלא...');
      await AwsApiClient.instance.startPanoramaStitch(job.jobId);

      // Poll until ready (or failed). OpenCV stitching of ~40 frames takes a
      // little while; give it generous, patient time with clear progress text.
      const maxPolls = 60; // ~2 min at 2 s
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
          _failStitch(status.error.isNotEmpty
              ? 'העיבוד נכשל. נסה לצלם שוב, לאט ובאור טוב.'
              : 'העיבוד נכשל. נסה לצלם שוב.');
          return;
        }
        setState(() => _stitchMsg = 'מחברים את התמונות לסיבוב מלא...');
      }
      _failStitch('העיבוד לוקח יותר מדי זמן. נסה שוב מאוחר יותר.');
    } catch (e) {
      debugPrint('panorama stitch failed: $e');
      _failStitch('משהו השתבש. בדוק את החיבור ונסה שוב.');
    }
  }

  void _failStitch(String msg) {
    if (!mounted) return;
    setState(() {
      _stitchError = msg;
      _stitching = true;
    });
  }

  // From the error overlay: go back to capture and let them keep/redo the sweep.
  void _retryFromError() {
    setState(() {
      _stitching = false;
      _stitchError = null;
      _stitchMsg = '';
    });
  }

  @override
  void dispose() {
    _running = false;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _gyro?.cancel();
    _accel?.cancel();
    _yawNotifier.dispose();
    // Delete the temp JPEG frames we wrote during the sweep — they'd otherwise
    // leak in systemTemp until the OS clears it. Fire-and-forget; errors logged.
    for (final path in _frames) {
      File(path).delete().catchError((Object e) {
        debugPrint('panorama temp frame delete failed: $e');
        return File(path);
      });
    }
    final c = _cam;
    if (c != null) {
      // stop the stream before disposing, else the plugin throws on teardown
      c.stopImageStream().catchError((_) {}).whenComplete(c.dispose);
    }
    super.dispose();
  }

  bool get _isLastRow => _rowIndex == _rows.length - 1;
  bool get _rowComplete => _rowDone >= _rows[_rowIndex].frames;

  @override
  Widget build(BuildContext context) {
    final row = _rows[_rowIndex];
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

          if (_cam != null && _error == null) _SweepGuide(rowIndex: _rowIndex),

          // live rotation ring — the primary "how far have I turned" feedback
          if (_cam != null && _error == null && _running)
            Center(
              child: ValueListenableBuilder<double>(
                valueListenable: _yawNotifier,
                builder: (_, yaw, __) => CustomPaint(
                  size: const Size(220, 220),
                  painter: _RingPainter(
                    yawDeg: yaw,
                    stepDeg: _stepDeg,
                    done: _rowDone,
                    target: row.frames,
                  ),
                ),
              ),
            ),

          // capture flash — the visual stand-in for the (now silent) shutter
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _flash ? 1 : 0,
              duration: const Duration(milliseconds: 90),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 4),
                ),
              ),
            ),
          ),

          // top: close + row indicator + row dots
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: _circle(IconsaxPlusLinear.close_circle),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                              '${row.title} · ${_rowIndex + 1}/${_rows.length}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _RowDots(rowIndex: _rowIndex, done: _rowDone, rows: _rows),
                  ],
                ),
              ),
            ),
          ),

          if (_cam != null && _error == null && !_stitching)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // live coaching while sweeping, static instruction otherwise
                      if (_running)
                        ValueListenableBuilder<double>(
                          valueListenable: _yawNotifier,
                          builder: (_, __, ___) => _hint(_coachText()),
                        )
                      else
                        _hint(row.hint),
                      const SizedBox(height: 12),
                      Text('${_frames.length}/$_total פריימים',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 14),
                      _actionButton(),
                    ],
                  ),
                ),
              ),
            ),

          // Full-screen "building your tour" / error overlay — covers everything.
          if (_stitching) _stitchOverlay(),
        ],
      ),
    );
  }

  // Big, calm, jargon-free overlay shown while the server builds the panorama,
  // and the clear retry screen if anything fails.
  Widget _stitchOverlay() {
    final hasError = _stitchError != null;
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
                  hasError ? 'לא הצלחנו לבנות את הסיור' : 'בונים את הסיור שלך',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                Text(
                  hasError
                      ? _stitchError!
                      : '$_stitchMsg\n\nאפשר להמתין כמה רגעים — אל תסגרו את המסך.',
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
                      label: const Text('נסה שוב',
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

  String _coachText() {
    // Frames are grabbed when the phone is near-STILL, so coach stop-and-go:
    // turn a step, pause for the snap, repeat.
    if (!_gotGyro) return 'סובב צעד · עצור · חזור על כך סביב';
    if (_spinRate > _maxSpinDegPerSec) return 'עצור רגע כדי לצלם 🐢';
    if (_yawDeg - _lastCaptureYaw >= _stepDeg) return 'יופי — עצור רגע';
    return 'סובב צעד קטן והמשך';
  }

  Widget _actionButton() {
    if (_running) {
      return _wideButton(
        filled: false,
        icon: IconsaxPlusLinear.pause,
        text: 'עצור',
        onTap: () => setState(() => _running = false),
      );
    }
    if (!_rowComplete) {
      return _wideButton(
        filled: true,
        icon: IconsaxPlusBold.camera,
        text: _rowDone > 0 ? 'המשך שורה' : 'התחל ${_rows[_rowIndex].title}',
        onTap: _runRow,
      );
    }
    // row complete → next row, or finish on the last row
    if (!_isLastRow) {
      return _wideButton(
        filled: true,
        icon: IconsaxPlusLinear.arrow_left_2,
        text: 'המשך ל${_rows[_rowIndex + 1].title}',
        onTap: _nextRow,
      );
    }
    return _wideButton(
      filled: true,
      icon: IconsaxPlusLinear.tick_circle,
      text: 'סיום',
      onTap: _finish,
    );
  }

  Widget _wideButton(
      {required bool filled,
      required IconData icon,
      required String text,
      required VoidCallback onTap}) {
    final child = filled
        ? FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: onTap,
            icon: Icon(icon),
            label:
                Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
          )
        : OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: onTap,
            icon: Icon(icon),
            label:
                Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
          );
    return Row(children: [
      Expanded(child: child),
      if (!_running && _frames.length >= 2) ...[
        const SizedBox(width: 10),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white30),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          ),
          onPressed: _finish,
          child:
              const Text('סיים', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ]);
  }

  Widget _hint(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
      );

  Widget _circle(IconData icon) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
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
}

/// CameraImage → JPEG bytes. Handles iOS BGRA8888 and Android YUV420, honouring
/// each plane's row/pixel stride (planes are often padded). Per-pixel rather than
/// a packed-buffer memcpy: simpler and correct regardless of padding.
Uint8List _encode(CameraImage image) {
  final w = image.width, h = image.height;
  final out = img.Image(width: w, height: h);
  if (image.format.group == ImageFormatGroup.bgra8888) {
    final p = image.planes[0];
    final stride = p.bytesPerRow;
    final b = p.bytes;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * stride + x * 4;
        out.setPixelRgb(x, y, b[i + 2], b[i + 1], b[i]); // BGRA → RGB
      }
    }
  } else {
    final yP = image.planes[0], uP = image.planes[1], vP = image.planes[2];
    final yB = yP.bytes, uB = uP.bytes, vB = vP.bytes;
    final yStride = yP.bytesPerRow;
    final uvStride = uP.bytesPerRow;
    final uvPix = uP.bytesPerPixel ?? 1;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final yi = y * yStride + x;
        final uvi = (y >> 1) * uvStride + (x >> 1) * uvPix;
        final yv = yB[yi];
        final u = uB[uvi] - 128;
        final v = vB[uvi] - 128;
        final r = (yv + 1.370705 * v).round().clamp(0, 255);
        final g = (yv - 0.337633 * u - 0.698001 * v).round().clamp(0, 255);
        final bb = (yv + 1.732446 * u).round().clamp(0, 255);
        out.setPixelRgb(x, y, r, g, bb);
      }
    }
  }
  return img.encodeJpg(out, quality: 85);
}

// Live rotation ring: filled arc = how far you've turned; ticks = frame slots.
class _RingPainter extends CustomPainter {
  _RingPainter(
      {required this.yawDeg,
      required this.stepDeg,
      required this.done,
      required this.target});
  final double yawDeg;
  final double stepDeg;
  final int done;
  final int target;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 8;
    final rect = Rect.fromCircle(center: c, radius: r);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = Colors.white24;
    final prog = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = AppColors.primary;
    canvas.drawCircle(c, r, track);
    final frac = (yawDeg / 360).clamp(0.0, 1.0);
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * frac, false, prog);

    // tick at each captured-frame angle slot
    final tick = Paint()
      ..color = Colors.white54
      ..strokeWidth = 2;
    for (var a = 0.0; a < 360; a += stepDeg) {
      final ang = -math.pi / 2 + a * math.pi / 180;
      final p1 = c + Offset(math.cos(ang), math.sin(ang)) * (r - 6);
      final p2 = c + Offset(math.cos(ang), math.sin(ang)) * (r + 6);
      canvas.drawLine(p1, p2, tick);
    }

    final tp = TextPainter(
      text: TextSpan(
          text: '$done/$target',
          style: const TextStyle(
              color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.yawDeg != yawDeg || old.done != done;
}

// Per-row capture progress as a dot strip — green = done, current is wide.
class _RowDots extends StatelessWidget {
  const _RowDots(
      {required this.rowIndex, required this.done, required this.rows});
  final int rowIndex;
  final int done;
  final List<_Row> rows;
  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(rows.length, (i) {
          final complete =
              i < rowIndex || (i == rowIndex && done >= rows[i].frames);
          final current = i == rowIndex;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: current ? 26 : 10,
            height: 10,
            decoration: BoxDecoration(
              color: complete
                  ? Colors.greenAccent
                  : current
                      ? AppColors.primary
                      : Colors.white24,
              borderRadius: BorderRadius.circular(999),
            ),
          );
        }),
      );
}

// Bold horizon + centre line. The horizon shifts per row to cue the tilt.
class _SweepGuide extends StatelessWidget {
  const _SweepGuide({required this.rowIndex});
  final int rowIndex;
  @override
  Widget build(BuildContext context) => IgnorePointer(
        child:
            CustomPaint(painter: _SweepPainter(rowIndex), size: Size.infinite),
      );
}

class _SweepPainter extends CustomPainter {
  _SweepPainter(this.rowIndex);
  final int rowIndex;
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    // middle→centre; up→lower (look up); down→higher (look down).
    const dys = [0.5, 0.66, 0.34];
    final cy = size.height * dys[rowIndex];
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.7)
      ..strokeWidth = 2.5;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), p);
    canvas.drawLine(Offset(cx, cy - 40), Offset(cx, cy + 40), p);
  }

  @override
  bool shouldRepaint(covariant _SweepPainter old) => old.rowIndex != rowIndex;
}
