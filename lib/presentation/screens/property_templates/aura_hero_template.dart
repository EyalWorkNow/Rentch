part of '../property_detail_screen.dart';

/// Aura Hero (a.k.a. `acidHero`) — centered brand mark + address, a tall rounded
/// hero with a glass owner card + size badge overlay, a glass "floor" pill, and
/// a clean white price card, followed by the shared full-parity content block.
///
/// Self-contained, designer-owned unit. Exclusive helper widgets used only by
/// this layout ([_AcidHeroOverlay], [_GlassFilterPill], [_AcidPriceCard]) live
/// in this file. Shared building blocks (top bar, hero media, parity sections)
/// stay in the library head.
class _AuraHeroTemplate extends StatelessWidget {
  const _AuraHeroTemplate({
    required this.property,
    required this.branding,
    required this.controller,
    required this.currentPage,
    required this.onPageChanged,
    required this.reviews,
    required this.avgRating,
    required this.hasVirtualTour,
    required this.isLandlordPreview,
    required this.onBackTap,
    required this.onShareTap,
    required this.onTour,
  });

  final RentalProperty property;
  final BrokerBrandingConfig branding;
  final PageController controller;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final List<AppReview> reviews;
  final double avgRating;
  final bool hasVirtualTour;
  final bool isLandlordPreview;
  final VoidCallback onBackTap;
  final VoidCallback onShareTap;
  final VoidCallback onTour;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              22,
              MediaQuery.of(context).padding.top + 8,
              22,
              124,
            ),
            child: Column(
              children: [
                // Empty title → renders the broker brand logo mark (not the
                // owner's name, which previously read oddly as a page title).
                _TemplateTopBar(
                  branding: branding,
                  title: '',
                  dark: false,
                  onBackTap: onBackTap,
                  onShareTap: onShareTap,
                ),
                const SizedBox(height: 14),
                Text(
                  property.address,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: branding.secondaryColor,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${property.city} · ${property.transactionLabel}',
                  style: TextStyle(
                    color: branding.secondaryColor.withValues(alpha: 0.68),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                _TemplateHeroMedia(
                  property: property,
                  controller: controller,
                  currentPage: currentPage,
                  onPageChanged: onPageChanged,
                  height: 320,
                  radius: 34,
                  overlay: _AcidHeroOverlay(
                    property: property,
                    branding: branding,
                    avgRating: avgRating,
                  ),
                ),
                const SizedBox(height: 18),
                _GlassFilterPill(
                  icon: IconsaxPlusLinear.layer,
                  label: property.floor.isEmpty
                      ? property.propertyType
                      : 'קומה ${property.floor}',
                  branding: branding,
                ),
                const SizedBox(height: 18),
                _AcidPriceCard(property: property, branding: branding),
                const SizedBox(height: 26),
                _ParitySections(
                  property: property,
                  branding: branding,
                  controller: controller,
                  reviews: reviews,
                  hasVirtualTour: hasVirtualTour,
                  isLandlordPreview: isLandlordPreview,
                  onShareTap: onShareTap,
                  onTour: onTour,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AcidHeroOverlay extends StatelessWidget {
  const _AcidHeroOverlay({
    required this.property,
    required this.branding,
    required this.avgRating,
  });

  final RentalProperty property;
  final BrokerBrandingConfig branding;
  final double avgRating;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          bottom: 22,
          right: 22,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 11, 16, 11),
                decoration: BoxDecoration(
                  color: branding.secondaryColor.withValues(alpha: 0.46),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: branding.accentColor,
                      child: Text(
                        property.ownerName.isEmpty ? '?' : property.ownerName[0],
                        style: TextStyle(
                          color: branding.secondaryColor,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          property.ownerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          avgRating > 0
                              ? '${avgRating.toStringAsFixed(1)} דירוג'
                              : 'מתווך נדל״ן',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 22,
          left: 22,
          child: Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: branding.secondaryColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Center(
              child: Text(
                '${property.sizeM2}\nמ״ר',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: branding.accentColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassFilterPill extends StatelessWidget {
  const _GlassFilterPill({
    required this.icon,
    required this.label,
    required this.branding,
  });

  final IconData icon;
  final String label;
  final BrokerBrandingConfig branding;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          Icon(icon, color: branding.secondaryColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: branding.secondaryColor,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AcidPriceCard extends StatelessWidget {
  const _AcidPriceCard({
    required this.property,
    required this.branding,
  });

  final RentalProperty property;
  final BrokerBrandingConfig branding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            property.propertyType,
            style: TextStyle(
              color: branding.secondaryColor,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                property.priceLabel,
                style: TextStyle(
                  color: branding.secondaryColor,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  property.priceSuffixLabel,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
