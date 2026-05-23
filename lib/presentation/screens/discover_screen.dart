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
                    if (provider.filters.requiredFeatures.isNotEmpty)
                      Positioned(
                        top: -3,
                        right: -3,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
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
                                  properties
                                      .map((p) => p.id)
                                      .join('-'),
                                ),
                                controller: provider.propertySwiperController,
                                cardsCount: properties.length,
                                padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
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
                                child: _UndoButton(
                                    onTap: provider.undoSwipe),
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
          if (provider.filters.requiredFeatures.isNotEmpty) ...[
            const SizedBox(width: 8),
            _Pill(
              icon: IconsaxPlusBold.filter,
              label: '${provider.filters.requiredFeatures.length} מסננים',
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
  late int _budget;
  late double _minRooms;
  late String _areaId;
  late Set<String> _features;

  @override
  void initState() {
    super.initState();
    final f = widget.provider.filters;
    _budget = f.maxBudget;
    _minRooms = f.minRooms;
    _areaId = f.areaId;
    _features = {...f.requiredFeatures};
  }

  @override
  Widget build(BuildContext context) {
    final area = widget.provider.searchAreas.firstWhere(
      (item) => item.id == _areaId,
      orElse: () => widget.provider.selectedArea,
    );

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
                      _features = {};
                    });
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
                          markers: widget.provider.filteredProperties
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
                _FilterSection(title: 'אזור חיפוש'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.provider.searchAreas.map((searchArea) {
                    final sel = _areaId == searchArea.id;
                    return ChoiceChip(
                      selected: sel,
                      label: Text(searchArea.name),
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
                      onSelected: (_) =>
                          setState(() => _areaId = searchArea.id),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 22),
                _SliderField(
                  label: 'תקציב מקסימלי',
                  value: _budget.toDouble(),
                  min: 3000,
                  max: 18000,
                  divisions: 150,
                  displayValue: _formatCurrency(_budget),
                  onChanged: (v) =>
                      setState(() => _budget = (v / 100).round() * 100),
                ),
                const SizedBox(height: 18),
                _SliderField(
                  label: 'מינימום חדרים',
                  value: _minRooms,
                  min: 1,
                  max: 6,
                  divisions: 10,
                  displayValue: _minRooms % 1 == 0
                      ? _minRooms.toInt().toString()
                      : '$_minRooms',
                  onChanged: (v) =>
                      setState(() => _minRooms = (v * 2).round() / 2),
                ),
                const SizedBox(height: 22),
                _FilterSection(title: 'מאפיינים חשובים'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.provider.availableFeatures
                      .take(16)
                      .map((feature) {
                    final sel = _features.contains(feature);
                    return FilterChip(
                      selected: sel,
                      label: Text(feature),
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
                      onSelected: (v) => setState(() {
                        if (v) {
                          _features.add(feature);
                        } else {
                          _features.remove(feature);
                        }
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () async {
                    await widget.provider.updateFilters(
                      SearchFilters(
                        maxBudget: _budget,
                        minRooms: _minRooms,
                        areaId: _areaId,
                        requiredFeatures: _features,
                      ),
                    );
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(IconsaxPlusBold.tick_circle),
                  label: const Text('החל סינון'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
        ),
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
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String displayValue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
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
            Icon(IconsaxPlusBold.undo, size: 16, color: AppColors.textSecondary),
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
              onTap: () => provider.updateFilters(SearchFilters(
                maxBudget: provider.filters.maxBudget + 500,
                minRooms: provider.filters.minRooms,
                areaId: provider.filters.areaId,
                requiredFeatures: provider.filters.requiredFeatures,
              )),
            ),
            const SizedBox(height: 10),
            _QuickActionBtn(
              icon: IconsaxPlusLinear.home,
              label: 'הפחת דרישת חדרים ב-0.5',
              onTap: () {
                if (provider.filters.minRooms > 1) {
                  provider.updateFilters(SearchFilters(
                    maxBudget: provider.filters.maxBudget,
                    minRooms: provider.filters.minRooms - 0.5,
                    areaId: provider.filters.areaId,
                    requiredFeatures: provider.filters.requiredFeatures,
                  ));
                }
              },
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
          foregroundColor:
              isHighlighted ? AppColors.primary : AppColors.navy,
          side: BorderSide(
            color: isHighlighted ? AppColors.primary : AppColors.borderLight,
          ),
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
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
                                      borderRadius:
                                          BorderRadius.circular(8))),
                              const SizedBox(height: 10),
                              Container(
                                  height: 14,
                                  width: 200,
                                  decoration: BoxDecoration(
                                      color: highlight,
                                      borderRadius:
                                          BorderRadius.circular(6))),
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
