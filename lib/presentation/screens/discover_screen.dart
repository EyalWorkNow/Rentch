import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/features/discover/action_button.dart';
import 'package:dating_app/presentation/features/discover/profile_card.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:dating_app/presentation/widgets/gamification/fomo_widgets.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/rentch_icon.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final properties = provider.filteredProperties;

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: AppColors.background,
            elevation: 0,
            centerTitle: true,
            title: Text(
              '${properties.length} דירות באזור',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.navy,
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: GestureDetector(
                  onTap: provider.isLoading
                      ? null
                      : () => _showFilters(context, provider),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        height: 42,
                        width: 42,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(0xFFE2E8F0),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: RentchIcon(
                            IconsaxPlusLinear.setting_4,
                            size: 20,
                            color: AppColors.navy,
                          ),
                        ),
                      ),
                      if (provider.activeFilterCount > 0)
                        Positioned(
                          top: -2,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${provider.activeFilterCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          body: provider.isLoading
              ? const _SkeletonDiscoverView()
              : SafeArea(
                  child: Column(
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            properties.isNotEmpty
                                ? CardSwiper(
                                    key: ValueKey(
                                      provider.filteredPropertiesRevision,
                                    ),
                                    controller:
                                        provider.propertySwiperController,
                                    cardsCount: properties.length,
                                    padding:
                                        const EdgeInsets.fromLTRB(10, 6, 10, 0),
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
                                      if (index < 0 ||
                                          index >= properties.length) {
                                        return const SizedBox.shrink();
                                      }
                                      return Stack(
                                        children: [
                                          ProfileCard(
                                            key: ValueKey(
                                              properties[index].id,
                                            ),
                                            property: properties[index],
                                            horizontalOffsetPercentage:
                                                horizontalOffsetPercentage,
                                          ),
                                          FomoCardOverlay(
                                            property: properties[index],
                                            likedIds: provider.likedPropertyIds,
                                          ),
                                        ],
                                      );
                                    },
                                  )
                                : const _NoMorePropertiesState(),
                            // Undo floating button — bottom-left of card stack
                            if (provider.canUndo)
                              Positioned(
                                bottom: 12,
                                left: 16,
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
                          onVirtualTour: () {
                            if (properties.isEmpty) return;
                            openPropertyTour(context, properties.first);
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
}

class MatchCelebrationOverlay extends StatefulWidget {
  const MatchCelebrationOverlay({super.key, required this.property});
  final RentalProperty property;

  @override
  State<MatchCelebrationOverlay> createState() =>
      _MatchCelebrationOverlayState();
}

class _MatchCelebrationOverlayState extends State<MatchCelebrationOverlay>
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
    final media = p.primaryMedia;

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
                      child: const RentchIcon(
                        IconsaxPlusLinear.heart,
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
              if (media != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    width: 220,
                    height: 150,
                    child: _MatchPropertyImage(media: media),
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
                        icon: const RentchIcon(IconsaxPlusLinear.message),
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

class _MatchPropertyImage extends StatelessWidget {
  const _MatchPropertyImage({required this.media});

  final PropertyMedia media;

  @override
  Widget build(BuildContext context) {
    return SafeMedia(
      media: media,
      fallback: _fallback(),
      fit: BoxFit.cover,
    );
  }

  Widget _fallback() => Container(
        color: AppColors.navy,
        child: const Center(
          child: RentchIcon(
            IconsaxPlusLinear.building,
            color: Colors.white30,
            size: 40,
          ),
        ),
      );
}

// ─── Filters Sheet ────────────────────────────────────────────────────────────

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({required this.provider});
  final DatingProvider provider;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  static const Duration _doubleTapWindow = Duration(milliseconds: 260);
  late final TextEditingController _locationCtrl;
  Timer? _pendingPriorityTimer;
  String? _pendingPriorityKey;
  late SearchFilters _draftFilters;
  late final String _initialFiltersKey;
  late int _visibleCount;
  late List<RentalProperty> _markerPreview;
  bool _didCommit = false;
  bool _showAllFeatures = false;

  @override
  void initState() {
    super.initState();
    _draftFilters = widget.provider.filters;
    _initialFiltersKey = _filtersKey(_draftFilters);
    _visibleCount = widget.provider.filteredCountFor(_draftFilters);
    _markerPreview = widget.provider.previewFilteredProperties(_draftFilters);
    _locationCtrl = TextEditingController(text: widget.provider.filters.city);
  }

  @override
  void dispose() {
    _commitDraftIfNeeded();
    _pendingPriorityTimer?.cancel();
    _locationCtrl.dispose();
    super.dispose();
  }

  void _setDraftFilters(SearchFilters filters, DatingProvider provider) {
    final count = provider.filteredCountFor(filters);
    final markers = provider.previewFilteredProperties(filters);
    setState(() {
      _draftFilters = filters;
      _visibleCount = count;
      _markerPreview = markers;
    });
  }

  SearchFilters _filtersForTransaction(
    SearchFilters filters,
    TransactionTypeFilter type,
  ) {
    final sliderMin = _priceSliderMin(type).round();
    final sliderMax = _priceSliderMax(type).round();
    return filters.copyWith(
      transactionType: type,
      minBudget: sliderMin,
      maxBudget: sliderMax,
    );
  }

  String _transactionMetric(
    DatingProvider provider,
    SearchFilters filters,
    TransactionTypeFilter type,
  ) {
    final scopedFilters = _filtersForTransaction(filters, type);
    final count = provider.filteredCountFor(scopedFilters);
    final averagePrice = provider.averagePriceFor(scopedFilters);
    final price = averagePrice <= 0
        ? 'אין מחיר'
        : _compactPriceLabel(averagePrice.round());
    return '$count דירות · $price';
  }

  String _filtersKey(SearchFilters filters) {
    return jsonEncode({
      ...filters.toJson(),
      'requiredFeatures': filters.requiredFeatures.toList()..sort(),
      'preferredFeatures': filters.preferredFeatures.toList()..sort(),
      'propertyTypes': filters.propertyTypes.toList()..sort(),
      'preferredPropertyTypes': filters.preferredPropertyTypes.toList()..sort(),
      'conditions': filters.conditions.toList()..sort(),
      'preferredConditions': filters.preferredConditions.toList()..sort(),
      'requiredListingSources':
          filters.requiredListingSources.map((source) => source.name).toList()
            ..sort(),
      'preferredListingSources':
          filters.preferredListingSources.map((source) => source.name).toList()
            ..sort(),
      'requiredMoveInFilters':
          filters.requiredMoveInFilters.map((filter) => filter.name).toList()
            ..sort(),
      'preferredMoveInFilters':
          filters.preferredMoveInFilters.map((filter) => filter.name).toList()
            ..sort(),
    });
  }

  bool get _hasPendingChanges =>
      _filtersKey(_draftFilters) != _initialFiltersKey;

  void _commitDraftIfNeeded() {
    if (_didCommit || !_hasPendingChanges) return;
    _didCommit = true;
    unawaited(widget.provider.updateFilters(_draftFilters));
  }

  /// One tap marks preferred, a second quick tap upgrades to required.
  /// Tapping an already-selected chip clears it.
  void _handlePriorityTap({
    required String key,
    required FilterPriority current,
    required ValueChanged<FilterPriority> onSelected,
  }) {
    if (current == FilterPriority.required ||
        (current == FilterPriority.preferred && _pendingPriorityKey != key)) {
      _pendingPriorityTimer?.cancel();
      _pendingPriorityKey = null;
      onSelected(FilterPriority.none);
      return;
    }

    if (_pendingPriorityKey == key) {
      _pendingPriorityTimer?.cancel();
      _pendingPriorityKey = null;
      onSelected(FilterPriority.required);
      return;
    }

    _pendingPriorityTimer?.cancel();
    _pendingPriorityKey = key;
    onSelected(FilterPriority.preferred);
    _pendingPriorityTimer = Timer(_doubleTapWindow, () {
      if (_pendingPriorityKey == key) {
        _pendingPriorityKey = null;
      }
    });
  }

  Future<void> _editSliderValue({
    required BuildContext context,
    required String title,
    required String initialValue,
    required String suffix,
    required TextInputType keyboardType,
    required ValueChanged<String> onSubmitted,
  }) async {
    final controller = TextEditingController(text: initialValue);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            title,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: TextField(
            controller: controller,
            keyboardType: keyboardType,
            autofocus: true,
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              suffixText: suffix.isEmpty ? null : suffix,
              hintText: 'הכנס מספר',
            ),
            onSubmitted: (submitted) =>
                Navigator.of(dialogContext).pop(submitted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('שמור'),
            ),
          ],
        );
      },
    );

    if (value == null) return;
    onSubmitted(value);
  }

  Future<void> _editRangeValues({
    required BuildContext context,
    required String title,
    required String initialMinValue,
    required String initialMaxValue,
    required String suffix,
    required TextInputType keyboardType,
    required void Function(String minValue, String maxValue) onSubmitted,
  }) async {
    final minController = TextEditingController(text: initialMinValue);
    final maxController = TextEditingController(text: initialMaxValue);
    final values = await showDialog<(String, String)>(
      context: context,
      builder: (dialogContext) {
        InputDecoration decoration(String hint) => InputDecoration(
              suffixText: suffix.isEmpty ? null : suffix,
              hintText: hint,
            );

        return AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            title,
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: minController,
                keyboardType: keyboardType,
                autofocus: true,
                textAlign: TextAlign.right,
                decoration: decoration('מינימום'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: maxController,
                keyboardType: keyboardType,
                textAlign: TextAlign.right,
                decoration: decoration('מקסימום'),
                onSubmitted: (_) => Navigator.of(dialogContext).pop(
                  (minController.text, maxController.text),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ביטול'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                (minController.text, maxController.text),
              ),
              child: const Text('שמור'),
            ),
          ],
        );
      },
    );

    if (values == null) return;
    onSubmitted(values.$1, values.$2);
  }

  void _resetFilters(DatingProvider provider) {
    const resetFilters = SearchFilters(
      query: '',
      minBudget: 600,
      maxBudget: 40000,
      minRooms: 0,
      maxRooms: 10,
      areaId: 'all_israel',
      requiredFeatures: <String>{},
      preferredFeatures: <String>{},
      minSizeM2: 0,
      maxSizeM2: 1000000,
      propertyTypes: <String>{},
      preferredPropertyTypes: <String>{},
      conditions: <String>{},
      preferredConditions: <String>{},
      listingSource: ListingSourceFilter.any,
      minFloor: 0,
      moveInFilter: MoveInFilter.any,
      sortBy: SearchSortOption.bestMatch,
      includeUnknownPriceListings: false,
      customAreaPolygon: <LatLng>[],
      city: '',
      transactionType: TransactionTypeFilter.any,
    );
    setState(() {
      _locationCtrl.clear();
      _draftFilters = resetFilters;
      _visibleCount = provider.filteredCountFor(resetFilters);
      _markerPreview = provider.previewFilteredProperties(resetFilters);
    });
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final f = _draftFilters;
        final area = f.hasCustomArea
            ? SearchArea.custom(polygon: f.customAreaPolygon)
            : provider.searchAreas.firstWhere(
                (item) => item.id == f.areaId,
                orElse: () => provider.selectedArea,
              );

        final locationQuery = _locationCtrl.text.trim().toLowerCase();
        final filteredCities = provider.availableCities
            .where((city) =>
                locationQuery.isEmpty ||
                city.toLowerCase().contains(locationQuery))
            .take(12)
            .toList();
        final filteredAreas = provider.searchAreas
            .where((a) =>
                locationQuery.isEmpty ||
                a.name.toLowerCase().contains(locationQuery))
            .where((a) => a.id != 'all_israel')
            .take(8)
            .toList();
        final locationSuggestions = <_LocationSuggestion>[
          ...filteredCities.map(
            (city) => _LocationSuggestion.city(city),
          ),
          ...filteredAreas.map(
            (searchArea) => _LocationSuggestion.area(searchArea),
          ),
        ];

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.92,
          ),
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: Column(
              children: [
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
                // Header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF2F4F5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                size: 18, color: AppColors.navy),
                          ),
                        ),
                      ),
                      const Text(
                        'סינון ומיון',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 1,
                  color: AppColors.borderLight.withValues(alpha: 0.8),
                ),
                // Scrollable content
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
                    children: [
                      // ── מטרה ──
                      _FilterSection(
                        title: 'מטרה',
                        icon: IconsaxPlusLinear.category,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _TransactionCard(
                            label: 'הכל',
                            price: _transactionMetric(
                              provider,
                              f,
                              TransactionTypeFilter.any,
                            ),
                            isSelected:
                                f.transactionType == TransactionTypeFilter.any,
                            onTap: () {
                              _setDraftFilters(
                                _filtersForTransaction(
                                  f,
                                  TransactionTypeFilter.any,
                                ),
                                provider,
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          _TransactionCard(
                            label: 'שכירות',
                            price: _transactionMetric(
                              provider,
                              f,
                              TransactionTypeFilter.rent,
                            ),
                            isSelected:
                                f.transactionType == TransactionTypeFilter.rent,
                            onTap: () {
                              _setDraftFilters(
                                _filtersForTransaction(
                                  f,
                                  TransactionTypeFilter.rent,
                                ),
                                provider,
                              );
                            },
                          ),
                          const SizedBox(width: 8),
                          _TransactionCard(
                            label: 'קנייה',
                            price: _transactionMetric(
                              provider,
                              f,
                              TransactionTypeFilter.sale,
                            ),
                            isSelected:
                                f.transactionType == TransactionTypeFilter.sale,
                            onTap: () {
                              _setDraftFilters(
                                _filtersForTransaction(
                                  f,
                                  TransactionTypeFilter.sale,
                                ),
                                provider,
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // ── תקציב ──
                      _FilterSection(
                        title: 'טווח מחירים',
                        icon: IconsaxPlusLinear.money,
                      ),
                      const SizedBox(height: 12),
                      _PriceHistogram(
                        minBudget: f.minBudget.toDouble().clamp(
                              _priceSliderMin(f.transactionType),
                              _priceSliderMax(f.transactionType),
                            ),
                        maxBudget: f.maxBudget.toDouble().clamp(
                              _priceSliderMin(f.transactionType),
                              _priceSliderMax(f.transactionType),
                            ),
                        sliderMin: _priceSliderMin(f.transactionType),
                        sliderMax: _priceSliderMax(f.transactionType),
                      ),
                      const SizedBox(height: 4),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          rangeThumbShape: const _CustomRangeSliderThumbShape(),
                          activeTrackColor: AppColors.primary,
                          inactiveTrackColor: const Color(0xFFE2ECF1),
                        ),
                        child: RangeSlider(
                          values: RangeValues(
                            f.minBudget.toDouble().clamp(
                                _priceSliderMin(f.transactionType),
                                _priceSliderMax(f.transactionType)),
                            f.maxBudget.toDouble().clamp(
                                _priceSliderMin(f.transactionType),
                                _priceSliderMax(f.transactionType)),
                          ),
                          min: _priceSliderMin(f.transactionType),
                          max: _priceSliderMax(f.transactionType),
                          divisions: _priceSliderDivisions(f.transactionType),
                          onChanged: (values) => _setDraftFilters(
                            f.copyWith(
                              minBudget: _roundedPriceForTransaction(
                                f.transactionType,
                                values.start,
                              ),
                              maxBudget: _roundedPriceForTransaction(
                                f.transactionType,
                                values.end,
                              ),
                            ),
                            provider,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _PriceInputCard(
                            label: 'מינימום',
                            value: _formatCurrency(f.minBudget.round()),
                            onTap: () => _editRangeValues(
                              context: context,
                              title: _priceFilterLabel(),
                              initialMinValue: f.minBudget.toString(),
                              initialMaxValue: f.maxBudget.toString(),
                              suffix: '₪',
                              keyboardType: TextInputType.number,
                              onSubmitted: (minRaw, maxRaw) {
                                final minParsed = int.tryParse(
                                  minRaw.replaceAll(RegExp(r'[^0-9]'), ''),
                                );
                                final maxParsed = maxRaw.trim().isEmpty
                                    ? 2000000000
                                    : int.tryParse(
                                        maxRaw.replaceAll(
                                            RegExp(r'[^0-9]'), ''),
                                      );
                                if (minParsed == null || maxParsed == null) {
                                  return;
                                }
                                final sliderMin =
                                    _priceSliderMin(f.transactionType).round();
                                final clampedMin = _roundedPriceForTransaction(
                                  f.transactionType,
                                  math.max(sliderMin, minParsed).toDouble(),
                                );
                                final clampedMax = _roundedPriceForTransaction(
                                  f.transactionType,
                                  math.max(clampedMin, maxParsed).toDouble(),
                                );
                                _setDraftFilters(
                                  f.copyWith(
                                    minBudget: clampedMin,
                                    maxBudget: clampedMax,
                                  ),
                                  provider,
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          _PriceInputCard(
                            label: 'מקסימום',
                            value: f.maxBudget >= 2000000000
                                ? 'ללא הגבלה'
                                : _formatCurrency(f.maxBudget.round()),
                            onTap: () => _editRangeValues(
                              context: context,
                              title: _priceFilterLabel(),
                              initialMinValue: f.minBudget.toString(),
                              initialMaxValue: f.maxBudget.toString(),
                              suffix: '₪',
                              keyboardType: TextInputType.number,
                              onSubmitted: (minRaw, maxRaw) {
                                final minParsed = int.tryParse(
                                  minRaw.replaceAll(RegExp(r'[^0-9]'), ''),
                                );
                                final maxParsed = maxRaw.trim().isEmpty
                                    ? 2000000000
                                    : int.tryParse(
                                        maxRaw.replaceAll(
                                            RegExp(r'[^0-9]'), ''),
                                      );
                                if (minParsed == null || maxParsed == null) {
                                  return;
                                }
                                final sliderMin =
                                    _priceSliderMin(f.transactionType).round();
                                final clampedMin = _roundedPriceForTransaction(
                                  f.transactionType,
                                  math.max(sliderMin, minParsed).toDouble(),
                                );
                                final clampedMax = _roundedPriceForTransaction(
                                  f.transactionType,
                                  math.max(clampedMin, maxParsed).toDouble(),
                                );
                                _setDraftFilters(
                                  f.copyWith(
                                    minBudget: clampedMin,
                                    maxBudget: clampedMax,
                                  ),
                                  provider,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile.adaptive(
                        value: f.includeUnknownPriceListings,
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'לכלול דירות בלי מחיר',
                          style: TextStyle(
                            color: AppColors.navy,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        subtitle: const Text(
                          'מחיר מתחת ל-600 ש"ח נחשב כלא ידוע',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        onChanged: (value) => _setDraftFilters(
                          f.copyWith(includeUnknownPriceListings: value),
                          provider,
                        ),
                      ),
                      const SizedBox(height: 24),
                      // ── חדרים ──
                      _FilterSection(
                        title: 'חדרים',
                        icon: IconsaxPlusLinear.home,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (int i = 0; i <= 5; i++) ...[
                            _CircleSelectorButton(
                              label: i == 0 ? 'הכל' : '$i+',
                              isSelected: i == 0
                                  ? (f.minRooms == 0 && f.maxRooms == 10)
                                  : (f.minRooms == i.toDouble()),
                              onTap: () {
                                if (i == 0) {
                                  _setDraftFilters(
                                    f.copyWith(minRooms: 0, maxRooms: 10),
                                    provider,
                                  );
                                } else {
                                  _setDraftFilters(
                                    f.copyWith(
                                        minRooms: i.toDouble(), maxRooms: 10),
                                    provider,
                                  );
                                }
                              },
                            ),
                          ]
                        ],
                      ),
                      const SizedBox(height: 24),
                      // ── מיקום (עיר + אזור) ──
                      _FilterSection(
                        title: 'מיקום',
                        icon: IconsaxPlusLinear.location,
                        action: (f.city.isNotEmpty ||
                                f.areaId != 'all_israel' ||
                                f.hasCustomArea)
                            ? TextButton(
                                onPressed: () {
                                  setState(() => _locationCtrl.clear());
                                  _setDraftFilters(
                                    f.copyWith(
                                      city: '',
                                      areaId: 'all_israel',
                                      customAreaPolygon: const <LatLng>[],
                                    ),
                                    provider,
                                  );
                                },
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  foregroundColor: AppColors.primary,
                                ),
                                child: const Text('הכל'),
                              )
                            : null,
                      ),
                      const SizedBox(height: 10),
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
                            const RentchIcon(
                              IconsaxPlusLinear.search_normal,
                              size: 18,
                              color: Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _locationCtrl,
                                textDirection: TextDirection.rtl,
                                onChanged: (v) => setState(() {}),
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppColors.navy,
                                  fontWeight: FontWeight.w700,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'חפש עיר או אזור',
                                  hintStyle: TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textSecondary
                                        .withValues(alpha: 0.72),
                                    fontWeight: FontWeight.w600,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                            if (_locationCtrl.text.isNotEmpty)
                              IconButton(
                                icon: const RentchIcon(
                                  IconsaxPlusLinear.close_circle,
                                  size: 18,
                                  color: AppColors.textSecondary,
                                ),
                                onPressed: () {
                                  setState(() => _locationCtrl.clear());
                                  _setDraftFilters(
                                    f.copyWith(
                                      city: '',
                                      areaId: 'all_israel',
                                      customAreaPolygon: const <LatLng>[],
                                    ),
                                    provider,
                                  );
                                },
                              ),
                            Container(
                              width: 40,
                              height: 40,
                              decoration: const BoxDecoration(
                                color: Color(0xFFF2F4F5),
                                shape: BoxShape.circle,
                              ),
                              child: const RentchIcon(
                                IconsaxPlusLinear.location,
                                size: 18,
                                color: AppColors.navy,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: Row(
                            textDirection: TextDirection.rtl,
                            children: [
                              for (final city in [
                                'תל אביב',
                                'ירושלים',
                                'חיפה',
                                'גבעתיים',
                                'רמת גן',
                                'הרצליה',
                                'ראשון לציון',
                              ]) ...[
                                _FilterLocationPill(
                                  label: city,
                                  isSelected: f.city == city,
                                  onTap: () {
                                    final nextCity = f.city == city ? '' : city;
                                    setState(() {
                                      _locationCtrl.text = nextCity;
                                    });
                                    _setDraftFilters(
                                      f.copyWith(
                                        city: nextCity,
                                        areaId: 'all_israel',
                                        customAreaPolygon: const <LatLng>[],
                                      ),
                                      provider,
                                    );
                                  },
                                ),
                                const SizedBox(width: 8),
                              ]
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (locationQuery.isNotEmpty &&
                          locationSuggestions.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            'לא נמצאו ערים או אזורים מתאימים',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      if (locationQuery.isNotEmpty &&
                          locationSuggestions.isNotEmpty)
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.borderLight),
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
                              for (var i = 0;
                                  i < locationSuggestions.length;
                                  i++)
                                _LocationSuggestionTile(
                                  suggestion: locationSuggestions[i],
                                  isSelected: locationSuggestions[i].isCity
                                      ? f.city == locationSuggestions[i].label
                                      : f.areaId ==
                                          locationSuggestions[i].area!.id,
                                  showDivider:
                                      i != locationSuggestions.length - 1,
                                  onTap: () {
                                    final suggestion = locationSuggestions[i];
                                    setState(() {
                                      _locationCtrl.text = suggestion.label;
                                    });
                                    if (suggestion.isCity) {
                                      _setDraftFilters(
                                        f.copyWith(
                                          city: suggestion.label,
                                          areaId: 'all_israel',
                                          customAreaPolygon: const <LatLng>[],
                                        ),
                                        provider,
                                      );
                                      return;
                                    }
                                    _setDraftFilters(
                                      f.copyWith(
                                        city: '',
                                        areaId: suggestion.area!.id,
                                        customAreaPolygon: const <LatLng>[],
                                      ),
                                      provider,
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 14),
                      // Mini map
                      Container(
                        height: 160,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: const Color(0xFFE2E8F0),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Stack(
                            children: [
                              FlutterMap(
                                key: ValueKey(
                                  '${f.areaId}-${f.city}-${f.customAreaPolygon.length}',
                                ),
                                options: MapOptions(
                                  initialCenter: area.center,
                                  initialZoom: area.id == 'all_israel' ? 7.5 : 11,
                                  interactionOptions: const InteractionOptions(
                                    flags: InteractiveFlag.all,
                                  ),
                                  onTap: (_, __) async {
                                    final polygon = await Navigator.of(context)
                                        .push<List<LatLng>>(
                                      MaterialPageRoute(
                                        fullscreenDialog: true,
                                        builder: (_) => _AreaLassoScreen(
                                          initialArea: area,
                                          initialPolygon: f.customAreaPolygon,
                                          previewMarkers: _markerPreview,
                                        ),
                                      ),
                                    );
                                    if (!mounted || polygon == null) return;
                                    _setDraftFilters(
                                      f.copyWith(
                                        city: '',
                                        areaId: 'all_israel',
                                        customAreaPolygon: polygon,
                                      ),
                                      provider,
                                    );
                                  },
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
                                        color: AppColors.primary
                                            .withValues(alpha: 0.2),
                                        borderColor: AppColors.primary,
                                        borderStrokeWidth: 3,
                                      ),
                                    ],
                                  ),
                                  MarkerLayer(
                                    markers: _markerPreview
                                        .map((p) => Marker(
                                              point: p.point,
                                              width: 28,
                                              height: 28,
                                              child: const RentchIcon(
                                                  IconsaxPlusLinear.building,
                                                  color: AppColors.primary,
                                                  size: 22),
                                            ))
                                        .toList(),
                                  ),
                                ],
                              ),
                              // Interactive overlay hint
                              Positioned(
                                top: 12,
                                right: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.1),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.edit_location_alt_rounded,
                                        size: 14,
                                        color: AppColors.primary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        f.hasCustomArea ? 'ערוך אזור' : 'סמן אזור',
                                        style: const TextStyle(
                                          color: AppColors.navy,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        f.hasCustomArea
                            ? 'האזור מסומן ידנית. אפשר להזיז את המפה וללחוץ עליה כדי לערוך את הלאסו.'
                            : 'אפשר להזיז את המפה. לחיצה עליה תפתח סימון ידני עם לאסו.',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      // ── מיון ──
                      _FilterSection(
                          title: 'מיון', icon: IconsaxPlusLinear.sort),
                      const SizedBox(height: 10),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: Row(
                          textDirection: TextDirection.rtl,
                          children: SearchSortOption.values.map((option) {
                            final selected = f.sortBy == option;
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: GestureDetector(
                                onTap: () => _setDraftFilters(
                                  f.copyWith(sortBy: option),
                                  provider,
                                ),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.primary
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.primary
                                          : AppColors.borderLight,
                                    ),
                                    boxShadow: selected
                                        ? [
                                            BoxShadow(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.22),
                                              blurRadius: 8,
                                              offset: const Offset(0, 4),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _sortIcon(option),
                                        size: 13,
                                        color: selected
                                            ? Colors.white
                                            : AppColors.navy,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        _sortLabel(option),
                                        style: TextStyle(
                                          color: selected
                                              ? Colors.white
                                              : AppColors.navy,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // ── גודל ──
                      _RangeSliderField(
                        label: 'טווח גודל',
                        icon: IconsaxPlusLinear.maximize_4,
                        values: RangeValues(
                          f.minSizeM2.toDouble().clamp(0, 2000),
                          f.maxSizeM2.toDouble().clamp(0, 2000),
                        ),
                        min: 0,
                        max: 2000,
                        divisions: 200,
                        displayValue:
                            _sizeDisplayValue(f.minSizeM2, f.maxSizeM2),
                        onValueTap: () => _editRangeValues(
                          context: context,
                          title: 'טווח גודל',
                          initialMinValue: f.minSizeM2.toString(),
                          initialMaxValue: f.maxSizeM2 >= 1000000
                              ? ''
                              : f.maxSizeM2.toString(),
                          suffix: 'מ"ר',
                          keyboardType: TextInputType.number,
                          onSubmitted: (minRaw, maxRaw) {
                            final minParsed = int.tryParse(
                              minRaw.replaceAll(RegExp(r'[^0-9]'), ''),
                            );
                            final maxParsed = maxRaw.trim().isEmpty
                                ? 1000000
                                : int.tryParse(
                                    maxRaw.replaceAll(RegExp(r'[^0-9]'), ''),
                                  );
                            if (minParsed == null || maxParsed == null) return;
                            final minSize = math.max(0, minParsed);
                            final maxSize = math.max(minSize, maxParsed);
                            _setDraftFilters(
                              f.copyWith(
                                minSizeM2: minSize,
                                maxSizeM2: maxSize,
                              ),
                              provider,
                            );
                          },
                        ),
                        onChanged: (values) {
                          final minSize = values.start.round();
                          final maxSize = values.end.round() >= 2000
                              ? 1000000
                              : values.end.round();
                          _setDraftFilters(
                            f.copyWith(
                              minSizeM2: minSize,
                              maxSizeM2: maxSize,
                            ),
                            provider,
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      // ── קומה ──
                      _SliderField(
                        label: 'קומה מינימלית',
                        icon: IconsaxPlusLinear.building,
                        value: f.minFloor.toDouble(),
                        min: 0,
                        max: 30,
                        divisions: 30,
                        displayValue: f.minFloor == 0
                            ? 'ללא הגבלה'
                            : 'קומה ${f.minFloor}+',
                        onValueTap: () => _editSliderValue(
                          context: context,
                          title: 'קומה מינימלית',
                          initialValue: f.minFloor == 0 ? '' : '${f.minFloor}',
                          suffix: '',
                          keyboardType: TextInputType.number,
                          onSubmitted: (raw) {
                            final parsed = raw.trim().isEmpty
                                ? 0
                                : int.tryParse(
                                    raw.replaceAll(RegExp(r'[^0-9]'), ''),
                                  );
                            if (parsed == null) return;
                            _setDraftFilters(
                              f.copyWith(minFloor: math.max(0, parsed)),
                              provider,
                            );
                          },
                        ),
                        onChanged: (value) => _setDraftFilters(
                          f.copyWith(minFloor: value.round()),
                          provider,
                        ),
                      ),
                      const SizedBox(height: 24),
                      // ── סוג נכס ──
                      _FilterSection(
                        title: 'סוג נכס',
                        icon: IconsaxPlusLinear.building,
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: Row(
                          textDirection: TextDirection.rtl,
                          children: provider.availablePropertyTypes.map((type) {
                            final state = f.propertyTypeState(type);
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 4),
                              child: _PropertyTypeCard(
                                label: type,
                                state: state,
                                icon: _propertyTypeIcon(type),
                                onTap: () => _handlePriorityTap(
                                  key: 'type:$type',
                                  current: state,
                                  onSelected: (priority) => _setDraftFilters(
                                    f.setPropertyTypeState(type, priority),
                                    provider,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // ── מצב הנכס ──
                      _FilterSection(
                        title: 'מצב הנכס',
                        icon: IconsaxPlusLinear.shield_tick,
                        action: const _PriorityLegend(),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: provider.availableConditions.map((condition) {
                          final state = f.conditionState(condition);
                          return _PriorityFilterChip(
                            label: condition,
                            state: state,
                            icon: IconsaxPlusLinear.shield_tick,
                            onTap: () => _handlePriorityTap(
                              key: 'condition:$condition',
                              current: state,
                              onSelected: (priority) => _setDraftFilters(
                                f.setConditionState(condition, priority),
                                provider,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      // ── מקור מודעה ──
                      _FilterSection(
                        title: 'מקור מודעה',
                        icon: IconsaxPlusLinear.profile_2user,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ListingSourceFilter.values
                            .where(
                                (source) => source != ListingSourceFilter.any)
                            .map((source) {
                          final state = f.listingSourceState(source);
                          return _PriorityFilterChip(
                            label: _listingSourceLabel(source),
                            state: state,
                            icon: _listingSourceIcon(source),
                            onTap: () => _handlePriorityTap(
                              key: 'listing-source:${source.name}',
                              current: state,
                              onSelected: (priority) => _setDraftFilters(
                                f.setListingSourceState(source, priority),
                                provider,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'ללא בחירה: יוצגו גם פרטיות וגם מתיווך',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      // ── מועד כניסה ──
                      _FilterSection(
                        title: 'מועד כניסה',
                        icon: IconsaxPlusLinear.calendar_1,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: MoveInFilter.values
                            .where((option) => option != MoveInFilter.any)
                            .map((option) {
                          final state = f.moveInState(option);
                          return _PriorityFilterChip(
                            label: _moveInLabel(option),
                            state: state,
                            icon: IconsaxPlusLinear.calendar_1,
                            onTap: () => _handlePriorityTap(
                              key: 'move-in:${option.name}',
                              current: state,
                              onSelected: (priority) => _setDraftFilters(
                                f.setMoveInState(option, priority),
                                provider,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'ללא בחירה: כל מועדי הכניסה רלוונטיים',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      // ── מאפיינים ──
                      Builder(
                        builder: (context) {
                          final selectedCount = provider.availableFeatures
                              .where((f2) =>
                                  f.featureState(f2) != FilterPriority.none)
                              .length;
                          return _FilterSection(
                            title: 'מאפיינים חשובים',
                            icon: IconsaxPlusLinear.filter,
                            badge: selectedCount > 0 ? '$selectedCount' : null,
                            action: GestureDetector(
                              onTap: () => setState(
                                () => _showAllFeatures = !_showAllFeatures,
                              ),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: _showAllFeatures
                                      ? AppColors.primary
                                          .withValues(alpha: 0.12)
                                      : const Color(0xFFF2F4F5),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  _showAllFeatures
                                      ? Icons.keyboard_arrow_up
                                      : Icons.add,
                                  size: 16,
                                  color: _showAllFeatures
                                      ? AppColors.primary
                                      : AppColors.navy,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 10),
                      if (!_showAllFeatures) ...[
                        Builder(
                          builder: (context) {
                            final selectedFeatures = provider.availableFeatures
                                .map((feature) =>
                                    (feature, f.featureState(feature)))
                                .where((pair) => pair.$2 != FilterPriority.none)
                                .toList();
                            if (selectedFeatures.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text(
                                  'לא נבחרו מאפיינים. לחץ על + כדי להוסיף.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            }
                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: selectedFeatures.map((pair) {
                                return _FeatureTag(
                                  label: pair.$1,
                                  state: pair.$2,
                                  onClear: () {
                                    _setDraftFilters(
                                      f.setFeatureState(
                                          pair.$1, FilterPriority.none),
                                      provider,
                                    );
                                  },
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: provider.availableFeatures
                              .take(24)
                              .map((feature) {
                            final state = f.featureState(feature);
                            return _PriorityFilterChip(
                              label: feature,
                              state: state,
                              icon: _featureIcon(feature),
                              onTap: () {
                                _handlePriorityTap(
                                  key: 'feature:$feature',
                                  current: state,
                                  onSelected: (priority) => _setDraftFilters(
                                    f.setFeatureState(feature, priority),
                                    provider,
                                  ),
                                );
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
                // Footer
                Container(
                  padding: EdgeInsets.fromLTRB(
                      20, 16, 20, 16 + MediaQuery.of(context).padding.bottom),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, -4),
                      ),
                    ],
                    border: const Border(
                      top: BorderSide(color: Color(0xFFE2ECF1)),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            _resetFilters(provider);
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            'נקה הכל',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: FilledButton(
                          onPressed: () {
                            _didCommit = true;
                            unawaited(provider.updateFilters(_draftFilters));
                            Navigator.of(context).pop();
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            transitionBuilder: (child, anim) => FadeTransition(
                              opacity: anim,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.3),
                                  end: Offset.zero,
                                ).animate(anim),
                                child: child,
                              ),
                            ),
                            child: Text(
                              'הצג $_visibleCount דירות',
                              key: ValueKey(_visibleCount),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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

class _FilterSection extends StatelessWidget {
  const _FilterSection(
      {required this.title, this.icon, this.action, this.badge});
  final String title;
  final IconData? icon;
  final Widget? action;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
        ],
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: AppColors.navy,
          ),
        ),
        if (badge != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              badge!,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
        if (action != null) ...[
          const Spacer(),
          action!,
        ],
      ],
    );
  }
}

class _PriorityLegend extends StatelessWidget {
  const _PriorityLegend();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LegendChip(
          label: 'מועדף',
          color: AppColors.primary,
          icon: Icons.favorite_rounded,
        ),
        const SizedBox(width: 8),
        _LegendChip(
          label: 'חייב להיות',
          color: AppColors.coral,
          icon: Icons.priority_high_rounded,
        ),
        const SizedBox(width: 10),
        const Text(
          'טאפ / דאבל טאפ',
          style: TextStyle(
            fontSize: 10,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Uses a chip surface, while tap interpretation is handled by the sheet state
/// so single tap can mean "preferred" and a quick second tap can upgrade it to
/// "required".
class _PriorityFilterChip extends StatelessWidget {
  const _PriorityFilterChip({
    required this.label,
    required this.state,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final FilterPriority state;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isActive = state != FilterPriority.none;
    final bool isRequired = state == FilterPriority.required;

    final Color activeColor = isRequired ? AppColors.coral : AppColors.primary;
    final Color labelColor = isActive ? Colors.white : AppColors.navy;

    return FilterChip(
      selected: isActive,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: activeColor,
      backgroundColor: AppColors.primaryLight2,
      side: BorderSide(
        color: isActive ? activeColor : AppColors.borderLight,
        width: 1.5,
      ),
      elevation: isActive ? 3 : 0,
      pressElevation: 4,
      shadowColor:
          isActive ? activeColor.withValues(alpha: 0.35) : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: labelColor),
          const SizedBox(width: 4),
          Text(label),
          if (state == FilterPriority.preferred) ...[
            const SizedBox(width: 4),
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.favorite_rounded,
                  size: 8, color: Colors.white),
            ),
          ],
          if (state == FilterPriority.required) ...[
            const SizedBox(width: 4),
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.priority_high_rounded,
                  size: 8, color: Colors.white),
            ),
          ],
        ],
      ),
      labelStyle: TextStyle(
        color: labelColor,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
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
    this.onValueTap,
    this.icon,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final ValueChanged<double> onChanged;
  final VoidCallback? onValueTap;
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
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onValueTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayValue,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const RentchIcon(
                        IconsaxPlusLinear.edit_2,
                        size: 14,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
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

class _RangeSliderField extends StatelessWidget {
  const _RangeSliderField({
    required this.label,
    required this.values,
    required this.min,
    required this.max,
    required this.divisions,
    required this.displayValue,
    required this.onChanged,
    this.onValueTap,
    this.icon,
  });

  final String label;
  final RangeValues values;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final ValueChanged<RangeValues> onChanged;
  final VoidCallback? onValueTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final safeStart = values.start.clamp(min, max);
    final safeEnd = values.end.clamp(safeStart, max);

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
                color: AppColors.navy,
              ),
            ),
            const Spacer(),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onValueTap,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderLight),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayValue,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const RentchIcon(
                        IconsaxPlusLinear.edit_2,
                        size: 14,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        RangeSlider(
          values: RangeValues(safeStart, safeEnd),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _AreaLassoScreen extends StatefulWidget {
  const _AreaLassoScreen({
    required this.initialArea,
    required this.initialPolygon,
    required this.previewMarkers,
  });

  final SearchArea initialArea;
  final List<LatLng> initialPolygon;
  final List<RentalProperty> previewMarkers;

  @override
  State<_AreaLassoScreen> createState() => _AreaLassoScreenState();
}

class _AreaLassoScreenState extends State<_AreaLassoScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  final List<LatLng> _currentPolygon = <LatLng>[];
  Offset? _lastDrawOffset;
  bool _drawMode = false; // Lasso mode active by default
  RentalProperty? _selectedProperty;
  final ScrollController _scrollController = ScrollController();

  List<LatLng> get _activePolygon => _currentPolygon;

  @override
  void initState() {
    super.initState();
    // Default select the first property marker to show the bottom card initially
    _selectedProperty = widget.previewMarkers.firstOrNull;
    _currentPolygon.addAll(widget.initialPolygon);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _animatedMapMove(LatLng destLocation, double destZoom) {
    final camera = _mapController.camera;
    final latTween = Tween<double>(
        begin: camera.center.latitude, end: destLocation.latitude);
    final lngTween = Tween<double>(
        begin: camera.center.longitude, end: destLocation.longitude);
    final zoomTween = Tween<double>(begin: camera.zoom, end: destZoom);

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    final animation =
        CurvedAnimation(parent: controller, curve: Curves.fastOutSlowIn);

    controller.addListener(() {
      if (!mounted) return;
      _mapController.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    });

    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        controller.dispose();
      } else if (status == AnimationStatus.dismissed) {
        controller.dispose();
      }
    });

    controller.forward();
  }

  void _selectProperty(RentalProperty property) {
    setState(() {
      _selectedProperty = property;
    });
    _animatedMapMove(property.point, 13.5);

    // Scroll horizontal card slider to the selected card
    final index = widget.previewMarkers.indexWhere((p) => p.id == property.id);
    if (index != -1 && _scrollController.hasClients) {
      // 280 is card width + 12 is separation
      _scrollController.animateTo(
        index * (280.0 + 12.0),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  int _activePointers = 0;

  void _startLasso(PointerDownEvent event) {
    _activePointers++;
    if (!_drawMode || _activePointers > 1) {
      if (_activePointers > 1) {
        setState(() {
          _currentPolygon.clear();
        });
      }
      return;
    }
    final point =
        _mapController.camera.screenOffsetToLatLng(event.localPosition);
    setState(() {
      _currentPolygon
        ..clear()
        ..add(point);
      _lastDrawOffset = event.localPosition;
    });
  }

  void _updateLasso(PointerMoveEvent event) {
    if (!_drawMode || _activePointers > 1 || _lastDrawOffset == null) return;
    if ((event.localPosition - _lastDrawOffset!).distance < 10) return;
    final point =
        _mapController.camera.screenOffsetToLatLng(event.localPosition);
    setState(() {
      _currentPolygon.add(point);
      _lastDrawOffset = event.localPosition;
    });
  }

  void _finishLasso(PointerUpEvent event) {
    _activePointers = math.max(0, _activePointers - 1);
    if (!_drawMode) return;
    setState(() => _lastDrawOffset = null);
  }

  void _cancelLasso(PointerCancelEvent event) {
    _activePointers = math.max(0, _activePointers - 1);
    setState(() => _lastDrawOffset = null);
  }

  void _locateUser() {
    if (widget.previewMarkers.isNotEmpty) {
      _animatedMapMove(widget.previewMarkers.first.point, 13.5);
    } else {
      _animatedMapMove(widget.initialArea.center, 12.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final polygon = _activePolygon;
    final canSave = polygon.length >= 3;
    final hasProperties = widget.previewMarkers.isNotEmpty;
    final hasPolygon = polygon.length >= 3;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Flutter Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.initialArea.center,
              initialZoom: widget.initialArea.id == 'all_israel' ? 7.5 : 12.5,
              interactionOptions: InteractionOptions(
                flags: _drawMode
                    ? InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom
                    : InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.rentch.app',
              ),
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: widget.initialArea.polygon,
                    color: AppColors.navy.withValues(alpha: 0.04),
                    borderColor: AppColors.navy.withValues(alpha: 0.12),
                    borderStrokeWidth: 1.4,
                  ),
                  if (hasPolygon)
                    Polygon(
                      points: polygon,
                      color: AppColors.primary.withValues(alpha: 0.18),
                      borderColor: AppColors.primary,
                      borderStrokeWidth: 2.8,
                    ),
                ],
              ),
              // Markers Layer: Circular Image Thumbnails inspired by mockup
              MarkerLayer(
                markers: widget.previewMarkers.map(
                  (property) {
                    final isSelected = property.id == _selectedProperty?.id;
                    return Marker(
                      point: property.point,
                      width: isSelected ? 66 : 46,
                      height: isSelected ? 74 : 54,
                      child: GestureDetector(
                        onTap: () => _selectProperty(property),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: isSelected ? 60 : 40,
                              height: isSelected ? 60 : 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF2C64E3)
                                      : Colors.white,
                                  width: isSelected ? 3.0 : 2.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.16),
                                    blurRadius: isSelected ? 8 : 4,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: SafeMedia(
                                  media: property.primaryMedia,
                                  fallback: Container(
                                    color: AppColors.primaryLight2,
                                    child: RentchIcon(
                                      IconsaxPlusLinear.building,
                                      size: isSelected ? 22 : 14,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            if (isSelected)
                              CustomPaint(
                                size: const Size(10, 6),
                                painter: _TrianglePainter(
                                    color: const Color(0xFF2C64E3)),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ).toList(),
              ),
            ],
          ),

          // Lasso draw listener
          if (_drawMode)
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _startLasso,
                onPointerMove: _updateLasso,
                onPointerUp: _finishLasso,
                onPointerCancel: _cancelLasso,
              ),
            ),

          // Top Search Bar & Circular Control Buttons
          Positioned(
            top: 16 + MediaQuery.of(context).padding.top,
            left: 16,
            right: 16,
            child: Row(
              children: [
                // Back Button
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE2ECF1)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: AppColors.navy),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                // Filter Dropdown Button replacing Search Bar
                Expanded(
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      cardColor: Colors.white,
                    ),
                    child: PopupMenuButton<String>(
                      tooltip: 'סוגי סינון',
                      onSelected: (value) {
                        final provider =
                            Provider.of<DatingProvider>(context, listen: false);
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          useSafeArea: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => _FiltersSheet(provider: provider),
                        );
                      },
                      offset: const Offset(0, 56),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(color: Color(0xFFE2ECF1)),
                      ),
                      itemBuilder: (BuildContext context) => [
                        const PopupMenuItem<String>(
                          value: 'price',
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('תקציב',
                                  style: TextStyle(
                                      color: AppColors.navy,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5)),
                              SizedBox(width: 8),
                              Icon(Icons.monetization_on_outlined,
                                  color: AppColors.navy, size: 18),
                            ],
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'rooms',
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('חדרים',
                                  style: TextStyle(
                                      color: AppColors.navy,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5)),
                              SizedBox(width: 8),
                              Icon(Icons.meeting_room_outlined,
                                  color: AppColors.navy, size: 18),
                            ],
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'type',
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('סוג נכס',
                                  style: TextStyle(
                                      color: AppColors.navy,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5)),
                              SizedBox(width: 8),
                              Icon(Icons.home_work_outlined,
                                  color: AppColors.navy, size: 18),
                            ],
                          ),
                        ),
                        const PopupMenuItem<String>(
                          value: 'features',
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('מאפיינים',
                                  style: TextStyle(
                                      color: AppColors.navy,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5)),
                              SizedBox(width: 8),
                              Icon(Icons.star_border_rounded,
                                  color: AppColors.navy, size: 18),
                            ],
                          ),
                        ),
                        const PopupMenuDivider(),
                        const PopupMenuItem<String>(
                          value: 'all',
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text('הצג את כל המסננים',
                                  style: TextStyle(
                                      color: AppColors.navy,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13.5)),
                              SizedBox(width: 8),
                              Icon(Icons.tune_rounded,
                                  color: AppColors.navy, size: 18),
                            ],
                          ),
                        ),
                      ],
                      child: Container(
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
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            const RentchIcon(
                              IconsaxPlusLinear.setting_4,
                              size: 18,
                              color: AppColors.navy,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                widget.initialArea.id == 'all_israel'
                                    ? 'סנן לפי...'
                                    : 'סינון באזור ${widget.initialArea.name}',
                                style: const TextStyle(
                                  color: AppColors.navy,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: AppColors.navy,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Locate User Button
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE2ECF1)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.gps_fixed_rounded,
                        color: AppColors.navy),
                    onPressed: _locateUser,
                  ),
                ),
                const SizedBox(width: 8),
                // Lasso toggle Button
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _drawMode ? AppColors.primary : Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: Icon(
                      _drawMode
                          ? Icons.gesture_rounded
                          : Icons.gesture_outlined,
                      color: _drawMode ? Colors.white : AppColors.navy,
                    ),
                    onPressed: () {
                      setState(() {
                        _drawMode = !_drawMode;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          // Bottom Area: Floating Card and Save buttons
          // 1. Bottom Headers: Styled as premium tags/chips with liquid glass
          if (hasProperties)
            Positioned(
              left: 16,
              right: 16,
              bottom: 368 + MediaQuery.of(context).padding.bottom,
              child: GestureDetector(
                onTap: canSave
                    ? () => Navigator.of(context).pop(List<LatLng>.from(polygon))
                    : null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.38),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: const Text(
                            'דירות באזור המסומן',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.26),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Text(
                            '${widget.previewMarkers.length} תוצאות',
                            style: const TextStyle(
                              color: Colors.white, // Solid white text
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 2. Carousel: Spans 100% edge-to-edge of the screen
          if (hasProperties)
            Positioned(
              left: 0,
              right: 0,
              bottom: 60 + MediaQuery.of(context).padding.bottom,
              child: SizedBox(
                height: 300,
                child: ListView.separated(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: widget.previewMarkers.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final property = widget.previewMarkers[index];
                    final isSelected = property.id == _selectedProperty?.id;
                    return _PropertyPreviewCard(
                      property: property,
                      isSelected: isSelected,
                      onTap: () => _selectProperty(property),
                      onOpenDetails: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PropertyDetailScreen(property: property),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),

          // 3. Action buttons (Clear & Save) positioned at the bottom
          Positioned(
            left: 16,
            right: 16,
            bottom: 4 + MediaQuery.of(context).padding.bottom,
            child: Row(
              children: [
                // Clear Lasso Button (Liquid Glass)
                Expanded(
                  flex: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.24),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _currentPolygon.clear();
                              _lastDrawOffset = null;
                              _selectedProperty =
                                  widget.previewMarkers.firstOrNull;
                            });
                          },
                          icon: const Icon(Icons.refresh_rounded,
                              color: Colors.white, size: 18),
                          label: const Text(
                            'נקה',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Save Lasso Button (Vibrant sky blue/cyan when canSave is true)
                Expanded(
                  flex: 2,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: canSave
                              ? const Color(0xFF38B6FF)
                                  .withValues(alpha: 0.85) // Sky Blue / Cyan
                              : Colors.black.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: canSave
                                ? const Color(0xFF38B6FF).withValues(alpha: 0.4)
                                : Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: TextButton.icon(
                          onPressed: canSave
                              ? () => Navigator.of(context)
                                  .pop(List<LatLng>.from(polygon))
                              : null,
                          icon: Icon(
                            Icons.check_circle_outline_rounded,
                            color: canSave
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.4),
                            size: 18,
                          ),
                          label: Text(
                            'שמור אזור',
                            style: TextStyle(
                              color: canSave
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.4),
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Thumbnail ───────────────────────────────────────────────────────────────

class _PropertyThumb extends StatelessWidget {
  const _PropertyThumb({required this.media});

  final PropertyMedia? media;

  @override
  Widget build(BuildContext context) {
    return SafeMedia(
      media: media,
      fallback: _fallback(),
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
    );
  }

  Widget _fallback() => Container(
        color: AppColors.primaryLight2,
        child: const RentchIcon(
          IconsaxPlusLinear.building,
          size: 42,
          color: AppColors.primary,
        ),
      );
}

class _PropertyPreviewCard extends StatelessWidget {
  const _PropertyPreviewCard({
    required this.property,
    required this.isSelected,
    required this.onTap,
    required this.onOpenDetails,
  });

  final RentalProperty property;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final isRent = property.transactionType != PropertyTransactionType.sale;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: isSelected
                ? Colors.white.withValues(alpha: 0.35)
                : Colors.white.withValues(alpha: 0.08),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.1),
              blurRadius: isSelected ? 16 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(25),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Full background property image
              _PropertyThumb(media: property.primaryMedia),

              // Top-Left transaction type glassmorphic pill
              Positioned(
                top: 12,
                left: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      color: Colors.black.withValues(alpha: 0.45),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF00FF66),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isRent ? 'להשכרה' : 'למכירה',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Top-Right details open icon button
              Positioned(
                top: 12,
                right: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: GestureDetector(
                      onTap: onOpenDetails,
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: 0.4),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        child: const Icon(
                          Icons.favorite_border_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom Glassmorphic Panel
              Positioned(
                bottom: 10,
                left: 10,
                right: 10,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      color: Colors.black
                          .withValues(alpha: 0.17), // 17% opacity base
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Price row with arrow
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    property.priceLabel,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  Text(
                                    property.priceSuffixLabel,
                                    style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.6),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              GestureDetector(
                                onTap: onOpenDetails,
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white.withValues(alpha: 0.16),
                                    border: Border.all(
                                        color: Colors.white
                                            .withValues(alpha: 0.2)),
                                  ),
                                  child: const Icon(
                                    Icons.arrow_forward_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Address row
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                color: Colors.white.withValues(alpha: 0.7),
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  property.address,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Spec pills
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _buildSpecPill(
                                icon: Icons.meeting_room_outlined,
                                label: '${property.roomsLabel} חדרים',
                              ),
                              _buildSpecPill(
                                icon: Icons.crop_free_rounded,
                                label: '${property.sizeM2} מ״ר',
                              ),
                              _buildSpecPill(
                                icon: Icons.layers_outlined,
                                label: property.floor.isEmpty
                                    ? 'קרקע'
                                    : 'קומה ${property.floor}',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSpecPill({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.8), size: 11),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
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
            RentchIcon(IconsaxPlusLinear.undo,
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
              child: const RentchIcon(
                IconsaxPlusLinear.search_normal,
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
              icon: IconsaxPlusLinear.undo,
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

String _compactPriceLabel(int value) {
  if (value >= 1000000) {
    final millions = value / 1000000;
    final formatted = millions >= 10
        ? millions.toStringAsFixed(0)
        : millions.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
    return '₪${formatted}M';
  }
  if (value >= 100000) {
    return '₪${(value / 1000).round()}K';
  }
  return _formatCurrency(value);
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

class _LocationSuggestion {
  const _LocationSuggestion._({
    required this.label,
    required this.icon,
    required this.caption,
    required this.isCity,
    this.area,
  });

  factory _LocationSuggestion.city(String city) {
    return _LocationSuggestion._(
      label: city,
      icon: IconsaxPlusLinear.building,
      caption: 'עיר',
      isCity: true,
    );
  }

  factory _LocationSuggestion.area(SearchArea area) {
    return _LocationSuggestion._(
      label: area.name,
      icon: IconsaxPlusLinear.location,
      caption: 'אזור',
      isCity: false,
      area: area,
    );
  }

  final String label;
  final IconData icon;
  final String caption;
  final bool isCity;
  final SearchArea? area;
}

class _LocationSuggestionTile extends StatelessWidget {
  const _LocationSuggestionTile({
    required this.suggestion,
    required this.isSelected,
    required this.onTap,
    required this.showDivider,
  });

  final _LocationSuggestion suggestion;
  final bool isSelected;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final titleColor = isSelected ? AppColors.primary : AppColors.navy;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryLight2 : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.14)
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    suggestion.icon,
                    color: titleColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.label,
                        style: TextStyle(
                          color: titleColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        suggestion.caption,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isSelected
                      ? IconsaxPlusLinear.tick_circle
                      : IconsaxPlusLinear.arrow_left_2,
                  color:
                      isSelected ? AppColors.primary : AppColors.textSecondary,
                  size: 18,
                ),
              ],
            ),
            if (showDivider)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Divider(height: 1, color: AppColors.borderLight),
              ),
          ],
        ),
      ),
    );
  }
}

String _priceFilterLabel() => 'טווח מחיר';

/// Display label for the size range slider.
/// When maxSizeM2 is at or above the slider ceiling (2000) or "unlimited",
/// we show a "2,000+ מ"ר" label instead of the raw large number.
String _sizeDisplayValue(int minSizeM2, int maxSizeM2) {
  final minStr = minSizeM2 == 0 ? '0' : '$minSizeM2';
  if (maxSizeM2 >= 1000000) {
    return minSizeM2 == 0 ? 'ללא הגבלה' : '$minStr+ מ"ר';
  }
  if (maxSizeM2 >= 2000) {
    return '$minStr - 2,000+ מ"ר';
  }
  return '$minStr - $maxSizeM2 מ"ר';
}

double _priceSliderMin(TransactionTypeFilter type) {
  switch (type) {
    case TransactionTypeFilter.any:
      return 600;
    case TransactionTypeFilter.rent:
      return 600;
    case TransactionTypeFilter.sale:
      return 100000;
  }
}

double _priceSliderMax(TransactionTypeFilter type) {
  switch (type) {
    case TransactionTypeFilter.any:
      return 40000;
    case TransactionTypeFilter.rent:
      return 40000;
    case TransactionTypeFilter.sale:
      return 10000000;
  }
}

int _priceSliderDivisions(TransactionTypeFilter type) {
  switch (type) {
    case TransactionTypeFilter.any:
      return 197;
    case TransactionTypeFilter.rent:
      return 197;
    case TransactionTypeFilter.sale:
      return 99;
  }
}

int _roundedPriceForTransaction(TransactionTypeFilter type, double value) {
  switch (type) {
    case TransactionTypeFilter.any:
      return (value / 200).round() * 200;
    case TransactionTypeFilter.rent:
      return (value / 200).round() * 200;
    case TransactionTypeFilter.sale:
      return (value / 100000).round() * 100000;
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
      return IconsaxPlusLinear.star;
  }
}

IconData _propertyTypeIcon(String type) {
  final lower = type.trim().toLowerCase();
  if (lower.contains('גג') ||
      lower.contains('פנטהאוז') ||
      lower.contains('דופלקס')) {
    return IconsaxPlusLinear.buildings;
  }
  if (lower.contains('גן') || lower.contains('חצר') || lower.contains('גינה')) {
    return IconsaxPlusLinear.map_1;
  }
  if (lower.contains('בית') ||
      lower.contains('קוטג') ||
      lower.contains('יחידת') ||
      lower.contains('סטודיו')) {
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
  if (lower.contains('ממ"ד') || lower.contains('ממד')) {
    return IconsaxPlusLinear.shield_tick;
  }
  if (lower.contains('מזגן') || lower.contains('מיזוג')) {
    return IconsaxPlusLinear.layer;
  }
  if (lower.contains('מרפסת')) return IconsaxPlusLinear.layer;
  if (lower.contains('מחסן')) return IconsaxPlusLinear.lock;
  if (lower.contains('ריהוט') || lower.contains('מרוהטת')) {
    return IconsaxPlusLinear.home;
  }
  if (lower.contains('חיות')) return IconsaxPlusLinear.heart;
  if (lower.contains('סורגים')) return IconsaxPlusLinear.lock;
  if (lower.contains('נגישות')) return IconsaxPlusLinear.profile_circle;
  if (lower.contains('גינה') || lower.contains('חצר')) {
    return IconsaxPlusLinear.map;
  }
  if (lower.contains('שומר') || lower.contains('אבטחה')) {
    return IconsaxPlusLinear.shield_tick;
  }
  if (lower.contains('משופצת') || lower.contains('משופץ')) {
    return IconsaxPlusLinear.setting_4;
  }
  return IconsaxPlusLinear.hashtag;
}

class _FilterLocationPill extends StatelessWidget {
  const _FilterLocationPill({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.navy : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected ? AppColors.navy : const Color(0xFFE2ECF1),
            width: 1,
          ),
        ),
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

class _CustomRangeSliderThumbShape extends RangeSliderThumbShape {
  const _CustomRangeSliderThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isPressed) {
    return const Size(28, 28);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    bool isDiscrete = false,
    bool isEnabled = true,
    bool isOnTop = false,
    bool isPressed = false,
    required SliderThemeData sliderTheme,
    TextDirection? textDirection,
    Thumb? thumb,
  }) {
    final Canvas canvas = context.canvas;

    final Path shadowPath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: 14));
    canvas.drawShadow(shadowPath, Colors.black, 4, true);

    final Paint fillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 13, fillPaint);

    final Paint borderPaint = Paint()
      ..color = AppColors.navy
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, 13, borderPaint);

    final Paint linePaint = Paint()
      ..color = AppColors.navy
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(center.dx - 5, center.dy - 2),
        Offset(center.dx + 5, center.dy - 2), linePaint);
    canvas.drawLine(Offset(center.dx - 5, center.dy + 2),
        Offset(center.dx + 5, center.dy + 2), linePaint);
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({
    required this.label,
    required this.price,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final String price;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.navy : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppColors.navy : AppColors.borderLight,
              width: isSelected ? 1.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: AppColors.navy.withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.7)
                            : AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (isSelected)
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 11,
                        color: Colors.white,
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight2,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'חי',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                price,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.2,
                  fontWeight: FontWeight.w900,
                  color: isSelected ? Colors.white : AppColors.navy,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PriceHistogram extends StatelessWidget {
  const _PriceHistogram({
    required this.minBudget,
    required this.maxBudget,
    required this.sliderMin,
    required this.sliderMax,
  });

  final double minBudget;
  final double maxBudget;
  final double sliderMin;
  final double sliderMax;

  @override
  Widget build(BuildContext context) {
    const heights = [
      10,
      15,
      25,
      30,
      20,
      35,
      50,
      45,
      60,
      55,
      40,
      30,
      25,
      18,
      12,
      8
    ];
    final n = heights.length;
    final range = sliderMax - sliderMin;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(n, (i) {
          final price = sliderMin + (i / (n - 1)) * range;
          final inRange = price >= minBudget && price <= maxBudget;
          return Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              height: heights[i].toDouble(),
              decoration: BoxDecoration(
                color: inRange ? AppColors.primary : const Color(0xFFE2ECF1),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _PriceInputCard extends StatelessWidget {
  const _PriceInputCard({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2ECF1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleSelectorButton extends StatelessWidget {
  const _CircleSelectorButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? AppColors.primary : const Color(0xFFE2ECF1),
            width: 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.24),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : AppColors.navy,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _PropertyTypeCard extends StatelessWidget {
  const _PropertyTypeCard({
    required this.label,
    required this.state,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final FilterPriority state;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isPreferred = state == FilterPriority.preferred;
    final bool isRequired = state == FilterPriority.required;
    final bool isActive = isPreferred || isRequired;

    final Color bgColor = isRequired
        ? AppColors.primary
        : (isPreferred ? AppColors.navy : const Color(0xFFF7F9FA));
    final Color iconBgColor =
        isActive ? Colors.white24 : const Color(0xFFE2ECF1);
    final Color labelColor = isActive ? Colors.white : AppColors.navy;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 108,
        height: 108,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isActive ? bgColor : const Color(0xFFE2ECF1),
            width: 1.5,
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: bgColor.withValues(alpha: 0.28),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: iconBgColor,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 16,
                    color: labelColor,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: labelColor,
                  ),
                ),
              ],
            ),
            if (isActive)
              Positioned(
                top: 0,
                left: 0,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: isRequired ? AppColors.coral : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isRequired
                          ? AppColors.coral
                          : Colors.white.withValues(alpha: 0.6),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    isRequired
                        ? Icons.priority_high_rounded
                        : Icons.check_rounded,
                    size: 12,
                    color: isRequired ? Colors.white : AppColors.primary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FeatureTag extends StatelessWidget {
  const _FeatureTag({
    required this.label,
    required this.state,
    required this.onClear,
  });

  final String label;
  final FilterPriority state;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final bool isRequired = state == FilterPriority.required;
    final Color accent = isRequired ? AppColors.coral : AppColors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.30), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isRequired ? Icons.priority_high_rounded : Icons.favorite_rounded,
            size: 11,
            color: accent,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(width: 5),
          GestureDetector(
            onTap: onClear,
            child: Icon(
              Icons.close,
              size: 13,
              color: accent.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  _TrianglePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
