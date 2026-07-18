import 'package:flutter/widgets.dart';
import 'package:dating_app/core/constants/app_colors.dart';

/// Phone-first layout adapter for large screens (iPad).
///
/// Rently's screens are designed for a phone-width portrait canvas. On a wide
/// display (iPad) we don't stretch every screen — instead the whole app is
/// rendered once inside a centered, phone-width column with neutral side
/// margins. `MediaQuery.size` is overridden to the clamped width so the screens
/// that size themselves off the screen width compute against the phone width
/// (no overflow / no oversized cards). On phones this is a no-op.
///
/// The centering is done with [Align]/[Center], whose render object applies its
/// offset to BOTH painting and hit-testing — so taps inside the centered column
/// register correctly (covered by ipad_frame_test.dart).
class IpadFrame extends StatelessWidget {
  const IpadFrame({super.key, required this.child});

  final Widget child;

  static const double phoneWidth = 480;
  static const double wideBreakpoint = 600;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // shortestSide is the canonical tablet check: it stays < 600 for phones in
    // ANY orientation, and only crosses the threshold on real tablets (iPad).
    if (mq.size.shortestSide <= wideBreakpoint) return child;

    final clamped = mq.copyWith(size: Size(phoneWidth, mq.size.height));
    return ColoredBox(
      color: AppColors.ink,
      child: Center(
        child: ClipRect(
          child: SizedBox(
            width: phoneWidth,
            height: mq.size.height,
            child: MediaQuery(data: clamped, child: child),
          ),
        ),
      ),
    );
  }
}
