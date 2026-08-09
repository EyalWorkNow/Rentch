import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/govdata/market_intelligence.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';

/// Friendly "fair rent" hint shown to a landlord under the price field while
/// they're setting a monthly rent. It surfaces the app's existing market model
/// (gov per-locality ₪/m² prior, via [MarketIntelligence.govExpectedRent]) as a
/// single big number plus a plain-Hebrew band comparing it to the typed price,
/// and a one-tap "use the recommended price" action.
///
/// It is intentionally rent-only and self-hiding: for a sale, or whenever the
/// model has no anchor for the city/size, it renders nothing (an empty box).
class FairRentHint extends StatelessWidget {
  FairRentHint({
    super.key,
    required this.city,
    required this.sizeM2,
    required this.rooms,
    required this.transactionType,
    required this.typedPrice,
    required this.onUseRecommended,
  });

  /// City as typed in the location step (may be empty mid-edit).
  final String city;

  /// Property size in m². 0 while the field is empty.
  final int sizeM2;

  /// Rooms — not required by the gov prior but kept for future refinement.
  final double rooms;

  final PropertyTransactionType transactionType;

  /// The rent the landlord has currently dialed in.
  final int typedPrice;

  /// Called with the recommended rent when the landlord taps "use it".
  final ValueChanged<int> onUseRecommended;

  /// Round to the nearest 50 ₪ so the suggestion reads like a real asking rent.
  int _roundRent(double v) => (v / 50).round() * 50;

  @override
  Widget build(BuildContext context) {
    // Sale prices aren't modeled here — show nothing.
    if (transactionType != PropertyTransactionType.rent) {
      return const SizedBox.shrink();
    }
    if (city.trim().length < 2 || sizeM2 <= 0) {
      return const SizedBox.shrink();
    }

    final expected =
        MarketIntelligence.govExpectedRent(city.trim(), sizeM2);
    if (expected == null || expected <= 0) {
      // No market anchor for this locality/size — hide gracefully.
      return const SizedBox.shrink();
    }

    final fair = _roundRent(expected);
    if (fair <= 0) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context)!;
    final band = _bandFor(l10n, typedPrice, fair);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              RentlyIcon(IconsaxPlusLinear.chart_2,
                  size: 18, color: AppColors.primaryDark),
              const SizedBox(width: 8),
              Text(
                l10n.fairRentHint2f1f13cd,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.primaryDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.fairRentHint9b75eb76(_formatThousands(fair)),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: AppColors.navy,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          // The band assessment vs the typed price.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: band.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(band.icon, size: 16, color: band.color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    band.message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: band.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Offer the one-tap action only when the typed price isn't already
          // the recommendation.
          if (typedPrice != fair) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => onUseRecommended(fair),
                icon: RentlyIcon(IconsaxPlusLinear.magic_star,
                    size: 16, color: AppColors.primaryDark),
                label: Text(
                  l10n.fairRentHintAdcf7818(_formatThousands(fair)),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryDark,
                  side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.5),
                      width: 1.4),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Decide the assessment band: green when within ~±8% of the fair rent, amber
  // when meaningfully below (could ask more) or above (may deter tenants).
  _RentBand _bandFor(AppLocalizations l10n, int typed, int fair) {
    if (typed <= 0) {
      return _RentBand(
        message: l10n.fairRentHintEa004c85,
        color: AppColors.primaryDark,
        icon: IconsaxPlusLinear.info_circle,
      );
    }
    final ratio = typed / fair;
    if (ratio < 0.92) {
      return _RentBand(
        message: l10n.fairRentHint1b102d50,
        color: AppColors.warning,
        icon: IconsaxPlusLinear.arrow_up_3,
      );
    }
    if (ratio > 1.08) {
      return _RentBand(
        message: l10n.fairRentHintAb830344,
        color: AppColors.warning,
        icon: IconsaxPlusLinear.arrow_down,
      );
    }
    return _RentBand(
      message: l10n.fairRentHintA4d97966,
      color: AppColors.success,
      icon: IconsaxPlusLinear.tick_circle,
    );
  }

  static String _formatThousands(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _RentBand {
  _RentBand({required this.message, required this.color, required this.icon});
  final String message;
  final Color color;
  final IconData icon;
}
