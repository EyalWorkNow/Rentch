import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/nearby_relevance.dart';
import 'package:flutter/material.dart';
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
  });

  final double lat;
  final double lon;
  final String city;
  final NearbyProfile profile;

  @override
  State<NearbyPlacesCard> createState() => _NearbyPlacesCardState();
}

class _NearbyPlacesCardState extends State<NearbyPlacesCard> {
  final List<(NearbySection, List<NearbyPlace>)> _sections = [];
  bool _loaded = false;

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
    ]);
    if (!mounted) return;
    // Show ALL nearby kinds with data (full reference), persona-relevant first.
    final out = <(NearbySection, List<NearbyPlace>)>[];
    for (final s in orderedNearbySections(widget.profile)) {
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _sections.length; i++) ...[
              if (i > 0)
                Divider(height: 1, thickness: 1, color: AppColors.borderLight),
              _section(_sections[i].$1.kind, _sections[i].$2),
            ],
          ],
        ),
      ),
    );
  }

  Widget _section(NearbyKind kind, List<NearbyPlace> places) {
    final (emoji, title, radiusKm) = _meta(kind);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        childrenPadding: const EdgeInsets.only(bottom: 6),
        title: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Flexible(
              child: Text(title,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.navy)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${places.length}${places.length >= 12 ? '+' : ''} עד $radiusKm ק״מ',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark),
              ),
            ),
          ],
        ),
        children: [for (final p in places) _placeRow(p)],
      ),
    );
  }

  (String, String, int) _meta(NearbyKind kind) {
    switch (kind) {
      case NearbyKind.schools:
        return ('🏫', 'בתי ספר קרובים', 2);
      case NearbyKind.kindergartens:
        return ('🧸', 'גנים קרובים', 2);
      case NearbyKind.clinics:
        return ('🏥', 'קופות חולים קרובות', 5);
      case NearbyKind.supermarkets:
        return ('🛒', 'סופרים קרובים', 2);
      case NearbyKind.parks:
        return ('🌳', 'פארקים קרובים', 2);
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
