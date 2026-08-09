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

  List<NearbyPlace> _dataFor(NearbySection s) {
    final la = widget.lat, lo = widget.lon;
    switch (s.kind) {
      case NearbyKind.schools:
        return IsraelGeoIndex.schoolsWithin(la, lo, km: 2, cap: 120);
      case NearbyKind.kindergartens:
        return IsraelGeoIndex.kindergartensWithin(la, lo, km: 2, cap: 120);
      case NearbyKind.clinics:
        return IsraelGeoIndex.clinicsWithin(la, lo,
            km: 5, hmo: s.hmo.isEmpty ? null : s.hmo, cap: 120); // clinics matter farther
      case NearbyKind.supermarkets:
        return IsraelGeoIndex.supermarketsWithin(la, lo, km: 2, cap: 120);
      case NearbyKind.parks:
        return IsraelGeoIndex.parksWithin(la, lo, km: 2, cap: 120);
      case NearbyKind.pharmacies:
        return IsraelGeoIndex.pharmaciesWithin(la, lo, km: 2, cap: 120);
      case NearbyKind.playgrounds:
        return IsraelGeoIndex.playgroundsWithin(la, lo, km: 2, cap: 120);
      case NearbyKind.dining:
        return IsraelGeoIndex.diningWithin(la, lo, km: 2, cap: 120);
      case NearbyKind.gyms:
        return IsraelGeoIndex.gymsWithin(la, lo, km: 3, cap: 120);
      case NearbyKind.nightlife:
        return IsraelGeoIndex.nightlifeVenuesWithin(la, lo, km: 2, cap: 120);
      case NearbyKind.synagogues:
        return IsraelGeoIndex.synagoguesWithin(la, lo, km: 2, cap: 120);
      case NearbyKind.culture:
        return IsraelGeoIndex.cultureWithin(la, lo, km: 3, cap: 120);
      case NearbyKind.hospitals:
        return IsraelGeoIndex.hospitalsWithin(la, lo, km: 5, cap: 120);
      case NearbyKind.transit:
        return IsraelGeoIndex.transitStopsWithin(la, lo, km: 2, cap: 120);
      case NearbyKind.worship:
        return IsraelGeoIndex.worshipWithin(la, lo, km: 2, cap: 120);
      case NearbyKind.pools:
        return IsraelGeoIndex.poolsWithin(la, lo, km: 3, cap: 120);
      case NearbyKind.dogParks:
        return IsraelGeoIndex.dogParksWithin(la, lo, km: 2, cap: 120);
      case NearbyKind.vets:
        return IsraelGeoIndex.vetsWithin(la, lo, km: 3, cap: 120);
      case NearbyKind.bikeShare:
        return IsraelGeoIndex.bikeShareWithin(la, lo, km: 2, cap: 120);
      case NearbyKind.coworking:
        return IsraelGeoIndex.coworkingWithin(la, lo, km: 3, cap: 120);
      case NearbyKind.parking:
        return IsraelGeoIndex.parkingWithin(la, lo, km: 2, cap: 120);
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
    final showAll = _showAllChips || total <= limit;
    final count = showAll ? total : limit;
    final chips = [for (var i = 0; i < count; i++) _chip(i, i == sel)];
    final viewAll = total > limit ? _viewAllButton(!showAll, total - limit) : null;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.nearbyPlacesCard29364e0f,
            style: const TextStyle(
                fontSize: 15.5, fontWeight: FontWeight.w900, color: AppColors.navy)),
        const SizedBox(height: 10),
        // Collapsed → a horizontal, swipeable CAROUSEL of the top tags. Expanded
        // ("צפה בכולם") → a full wrap so every tag is visible at once.
        if (showAll)
          Wrap(spacing: 8, runSpacing: 8, children: [
            ...chips,
            if (viewAll != null) viewAll,
          ])
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                chips[i],
              ],
              if (viewAll != null) ...[const SizedBox(width: 8), viewAll],
            ]),
          ),
        const SizedBox(height: 8),
        // Selected tag's places as an ADAPTIVE wrap — each card sizes to its own
        // content so the FULL name shows (even a long one), and rows fill
        // asymmetrically to the width instead of a rigid symmetric grid.
        if (_sections.isNotEmpty) ...[
          LayoutBuilder(
            builder: (context, c) => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final pl in _sections[sel].$2.skip(_currentPage * 10).take(10))
                  _placeCard(pl, c.maxWidth),
              ],
            ),
          ),
          // Pagination controls (only if total items > 10)
          if (_sections[sel].$2.length > 10) ...[
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Previous page button (RTL right-side button)
                TextButton(
                  onPressed: _currentPage > 0 
                      ? () => setState(() => _currentPage--) 
                      : null,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    disabledForegroundColor: AppColors.textSecondary.withOpacity(0.3),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_forward_ios_rounded, size: 13),
                      const SizedBox(width: 4),
                      Text(l10n.nearbyPlacesCard7e6e0fb1, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    ],
                  ),
                ),
                // Page Indicator
                Text(
                  l10n.nearbyPlacesCard4a3e7c17(
                    _currentPage + 1,
                    (_sections[sel].$2.length / 10).ceil(),
                  ),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                // Next page button (RTL left-side button)
                TextButton(
                  onPressed: _currentPage < ((_sections[sel].$2.length / 10).ceil() - 1)
                      ? () => setState(() => _currentPage++)
                      : null,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    disabledForegroundColor: AppColors.textSecondary.withOpacity(0.3),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.nearbyPlacesCard5f9edf6e, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_back_ios_rounded, size: 13),
                    ],
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
                  Text(l10n.nearbyPlacesCard4745b1e9,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary)),
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

  /// One place card for the adaptive wrap: hugs its content (full name · type ·
  /// distance), min ~104px so tiny names still read, max ~66% of the row so a long
  /// name gets a wide card while short ones still pack several per row.
  Widget _placeCard(NearbyPlace p, double availWidth) {
    final sub = _sub(p);
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: 104,
        maxWidth: (availWidth * 0.66).clamp(140.0, 320.0),
      ),
      child: InkWell(
        onTap: () => _confirmOpenGoogle(p.name),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(p.name,
                    softWrap: true,
                    style: const TextStyle(
                        fontSize: 13,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                if (sub.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(sub,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                  ),
                const SizedBox(height: 6),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.place_rounded, size: 12, color: AppColors.primary),
                  const SizedBox(width: 2),
                  Text(_distLabel(p.km),
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary)),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _viewAllButton(bool collapsed, int hidden) {
    return InkWell(
      onTap: () => setState(() => _showAllChips = !_showAllChips),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.primary),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(collapsed
                  ? AppLocalizations.of(context)!.nearbyPlacesCard9197afde(hidden)
                  : AppLocalizations.of(context)!.nearbyPlacesCard6192614d,
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.primary)),
          const SizedBox(width: 4),
          Icon(collapsed ? Icons.expand_more_rounded : Icons.expand_less_rounded,
              size: 18, color: AppColors.primary),
        ]),
      ),
    );
  }

  Widget _chip(int index, bool on) {
    final (icon, title, _) = _meta(_sections[index].$1.kind);
    final n = _sections[index].$2.length;
    return InkWell(
      onTap: () => setState(() {
        _selected = index;
        _currentPage = 0;
      }),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: on ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? AppColors.primary : AppColors.borderLight),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: on ? Colors.white : AppColors.primary),
          const SizedBox(width: 6),
          Text(title.replaceAll(' קרובים', '').replaceAll(' קרובות', ''),
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: on ? Colors.white : AppColors.navy)),
          const SizedBox(width: 6),
          Text('$n${n >= 12 ? '+' : ''}',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: on ? Colors.white70 : AppColors.textSecondary)),
        ]),
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
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${places.length}${places.length >= 12 ? '+' : ''}'
                        '${AppLocalizations.of(context)!.nearbyPlacesCardC3e59a4e(radiusKm)}',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark),
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
        return (IconsaxPlusLinear.teacher, l10n.nearbyPlacesCardCef7ef5e, 2);
      case NearbyKind.kindergartens:
        return (IconsaxPlusLinear.emoji_happy, l10n.nearbyPlacesCardD7b78a1f, 2);
      case NearbyKind.clinics:
        return (IconsaxPlusLinear.hospital, l10n.nearbyPlacesCard385087d3, 5);
      case NearbyKind.supermarkets:
        return (IconsaxPlusLinear.shopping_cart, l10n.nearbyPlacesCard19a008ff, 2);
      case NearbyKind.parks:
        return (IconsaxPlusLinear.tree, l10n.nearbyPlacesCardCdc11038, 2);
      case NearbyKind.pharmacies:
        return (IconsaxPlusLinear.health, l10n.nearbyPlacesCardEc7edb50, 2);
      case NearbyKind.playgrounds:
        return (IconsaxPlusLinear.game, l10n.nearbyPlacesCard71ec0056, 2);
      case NearbyKind.dining:
        return (IconsaxPlusLinear.reserve, l10n.nearbyPlacesCard09b9bc6f, 2);
      case NearbyKind.gyms:
        return (IconsaxPlusLinear.weight, l10n.nearbyPlacesCard117e5860, 3);
      case NearbyKind.nightlife:
        return (IconsaxPlusLinear.cup, l10n.nearbyPlacesCardD4ecbfa0, 2);
      case NearbyKind.synagogues:
        return (IconsaxPlusLinear.buildings, l10n.nearbyPlacesCard7e72c9af, 2);
      case NearbyKind.culture:
        return (IconsaxPlusLinear.gallery, l10n.nearbyPlacesCard21a17e0d, 3);
      case NearbyKind.hospitals:
        return (IconsaxPlusLinear.heart, l10n.nearbyPlacesCard46be343a, 5);
      case NearbyKind.transit:
        return (IconsaxPlusLinear.bus, l10n.nearbyPlacesCard07638922, 2);
      case NearbyKind.worship:
        return (IconsaxPlusLinear.courthouse, l10n.nearbyPlacesCardBb428196, 2);
      case NearbyKind.pools:
        return (IconsaxPlusLinear.drop, l10n.nearbyPlacesCard34ff0c6c, 3);
      case NearbyKind.dogParks:
        return (IconsaxPlusLinear.pet, l10n.nearbyPlacesCard5290646f, 2);
      case NearbyKind.vets:
        return (IconsaxPlusLinear.lifebuoy, l10n.nearbyPlacesCard6faa1286, 3);
      case NearbyKind.bikeShare:
        return (IconsaxPlusLinear.routing, l10n.nearbyPlacesCard5b5ddf14, 2);
      case NearbyKind.coworking:
        return (IconsaxPlusLinear.briefcase, l10n.nearbyPlacesCard5d4c2d06, 3);
      case NearbyKind.parking:
        return (IconsaxPlusLinear.car, l10n.nearbyPlacesCard0a96eae3, 2);
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
