import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

/// Side-by-side comparison of the tenant's saved (or searched-in) listings.
///
/// Rebuilt: the compare set is a single ordered list of up to 3 columns that is
/// SEEDED automatically from the first saved listings — so the screen never opens
/// blank. Chips add/remove columns; the search action pulls in non-saved flats.
class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});

  /// Max columns shown side-by-side (mobile-portrait ceiling).
  static const int maxColumns = 3;

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  /// Ordered ids of the listings currently in the comparison (<= maxColumns).
  final List<String> _columns = <String>[];

  /// Listings pulled in via search (not in the saved list).
  final List<RentalProperty> _searchAdded = <RentalProperty>[];

  /// Seed the columns exactly once, from the first saved listings.
  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // context.watch in build() makes this fire again when saved listings finish
    // loading, so seeding survives async persistence.
    if (_seeded) return;
    final pool = _pool(context.read<DatingProvider>());
    if (pool.length < 2) return;
    _columns
      ..clear()
      ..addAll(pool.take(CompareScreen.maxColumns).map((p) => p.id));
    _seeded = true;
  }

  /// Saved listings + search-added (deduped, saved first).
  List<RentalProperty> _pool(DatingProvider p) => <RentalProperty>[
        ...p.savedProperties,
        ..._searchAdded
            .where((a) => !p.savedProperties.any((s) => s.id == a.id)),
      ];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DatingProvider>();
    final pool = _pool(provider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('השוואת דירות'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          actions: [
            IconButton(
              tooltip: 'חיפוש דירה להשוואה',
              icon: const Icon(IconsaxPlusLinear.search_normal_1),
              onPressed: () => _openSearch(provider),
            ),
          ],
        ),
        body: _body(provider, pool),
      ),
    );
  }

  Widget _body(DatingProvider provider, List<RentalProperty> pool) {
    if (pool.length < 2) return _EmptyState(savedCount: pool.length);

    final columns = _resolveColumns(pool);
    final showChips = pool.length > CompareScreen.maxColumns;

    return Column(
      children: [
        if (showChips)
          _Selector(pool: pool, selected: _columns, onToggle: _toggle),
        if (columns.length < 2)
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'בחרו לפחות 2 דירות להשוואה',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          )
        else
          Expanded(child: _CompareTable(properties: columns, provider: provider)),
      ],
    );
  }

  /// The current columns as live properties, in the user's order, dropping any
  /// id that has left the pool (e.g. un-saved elsewhere).
  List<RentalProperty> _resolveColumns(List<RentalProperty> pool) {
    final byId = {for (final p in pool) p.id: p};
    return [
      for (final id in _columns)
        if (byId[id] != null) byId[id]!
    ];
  }

  void _toggle(String id) {
    setState(() {
      if (_columns.contains(id)) {
        _columns.remove(id);
      } else if (_columns.length < CompareScreen.maxColumns) {
        _columns.add(id);
      }
    });
  }

  Future<void> _openSearch(DatingProvider provider) async {
    final picked = await showModalBottomSheet<RentalProperty>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ComparePickerSheet(properties: provider.allProperties),
    );
    if (picked == null) return;
    setState(() {
      if (!_searchAdded.any((p) => p.id == picked.id) &&
          !provider.savedProperties.any((p) => p.id == picked.id)) {
        _searchAdded.add(picked);
      }
      // Make room + show it: if full, drop the oldest column.
      _columns.remove(picked.id);
      if (_columns.length >= CompareScreen.maxColumns) _columns.removeAt(0);
      _columns.add(picked.id);
    });
  }
}

/// Chips to add/remove columns when more than [maxColumns] are in the pool.
class _Selector extends StatelessWidget {
  const _Selector({
    required this.pool,
    required this.selected,
    required this.onToggle,
  });

  final List<RentalProperty> pool;
  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'בחרו עד ${CompareScreen.maxColumns} דירות (${selected.length}/${CompareScreen.maxColumns})',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final p in pool)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: FilterChip(
                      selected: selected.contains(p.id),
                      onSelected: (_) => onToggle(p.id),
                      label: Text(_shortLabel(p)),
                      labelStyle: TextStyle(
                        fontSize: 13,
                        color: selected.contains(p.id)
                            ? AppColors.textOnPrimary
                            : AppColors.textPrimary,
                      ),
                      selectedColor: AppColors.primary,
                      backgroundColor: AppColors.background,
                      checkmarkColor: AppColors.textOnPrimary,
                      side: BorderSide(color: AppColors.borderLight),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _shortLabel(RentalProperty p) {
    final where =
        p.neighborhood.trim().isNotEmpty ? p.neighborhood.trim() : p.city.trim();
    return '$where · ${p.priceLabel}';
  }
}

/// The side-by-side table. Numeric rows highlight the best value per row;
/// amenity rows show ✓/✗. A "best value" verdict card sits on top when the data
/// supports one.
class _CompareTable extends StatelessWidget {
  const _CompareTable({required this.properties, required this.provider});

  final List<RentalProperty> properties;
  final DatingProvider provider;

  @override
  Widget build(BuildContext context) {
    final rows = <_CompareRow>[
      _CompareRow.number('מחיר',
          (p) => p.price > 0 ? p.price.toDouble() : null, (p) => p.priceLabel,
          best: _Best.min),
      _CompareRow.number('₪ למ"ר', _perM2, _perM2Label, best: _Best.min),
      _CompareRow.text('חדרים', (p) => p.roomsLabel),
      _CompareRow.number('שטח',
          (p) => p.sizeM2 > 0 ? p.sizeM2.toDouble() : null,
          (p) => p.sizeM2 > 0 ? '${p.sizeM2} מ"ר' : '—',
          best: _Best.max),
      _CompareRow.text('קומה', _floorLabel),
      _CompareRow.flag('מעלית', (p) => p.featureFlags.isEnabled('elevator')),
      _CompareRow.flag('חניה', (p) => p.featureFlags.isEnabled('parking')),
      _CompareRow.flag('מרפסת', (p) => p.featureFlags.isEnabled('balcony')),
      _CompareRow.flag('ממ"ד', (p) => p.featureFlags.isEnabled('mamad')),
      _CompareRow.text('מצב',
          (p) => p.condition.trim().isEmpty ? '—' : p.condition.trim()),
      _CompareRow.number(
        'התאמה',
        (p) => provider.displayMatchScore(p)?.toDouble(),
        (p) {
          final s = provider.displayMatchScore(p);
          return s == null ? '—' : '$s%';
        },
        best: _Best.max,
      ),
    ];

    final bestIdx = _bestValueIndex(properties);
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (bestIdx >= 0) ...[
              _ValueVerdict(
                winner: properties[bestIdx],
                pros: _pros(properties, bestIdx),
                cons: _cons(properties, bestIdx),
                ppmLabel: _perM2Label(properties[bestIdx]),
              ),
              const SizedBox(height: 12),
            ],
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.borderLight),
              ),
              child: Column(
                children: [
                  _HeaderRow(properties: properties, winnerIndex: bestIdx),
                  for (var i = 0; i < rows.length; i++)
                    _DataRow(
                      row: rows[i],
                      properties: properties,
                      shaded: i.isEven,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _bestValueIndex(List<RentalProperty> props) => bestValueIndex(
        ppm: props.map(_perM2).toList(),
        featureFrac: [
          for (final p in props)
            _premiumFeatures.where((f) => p.featureFlags.isEnabled(f)).length /
                _premiumFeatures.length
        ],
        match: [for (final p in props) (provider.displayMatchScore(p) ?? 0) / 100.0],
      );

  static const _premiumFeatures = ['elevator', 'parking', 'balcony', 'mamad'];
  static const _featureHe = {
    'elevator': 'מעלית',
    'parking': 'חניה',
    'balcony': 'מרפסת',
    'mamad': 'ממ"ד',
  };

  List<String> _pros(List<RentalProperty> props, int idx) {
    final w = props[idx];
    final others = [
      for (var i = 0; i < props.length; i++)
        if (i != idx) props[i]
    ];
    final out = <String>[];
    final wPpm = _perM2(w);
    if (wPpm != null &&
        others.every((o) {
          final op = _perM2(o);
          return op == null || wPpm <= op;
        })) {
      out.add('התמורה הכי טובה למחיר — ${_perM2Label(w)} למ"ר');
    }
    if (w.price > 0 && others.every((o) => o.price <= 0 || w.price <= o.price)) {
      out.add('הכי זולה — ${w.priceLabel}');
    }
    if (w.sizeM2 > 0 && others.every((o) => w.sizeM2 >= o.sizeM2)) {
      out.add('הכי מרווחת — ${w.sizeM2} מ"ר');
    }
    for (final f in _premiumFeatures) {
      if (w.featureFlags.isEnabled(f) &&
          others.any((o) => !o.featureFlags.isEnabled(f))) {
        out.add('עם ${_featureHe[f]} (חלק מהאחרות בלי)');
      }
    }
    final wm = provider.displayMatchScore(w);
    if (wm != null &&
        others.every((o) {
          final om = provider.displayMatchScore(o);
          return om == null || wm >= om;
        })) {
      out.add('ההתאמה הגבוהה ביותר — $wm%');
    }
    return out.take(4).toList();
  }

  List<String> _cons(List<RentalProperty> props, int idx) {
    final w = props[idx];
    final others = [
      for (var i = 0; i < props.length; i++)
        if (i != idx) props[i]
    ];
    final out = <String>[];
    if (others.any((o) => o.price > 0 && (w.price <= 0 || o.price < w.price))) {
      out.add('לא הכי זולה בקבוצה');
    }
    if (others.any((o) => o.sizeM2 > w.sizeM2)) {
      out.add('יש מרווחת יותר בהשוואה');
    }
    for (final f in _premiumFeatures) {
      if (!w.featureFlags.isEnabled(f) &&
          others.any((o) => o.featureFlags.isEnabled(f))) {
        out.add('בלי ${_featureHe[f]} (יש באחרת)');
      }
    }
    return out.take(3).toList();
  }

  static double? _perM2(RentalProperty p) =>
      (p.sizeM2 <= 0 || p.price <= 0) ? null : p.price / p.sizeM2;

  static String _perM2Label(RentalProperty p) {
    if (p.sizeM2 <= 0 || p.price <= 0) return '—';
    return '₪${(p.price / p.sizeM2).round()}';
  }

  static String _floorLabel(RentalProperty p) {
    final floor = p.floor.trim();
    if (floor.isEmpty) return '—';
    final total = p.totalFloors.trim();
    return total.isEmpty ? floor : '$floor/$total';
  }
}

/// The value-for-money verdict: which listing gives the most per shekel, with an
/// honest pros/cons breakdown.
class _ValueVerdict extends StatelessWidget {
  const _ValueVerdict({
    required this.winner,
    required this.pros,
    required this.cons,
    required this.ppmLabel,
  });

  final RentalProperty winner;
  final List<String> pros;
  final List<String> cons;
  final String ppmLabel;

  String get _where {
    final w = winner.neighborhood.trim().isNotEmpty
        ? winner.neighborhood.trim()
        : winner.city.trim();
    return w.isNotEmpty ? w : winner.address;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            AppColors.primary,
            AppColors.primary.withValues(alpha: 0.82),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Text('🏆', style: TextStyle(fontSize: 20)),
              SizedBox(width: 8),
              Text('המשתלמת ביותר',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 6),
          Text(_where,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800)),
          Text('תמורה למחיר: $ppmLabel למ"ר · ${winner.priceLabel}',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5)),
          const SizedBox(height: 12),
          for (final p in pros)
            _line(IconsaxPlusBold.tick_circle, p, Colors.white),
          if (cons.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final c in cons)
              _line(IconsaxPlusLinear.minus_cirlce, c,
                  Colors.white.withValues(alpha: 0.78)),
          ],
        ],
      ),
    );
  }

  Widget _line(IconData icon, String text, Color color) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(text,
                  style:
                      TextStyle(color: color, fontSize: 12.5, height: 1.25)),
            ),
          ],
        ),
      );
}

/// Value-for-money pick: mostly ₪/m² (min is best), nudged by premium features
/// and match. Returns -1 (no winner) unless at least 2 columns have a real ₪/m²
/// — otherwise the "winner" is arbitrary, which is worse than showing none.
int bestValueIndex({
  required List<double?> ppm,
  required List<double> featureFrac,
  required List<double> match,
}) {
  if (ppm.length < 2) return -1;
  final valid = ppm.whereType<double>().toList();
  if (valid.length < 2) return -1;
  final maxPpm = valid.reduce((a, b) => a > b ? a : b);
  var best = 0;
  var bestScore = -1.0;
  for (var i = 0; i < ppm.length; i++) {
    final p = ppm[i];
    final ppmScore = (p == null || maxPpm == 0) ? 0.0 : (1 - p / maxPpm);
    final s = ppmScore * 0.6 + featureFrac[i] * 0.25 + match[i] * 0.15;
    if (s > bestScore) {
      bestScore = s;
      best = i;
    }
  }
  return best;
}

/// Column indices holding the best value. Uses an epsilon so float ties (₪/m²,
/// match %) all light up instead of one missing on rounding; returns empty when
/// every column has the same value (nothing to "win") or none are numeric.
Set<int> numericWinners(List<double?> vals, {required bool minIsBest}) {
  double? bestVal;
  for (final v in vals) {
    if (v == null) continue;
    if (bestVal == null || (minIsBest ? v < bestVal : v > bestVal)) bestVal = v;
  }
  if (bestVal == null) return const {};
  if (vals.whereType<double>().toSet().length < 2) return const {};
  final out = <int>{};
  for (var i = 0; i < vals.length; i++) {
    final v = vals[i];
    if (v != null && (v - bestVal).abs() < 0.5) out.add(i);
  }
  return out;
}

enum _Best { none, min, max }

class _CompareRow {
  const _CompareRow._(
      this.label, this.display, this.numeric, this.flag, this.best);
  final String label;
  final String Function(RentalProperty) display;
  final double? Function(RentalProperty)? numeric;
  final bool Function(RentalProperty)? flag;
  final _Best best;

  factory _CompareRow.text(String l, String Function(RentalProperty) d) =>
      _CompareRow._(l, d, null, null, _Best.none);

  factory _CompareRow.number(
    String l,
    double? Function(RentalProperty) numeric,
    String Function(RentalProperty) display, {
    required _Best best,
  }) =>
      _CompareRow._(l, display, numeric, null, best);

  factory _CompareRow.flag(String l, bool Function(RentalProperty) f) =>
      _CompareRow._(l, (p) => f(p) ? 'כן' : 'לא', null, f, _Best.none);
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.properties, this.winnerIndex = -1});
  final List<RentalProperty> properties;
  final int winnerIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryLight2,
      // IntrinsicHeight bounds the row height so crossAxisAlignment.stretch is
      // valid inside the vertical SingleChildScrollView. Without it the Row is
      // given infinite height and the whole table fails to lay out (blank page).
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _LabelCell(''),
            for (var ci = 0; ci < properties.length; ci++)
              Expanded(
                  child:
                      _headerCell(context, properties[ci], ci == winnerIndex)),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(BuildContext context, RentalProperty p, bool isWinner) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PropertyDetailScreen(property: p)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isWinner)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text('🏆 מומלץ',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                height: 54,
                width: double.infinity,
                child: SafeMedia(
                  media: p.primaryMedia,
                  fallback: Container(color: AppColors.borderLight),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _title(p),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: isWinner ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _title(RentalProperty p) {
    final where =
        p.neighborhood.trim().isNotEmpty ? p.neighborhood.trim() : p.city.trim();
    return where.isNotEmpty ? where : p.address;
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.row,
    required this.properties,
    required this.shaded,
  });

  final _CompareRow row;
  final List<RentalProperty> properties;
  final bool shaded;

  @override
  Widget build(BuildContext context) {
    final winners = _winners();
    return Container(
      color: shaded ? AppColors.background : AppColors.surface,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LabelCell(row.label),
            for (var i = 0; i < properties.length; i++)
              Expanded(child: _cell(properties[i], winners.contains(i))),
          ],
        ),
      ),
    );
  }

  Set<int> _winners() {
    if (row.numeric == null || row.best == _Best.none) return const {};
    return numericWinners(
      [for (final p in properties) row.numeric!(p)],
      minIsBest: row.best == _Best.min,
    );
  }

  Widget _cell(RentalProperty p, bool isWinner) {
    if (row.flag != null) {
      final on = row.flag!(p);
      return Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        child: Icon(
          on ? IconsaxPlusBold.tick_circle : IconsaxPlusLinear.minus_cirlce,
          color: on ? AppColors.success : AppColors.textDisabled,
          size: 22,
        ),
      );
    }
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      color: isWinner ? AppColors.primary.withValues(alpha: 0.10) : null,
      // NOTE: no FittedBox here — it doesn't support the intrinsic sizing that
      // the row's IntrinsicHeight needs and throws "RenderBox was not laid out",
      // leaving the whole table blank. Plain single-line text + ellipsis instead.
      child: Text(
        row.display(p),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15,
          fontWeight: isWinner ? FontWeight.w900 : FontWeight.w700,
          color: isWinner ? AppColors.primary : AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _LabelCell extends StatelessWidget {
  const _LabelCell(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 84,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.savedCount});
  final int savedCount;

  @override
  Widget build(BuildContext context) {
    final message = savedCount == 0
        ? 'עדיין לא שמרתם דירות.\nשמרו לפחות 2 דירות כדי להשוות ביניהן.'
        : 'שמרתם דירה אחת בלבד.\nשמרו עוד דירה כדי להשוות ביניהן.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.compare_arrows_rounded,
                size: 64, color: AppColors.textDisabled),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 17, height: 1.4, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Searchable catalog list → returns the tapped property to add to the compare.
class _ComparePickerSheet extends StatefulWidget {
  const _ComparePickerSheet({required this.properties});
  final List<RentalProperty> properties;
  @override
  State<_ComparePickerSheet> createState() => _ComparePickerSheetState();
}

class _ComparePickerSheetState extends State<_ComparePickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.properties
        : widget.properties.where((p) {
            return p.city.toLowerCase().contains(q) ||
                p.neighborhood.toLowerCase().contains(q) ||
                p.address.toLowerCase().contains(q);
          }).toList();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (context, scroll) => Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 12),
              const Align(
                alignment: Alignment.centerRight,
                child: Text('הוספת דירה להשוואה',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 10),
              TextField(
                textDirection: TextDirection.rtl,
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                decoration: InputDecoration(
                  hintText: 'חיפוש לפי עיר / שכונה / כתובת…',
                  prefixIcon: const Icon(IconsaxPlusLinear.search_normal_1),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: list.isEmpty
                    ? const Center(
                        child: Text('אופס! לא נמצאו דירות תואמות',
                            style: TextStyle(color: AppColors.textSecondary)))
                    : ListView.builder(
                        controller: scroll,
                        itemCount: list.length,
                        itemBuilder: (_, i) {
                          final p = list[i];
                          final where = p.neighborhood.trim().isNotEmpty
                              ? '${p.neighborhood}, ${p.city}'
                              : p.city;
                          return ListTile(
                            leading: Icon(Icons.home_outlined,
                                color: AppColors.primary),
                            title: Text(where,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle:
                                Text('${p.priceLabel} · ${p.roomsLabel} חד׳'),
                            onTap: () => Navigator.of(context).pop(p),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
