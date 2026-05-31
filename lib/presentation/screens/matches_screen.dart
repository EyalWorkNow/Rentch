import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/message_screen.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

// ─── Filter chip descriptors ──────────────────────────────────────────────────

const _kFilterAll = 'all';
const _kFilterNew = 'new';
const _kFilterOld = 'old';
const _kFilterTomorrow = 'tomorrow';

const _kAgeFilterLabels = <String, String>{
  _kFilterAll: 'הכל',
  _kFilterNew: 'חדש',
  _kFilterOld: 'ישן',
};

const _kScheduleFilterLabels = <String, String>{
  _kFilterAll: 'הכל',
  _kFilterTomorrow: 'מחר',
};

const _kNewMatchWindow = Duration(days: 7);

DateTime _lastActivity(RentalMatch match) {
  if (match.messages.isEmpty) return match.createdAt;
  return match.messages.last.createdAt;
}

// ─── MatchesScreen ────────────────────────────────────────────────────────────

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  String _query = '';
  String _ageFilter = _kFilterAll;
  String _scheduleFilter = _kFilterAll;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Builds filtered pairs of (match, property) from the full match list.
  List<({RentalMatch match, RentalProperty property})> _applyFilters(
    List<RentalMatch> matches,
    DatingProvider provider,
  ) {
    final pairs = matches
        .map((m) {
          final p = provider.propertyById(m.propertyId);
          if (p == null) return null;
          return (match: m, property: p);
        })
        .whereType<({RentalMatch match, RentalProperty property})>()
        .toList();

    final q = _query.trim().toLowerCase();
    final afterSearch = q.isEmpty
        ? pairs
        : pairs.where((pair) {
            final prop = pair.property;
            return prop.address.toLowerCase().contains(q) ||
                prop.city.toLowerCase().contains(q) ||
                prop.neighborhood.toLowerCase().contains(q) ||
                pair.match.messages.any(
                  (message) => message.text.toLowerCase().contains(q),
                );
          }).toList();

    final now = DateTime.now();
    List<({RentalMatch match, RentalProperty property})> filtered;
    switch (_ageFilter) {
      case _kFilterNew:
        filtered = afterSearch
            .where((pair) =>
                now.difference(pair.match.createdAt) <= _kNewMatchWindow)
            .toList();
        break;
      case _kFilterOld:
        filtered = afterSearch
            .where((pair) =>
                now.difference(pair.match.createdAt) > _kNewMatchWindow)
            .toList();
        break;
      default:
        filtered = afterSearch;
    }

    if (_scheduleFilter == _kFilterTomorrow) {
      filtered = filtered
          .where((pair) => pair.match.messages.any(
                (message) => message.text.contains('מחר'),
              ))
          .toList();
    }

    filtered.sort(
      (a, b) => _lastActivity(b.match).compareTo(_lastActivity(a.match)),
    );
    return filtered;
  }

  bool get _isFiltering =>
      _query.trim().isNotEmpty ||
      _ageFilter != _kFilterAll ||
      _scheduleFilter != _kFilterAll;

  void _clearFilters() {
    setState(() {
      _query = '';
      _ageFilter = _kFilterAll;
      _scheduleFilter = _kFilterAll;
      _searchCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final allMatches = provider.matches;
        final filtered = _applyFilters(allMatches, provider);
        final total = allMatches
            .where((m) => provider.propertyById(m.propertyId) != null)
            .length;

        final subtitleText = _isFiltering
            ? '${filtered.length} מתוך $total דירות'
            : '$total שיחות פעילות';

        return Scaffold(
          backgroundColor: const Color(0xFFF2F7FA),
          appBar: AppBar(
            backgroundColor: AppColors.navy,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: true,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'התאמות',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (allMatches.isNotEmpty)
                  Text(
                    subtitleText,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
          body: provider.isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary))
              : allMatches.isEmpty
                  ? const _EmptyMatches()
                  : Column(
                      children: [
                        _MatchesToolbar(
                          controller: _searchCtrl,
                          query: _query,
                          ageFilter: _ageFilter,
                          scheduleFilter: _scheduleFilter,
                          onQueryChanged: (value) =>
                              setState(() => _query = value),
                          onClearQuery: () => setState(() {
                            _query = '';
                            _searchCtrl.clear();
                          }),
                          onAgeFilterChanged: (value) =>
                              setState(() => _ageFilter = value),
                          onScheduleFilterChanged: (value) =>
                              setState(() => _scheduleFilter = value),
                        ),
                        Expanded(
                          child: filtered.isEmpty
                              ? _EmptyFilterResults(onClear: _clearFilters)
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 12, 16, 120),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 14),
                                  itemBuilder: (context, index) {
                                    final pair = filtered[index];
                                    return _MatchCard(
                                      match: pair.match,
                                      property: pair.property,
                                      onTap: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => MessageScreen(
                                              matchId: pair.match.id),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
        );
      },
    );
  }
}

class _MatchesToolbar extends StatelessWidget {
  const _MatchesToolbar({
    required this.controller,
    required this.query,
    required this.ageFilter,
    required this.scheduleFilter,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onAgeFilterChanged,
    required this.onScheduleFilterChanged,
  });

  final TextEditingController controller;
  final String query;
  final String ageFilter;
  final String scheduleFilter;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final ValueChanged<String> onAgeFilterChanged;
  final ValueChanged<String> onScheduleFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2ECF1)),
        boxShadow: [
          BoxShadow(
            color: AppColors.navy.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFF5FAFD),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2ECF1)),
            ),
            child: TextField(
              controller: controller,
              textDirection: TextDirection.rtl,
              onChanged: onQueryChanged,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.navy,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: 'חיפוש כתובת, עיר או הודעה...',
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w600,
                ),
                prefixIcon: const Icon(
                  IconsaxPlusBold.search_normal,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                suffixIcon: query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          IconsaxPlusBold.close_circle,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                        onPressed: onClearQuery,
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Padding(
                padding: EdgeInsetsDirectional.only(end: 10),
                child: Text(
                  'Sort by',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                child: _FilterDropdown(
                  label: 'סטטוס',
                  value: ageFilter,
                  items: _kAgeFilterLabels,
                  onChanged: onAgeFilterChanged,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _FilterDropdown(
                  label: 'תיאום',
                  value: scheduleFilter,
                  items: _kScheduleFilterLabels,
                  onChanged: onScheduleFilterChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsetsDirectional.only(start: 12, end: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5FAFD),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2ECF1)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(18),
          icon: const Icon(
            IconsaxPlusBold.arrow_down_1,
            size: 16,
            color: AppColors.textSecondary,
          ),
          style: const TextStyle(
            color: AppColors.navy,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
          dropdownColor: Colors.white,
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
          selectedItemBuilder: (context) {
            return items.entries
                .map(
                  (entry) => Align(
                    alignment: Alignment.centerRight,
                    child: RichText(
                      textDirection: TextDirection.rtl,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '$label: ',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          TextSpan(
                            text: entry.value,
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList();
          },
          items: items.entries
              .map(
                (entry) => DropdownMenuItem<String>(
                  value: entry.key,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      entry.value,
                      textDirection: TextDirection.rtl,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

// ─── Empty filter results ─────────────────────────────────────────────────────

class _EmptyFilterResults extends StatelessWidget {
  const _EmptyFilterResults({required this.onClear});
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                IconsaxPlusBold.search_normal,
                color: AppColors.primary,
                size: 36,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'לא נמצאו תוצאות',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'לא נמצאו תוצאות עבור החיפוש הזה — נסה לשנות את הסינון.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(IconsaxPlusBold.close_circle, size: 16),
              label: const Text('נקה סינון'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Match card ───────────────────────────────────────────────────────────────

class _MatchCard extends StatelessWidget {
  const _MatchCard({
    required this.match,
    required this.property,
    required this.onTap,
  });

  final RentalMatch match;
  final RentalProperty property;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final media = property.primaryMedia;
    final lastMessage = match.messages.isEmpty ? null : match.messages.last;
    final stage = _matchStage(match);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: const Color(0xFFE2ECF1), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: const Color(0xFFE2ECF1),
                        width: 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(21),
                      child: SafeMedia(
                        media: media,
                        fallback: Container(
                          color: AppColors.primaryLight2,
                          child: const Icon(
                            IconsaxPlusBold.building,
                            color: AppColors.primary,
                            size: 30,
                          ),
                        ),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                property.address,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.navy,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _FreshnessBadge(match: match),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _MetaChip(
                              icon: IconsaxPlusBold.money,
                              label: property.priceLabel,
                            ),
                            _MetaChip(
                              icon: IconsaxPlusBold.home,
                              label: '${property.roomsLabel} חדרים',
                            ),
                            _MetaChip(
                              icon: IconsaxPlusBold.location,
                              label: property.city,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _LastMessagePreview(message: lastMessage),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FCFE),
                border: Border(
                  top: BorderSide(color: Color(0xFFE2ECF1), width: 1),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _StatusChip(
                          label: stage.label,
                          color: stage.color,
                          icon: stage.icon,
                        ),
                        if (match.ownerSigned)
                          const _StatusChip(
                            label: 'בעלים חתם',
                            color: Color(0xFF27AE60),
                            icon: IconsaxPlusBold.pen_tool,
                          ),
                        if (match.tenantSigned)
                          const _StatusChip(
                            label: 'שוכר חתם',
                            color: Color(0xFF27AE60),
                            icon: IconsaxPlusBold.edit,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'פתח שיחה',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary,
                          ),
                        ),
                        SizedBox(width: 6),
                        Icon(
                          IconsaxPlusBold.arrow_left,
                          size: 14,
                          color: AppColors.primary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  ({String label, Color color, IconData icon}) _matchStage(RentalMatch match) {
    if (match.ownerSigned && match.tenantSigned) {
      return (
        label: 'חתום',
        color: const Color(0xFF27AE60),
        icon: IconsaxPlusBold.tick_circle,
      );
    }
    if (match.contractSent) {
      return (
        label: 'חוזה נשלח',
        color: const Color(0xFF27AE60),
        icon: IconsaxPlusBold.document_text,
      );
    }
    return (
      label: 'שיחה פתוחה',
      color: AppColors.primary,
      icon: IconsaxPlusBold.message,
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F7FA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _FreshnessBadge extends StatelessWidget {
  const _FreshnessBadge({required this.match});

  final RentalMatch match;

  @override
  Widget build(BuildContext context) {
    final isNew =
        DateTime.now().difference(match.createdAt) <= _kNewMatchWindow;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: (isNew ? AppColors.primary : AppColors.textSecondary)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isNew ? 'חדש' : 'ישן',
        style: TextStyle(
          color: isNew ? AppColors.primary : AppColors.textSecondary,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _LastMessagePreview extends StatelessWidget {
  const _LastMessagePreview({required this.message});

  final ChatMessage? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FCFE),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2ECF1)),
      ),
      child: Row(
        children: [
          const Icon(
            IconsaxPlusBold.message,
            size: 14,
            color: AppColors.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message?.text ?? 'שיחה חדשה מוכנה לפתיחה',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.35,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Status chip ──────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.18), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty matches (no matches at all) ───────────────────────────────────────

class _EmptyMatches extends StatelessWidget {
  const _EmptyMatches();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                IconsaxPlusBold.heart_tick,
                color: AppColors.primary,
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'עוד אין התאמות',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'כשתאהב דירה ובעל הדירה יאשר אותך — ההתאמה תופיע כאן.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.55,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
