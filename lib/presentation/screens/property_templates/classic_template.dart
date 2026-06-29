part of '../property_detail_screen.dart';

/// Rently Classic — the default property-detail layout (white scaffold, rounded
/// hero gallery card, specs grid, features, match insight, affordability,
/// gallery thumbnails, source URL, owner, reviews, map + bottom action bar).
///
/// This is the layout shown when no broker template is chosen (or "קלאסי" is
/// selected). It is a self-contained, designer-editable unit: the dispatch in
/// `_PropertyDetailScreenState._buildContent` constructs it with the property,
/// its precomputed view data, and the action callbacks below.
class _ClassicTemplate extends StatelessWidget {
  const _ClassicTemplate({
    required this.property,
    required this.controller,
    required this.currentPage,
    required this.onPageChanged,
    required this.title,
    required this.media,
    required this.reviews,
    required this.avgRating,
    required this.hasVirtualTour,
    required this.isLandlordPreview,
    required this.monthlyIncome,
    required this.onBackTap,
    required this.onShareTap,
    required this.onLike,
    required this.onTour,
    required this.onEdit,
  });

  final RentalProperty property;
  final PageController controller;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final String title;
  final List<PropertyMedia> media;
  final List<AppReview> reviews;
  final double avgRating;
  final bool hasVirtualTour;
  final bool isLandlordPreview;
  final int? monthlyIncome;
  final VoidCallback onBackTap;
  final VoidCallback onShareTap;
  final VoidCallback onLike;
  final VoidCallback onTour;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final p = property;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Image Gallery wrapped in a padded rounded card (Mockup Style)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    5,
                    MediaQuery.of(context).padding.top + 12,
                    5,
                    16,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(32),
                      // white 8px frame + soft drop shadow → reads like a window.
                      border: Border.all(color: Colors.white, width: 8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 22,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: SizedBox(
                        height: 460,
                        child: _ImageGallery(
                          property: p,
                          controller: controller,
                          currentPage: currentPage,
                          onPageChanged: onPageChanged,
                          avgRating: avgRating,
                          onBackTap: onBackTap,
                          onShareTap: onShareTap,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 140),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title & Location & Favorite Heart Icon Row (Mockup Style)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: const TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const RentlyIcon(
                                        IconsaxPlusLinear.location,
                                        size: 16,
                                        color: Color(0xFF64748B)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        p.address,
                                        style: const TextStyle(
                                          color: Color(0xFF64748B),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // ── Property facts/specs — DIRECTLY below gallery+title
                      // so a tenant judges fit immediately (rooms, size,
                      // floor, condition, parking, elevator, entry, price).
                      const Text(
                        'פרטי הנכס',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _PropertyFactsCard(p),
                      const SizedBox(height: 24),

                      // ── ALL tags/features right under the specs. Shows the
                      // FULL set (no cap) so the tenant sees exactly what the
                      // property has.
                      if (p.features.isNotEmpty) ...[
                        _SectionCardShell(
                          title: 'מאפיינים חשובים',
                          icon: IconsaxPlusLinear.flash_1,
                          child: _FeatureWrap(features: p.features),
                        ),
                      ],

                      // ── "למה ההתאמה הזו?" — collapsible dropdown (collapsed
                      // by default) with a "?" icon; expands the scorecard.
                      if (!isLandlordPreview)
                        _MatchInsightDropdown(property: p),

                      // Affordability + rights (rentals only, real tenants).
                      if (!isLandlordPreview &&
                          p.transactionType ==
                              PropertyTransactionType.rent) ...[
                        _AffordabilityStrip(
                          property: p,
                          monthlyIncome: monthlyIncome,
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (_PropertySignalStrip.shouldShow(context, p)) ...[
                        _PropertySignalStrip(property: p),
                        const SizedBox(height: 24),
                      ],

                      // Photos / Gallery Carousel (Mockup Style)
                      if (media.isNotEmpty) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'גלריה',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              '${media.length} תמונות',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FadeSlideEntrance(
                          duration: const Duration(milliseconds: 450),
                          offset: const Offset(0.0, 30.0),
                          child: SizedBox(
                            height: 105,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: media.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, index) {
                                final item = media[index];
                                return ScaleBounce(
                                  onTap: () {
                                    controller.animateToPage(
                                      index,
                                      duration:
                                          const Duration(milliseconds: 300),
                                      curve: Curves.easeInOut,
                                    );
                                  },
                                  scaleDownTo: 0.90,
                                  child: Column(
                                    children: [
                                      ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(16),
                                        child: SizedBox(
                                          width: 100,
                                          height: 70,
                                          child: SafeMedia(
                                            media: item,
                                            fit: BoxFit.cover,
                                            fallback:
                                                _ImageFallback(city: p.city),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        item.isVideo
                                            ? 'סרטון'
                                            : 'תמונה ${index + 1}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Description / Website URL Section
                      if (p.url.isNotEmpty) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'אתר מקור',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            GestureDetector(
                              onTap: () async {
                                await launchUrl(Uri.parse(p.url),
                                    mode: LaunchMode.externalApplication);
                              },
                              child: const Text(
                                'צפה במקור',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF13BEC9),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'נכס זה פורסם במקור באתר ${Uri.parse(p.url).host}. באפשרותך לפתוח את המודעה המקורית לצפייה בפרטים המלאים.',
                          style: const TextStyle(
                            color: Color(0xFF475569),
                            fontSize: 13.5,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // Owner Section (features + match moved up, directly
                      // below the specs).
                      _SectionCardShell(
                        title: 'בעל הנכס',
                        icon: IconsaxPlusLinear.profile_2user,
                        child: _OwnerCard(property: p),
                      ),

                      // Reviews Section (Mockup Style)
                      if (reviews.isNotEmpty) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'חוות דעת',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            Text(
                              '${reviews.length} ביקורות',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _HorizontalReviewsList(reviews),
                        const SizedBox(height: 24),
                      ],

                      // Location Map Section
                      _SectionCardShell(
                        title: 'מיקום',
                        icon: IconsaxPlusLinear.location,
                        child: _MapSection(property: p),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Floating share button at bottom left
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 85,
            left: 20,
            child: ScaleBounce(
              onTap: onShareTap,
              scaleDownTo: 0.88,
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(
                  child: RentlyIcon(
                    IconsaxPlusLinear.export_2,
                    color: Colors.black,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),

          // Bottom action bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomBar(
              property: p,
              hasVirtualTour: hasVirtualTour,
              isLandlordPreview: isLandlordPreview,
              onLike: onLike,
              onTour: onTour,
              onEdit: onEdit,
            ),
          ),
        ],
      ),
    );
  }
}
