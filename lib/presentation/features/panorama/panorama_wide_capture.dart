import 'package:camera/camera.dart';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// In-app wide capture: one ultra-wide (as wide as the device allows) photo per
/// point, with a level guide. Returns the photo path via pop. Displayed as a
/// partial panorama (haov/vaov) by the viewer — a quick in-app alternative to
/// importing a full equirectangular panorama.
class PanoramaWideCaptureScreen extends StatefulWidget {
  const PanoramaWideCaptureScreen({super.key});

  @override
  State<PanoramaWideCaptureScreen> createState() =>
      _PanoramaWideCaptureScreenState();
}

class _PanoramaWideCaptureScreenState extends State<PanoramaWideCaptureScreen> {
  CameraController? _cam;
  String? _error;
  bool _shooting = false;

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
      // widen as much as the device allows (gets the ultra-wide on phones whose
      // back camera is a virtual multi-lens device).
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
      Navigator.of(context).pop(shot.path);
    } catch (_) {
      if (mounted) setState(() => _shooting = false);
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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

          if (_cam != null && _error == null) const _LevelGuide(),

          // top bar
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
                      onTap: () => Navigator.of(context).pop(),
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
                  ],
                ),
              ),
            ),
          ),

          // bottom: hint + shutter
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
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'החזק את הטלפון אנכי וישר, ועמוד במרכז החדר',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(height: 18),
                      GestureDetector(
                        onTap: _shoot,
                        child: Container(
                          width: 74,
                          height: 74,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: AppColors.primary, width: 4),
                          ),
                          child: _shooting
                              ? Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: CircularProgressIndicator(
                                      strokeWidth: 3, color: AppColors.primary))
                              : Icon(IconsaxPlusBold.camera,
                                  color: AppColors.primary, size: 32),
                        ),
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
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('סגור'),
            ),
          ],
        ),
      );
}

// Horizon line + centre reticle to help keep the shot level.
class _LevelGuide extends StatelessWidget {
  const _LevelGuide();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: SizedBox.expand(
          child: CustomPaint(painter: _LevelPainter()),
        ),
      ),
    );
  }
}

class _LevelPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2, cx = size.width / 2;
    final line = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), line);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AppColors.primary;
    canvas.drawCircle(Offset(cx, cy), 18, ring);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
