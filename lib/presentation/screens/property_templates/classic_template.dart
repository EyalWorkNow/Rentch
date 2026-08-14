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
    required this.onBoost,
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
  final VoidCallback onBoost;
  final VoidCallback onLike;
  final VoidCallback onTour;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final p = property;
    final sections = _sections(context, l10n, p);
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

              // Below-the-fold content as a lazy sliver (was a single eager
              // Column built synchronously on first frame — specs,
              // enrichment, features, match insight, gallery thumbnails,
              // owner, reviews and the map section all constructed and
              // laid out at once, which is exactly the frame-blocking cost
              // that makes the page feel unresponsive to scroll/tap right
              // after opening). Flutter now only builds/lays out each
              // section as it scrolls into view — same fix already applied
              // to the broker templates' _ParitySections, ported here since
              // Classic has its own independent content list.
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 140),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => sections[index],
                    childCount: sections.length,
                  ),
                ),
              ),
            ],
          ),

          // Floating action at bottom-left: BOOST for the landlord (their own
          // listing), SHARE for everyone else.
          Positioned(
            bottom: MediaQuery.of(context).padding.bottom + 85,
            left: 20,
            child: isLandlordPreview
                // Boost — premium indigo pill (matches the PRO brand accent).
                ? ScaleBounce(
                    onTap: onBoost,
                    scaleDownTo: 0.9,
                    child: Container(
                      height: 54,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF5B61F6), Color(0xFF4F46E5)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color:
                                const Color(0xFF4F46E5).withValues(alpha: 0.38),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const RentlyIcon(IconsaxPlusBold.flash_1,
                              color: Colors.white, size: 22),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              l10n.classicTemplate88aea894,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ScaleBounce(
                    onTap: onShareTap,
                    scaleDownTo: 0.88,
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.slate200),
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

  /// The ordered list of below-the-fold section widgets (was the Column's
  /// `children` inline above) — extracted so the lazy SliverList above and
  /// any future eager fallback can share the exact same content.
  List<Widget> _sections(
      BuildContext context, AppLocalizations l10n, RentalProperty p) {
    return [
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
                    color: AppColors.ink,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const RentlyIcon(IconsaxPlusLinear.location,
                        size: 16, color: AppColors.slate500),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        p.address,
                        style: const TextStyle(
                          color: AppColors.slate500,
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
      Text(
        l10n.classicTemplate220d2733,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w900,
          color: AppColors.ink,
        ),
      ),
      const SizedBox(height: 12),
      _PropertyFactsCard(p),
      const SizedBox(height: 24),

      // ── Phase-1 listing intelligence: price/neighborhood
      // badges (shown only if backend enrichment is present)
      // + the "שאל את Rently" Q&A entry. Self-hides per-field
      // and is omitted entirely in landlord preview.
      if (!isLandlordPreview) ...[
        _ListingEnrichmentBlock(property: p, title: title),
        const SizedBox(height: 24),
      ],

      // ── Description — was captured (website's Ezra
      // publisher flow always sends it) but had no field in
      // the app's model at all: silently dropped, never shown
      // anywhere. Now modeled (RentalProperty.description)
      // and surfaced here, right above features — this is the
      // actually-used default layout (Classic), unlike the
      // broker-template branch in property_detail_screen.dart.
      if (p.description.trim().isNotEmpty) ...[
        _SectionCardShell(
          title: l10n.propertyDetailScreenDescription,
          icon: IconsaxPlusLinear.document_text,
          child: Text(
            p.description.trim(),
            style: const TextStyle(
                fontSize: 14.5, height: 1.5, color: AppColors.ink),
          ),
        ),
      ],

      // ── ALL tags/features right under the specs. Shows the
      // FULL set (no cap) so the tenant sees exactly what the
      // property has.
      if (p.features.isNotEmpty) ...[
        _SectionCardShell(
          title: l10n.classicTemplate64680a66,
          icon: IconsaxPlusLinear.flash_1,
          child: _FeatureWrap(features: p.features),
        ),
      ],

      // ── "למה ההתאמה הזו?" — collapsible dropdown (collapsed
      // by default) with a "?" icon; expands the scorecard.
      if (!isLandlordPreview) _MatchInsightDropdown(property: p),

      // Affordability + rights (rentals only, real tenants).
      if (!isLandlordPreview &&
          p.transactionType == PropertyTransactionType.rent) ...[
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
            Text(
              l10n.classicTemplateEed2fbf3,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            Text(
              l10n.classicTemplateAb29f776(media.length),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.slate500,
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
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = media[index];
                return ScaleBounce(
                  onTap: () {
                    controller.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  scaleDownTo: 0.90,
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: SizedBox(
                          width: 100,
                          height: 70,
                          child: SafeMedia(
                            media: item,
                            fit: BoxFit.cover,
                            fallback: _ImageFallback(city: p.city),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.isVideo
                            ? l10n.classicTemplateF5686614
                            : l10n.classicTemplate0429d88a(index + 1),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.slate500,
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
            Text(
              l10n.classicTemplateCb66c16b,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            GestureDetector(
              onTap: () async {
                await launchUrl(Uri.parse(p.url),
                    mode: LaunchMode.externalApplication);
              },
              child: Text(
                l10n.classicTemplate5e4548cf,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.tealBrand,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.classicTemplateB58f6b9c(Uri.parse(p.url).host),
          style: const TextStyle(
            color: AppColors.slate600,
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 24),
      ],

      // Owner Section (features + match moved up, directly
      // below the specs).
      _SectionCardShell(
        title: l10n.classicTemplateC1a89075,
        icon: IconsaxPlusLinear.profile_2user,
        child: _OwnerCard(property: p),
      ),

      // Reviews Section (Mockup Style)
      if (reviews.isNotEmpty) ...[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              l10n.classicTemplate1c5efd6c,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            Text(
              l10n.classicTemplate16c30b46(reviews.length),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.slate500,
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
        title: l10n.classicTemplate26d0e7de,
        icon: IconsaxPlusLinear.location,
        child: _MapSection(property: p),
      ),
    ];
  }
}
