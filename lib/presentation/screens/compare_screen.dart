import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
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

/// The actual side-by-side table.
class _CompareTable extends StatelessWidget {
  const _CompareTable({required this.properties, required this.provider});

  final List<RentalProperty> properties;
  final DatingProvider provider;

  @override
  Widget build(BuildContext context) {
    final rows = <_CompareRow>[
      _CompareRow('מחיר', (p) => p.priceLabel),
      _CompareRow('₪ למ"ר', _pricePerM2),
      _CompareRow('חדרים', (p) => p.roomsLabel),
      _CompareRow('שטח', (p) => p.sizeM2 > 0 ? '${p.sizeM2} מ"ר' : '—'),
      _CompareRow('קומה', _floorLabel),
      _CompareRow('התאמה', (p) => _matchLabel(p)),
    ];

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Container(
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

  String _matchLabel(RentalProperty p) {
    final score = provider.displayMatchScore(p);
    return score == null ? '—' : '$score%';
  }

  static String _pricePerM2(RentalProperty p) {
    if (p.sizeM2 <= 0 || p.price <= 0) return '—';
    final perM2 = (p.price / p.sizeM2).round();
    return '₪$perM2';
  }

  static String _floorLabel(RentalProperty p) {
    final floor = p.floor.trim();
    if (floor.isEmpty) return '—';
    final total = p.totalFloors.trim();
    return total.isEmpty ? floor : '$floor/$total';
  }
}

class _CompareRow {
  const _CompareRow(this.label, this.value);
  final String label;
  final String Function(RentalProperty) value;
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.properties});
  final List<RentalProperty> properties;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primaryLight2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          const _LabelCell(''),
          for (final p in properties)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 6,
                ),
                child: Text(
                  _title(p),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
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
    return Container(
      color: shaded ? AppColors.background : AppColors.surface,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _LabelCell(row.label),
            for (final p in properties)
              Expanded(
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 6,
                  ),
                  child: Text(
                    row.value(p),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
          ],
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
