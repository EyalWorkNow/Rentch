import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/nearby_relevance.dart';
import 'package:dating_app/core/search/scenario_layers.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// "Nearby places" on the property detail screen — PERSONALISED. Given the
/// seeker's [profile] (derived from their query/persona), it shows only the
/// relevant sections (schools / kindergartens / clinics / supermarkets / parks),
/// ordered most-relevant first: a family sees schools & kindergartens, a
/// health-focused seeker sees their HMO's clinics, a young single sees neither
/// (the card hides). Each place lists name · type · distance and offers to open
/// a Google search. Data from [IsraelGeoIndex] (data.gov.il + OSM).
class NearbyPlacesCard extends StatefulWidget {
  NearbyPlacesCard({
    super.key,
    required this.lat,
    required this.lon,
    required this.city,
    required this.profile,
    this.relevantOnly = false,
    this.carousel = false,
    this.maxChips = 5,
    this.showAllKinds = false,
    this.preferredKinds = const <NearbyKind>{},
    this.showHeader = true,
  });

  final double lat;
  final double lon;
  final String city;
  final NearbyProfile profile;

  /// When true (property detail), expose EVERY nearby kind that has data — not
  /// just the persona-relevant subset — persona-relevant first, then the rest.
  final bool showAllKinds;

  /// The seeker's explicitly-chosen important categories (from the search
  /// filter). These are surfaced FIRST, ahead of persona ordering.
  final Set<NearbyKind> preferredKinds;

  /// When true (the chat "למה זו" preview), show ONLY the sections relevant to the
  /// seeker's query. When false (the property detail screen), show ALL kinds with
  /// data as a full reference, persona-relevant first.
  final bool relevantOnly;

  /// When true, render a CAROUSEL of tags — tap a tag to open its list below,
  /// one at a time. Only the first [maxChips] tags show, with a "צפה בכולם" button
  /// to reveal the rest.
  final bool carousel;

  /// Carousel: how many tags to show before the "צפה בכולם (+N)" button.
  final int maxChips;

  /// Hide the card's own title when a host section already renders one
  /// (the property page's מקומות בקרבת הדירה header + toggle).
  final bool showHeader;

  @override
  State<NearbyPlacesCard> createState() => _NearbyPlacesCardState();
}

class _NearbyPlacesCardState extends State<NearbyPlacesCard> {
  final List<(NearbySection, List<NearbyPlace>)> _sections = [];
  bool _loaded = false;
  int _open = 0; // accordion: index of the single expanded section (-1 = none)
  int _selected = 0; // carousel: index of the tag whose list is shown
  int _currentPage = 0; // current page for place card pagination
  bool _showAllChips = false; // carousel: "הצג הכל" reveals every tag (wrap)
  // Chat preview only: the user tapped "ראה עוד מקומות" → widen from the
  // relevant-only subset to EVERY nearby kind with data.
  bool _expandedAll = false;

  @override
  void initState() {
    super.initState();
    // Compute AFTER the first frame so opening the detail page is scrollable
    // instantly — the POI section scan (up to ~20 kinds, hundreds of points each
    // in a dense area) otherwise runs in a pre-frame microtask and freezes the
    // opening frame. The card renders nothing until _loaded, so a one-frame defer
    // is invisible.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void reassemble() {
    super.reassemble();
    _load();
  }

  Future<void> _load() async {
    // Idempotent loaders — no-op if already loaded at startup.
    await Future.wait([
      IsraelGeoIndex.loadSchools(),
      IsraelGeoIndex.loadParks(),
      IsraelGeoIndex.loadClinics(),
      IsraelGeoIndex.loadSupermarkets(),
      IsraelGeoIndex.loadLifestylePois(),
    ]);
    if (!mounted) return;
    final sections = _resolveSections();
    final out = <(NearbySection, List<NearbyPlace>)>[];
    var scanned = 0;
    for (final s in sections) {
      final places = _dataFor(s);
      if (places.isNotEmpty) out.add((s, places));
      // Yield to the event loop every few kinds so a dense area never blocks a
      // single frame while the user is scrolling.
      if (++scanned % 4 == 0) await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
    }
    setState(() {
      _sections
        ..clear()
        ..addAll(out);
      _selected = _selected.clamp(0, out.isEmpty ? 0 : out.length - 1);
      // The section list just changed (initial load / "ראה עוד מקומות") — a
      // page index carried over from a longer section would show an EMPTY
      // grid (skip beyond the new list's end).
      _currentPage = 0;
      _loaded = true;
    });
  }

  // Decide which nearby sections to render, in order:
  //   1) the seeker's explicitly-preferred categories (from the search filter),
  //   2) persona/spec-relevant sections,
  //   3) (showAllKinds) every remaining kind, so the detail page is a full
  //      browsable reference. Secular seekers never get synagogues/worship.
  List<NearbySection> _resolveSections() {
    // Spec-primary (curated 504-scenario mapping) with heuristic fallback.
    final base = personalizedNearbySections(
      widget.profile,
      coreOnly: widget.relevantOnly && !_expandedAll,
    );
    if (!widget.showAllKinds && widget.preferredKinds.isEmpty) return base;

    final have = base.map((s) => s.kind).toSet();
    bool suppressed(NearbyKind k) => widget.profile.secular &&
        (k == NearbyKind.synagogues || k == NearbyKind.worship);

    final all = <NearbySection>[...base];
    if (widget.showAllKinds) {
      for (final k in NearbyKind.values) {
        if (have.contains(k) || suppressed(k)) continue;
        all.add(NearbySection(k, priority: 0));
        have.add(k);
      }
    }
    if (widget.preferredKinds.isEmpty) return all;

    // Move preferred categories to the front (adding any not already present).
    final pref = <NearbySection>[];
    for (final k in widget.preferredKinds) {
      if (suppressed(k)) continue;
      final match = all.where((s) => s.kind == k);
      pref.add(match.isNotEmpty ? match.first : NearbySection(k, priority: 0));
    }
    final rest = all.where((s) => !widget.preferredKinds.contains(s.kind));
    return [...pref, ...rest];
  }

  // Chat preview: widen from relevant-only to every nearby kind, on demand.
  void _revealAllKinds() {
    setState(() => _expandedAll = true);
    _load();
  }

  // Outside city centers many layers are empty at their default radius, which
  // used to hide them entirely (a suburb property showed ~12 of 23 layers).
  // Retry empty layers at 3× the radius (capped at 10 km) — the section badge
  // and each item show the REAL distance, so nothing is misrepresented.
  List<NearbyPlace> _withFallback(
      List<NearbyPlace> Function(double km) q, double km) {
    final first = q(km);
    if (first.isNotEmpty) return first;
    final wide = (km * 3).clamp(km, 10.0);
    return q(wide);
  }

  List<NearbyPlace> _dataFor(NearbySection s) {
    final la = widget.lat, lo = widget.lon;
    switch (s.kind) {
      case NearbyKind.schools:
        return _withFallback(
            (km) => IsraelGeoIndex.schoolsWithin(la, lo, km: km, cap: 120), 2);
      case NearbyKind.kindergartens:
        return _withFallback(
            (km) => IsraelGeoIndex.kindergartensWithin(la, lo, km: km, cap: 120),
            2);
      case NearbyKind.clinics:
        return _withFallback(
            (km) => IsraelGeoIndex.clinicsWithin(la, lo,
                km: km, hmo: s.hmo.isEmpty ? null : s.hmo, cap: 120),
            5); // clinics matter farther
      case NearbyKind.supermarkets:
        return _withFallback(
            (km) => IsraelGeoIndex.supermarketsWithin(la, lo, km: km, cap: 120),
            2);
      case NearbyKind.parks:
        return _withFallback(
            (km) => IsraelGeoIndex.parksWithin(la, lo, km: km, cap: 120), 2);
      case NearbyKind.pharmacies:
        return _withFallback(
            (km) => IsraelGeoIndex.pharmaciesWithin(la, lo, km: km, cap: 120),
            2);
      case NearbyKind.playgrounds:
        return _withFallback(
            (km) => IsraelGeoIndex.playgroundsWithin(la, lo, km: km, cap: 120),
            2);
      case NearbyKind.dining:
        return _withFallback(
            (km) => IsraelGeoIndex.diningWithin(la, lo, km: km, cap: 120), 2);
      case NearbyKind.gyms:
        return _withFallback(
            (km) => IsraelGeoIndex.gymsWithin(la, lo, km: km, cap: 120), 3);
      case NearbyKind.nightlife:
        return _withFallback(
            (km) =>
                IsraelGeoIndex.nightlifeVenuesWithin(la, lo, km: km, cap: 120),
            2);
      case NearbyKind.synagogues:
        return _withFallback(
            (km) => IsraelGeoIndex.synagoguesWithin(la, lo, km: km, cap: 120),
            2);
      case NearbyKind.culture:
        return _withFallback(
            (km) => IsraelGeoIndex.cultureWithin(la, lo, km: km, cap: 120), 3);
      case NearbyKind.hospitals:
        return _withFallback(
            (km) => IsraelGeoIndex.hospitalsWithin(la, lo, km: km, cap: 120),
            5);
      case NearbyKind.transit:
        return _withFallback(
            (km) => IsraelGeoIndex.transitStopsWithin(la, lo, km: km, cap: 120),
            2);
      case NearbyKind.worship:
        return _withFallback(
            (km) => IsraelGeoIndex.worshipWithin(la, lo, km: km, cap: 120), 2);
      case NearbyKind.pools:
        return _withFallback(
            (km) => IsraelGeoIndex.poolsWithin(la, lo, km: km, cap: 120), 3);
      case NearbyKind.dogParks:
        return _withFallback(
            (km) => IsraelGeoIndex.dogParksWithin(la, lo, km: km, cap: 120), 2);
      case NearbyKind.vets:
        return _withFallback(
            (km) => IsraelGeoIndex.vetsWithin(la, lo, km: km, cap: 120), 3);
      case NearbyKind.bikeShare:
        return _withFallback(
            (km) => IsraelGeoIndex.bikeShareWithin(la, lo, km: km, cap: 120),
            2);
      case NearbyKind.coworking:
        return _withFallback(
            (km) => IsraelGeoIndex.coworkingWithin(la, lo, km: km, cap: 120),
            3);
      case NearbyKind.parking:
        return _withFallback(
            (km) => IsraelGeoIndex.parkingWithin(la, lo, km: km, cap: 120), 2);
      case NearbyKind.rail:
        return _withFallback(
            (km) => IsraelGeoIndex.railStationsWithin(la, lo, km: km, cap: 120),
            5);
      case NearbyKind.airQuality:
        return _withFallback(
            (km) => IsraelGeoIndex.airQualityStationsWithin(la, lo,
                km: km, cap: 120),
            5);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _sections.isEmpty) return const SizedBox.shrink();
    return Directionality(
      textDirection: Directionality.of(context),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderLight),
        ),
        padding: widget.carousel ? const EdgeInsets.fromLTRB(14, 14, 14, 8) : EdgeInsets.zero,
        child: widget.carousel ? _carousel() : _accordion(),
      ),
    );
  }

  Widget _accordion() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < _sections.length; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: AppColors.borderLight),
            _section(i, _sections[i].$1.kind, _sections[i].$2),
          ],
        ],
      );

  // ── carousel: a row of tags → tap one to open its list below (one at a time).
  // Shows the top [maxChips] tags, then a "צפה בכולם (+N)" button reveals the rest.
  Widget _carousel() {
    final sel = _selected.clamp(0, _sections.length - 1);
    final total = _sections.length;
    final limit = widget.maxChips;
    // Keep the chip strip expanded while a beyond-the-fold chip is selected —
    // collapsing used to hide the selected chip entirely (grid shows section
    // 7, chips show 0-2 with nothing highlighted).
    final showAll = _showAllChips || total <= limit || sel >= limit;
    final count = showAll ? total : limit;
    final viewAll = total > limit ? _viewAllButton(!showAll, total - limit) : null;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showHeader) ...[
          Text(l10n.nearbyPlacesCard29364e0f,
              style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy)),
          const SizedBox(height: 8),
        ],
        // Category tags in a 2-column equal-width Grid — spacious, bold, and highly readable.
        Column(
          children: [
            for (var r = 0; r < (count / 2).ceil(); r++) ...[
              if (r > 0) const SizedBox(height: 6),
              Row(
                children: [
                  for (var c = 0; c < 2; c++) ...[
                    if (c > 0) const SizedBox(width: 8),
                    Expanded(
                      child: (r * 2 + c) < count
                          ? _chip(r * 2 + c, (r * 2 + c) == sel)
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
        if (viewAll != null) ...[
          const SizedBox(height: 6),
          Center(child: viewAll),
        ],
        const SizedBox(height: 6),
        // Selected tag's places as a FIXED 3×3 grid — 9 places per page, each
        // cell carries the category icon + name + distance, with prev/next
        // paging below.
        if (_sections.isNotEmpty) ...[
          GridView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            // FIXED cell height, not childAspectRatio: a ratio-derived height
            // shrinks with the host width, and inside the chat bubble (much
            // narrower than the property page) the cells dropped below their
            // content height → "BOTTOM OVERFLOWED BY N PIXELS" stripes on
            // every cell of אתי's מקומות-בקרבת-הדירה preview.
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: 82,
            ),
            children: [
              for (final pl
                  in _sections[sel].$2.skip(_currentPage * 9).take(9))
                _gridPlaceCard(pl, _meta(_sections[sel].$1.kind).$1),
            ],
          ),
          // Pagination controls (only if total items > 9)
          if (_sections[sel].$2.length > 9) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Previous page button (RTL right-side button)
                InkWell(
                  onTap: _currentPage > 0 
                      ? () => setState(() => _currentPage--) 
                      : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 12,
                          color: _currentPage > 0 ? AppColors.primary : AppColors.textSecondary.withOpacity(0.3),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          l10n.nearbyPlacesCard7e6e0fb1,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                            color: _currentPage > 0 ? AppColors.primary : AppColors.textSecondary.withOpacity(0.3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Page Indicator
                Text(
                  l10n.nearbyPlacesCard4a3e7c17(
                    _currentPage + 1,
                    (_sections[sel].$2.length / 9).ceil(),
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                // Next page button (RTL left-side button)
                InkWell(
                  onTap: _currentPage < ((_sections[sel].$2.length / 9).ceil() - 1)
                      ? () => setState(() => _currentPage++)
                      : null,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l10n.nearbyPlacesCard5f9edf6e,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                            color: _currentPage < ((_sections[sel].$2.length / 9).ceil() - 1) ? AppColors.primary : AppColors.textSecondary.withOpacity(0.3),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_back_ios_rounded,
                          size: 12,
                          color: _currentPage < ((_sections[sel].$2.length / 9).ceil() - 1) ? AppColors.primary : AppColors.textSecondary.withOpacity(0.3),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
        // Chat preview: once the relevant places are shown, let an interested
        // seeker widen to EVERY nearby kind (parks, gyms, transit, culture…).
        if (widget.relevantOnly && !_expandedAll) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: _revealAllKinds,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.primary),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                    child: Text(l10n.nearbyPlacesCard4745b1e9,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary)),
                  ),
                  const SizedBox(width: 4),
                  Icon(IconsaxPlusLinear.discover_1,
                      size: 17, color: AppColors.primary),
                ]),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// One cell of the 3×3 place grid: category icon in a tinted circle, the
  /// place name (up to 2 lines), and the distance — tap opens a Google search.
  Widget _gridPlaceCard(NearbyPlace p, IconData icon) {
    final subText = p.stage.isNotEmpty
        ? p.stage
        : (p.sector.isNotEmpty ? p.sector : '');

    return InkWell(
      onTap: () => _confirmOpenGoogle(p.name),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.22),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
            if (subText.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary.withValues(alpha: 0.7),
                ),
              ),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _distLabel(p.km),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  Icons.location_on_outlined,
                  size: 13,
                  color: AppColors.primary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _viewAllButton(bool collapsed, int hidden) {
    return InkWell(
      onTap: () => setState(() => _showAllChips = !_showAllChips),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.primary, width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(
            collapsed
                ? AppLocalizations.of(context)!.nearbyPlacesCard9197afde(hidden)
                : AppLocalizations.of(context)!.nearbyPlacesCard6192614d,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            collapsed ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
            size: 18,
            color: AppColors.primary,
          ),
        ]),
      ),
    );
  }

  Widget _chip(int index, bool on) {
    final l10n = AppLocalizations.of(context)!;
    final (icon, title, _) = _meta(_sections[index].$1.kind);
    final n = _sections[index].$2.length;
    final cleanTitle = title
        .replaceAll(l10n.nearbyPlacesCardChipSuffixMasc, '')
        .replaceAll(l10n.nearbyPlacesCardChipSuffixFem, '')
        .replaceAll(' ורק"ל', '');

    return InkWell(
      onTap: () => setState(() {
        _selected = index;
        _currentPage = 0;
      }),
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: on ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: on ? AppColors.primary : AppColors.borderLight,
            width: on ? 1.5 : 1.0,
          ),
          boxShadow: on
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.22),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: on ? Colors.white : AppColors.primary),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                cleanTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: on ? Colors.white : AppColors.navy,
                ),
              ),
            ),
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: on
                    ? Colors.white.withValues(alpha: 0.25)
                    : AppColors.cloud,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$n',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: on ? Colors.white : AppColors.navy,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(int index, NearbyKind kind, List<NearbyPlace> places) {
    final (icon, title, radiusKm) = _meta(kind);
    final open = _open == index;
    // ACCORDION: tapping a header opens it and closes any other — one at a time,
    // so a family's long list never buries the section below it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = open ? -1 : index),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy)),
                      // Collapsed hint — the nearest place, so the row is useful
                      // even before you open it.
                      if (!open && places.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            '${places.first.name} · ${_distLabel(places.first.km)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    // Range badge reflects the FARTHEST item actually shown
                    // (fallback radius may exceed the kind's default radius).
                    '${places.length}${places.length >= 120 ? '+' : ''}'
                        '${AppLocalizations.of(context)!.nearbyPlacesCardC3e59a4e(places.isEmpty ? radiusKm : places.last.km.ceil())}',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary),
                  ),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.keyboard_arrow_down_rounded,
                      size: 22, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 200),
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(children: [for (final p in places) _placeRow(p)]),
          ),
          crossFadeState:
              open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
        ),
      ],
    );
  }

  (IconData, String, int) _meta(NearbyKind kind) {
    final l10n = AppLocalizations.of(context)!;
    switch (kind) {
      case NearbyKind.schools:
        return (Icons.school_rounded, l10n.nearbyPlacesCardCef7ef5e, 2);
      case NearbyKind.kindergartens:
        return (Icons.child_friendly_rounded, l10n.nearbyPlacesCardD7b78a1f, 2);
      case NearbyKind.clinics:
        return (Icons.local_hospital_rounded, l10n.nearbyPlacesCard385087d3, 5);
      case NearbyKind.supermarkets:
        return (Icons.shopping_cart_rounded, l10n.nearbyPlacesCard19a008ff, 2);
      case NearbyKind.parks:
        return (Icons.park_rounded, l10n.nearbyPlacesCardCdc11038, 2);
      case NearbyKind.pharmacies:
        return (Icons.local_pharmacy_rounded, l10n.nearbyPlacesCardEc7edb50, 2);
      case NearbyKind.playgrounds:
        return (Icons.child_care_rounded, l10n.nearbyPlacesCard71ec0056, 2);
      case NearbyKind.dining:
        return (Icons.restaurant_rounded, l10n.nearbyPlacesCard09b9bc6f, 2);
      case NearbyKind.gyms:
        return (Icons.fitness_center_rounded, l10n.nearbyPlacesCard117e5860, 3);
      case NearbyKind.nightlife:
        return (Icons.local_bar_rounded, l10n.nearbyPlacesCardD4ecbfa0, 2);
      case NearbyKind.synagogues:
        return (Icons.synagogue_rounded, l10n.nearbyPlacesCard7e72c9af, 2);
      case NearbyKind.culture:
        return (Icons.museum_rounded, l10n.nearbyPlacesCard21a17e0d, 3);
      case NearbyKind.hospitals:
        return (Icons.local_hospital_rounded, l10n.nearbyPlacesCard46be343a, 5);
      case NearbyKind.transit:
        return (Icons.directions_bus_rounded, l10n.nearbyPlacesCard07638922, 2);
      case NearbyKind.worship:
        return (Icons.place_rounded, l10n.nearbyPlacesCardBb428196, 2);
      case NearbyKind.pools:
        return (Icons.pool_rounded, l10n.nearbyPlacesCard34ff0c6c, 3);
      case NearbyKind.dogParks:
        return (Icons.pets_rounded, l10n.nearbyPlacesCard5290646f, 2);
      case NearbyKind.vets:
        return (Icons.medical_services_rounded, l10n.nearbyPlacesCard6faa1286, 3);
      case NearbyKind.bikeShare:
        return (Icons.pedal_bike_rounded, l10n.nearbyPlacesCard5b5ddf14, 2);
      case NearbyKind.coworking:
        return (Icons.work_rounded, l10n.nearbyPlacesCard5d4c2d06, 3);
      case NearbyKind.parking:
        return (Icons.local_parking_rounded, l10n.nearbyPlacesCard0a96eae3, 2);
      case NearbyKind.rail:
        return (Icons.train_rounded, l10n.nearbyPlacesCardRail, 5);
      case NearbyKind.airQuality:
        return (Icons.air_rounded, l10n.nearbyPlacesCardAirQuality, 5);
    }
  }

  Widget _placeRow(NearbyPlace p) {
    final sub = _sub(p);
    return InkWell(
      onTap: () => _confirmOpenGoogle(p.name),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 9, 16, 9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  if (sub.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(sub,
                          style: const TextStyle(
                              fontSize: 12.5, color: AppColors.textSecondary)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(_distLabel(p.km),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary)),
            const SizedBox(width: 4),
            const Icon(Icons.open_in_new_rounded,
                size: 15, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  // Per-kind sublabel: schools "יסודי · ממלכתי", clinics "כללית"/"מרפאה", else none.
  String _sub(NearbyPlace p) {
    switch (p.kind) {
      case 'school':
      case 'kindergarten':
        return p.sector.isEmpty ? p.stage : '${p.stage} · ${p.sector}';
      case 'clinic':
        return p.sector.isEmpty
            ? AppLocalizations.of(context)!.nearbyPlacesCard6278673e
            : p.sector;
      case 'dining':
      case 'nightlife':
      case 'culture':
      case 'transit':
      case 'worship':
      case 'pool':
        return p.stage; // dining/culture/transit/worship types · בריכה/מרכז ספורט
      default:
        return '';
    }
  }

  String _distLabel(double km) {
    final l10n = AppLocalizations.of(context)!;
    return km < 1
        ? l10n.nearbyPlacesCardDcabfe76((km * 1000).round())
        : l10n.nearbyPlacesCard0b2db321(km.toStringAsFixed(1));
  }

  Future<void> _confirmOpenGoogle(String name) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: Directionality.of(context),
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(l10n.nearbyPlacesCard4f9b07b3,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          content: Text(l10n.nearbyPlacesCardE927ed2c(name),
              style:
                  const TextStyle(color: AppColors.textSecondary, height: 1.4)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.nearbyPlacesCardA7c55a8d)),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.nearbyPlacesCard95337767),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final q = Uri.encodeComponent(
        widget.city.trim().isEmpty ? name : '$name ${widget.city}');
    try {
      await launchUrl(Uri.parse('https://www.google.com/search?q=$q'),
          mode: LaunchMode.externalApplication);
    } catch (_) {/* launch failed — nothing to do */}
  }
}
