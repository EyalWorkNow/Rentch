import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Feature #7 — side-by-side comparison of the tenant's saved properties.
///
/// Reads (READ-ONLY) [DatingProvider.savedProperties]. If the tenant saved more
/// than 3 listings, a selector lets them pick up to 3 to compare. An empty/under
/// state is shown when fewer than 2 are saved (nothing to compare).
class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});

  /// Max columns shown side-by-side.
  static const int maxColumns = 3;

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

class _CompareScreenState extends State<CompareScreen> {
  /// Property ids the user picked to compare (only used when >3 saved).
  final Set<String> _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DatingProvider>();
    final saved = provider.savedProperties;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('השוואת דירות'),
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        body: _buildBody(context, provider, saved),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    DatingProvider provider,
    List<RentalProperty> saved,
  ) {
    if (saved.length < 2) {
      return _EmptyState(savedCount: saved.length);
    }

    final needsSelection = saved.length > CompareScreen.maxColumns;
    final List<RentalProperty> columns = needsSelection
        ? _resolveSelection(saved)
        : saved;

    return Column(
      children: [
        if (needsSelection)
          _Selector(
            saved: saved,
            selected: _selected,
            onToggle: _toggle,
          ),
        if (columns.length < 2)
          const Expanded(
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'בחרו עד 3 דירות להשוואה',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
        else
          Expanded(child: _CompareTable(properties: columns, provider: provider)),
      ],
    );
  }

  /// When more than 3 are saved, show the user's picks (capped at 3). If they
  /// haven't picked enough yet, fall back to the first few so something shows.
  List<RentalProperty> _resolveSelection(List<RentalProperty> saved) {
    final picked =
        saved.where((p) => _selected.contains(p.id)).toList(growable: false);
    if (picked.length >= 2) return picked.take(CompareScreen.maxColumns).toList();
    return const [];
  }

  void _toggle(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else if (_selected.length < CompareScreen.maxColumns) {
        _selected.add(id);
      }
    });
  }
}

/// Horizontal chips to pick up to 3 properties when more than 3 are saved.
class _Selector extends StatelessWidget {
  const _Selector({
    required this.saved,
    required this.selected,
    required this.onToggle,
  });

  final List<RentalProperty> saved;
  final Set<String> selected;
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
            'בחרו עד 3 דירות להשוואה (${selected.length}/${CompareScreen.maxColumns})',
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
                for (final p in saved)
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
    final where = p.neighborhood.trim().isNotEmpty
        ? p.neighborhood.trim()
        : p.city.trim();
    return '$where · ${p.priceLabel}';
  }
}

/// The actual side-by-side table. Numeric rows highlight the best value per row
/// (cheapest, biggest, best ₪/m², highest match); amenity rows show ✓/✗.
class _CompareTable extends StatelessWidget {
  const _CompareTable({required this.properties, required this.provider});

  final List<RentalProperty> properties;
  final DatingProvider provider;

  @override
  Widget build(BuildContext context) {
    final rows = <_CompareRow>[
      _CompareRow.number('מחיר', (p) => p.price > 0 ? p.price.toDouble() : null,
          (p) => p.priceLabel,
          best: _Best.min),
      _CompareRow.number('₪ למ"ר', _perM2, _perM2Label, best: _Best.min),
      _CompareRow.text('חדרים', (p) => p.roomsLabel),
      _CompareRow.number(
          'שטח', (p) => p.sizeM2 > 0 ? p.sizeM2.toDouble() : null,
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
          (p) => (provider.displayMatchScore(p) ?? -1).toDouble(),
          (p) {
        final s = provider.displayMatchScore(p);
        return s == null ? '—' : '$s%';
      }, best: _Best.max),
    ];

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: Column(
            children: [
              _HeaderRow(properties: properties),
              for (var i = 0; i < rows.length; i++)
                _DataRow(
                  row: rows[i],
                  properties: properties,
                  shaded: i.isEven,
                ),
            ],
          ),
        ),
      ),
    );
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

enum _Best { none, min, max }

class _CompareRow {
  const _CompareRow._(this.label, this.display, this.numeric, this.flag,
      this.best);
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
  const _HeaderRow({required this.properties});
  final List<RentalProperty> properties;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryLight2,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _LabelCell(''),
          for (final p in properties)
            Expanded(
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PropertyDetailScreen(property: p),
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _title(RentalProperty p) {
    final where = p.neighborhood.trim().isNotEmpty
        ? p.neighborhood.trim()
        : p.city.trim();
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
    // Which column(s) hold the best numeric value for this row?
    final winners = <int>{};
    if (row.numeric != null && row.best != _Best.none) {
      final vals = [for (final p in properties) row.numeric!(p)];
      double? bestVal;
      for (final v in vals) {
        if (v == null) continue;
        if (bestVal == null ||
            (row.best == _Best.min ? v < bestVal : v > bestVal)) {
          bestVal = v;
        }
      }
      if (bestVal != null) {
        for (var i = 0; i < vals.length; i++) {
          if (vals[i] == bestVal) winners.add(i);
        }
      }
    }

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

  Widget _cell(RentalProperty p, bool isWinner) {
    if (row.flag != null) {
      final on = row.flag!(p);
      return Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        child: Icon(
          on ? Icons.check_circle_rounded : Icons.remove_circle_outline_rounded,
          color: on ? AppColors.success : AppColors.textDisabled,
          size: 22,
        ),
      );
    }
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      color: isWinner ? AppColors.primary.withValues(alpha: 0.10) : null,
      child: Text(
        row.display(p),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 17,
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
      width: 88,
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
            Icon(
              Icons.compare_arrows_rounded,
              size: 64,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                height: 1.4,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
