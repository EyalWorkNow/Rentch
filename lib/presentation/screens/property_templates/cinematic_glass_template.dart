part of '../property_detail_screen.dart';

/// Cinematic Glass (`cinematicGlass`) — a dark, dramatic "property reveal".
///
/// The full media gallery bleeds edge-to-edge to the very top as a swipeable,
/// cinematic backdrop (carousel dots + video supported via [_TemplateHeroMedia]).
/// A layered scrim keeps the moody mood while guaranteeing high-contrast text;
/// a soft brand-accent glow rims the hero. Frosted-glass cards float over the
/// imagery: a translucent top bar, a price/identity block, and a stats rail.
/// Below, the shared parity block renders EVERY real section in its dark glass
/// variant so the whole experience stays cinematic — and crucially never
/// duplicates the gallery, which the parity block already owns.
///
/// Built purely from shared building blocks + private helpers in this file;
/// fully designer-owned. On-brand glow comes from [AppColors.primary]
/// (auto-black for brokers, teal otherwise) — never a hard-coded accent.
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
    final size = MediaQuery.sizeOf(context).height;
    final topInset = MediaQuery.of(context).padding.top;
    // The cinematic hero fills most of the first screen; the overlaid identity
    // block + glass body then scroll up over it.
    final heroHeight = (size * 0.66).clamp(420.0, 620.0);
    // The brand accent (black for brokers / teal otherwise). Read live so a
    // role switch repaints the glow; never const so we respect the const-trap.
    final accent = AppColors.primary;

    return ColoredBox(
      // A near-black canvas so any over-scroll / bounce reveals cinematic dark,
      // never a jarring white flash.
      color: const Color(0xFF0A0B0F),
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              children: [
                // ── Cinematic hero: the full swipeable gallery, edge-to-edge
                //    to the very top. Carousel dots + video come for free.
                SizedBox(
                  height: heroHeight,
                  width: double.infinity,
                  child: _TemplateHeroMedia(
                    property: property,
                    controller: controller,
                    currentPage: currentPage,
                    onPageChanged: onPageChanged,
                    height: heroHeight,
                    radius: 0,
                    alignment: Alignment.center,
                    overlay: _CinematicScrim(
                      base: branding.secondaryColor,
                      accent: accent,
                    ),
                  ),
                ),

                // ── Floating glass top bar (back / brand / share). Honours the
                //    status-bar safe area; translucent so the image shows through.
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

                // ── Identity block overlaid low on the hero: transaction kicker,
                //    glowing price, address, and a frosted stats rail. Sits in a
                //    column anchored to the hero's lower third so it reads as a
                //    cinematic title card.
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 22,
                  child: _CinematicIdentity(
                    property: property,
                    accent: accent,
                  ),
                ),
              ],
            ),
          ),

          // ── Body: the shared parity block in its dark-glass variant, floating
          //    over the brand-dark canvas with a frosted top edge so it feels
          //    continuous with the cinematic hero. Renders EVERY real section
          //    (facts, owner, match, tours/360/3D, map, reviews, CTA) once.
          SliverToBoxAdapter(
            child: _CinematicBody(
              base: branding.secondaryColor,
              accent: accent,
              child: _ParitySections(
                property: property,
                branding: branding,
                controller: controller,
                reviews: reviews,
                hasVirtualTour: hasVirtualTour,
                isLandlordPreview: isLandlordPreview,
                onShareTap: onShareTap,
                onTour: onTour,
                dark: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Multi-stop cinematic scrim painted over the hero media. A short dark wash at
/// the very top keeps the glass top-bar legible; the heavy lower gradient melts
/// the imagery into the brand-dark body and guarantees white text contrast. A
/// faint accent bloom near the bottom adds the signature glow.
class _CinematicScrim extends StatelessWidget {
  const _CinematicScrim({required this.base, required this.accent});

  final Color base;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.30, 0.62, 0.86, 1.0],
              colors: [
                Colors.black.withValues(alpha: 0.55),
                Colors.black.withValues(alpha: 0.10),
                base.withValues(alpha: 0.34),
                base.withValues(alpha: 0.78),
                base.withValues(alpha: 0.98),
              ],
            ),
          ),
        ),
        // Signature accent bloom rising from the lower-left.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(-0.7, 1.15),
              radius: 1.1,
              colors: [
                accent.withValues(alpha: 0.30),
                accent.withValues(alpha: 0.0),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The overlaid cinematic "title card": transaction kicker, glowing price and
/// suffix, address, and a frosted-glass stats rail (rooms / size / floor).
/// All copy is real property data; entrance is a tasteful staggered fade-slide.
class _CinematicIdentity extends StatelessWidget {
  const _CinematicIdentity({required this.property, required this.accent});

  final RentalProperty property;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeSlideEntrance(
          duration: const Duration(milliseconds: 420),
          offset: const Offset(0, 22),
          child: _TransactionKicker(
            label: property.transactionLabel,
            accent: accent,
          ),
        ),
        const SizedBox(height: 14),
        FadeSlideEntrance(
          delay: const Duration(milliseconds: 80),
          duration: const Duration(milliseconds: 460),
          offset: const Offset(0, 26),
          child: _GlowingPrice(property: property, accent: accent),
        ),
        const SizedBox(height: 12),
        FadeSlideEntrance(
          delay: const Duration(milliseconds: 150),
          duration: const Duration(milliseconds: 460),
          offset: const Offset(0, 26),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Icon(
                  IconsaxPlusBold.location,
                  size: 19,
                  color: Colors.white.withValues(alpha: 0.92),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  property.address,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    height: 1.3,
                    fontWeight: FontWeight.w800,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        FadeSlideEntrance(
          delay: const Duration(milliseconds: 220),
          duration: const Duration(milliseconds: 480),
          offset: const Offset(0, 28),
          child: _GlassStatsRail(property: property, accent: accent),
        ),
      ],
    );
  }
}

/// Small glowing pill announcing the transaction type (השכרה / מכירה).
class _TransactionKicker extends StatelessWidget {
  const _TransactionKicker({required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(14), sigmaY: PlatformFx.blurSigma(14)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: accent.withValues(alpha: 0.55), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.9),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.2,
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

/// The headline price: oversized, white, with an accent under-glow and the
/// suffix (לחודש / למכירה) as a quieter trailing label.
class _GlowingPrice extends StatelessWidget {
  const _GlowingPrice({required this.property, required this.accent});

  final RentalProperty property;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            property.priceLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 46,
              height: 1.0,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.5,
              shadows: [
                Shadow(color: accent.withValues(alpha: 0.55), blurRadius: 26),
                Shadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 18,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            property.priceSuffixLabel,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

/// Frosted-glass rail of the three headline facts: rooms, size, floor. Each is
/// derived directly from the property; empty facts are dropped so the rail never
/// shows blanks. Big legible type + targets for older users.
class _GlassStatsRail extends StatelessWidget {
  const _GlassStatsRail({required this.property, required this.accent});

  final RentalProperty property;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final stats = <_StatItem>[
      _StatItem(
        icon: IconsaxPlusLinear.home_2,
        value: property.roomsLabel,
        label: AppLocalizations.of(context)!.cinematicGlassTemplateB50b3974,
      ),
      if (property.sizeM2 > 0)
        _StatItem(
          icon: IconsaxPlusLinear.maximize_3,
          value: '${property.sizeM2}',
          label: AppLocalizations.of(context)!.cinematicGlassTemplateD3b9013b,
        ),
      if (property.floor.trim().isNotEmpty)
        _StatItem(
          icon: IconsaxPlusLinear.building_4,
          value: floorLabel(property.floor.trim(), AppLocalizations.of(context)!),
          label: AppLocalizations.of(context)!.cinematicGlassTemplate047e630b,
        ),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(20), sigmaY: PlatformFx.blurSigma(20)),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              for (var i = 0; i < stats.length; i++) ...[
                if (i > 0)
                  Container(
                    width: 1,
                    height: 38,
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                Expanded(child: _StatCell(item: stats[i], accent: accent)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem {
  const _StatItem({
    required this.icon,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final String value;
  final String label;
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.item, required this.accent});

  final _StatItem item;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(item.icon, color: accent, size: 22),
        const SizedBox(height: 8),
        Text(
          item.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          item.label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.68),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// The scrolling body shell: a frosted dark-glass panel with a rounded top edge
/// that overlaps the hero so the cinematic imagery bleeds into the content. A
/// thin accent hairline at the seam ties it to the brand glow.
class _CinematicBody extends StatelessWidget {
  const _CinematicBody({
    required this.base,
    required this.accent,
    required this.child,
  });

  final Color base;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      // Pull the panel up so its rounded top overlaps the hero's lower edge.
      offset: const Offset(0, -28),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(24), sigmaY: PlatformFx.blurSigma(24)),
          child: Container(
            decoration: BoxDecoration(
              // A slightly-lifted dark glass over the brand-dark base so the
              // white-on-dark parity cards read with depth and warmth.
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color.alphaBlend(
                    Colors.white.withValues(alpha: 0.06),
                    base.withValues(alpha: 0.97),
                  ),
                  const Color(0xFF0A0B0F),
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(34),
              ),
              border: Border(
                top: BorderSide(
                  color: accent.withValues(alpha: 0.45),
                  width: 1.2,
                ),
              ),
            ),
            child: Column(
              children: [
                // Grab handle hint to invite scroll, glowing in the accent.
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 6),
                  child: Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    18,
                    14,
                    18,
                    MediaQuery.of(context).padding.bottom + 120,
                  ),
                  child: child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
