part of '../property_detail_screen.dart';

/// Gallery Editorial (`galleryEditorial`) — a luxury real-estate MAGAZINE
/// spread. A big, confident edge-to-edge hero (reaching the very top, with the
/// top bar overlaid in the safe area) opens the feature; below it an editorial
/// masthead lays out a kicker rule, a large display title, a refined location
/// line, an editorial price line and a magazine-style "spec ledger" of stat
/// columns, followed by a factual lede built from REAL data — then a centered
/// section ornament leads into the complete shared parity block.
///
/// Self-contained and designer-owned: uses only shared building blocks plus the
/// small private helpers defined in this file. No section is duplicated — every
/// gallery / facts / owner / reviews / map / tour / match section is rendered
/// exactly once, by [_ParitySections].
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

  static const double _heroHeight = 440;

  // Editorial ink colours derived from the brand's secondary (text) colour so
  // the magazine reads as one tasteful, on-brand palette — never hard-coded.
  Color get _ink => branding.secondaryColor;
  Color get _inkMuted => branding.secondaryColor.withValues(alpha: 0.55);
  Color get _hairline => branding.secondaryColor.withValues(alpha: 0.12);

  /// The editorial kicker: `type · neighborhood` (or city) in small caps. Falls
  /// back gracefully so it always reads as a real, complete label.
  String _kicker(AppLocalizations l10n) {
    final type = property.propertyType.trim();
    final place = property.neighborhood.trim().isNotEmpty
        ? property.neighborhood.trim()
        : property.city.trim();
    if (type.isNotEmpty && place.isNotEmpty) return '$type · $place';
    if (type.isNotEmpty) return type;
    return place.isNotEmpty ? place : l10n.galleryEditorialTemplate4771acf8;
  }

  /// The display title — the headline of the feature.
  String _displayTitle(AppLocalizations l10n) {
    if (property.street.trim().isNotEmpty) {
      final number = property.streetNumber > 0 ? ' ${property.streetNumber}' : '';
      return l10n.galleryEditorialTemplate17773b7f(
          property.propertyType, property.street, number);
    }
    return property.address;
  }

  /// A factual lede paragraph composed strictly from REAL listing data — no
  /// invented prose. Reads like an editorial standfirst introducing the home.
  String _lede(AppLocalizations l10n) {
    final parts = <String>[];
    parts.add(l10n.galleryEditorialTemplateD886d07f(property.roomsLabel));
    if (property.sizeM2 > 0) {
      parts.add(l10n.galleryEditorialTemplateFdb4eac7(property.sizeM2));
    }
    if (property.floor.trim().isNotEmpty) {
      final total = property.totalFloors.trim();
      parts.add(total.isNotEmpty
          ? l10n.galleryEditorialTemplateCa554bb0(property.floor, total)
          : l10n.galleryEditorialTemplateD068bb57(property.floor));
    }
    if (property.condition.trim().isNotEmpty) parts.add(property.condition.trim());
    final spec = parts.join(' · ');
    final place = property.neighborhood.trim().isNotEmpty
        ? '${property.neighborhood.trim()}, ${property.city}'
        : property.city;
    return l10n.galleryEditorialTemplate19aad790(
        property.propertyType, place, spec);
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            // Edge-to-edge hero: no top padding so the image reaches the very
            // top; the top bar is overlaid inside the status-bar safe area.
            // Bottom padding clears the floating bottom bar.
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 124),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHero(context, topInset),
                _buildMasthead(context),
                const SizedBox(height: 24),
                _EditorialDivider(
                  hairline: _hairline,
                  accent: branding.primaryColor,
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

  // ── Hero ────────────────────────────────────────────────────────────────
  Widget _buildHero(BuildContext context, double topInset) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      height: _heroHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: _TemplateHeroMedia(
              property: property,
              controller: controller,
              currentPage: currentPage,
              onPageChanged: onPageChanged,
              height: _heroHeight,
              radius: 0,
            ),
          ),
          // Soft top scrim so the overlaid controls stay readable over any
          // image, and a bottom scrim anchoring the overlaid kicker.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.32, 0.7, 1.0],
                    colors: [
                      Colors.black.withValues(alpha: 0.40),
                      Colors.black.withValues(alpha: 0.06),
                      Colors.black.withValues(alpha: 0.10),
                      Colors.black.withValues(alpha: 0.52),
                    ],
                  ),
                ),
              ),
            ),
          ),
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
          // Editorial overlay low on the image: a thin rule + a small-caps
          // "feature" kicker, the magazine signature of this template.
          Positioned(
            left: 24,
            right: 24,
            bottom: 26,
            child: IgnorePointer(
              child: Row(
                children: [
                  Container(
                    width: 26,
                    height: 2,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      property.transactionType == PropertyTransactionType.sale
                          ? l10n.galleryEditorialTemplateA765f2f3
                          : l10n.galleryEditorialTemplate900c3a51,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3.5,
                        height: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Masthead (editorial text block) ───────────────────────────────────────
  Widget _buildMasthead(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Kicker rule — small caps over a hairline, magazine section label.
          Text(
            _kicker(l10n).toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: branding.primaryColor,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 2.2,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: _hairline),
          const SizedBox(height: 16),

          // Display headline.
          Text(
            _displayTitle(l10n),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _ink,
              fontSize: 32,
              fontWeight: FontWeight.w900,
              height: 1.06,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 10),

          // Location line.
          Row(
            children: [
              Icon(IconsaxPlusLinear.location,
                  size: 16, color: branding.primaryColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  property.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _inkMuted,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          // Editorial lede — a factual standfirst built from real data.
          Text(
            _lede(l10n),
            style: TextStyle(
              color: branding.secondaryColor.withValues(alpha: 0.78),
              fontSize: 16,
              height: 1.6,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),

          // Editorial price line — large price + suffix + price-per-m² caption.
          _buildPriceBlock(l10n),
          const SizedBox(height: 24),

          // Magazine "spec ledger": stat columns split by vertical hairlines.
          _SpecLedger(
            property: property,
            ink: _ink,
            muted: _inkMuted,
            hairline: _hairline,
            accent: branding.primaryColor,
          ),
        ],
      ),
    );
  }

  Widget _buildPriceBlock(AppLocalizations l10n) {
    final ppm = property.pricePerSquareMeter;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              property.priceLabel,
              style: TextStyle(
                color: _ink,
                fontSize: 38,
                fontWeight: FontWeight.w900,
                height: 1.0,
                letterSpacing: -1.0,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                property.priceSuffixLabel,
                style: TextStyle(
                  color: _inkMuted,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (ppm != null) ...[
          const SizedBox(height: 6),
          Text(
            l10n.galleryEditorialTemplateE5340f86(_editorialNumber(ppm)),
            style: TextStyle(
              color: _inkMuted,
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ],
    );
  }
}

/// Magazine-style stat ledger: equal stat columns separated by vertical
/// hairlines. Big, legible numerals over small-caps labels — easy for older
/// users to scan. Only renders columns backed by real data.
class _SpecLedger extends StatelessWidget {
  const _SpecLedger({
    required this.property,
    required this.ink,
    required this.muted,
    required this.hairline,
    required this.accent,
  });

  final RentalProperty property;
  final Color ink;
  final Color muted;
  final Color hairline;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final entries = <_SpecEntry>[
      _SpecEntry(property.roomsLabel, l10n.galleryEditorialTemplateB50b3974),
      if (property.sizeM2 > 0)
        _SpecEntry('${property.sizeM2}', l10n.galleryEditorialTemplateD3b9013b),
      if (property.floor.trim().isNotEmpty)
        _SpecEntry(property.floor, l10n.galleryEditorialTemplate047e630b),
      if (property.totalFloors.trim().isNotEmpty)
        _SpecEntry(property.totalFloors, l10n.galleryEditorialTemplate71c5f6b5),
    ];

    final columns = <Widget>[];
    for (var i = 0; i < entries.length; i++) {
      if (i > 0) {
        columns.add(Container(width: 1, height: 38, color: hairline));
      }
      columns.add(Expanded(child: _column(entries[i])));
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: hairline),
          bottom: BorderSide(color: hairline),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: columns,
      ),
    );
  }

  Widget _column(_SpecEntry e) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          e.value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: ink,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            height: 1.0,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          e.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
      ],
    );
  }
}

class _SpecEntry {
  const _SpecEntry(this.value, this.label);
  final String value;
  final String label;
}

/// A centered editorial section ornament: a hairline rule broken by a small
/// brand-accent diamond — the typographic "section break" of the magazine.
class _EditorialDivider extends StatelessWidget {
  const _EditorialDivider({required this.hairline, required this.accent});

  final Color hairline;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: hairline)),
          const SizedBox(width: 12),
          Transform.rotate(
            angle: 0.785398, // 45° — a refined diamond mark.
            child: Container(
              width: 7,
              height: 7,
              color: accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Container(height: 1, color: hairline)),
        ],
      ),
    );
  }
}

/// Formats an integer with thin grouping for the editorial price caption.
String _editorialNumber(int value) {
  final s = value.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return (value < 0 ? '-' : '') + buf.toString();
}
