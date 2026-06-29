part of '../property_detail_screen.dart';

/// Cinematic Glass (`cinematicGlass`) — a full-screen primary image with a dark
/// gradient wash, a glass transaction/price strip and address overlaid low on
/// the image, then the shared parity block wrapped in a light surface so the
/// white content cards stay legible over the dark backdrop. Uses only shared
/// building blocks; self-contained and designer-owned.
class _CinematicGlassTemplate extends StatelessWidget {
  const _CinematicGlassTemplate({
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
    return Stack(
      children: [
        Positioned.fill(
          child: SafeMedia(
            media: property.primaryMedia ??
                const PropertyMedia(url: '', type: PropertyMediaType.image),
            fit: BoxFit.cover,
            alignment: Alignment.center,
            fallback: _ImageFallback(city: property.city),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.30),
                  branding.secondaryColor.withValues(alpha: 0.52),
                  branding.secondaryColor.withValues(alpha: 0.90),
                ],
              ),
            ),
          ),
        ),
        CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  MediaQuery.of(context).padding.top + 14,
                  18,
                  126,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TemplateTopBar(
                      branding: branding,
                      title: '',
                      dark: true,
                      onBackTap: onBackTap,
                      onShareTap: onShareTap,
                    ),
                    SizedBox(height: MediaQuery.sizeOf(context).height * 0.40),
                    // Transaction + price glass strip over the cinematic image.
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      property.transactionLabel,
                                      style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.78),
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${property.priceLabel} ${property.priceSuffixLabel}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _StatusCapsule(
                                label: '${property.roomsLabel} חד׳',
                                fg: branding.secondaryColor,
                                bg: Colors.white,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      property.address,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Parity block lives in a light surface so the white content
                    // cards (owner/facts/map/reviews) stay legible over the dark
                    // cinematic backdrop, while still rendering EVERY section.
                    ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: Container(
                        color: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 22),
                        child: _ParitySections(
                          property: property,
                          branding: branding,
                          controller: controller,
                          reviews: reviews,
                          hasVirtualTour: hasVirtualTour,
                          isLandlordPreview: isLandlordPreview,
                          onShareTap: onShareTap,
                          onTour: onTour,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
