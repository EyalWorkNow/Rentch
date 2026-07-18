/// Rently design-system ROOT — the single place the app's visual language lives.
///
/// Import this one file to reach every design token:
///   import 'package:dating_app/core/design/design_system.dart';
///
/// - [AppColors]   — brand accent (runtime-swappable per account) + neutrals/slate
/// - [BrandPalette]— the source-of-truth brand accent presets (teal / broker)
/// - [AppType]     — font family, type scale, weights, named text styles
/// - [AppSpacing]  — 4px spacing scale + common insets/gaps
/// - [AppRadii]    — corner-radius scale (incl. the single `pill` convention)
/// - [AppIcons]    — semantic icon registry (meaning → IconData)
/// - [AppStyles]   — legacy composed styles (buttons / inputs / cards)
///
/// Change a colour, font size, radius or icon here (or in the files below) and
/// it propagates app-wide.
library;

export '../constants/app_colors.dart';
export '../constants/app_styles.dart';
export '../constants/brand_palette.dart';
export 'app_icons.dart';
export 'app_radii.dart';
export 'app_spacing.dart';
export 'app_typography.dart';
