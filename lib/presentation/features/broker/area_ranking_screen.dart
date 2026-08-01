import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/insights/area_intelligence.dart';
import 'package:dating_app/core/insights/target_personas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:latlong2/latlong.dart';

/// "דרג אזורים בעיר" — pick a target persona + a city and rank ALL the city's CBS
/// statistical blocks best→worst for that crowd, as a list AND a colour-graded
/// map. The "where should I buy for this audience" view (Area Intelligence P2).
class AreaRankingScreen extends StatefulWidget {
  const AreaRankingScreen({super.key});
  @override
  State<AreaRankingScreen> createState() => _AreaRankingScreenState();
}

class _AreaRankingScreenState extends State<AreaRankingScreen> {
  final _city = TextEditingController();
  String _persona = 'families';
  bool _loading = false;
  bool _mapView = false;
  String? _error;
  List<RankedArea> _ranked = const [];

  static Color _fitColor(int pct) => pct >= 72
      ? AppColors.success
      : (pct >= 56 ? AppColors.primary : (pct >= 42 ? AppColors.warning : AppColors.error));

  Future<void> _rank() async {
    final city = _city.text.trim();
    if (city.isEmpty || _loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    // rankCityAreas is synchronous but heavy for a big city; yield a frame so the
    // spinner paints, and cap the map/list to the top 60 blocks.
    final persona = TargetPersona.byKey(_persona)!;
    final ranked = await Future(() =>
        AreaIntelligence.rankCityAreas(city, persona, limit: 60));
    if (!mounted) return;
    setState(() {
      _loading = false;
      _ranked = ranked;
      if (ranked.isEmpty) {
        _error = 'לא מצאתי אזורים סטטיסטיים לעיר הזו. נסה שם עיר מלא (למשל: תל אביב, חיפה, ירושלים).';
      }
    });
  }

  @override
  void dispose() {
    _city.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('דרג אזורים בעיר'),
          bottom: const PreferredSize(
            preferredSize: Size.fromHeight(1),
            child: Divider(color: AppColors.divider, height: 1, thickness: 1),
          ),
          actions: [
            if (_ranked.isNotEmpty)
              IconButton(
                onPressed: () => setState(() => _mapView = !_mapView),
                icon: Icon(_mapView ? IconsaxPlusLinear.task_square : IconsaxPlusLinear.map_1),
                tooltip: _mapView ? 'רשימה' : 'מפה',
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(children: [
                _personaPicker(),
                const SizedBox(height: 10),
                _cityRow(),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      style: TextStyle(color: AppColors.error, fontSize: 13)),
                ],
              ]),
            ),
            if (_ranked.isNotEmpty)
              Expanded(child: _mapView ? _map() : _list()),
          ]),
        ),
      ),
    );
  }

  Widget _personaPicker() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final p in TargetPersona.all) ...[
            _personaChip(p),
            const SizedBox(width: 8),
          ],
        ]),
      );

  Widget _personaChip(TargetPersona p) {
    final on = p.key == _persona;
    return GestureDetector(
      onTap: () {
        setState(() {
          _persona = p.key;
          _ranked = const []; // force a re-rank for the new persona
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: on ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: on ? AppColors.primary : AppColors.borderLight),
        ),
        child: Text('${p.emoji} ${p.label}',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: on ? Colors.white : AppColors.navy)),
      ),
    );
  }

  Widget _cityRow() => Row(children: [
        Expanded(
          child: TextField(
            controller: _city,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _rank(),
            decoration: InputDecoration(
              hintText: 'עיר (למשל: תל אביב)',
              filled: true,
              fillColor: Colors.white,
              prefixIcon: Icon(IconsaxPlusLinear.buildings, color: AppColors.primary),
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
            onPressed: _loading ? null : _rank,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: _loading
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('דרג',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          ),
        ),
      ]);

  // ── list view ──────────────────────────────────────────────────────────────
  Widget _list() => ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
        itemCount: _ranked.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) => _rankRow(i + 1, _ranked[i]),
      );

  Widget _rankRow(int rank, RankedArea r) {
    final color = _fitColor(r.fit.pct);
    final reason = r.fit.reasons.isNotEmpty ? r.fit.reasons.first.label : '';
    return GestureDetector(
      onTap: () => _showDetail(r),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Row(children: [
          Container(
            width: 34, height: 34, alignment: Alignment.center,
            decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10)),
            child: Text('$rank',
                style: TextStyle(
                    fontWeight: FontWeight.w900, color: AppColors.primaryDark)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('אזור ${r.area.id}  ·  אשכול ${r.area.ses}/10',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              if (reason.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('✓ $reason',
                      style: TextStyle(
                          fontSize: 12.5, color: AppColors.textSecondary)),
                ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999)),
            child: Text('${r.fit.pct}%',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w900, color: color)),
          ),
        ]),
      ),
    );
  }

  // ── map view ───────────────────────────────────────────────────────────────
  Widget _map() {
    // Centre on the mean of the ranked centroids.
    var la = 0.0, lo = 0.0;
    for (final r in _ranked) {
      la += r.centroid[0];
      lo += r.centroid[1];
    }
    final center = LatLng(la / _ranked.length, lo / _ranked.length);
    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: 12),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.rentch.app',
        ),
        PolygonLayer(
          polygons: [
            for (final r in _ranked)
              Polygon(
                points: [for (final p in r.poly) LatLng(p[0], p[1])],
                color: _fitColor(r.fit.pct).withValues(alpha: 0.45),
                borderColor: _fitColor(r.fit.pct),
                borderStrokeWidth: 1,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final r in _ranked)
              Marker(
                point: LatLng(r.centroid[0], r.centroid[1]),
                width: 34, height: 22,
                child: GestureDetector(
                  onTap: () => _showDetail(r),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: _fitColor(r.fit.pct),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white, width: 1.5)),
                    child: Text('${r.fit.pct}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  void _showDetail(RankedArea r) {
    final p = r.profile;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('אזור ${r.area.id}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: _fitColor(r.fit.pct).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999)),
                child: Text('${r.fit.pct}% התאמה',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w900,
                        color: _fitColor(r.fit.pct))),
              ),
            ]),
            const SizedBox(height: 12),
            if (r.fit.reasons.isNotEmpty)
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final rn in r.fit.reasons)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(999)),
                    child: Text('✓ ${rn.label}',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700,
                            color: AppColors.primaryDark)),
                  ),
              ]),
            const SizedBox(height: 14),
            _miniStat('אשכול סוציו-אקונומי', '${r.area.ses}/10'),
            _miniStat('בטיחות', '${(p.safety * 100).round()}%'),
            _miniStat('מרכזיות', '${(p.centrality * 100).round()}%'),
            _miniStat('תחבורה', '${(p.transit * 100).round()}%'),
            _miniStat('חינוך', '${(p.schools * 100).round()}%'),
            _miniStat('ילדים / עובדים / 65+',
                '${(p.childShare * 100).round()}% · ${(p.youngShare * 100).round()}% · ${(p.seniorShare * 100).round()}%'),
            const Divider(height: 20),
            _miniStat('💰 ציון השקעה', '${p.investment.investmentScore}/100'),
            _miniStat('ביקוש שכירות', '${(p.investment.rentability * 100).round()}%'),
            if (p.investment.roughYieldPct != null)
              _miniStat('הערכת תשואה (גסה)',
                  '~${p.investment.roughYieldPct!.toStringAsFixed(1)}%'),
          ]),
        ),
      ),
    );
  }

  Widget _miniStat(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(
              child: Text(k,
                  style: const TextStyle(
                      fontSize: 13.5, color: AppColors.textSecondary))),
          Text(v,
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
        ]),
      );
}
