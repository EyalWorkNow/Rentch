import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// "מומלץ בשבילך" — a horizontal strip of compact property cards backed by the
/// collaborative-filtering recommendations (DatingProvider.cfRecommendedIds).
/// Lives directly under the search field; renders nothing when there are no
/// recommendations so the search area collapses cleanly.
class RecommendedForYouStrip extends StatelessWidget {
  const RecommendedForYouStrip({
    super.key,
    required this.properties,
    required this.onTap,
  });

  /// CF-recommended listings, already resolved + ordered (highest first).
  final List<RentalProperty> properties;
  final ValueChanged<RentalProperty> onTap;

  @override
  Widget build(BuildContext context) {
    if (properties.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            children: [
              RentlyIcon(IconsaxPlusLinear.magic_star,
                  size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              const Text(
                'מומלץ בשבילך',
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 168,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              // RTL: first (highest-ranked) card sits on the right.
              reverse: true,
              padding: EdgeInsets.zero,
              itemCount: properties.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) => _CompactCard(
                property: properties[i],
                onTap: () => onTap(properties[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactCard extends StatelessWidget {
  const _CompactCard({required this.property, required this.onTap});

  final RentalProperty property;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = property;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 158,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2ECF1), width: 1),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 92,
              child: SafeMedia(
                media: p.primaryMedia,
                fit: BoxFit.cover,
                fallback: Container(
                  color: AppColors.primaryLight2,
                  child: Icon(IconsaxPlusLinear.building,
                      color: AppColors.primary, size: 30),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p.priceLabel,
                    textDirection: TextDirection.rtl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    p.address,
                    textDirection: TextDirection.rtl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${p.roomsLabel} חד׳ · ${p.sizeM2} מ״ר',
                    textDirection: TextDirection.rtl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
