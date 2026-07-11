import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/nearby_relevance.dart';
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
  const NearbyPlacesCard({
    super.key,
    required this.lat,
    required this.lon,
    required this.city,
    required this.profile,
    this.relevantOnly = false,
    this.carousel = false,
    this.maxChips = 5,
  });

  final double lat;
  final double lon;
  final String city;
  final NearbyProfile profile;

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
  bool _showAllChips = false; // carousel: "הצג הכל" reveals every tag (wrap)

  @override
  void initState() {
    super.initState();
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
    // Chat preview → only what's relevant to the seeker; detail screen → ALL kinds
    // with data (full reference), persona-relevant first.
    final sections = widget.relevantOnly
        ? relevantNearbySections(widget.profile)
        : orderedNearbySections(widget.profile);
    final out = <(NearbySection, List<NearbyPlace>)>[];
    for (final s in sections) {
      final places = _dataFor(s);
      if (places.isNotEmpty) out.add((s, places));
    }
    setState(() {
      _sections
        ..clear()
        ..addAll(out);
      _loaded = true;
    });
  }

  List<NearbyPlace> _dataFor(NearbySection s) {
    final la = widget.lat, lo = widget.lon;
    switch (s.kind) {
      case NearbyKind.schools:
        return IsraelGeoIndex.schoolsWithin(la, lo, km: 2);
      case NearbyKind.kindergartens:
        return IsraelGeoIndex.kindergartensWithin(la, lo, km: 2);
      case NearbyKind.clinics:
        return IsraelGeoIndex.clinicsWithin(la, lo,
            km: 5, hmo: s.hmo.isEmpty ? null : s.hmo); // clinics matter farther
      case NearbyKind.supermarkets:
        return IsraelGeoIndex.supermarketsWithin(la, lo, km: 2);
      case NearbyKind.parks:
        return IsraelGeoIndex.parksWithin(la, lo, km: 2);
      case NearbyKind.pharmacies:
        return IsraelGeoIndex.pharmaciesWithin(la, lo, km: 2);
      case NearbyKind.playgrounds:
        return IsraelGeoIndex.playgroundsWithin(la, lo, km: 2);
      case NearbyKind.dining:
        return IsraelGeoIndex.diningWithin(la, lo, km: 2);
      case NearbyKind.gyms:
        return IsraelGeoIndex.gymsWithin(la, lo, km: 3);
      case NearbyKind.nightlife:
        return IsraelGeoIndex.nightlifeVenuesWithin(la, lo, km: 2);
      case NearbyKind.synagogues:
        return IsraelGeoIndex.synagoguesWithin(la, lo, km: 2);
      case NearbyKind.culture:
        return IsraelGeoIndex.cultureWithin(la, lo, km: 3);
      case NearbyKind.hospitals:
        return IsraelGeoIndex.hospitalsWithin(la, lo, km: 5);
      case NearbyKind.transit:
        return IsraelGeoIndex.transitStopsWithin(la, lo, km: 2);
      case NearbyKind.worship:
        return IsraelGeoIndex.worshipWithin(la, lo, km: 2);
      case NearbyKind.pools:
        return IsraelGeoIndex.poolsWithin(la, lo, km: 3);
      case NearbyKind.dogParks:
        return IsraelGeoIndex.dogParksWithin(la, lo, km: 2);
      case NearbyKind.vets:
        return IsraelGeoIndex.vetsWithin(la, lo, km: 3);
      case NearbyKind.bikeShare:
        return IsraelGeoIndex.bikeShareWithin(la, lo, km: 2);
      case NearbyKind.coworking:
        return IsraelGeoIndex.coworkingWithin(la, lo, km: 3);
      case NearbyKind.parking:
        return IsraelGeoIndex.parkingWithin(la, lo, km: 2);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _sections.isEmpty) return const SizedBox.shrink();
    return Directionality(
      textDirection: TextDirection.rtl,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('מקומות בקרבה',
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
        // Selected tag's places as a 3-column grid of square cards
        // (name · what it is · distance), each in one square component.
        if (_sections.isNotEmpty)
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1, // square
            children: [
              for (final pl in _sections[sel].$2.take(9)) _placeCard(pl),
            ],
          ),
      ],
    );
  }

  /// One square place card for the preview grid: name · type · distance.
  Widget _placeCard(NearbyPlace p) {
    final sub = _sub(p);
    return InkWell(
      onTap: () => _confirmOpenGoogle(p.name),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(p.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
            ),
            if (sub.isNotEmpty)
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10.5, color: AppColors.textSecondary)),
            const SizedBox(height: 3),
            Row(children: [
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
          Text(collapsed ? 'צפה בכולם (+$hidden)' : 'הצג פחות',
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
      onTap: () => setState(() => _selected = index),
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
                    '${places.length}${places.length >= 12 ? '+' : ''} · $radiusKm ק״מ',
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
    switch (kind) {
      case NearbyKind.schools:
        return (IconsaxPlusLinear.teacher, 'בתי ספר קרובים', 2);
      case NearbyKind.kindergartens:
        return (IconsaxPlusLinear.emoji_happy, 'גנים קרובים', 2);
      case NearbyKind.clinics:
        return (IconsaxPlusLinear.hospital, 'קופות חולים קרובות', 5);
      case NearbyKind.supermarkets:
        return (IconsaxPlusLinear.shopping_cart, 'סופרים קרובים', 2);
      case NearbyKind.parks:
        return (IconsaxPlusLinear.tree, 'פארקים קרובים', 2);
      case NearbyKind.pharmacies:
        return (IconsaxPlusLinear.health, 'בתי מרקחת קרובים', 2);
      case NearbyKind.playgrounds:
        return (IconsaxPlusLinear.game, 'גני שעשועים קרובים', 2);
      case NearbyKind.dining:
        return (IconsaxPlusLinear.reserve, 'מסעדות ובתי קפה קרובים', 2);
      case NearbyKind.gyms:
        return (IconsaxPlusLinear.weight, 'חדרי כושר קרובים', 3);
      case NearbyKind.nightlife:
        return (IconsaxPlusLinear.cup, 'ברים ופאבים קרובים', 2);
      case NearbyKind.synagogues:
        return (IconsaxPlusLinear.buildings, 'בתי כנסת קרובים', 2);
      case NearbyKind.culture:
        return (IconsaxPlusLinear.gallery, 'מוסדות תרבות קרובים', 3);
      case NearbyKind.hospitals:
        return (IconsaxPlusLinear.heart, 'בתי חולים קרובים', 5);
      case NearbyKind.transit:
        return (IconsaxPlusLinear.bus, 'תחנות רכבת ורק״ל קרובות', 2);
      case NearbyKind.worship:
        return (IconsaxPlusLinear.courthouse, 'מסגדים וכנסיות קרובים', 2);
      case NearbyKind.pools:
        return (IconsaxPlusLinear.drop, 'בריכות ומרכזי ספורט', 3);
      case NearbyKind.dogParks:
        return (IconsaxPlusLinear.pet, 'גינות כלבים קרובות', 2);
      case NearbyKind.vets:
        return (IconsaxPlusLinear.lifebuoy, 'וטרינרים קרובים', 3);
      case NearbyKind.bikeShare:
        return (IconsaxPlusLinear.routing, 'תחנות אופניים קרובות', 2);
      case NearbyKind.coworking:
        return (IconsaxPlusLinear.briefcase, 'חללי עבודה קרובים', 3);
      case NearbyKind.parking:
        return (IconsaxPlusLinear.car, 'חניונים קרובים', 2);
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
        return p.sector.isEmpty ? 'מרפאה' : p.sector;
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

  String _distLabel(double km) =>
      km < 1 ? '${(km * 1000).round()} מ׳' : '${km.toStringAsFixed(1)} ק״מ';

  Future<void> _confirmOpenGoogle(String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('לפתוח בגוגל?',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          content: Text('נחפש את «$name» בגוגל.',
              style:
                  const TextStyle(color: AppColors.textSecondary, height: 1.4)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ביטול')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('חפש בגוגל'),
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
