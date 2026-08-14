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

  /// Blur sigma. Previously trimmed only 10% on Android ("near-parity with
  /// iOS so the frosted-glass design looks the same") — but with ~65
  /// BackdropFilter/blur sites across the app, several inside scrolling or
  /// animating screens (the discover deck alone has ~15), that 10% margin
  /// was not enough to matter on Android/Impeller, which (per the class doc
  /// above) recomputes the full-backdrop blur every frame there. Blur cost
  /// scales with the kernel size, which scales with sigma, so a real cut
  /// here (not just a cosmetic one) is what actually reduces per-frame cost.
  /// Still frosted, just a lighter frost — favoring smoothness over iOS
  /// pixel-parity on the platform where the cost is real.
  static double blurSigma(double base) =>
      isAndroid ? (base * 0.6).clamp(2.0, base) : base;
}
