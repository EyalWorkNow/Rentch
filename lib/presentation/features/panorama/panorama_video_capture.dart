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
import 'package:video_compress/video_compress.dart';

/// The SIMPLEST 360° capture for an older, non-technical landlord: record a
/// short video while turning ONCE on the spot. The app records full-screen video
/// and, in parallel, samples a gravity-projected yaw/pitch pose at ~15 Hz into a
/// [poseTimeline]. On stop it transcodes to a small mp4, hands the video + the
/// pose timeline to the server (which extracts sharp keyframes and stitches via
/// the poses — built by another agent), polls until ready, and pops a finished
/// [PanoramaSweepResult] (a stitched equirectangular URL + angle of view). The
/// caller adds it as a tour node EXACTLY like the frame-by-frame sweep result —
/// the tour/node flow is unchanged.
///
/// Pose is gravity-projected (not a fixed axis): the accelerometer gives the
/// world-up unit vector in the device frame, and `yawRate = gyro · gravityUnit`
/// integrates to a correct heading even if the phone is tilted. Pitch comes from
/// the same gravity vector. This mirrors the math proven in
/// panorama_sweep_capture.dart.
class PanoramaVideoCaptureScreen extends StatefulWidget {
  const PanoramaVideoCaptureScreen({super.key});

  @override
  State<PanoramaVideoCaptureScreen> createState() =>
      _PanoramaVideoCaptureScreenState();
}

// Camera horizontal field of view in degrees. The `camera` plugin doesn't expose
// it, so use a sane default for a typical phone back camera; vfov is derived from
// the recording aspect (portrait → vfov > hfov).
const _defaultHfovDeg = 65.0;
const _poseSampleMs = 66; // ~15 Hz pose sampling
const _minRecordMs = 12000; // need at least one real, slow full turn
const _maxRecordMs = 90000; // hard cap → auto-stop so files stay sane
const _maxUploadBytes = 40 * 1024 * 1024; // abort if transcode is still huge

class _PanoramaVideoCaptureScreenState
    extends State<PanoramaVideoCaptureScreen> {
  CameraController? _cam;
  StreamSubscription<GyroscopeEvent>? _gyro;
  StreamSubscription<AccelerometerEvent>? _accel;
  Timer? _poseTimer;
  Timer? _capTimer; // hard-cap auto-stop
  String? _error;

  bool _recording = false;
  bool _building = false; // transcode → upload → stitch → poll overlay

  // Ultra-wide (0.5×) state. _minZoom is null when no ultra-wide is reachable
  // (toggle stays hidden). _ultraWide tracks the current lens choice.
  double? _minZoom;
  bool _ultraWide = false;
  String _buildMsg = '';
  String? _buildError; // set → show retry, never crash

  // Pose integration (gravity-projected). Same approach as the sweep screen.
  final _clock = Stopwatch(); // ms since record start
  double _yawDeg = 0; // accumulated |yaw| since record start
  double _spinRate = 0; // deg/s about world-up (for "slow down" coaching)
  int _lastGyroUs = 0;
  double _gx = 0, _gy = -1, _gz = 0; // gravity unit vector; default upright portrait
  double _pitchDeg = 0; // current tilt from gravity

  // The shared contract: {tMs, yaw (0..360), pitch} in DEGREES, monotonic tMs.
  final List<Map<String, double>> _poseTimeline = [];
  final _yawNotifier = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    // Self-check the gravity-projection math: a pure horizontal turn of an
    // upright portrait phone (gyro = +Y, gravity = -Y) must project to a yaw
    // rate of magnitude 1, while a screen-normal twist (gyro = +Z) projects ~0.
    assert(() {
      double dot(List<double> a, List<double> b) =>
          a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
      final gravity = [0.0, -1.0, 0.0];
      final yawTurn = dot([0.0, 1.0, 0.0], gravity).abs();
      final twist = dot([0.0, 0.0, 1.0], gravity).abs();
      return (yawTurn - 1).abs() < 1e-9 && twist < 1e-9;
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
      // high = 720p (≤1080p): sharp enough for keyframe extraction, light enough
      // to record + transcode reliably on an older phone.
      ctrl = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      // Lock focus/exposure/orientation so frames don't hunt or re-expose
      // mid-turn — the biggest source of blur. Best-effort per lock.
      await _lockCamera(ctrl);
      // Prefer the ultra-wide (0.5×) view: it captures more of the room in one
      // turn. Query zoom range; if the device exposes sub-1.0 zoom there's an
      // ultra-wide reachable — default to it and surface a toggle. Fail-soft.
      await _initZoom(ctrl);
      _accel = accelerometerEventStream().listen(_onAccel);
      _gyro = gyroscopeEventStream().listen(_onGyro);
      setState(() => _cam = ctrl);
    } catch (e) {
      debugPrint('panorama video camera init failed: $e');
      try {
        await ctrl?.dispose();
      } catch (e2) {
        debugPrint('panorama video dispose after init-fail: $e2');
      }
      if (mounted) {
        setState(() => _error = 'לא ניתן לפתוח את המצלמה. בדקו הרשאות מצלמה.');
      }
    }
  }

  Future<void> _lockCamera(CameraController ctrl) async {
    Future<void> tryLock(String what, Future<void> Function() f) async {
      try {
        await f();
      } catch (e) {
        debugPrint('panorama video lock $what failed: $e');
      }
    }

    await tryLock('orientation',
        () => ctrl.lockCaptureOrientation(DeviceOrientation.portraitUp));
    await tryLock('focus', () => ctrl.setFocusMode(FocusMode.locked));

    // EXPOSURE — the old code locked instantly on the very first metered frame,
    // which is usually blown out (the preview hasn't settled yet). Instead:
    //   1) Let auto-exposure run and settle BEFORE we lock (short delay).
    //   2) Bias modestly NEGATIVE (-1.0..-1.5 EV, clamped to device range) so
    //      bright rooms/windows don't blow out the highlights.
    //   3) Lock so it stays CONSISTENT across the whole sweep (no per-frame
    //      flicker between keyframes).
    // Every step is best-effort: an unsupported API just falls through.
    await tryLock('exposure-auto',
        () => ctrl.setExposureMode(ExposureMode.auto));
    // Give the metering ~600ms to converge on a sane exposure for the room.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    await tryLock('exposure-offset', () async {
      final minEv = await ctrl.getMinExposureOffset();
      final maxEv = await ctrl.getMaxExposureOffset();
      // Aim for -1.25 EV; clamp into whatever the device actually supports.
      // If the device reports no range (min==max==0) this resolves to 0 → no-op.
      final target = (-1.25).clamp(minEv, maxEv);
      await ctrl.setExposureOffset(target);
    });
    // Lock AFTER settling + biasing so the value we just metered is held steady.
    await tryLock('exposure-lock',
        () => ctrl.setExposureMode(ExposureMode.locked));
  }

  // 0.5× ultra-wide support. `getMinZoomLevel()` < 1.0 means the device exposes
  // the ultra-wide lens via zoom; default to it (wider room shot) and show the
  // 0.5×/1× toggle. If min zoom >= 1.0 there's no ultra-wide reachable → keep
  // the toggle hidden (no dead button). Fail-soft on any unsupported API.
  Future<void> _initZoom(CameraController ctrl) async {
    try {
      final minZoom = await ctrl.getMinZoomLevel();
      if (minZoom < 1.0) {
        _minZoom = minZoom;
        _ultraWide = true;
        await ctrl.setZoomLevel(minZoom); // default to the wider view
      }
    } catch (e) {
      debugPrint('panorama video zoom probe failed: $e');
      _minZoom = null; // hide toggle on probe failure
    }
  }

  // Toggle between 0.5× (ultra-wide, minZoom) and 1× (normal). Best-effort.
  Future<void> _toggleUltraWide() async {
    final cam = _cam;
    final mz = _minZoom;
    if (cam == null || mz == null) return;
    final next = !_ultraWide;
    try {
      await cam.setZoomLevel(next ? mz : 1.0);
      setState(() => _ultraWide = next);
    } catch (e) {
      debugPrint('panorama video setZoom failed: $e');
    }
  }

  // Gravity (world-up) in device coords: the accelerometer at rest reads ≈ +g
  // along up, so its unit vector IS world-up. Also gives the current pitch.
  void _onAccel(AccelerometerEvent e) {
    final m = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    if (m < 1e-3) return; // free-fall / bogus — keep last good gravity
    _gx = e.x / m;
    _gy = e.y / m;
    _gz = e.z / m;
    // Pitch: how far the phone's optical axis (device -Z) tilts off the horizon.
    // For upright portrait at rest gz≈0 → pitch≈0; tilting up/down moves gz.
    _pitchDeg = math.asin(_gz.clamp(-1.0, 1.0)) * 180 / math.pi;
  }

  // Integrate angular velocity about WORLD-UP: yawRate = gyro · gravityUnit.
  void _onGyro(GyroscopeEvent e) {
    final now = _clock.elapsedMicroseconds;
    final last = _lastGyroUs;
    _lastGyroUs = now;
    if (!_recording || last == 0) {
      _spinRate = 0;
      return;
    }
    final dt = (now - last) / 1e6;
    final yawRate = e.x * _gx + e.y * _gy + e.z * _gz; // rad/s about world-up
    _spinRate = yawRate.abs() * 180 / math.pi;
    _yawDeg += (yawRate * 180 / math.pi * dt).abs(); // abs → direction-agnostic
    _yawNotifier.value = _yawDeg;
  }

  Future<void> _startRecording() async {
    final cam = _cam;
    if (cam == null || _recording) return;
    try {
      _poseTimeline.clear();
      _yawDeg = 0;
      _lastGyroUs = 0;
      _yawNotifier.value = 0;
      _clock
        ..reset()
        ..start();
      await cam.startVideoRecording();
      setState(() => _recording = true);
      // Sample the pose at ~15 Hz, parallel to the recording.
      _poseTimer = Timer.periodic(
          const Duration(milliseconds: _poseSampleMs), (_) => _samplePose());
      // Hard cap: auto-stop so the clip (and the transcode) stays sane.
      _capTimer = Timer(const Duration(milliseconds: _maxRecordMs), () {
        if (_recording) _stopRecording();
      });
      HapticFeedback.mediumImpact();
    } catch (e) {
      debugPrint('panorama video start failed: $e');
      if (mounted) {
        setState(() => _error = 'לא ניתן להתחיל הקלטה. נסו שוב.');
      }
    }
  }

  void _samplePose() {
    final tMs = _clock.elapsedMilliseconds;
    // Keep tMs strictly increasing (Timer can fire slightly out of order under
    // load); skip a non-advancing sample rather than break monotonicity.
    if (_poseTimeline.isNotEmpty && tMs <= _poseTimeline.last['tMs']!) return;
    _poseTimeline.add({
      'tMs': tMs.toDouble(),
      'yaw': (_yawDeg % 360 + 360) % 360,
      'pitch': _pitchDeg,
    });
  }

  Future<void> _stopRecording() async {
    final cam = _cam;
    if (cam == null || !_recording) return;
    _poseTimer?.cancel();
    _capTimer?.cancel();
    final elapsed = _clock.elapsedMilliseconds;
    _clock.stop();
    setState(() => _recording = false);

    if (elapsed < _minRecordMs) {
      // Too short to be a real full turn — coach, don't ship a broken pano.
      _toast(
          'ההקלטה קצרה מדי. סובבו לאט סיבוב אחד מלא (לפחות ${_minRecordMs ~/ 1000} שניות).');
      try {
        await cam.stopVideoRecording(); // discard
      } catch (_) {}
      // Let them record again.
      _clock.reset();
      return;
    }

    XFile? raw;
    try {
      raw = await cam.stopVideoRecording();
    } catch (e) {
      debugPrint('panorama video stop failed: $e');
      _toast('שמירת ההקלטה נכשלה. נסו שוב.');
      return;
    }
    await _buildFromVideo(File(raw.path));
  }

  // Transcode → create job → PUT video → start stitch → poll until ready → pop.
  Future<void> _buildFromVideo(File rawVideo) async {
    setState(() {
      _building = true;
      _buildError = null;
      _buildMsg = 'מכינים את הסרטון...';
    });

    // Snapshot the timeline so it can't mutate mid-flight; assert the contract.
    final timeline = List<Map<String, double>>.from(_poseTimeline);
    assert(_timelineValid(timeline),
        'poseTimeline must be monotonic in tMs with yaw 0..360');

    File? mp4;
    try {
      final info = await VideoCompress.compressVideo(
        rawVideo.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: false,
      );
      final out = info?.path;
      if (out == null || out.trim().isEmpty) {
        _failBuild('לא הצלחנו להכין את הסרטון. נסו שוב.');
        return;
      }
      mp4 = File(out);
      if (await mp4.length() > _maxUploadBytes) {
        _failBuild('הסרטון גדול מדי להעלאה. צלמו סיבוב קצר יותר ונסו שוב.');
        return;
      }
    } catch (e) {
      debugPrint('panorama video transcode failed: $e');
      _failBuild('הכנת הסרטון נכשלה. נסו שוב.');
      return;
    }

    try {
      if (!mounted) return;
      setState(() => _buildMsg = 'מתחילים לבנות את הסיור...');
      // No property exists yet while the draft is being filled; group the job
      // under a one-off id used only as a server folder key.
      final groupId = 'draft_${DateTime.now().millisecondsSinceEpoch}';
      final aspect = _recordAspect();
      final job = await AwsApiClient.instance.createPanoramaVideoJob(
        propertyId: groupId,
        hfov: _defaultHfovDeg,
        vfov: _defaultHfovDeg * aspect,
        poseTimeline: timeline,
      );
      if (job == null) {
        _failBuild('לא הצלחנו להתחיל את העיבוד. בדקו את החיבור לאינטרנט.');
        return;
      }

      if (!mounted) return;
      setState(() => _buildMsg = 'מעלים את הסרטון...');
      final ok = await AwsApiClient.instance
          .uploadVideoToPresigned(job.videoUploadUrl, mp4.path);
      if (!ok) {
        _failBuild('ההעלאה נכשלה. בדקו את החיבור ונסו שוב.');
        return;
      }

      if (!mounted) return;
      setState(() => _buildMsg = 'בונים את הסיור...');
      await AwsApiClient.instance.startPanoramaStitch(job.jobId);

      // Poll until ready (or failed). Keyframe extraction + stitching takes a
      // while; give it generous, patient time with a calm message.
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
          ));
          return;
        }
        if (status.status == 'failed') {
          _failBuild('העיבוד נכשל. נסו לצלם שוב, לאט ובאור טוב.');
          return;
        }
        setState(() => _buildMsg = 'בונים את הסיור...');
      }
      _failBuild('העיבוד לוקח יותר מדי זמן. נסו שוב מאוחר יותר.');
    } catch (e) {
      debugPrint('panorama video build failed: $e');
      _failBuild('משהו השתבש. בדקו את החיבור ונסו שוב.');
    }
  }

  double _recordAspect() {
    final cam = _cam;
    if (cam == null || !cam.value.isInitialized) return 16 / 9;
    final a = cam.value.aspectRatio; // width/height of the sensor stream
    if (a <= 0) return 16 / 9;
    // Portrait recording → tall frame → vfov/hfov > 1. aspectRatio is w/h, so
    // the portrait height/width factor is 1/a.
    return 1 / a;
  }

  // Contract self-check used by the assert: monotonic tMs, yaw in [0,360].
  bool _timelineValid(List<Map<String, double>> t) {
    var lastT = -1.0;
    for (final p in t) {
      final tMs = p['tMs'], yaw = p['yaw'];
      if (tMs == null || yaw == null) return false;
      if (tMs <= lastT) return false;
      if (yaw < 0 || yaw > 360) return false;
      lastT = tMs;
    }
    return true;
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
      _clock.reset();
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 3600),
      content: Text(msg),
    ));
  }

  @override
  void dispose() {
    _poseTimer?.cancel();
    _capTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _gyro?.cancel();
    _accel?.cancel();
    _yawNotifier.dispose();
    final c = _cam;
    if (c != null) {
      // If still recording, stop first so the plugin doesn't throw on teardown.
      if (c.value.isRecordingVideo) {
        c.stopVideoRecording().catchError((_) => XFile('')).whenComplete(
            c.dispose);
      } else {
        c.dispose();
      }
    }
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

          // Live coverage ring + big Hebrew coaching — turns green at a full
          // turn so an older user SEES at a glance when one rotation is done.
          if (_cam != null && _error == null && _recording)
            Center(
              child: ValueListenableBuilder<double>(
                valueListenable: _yawNotifier,
                builder: (_, yaw, __) {
                  final done = yaw >= 359.5;
                  final tooFast = _spinRate > 40;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Persistent top coaching line: stand still, turn slowly.
                      _coachPill(
                        done
                            ? 'סיבוב מלא ✓ אפשר לעצור'
                            : 'עמדו במקום וסובבו לאט סיבוב שלם',
                        bg: done
                            ? Colors.green.withValues(alpha: 0.85)
                            : Colors.black.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 18),
                      CustomPaint(
                        size: const Size(240, 240),
                        painter: _YawRingPainter(
                            yawDeg: yaw, tooFast: tooFast && !done),
                      ),
                      const SizedBox(height: 18),
                      // "Slow down" hint only while actually spinning too fast.
                      if (tooFast && !done)
                        _coachPill('סובב יותר לאט 🐢',
                            bg: AppColors.coral.withValues(alpha: 0.92)),
                    ],
                  );
                },
              ),
            ),

          // Top: close button.
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
                    // 0.5× / 1× toggle — only when an ultra-wide lens is
                    // reachable and we're not mid-build.
                    if (_minZoom != null && !_building) _zoomToggle(),
                  ],
                ),
              ),
            ),
          ),

          // Bottom: big instruction + record/stop button.
          if (_cam != null && _error == null && !_building)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _instruction(),
                      const SizedBox(height: 16),
                      _recordButton(),
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

  Widget _instruction() {
    String text;
    if (!_recording) {
      text = 'עמדו במרכז החדר, לחצו הקלטה, וסובבו לאט סיבוב אחד מלא.';
    } else if (_spinRate > 40) {
      text = 'לאט יותר 🐢 — תנו למצלמה לצלם חד';
    } else {
      text = 'המשיכו לסובב לאט עד שהטבעת תתמלא ותהפוך לירוקה';
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

  Widget _recordButton() {
    if (!_recording) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.coral,
            padding: const EdgeInsets.symmetric(vertical: 18),
          ),
          onPressed: _startRecording,
          icon: const Icon(IconsaxPlusBold.video, size: 26),
          label: const Text('התחל הקלטה',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 18),
        ),
        onPressed: _stopRecording,
        icon: const Icon(IconsaxPlusBold.stop, size: 26),
        label: const Text('עצור וסיים',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
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

  // Big, high-contrast coaching pill used by the rotation guidance.
  Widget _coachPill(String text, {required Color bg}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
              height: 1.35,
              fontWeight: FontWeight.w900),
        ),
      );

  // Big, clear 0.5× / 1× pill. Shows which view is active; tap flips it.
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

// Live yaw ring: the filled arc is how far you've turned (0→360). It turns green
// at a full turn so an older user can SEE, at a glance, when one rotation is done.
class _YawRingPainter extends CustomPainter {
  _YawRingPainter({required this.yawDeg, this.tooFast = false});
  final double yawDeg;
  final bool tooFast; // turning too fast → warn on the arc colour

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 10;
    final rect = Rect.fromCircle(center: c, radius: r);
    final frac = (yawDeg / 360).clamp(0.0, 1.0);
    final done = frac >= 0.999;

    // Arc colour: green when a full turn is reached, coral while turning too
    // fast (visual echo of the "slow down" hint), otherwise the brand colour.
    final arcColor = done
        ? Colors.greenAccent
        : tooFast
            ? AppColors.coral
            : AppColors.primary;

    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..color = Colors.white24);
    canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * frac,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round
          ..color = arcColor);

    final label = done ? 'סיבוב מלא ✓' : '${(frac * 360).round()}°';
    final tp = TextPainter(
      text: TextSpan(
          text: label,
          style: TextStyle(
              color: done ? Colors.greenAccent : Colors.white,
              fontSize: done ? 26 : 34,
              fontWeight: FontWeight.w900)),
      textDirection: TextDirection.rtl,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _YawRingPainter old) =>
      old.yawDeg != yawDeg || old.tooFast != tooFast;
}
