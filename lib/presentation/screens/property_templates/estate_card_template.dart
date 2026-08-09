part of '../property_detail_screen.dart';

/// Estate Card (`estateCard`) — a PREMIUM, boutique-estate-agency identity.
///
/// An edge-to-edge hero bleeds to the very top with a cinematic dark scrim, a
/// refined translucent top bar in the safe area, and an over-image "kicker"
/// (transaction · city) set in fine letter-spaced caps. A single elegant white
/// "estate card" floats UP over the hero — hairline borders, a champagne-gold
/// rule, refined price typography with suffix, address, and a dense facts row —
/// then the shared full-parity content block renders every remaining section.
///
/// Self-contained and designer-owned. Exclusive helpers used only by this
/// layout live in this file ([_EstateGoldRule], [_EstateKicker],
/// [_EstateFactChips], [_EstateSectionFrame]). Shared building blocks (top bar,
/// hero media, parity sections) stay in the library head. NO duplicate
/// galleries or sections — the hero + parity block own all data exactly once.
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

  // A tasteful champagne-gold accent that reads "luxury/boutique" on ANY brand
  // without overriding the brand's own primary/secondary. Used only for fine
  // detailing (rules, the estate monogram ring, the "חדש" pill border).
  static const Color _gold = Color(0xFFB89B5E);
  static const Color _goldSoft = Color(0xFFE9DEC4);

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    // Hero bleeds to the very top; its bottom tucks UNDER the floating card.
    const heroHeight = 540.0;
    const cardOverlap = 56.0; // how far the estate card rides up over the hero

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            // No top inset — the image bleeds to the very top; the top bar
            // carries the status-bar safe area instead.
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── HERO + floating estate card ──────────────────────────────
                SizedBox(
                  // Reserve the hero height plus the part of the card that sits
                  // below the image, so nothing is clipped.
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Edge-to-edge hero with a refined dark scrim for legible
                      // overlay controls + the over-image kicker line.
                      SizedBox(
                        height: heroHeight,
                        child: _TemplateHeroMedia(
                          property: property,
                          controller: controller,
                          currentPage: currentPage,
                          onPageChanged: onPageChanged,
                          height: heroHeight,
                          radius: 0,
                          alignment: Alignment.center,
                          overlay: _EstateHeroScrim(
                            property: property,
                            branding: branding,
                            topInset: topInset,
                          ),
                        ),
                      ),

                      // Translucent, safe-area top bar (brand mark + controls).
                      Positioned(
                        top: topInset + 12,
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

                      // The floating "estate card" — the signature element.
                      Positioned(
                        left: 18,
                        right: 18,
                        top: heroHeight - cardOverlap,
                        child: FadeSlideEntrance(
                          offset: const Offset(0, 26),
                          duration: const Duration(milliseconds: 520),
                          child: _EstatePriceCard(
                            property: property,
                            branding: branding,
                            gold: _gold,
                            goldSoft: _goldSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Spacer that absorbs the part of the card below the hero plus
                // breathing room before the parity block.
                SizedBox(
                  height: _estateCardEstimatedHeight(property) -
                      cardOverlap +
                      18,
                ),

                // ── Shared full-parity content (single source of all data) ───
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

  /// Conservative height estimate for the floating card so the spacer below it
  /// never clips the parity block. The card content is fixed-structure (header,
  /// gold rule, price row, address, facts), so a constant is safe and avoids a
  /// layout pass. Facts can wrap to two lines on narrow phones → add headroom.
  static double _estateCardEstimatedHeight(RentalProperty property) => 286;
}

/// Cinematic dark scrim + over-image "kicker" for the estate hero. Keeps the
/// brand mark / controls legible and sets a refined boutique tone with a fine
/// letter-spaced caps line (transaction · city) low on the image.
class _EstateHeroScrim extends StatelessWidget {
  const _EstateHeroScrim({
    required this.property,
    required this.branding,
    required this.topInset,
  });

  final RentalProperty property;
  final BrokerBrandingConfig branding;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Top wash → keeps the translucent controls readable.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [
                  Colors.black.withValues(alpha: 0.34),
                  Colors.black.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          // Bottom wash → seats the kicker + tucks under the floating card.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.center,
                colors: [
                  Colors.black.withValues(alpha: 0.62),
                  Colors.black.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          // Over-image kicker: refined caps line, lifted above where the card
          // overlaps so it stays fully visible.
          Positioned(
            left: 26,
            right: 26,
            bottom: 84,
            child: _EstateKicker(
              property: property,
            ),
          ),
        ],
      ),
    );
  }
}

/// A fine letter-spaced caps line over the hero: "להשכרה · תל אביב" with a
/// small gold tick — the boutique-agency signature.
class _EstateKicker extends StatelessWidget {
  const _EstateKicker({required this.property});

  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      property.transactionLabel,
      if (property.city.trim().isNotEmpty) property.city.trim(),
    ];
    return Row(
      children: [
        Container(
          width: 22,
          height: 1.4,
          color: _EstateCardTemplate._gold,
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            parts.join('   ·   '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.4,
              height: 1.2,
              shadows: [
                Shadow(color: Colors.black54, blurRadius: 8),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The signature floating estate card: hairline-framed white surface with a
/// soft elevation, a refined eyebrow (property type in caps), a champagne-gold
/// rule, large price + suffix, an optional "חדש" gold capsule, the address,
/// and a dense facts row. Renders REAL property data only — no fake content.
class _EstatePriceCard extends StatelessWidget {
  const _EstatePriceCard({
    required this.property,
    required this.branding,
    required this.gold,
    required this.goldSoft,
  });

  final RentalProperty property;
  final BrokerBrandingConfig branding;
  final Color gold;
  final Color goldSoft;

  @override
  Widget build(BuildContext context) {
    final ppsm = property.pricePerSquareMeter;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.black.withValues(alpha: 0.05)),
        boxShadow: [
          // Soft, refined estate elevation (two layers for depth).
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 32,
            spreadRadius: -6,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Eyebrow: property type in fine caps + a small estate monogram ring.
          Row(
            children: [
              Expanded(
                child: Text(
                  property.propertyType,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: branding.secondaryColor.withValues(alpha: 0.72),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
              if (property.isVerifiedListing) ...[
                Icon(IconsaxPlusBold.verify, size: 16, color: gold),
                const SizedBox(width: 5),
                Text(
                  AppLocalizations.of(context)!.estateCardTemplate7de9ac58,
                  style: TextStyle(
                    color: gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          _EstateGoldRule(gold: gold, goldSoft: goldSoft),
          const SizedBox(height: 16),

          // Price row: large value + suffix, with an optional "חדש" gold pill.
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: property.priceLabel,
                        style: TextStyle(
                          color: branding.secondaryColor,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.6,
                          height: 1.0,
                        ),
                      ),
                      TextSpan(
                        text: '  ${property.priceSuffixLabel}',
                        style: TextStyle(
                          color: branding.secondaryColor
                              .withValues(alpha: 0.55),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              if (property.isNewListing)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: goldSoft.withValues(alpha: 0.34),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: gold.withValues(alpha: 0.45)),
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.estateCardTemplate08bca18d,
                    style: TextStyle(
                      color: gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
            ],
          ),

          // Optional refined per-m² line (real, derived) — adds "boutique
          // valuation" texture without clutter.
          if (ppsm != null) ...[
            const SizedBox(height: 6),
            Text(
              AppLocalizations.of(context)!
                  .estateCardTemplateCdc7944d(_estateFormat(ppsm)),
              style: TextStyle(
                color: branding.secondaryColor.withValues(alpha: 0.50),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],

          const SizedBox(height: 14),

          // Address with a fine location glyph.
          Row(
            children: [
              Icon(
                IconsaxPlusLinear.location,
                size: 17,
                color: branding.primaryColor,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  property.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: branding.secondaryColor.withValues(alpha: 0.82),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Dense facts row (rooms · size · floor · condition).
          _EstateFactChips(property: property, branding: branding),
        ],
      ),
    );
  }
}

/// A thin champagne-gold rule with a small diamond node centred — fine estate
/// detailing that separates the eyebrow from the price.
class _EstateGoldRule extends StatelessWidget {
  const _EstateGoldRule({required this.gold, required this.goldSoft});

  final Color gold;
  final Color goldSoft;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 2,
          decoration: BoxDecoration(
            color: gold,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 6),
        Transform.rotate(
          angle: 0.785398, // 45° — a small diamond node
          child: Container(width: 5, height: 5, color: gold),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Container(
            height: 1,
            color: goldSoft.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

/// Refined fact chips for the estate card — big targets, big type, on-brand,
/// hairline framed. Renders ONLY facts that exist on the property.
class _EstateFactChips extends StatelessWidget {
  const _EstateFactChips({required this.property, required this.branding});

  final RentalProperty property;
  final BrokerBrandingConfig branding;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final facts = <_TemplateFact>[
      _TemplateFact(IconsaxPlusLinear.building,
          l10n.estateCardTemplateD886d07f(property.roomsLabel)),
      _TemplateFact(IconsaxPlusLinear.maximize_3,
          l10n.estateCardTemplateFdb4eac7(property.sizeM2)),
      if (property.floor.trim().isNotEmpty)
        _TemplateFact(IconsaxPlusLinear.layer,
            l10n.estateCardTemplateD068bb57(property.floor)),
      if (property.condition.trim().isNotEmpty)
        _TemplateFact(IconsaxPlusLinear.star, property.condition),
    ];

    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: facts
          .map(
            (fact) => Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.slate50,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(fact.icon, size: 17, color: branding.primaryColor),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      fact.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: branding.secondaryColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

/// Compact thousands formatter for the per-m² figure (mirrors model style).
String _estateFormat(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}
