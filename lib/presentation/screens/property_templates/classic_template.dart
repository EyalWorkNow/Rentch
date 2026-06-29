part of '../property_detail_screen.dart';

/// Rently Classic — the polished, trustworthy DEFAULT property-detail layout.
///
/// This is the gold-standard look shown when no broker template is chosen (or
/// "קלאסי" is selected). Design goals: an edge-to-edge cinematic hero that runs
/// all the way to the top of the screen (under the status bar), a calm white
/// content sheet that lifts over the photo, refined typographic hierarchy, and
/// generous spacing tuned for OLDER users (large readable type, big tap targets,
/// high contrast). It renders the COMPLETE real data — price, address, specs,
/// features, match insight, affordability, 360°/3D tours, gallery, owner,
/// reviews and map — with no duplicate sections.
///
/// Self-contained, designer-owned unit. The dispatch in
/// `_PropertyDetailScreenState._buildContent` constructs it. Private helper
/// widgets used only by this layout live in this file; shared building blocks
/// (`_PropertyFactsCard`, `_FeatureWrap`, `_MatchInsightDropdown`,
/// `_AffordabilityStrip`, `_PropertySignalStrip`, `_OwnerCard`, `_MapSection`,
/// `_MediaTourCard`, `_TourEntryCard`, `_BottomBar`, …) stay in the library head.
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

  // Classic identity uses the live brand accent (teal for tenants / black for
  // brokers — never hard-coded). A neutral slate secondary keeps the body calm
  // and premium. Built per-build so it always tracks the runtime accent; never
  // `const` because it reads AppColors mutable statics.
  BrokerBrandingConfig get _branding => BrokerBrandingConfig(
        propertyTemplate: BrokerPropertyTemplate.rentlyClassic,
        primaryColorValue: AppColors.primary.toARGB32(),
        secondaryColorValue: 0xFF0F172A,
        accentColorValue: AppColors.primaryLight2.toARGB32(),
      );

  static const Color _ink = Color(0xFF0F172A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _hairline = Color(0xFFE9EEF3);

  @override
  Widget build(BuildContext context) {
    final p = property;
    final branding = _branding;
    final topInset = MediaQuery.of(context).padding.top;
    final has360 = p.hasPanoramaTour;
    final has3d =
        _scan3dGlbUrl(p) != null || _scan3dSplatUrl(p) != null;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // ── Cinematic hero — edge-to-edge, runs to the very TOP of the
              //    screen (under the status bar). Readable glass controls float
              //    inside the safe area; price + address sit on a soft scrim.
              SliverToBoxAdapter(
                child: _ClassicHero(
                  property: p,
                  controller: controller,
                  currentPage: currentPage,
                  onPageChanged: onPageChanged,
                  avgRating: avgRating,
                  topInset: topInset,
                  onBackTap: onBackTap,
                  onShareTap: onShareTap,
                ),
              ),

              // ── Content sheet — lifts over the photo with a big rounded top.
              SliverToBoxAdapter(
                child: Transform.translate(
                  offset: const Offset(0, -26),
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(28),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 150),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Grab handle — signals a scrollable sheet.
                        Center(
                          child: Container(
                            width: 44,
                            height: 5,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE2E8F0),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),

                        // ── Headline: title + address + price block.
                        _ClassicHeadline(property: p, title: title),
                        const SizedBox(height: 24),

                        // ── Property facts — rooms / size / floor / condition /
                        //    parking / elevator / entry / price. Judged first.
                        _SectionHeader(
                          'פרטי הנכס',
                          icon: IconsaxPlusLinear.building_3,
                          accent: branding.primaryColor,
                        ),
                        const SizedBox(height: 14),
                        _PropertyFactsCard(p),
                        const SizedBox(height: 28),

                        // ── Full feature/amenity set (no cap).
                        if (p.features.isNotEmpty) ...[
                          _SectionHeader(
                            'מאפיינים חשובים',
                            icon: IconsaxPlusLinear.flash_1,
                            accent: branding.primaryColor,
                          ),
                          const SizedBox(height: 14),
                          _FeatureWrap(features: p.features),
                          const SizedBox(height: 28),
                        ],

                        // ── "למה ההתאמה הזו?" — collapsible scorecard (tenants).
                        if (!isLandlordPreview) ...[
                          _MatchInsightDropdown(property: p),
                        ],

                        // ── Affordability + rights (rentals, real tenants).
                        if (!isLandlordPreview &&
                            p.transactionType ==
                                PropertyTransactionType.rent) ...[
                          _AffordabilityStrip(
                            property: p,
                            monthlyIncome: monthlyIncome,
                          ),
                          const SizedBox(height: 28),
                        ],

                        // ── Market signals / highlights.
                        if (_PropertySignalStrip.shouldShow(context, p)) ...[
                          _PropertySignalStrip(property: p),
                          const SizedBox(height: 28),
                        ],

                        // ── Virtual tours — 360° pano + 3D scan viewers. (The
                        //    previously-missing section, now first-class here.)
                        _SectionHeader(
                          has360 || has3d ? 'סיורים' : 'סיור וירטואלי',
                          icon: IconsaxPlusLinear.video_play,
                          accent: branding.primaryColor,
                        ),
                        const SizedBox(height: 14),
                        ..._buildTourCards(
                          context,
                          property: p,
                          branding: branding,
                          has360: has360,
                          has3d: has3d,
                        ),
                        const SizedBox(height: 28),

                        // ── Gallery thumbnails — tap to jump the hero carousel.
                        if (media.isNotEmpty) ...[
                          _SectionHeader(
                            'גלריה',
                            icon: IconsaxPlusLinear.gallery,
                            accent: branding.primaryColor,
                            trailing: '${media.length} תמונות',
                          ),
                          const SizedBox(height: 14),
                          _ClassicGalleryStrip(
                            media: media,
                            city: p.city,
                            controller: controller,
                          ),
                          const SizedBox(height: 28),
                        ],

                        // ── Source / origin listing.
                        if (p.url.isNotEmpty) ...[
                          _SectionHeader(
                            'אתר מקור',
                            icon: IconsaxPlusLinear.global,
                            accent: branding.primaryColor,
                          ),
                          const SizedBox(height: 12),
                          _ClassicSourceCard(
                            url: p.url,
                            accent: branding.primaryColor,
                          ),
                          const SizedBox(height: 28),
                        ],

                        // ── Owner / contact.
                        _SectionHeader(
                          'בעל הנכס',
                          icon: IconsaxPlusLinear.profile_2user,
                          accent: branding.primaryColor,
                        ),
                        const SizedBox(height: 14),
                        _OwnerCard(property: p),
                        const SizedBox(height: 28),

                        // ── Reviews.
                        if (reviews.isNotEmpty) ...[
                          _SectionHeader(
                            'חוות דעת',
                            icon: IconsaxPlusLinear.star_1,
                            accent: branding.primaryColor,
                            trailing: '${reviews.length} ביקורות',
                          ),
                          const SizedBox(height: 14),
                          _HorizontalReviewsList(reviews),
                          const SizedBox(height: 28),
                        ],

                        // ── Location / map.
                        _SectionHeader(
                          'מיקום',
                          icon: IconsaxPlusLinear.location,
                          accent: branding.primaryColor,
                        ),
                        const SizedBox(height: 14),
                        _MapSection(property: p),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // ── Bottom action bar (contract/tour CTA + like + edit).
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

  /// Tour cards mirror the parity logic: prefer real 360°/3D viewers, else a
  /// single living entry card (video / processing / "request a scan").
  List<Widget> _buildTourCards(
    BuildContext context, {
    required RentalProperty property,
    required BrokerBrandingConfig branding,
    required bool has360,
    required bool has3d,
  }) {
    const surface = Colors.white;
    const onSurface = _ink;
    const muted = _muted;
    final cards = <Widget>[];

    if (has360) {
      cards.add(_MediaTourCard(
        icon: Icons.threesixty_rounded,
        title: 'סיור 360°',
        subtitle: 'סיור פנורמי אינטראקטיבי — הסתובבו בדירה',
        branding: branding,
        surface: surface,
        onSurface: onSurface,
        muted: muted,
        onTap: () =>
            PanoramaPsvTourView.open(context, property.panoramaTour!),
      ));
    }
    if (has3d) {
      cards.add(_MediaTourCard(
        icon: Icons.view_in_ar_rounded,
        title: 'סריקת תלת-מימד',
        subtitle: 'מודל תלת-מימדי — סובבו והתקרבו מכל זווית',
        branding: branding,
        surface: surface,
        onSurface: onSurface,
        muted: muted,
        onTap: () => Scan3dViewerScreen.open(
          context,
          meshGlbUrl: _scan3dGlbUrl(property),
          splatUrl: _scan3dSplatUrl(property),
          title: 'סריקת תלת-מימד',
        ),
      ));
    }

    if (cards.isEmpty) {
      cards.add(_TourEntryCard(
        property: property,
        branding: branding,
        hasVirtualTour: hasVirtualTour,
        surface: surface,
        onSurface: onSurface,
        muted: muted,
        onTour: onTour,
      ));
      return cards;
    }

    // Interleave spacing between multiple tour cards.
    final spaced = <Widget>[];
    for (var i = 0; i < cards.length; i++) {
      if (i > 0) spaced.add(const SizedBox(height: 12));
      spaced.add(cards[i]);
    }
    return spaced;
  }
}

// ─── Hero ─────────────────────────────────────────────────────────────────────

/// Edge-to-edge cinematic hero: full-bleed photo carousel that runs under the
/// status bar, glass back/share controls inside the safe area, a soft bottom
/// scrim, rating chip, address + price overlay, and carousel dots.
class _ClassicHero extends StatelessWidget {
  const _ClassicHero({
    required this.property,
    required this.controller,
    required this.currentPage,
    required this.onPageChanged,
    required this.avgRating,
    required this.topInset,
    required this.onBackTap,
    required this.onShareTap,
  });

  final RentalProperty property;
  final PageController controller;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final double avgRating;
  final double topInset;
  final VoidCallback onBackTap;
  final VoidCallback onShareTap;

  @override
  Widget build(BuildContext context) {
    final media = property.media;
    final safeCurrent =
        media.isEmpty ? 0 : currentPage.clamp(0, media.length - 1).toInt();
    // Tall, immersive hero scaled to the screen; bounded for very tall devices.
    final heroHeight =
        (MediaQuery.of(context).size.height * 0.56).clamp(360.0, 540.0);

    return SizedBox(
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Full-bleed media — to the very top of the screen.
          media.isEmpty
              ? _ImageFallback(city: property.city)
              : PageView.builder(
                  controller: controller,
                  onPageChanged: onPageChanged,
                  itemCount: media.length,
                  itemBuilder: (_, index) => SafeMedia(
                    media: media[index],
                    fit: BoxFit.cover,
                    fallback: _ImageFallback(city: property.city),
                    videoMode: SafeVideoDisplayMode.playback,
                  ),
                ),

          // Top scrim — keeps the glass controls legible over bright photos.
          IgnorePointer(
            child: Container(
              height: topInset + 90,
              alignment: Alignment.topCenter,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.32),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Bottom scrim — anchors the address/price overlay + sheet seam.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                height: 220,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.62),
                      Colors.black.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Carousel dots (above the sheet seam).
          if (media.length > 1)
            Positioned(
              bottom: 52,
              left: 0,
              right: 0,
              child: _CarouselDots(count: media.length, current: safeCurrent),
            ),

          // Glass controls — inside the safe area.
          Positioned(
            top: topInset + 10,
            left: 18,
            right: 18,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _GlassCircleButton(
                  icon: IconsaxPlusLinear.arrow_right,
                  onTap: onBackTap,
                ),
                if (avgRating > 0) _HeroRatingChip(rating: avgRating),
                _GlassCircleButton(
                  icon: IconsaxPlusLinear.export_2,
                  onTap: onShareTap,
                ),
              ],
            ),
          ),

          // Transaction-type capsule, top-aligned with the price overlay.
          Positioned(
            left: 20,
            right: 20,
            bottom: 46,
            child: _HeroCaption(property: property),
          ),
        ],
      ),
    );
  }
}

/// Translucent round button used for the hero controls (back / share).
class _GlassCircleButton extends StatelessWidget {
  const _GlassCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ScaleBounce(
      onTap: onTap,
      scaleDownTo: 0.86,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Glass rating chip floating at the top of the hero.
class _HeroRatingChip extends StatelessWidget {
  const _HeroRatingChip({required this.rating});
  final double rating;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded,
                  color: Color(0xFFFFC53D), size: 19),
              const SizedBox(width: 5),
              Text(
                rating.toStringAsFixed(1),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Address + transaction capsule that sits over the bottom scrim of the hero.
class _HeroCaption extends StatelessWidget {
  const _HeroCaption({required this.property});
  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            '${property.transactionLabel} · ${property.propertyType}',
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(IconsaxPlusBold.location,
                color: Colors.white, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                property.address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  shadows: [
                    Shadow(color: Colors.black54, blurRadius: 8),
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

// ─── Headline (title + price) ───────────────────────────────────────────────────

/// Title, full address and a prominent price block at the top of the sheet.
class _ClassicHeadline extends StatelessWidget {
  const _ClassicHeadline({required this.property, required this.title});

  final RentalProperty property;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _ClassicTemplate._ink,
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.6,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const RentlyIcon(IconsaxPlusLinear.location,
                size: 17, color: _ClassicTemplate._muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                property.address,
                style: const TextStyle(
                  color: _ClassicTemplate._muted,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        // Price block — large, high-contrast, with suffix.
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              property.priceLabel,
              style: TextStyle(
                color: AppColors.primaryDark,
                fontSize: 32,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                property.priceSuffixLabel,
                style: const TextStyle(
                  color: _ClassicTemplate._muted,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── Section header ─────────────────────────────────────────────────────────────

/// Consistent section header: tinted icon chip + bold Hebrew title + optional
/// trailing count. Large and high-contrast for older readers.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
    this.title, {
    required this.icon,
    required this.accent,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: accent, size: 19),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: _ClassicTemplate._ink,
              letterSpacing: -0.3,
            ),
          ),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: _ClassicTemplate._muted,
            ),
          ),
      ],
    );
  }
}

// ─── Gallery strip ──────────────────────────────────────────────────────────────

/// Horizontal thumbnail strip — tapping a tile jumps the hero carousel.
class _ClassicGalleryStrip extends StatelessWidget {
  const _ClassicGalleryStrip({
    required this.media,
    required this.city,
    required this.controller,
  });

  final List<PropertyMedia> media;
  final String city;
  final PageController controller;

  @override
  Widget build(BuildContext context) {
    return FadeSlideEntrance(
      duration: const Duration(milliseconds: 420),
      offset: const Offset(0.0, 24.0),
      child: SizedBox(
        height: 116,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: media.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final item = media[index];
            return ScaleBounce(
              onTap: () {
                if (controller.hasClients) {
                  controller.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                }
              },
              scaleDownTo: 0.92,
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: 116,
                      height: 84,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          SafeMedia(
                            media: item,
                            fit: BoxFit.cover,
                            fallback: _ImageFallback(city: city),
                          ),
                          if (item.isVideo)
                            const Center(
                              child: Icon(Icons.play_circle_fill_rounded,
                                  color: Colors.white, size: 30),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    item.isVideo ? 'סרטון' : 'תמונה ${index + 1}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: _ClassicTemplate._muted,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─── Source card ────────────────────────────────────────────────────────────────

/// Origin-listing card with the source host and a "view original" action.
class _ClassicSourceCard extends StatelessWidget {
  const _ClassicSourceCard({required this.url, required this.accent});

  final String url;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final host = Uri.parse(url).host;
    return GestureDetector(
      onTap: () async {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _ClassicTemplate._hairline),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(IconsaxPlusLinear.link, color: accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    host.isEmpty ? 'המודעה המקורית' : host,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: _ClassicTemplate._ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'פתחו את המודעה לצפייה בפרטים המלאים',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500,
                      color: _ClassicTemplate._muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'צפה במקור',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
