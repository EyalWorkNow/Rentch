import 'package:camera_360/camera_360.dart';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// Real guided 360° capture, backed by the camera_360 plugin (OpenCV stitching).
/// Shows an onboarding intro, then the plugin's dot-guided capture UI, and pops
/// the stitched panorama's file path on success.
class Camera360CaptureScreen extends StatefulWidget {
  const Camera360CaptureScreen({super.key});

  @override
  State<Camera360CaptureScreen> createState() => _Camera360CaptureScreenState();
}

class _Camera360CaptureScreenState extends State<Camera360CaptureScreen> {
  bool _started = false;
  int _progress = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _started ? _capture() : _intro(),
    );
  }

  Widget _capture() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Camera360(
          onCaptureEnded: (data) {
            if (data['success'] == true && data['panorama'] != null) {
              final XFile panorama = data['panorama'] as XFile;
              Navigator.of(context).pop(panorama.path);
            } else {
              Navigator.of(context).pop();
            }
          },
          onProgressChanged: (p) {
            if (mounted) setState(() => _progress = p);
          },
          userLoadingText: 'מכין את הפנורמה…',
          userHelperText: 'כוון את המצלמה אל הנקודה',
          userHelperTiltLeftText: 'הטה שמאלה',
          userHelperTiltRightText: 'הטה ימינה',
          cameraSelectorInfoPopUpContent: const Text(
            'לאיכות הטובה ביותר בחר את העדשה הרחבה',
            textAlign: TextAlign.center,
          ),
          cameraNotReadyContent: const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
        // close + progress
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
                  const Spacer(),
                  if (_progress > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('$_progress%',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _intro() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: const Icon(IconsaxPlusLinear.close_circle,
                    color: Colors.white54, size: 28),
              ),
            ),
            const Spacer(),
            Center(
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child:
                    const Icon(IconsaxPlusBold.global, color: Colors.white, size: 46),
              ),
            ),
            const SizedBox(height: 20),
            const Text('סיור 360° מודרך',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(
              'נצלם את החדר ב-360° עם הנחיות על המסך — סובב לאט ועקוב אחרי הנקודה.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                  height: 1.4),
            ),
            const SizedBox(height: 28),
            _step(IconsaxPlusLinear.user, 'עמוד במרכז החדר',
                'הישאר במקום — רק תסתובב סביב הציר שלך.'),
            _step(IconsaxPlusLinear.rotate_left, 'סובב לאט',
                'עקוב אחרי הנקודה שבמסך עד לסיום הסיבוב המלא.'),
            _step(IconsaxPlusLinear.sun_1, 'תאורה טובה',
                'צלם בתאורה אחידה לתוצאה חדה יותר.'),
            const Spacer(),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
                onPressed: () => setState(() => _started = true),
                icon: const Icon(IconsaxPlusBold.camera),
                label: const Text('בוא נתחיל',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(body,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.65),
                        fontSize: 12.5,
                        height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
