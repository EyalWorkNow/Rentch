import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/constants/brand_palette.dart';

/// Verifies the "swap the theme accent" contract holds PER COLOUR TYPE:
///   • the brand accent (primary + its derived tones + helpers) re-tints;
///   • fixed semantics (success/danger/warning/info/score/like/superLike) and
///     neutrals (navy/scrims) DO NOT move — a success tick stays green, an
///     error stays red, no matter the accent.
/// If a screen ever hardcodes an accent hex again, the widget smoke-test below
/// still passes (it builds from tokens) — but the token asserts guarantee the
/// machinery every migrated screen now depends on keeps working.
void main() {
  // AppColors accent is a mutable global; restore the app default between tests.
  tearDown(() {
    AppColors.customPrimary = null;
    AppColors.applyRole('tenant');
  });

  const hotPink = Color(0xFFEC4899); // a colour nothing else in the app uses

  group('theme swap', () {
    test('a custom accent re-tints every accent token', () {
      AppColors.customPrimary = hotPink;
      AppColors.applyRole('tenant');

      expect(AppColors.primary, hotPink, reason: 'primary must be the custom accent');
      expect(AppColors.primaryDark, isNot(BrandPalette.teal.primaryDark),
          reason: 'dark tone must be re-derived, not the old teal');
      expect(AppColors.primaryLight, isNot(BrandPalette.teal.primaryLight));
      // helpers track primary
      expect(AppColors.accentGlow(0.25), hotPink.withValues(alpha: 0.25));
      expect(AppColors.accentSoft(), hotPink.withValues(alpha: 0.12));
      expect(AppColors.accentBg, AppColors.primaryLight2);
    });

    test('fixed semantic + neutral tokens never move when the accent swaps', () {
      List<Color> snapshot() => [
            AppColors.success, AppColors.successDeep, AppColors.successBg,
            AppColors.warning, AppColors.warningDeep, AppColors.warningBg,
            AppColors.danger, AppColors.dangerDeep, AppColors.dangerSoft,
            AppColors.info, AppColors.infoDeep, AppColors.sky, AppColors.carrot,
            AppColors.scoreStrong, AppColors.scoreGood, AppColors.scoreMixed,
            AppColors.like, AppColors.superLike, AppColors.pink,
            AppColors.navy, AppColors.navyMid, AppColors.navyShadow,
            AppColors.scrim, AppColors.scrimSoft, AppColors.scrimStrong,
          ];
      final before = snapshot();
      AppColors.customPrimary = hotPink;
      AppColors.applyRole('tenant');
      expect(snapshot(), before, reason: 'no semantic/neutral token may follow the accent');
    });

    test('broker role flips isBrokerAccent + accent; tenant restores', () {
      AppColors.customPrimary = null;
      AppColors.applyRole('broker');
      expect(AppColors.isBrokerAccent, isTrue);
      expect(AppColors.primary, BrandPalette.broker.primary);

      AppColors.applyRole('tenant');
      expect(AppColors.isBrokerAccent, isFalse);
      expect(AppColors.primary, BrandPalette.teal.primary);
    });

    test('score tiers stay on their fixed traffic-scale (brand-independent)', () {
      AppColors.customPrimary = hotPink;
      AppColors.applyRole('tenant');
      expect(AppColors.scoreStrong, AppColors.successDeep); // green, not pink
      expect(AppColors.scoreMixed, AppColors.warningDeep); // orange, not pink
      expect(AppColors.scoreStrong, isNot(AppColors.primary));
    });

    testWidgets('a token-driven accent gradient repaints after a swap', (tester) async {
      Widget accentBox() => Directionality(
            textDirection: TextDirection.rtl,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  AppColors.primaryLight,
                  AppColors.primary,
                  AppColors.primaryDark,
                ]),
              ),
            ),
          );
      LinearGradient gradientOf() => (tester
              .widget<DecoratedBox>(find.byType(DecoratedBox))
              .decoration as BoxDecoration)
          .gradient! as LinearGradient;

      AppColors.applyRole('tenant');
      await tester.pumpWidget(accentBox());
      expect(gradientOf().colors[1], BrandPalette.teal.primary);

      AppColors.customPrimary = hotPink;
      AppColors.applyRole('tenant');
      await tester.pumpWidget(accentBox());
      expect(gradientOf().colors[1], hotPink,
          reason: 'the middle stop must follow the swapped accent, not stay teal');
    });
  });
}
