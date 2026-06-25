import 'package:camera/camera.dart';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// Result of the optional pole-capture step: the floor (nadir) and ceiling
/// (zenith) photo paths. Either may be null if the landlord skipped that shot.
class PolePhotos {
  const PolePhotos({this.floorPath, this.ceilingPath});
  final String? floorPath;
  final String? ceilingPath;

  bool get hasAny => floorPath != null || ceilingPath != null;
}

/// OPTIONAL "שפר רצפה ותקרה" step. A single horizontal phone panorama has no real
/// ceiling/floor, so we guide the landlord to take ONE downward photo (floor) and
/// ONE upward photo (ceiling). Those two real photos are composited into the pole
/// caps server-side (server/pole_fill) — honest, not AI-invented.
///
/// Fully skippable for older landlords: every step has a "דלג" action and the
/// flow returns whatever was captured (possibly nothing).
class PanoramaPoleCaptureScreen extends StatefulWidget {
  const PanoramaPoleCaptureScreen({super.key});

  @override
  State<PanoramaPoleCaptureScreen> createState() =>
      _PanoramaPoleCaptureScreenState();
}

enum _Step { floor, ceiling }

class _PanoramaPoleCaptureScreenState extends State<PanoramaPoleCaptureScreen> {
  CameraController? _cam;
  String? _error;
  bool _shooting = false;

  _Step _step = _Step.floor;
  String? _floorPath;
  String? _ceilingPath;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    _init();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw StateError('no camera');
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final ctrl = CameraController(back, ResolutionPreset.veryHigh,
          enableAudio: false);
      await ctrl.initialize();
      try {
        await ctrl.setZoomLevel(await ctrl.getMinZoomLevel());
      } catch (_) {}
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() => _cam = ctrl);
    } catch (_) {
      if (mounted) setState(() => _error = 'לא ניתן לפתוח את המצלמה');
    }
  }

  Future<void> _shoot() async {
    final cam = _cam;
    if (cam == null || _shooting) return;
    setState(() => _shooting = true);
    try {
      HapticFeedback.mediumImpact();
      final shot = await cam.takePicture();
      if (!mounted) return;
      if (_step == _Step.floor) {
        _floorPath = shot.path;
        setState(() {
          _step = _Step.ceiling;
          _shooting = false;
        });
      } else {
        _ceilingPath = shot.path;
        _finish();
      }
    } catch (_) {
      if (mounted) setState(() => _shooting = false);
    }
  }

  // Skip the current pole and move on (or finish if it was the last).
  void _skipStep() {
    if (_step == _Step.floor) {
      setState(() => _step = _Step.ceiling);
    } else {
      _finish();
    }
  }

  void _finish() {
    Navigator.of(context).pop(
      PolePhotos(floorPath: _floorPath, ceilingPath: _ceilingPath),
    );
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _cam?.dispose();
    super.dispose();
  }

  bool get _isFloor => _step == _Step.floor;

  String get _title => _isFloor ? 'צלם את הרצפה' : 'צלם את התקרה';

  String get _hint => _isFloor
      ? 'כוון את הטלפון כלפי מטה אל הרצפה ועמוד במקום שבו צילמת את הפנורמה'
      : 'כוון את הטלפון כלפי מעלה אל התקרה, מאותה נקודה בדיוק';

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

          if (_cam != null && _error == null) _PoleGuide(pointDown: _isFloor),

          // top bar: close + step indicator
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
                      onTap: _finish,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(IconsaxPlusLinear.close_circle,
                            color: Colors.white, size: 20),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _isFloor ? 'שלב 1 מתוך 2 · רצפה' : 'שלב 2 מתוך 2 · תקרה',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (_cam != null && _error == null)
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _title,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _hint,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  height: 1.35,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: _shooting ? null : _skipStep,
                            child: const Text('דלג',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 24),
                          GestureDetector(
                            onTap: _shoot,
                            child: Container(
                              width: 74,
                              height: 74,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: AppColors.primary, width: 4),
                              ),
                              child: _shooting
                                  ? Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: CircularProgressIndicator(
                                          strokeWidth: 3,
                                          color: AppColors.primary))
                                  : Icon(IconsaxPlusBold.camera,
                                      color: AppColors.primary, size: 32),
                            ),
                          ),
                          const SizedBox(width: 24),
                          const SizedBox(width: 48), // balance the "דלג" button
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
              onPressed: () => Navigator.of(context).pop(const PolePhotos()),
              child: const Text('סגור'),
            ),
          ],
        ),
      );
}

// A big up/down arrow + centre reticle to coach which way to point the phone.
class _PoleGuide extends StatelessWidget {
  const _PoleGuide({required this.pointDown});
  final bool pointDown;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Icon(
          pointDown
              ? IconsaxPlusLinear.arrow_down_1
              : IconsaxPlusLinear.arrow_up_1,
          color: AppColors.primary.withValues(alpha: 0.85),
          size: 88,
        ),
      ),
    );
  }
}
