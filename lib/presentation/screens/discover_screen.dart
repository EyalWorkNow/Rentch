import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/features/discover/action_button.dart';
import 'package:dating_app/presentation/features/discover/profile_card.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:dating_app/presentation/widgets/gamification/fomo_widgets.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
            centerTitle: false,
            title: SvgPicture.asset(
              'assets/images/rentch_logo.svg',
              height: 40,
              width: 40,
              fit: BoxFit.contain,
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
                    const Icon(IconsaxPlusBold.setting_4,
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
                                      return Stack(
                                        children: [
                                          ProfileCard(
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
          child: Icon(
            IconsaxPlusBold.building,
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
  late final TextEditingController _queryCtrl;
  late final TextEditingController _locationCtrl;
  Timer? _previewDebounce;
  late SearchFilters _draftFilters;
  late final String _initialFiltersKey;
  late int _visibleCount;
  late List<RentalProperty> _markerPreview;
  bool _didCommit = false;

  @override
  void initState() {
    super.initState();
    _draftFilters = widget.provider.filters;
    _initialFiltersKey = _filtersKey(_draftFilters);
    final currentProperties = widget.provider.filteredProperties;
    _visibleCount = currentProperties.length;
    _markerPreview = currentProperties.take(18).toList();
    _queryCtrl = TextEditingController(text: widget.provider.filters.query);
    _locationCtrl = TextEditingController(text: widget.provider.filters.city);
  }

  @override
  void dispose() {
    _commitDraftIfNeeded();
    _previewDebounce?.cancel();
    _queryCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value, DatingProvider provider) {
    _setDraftFilters(_draftFilters.copyWith(query: value), provider);
  }

  void _setDraftFilters(SearchFilters filters, DatingProvider provider) {
    setState(() => _draftFilters = filters);
    _schedulePreviewRefresh(provider);
  }

  void _schedulePreviewRefresh(DatingProvider provider) {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 160), () {
      if (!mounted) return;
      final count = provider.filteredCountFor(_draftFilters);
      final markers = provider.previewFilteredProperties(_draftFilters);
      if (!mounted) return;
      setState(() {
        _visibleCount = count;
        _markerPreview = markers;
      });
    });
  }

  String _filtersKey(SearchFilters filters) {
    return jsonEncode({
      ...filters.toJson(),
      'requiredFeatures': filters.requiredFeatures.toList()..sort(),
      'preferredFeatures': filters.preferredFeatures.toList()..sort(),
      'propertyTypes': filters.propertyTypes.toList()..sort(),
      'conditions': filters.conditions.toList()..sort(),
    });
  }

  bool get _hasPendingChanges => _filtersKey(_draftFilters) != _initialFiltersKey;

  void _commitDraftIfNeeded() {
    if (_didCommit || !_hasPendingChanges) return;
    _didCommit = true;
    unawaited(widget.provider.updateFilters(_draftFilters));
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
            onSubmitted: (submitted) => Navigator.of(dialogContext).pop(submitted),
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

  void _resetFilters(DatingProvider provider) {
    const resetFilters = SearchFilters(
      query: '',
      maxBudget: 2000000000,
      minRooms: 0,
      areaId: 'all_israel',
      requiredFeatures: <String>{},
      preferredFeatures: <String>{},
      minSizeM2: 0,
      maxSizeM2: 1000000,
      propertyTypes: <String>{},
      conditions: <String>{},
      listingSource: ListingSourceFilter.any,
      minFloor: 0,
      moveInFilter: MoveInFilter.any,
      sortBy: SearchSortOption.bestMatch,
      city: '',
      transactionType: TransactionTypeFilter.any,
    );
    setState(() {
      _queryCtrl.clear();
      _locationCtrl.clear();
      _draftFilters = resetFilters;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    _schedulePreviewRefresh(provider);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final f = _draftFilters;
        final area = provider.searchAreas.firstWhere(
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
                const SizedBox(height: 14),
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      const Icon(IconsaxPlusBold.setting_4,
                          size: 22, color: AppColors.navy),
                      const SizedBox(width: 8),
                      const Text(
                        'סינון',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$_visibleCount דירות',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _resetFilters(provider),
                        icon: const Icon(IconsaxPlusBold.refresh, size: 15),
                        label: const Text('אפס'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.coral,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Single search field
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: _queryCtrl,
                    textDirection: TextDirection.rtl,
                    onChanged: (v) {
                      setState(() {});
                      _onQueryChanged(v, provider);
                    },
                    decoration: InputDecoration(
                      hintText: 'חפש עיר, שכונה, סוג נכס...',
                      prefixIcon: const Icon(IconsaxPlusBold.search_normal),
                      suffixIcon: _queryCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(IconsaxPlusBold.close_circle),
                              onPressed: () {
                                setState(() => _queryCtrl.clear());
                                _setDraftFilters(
                                  f.copyWith(query: ''),
                                  provider,
                                );
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
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
                          title: 'מטרה', icon: IconsaxPlusBold.category),
                      const SizedBox(height: 10),
                      Row(
                        children: TransactionTypeFilter.values.map((type) {
                          final selected = f.transactionType == type;
                          return Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              child: ChoiceChip(
                                selected: selected,
                                label: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(_transactionTypeIcon(type),
                                        size: 15,
                                        color: selected
                                            ? Colors.white
                                            : AppColors.navy),
                                    const SizedBox(width: 5),
                                    Flexible(
                                      child: Text(
                                        _transactionTypeLabel(type),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                labelStyle: TextStyle(
                                  color:
                                      selected ? Colors.white : AppColors.navy,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                                selectedColor: AppColors.primary,
                                backgroundColor: AppColors.primaryLight2,
                                side: BorderSide(
                                    color: selected
                                        ? AppColors.primary
                                        : AppColors.borderLight),
                                showCheckmark: false,
                                onSelected: (_) => _setDraftFilters(
                                  f.copyWith(
                                    transactionType: type,
                                    maxBudget: _priceResetForTransaction(
                                        type, f.maxBudget),
                                  ),
                                  provider,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      // ── תקציב ──
                      _SliderField(
                        label: _priceFilterLabel(f.transactionType),
                        icon: IconsaxPlusBold.money,
                        value: f.maxBudget.toDouble(),
                        min: _priceSliderMin(f.transactionType),
                        max: _priceSliderMax(f.transactionType),
                        divisions: _priceSliderDivisions(f.transactionType),
                        displayValue: _formatCurrency(f.maxBudget),
                        onValueTap: () => _editSliderValue(
                          context: context,
                          title: _priceFilterLabel(f.transactionType),
                          initialValue: f.maxBudget.toString(),
                          suffix: '₪',
                          keyboardType: TextInputType.number,
                          onSubmitted: (raw) {
                            final parsed = int.tryParse(
                              raw.replaceAll(RegExp(r'[^0-9]'), ''),
                            );
                            if (parsed == null) return;
                            final clamped = _roundedPriceForTransaction(
                              f.transactionType,
                              parsed
                                  .clamp(
                                    _priceSliderMin(f.transactionType).round(),
                                    _priceSliderMax(f.transactionType).round(),
                                  )
                                  .toDouble(),
                            );
                            _setDraftFilters(
                              f.copyWith(maxBudget: clamped),
                              provider,
                            );
                          },
                        ),
                        onChanged: (v) => _setDraftFilters(
                          f.copyWith(
                            maxBudget: _roundedPriceForTransaction(
                              f.transactionType,
                              v,
                            ),
                          ),
                          provider,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // ── חדרים ──
                      _SliderField(
                        label: 'מינימום חדרים',
                        icon: IconsaxPlusBold.home,
                        value: f.minRooms,
                        min: 0,
                        max: 6,
                        divisions: 12,
                        displayValue: f.minRooms == 0
                            ? 'ללא הגבלה'
                            : f.minRooms % 1 == 0
                                ? f.minRooms.toInt().toString()
                                : '${f.minRooms}',
                        onValueTap: () => _editSliderValue(
                          context: context,
                          title: 'מינימום חדרים',
                          initialValue: f.minRooms == 0 ? '' : '${f.minRooms}',
                          suffix: '',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onSubmitted: (raw) {
                            final normalized = raw.trim().replaceAll(',', '.');
                            final parsed = normalized.isEmpty
                                ? 0.0
                                : double.tryParse(normalized);
                            if (parsed == null) return;
                            final clamped =
                                ((parsed.clamp(0, 6) * 2).round() / 2).toDouble();
                            _setDraftFilters(
                              f.copyWith(minRooms: clamped),
                              provider,
                            );
                          },
                        ),
                        onChanged: (v) => _setDraftFilters(
                          f.copyWith(minRooms: (v * 2).round() / 2),
                          provider,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // ── מיקום (עיר + אזור) ──
                      _FilterSection(
                        title: 'מיקום',
                        icon: IconsaxPlusBold.location,
                        action: (f.city.isNotEmpty || f.areaId != 'all_israel')
                            ? TextButton(
                                onPressed: () {
                                  setState(() => _locationCtrl.clear());
                                  _setDraftFilters(
                                    f.copyWith(city: '', areaId: 'all_israel'),
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
                      TextField(
                        controller: _locationCtrl,
                        textDirection: TextDirection.rtl,
                        onChanged: (v) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'חפש עיר או אזור',
                          prefixIcon: const Icon(IconsaxPlusBold.search_normal),
                          suffixIcon: _locationCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon:
                                      const Icon(IconsaxPlusBold.close_circle),
                                  onPressed: () {
                                    setState(() => _locationCtrl.clear());
                                    _setDraftFilters(
                                      f.copyWith(city: '', areaId: 'all_israel'),
                                      provider,
                                    );
                                  },
                                )
                              : null,
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
                                        ),
                                        provider,
                                      );
                                      return;
                                    }
                                    _setDraftFilters(
                                      f.copyWith(
                                        city: '',
                                        areaId: suggestion.area!.id,
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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: SizedBox(
                          height: 160,
                          child: FlutterMap(
                            key: ValueKey('${f.areaId}-${f.city}'),
                            options: MapOptions(
                              initialCenter: area.center,
                              initialZoom: area.id == 'all_israel' ? 7.5 : 11,
                              interactionOptions: const InteractionOptions(
                                  flags: InteractiveFlag.none),
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
                                          child: const Icon(
                                              IconsaxPlusBold.building,
                                              color: AppColors.primary,
                                              size: 22),
                                        ))
                                    .toList(),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      // ── מיון ──
                      _FilterSection(title: 'מיון', icon: IconsaxPlusBold.sort),
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
                                Icon(_sortIcon(option),
                                    size: 13,
                                    color: selected
                                        ? Colors.white
                                        : AppColors.navy),
                                const SizedBox(width: 4),
                                Text(_sortLabel(option)),
                              ],
                            ),
                            labelStyle: TextStyle(
                              color: selected ? Colors.white : AppColors.navy,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                            selectedColor: AppColors.primary,
                            backgroundColor: AppColors.primaryLight2,
                            side: BorderSide(
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.borderLight),
                            showCheckmark: false,
                            onSelected: (_) => _setDraftFilters(
                              f.copyWith(sortBy: option),
                              provider,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      // ── גודל ──
                      _SliderField(
                        label: 'גודל מינימלי',
                        icon: IconsaxPlusBold.maximize_4,
                        value: f.minSizeM2.toDouble(),
                        min: 0,
                        max: 250,
                        divisions: 25,
                        displayValue: '${f.minSizeM2.round()} מ"ר',
                        onValueTap: () => _editSliderValue(
                          context: context,
                          title: 'גודל מינימלי',
                          initialValue: f.minSizeM2.toString(),
                          suffix: 'מ"ר',
                          keyboardType: TextInputType.number,
                          onSubmitted: (raw) {
                            final parsed = int.tryParse(
                              raw.replaceAll(RegExp(r'[^0-9]'), ''),
                            );
                            if (parsed == null) return;
                            final minSize = parsed.clamp(0, 250);
                            final maxSize =
                                f.maxSizeM2 < minSize ? minSize : f.maxSizeM2;
                            _setDraftFilters(
                              f.copyWith(
                                minSizeM2: minSize,
                                maxSizeM2: maxSize,
                              ),
                              provider,
                            );
                          },
                        ),
                        onChanged: (value) {
                          final minSize = value.round();
                          final maxSize =
                              f.maxSizeM2 < minSize ? minSize : f.maxSizeM2;
                          _setDraftFilters(
                            f.copyWith(
                              minSizeM2: minSize,
                              maxSizeM2: maxSize,
                            ),
                            provider,
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      _SliderField(
                        label: 'גודל מקסימלי',
                        icon: IconsaxPlusBold.maximize_4,
                        value: f.maxSizeM2.toDouble(),
                        min: 20,
                        max: 1000000,
                        divisions: 100,
                        displayValue: f.maxSizeM2 >= 1000000
                            ? 'ללא הגבלה'
                            : '${f.maxSizeM2.round()} מ"ר',
                        onValueTap: () => _editSliderValue(
                          context: context,
                          title: 'גודל מקסימלי',
                          initialValue: f.maxSizeM2 >= 1000000
                              ? ''
                              : f.maxSizeM2.toString(),
                          suffix: 'מ"ר',
                          keyboardType: TextInputType.number,
                          onSubmitted: (raw) {
                            final parsed = raw.trim().isEmpty
                                ? 1000000
                                : int.tryParse(
                                    raw.replaceAll(RegExp(r'[^0-9]'), ''),
                                  );
                            if (parsed == null) return;
                            final maxSize = parsed.clamp(20, 1000000);
                            final minSize =
                                f.minSizeM2 > maxSize ? maxSize : f.minSizeM2;
                            _setDraftFilters(
                              f.copyWith(
                                minSizeM2: minSize,
                                maxSizeM2: maxSize,
                              ),
                              provider,
                            );
                          },
                        ),
                        onChanged: (value) {
                          final maxSize = value.round();
                          final minSize =
                              f.minSizeM2 > maxSize ? maxSize : f.minSizeM2;
                          _setDraftFilters(
                            f.copyWith(
                              minSizeM2: minSize,
                              maxSizeM2: maxSize,
                            ),
                            provider,
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      // ── קומה ──
                      _SliderField(
                        label: 'קומה מינימלית',
                        icon: IconsaxPlusBold.building,
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
                              f.copyWith(minFloor: parsed.clamp(0, 30)),
                              provider,
                            );
                          },
                        ),
                        onChanged: (value) => _setDraftFilters(
                          f.copyWith(minFloor: value.round()),
                          provider,
                        ),
                      ),
                      const SizedBox(height: 20),
                      // ── סוג נכס ──
                      _FilterSection(
                          title: 'סוג נכס', icon: IconsaxPlusBold.building),
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
                                Icon(_propertyTypeIcon(type),
                                    size: 13,
                                    color: selected
                                        ? Colors.white
                                        : AppColors.navy),
                                const SizedBox(width: 4),
                                Text(type),
                              ],
                            ),
                            labelStyle: TextStyle(
                              color: selected ? Colors.white : AppColors.navy,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                            selectedColor: AppColors.primary,
                            backgroundColor: AppColors.primaryLight2,
                            side: BorderSide(
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.borderLight),
                            showCheckmark: false,
                            onSelected: (value) {
                              final types = {...f.propertyTypes};
                              if (value) {
                                types.add(type);
                              } else {
                                types.remove(type);
                              }
                              _setDraftFilters(
                                f.copyWith(propertyTypes: types),
                                provider,
                              );
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      // ── מצב הנכס ──
                      _FilterSection(
                          title: 'מצב הנכס', icon: IconsaxPlusBold.shield_tick),
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
                                Icon(IconsaxPlusBold.shield_tick,
                                    size: 13,
                                    color: selected
                                        ? Colors.white
                                        : AppColors.navy),
                                const SizedBox(width: 4),
                                Text(condition),
                              ],
                            ),
                            labelStyle: TextStyle(
                              color: selected ? Colors.white : AppColors.navy,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                            selectedColor: AppColors.primary,
                            backgroundColor: AppColors.primaryLight2,
                            side: BorderSide(
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.borderLight),
                            showCheckmark: false,
                            onSelected: (value) {
                              final conds = {...f.conditions};
                              if (value) {
                                conds.add(condition);
                              } else {
                                conds.remove(condition);
                              }
                              _setDraftFilters(
                                f.copyWith(conditions: conds),
                                provider,
                              );
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      // ── מקור מודעה ──
                      _FilterSection(
                          title: 'מקור מודעה',
                          icon: IconsaxPlusBold.profile_2user),
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
                                Icon(_listingSourceIcon(source),
                                    size: 13,
                                    color: selected
                                        ? Colors.white
                                        : AppColors.navy),
                                const SizedBox(width: 4),
                                Text(_listingSourceLabel(source)),
                              ],
                            ),
                            labelStyle: TextStyle(
                              color: selected ? Colors.white : AppColors.navy,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                            selectedColor: AppColors.primary,
                            backgroundColor: AppColors.primaryLight2,
                            side: BorderSide(
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.borderLight),
                            showCheckmark: false,
                            onSelected: (_) => _setDraftFilters(
                              f.copyWith(listingSource: source),
                              provider,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      // ── מועד כניסה ──
                      _FilterSection(
                          title: 'מועד כניסה',
                          icon: IconsaxPlusBold.calendar_1),
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
                                Icon(IconsaxPlusBold.calendar_1,
                                    size: 13,
                                    color: selected
                                        ? Colors.white
                                        : AppColors.navy),
                                const SizedBox(width: 4),
                                Text(_moveInLabel(option)),
                              ],
                            ),
                            labelStyle: TextStyle(
                              color: selected ? Colors.white : AppColors.navy,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                            selectedColor: AppColors.primary,
                            backgroundColor: AppColors.primaryLight2,
                            side: BorderSide(
                                color: selected
                                    ? AppColors.primary
                                    : AppColors.borderLight),
                            showCheckmark: false,
                            onSelected: (_) => _setDraftFilters(
                              f.copyWith(moveInFilter: option),
                              provider,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      // ── מאפיינים ──
                      _FilterSection(
                          title: 'מאפיינים חשובים',
                          icon: IconsaxPlusBold.filter,
                          action: _FeatureTagLegend()),
                      const SizedBox(height: 6),
                      // Legend hint
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            _TagStateDot(color: AppColors.primary),
                            const SizedBox(width: 4),
                            Text('מועדף',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(width: 12),
                            _TagStateDot(color: AppColors.coral),
                            const SizedBox(width: 4),
                            Text('חייב להיות (deal breaker)',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            provider.availableFeatures.take(16).map((feature) {
                          final state = f.featureState(feature);
                          return _TriStateFeatureChip(
                            feature: feature,
                            state: state,
                            icon: _featureIcon(feature),
                            onTap: () {
                              _setDraftFilters(
                                f.cycleFeature(feature),
                                provider,
                              );
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () {
                          _didCommit = true;
                          unawaited(provider.updateFilters(_draftFilters));
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(IconsaxPlusBold.tick_circle),
                        label: Text(
                            'הצג $_visibleCount דירות'),
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

/// Small colored dot used in the legend row.
class _TagStateDot extends StatelessWidget {
  const _TagStateDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Empty widget placeholder (legend is inline now).
class _FeatureTagLegend extends StatelessWidget {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Tri-state feature chip: none → preferred (blue) → dealBreaker (red) → none.
///
/// Cycle on tap — each state has its own color, icon, and border.
class _TriStateFeatureChip extends StatelessWidget {
  const _TriStateFeatureChip({
    required this.feature,
    required this.state,
    required this.icon,
    required this.onTap,
  });

  final String feature;
  final FeatureTagState state;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color bgColor;
    final Color textColor;
    final Color borderColor;
    final IconData? trailingIcon;

    switch (state) {
      case FeatureTagState.none:
        bgColor     = AppColors.primaryLight2;
        textColor   = AppColors.navy;
        borderColor = AppColors.borderLight;
        trailingIcon = null;
      case FeatureTagState.preferred:
        bgColor     = AppColors.primary;
        textColor   = Colors.white;
        borderColor = AppColors.primary;
        trailingIcon = Icons.favorite_rounded; // heart — nice to have
      case FeatureTagState.dealBreaker:
        bgColor     = AppColors.coral;
        textColor   = Colors.white;
        borderColor = AppColors.coral;
        trailingIcon = Icons.priority_high_rounded; // exclamation — must have
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: state != FeatureTagState.none
              ? [
                  BoxShadow(
                    color: bgColor.withValues(alpha: 0.35),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: textColor),
            const SizedBox(width: 4),
            Text(
              feature,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 4),
              Icon(trailingIcon, size: 11, color: textColor.withValues(alpha: 0.85)),
            ],
          ],
        ),
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
                      const Icon(
                        IconsaxPlusBold.edit_2,
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
              icon: IconsaxPlusBold.money,
              label: 'הרחב תקציב ב-₪500',
              onTap: () => provider.updateFilters(
                provider.filters.copyWith(
                  maxBudget: provider.filters.maxBudget + 500,
                ),
              ),
            ),
            const SizedBox(height: 10),
            _QuickActionBtn(
              icon: IconsaxPlusBold.home,
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
              icon: IconsaxPlusBold.maximize_4,
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
      icon: IconsaxPlusBold.building,
      caption: 'עיר',
      isCity: true,
    );
  }

  factory _LocationSuggestion.area(SearchArea area) {
    return _LocationSuggestion._(
      label: area.name,
      icon: IconsaxPlusBold.location,
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
                      ? IconsaxPlusBold.tick_circle
                      : IconsaxPlusBold.arrow_left_2,
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

String _transactionTypeLabel(TransactionTypeFilter type) {
  switch (type) {
    case TransactionTypeFilter.any:
      return 'הכל';
    case TransactionTypeFilter.rent:
      return 'השכרה';
    case TransactionTypeFilter.sale:
      return 'מכירה';
  }
}

IconData _transactionTypeIcon(TransactionTypeFilter type) {
  switch (type) {
    case TransactionTypeFilter.any:
      return IconsaxPlusBold.category;
    case TransactionTypeFilter.rent:
      return IconsaxPlusBold.key;
    case TransactionTypeFilter.sale:
      return IconsaxPlusBold.receipt_2;
  }
}

String _priceFilterLabel(TransactionTypeFilter type) {
  switch (type) {
    case TransactionTypeFilter.any:
      return 'מחיר מקסימלי';
    case TransactionTypeFilter.rent:
      return 'תקציב שכירות מקסימלי';
    case TransactionTypeFilter.sale:
      return 'מחיר קנייה מקסימלי';
  }
}

int? _priceResetForTransaction(TransactionTypeFilter type, int currentBudget) {
  if (type == TransactionTypeFilter.any) {
    return 2000000000;
  }
  if (type == TransactionTypeFilter.sale &&
      (currentBudget <= 100000 || currentBudget > 10000000)) {
    return 10000000;
  }
  if (type == TransactionTypeFilter.rent &&
      (currentBudget < 3000 || currentBudget > 18000)) {
    return 9000;
  }
  return null;
}

double _priceSliderMin(TransactionTypeFilter type) {
  switch (type) {
    case TransactionTypeFilter.any:
      return 0;
    case TransactionTypeFilter.rent:
      return 3000;
    case TransactionTypeFilter.sale:
      return 500000;
  }
}

double _priceSliderMax(TransactionTypeFilter type) {
  switch (type) {
    case TransactionTypeFilter.any:
      return 2000000000;
    case TransactionTypeFilter.rent:
      return 18000;
    case TransactionTypeFilter.sale:
      return 10000000;
  }
}

int _priceSliderDivisions(TransactionTypeFilter type) {
  switch (type) {
    case TransactionTypeFilter.any:
      return 200;
    case TransactionTypeFilter.rent:
      return 150;
    case TransactionTypeFilter.sale:
      return 95;
  }
}

int _roundedPriceForTransaction(TransactionTypeFilter type, double value) {
  switch (type) {
    case TransactionTypeFilter.any:
      return (value / 10000000).round() * 10000000;
    case TransactionTypeFilter.rent:
      return (value / 100).round() * 100;
    case TransactionTypeFilter.sale:
      return (value / 50000).round() * 50000;
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
      return IconsaxPlusBold.sort;
    case SearchSortOption.priceHighToLow:
      return IconsaxPlusBold.sort;
    case SearchSortOption.newestEntry:
      return IconsaxPlusBold.calendar;
    case SearchSortOption.biggestFirst:
      return IconsaxPlusBold.maximize_3;
    case SearchSortOption.bestMatch:
      return IconsaxPlusBold.star;
  }
}

IconData _propertyTypeIcon(String type) {
  final lower = type.trim().toLowerCase();
  if (lower.contains('גג') ||
      lower.contains('פנטהאוז') ||
      lower.contains('דופלקס')) {
    return IconsaxPlusBold.buildings;
  }
  if (lower.contains('גן') || lower.contains('חצר') || lower.contains('גינה')) {
    return IconsaxPlusBold.map_1;
  }
  if (lower.contains('בית') ||
      lower.contains('קוטג') ||
      lower.contains('יחידת') ||
      lower.contains('סטודיו')) {
    return IconsaxPlusBold.home;
  }
  return IconsaxPlusBold.building;
}

IconData _listingSourceIcon(ListingSourceFilter source) {
  switch (source) {
    case ListingSourceFilter.any:
      return IconsaxPlusBold.profile_2user;
    case ListingSourceFilter.privateOnly:
      return IconsaxPlusBold.user;
    case ListingSourceFilter.agencyOnly:
      return IconsaxPlusBold.buildings;
  }
}

IconData _featureIcon(String feature) {
  final lower = feature.trim().toLowerCase();
  if (lower.contains('חניה')) return IconsaxPlusBold.routing;
  if (lower.contains('מעלית')) return IconsaxPlusBold.buildings;
  if (lower.contains('ממ"ד') || lower.contains('ממד')) {
    return IconsaxPlusBold.shield_tick;
  }
  if (lower.contains('מזגן') || lower.contains('מיזוג')) {
    return IconsaxPlusBold.layer;
  }
  if (lower.contains('מרפסת')) return IconsaxPlusBold.layer;
  if (lower.contains('מחסן')) return IconsaxPlusBold.lock;
  if (lower.contains('ריהוט') || lower.contains('מרוהטת')) {
    return IconsaxPlusBold.home;
  }
  if (lower.contains('חיות')) return IconsaxPlusBold.heart;
  if (lower.contains('סורגים')) return IconsaxPlusBold.lock;
  if (lower.contains('נגישות')) return IconsaxPlusBold.profile_circle;
  if (lower.contains('גינה') || lower.contains('חצר')) {
    return IconsaxPlusBold.map;
  }
  if (lower.contains('שומר') || lower.contains('אבטחה')) {
    return IconsaxPlusBold.shield_tick;
  }
  if (lower.contains('משופצת') || lower.contains('משופץ')) {
    return IconsaxPlusBold.setting_4;
  }
  return IconsaxPlusBold.hashtag;
}
