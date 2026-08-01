import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Rendering effects tuned per platform.
///
/// `BackdropFilter` / `ImageFilter.blur` is a per-frame save-layer + full-backdrop
/// Gaussian blur. iOS/Metal composites this comparatively cheaply; Android/Impeller
/// runs it much more expensively and more device-variably — especially over
/// scrolling or animating content, where it recomputes every frame. Trimming the
/// blur radius on Android keeps glass surfaces smooth there while leaving the iOS
/// look untouched.
class PlatformFx {
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// Blur sigma. Kept at near-parity with iOS (0.9) so the frosted-glass design
  /// looks the SAME on Android — the app is glass-heavy and a lighter blur read
  /// as a different design. The tiny 10% trim is an imperceptible safety margin
  /// for Android/Impeller over animating content; iOS is untouched.
  static double blurSigma(double base) =>
      isAndroid ? (base * 0.9).clamp(2.0, base) : base;
}
