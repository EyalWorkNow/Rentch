part of '../property_detail_screen.dart';

/// Aura Hero (a.k.a. `acidHero`) — the most EXPRESSIVE template. An edge-to-edge
/// hero that reaches the very top of the screen, washed by a vibrant brand
/// "aura" gradient, with glass safe-area controls and a glowing rating chip
/// overlaid low on the image. Below the hero, a vivid aura panel carries
/// oversized price typography, the transaction badge, and a quick-facts rail —
/// then the shared full-parity content block renders every remaining section.
///
/// The aura gradient is built FROM the live brand palette (`branding` +
/// runtime-swappable [AppColors.primary]) so it re-themes for brokers (black)
/// vs. tenants (teal) without hard-coded accents.
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
    final topInset = MediaQuery.of(context).padding.top;
    // Aura accent derived from the live brand palette so it re-themes correctly.
    final aura = branding.primaryColor;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          // Edge-to-edge: no top padding so the hero reaches the very top; the
          // top bar is overlaid inside the status-bar safe area.
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 128),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Edge-to-edge hero with overlaid glass controls ──────────
                SizedBox(
                  // Tall, immersive hero (extends under the status bar).
                  height: 440 + topInset,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: _TemplateHeroMedia(
                          property: property,
                          controller: controller,
                          currentPage: currentPage,
                          onPageChanged: onPageChanged,
                          height: 440 + topInset,
                          radius: 0,
                          overlay: _AcidHeroOverlay(
                            property: property,
                            branding: branding,
                            avgRating: avgRating,
                            aura: aura,
                          ),
                        ),
                      ),
                      Positioned(
                        top: topInset + 12,
                        left: 18,
                        right: 18,
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
                // ── Vivid aura price panel (pulled up to overlap the hero) ──
                Transform.translate(
                  offset: const Offset(0, -34),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                    child: _AcidPriceCard(
                      property: property,
                      branding: branding,
                      aura: aura,
                    ),
                  ),
                ),
                // ── Floor / type quick pill ─────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                  child: _GlassFilterPill(
                    icon: IconsaxPlusLinear.layer,
                    label: property.floor.isEmpty
                        ? property.propertyType
                        : AppLocalizations.of(context)!
                            .auraHeroTemplateD068bb57(property.floor),
                    branding: branding,
                    aura: aura,
                  ),
                ),
                const SizedBox(height: 24),
                // ── Shared full-parity content (no duplicates) ──────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
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
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Overlay painted on top of the edge-to-edge hero image: a bottom aura wash
/// for legibility, the oversized address/city headline, a glowing rating chip,
/// and a glass size badge. All colours derive from the brand palette.
class _AcidHeroOverlay extends StatelessWidget {
  const _AcidHeroOverlay({
    required this.property,
    required this.branding,
    required this.avgRating,
    required this.aura,
  });

  final RentalProperty property;
  final BrokerBrandingConfig branding;
  final double avgRating;
  final Color aura;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Vibrant aura wash: brand-tinted at the bottom for readable text,
        // fading to transparent so the photo stays vivid up top.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.42, 0.74, 1.0],
                colors: [
                  Colors.black.withValues(alpha: 0.26),
                  Colors.transparent,
                  aura.withValues(alpha: 0.42),
                  branding.secondaryColor.withValues(alpha: 0.92),
                ],
              ),
            ),
          ),
        ),
        // Headline + rating sit low-left (logical-start in RTL).
        Positioned(
          left: 20,
          right: 20,
          bottom: 50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: _AuraGlowChip(
                      icon: IconsaxPlusBold.star_1,
                      label: avgRating > 0
                          ? avgRating.toStringAsFixed(1)
                          : AppLocalizations.of(context)!
                              .auraHeroTemplate08bca18d,
                      aura: aura,
                      secondary: branding.secondaryColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: _AuraGlowChip(
                      icon: IconsaxPlusLinear.maximize_3,
                      label: AppLocalizations.of(context)!
                          .auraHeroTemplateFdb4eac7(property.sizeM2),
                      aura: aura,
                      secondary: branding.secondaryColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                property.address,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  height: 1.06,
                  letterSpacing: -0.5,
                  fontWeight: FontWeight.w900,
                  shadows: [
                    Shadow(
                      color: Color(0x66000000),
                      blurRadius: 16,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    IconsaxPlusBold.location,
                    size: 16,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      '${property.city} · ${property.transactionLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.88),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Small glowing glass chip used over the hero (rating / size). The glow tint
/// comes from the live brand accent so it re-themes.
class _AuraGlowChip extends StatelessWidget {
  const _AuraGlowChip({
    required this.icon,
    required this.label,
    required this.aura,
    required this.secondary,
  });

  final IconData icon;
  final String label;
  final Color aura;
  final Color secondary;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(16), sigmaY: PlatformFx.blurSigma(16)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
            boxShadow: [
              BoxShadow(
                color: aura.withValues(alpha: 0.45),
                blurRadius: 18,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glass quick-fact pill (floor / property type) under the price panel.
class _GlassFilterPill extends StatelessWidget {
  const _GlassFilterPill({
    required this.icon,
    required this.label,
    required this.branding,
    required this.aura,
  });

  final IconData icon;
  final String label;
  final BrokerBrandingConfig branding;
  final Color aura;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: aura.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: aura.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: aura.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: aura, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: branding.secondaryColor,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The signature aura price card: a vivid brand-gradient panel with oversized
/// price typography, a transaction badge, and a compact rooms/size/floor rail.
/// The gradient is built FROM the brand palette so it re-themes per account.
class _AcidPriceCard extends StatelessWidget {
  const _AcidPriceCard({
    required this.property,
    required this.branding,
    required this.aura,
  });

  final RentalProperty property;
  final BrokerBrandingConfig branding;
  final Color aura;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            branding.secondaryColor,
            Color.lerp(branding.secondaryColor, aura, 0.55) ??
                branding.secondaryColor,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: aura.withValues(alpha: 0.40),
            blurRadius: 34,
            spreadRadius: -8,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  property.propertyType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              // Transaction badge in the accent for a vivid pop.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: branding.accentColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  property.transactionLabel,
                  style: TextStyle(
                    color: branding.secondaryColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Oversized price headline.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text(
                  property.priceLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 44,
                    height: 1.0,
                    letterSpacing: -1.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Text(
                  property.priceSuffixLabel,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.70),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Compact rooms / size / floor rail (legible over the gradient).
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Row(
              children: [
                _AuraStat(
                  icon: IconsaxPlusBold.building,
                  value: property.roomsLabel,
                  label: AppLocalizations.of(context)!.auraHeroTemplateB50b3974,
                ),
                _AuraStatDivider(),
                _AuraStat(
                  icon: IconsaxPlusBold.maximize_3,
                  value: '${property.sizeM2}',
                  label: AppLocalizations.of(context)!.auraHeroTemplateD3b9013b,
                ),
                _AuraStatDivider(),
                _AuraStat(
                  icon: IconsaxPlusBold.layer,
                  value: property.floor.isEmpty ? '—' : property.floor,
                  label: AppLocalizations.of(context)!.auraHeroTemplate047e630b,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AuraStat extends StatelessWidget {
  const _AuraStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 19, color: Colors.white.withValues(alpha: 0.90)),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.62),
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AuraStatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 38,
      color: Colors.white.withValues(alpha: 0.14),
    );
  }
}
