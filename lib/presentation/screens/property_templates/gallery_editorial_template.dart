part of '../property_detail_screen.dart';

/// Gallery Editorial (`galleryEditorial`) — an edge-to-edge 385px hero with the
/// top bar overlaid in the safe area, then an editorial text block (title,
/// location, transaction capsule, price), followed by the shared parity block.
/// Uses only shared building blocks; self-contained and designer-owned.
class _GalleryEditorialTemplate extends StatelessWidget {
  const _GalleryEditorialTemplate({
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
            // Edge-to-edge hero: no top padding so the image reaches the very
            // top; the top bar is overlaid inside the status-bar safe area.
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 124),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 385,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _TemplateHeroMedia(
                          property: property,
                          controller: controller,
                          currentPage: currentPage,
                          onPageChanged: onPageChanged,
                          height: 385,
                          radius: 0,
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
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        property.street.isNotEmpty
                            ? '${property.propertyType} ב${property.street}'
                            : property.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: branding.secondaryColor,
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          height: 1.08,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(IconsaxPlusLinear.location,
                              size: 15, color: branding.primaryColor),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              property.address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: branding.secondaryColor
                                    .withValues(alpha: 0.62),
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _StatusCapsule(
                        label: property.transactionLabel,
                        fg: branding.secondaryColor,
                        bg: const Color(0xFFF3F4F6),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            property.priceLabel,
                            style: TextStyle(
                              color: branding.secondaryColor,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              property.priceSuffixLabel,
                              style: TextStyle(
                                color: branding.secondaryColor
                                    .withValues(alpha: 0.55),
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
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
