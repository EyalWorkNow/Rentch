import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/insights/area_intelligence.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/services/govmap_geocoder.dart';
import 'package:dating_app/core/services/overpass_poi_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/features/broker/area_ranking_screen.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// One autocomplete suggestion — resolved to REAL coordinates up front (CBS
/// locality centroid or an actual listing), so the profile never depends on the
/// flaky OS geocoder.
class _PlaceSuggestion {
  const _PlaceSuggestion(this.label, this.lat, this.lon, this.city);
  final String label;
  final double lat, lon;
  final String city;
}

/// One category of concrete nearby places to render ("what's actually here").
class _NearbyCategory {
  const _NearbyCategory(this.key, this.emoji, this.label, this.places);
  final String key, emoji, label;
  final List<NearbyPlace> places;
}

/// "אינטליגנציית אזור" — enter an address, get every gov-data layer at that spot
/// and see which target tenant/buyer persona it serves best (and why). The
/// supply-side mirror of the tenant search engine (see AreaIntelligence).
class AreaIntelScreen extends StatefulWidget {
  const AreaIntelScreen({super.key});
  @override
  State<AreaIntelScreen> createState() => _AreaIntelScreenState();
}

class _AreaIntelScreenState extends State<AreaIntelScreen> {
  bool _loading = false;
  String? _error;
  AreaProfile? _profile;
  List<PersonaFit> _fits = const [];
  List<_NearbyCategory> _nearby = const [];
  final Set<String> _expandedCats = {};
  String _selectedPersona = 'young_couples';

  String _acToken = '';

  /// Address autocomplete. PRIMARY = GovMap (official Israeli mapping) — every
  /// town, street and house number with precise coordinates, so the profile is
  /// built at the EXACT spot. Debounced so only the last keystroke hits the
  /// network. Falls back to offline locality/listing suggestions if GovMap is
  /// unreachable or returns nothing.
  Future<Iterable<_PlaceSuggestion>> _acOptions(String raw) async {
    final q = raw.trim();
    if (q.length < 2) return const [];
    final token = q;
    _acToken = token;
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (_acToken != token || !mounted) return const [];
    final gov = await GovMapGeocoder.instance.search(q);
    if (_acToken != token) return const []; // superseded while awaiting
    if (gov.isNotEmpty) {
      return gov
          .map((p) => _PlaceSuggestion(p.label, p.lat, p.lon, p.city))
          .toList();
    }
    return _suggest(q);
  }

  /// Offline fallback suggestions from OUR data: every CBS locality (reliable
  /// centroid coords) + real listings from the loaded catalogue (street-level).
  List<_PlaceSuggestion> _suggest(String raw) {
    final q = raw.trim();
    if (q.length < 2) return const [];
    final out = <_PlaceSuggestion>[];
    final seen = <String>{};
    for (final l in GovData.instance.localities) {
      if (l.lat.abs() < 0.1) continue;
      if (l.name.contains(q) && seen.add(l.name)) {
        out.add(_PlaceSuggestion(l.name, l.lat, l.lon, l.name));
      }
      if (out.length >= 6) break;
    }
    List<RentalProperty> props;
    try {
      props = context.read<DatingProvider>().allProperties;
    } catch (_) {
      props = const [];
    }
    for (final p in props) {
      if (p.lat.abs() < 0.1) continue;
      if (p.street.contains(q) ||
          p.city.contains(q) ||
          p.neighborhood.contains(q)) {
        final label = p.street.isEmpty
            ? p.city
            : '${p.street} ${p.streetNumber}, ${p.city}';
        if (seen.add(label)) {
          out.add(_PlaceSuggestion(label, p.lat, p.lon, p.city));
        }
      }
      if (out.length >= 12) break;
    }
    return out.take(10).toList();
  }

  Future<void> _analyze(_PlaceSuggestion? picked, String typed) async {
    if (_loading) return;
    final q = (picked?.label ?? typed).trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      double lat, lon;
      String city;
      if (picked != null) {
        lat = picked.lat;
        lon = picked.lon;
        city = picked.city;
      } else {
        // Manual submit without picking a suggestion: resolve via GovMap first
        // (precise), then a CBS locality named in the text, then the OS geocoder.
        final gov = await GovMapGeocoder.instance.search(q);
        if (gov.isNotEmpty) {
          lat = gov.first.lat;
          lon = gov.first.lon;
          city = gov.first.city;
        } else {
          final loc = GovData.instance.findLocalityInText(q);
          if (loc != null) {
            lat = loc.lat;
            lon = loc.lon;
            city = loc.name;
          } else {
            final geo = await locationFromAddress(q);
            if (geo.isEmpty) throw 'no-geo';
            lat = geo.first.latitude;
            lon = geo.first.longitude;
            city = GovData.instance.statAreaAt(lat, lon)?.city ?? '';
          }
        }
      }
      // Normalize the resolved city to GovData's canonical spelling (GovMap
      // returns "תל אביב-יפו"), so the city-keyed lookups (safety / rent / yield)
      // hit instead of falling back to defaults. Block-level SES + demographics
      // still come from the exact-point stat-area polygon regardless.
      final canon = GovData.instance.findLocalityInText(city)?.name;
      if (canon != null && canon.isNotEmpty) city = canon;
      // The lifestyle POI layers (dining / gyms / pharmacies / culture / transit /
      // playgrounds) are lazy-loaded — the tenant card loads them, but this screen
      // may open first. All loaders are idempotent, so this is a one-time cost.
      await Future.wait([
        IsraelGeoIndex.loadLifestylePois(),
        IsraelGeoIndex.loadParks(),
        IsraelGeoIndex.loadSchools(),
        IsraelGeoIndex.loadSupermarkets(),
        IsraelGeoIndex.loadClinics(),
      ]);
      final profile = AreaIntelligence.profileAt(lat, lon, city: city);
      final fits = AreaIntelligence.suitablePersonas(profile.pfv);
      final nearby = await _collectNearby(lat, lon);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _fits = fits;
        _nearby = nearby;
        _expandedCats.clear();
        _selectedPersona = fits.first.persona.key;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'לא הצלחתי לאתר את הכתובת. נסה לבחור מההשלמה או לכתוב עיר + רחוב.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// EVERYTHING within [_radiusKm] of the point, by category. Merges the LIVE
  /// OpenStreetMap/Overpass POIs (comprehensive — the bundled files miss many
  /// cafés/gyms/parks) with our bundled gov layers, deduped, so nothing in the
  /// radius is left out. Async because Overpass is a live query.
  static const double _radiusKm = 2.0;

  Future<List<_NearbyCategory>> _collectNearby(double lat, double lon) async {
    final ov = await OverpassPoiService.instance
        .nearby(lat, lon, radiusM: (_radiusKm * 1000).round());

    List<NearbyPlace> merge(String key, List<NearbyPlace> bundled) {
      final all = <NearbyPlace>[...bundled, ...(ov[key] ?? const [])];
      final seen = <String>{};
      final dedup = <NearbyPlace>[];
      for (final p in all) {
        if (p.km > _radiusKm) continue;
        final id = p.name.isEmpty
            ? '${p.lat.toStringAsFixed(4)},${p.lon.toStringAsFixed(4)}'
            : p.name.replaceAll(RegExp(r'\s+'), '');
        if (seen.add('$key|$id')) dedup.add(p);
      }
      dedup.sort((a, b) => a.km.compareTo(b.km));
      return dedup;
    }

    final defs = <List<Object>>[
      ['transit', '🚉', 'תחבורה ציבורית',
          IsraelGeoIndex.transitStopsWithin(lat, lon, km: _radiusKm, cap: 120)],
      ['schools', '🏫', 'בתי ספר',
          IsraelGeoIndex.schoolsWithin(lat, lon, km: _radiusKm, cap: 120)],
      ['kindergartens', '🧸', 'גני ילדים',
          IsraelGeoIndex.kindergartensWithin(lat, lon, km: _radiusKm, cap: 120)],
      ['parks', '🌳', 'פארקים וגינות',
          IsraelGeoIndex.parksWithin(lat, lon, km: _radiusKm, cap: 120)],
      ['dining', '☕', 'בתי קפה ומסעדות',
          IsraelGeoIndex.diningWithin(lat, lon, km: _radiusKm, cap: 120)],
      ['supermarkets', '🛒', 'סופרמרקטים וקניות',
          IsraelGeoIndex.supermarketsWithin(lat, lon, km: _radiusKm, cap: 120)],
      ['health', '🏥', 'שירותי בריאות',
          IsraelGeoIndex.clinicsWithin(lat, lon, km: _radiusKm, cap: 120)],
      ['pharmacies', '💊', 'בתי מרקחת',
          IsraelGeoIndex.pharmaciesWithin(lat, lon, km: _radiusKm, cap: 120)],
      ['gyms', '🏋️', 'חדרי כושר וספורט',
          IsraelGeoIndex.gymsWithin(lat, lon, km: _radiusKm, cap: 120)],
      ['worship', '🕍', 'בתי כנסת ותפילה',
          IsraelGeoIndex.synagoguesWithin(lat, lon, km: _radiusKm, cap: 120)],
      ['culture', '🎭', 'תרבות ופנאי',
          IsraelGeoIndex.cultureWithin(lat, lon, km: _radiusKm, cap: 120)],
      ['playgrounds', '🛝', 'גני משחקים',
          IsraelGeoIndex.playgroundsWithin(lat, lon, km: _radiusKm, cap: 120)],
    ];
    final cats = <_NearbyCategory>[];
    for (final d in defs) {
      final places = merge(d[0] as String, d[3] as List<NearbyPlace>);
      if (places.isNotEmpty) {
        cats.add(_NearbyCategory(
            d[0] as String, d[1] as String, d[2] as String, places));
      }
    }
    return cats;
  }

  static String _dist(double km) =>
      km < 1 ? '${(km * 1000).round()} מ׳' : '${km.toStringAsFixed(1)} ק״מ';

  // Tapping a place searches it on Google (name + city; unnamed → its category
  // + city), opening the browser/Google app.
  Future<void> _searchGoogle(NearbyPlace p, String catLabel) async {
    final city = _profile?.city ?? '';
    final q = (p.name.isEmpty ? '$catLabel $city' : '${p.name} $city').trim();
    final uri = Uri.parse(
        'https://www.google.com/search?q=${Uri.encodeQueryComponent(q)}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {/* no browser available — ignore */}
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          surfaceTintColor: AppColors.primary,
          elevation: 0,
          centerTitle: true,
          title: const Text('אינטליגנציית אזור',
              style: TextStyle(
                  color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              _intro(),
              const SizedBox(height: 10),
              // Cross-link to the city-wide ranking (Phase 2).
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AreaRankingScreen())),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    Icon(IconsaxPlusLinear.ranking_1, color: AppColors.primary, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('דרג את כל האזורים בעיר לפי קהל יעד',
                          style: TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary)),
                    ),
                    Icon(IconsaxPlusLinear.arrow_left_2,
                        color: AppColors.primary, size: 18),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              _addressRow(),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: TextStyle(color: AppColors.error, fontSize: 13.5)),
              ],
              if (_profile != null) ...[
                const SizedBox(height: 18),
                _personaPicker(),
                const SizedBox(height: 12),
                _selectedFitCard(),
                const SizedBox(height: 18),
                _sectionTitle('עדשת השקעה'),
                const SizedBox(height: 10),
                _investmentCard(_profile!.investment),
                const SizedBox(height: 18),
                _sectionTitle('כל שכבות הנתונים במקום'),
                const SizedBox(height: 10),
                _layersCard(_profile!),
                if (_nearby.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _sectionTitle('מה יש בסביבה'),
                  const SizedBox(height: 10),
                  _nearbyCard(),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _intro() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
        ),
        child: Row(children: [
          Icon(IconsaxPlusLinear.map_1, color: AppColors.primary, size: 24),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'הזן כתובת לבדיקת השקעה — ואקבל את כל הנתונים והשכבות של האזור, '
              'ולמי הוא הכי מתאים. ככה תדע בדיוק איזה קהל לחפש ומה חוזק המקום.',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      );

  Widget _addressRow() => Autocomplete<_PlaceSuggestion>(
        displayStringForOption: (o) => o.label,
        optionsBuilder: (v) => _acOptions(v.text),
        onSelected: (o) => _analyze(o, o.label),
        optionsViewBuilder: (context, onSelected, options) => Align(
          alignment: Alignment.topRight,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, maxWidth: 340),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final o in options)
                    ListTile(
                      dense: true,
                      leading: Icon(IconsaxPlusLinear.location,
                          size: 18, color: AppColors.primary),
                      title: Text(o.label,
                          style: const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700)),
                      onTap: () => onSelected(o),
                    ),
                ],
              ),
            ),
          ),
        ),
        fieldViewBuilder: (context, controller, focus, onSubmit) =>
            Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focus,
              textInputAction: TextInputAction.search,
              onSubmitted: (t) => _analyze(null, t),
              decoration: InputDecoration(
                hintText: 'כתובת: עיר + רחוב (למשל: תל אביב, דיזנגוף 100)',
                filled: true,
                fillColor: Colors.white,
                prefixIcon:
                    Icon(IconsaxPlusLinear.location, color: AppColors.primary),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppColors.borderLight)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: AppColors.borderLight)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _loading ? null : () => _analyze(null, controller.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('נתח',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            ),
          ),
        ]),
      );

  Widget _personaPicker() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final f in _fits) ...[
            _personaChip(f),
            const SizedBox(width: 8),
          ],
        ]),
      );

  Widget _personaChip(PersonaFit f) {
    final on = f.persona.key == _selectedPersona;
    return GestureDetector(
      onTap: () => setState(() => _selectedPersona = f.persona.key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: on ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
              color: on ? AppColors.primary : AppColors.borderLight),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${f.persona.emoji} ${f.persona.label}',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: on ? Colors.white : AppColors.navy)),
          const SizedBox(width: 6),
          Text('${f.pct}%',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: on ? Colors.white70 : AppColors.primary)),
        ]),
      ),
    );
  }

  Widget _selectedFitCard() {
    final f = _fits.firstWhere((x) => x.persona.key == _selectedPersona,
        orElse: () => _fits.first);
    final color = f.pct >= 75
        ? AppColors.success
        : (f.pct >= 55 ? AppColors.primary : AppColors.warning);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('${f.persona.emoji} ${f.persona.label}',
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999)),
            child: Text('${f.pct}% התאמה',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w900, color: color)),
          ),
        ]),
        const SizedBox(height: 12),
        if (f.reasons.isEmpty)
          Text('האזור פחות מתאים לקהל הזה.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5))
        else ...[
          Text('למה זה עובד לקהל הזה:',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in f.reasons)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999)),
                child: Text('✓ ${r.label}',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark)),
              ),
          ]),
        ],
      ]),
    );
  }

  Widget _investmentCard(InvestmentLens inv) {
    final scoreColor = inv.investmentScore >= 70
        ? AppColors.success
        : (inv.investmentScore >= 50 ? AppColors.primary : AppColors.warning);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(IconsaxPlusLinear.chart_21, color: scoreColor, size: 20),
          const SizedBox(width: 8),
          const Text('ציון השקעה',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: scoreColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999)),
            child: Text('${inv.investmentScore}/100',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w900, color: scoreColor)),
          ),
        ]),
        const SizedBox(height: 12),
        _bar('ביקוש שכירות (קלות השכרה)', inv.rentability),
        _bar('פוטנציאל השבחה (תשתית מתוכננת)', inv.appreciation),
        if (inv.relativePriceTier != null)
          _bar('רמת מחירים באזור (יחסי)', inv.relativePriceTier!),
        if (inv.roughYieldPct != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: Text('הערכת תשואה ברוטו',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary))),
            Text('~${inv.roughYieldPct!.toStringAsFixed(1)}%',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w900,
                    color: AppColors.primary)),
          ]),
        ],
        const SizedBox(height: 8),
        Text(
          inv.valuePerSqm2013 != null
              ? 'רמת המחירים מבוססת על שווי הלמ״ס 2013 (₪${inv.valuePerSqm2013}/מ״ר) — מדד יחסי; התשואה הערכה גסה בלבד.'
              : 'ביקוש והשבחה מנתונים עדכניים. אין נתוני שווי לאזור זה.',
          style: TextStyle(
              fontSize: 11, height: 1.35, color: AppColors.textSecondary),
        ),
      ]),
    );
  }

  Widget _layersCard(AreaProfile p) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(children: [
        if (p.sesCluster > 0)
          _clusterRow('אשכול סוציו-אקונומי (בלוק)', p.sesCluster),
        _bar('בטיחות (ברמת העיר)', p.safety),
        _bar('מרכזיות', p.centrality),
        _bar('תחבורה ציבורית', p.transit),
        _bar('מוסדות חינוך', p.schools),
        _bar('שירותי בריאות', p.health),
        _bar('חיי לילה ובילוי', p.nightlife),
        _bar('קרבה לתעסוקה', p.employment),
        _bar('פארקים וירוק', p.parkAccess),
        _bar('פוטנציאל השבחה', p.futureValue),
        const Divider(height: 22),
        _demographics(p),
      ]),
    );
  }

  Widget _clusterRow(String label, int cluster) {
    final color = cluster >= 7
        ? AppColors.success
        : (cluster >= 4 ? AppColors.primary : AppColors.warning);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(children: [
        Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999)),
          child: Text('$cluster מתוך 10',
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w900, color: color)),
        ),
      ]),
    );
  }

  Widget _bar(String label, double v) {
    final pct = (v.clamp(0.0, 1.0) * 100).round();
    final color = pct >= 66
        ? AppColors.success
        : (pct >= 40 ? AppColors.primary : AppColors.warning);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary))),
          Text('$pct%',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w900, color: color)),
        ]),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: v.clamp(0.0, 1.0),
            minHeight: 7,
            backgroundColor: AppColors.borderLight,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ]),
    );
  }

  Widget _demographics(AreaProfile p) => Row(children: [
        _demoStat('👶 ילדים (0-19)', p.childShare),
        _demoStat('🧑 עובדים (20-64)', p.youngShare),
        _demoStat('🌿 65+', p.seniorShare),
      ]);

  Widget _demoStat(String label, double share) => Expanded(
        child: Column(children: [
          Text('${(share.clamp(0.0, 1.0) * 100).round()}%',
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 10.5, color: AppColors.textSecondary)),
        ]),
      );

  Widget _nearbyCard() => Container(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(children: [
          for (final c in _nearby) _nearbyCategory(c),
        ]),
      );

  static const int _collapsedCount = 12;

  Widget _nearbyCategory(_NearbyCategory c) {
    final expanded = _expandedCats.contains(c.key);
    final shown =
        expanded ? c.places : c.places.take(_collapsedCount).toList();
    final hidden = c.places.length - shown.length;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${c.emoji}  ${c.label}',
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary)),
          ),
          // The count makes completeness visible — "everything within 2 km".
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999)),
            child: Text('${c.places.length}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: AppColors.primaryDark)),
          ),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final p in shown)
            GestureDetector(
              onTap: () => _searchGoogle(p, c.label),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.12))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    '${p.name.isEmpty ? c.label : p.name} · ${_dist(p.km)}',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark),
                  ),
                  const SizedBox(width: 5),
                  Icon(IconsaxPlusLinear.search_normal_1,
                      size: 12, color: AppColors.primary),
                ]),
              ),
            ),
          if (hidden > 0)
            GestureDetector(
              onTap: () => setState(() => _expandedCats.add(c.key)),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(999)),
                child: Text('+ $hidden נוספים · הצג הכל',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ),
          if (expanded && c.places.length > _collapsedCount)
            GestureDetector(
              onTap: () => setState(() => _expandedCats.remove(c.key)),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.borderLight)),
                child: Text('הצג פחות',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary)),
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textPrimary));
}
