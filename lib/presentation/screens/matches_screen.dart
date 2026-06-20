import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/message_screen.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:dating_app/presentation/widgets/property_share_sheet.dart';
import 'package:dating_app/presentation/widgets/scale_bounce.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';
import 'package:provider/provider.dart';
import 'package:dating_app/presentation/widgets/animations/micro_animations.dart';

String _relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 60) return 'לפני ${diff.inMinutes} דק׳';
  if (diff.inHours < 24) return 'לפני ${diff.inHours} שע׳';
  if (diff.inDays == 1) return 'אתמול';
  if (diff.inDays < 7) return 'לפני ${diff.inDays} ימים';
  if (diff.inDays < 14) return 'לפני שבוע';
  return 'לפני ${(diff.inDays / 7).round()} שבועות';
}

// ─── Filter chip descriptors ──────────────────────────────────────────────────

const _kFilterAll = 'all';
const _kFilterNew = 'new';
const _kFilterOld = 'old';
const _kFilterTomorrow = 'tomorrow';

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
  bool _showFilters = true;
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
          body: SafeArea(
            bottom: false,
            child: provider.isLoading
                ? Center(
                    child: CircularProgressIndicator(color: AppColors.primary))
                : allMatches.isEmpty
                    ? _EmptyMatches(isLandlord: provider.isLandlord)
                    : Column(
                        children: [
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(20, 14, 20, 0),
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                subtitleText,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          _MatchesToolbar(
                            controller: _searchCtrl,
                            query: _query,
                            ageFilter: _ageFilter,
                            scheduleFilter: _scheduleFilter,
                            showFilters: _showFilters,
                            onFilterTap: () =>
                                setState(() => _showFilters = !_showFilters),
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
    required this.showFilters,
    required this.onFilterTap,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onAgeFilterChanged,
    required this.onScheduleFilterChanged,
  });

  final TextEditingController controller;
  final String query;
  final String ageFilter;
  final String scheduleFilter;
  final bool showFilters;
  final VoidCallback onFilterTap;
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
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0xFFE2ECF1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: [
                const SizedBox(width: 10),
                const RentlyIcon(
                  IconsaxPlusLinear.search_normal,
                  size: 18,
                  color: Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
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
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                AnimatedScale(
                  duration: const Duration(milliseconds: 200),
                  scale: query.isNotEmpty ? 1.0 : 0.0,
                  curve: Curves.easeOutBack,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: query.isNotEmpty ? 1.0 : 0.0,
                    child: ScaleBounce(
                      onTap: onClearQuery,
                      scaleDownTo: 0.82,
                      child: const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: RentlyIcon(
                          IconsaxPlusLinear.close_circle,
                          size: 18,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                ScaleBounce(
                  onTap: onFilterTap,
                  scaleDownTo: 0.88,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: showFilters
                          ? AppColors.navy
                          : const Color(0xFFF2F4F5),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: AnimatedRotation(
                        turns: showFilters ? 0.125 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutBack,
                        child: RentlyIcon(
                          IconsaxPlusLinear.setting_4,
                          size: 18,
                          color: showFilters ? Colors.white : AppColors.navy,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    _FilterPill(
                      label: 'הכל',
                      isSelected: ageFilter == _kFilterAll &&
                          scheduleFilter == _kFilterAll,
                      onTap: () {
                        onAgeFilterChanged(_kFilterAll);
                        onScheduleFilterChanged(_kFilterAll);
                      },
                    ),
                    const SizedBox(width: 8),
                    _FilterPill(
                      label: 'חדש',
                      isSelected: ageFilter == _kFilterNew,
                      onTap: () {
                        onAgeFilterChanged(_kFilterNew);
                      },
                    ),
                    const SizedBox(width: 8),
                    _FilterPill(
                      label: 'ישן',
                      isSelected: ageFilter == _kFilterOld,
                      onTap: () {
                        onAgeFilterChanged(_kFilterOld);
                      },
                    ),
                    const SizedBox(width: 8),
                    _FilterPill(
                      label: 'תואם למחר',
                      isSelected: scheduleFilter == _kFilterTomorrow,
                      onTap: () {
                        onScheduleFilterChanged(
                          scheduleFilter == _kFilterTomorrow
                              ? _kFilterAll
                              : _kFilterTomorrow,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            crossFadeState: showFilters
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChipAnimated(
      isSelected: isSelected,
      onTap: onTap,
      activeColor: AppColors.navy,
      inactiveColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.navy,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
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
              child: RentlyIcon(
                IconsaxPlusLinear.search_normal,
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
              icon: const RentlyIcon(IconsaxPlusLinear.close_circle, size: 16),
              label: const Text('נקה סינון'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary),
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

class _MatchCard extends StatefulWidget {
  const _MatchCard({
    required this.match,
    required this.property,
    required this.onTap,
  });

  final RentalMatch match;
  final RentalProperty property;
  final VoidCallback onTap;

  @override
  State<_MatchCard> createState() => _MatchCardState();
}

class _MatchCardState extends State<_MatchCard> {
  bool _isExpanded = false;

  ({String label, Color color, IconData icon}) _matchStage(RentalMatch match) {
    if (match.ownerSigned && match.tenantSigned) {
      return (
        label: 'חתום',
        color: const Color(0xFF27AE60),
        icon: IconsaxPlusLinear.tick_circle,
      );
    }
    if (match.contractSent) {
      return (
        label: 'חוזה נשלח',
        color: const Color(0xFF27AE60),
        icon: IconsaxPlusLinear.document_text,
      );
    }
    return (
      label: 'שיחה פתוחה',
      color: AppColors.primary,
      icon: IconsaxPlusLinear.message,
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = widget.property.primaryMedia;
    final lastMessage =
        widget.match.messages.isEmpty ? null : widget.match.messages.last;
    final stage = _matchStage(widget.match);
    final provider = context.read<DatingProvider>();
    final isLandlord = provider.isLandlord;
    final tenantName = provider.tenantProfile?.name ?? '';
    final awaitingReply = isLandlord &&
        lastMessage != null &&
        tenantName.isNotEmpty &&
        lastMessage.sender == tenantName;

    return ScaleBounce(
      onTap: widget.onTap,
      scaleDownTo: 0.97,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFE2ECF1), width: 1),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.05),
              blurRadius: 20,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(5),
              child: AspectRatio(
                aspectRatio: 1.84,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      SafeMedia(
                        media: media,
                        fallback: Container(
                          color: AppColors.primaryLight2,
                          child: RentlyIcon(
                            IconsaxPlusLinear.building,
                            color: AppColors.primary,
                            size: 48,
                          ),
                        ),
                        fit: BoxFit.cover,
                      ),
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            widget.property.propertyType,
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: _FreshnessBadge(match: widget.match),
                        ),
                      ),
                      Positioned(
                        bottom: 10,
                        left: 10,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: const RentlyIcon(
                              IconsaxPlusLinear.send_2,
                              color: AppColors.navy,
                              size: 16,
                            ),
                            onPressed: () {
                              showPropertyShareSheet(context, widget.property);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const OnlineDotPulse(size: 8),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    widget.property.street.isNotEmpty
                                        ? '${widget.property.street} ${widget.property.streetNumber}'
                                        : widget.property.address,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.navy,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${widget.property.city}, ${widget.property.neighborhood}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        widget.property.priceLabel,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _MockupChip(
                          icon: IconsaxPlusLinear.home,
                          label: '${widget.property.roomsLabel} חדרים',
                        ),
                        const SizedBox(width: 8),
                        _MockupChip(
                          icon: IconsaxPlusLinear.maximize_3,
                          label: '${widget.property.sizeM2} מ״ר',
                        ),
                        const SizedBox(width: 8),
                        _MockupChip(
                          icon: IconsaxPlusLinear.routing,
                          label: widget.property.features.firstOrNull ??
                              'מעלית',
                        ),
                        const SizedBox(width: 8),
                        _MockupChip(
                          icon: IconsaxPlusLinear.wind,
                          label: widget.property.features.length > 1
                              ? widget.property.features[1]
                              : 'ממוזגת',
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
}

class _MockupChip extends StatelessWidget {
  const _MockupChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F7FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: AppColors.navy,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
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
    final lastActivity = match.messages.isNotEmpty
        ? match.messages.last.createdAt
        : match.createdAt;
    final isNew =
        DateTime.now().difference(match.createdAt) <= _kNewMatchWindow;
    final timeLabel = _relativeTime(lastActivity);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: (isNew ? AppColors.primary : AppColors.textSecondary)
            .withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        isNew && match.messages.isEmpty ? 'חדש' : timeLabel,
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
          RentlyIcon(
            IconsaxPlusLinear.message,
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
  const _EmptyMatches({required this.isLandlord});
  final bool isLandlord;

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
              child: RentlyIcon(
                IconsaxPlusLinear.heart_tick,
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
            Text(
              isLandlord
                  ? 'כשתאשר שוכרים מועמדים בסוויפים — ההתאמות יופיעו כאן.'
                  : 'כשתאהב דירה ובעל הדירה יאשר אותך — ההתאמה תופיע כאן.',
              textAlign: TextAlign.center,
              style: const TextStyle(
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
