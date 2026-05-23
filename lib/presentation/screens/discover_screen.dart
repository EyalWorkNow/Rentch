import 'dart:async';
import 'dart:math' as math;

import 'package:dating_app/core/constants/app_colors.dart';

import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/features/discover/action_button.dart';
import 'package:dating_app/presentation/features/discover/profile_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final pendingMatch = provider.pendingMatchProperty;
        if (pendingMatch != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!context.mounted) return;
            _showMatchDialog(context, pendingMatch);
            provider.clearPendingMatch();
          });
        }

        final properties = provider.filteredProperties;

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: AppColors.background,
            title: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    IconsaxPlusBold.building,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Rentch',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'סינון',
                onPressed: provider.isLoading
                    ? null
                    : () => _showFilters(context, provider),
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(IconsaxPlusLinear.setting_4,
                        color: AppColors.navy),
                    if (provider.activeFilterCount > 0)
                      Positioned(
                        top: -7,
                        right: -9,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            borderRadius:
                                BorderRadius.all(Radius.circular(999)),
                          ),
                          child: Text(
                            '${provider.activeFilterCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: provider.isLoading
              ? const _SkeletonDiscoverView()
              : SafeArea(
                  child: Column(
                    children: [
                      _FilterPills(provider: provider),
                      Expanded(
                        child: Stack(
                          children: [
                            properties.isNotEmpty
                                ? CardSwiper(
                                    key: ValueKey(
                                      properties.map((p) => p.id).join('-'),
                                    ),
                                    controller:
                                        provider.propertySwiperController,
                                    cardsCount: properties.length,
                                    padding:
                                        const EdgeInsets.fromLTRB(10, 0, 10, 0),
                                    scale: 0.93,
                                    threshold: 38,
                                    maxAngle: 16,
                                    isLoop: false,
                                    numberOfCardsDisplayed:
                                        math.min(3, properties.length),
                                    backCardOffset: const Offset(0, 20),
                                    allowedSwipeDirection:
                                        const AllowedSwipeDirection.only(
                                      left: true,
                                      right: true,
                                      up: true,
                                    ),
                                    onSwipe: provider.handlePropertySwipe,
                                    cardBuilder: (
                                      context,
                                      index,
                                      horizontalOffsetPercentage,
                                      verticalOffsetPercentage,
                                    ) {
                                      return ProfileCard(
                                        property: properties[index],
                                        horizontalOffsetPercentage:
                                            horizontalOffsetPercentage,
                                      );
                                    },
                                  )
                                : const _NoMorePropertiesState(),
                            // Undo floating button — top-left of card stack
                            if (provider.canUndo)
                              Positioned(
                                top: 14,
                                left: 20,
                                child: _UndoButton(onTap: provider.undoSwipe),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 4, 0, 16),
                        child: ActionButtons(
                          onSwipeLeft: provider.swipePropertyLeft,
                          onSwipeRight: provider.swipePropertyRight,
                          onSuperLike: provider.superLikeProperty,
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Future<void> _showFilters(
    BuildContext context,
    DatingProvider provider,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FiltersSheet(provider: provider),
    );
  }

  void _showMatchDialog(BuildContext context, RentalProperty property) {
    HapticFeedback.heavyImpact();
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.transparent,
        pageBuilder: (_, __, ___) =>
            _MatchCelebrationOverlay(property: property),
      ),
    );
  }
}

class _FilterPills extends StatelessWidget {
  const _FilterPills({required this.provider});
  final DatingProvider provider;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          if (provider.filters.hasQuery) ...[
            _Pill(
              icon: IconsaxPlusLinear.search_normal,
              label: provider.filters.query,
              onTap: () => _showFilters(context, provider),
              highlighted: true,
            ),
            const SizedBox(width: 8),
          ],
          _Pill(
            icon: IconsaxPlusLinear.location,
            label: provider.selectedArea.name,
            onTap: () => _showFilters(context, provider),
          ),
          const SizedBox(width: 8),
          _Pill(
            icon: IconsaxPlusLinear.money,
            label: 'עד ${_formatCurrency(provider.filters.maxBudget)}',
            onTap: () => _showFilters(context, provider),
          ),
          const SizedBox(width: 8),
          _Pill(
            icon: IconsaxPlusLinear.home,
            label: 'מינ. ${provider.filters.minRooms.toStringAsFixed(0)} חדרים',
            onTap: () => _showFilters(context, provider),
          ),
          const SizedBox(width: 8),
          _Pill(
            icon: IconsaxPlusLinear.maximize_4,
            label:
                '${provider.filters.minSizeM2}-${provider.filters.maxSizeM2} מ"ר',
            onTap: () => _showFilters(context, provider),
          ),
          if (provider.activeFilterCount > 0) ...[
            const SizedBox(width: 8),
            _Pill(
              icon: IconsaxPlusBold.filter,
              label: '${provider.activeFilterCount} מסננים פעילים',
              onTap: () => _showFilters(context, provider),
              highlighted: true,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showFilters(
      BuildContext context, DatingProvider provider) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FiltersSheet(provider: provider),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: highlighted
              ? AppColors.primary.withValues(alpha: 0.12)
              : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: highlighted ? AppColors.primary : AppColors.borderLight,
          ),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: highlighted ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: highlighted ? AppColors.primary : AppColors.navy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchCommandBar extends StatefulWidget {
  const _SearchCommandBar({required this.provider});

  final DatingProvider provider;

  @override
  State<_SearchCommandBar> createState() => _SearchCommandBarState();
}

class _SearchCommandBarState extends State<_SearchCommandBar> {
  late final TextEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.provider.filters.query);
  }

  @override
  void didUpdateWidget(covariant _SearchCommandBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final query = widget.provider.filters.query;
    if (query != _controller.text) {
      _controller.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _scheduleQueryUpdate(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      widget.provider
          .updateFilters(widget.provider.filters.copyWith(query: value));
    });
  }

  @override
  Widget build(BuildContext context) {
    final filters = widget.provider.filters;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        children: [
          TextField(
            controller: _controller,
            textDirection: TextDirection.rtl,
            onChanged: _scheduleQueryUpdate,
            decoration: InputDecoration(
              hintText: 'חפש לפי עיר, רחוב, שכונה, סוג נכס או מאפיין',
              prefixIcon: const Icon(IconsaxPlusLinear.search_normal),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  PopupMenuButton<SearchSortOption>(
                    tooltip: 'מיון',
                    initialValue: filters.sortBy,
                    onSelected: (sortBy) {
                      widget.provider
                          .updateFilters(filters.copyWith(sortBy: sortBy));
                    },
                    itemBuilder: (context) => SearchSortOption.values
                        .map(
                          (option) => PopupMenuItem(
                            value: option,
                            child: Text(_sortLabel(option)),
                          ),
                        )
                        .toList(),
                    icon: const Icon(IconsaxPlusLinear.sort),
                  ),
                  if (_controller.text.isNotEmpty)
                    IconButton(
                      tooltip: 'נקה חיפוש',
                      onPressed: () {
                        _controller.clear();
                        widget.provider
                            .updateFilters(filters.copyWith(query: ''));
                      },
                      icon: const Icon(IconsaxPlusLinear.close_circle),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _QuickToggleChip(
                  label: 'כניסה מיידית',
                  selected: filters.moveInFilter == MoveInFilter.immediate,
                  onTap: () => widget.provider.updateFilters(
                    filters.copyWith(
                      moveInFilter:
                          filters.moveInFilter == MoveInFilter.immediate
                              ? MoveInFilter.any
                              : MoveInFilter.immediate,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _QuickToggleChip(
                  label: 'בעלים פרטיים',
                  selected:
                      filters.listingSource == ListingSourceFilter.privateOnly,
                  onTap: () => widget.provider.updateFilters(
                    filters.copyWith(
                      listingSource: filters.listingSource ==
                              ListingSourceFilter.privateOnly
                          ? ListingSourceFilter.any
                          : ListingSourceFilter.privateOnly,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _QuickToggleChip(
                  label: '80+ מ"ר',
                  selected: filters.minSizeM2 >= 80,
                  onTap: () => widget.provider.updateFilters(
                    filters.copyWith(
                        minSizeM2: filters.minSizeM2 >= 80 ? 0 : 80),
                  ),
                ),
                const SizedBox(width: 8),
                _QuickToggleChip(
                  label: _sortLabel(filters.sortBy),
                  selected: filters.sortBy != SearchSortOption.bestMatch,
                  onTap: () => _showSortPicker(context, filters),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSortPicker(
      BuildContext context, SearchFilters filters) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'מיין את הדק',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 12),
                ...SearchSortOption.values.map(
                  (option) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_sortLabel(option)),
                    trailing: filters.sortBy == option
                        ? const Icon(IconsaxPlusBold.tick_circle,
                            color: AppColors.primary)
                        : null,
                    onTap: () async {
                      await widget.provider
                          .updateFilters(filters.copyWith(sortBy: option));
                      if (context.mounted) Navigator.of(context).pop();
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

class _QuickToggleChip extends StatelessWidget {
  const _QuickToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderLight,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.navy,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _ResultsInsightBar extends StatelessWidget {
  const _ResultsInsightBar({required this.provider});

  final DatingProvider provider;

  @override
  Widget build(BuildContext context) {
    final count = provider.filteredProperties.length;
    final avgPrice = provider.averageFilteredPrice;
    final avgSize = provider.averageFilteredSize;
    final leadText = count == 0
        ? 'כרגע אין התאמות. נסה להרחיב את החיפוש או לשנות קצב.'
        : count == 1
            ? 'נשארה התאמה אחת מדויקת לחיפוש שלך.'
            : 'יש כרגע $count דירות שמתאימות להגדרות שלך.';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFF7FFFE), Color(0xFFEAF7FF)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              leadText,
              style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _MiniMetric(
                  label: 'מחיר ממוצע',
                  value: count == 0 ? '-' : _formatCurrency(avgPrice.round()),
                ),
                const SizedBox(width: 8),
                _MiniMetric(
                  label: 'גודל ממוצע',
                  value: count == 0 ? '-' : '${avgSize.round()} מ"ר',
                ),
                const SizedBox(width: 8),
                _MiniMetric(
                  label: 'מיון',
                  value: _sortLabel(provider.filters.sortBy),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.88),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: AppColors.navy,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchCelebrationOverlay extends StatefulWidget {
  const _MatchCelebrationOverlay({required this.property});
  final RentalProperty property;

  @override
  State<_MatchCelebrationOverlay> createState() =>
      _MatchCelebrationOverlayState();
}

class _MatchCelebrationOverlayState extends State<_MatchCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.property;
    final imgUrl = p.imageUrls.isNotEmpty ? p.imageUrls.first : '';

    return Material(
      color: Colors.black.withValues(alpha: 0.88),
      child: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ScaleTransition(
                scale: _scale,
                child: Column(
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primary, width: 3),
                      ),
                      child: const Icon(
                        IconsaxPlusBold.heart,
                        color: AppColors.primary,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'זה מאצ׳!',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'נוצרה התאמה עם\n${p.address}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              if (imgUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    width: 220,
                    height: 150,
                    child: Image.network(
                      imgUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.navy,
                        child: const Center(
                          child: Icon(IconsaxPlusBold.building,
                              color: Colors.white30, size: 40),
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 36),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(IconsaxPlusBold.message),
                        label: const Text('פתח צ׳אט'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('המשך לחפש'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Filters Sheet ────────────────────────────────────────────────────────────

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({required this.provider});
  final DatingProvider provider;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late final TextEditingController _areaSearchCtrl;
  late final FocusNode _areaSearchFocusNode;
  bool _showAreaSearch = false;

  @override
  void initState() {
    super.initState();
    _areaSearchCtrl = TextEditingController();
    _areaSearchFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _areaSearchCtrl.dispose();
    _areaSearchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final f = provider.filters;
        final area = provider.searchAreas.firstWhere(
          (item) => item.id == f.areaId,
          orElse: () => provider.selectedArea,
        );

        final filteredSearchAreas = provider.searchAreas.where((searchArea) {
          final query = _areaSearchCtrl.text.trim().toLowerCase();
          return searchArea.name.toLowerCase().contains(query);
        }).toList();

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.92,
          ),
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              // Handle
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Text(
                      'סינון דירות',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: AppColors.navy,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _areaSearchCtrl.clear();
                          _showAreaSearch = false;
                          _areaSearchFocusNode.unfocus();
                        });
                        provider.updateFilters(const SearchFilters(
                          query: '',
                          maxBudget: 9000,
                          minRooms: 2,
                          areaId: 'gush_dan',
                          requiredFeatures: <String>{},
                          minSizeM2: 0,
                          maxSizeM2: 400,
                          propertyTypes: <String>{},
                          conditions: <String>{},
                          listingSource: ListingSourceFilter.any,
                          minFloor: 0,
                          moveInFilter: MoveInFilter.any,
                          sortBy: SearchSortOption.bestMatch,
                        ));
                      },
                      child: const Text(
                        'אפס הכל',
                        style: TextStyle(
                          color: AppColors.coral,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Scrollable content
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                  children: [
                    _SearchCommandBar(provider: provider),
                    _ResultsInsightBar(provider: provider),
                    const SizedBox(height: 8),
                    // Mini map
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: SizedBox(
                        height: 190,
                        child: FlutterMap(
                          options: MapOptions(
                            initialCenter: area.center,
                            initialZoom: 11,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.none,
                            ),
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.rentch.app',
                            ),
                            PolygonLayer(
                              polygons: [
                                Polygon(
                                  points: area.polygon,
                                  color: AppColors.primary.withValues(alpha: 0.2),
                                  borderColor: AppColors.primary,
                                  borderStrokeWidth: 3,
                                ),
                              ],
                            ),
                            MarkerLayer(
                              markers: provider.filteredProperties
                                  .take(18)
                                  .map((property) {
                                return Marker(
                                  point: property.point,
                                  width: 28,
                                  height: 28,
                                  child: const Icon(
                                    IconsaxPlusBold.building,
                                    color: AppColors.primary,
                                    size: 22,
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    _FilterSection(
                      title: 'אזור חיפוש',
                      icon: IconsaxPlusLinear.location,
                      action: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          _showAreaSearch
                              ? IconsaxPlusLinear.close_square
                              : IconsaxPlusLinear.search_normal_1,
                          size: 20,
                          color: AppColors.primary,
                        ),
                        onPressed: () {
                          setState(() {
                            _showAreaSearch = !_showAreaSearch;
                            if (!_showAreaSearch) {
                              _areaSearchCtrl.clear();
                              _areaSearchFocusNode.unfocus();
                            } else {
                              _areaSearchFocusNode.requestFocus();
                            }
                          });
                        },
                      ),
                    ),
                    AnimatedCrossFade(
                      firstChild: const SizedBox.shrink(),
                      secondChild: Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 6),
                        child: TextField(
                          controller: _areaSearchCtrl,
                          focusNode: _areaSearchFocusNode,
                          textDirection: TextDirection.rtl,
                          onChanged: (value) {
                            setState(() {}); // Rebuild to filter chips
                          },
                          decoration: const InputDecoration(
                            hintText: 'חפש אזור (למשל: תל אביב, גוש דן, השרון)',
                            prefixIcon: Icon(IconsaxPlusLinear.search_normal),
                          ),
                        ),
                      ),
                      crossFadeState: _showAreaSearch
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      duration: const Duration(milliseconds: 200),
                    ),
                    const SizedBox(height: 12),
                    if (filteredSearchAreas.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'לא נמצאו אזורים מתאימים',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: filteredSearchAreas.map((searchArea) {
                          final sel = f.areaId == searchArea.id;
                          return ChoiceChip(
                            selected: sel,
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  IconsaxPlusLinear.location,
                                  size: 14,
                                  color: sel ? Colors.white : AppColors.navy,
                                ),
                                const SizedBox(width: 5),
                                Text(searchArea.name),
                              ],
                            ),
                            labelStyle: TextStyle(
                              color: sel ? Colors.white : AppColors.navy,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                            selectedColor: AppColors.primary,
                            backgroundColor: AppColors.primaryLight2,
                            side: BorderSide(
                              color: sel ? AppColors.primary : AppColors.borderLight,
                            ),
                            showCheckmark: false,
                            onSelected: (_) => provider.updateFilters(
                              f.copyWith(areaId: searchArea.id),
                            ),
                          );
                        }).toList(),
                      ),
                    const SizedBox(height: 22),
                    _FilterSection(
                      title: 'מיון דק הדירות',
                      icon: IconsaxPlusLinear.sort,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: SearchSortOption.values.map((option) {
                        final selected = f.sortBy == option;
                        return ChoiceChip(
                          selected: selected,
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _sortIcon(option),
                                size: 14,
                                color: selected ? Colors.white : AppColors.navy,
                              ),
                              const SizedBox(width: 5),
                              Text(_sortLabel(option)),
                            ],
                          ),
                          labelStyle: TextStyle(
                            color: selected ? Colors.white : AppColors.navy,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.primaryLight2,
                          side: BorderSide(
                            color: selected
                                ? AppColors.primary
                                : AppColors.borderLight,
                          ),
                          showCheckmark: false,
                          onSelected: (_) => provider.updateFilters(
                            f.copyWith(sortBy: option),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 22),
                    _SliderField(
                      label: 'תקציב מקסימלי',
                      icon: IconsaxPlusLinear.money,
                      value: f.maxBudget.toDouble(),
                      min: 3000,
                      max: 18000,
                      divisions: 150,
                      displayValue: _formatCurrency(f.maxBudget),
                      onChanged: (v) => provider.updateFilters(
                        f.copyWith(maxBudget: (v / 100).round() * 100),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SliderField(
                      label: 'מינימום חדרים',
                      icon: IconsaxPlusLinear.home,
                      value: f.minRooms,
                      min: 1,
                      max: 6,
                      divisions: 10,
                      displayValue: f.minRooms % 1 == 0
                          ? f.minRooms.toInt().toString()
                          : '${f.minRooms}',
                      onChanged: (v) => provider.updateFilters(
                        f.copyWith(minRooms: (v * 2).round() / 2),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _SliderField(
                      label: 'גודל מינימלי',
                      icon: IconsaxPlusLinear.maximize_4,
                      value: f.minSizeM2.toDouble(),
                      min: 0,
                      max: 250,
                      divisions: 25,
                      displayValue: '${f.minSizeM2.round()} מ"ר',
                      onChanged: (value) {
                        final minSize = value.round();
                        final maxSize = f.maxSizeM2 < minSize ? minSize : f.maxSizeM2;
                        provider.updateFilters(
                          f.copyWith(minSizeM2: minSize, maxSizeM2: maxSize),
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    _SliderField(
                      label: 'גודל מקסימלי',
                      icon: IconsaxPlusLinear.maximize_4,
                      value: f.maxSizeM2.toDouble(),
                      min: 20,
                      max: 400,
                      divisions: 38,
                      displayValue: '${f.maxSizeM2.round()} מ"ר',
                      onChanged: (value) {
                        final maxSize = value.round();
                        final minSize = f.minSizeM2 > maxSize ? maxSize : f.minSizeM2;
                        provider.updateFilters(
                          f.copyWith(minSizeM2: minSize, maxSizeM2: maxSize),
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    _SliderField(
                      label: 'קומה מינימלית',
                      icon: IconsaxPlusBold.building,
                      value: f.minFloor.toDouble(),
                      min: 0,
                      max: 30,
                      divisions: 30,
                      displayValue:
                          f.minFloor == 0 ? 'ללא הגבלה' : 'קומה ${f.minFloor}+',
                      onChanged: (value) => provider.updateFilters(
                        f.copyWith(minFloor: value.round()),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _FilterSection(
                      title: 'סוג נכס',
                      icon: IconsaxPlusBold.building,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: provider.availablePropertyTypes.map((type) {
                        final selected = f.propertyTypes.contains(type);
                        return FilterChip(
                          selected: selected,
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _propertyTypeIcon(type),
                                size: 14,
                                color: selected ? Colors.white : AppColors.navy,
                              ),
                              const SizedBox(width: 5),
                              Text(type),
                            ],
                          ),
                          labelStyle: TextStyle(
                            color: selected ? Colors.white : AppColors.navy,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.primaryLight2,
                          side: BorderSide(
                            color: selected
                                ? AppColors.primary
                                : AppColors.borderLight,
                          ),
                          checkmarkColor: Colors.white,
                          showCheckmark: false,
                          onSelected: (value) {
                            final types = {...f.propertyTypes};
                            if (value) {
                              types.add(type);
                            } else {
                              types.remove(type);
                            }
                            provider.updateFilters(f.copyWith(propertyTypes: types));
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 22),
                    _FilterSection(
                      title: 'מצב הנכס',
                      icon: IconsaxPlusLinear.shield_tick,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: provider.availableConditions.map((condition) {
                        final selected = f.conditions.contains(condition);
                        return FilterChip(
                          selected: selected,
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                IconsaxPlusLinear.shield_tick,
                                size: 14,
                                color: selected ? Colors.white : AppColors.navy,
                              ),
                              const SizedBox(width: 5),
                              Text(condition),
                            ],
                          ),
                          labelStyle: TextStyle(
                            color: selected ? Colors.white : AppColors.navy,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.primaryLight2,
                          side: BorderSide(
                            color: selected
                                ? AppColors.primary
                                : AppColors.borderLight,
                          ),
                          checkmarkColor: Colors.white,
                          showCheckmark: false,
                          onSelected: (value) {
                            final conds = {...f.conditions};
                            if (value) {
                              conds.add(condition);
                            } else {
                              conds.remove(condition);
                            }
                            provider.updateFilters(f.copyWith(conditions: conds));
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 22),
                    _FilterSection(
                      title: 'מקור מודעה',
                      icon: IconsaxPlusLinear.profile_2user,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: ListingSourceFilter.values.map((source) {
                        final selected = f.listingSource == source;
                        return ChoiceChip(
                          selected: selected,
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _listingSourceIcon(source),
                                size: 14,
                                color: selected ? Colors.white : AppColors.navy,
                              ),
                              const SizedBox(width: 5),
                              Text(_listingSourceLabel(source)),
                            ],
                          ),
                          labelStyle: TextStyle(
                            color: selected ? Colors.white : AppColors.navy,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.primaryLight2,
                          side: BorderSide(
                            color: selected
                                ? AppColors.primary
                                : AppColors.borderLight,
                          ),
                          showCheckmark: false,
                          onSelected: (_) => provider.updateFilters(
                            f.copyWith(listingSource: source),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 22),
                    _FilterSection(
                      title: 'מועד כניסה',
                      icon: IconsaxPlusLinear.calendar_1,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: MoveInFilter.values.map((option) {
                        final selected = f.moveInFilter == option;
                        return ChoiceChip(
                          selected: selected,
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                IconsaxPlusLinear.calendar_1,
                                size: 14,
                                color: selected ? Colors.white : AppColors.navy,
                              ),
                              const SizedBox(width: 5),
                              Text(_moveInLabel(option)),
                            ],
                          ),
                          labelStyle: TextStyle(
                            color: selected ? Colors.white : AppColors.navy,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.primaryLight2,
                          side: BorderSide(
                            color: selected
                                ? AppColors.primary
                                : AppColors.borderLight,
                          ),
                          showCheckmark: false,
                          onSelected: (_) => provider.updateFilters(
                            f.copyWith(moveInFilter: option),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 22),
                    _FilterSection(
                      title: 'מאפיינים חשובים',
                      icon: IconsaxPlusBold.filter,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: provider.availableFeatures.take(16).map((feature) {
                        final sel = f.requiredFeatures.contains(feature);
                        return FilterChip(
                          selected: sel,
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _featureIcon(feature),
                                size: 14,
                                color: sel ? Colors.white : AppColors.navy,
                              ),
                              const SizedBox(width: 5),
                              Text(feature),
                            ],
                          ),
                          labelStyle: TextStyle(
                            color: sel ? Colors.white : AppColors.navy,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.primaryLight2,
                          side: BorderSide(
                            color: sel ? AppColors.primary : AppColors.borderLight,
                          ),
                          checkmarkColor: Colors.white,
                          showCheckmark: false,
                          onSelected: (v) {
                            final feats = {...f.requiredFeatures};
                            if (v) {
                              feats.add(feature);
                            } else {
                              feats.remove(feature);
                            }
                            provider.updateFilters(f.copyWith(requiredFeatures: feats));
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(IconsaxPlusBold.tick_circle),
                      label: Text('הצג ${provider.filteredProperties.length} דירות'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.title, this.icon, this.action});
  final String title;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 18, color: AppColors.navy),
          const SizedBox(width: 8),
        ],
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
        ),
        if (action != null) ...[
          const Spacer(),
          action!,
        ],
      ],
    );
  }
}

class _SliderField extends StatelessWidget {
  const _SliderField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayValue,
    required this.onChanged,
    this.icon,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final ValueChanged<double> onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: AppColors.navy),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy),
            ),
            const Spacer(),
            Text(
              displayValue,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _UndoButton extends StatelessWidget {
  const _UndoButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.borderLight),
          boxShadow: const [
            BoxShadow(
              color: AppColors.shadow,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(IconsaxPlusBold.undo,
                size: 16, color: AppColors.textSecondary),
            SizedBox(width: 5),
            Text(
              'בטל',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoMorePropertiesState extends StatelessWidget {
  const _NoMorePropertiesState();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DatingProvider>();

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                IconsaxPlusBold.search_normal,
                color: AppColors.primary,
                size: 40,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'ראית את כל הדירות!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'נסה אחת מהפעולות המהירות כדי למצוא עוד דירות',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                height: 1.5,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            _QuickActionBtn(
              icon: IconsaxPlusLinear.money,
              label: 'הרחב תקציב ב-₪500',
              onTap: () => provider.updateFilters(
                provider.filters.copyWith(
                  maxBudget: provider.filters.maxBudget + 500,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _QuickActionBtn(
              icon: IconsaxPlusLinear.home,
              label: 'הפחת דרישת חדרים ב-0.5',
              onTap: () {
                if (provider.filters.minRooms > 1) {
                  provider.updateFilters(
                    provider.filters.copyWith(
                      minRooms: provider.filters.minRooms - 0.5,
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 10),
            _QuickActionBtn(
              icon: IconsaxPlusLinear.maximize_4,
              label: 'פתח גודל מ-20 מ"ר',
              onTap: () => provider.updateFilters(
                provider.filters.copyWith(
                  minSizeM2: provider.filters.minSizeM2 >= 20
                      ? provider.filters.minSizeM2 - 20
                      : 0,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _QuickActionBtn(
              icon: IconsaxPlusBold.undo,
              label: 'אפס דירות שדילגתי',
              onTap: () => provider.resetPassed(),
              isHighlighted: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionBtn extends StatelessWidget {
  const _QuickActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isHighlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: isHighlighted ? AppColors.primary : AppColors.navy,
          side: BorderSide(
            color: isHighlighted ? AppColors.primary : AppColors.borderLight,
          ),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
    );
  }
}

class _SkeletonDiscoverView extends StatefulWidget {
  const _SkeletonDiscoverView();

  @override
  State<_SkeletonDiscoverView> createState() => _SkeletonDiscoverViewState();
}

class _SkeletonDiscoverViewState extends State<_SkeletonDiscoverView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _shimmer = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
        child: AnimatedBuilder(
          animation: _shimmer,
          builder: (context, _) {
            final base = Color.lerp(
              const Color(0xFFE8EDF2),
              const Color(0xFFF4F6F9),
              _shimmer.value,
            )!;
            final highlight = Color.lerp(
              const Color(0xFFDDE3EB),
              const Color(0xFFEBEFF4),
              _shimmer.value,
            )!;
            return Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(color: base),
                        Positioned(
                          bottom: 28,
                          left: 24,
                          right: 24,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                  height: 28,
                                  width: 140,
                                  decoration: BoxDecoration(
                                      color: highlight,
                                      borderRadius: BorderRadius.circular(8))),
                              const SizedBox(height: 10),
                              Container(
                                  height: 14,
                                  width: 200,
                                  decoration: BoxDecoration(
                                      color: highlight,
                                      borderRadius: BorderRadius.circular(6))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Container(
                    height: 52,
                    color: Color.lerp(base, highlight, 0.5),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String _formatCurrency(int value) {
  final raw = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final remaining = raw.length - i;
    buffer.write(raw[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write(',');
    }
  }
  return '₪$buffer';
}

String _sortLabel(SearchSortOption option) {
  switch (option) {
    case SearchSortOption.bestMatch:
      return 'התאמה חכמה';
    case SearchSortOption.priceLowToHigh:
      return 'מחיר מהנמוך לגבוה';
    case SearchSortOption.priceHighToLow:
      return 'מחיר מהגבוה לנמוך';
    case SearchSortOption.newestEntry:
      return 'כניסה הכי קרובה';
    case SearchSortOption.biggestFirst:
      return 'הכי מרווחות';
  }
}

String _listingSourceLabel(ListingSourceFilter source) {
  switch (source) {
    case ListingSourceFilter.any:
      return 'הכל';
    case ListingSourceFilter.privateOnly:
      return 'בעלים פרטיים';
    case ListingSourceFilter.agencyOnly:
      return 'תיווך בלבד';
  }
}

String _moveInLabel(MoveInFilter option) {
  switch (option) {
    case MoveInFilter.any:
      return 'כל מועד';
    case MoveInFilter.immediate:
      return 'מיידי';
    case MoveInFilter.within30Days:
      return 'עד 30 יום';
    case MoveInFilter.within90Days:
      return 'עד 90 יום';
  }
}

IconData _sortIcon(SearchSortOption option) {
  switch (option) {
    case SearchSortOption.priceLowToHigh:
      return IconsaxPlusLinear.sort;
    case SearchSortOption.priceHighToLow:
      return IconsaxPlusLinear.sort;
    case SearchSortOption.newestEntry:
      return IconsaxPlusLinear.calendar;
    case SearchSortOption.biggestFirst:
      return IconsaxPlusLinear.maximize_3;
    case SearchSortOption.bestMatch:
      return IconsaxPlusBold.star;
  }
}

IconData _propertyTypeIcon(String type) {
  final lower = type.trim().toLowerCase();
  if (lower.contains('גג') || lower.contains('פנטהאוז') || lower.contains('דופלקס')) {
    return IconsaxPlusLinear.buildings;
  }
  if (lower.contains('גן') || lower.contains('חצר') || lower.contains('גינה')) {
    return IconsaxPlusLinear.map_1;
  }
  if (lower.contains('בית') || lower.contains('קוטג') || lower.contains('יחידת') || lower.contains('סטודיו')) {
    return IconsaxPlusLinear.home;
  }
  return IconsaxPlusLinear.building;
}

IconData _listingSourceIcon(ListingSourceFilter source) {
  switch (source) {
    case ListingSourceFilter.any:
      return IconsaxPlusLinear.profile_2user;
    case ListingSourceFilter.privateOnly:
      return IconsaxPlusLinear.user;
    case ListingSourceFilter.agencyOnly:
      return IconsaxPlusLinear.buildings;
  }
}

IconData _featureIcon(String feature) {
  final lower = feature.trim().toLowerCase();
  if (lower.contains('חניה')) return IconsaxPlusLinear.routing;
  if (lower.contains('מעלית')) return IconsaxPlusLinear.buildings;
  if (lower.contains('ממ"ד') || lower.contains('ממד')) return IconsaxPlusLinear.shield_tick;
  if (lower.contains('מזגן') || lower.contains('מיזוג')) return IconsaxPlusLinear.layer;
  if (lower.contains('מרפסת')) return IconsaxPlusLinear.layer;
  if (lower.contains('מחסן')) return IconsaxPlusLinear.lock;
  if (lower.contains('ריהוט') || lower.contains('מרוהטת')) return IconsaxPlusLinear.home;
  if (lower.contains('חיות')) return IconsaxPlusBold.heart;
  if (lower.contains('סורגים')) return IconsaxPlusLinear.lock;
  if (lower.contains('נגישות')) return IconsaxPlusLinear.profile_circle;
  if (lower.contains('גינה') || lower.contains('חצר')) return IconsaxPlusLinear.map;
  if (lower.contains('שומר') || lower.contains('אבטחה')) return IconsaxPlusLinear.shield_tick;
  if (lower.contains('משופצת') || lower.contains('משופץ')) return IconsaxPlusLinear.setting_4;
  return IconsaxPlusLinear.hashtag;
}
