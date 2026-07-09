import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// "Nearby places" on the property detail screen: three collapsible sections —
/// kindergartens / schools / parks — each listing the real named places within
/// 2 km with their type and distance (sorted nearest-first). Tapping a place
/// offers to open a Google search for it. Data comes from [IsraelGeoIndex]
/// (bundled data.gov.il institutions + OSM parks).
class NearbyPlacesCard extends StatefulWidget {
  const NearbyPlacesCard({
    super.key,
    required this.lat,
    required this.lon,
    required this.city,
  });

  final double lat;
  final double lon;
  final String city;

  @override
  State<NearbyPlacesCard> createState() => _NearbyPlacesCardState();
}

class _NearbyPlacesCardState extends State<NearbyPlacesCard> {
  static const double _radiusKm = 2.0;
  List<NearbyPlace> _kindergartens = const [];
  List<NearbyPlace> _schools = const [];
  List<NearbyPlace> _parks = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Idempotent — no-ops if already loaded at startup.
    await Future.wait([IsraelGeoIndex.loadSchools(), IsraelGeoIndex.loadParks()]);
    if (!mounted) return;
    setState(() {
      _kindergartens = IsraelGeoIndex.kindergartensWithin(widget.lat, widget.lon,
          km: _radiusKm);
      _schools =
          IsraelGeoIndex.schoolsWithin(widget.lat, widget.lon, km: _radiusKm);
      _parks =
          IsraelGeoIndex.parksWithin(widget.lat, widget.lon, km: _radiusKm);
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    if (_kindergartens.isEmpty && _schools.isEmpty && _parks.isEmpty) {
      return const SizedBox.shrink();
    }
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
            _section('🏫', 'בתי ספר קרובים', _schools),
            if (_schools.isNotEmpty && _kindergartens.isNotEmpty) _divider(),
            _section('🧸', 'גנים קרובים', _kindergartens),
            if ((_schools.isNotEmpty || _kindergartens.isNotEmpty) &&
                _parks.isNotEmpty)
              _divider(),
            _section('🌳', 'פארקים קרובים', _parks),
          ],
        ),
      ),
    );
  }

  Widget _divider() =>
      Divider(height: 1, thickness: 1, color: AppColors.borderLight);

  Widget _section(String emoji, String title, List<NearbyPlace> places) {
    if (places.isEmpty) return const SizedBox.shrink();
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        childrenPadding: const EdgeInsets.only(bottom: 6),
        title: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${places.length}${places.length >= 12 ? '+' : ''} עד 2 ק״מ',
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

  Widget _placeRow(NearbyPlace p) {
    final sub = _typeLabel(p);
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

  // "יסודי ממלכתי" / "גן חרדי" / "תיכון" / "פארק".
  String _typeLabel(NearbyPlace p) {
    if (p.stage.isEmpty) return 'פארק';
    return p.sector.isEmpty ? p.stage : '${p.stage} · ${p.sector}';
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
              style: const TextStyle(color: AppColors.textSecondary, height: 1.4)),
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
    final uri = Uri.parse('https://www.google.com/search?q=$q');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {/* launch failed — nothing to do */}
  }
}
