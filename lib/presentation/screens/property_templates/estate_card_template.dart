part of '../property_detail_screen.dart';

/// Estate Card (`estateCard`) — a full-bleed 510px hero with the top bar overlaid
/// in the safe area and a white rounded info card pinned to the bottom (price,
/// new-listing capsule, location, dense facts), followed by the shared parity
/// block. Uses only shared building blocks; self-contained and designer-owned.
class _EstateCardTemplate extends StatelessWidget {
  const _EstateCardTemplate({
    required this.property,
    required this.branding,
    required this.controller,
    required this.currentPage,
    required this.onPageChanged,
    required this.reviews,
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
            // Edge-to-edge hero: no top inset here so the image bleeds to the
            // very top; the top bar carries the status-bar safe area instead.
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 510,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _TemplateHeroMedia(
                          property: property,
                          controller: controller,
                          currentPage: currentPage,
                          onPageChanged: onPageChanged,
                          height: 510,
                          radius: 0,
                          alignment: Alignment.center,
                        ),
                      ),
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 12,
                        left: 20,
                        right: 20,
                        child: _TemplateTopBar(
                          branding: branding,
                          title: '',
                          dark: true,
                          onBackTap: onBackTap,
                          onShareTap: onShareTap,
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(32),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      property.priceLabel,
                                      style: TextStyle(
                                        color: branding.secondaryColor,
                                        fontSize: 28,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  if (property.isNewListing)
                                    _StatusCapsule(
                                      label: 'חדש',
                                      fg: branding.primaryColor,
                                      bg: branding.primaryColor
                                          .withValues(alpha: 0.10),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Icon(
                                    IconsaxPlusLinear.location,
                                    size: 16,
                                    color: branding.primaryColor,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      property.address,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              _TemplateFactsWrap(
                                property: property,
                                branding: branding,
                                dense: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
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
