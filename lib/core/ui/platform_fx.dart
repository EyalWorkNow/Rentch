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

  /// A blur sigma reduced on Android (~45% lighter, with a small floor so it still
  /// reads as frosted); unchanged on iOS and other platforms.
  static double blurSigma(double base) =>
      isAndroid ? (base * 0.55).clamp(2.0, base) : base;
}
