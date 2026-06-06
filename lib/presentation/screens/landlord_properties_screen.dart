import 'dart:ui';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/add_property_screen.dart'
    show AddPropertyScreen, EditPropertyScreen;
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/rentch_icon.dart';
import 'package:provider/provider.dart';

class LandlordPropertiesScreen extends StatefulWidget {
  const LandlordPropertiesScreen({super.key});

  @override
  State<LandlordPropertiesScreen> createState() =>
      _LandlordPropertiesScreenState();
}

class _LandlordPropertiesScreenState extends State<LandlordPropertiesScreen> {
  static const double _floatingActionBottomInset = 92;
  static const double _listBottomInset = 132;

  String _query = '';
  String _activeFilter =
      'all'; // 'all', 'expensive', 'rooms3', 'agency', 'private'
  String _sortBy = 'recent'; // 'recent', 'price_asc', 'price_desc', 'rooms'
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matchesQuery(RentalProperty property) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return property.address.toLowerCase().contains(query) ||
        property.searchableText.contains(query);
  }

  bool _matchesActiveFilter(RentalProperty property) {
    switch (_activeFilter) {
      case 'high_priority':
        return property.price < 6000;
      case 'luxury':
        return property.price >= 10000;
      case 'immediate':
        final entryDate = property.entryDate.trim().toLowerCase();
        return entryDate.isEmpty ||
            entryDate.contains('מיידי') ||
            entryDate.contains('immediate') ||
            entryDate.contains('now') ||
            entryDate.contains('today');
      case 'large':
        return property.rooms >= 4;
      case 'agency':
        return property.agencyListing;
      case 'private':
        return !property.agencyListing;
      case 'all':
      default:
        return true;
    }
  }

  void _setActiveFilter(String filter) {
    if (_activeFilter == filter) return;
    setState(() => _activeFilter = filter);
  }

  void _setSortBy(String sortBy) {
    if (_sortBy == sortBy) return;
    setState(() => _sortBy = sortBy);
  }

  void _clearSearchAndFilters() {
    setState(() {
      _query = '';
      _activeFilter = 'all';
      _searchCtrl.clear();
    });
  }

  void _resetSheetControls() {
    setState(() {
      _activeFilter = 'all';
      _sortBy = 'recent';
    });
  }

  List<RentalProperty> _applyFiltersAndSort(List<RentalProperty> properties) {
    final list =
        properties.where(_matchesQuery).where(_matchesActiveFilter).toList();

    // Sort
    switch (_sortBy) {
      case 'price_asc':
        list.sort((a, b) => a.price.compareTo(b.price));
        break;
      case 'price_desc':
        list.sort((a, b) => b.price.compareTo(a.price));
        break;
      case 'rooms':
        list.sort((a, b) => b.rooms.compareTo(a.rooms));
        break;
      default:
        // 'recent' — keep original order
        break;
    }

    return list;
  }

  void _showSortSheet() {
    final hasActiveFilterOrSort = _activeFilter != 'all' || _sortBy != 'recent';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final sortOptions = [
          ('recent', 'ברירת מחדל'),
          ('price_asc', 'לפי מחיר עולה'),
          ('price_desc', 'לפי מחיר יורד'),
          ('rooms', 'לפי חדרים'),
        ];

        final filterOptions = [
          ('all', 'הכל'),
          ('high_priority', 'עדיפות שיווקית (עד 6K)'),
          ('luxury', 'נכסי יוקרה (10K+)'),
          ('immediate', 'כניסה מיידית'),
          ('large', 'דירות גדולות (4+ חדרים)'),
          ('agency', 'בלעדיות (סוכנות)'),
          ('private', 'פרטי (ללא תיווך)'),
        ];

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'סינון ומיון נכסים',
                        style: TextStyle(
                          color: AppColors.navy,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (hasActiveFilterOrSort)
                      TextButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _resetSheetControls();
                        },
                        child: const Text('איפוס'),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'סינון לפי תגיות',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: filterOptions.map((opt) {
                    final isSelected = _activeFilter == opt.$1;
                    return GestureDetector(
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _setActiveFilter(opt.$1);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary : Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.borderLight,
                            width: 1,
                          ),
                        ),
                        child: Text(
                          opt.$2,
                          style: TextStyle(
                            color: isSelected ? Colors.white : AppColors.navy,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                const Text(
                  'מיון לפי',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                ...sortOptions.map((opt) {
                  final isSelected = _sortBy == opt.$1;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: Icon(
                      isSelected
                          ? IconsaxPlusLinear.tick_circle
                          : IconsaxPlusLinear.record_circle,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textSecondary,
                      size: 20,
                    ),
                    title: Text(
                      opt.$2,
                      style: TextStyle(
                        color: isSelected ? AppColors.primary : AppColors.navy,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                        fontSize: 14.5,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _setSortBy(opt.$1);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final allProperties = provider.myProperties;
        final filtered = _applyFiltersAndSort(allProperties);
        final isFiltered = _query.isNotEmpty || _activeFilter != 'all';
        final canPop = Navigator.of(context).canPop();

        final hasActiveFilterOrSort =
            _sortBy != 'recent' || _activeFilter != 'all';

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: AppColors.background,
            elevation: 0,
            scrolledUnderElevation: 0,
            toolbarHeight: 64,
            leading: canPop
                ? IconButton(
                    icon: const RentchIcon(IconsaxPlusLinear.arrow_right,
                        color: AppColors.navy),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                : null,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'הדירות שלי',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${allProperties.length} דירות פעילות',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: Padding(
            padding: const EdgeInsets.only(bottom: _floatingActionBottomInset),
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AddPropertyScreen(),
                ),
              ),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RentchIcon(
                      IconsaxPlusLinear.add,
                      color: Colors.white,
                      size: 16,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'הוספה',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
          body: provider.isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      // Search row + sort/filter button
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 52,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(26),
                                  border: Border.all(
                                      color: const Color(0xFFE2ECF1)),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.04),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
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
                                        controller: _searchCtrl,
                                        onChanged: (v) =>
                                            setState(() => _query = v.trim()),
                                        textDirection: TextDirection.rtl,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: AppColors.navy,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: 'חיפוש לפי כתובת, עיר...',
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
                                              const EdgeInsets.symmetric(
                                                  vertical: 12),
                                        ),
                                      ),
                                    ),
                                    if (_query.isNotEmpty)
                                      IconButton(
                                        icon: const RentchIcon(
                                          IconsaxPlusLinear.close_circle,
                                          size: 18,
                                          color: AppColors.textSecondary,
                                        ),
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          setState(() => _query = '');
                                        },
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              key: const ValueKey(
                                'landlord-properties-filter-button',
                              ),
                              onTap: _showSortSheet,
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: hasActiveFilterOrSort
                                      ? AppColors.primary
                                      : const Color(0xFFF2F4F5),
                                  shape: BoxShape.circle,
                                  boxShadow: hasActiveFilterOrSort
                                      ? [
                                          BoxShadow(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.24),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          )
                                        ]
                                      : null,
                                ),
                                child: RentchIcon(
                                  IconsaxPlusLinear.filter,
                                  size: 20,
                                  color: hasActiveFilterOrSort
                                      ? Colors.white
                                      : AppColors.navy,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Scrollable Filter Pills under Search Bar
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: Row(
                            textDirection: TextDirection.rtl,
                            children: [
                              _FilterPill(
                                label: 'הכל',
                                isSelected: _activeFilter == 'all',
                                onTap: () => _setActiveFilter('all'),
                              ),
                              const SizedBox(width: 8),
                              _FilterPill(
                                label: 'כניסה מיידית',
                                isSelected: _activeFilter == 'immediate',
                                onTap: () => _setActiveFilter('immediate'),
                              ),
                              const SizedBox(width: 8),
                              _FilterPill(
                                label: 'דירות גדולות',
                                isSelected: _activeFilter == 'large',
                                onTap: () => _setActiveFilter('large'),
                              ),
                              const SizedBox(width: 8),
                              _FilterPill(
                                label: 'פרטי',
                                isSelected: _activeFilter == 'private',
                                onTap: () => _setActiveFilter('private'),
                              ),
                              const SizedBox(width: 8),
                              _FilterPill(
                                label: 'בלעדיות',
                                isSelected: _activeFilter == 'agency',
                                onTap: () => _setActiveFilter('agency'),
                              ),
                              const SizedBox(width: 8),
                              _FilterPill(
                                label: 'יוקרה',
                                isSelected: _activeFilter == 'luxury',
                                onTap: () => _setActiveFilter('luxury'),
                              ),
                              const SizedBox(width: 8),
                              _FilterPill(
                                label: 'עד 6K',
                                isSelected: _activeFilter == 'high_priority',
                                onTap: () => _setActiveFilter('high_priority'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Results count when filtered
                      if (isFiltered) ...[
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              '${filtered.length} מתוך ${allProperties.length} נכסים',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      // List or empty state
                      Expanded(
                        child: allProperties.isEmpty
                            ? const _EmptyPropertiesState()
                            : filtered.isEmpty
                                ? _EmptyFilteredState(
                                    onClear: _clearSearchAndFilters,
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 0, 16, _listBottomInset),
                                    itemBuilder: (context, index) {
                                      final property = filtered[index];
                                      final matchCount = provider.matches
                                          .where((m) =>
                                              m.propertyId == property.id)
                                          .length;
                                      return _PropertyManageCard(
                                        property: property,
                                        matchCount: matchCount,
                                        onRemove: () => context
                                            .read<DatingProvider>()
                                            .removeLandlordProperty(
                                                property.id),
                                        onEdit: () =>
                                            Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => EditPropertyScreen(
                                                property: property),
                                          ),
                                        ),
                                      );
                                    },
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 12),
                                    itemCount: filtered.length,
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

// ─── Property card ───────────────────────────────────────────────────────────

class _PropertyManageCard extends StatelessWidget {
  const _PropertyManageCard({
    required this.property,
    required this.matchCount,
    required this.onRemove,
    required this.onEdit,
  });

  final RentalProperty property;
  final int matchCount;
  final VoidCallback onRemove;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: AspectRatio(
        aspectRatio: 0.92,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _PropertyThumb(media: property.primaryMedia),
              // Linear gradient overlay (smooth dark bottom)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.3),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.85),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
              // Top Row for Glass Tags (Beds, Floor/Type, Size)
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _GlassTag(
                        icon: Icons.king_bed_outlined,
                        label: '${property.roomsLabel} חדרים',
                      ),
                      const SizedBox(width: 8),
                      _GlassTag(
                        icon: Icons.layers_outlined,
                        label: property.floor.isEmpty
                            ? 'דירה'
                            : 'קומה ${property.floor}',
                      ),
                      const SizedBox(width: 8),
                      _GlassTag(
                        icon: Icons.space_dashboard_outlined,
                        label: '${property.sizeM2} מ״ר',
                      ),
                    ],
                  ),
                ),
              ),
              // Price, Address, and Action Buttons at the bottom
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Price and Address Column
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Price
                          Text(
                            property.priceLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Location Address
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  property.address,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Actions Row (Circular Edit and Status Indicator)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Edit Button (Glassmorphic White Circle)
                        ClipOval(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.18),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.20),
                                  width: 1,
                                ),
                              ),
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                onPressed: onEdit,
                                icon: const RentchIcon(
                                  IconsaxPlusLinear.edit_2,
                                  color: Colors.white,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Status Indicator Circle (Glassmorphic Green/Grey Circle)
                        ClipOval(
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: property.isActive
                                    ? AppColors.success.withValues(alpha: 0.25)
                                    : Colors.white.withValues(alpha: 0.1),
                                border: Border.all(
                                  color: property.isActive
                                      ? AppColors.success
                                          .withValues(alpha: 0.40)
                                      : Colors.white.withValues(alpha: 0.15),
                                  width: 1,
                                ),
                              ),
                              child: Center(
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: property.isActive
                                        ? AppColors.success
                                        : Colors.white60,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
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

// ─── Glassmorphism Tag ────────────────────────────────────────────────────────

class _GlassTag extends StatelessWidget {
  const _GlassTag({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.20),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Empty states ────────────────────────────────────────────────────────────

class _EmptyPropertiesState extends StatelessWidget {
  const _EmptyPropertiesState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const RentchIcon(
                IconsaxPlusLinear.buildings,
                size: 36,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'עדיין לא הוספת דירות',
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'הוסף נכס ראשון כדי להתחיל לקבל לייקים, מועמדים ושיחות.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFilteredState extends StatelessWidget {
  const _EmptyFilteredState({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const RentchIcon(
                IconsaxPlusLinear.search_normal,
                size: 30,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'לא נמצאו נכסים עם הסינון הזה',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.navy,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'נסה לשנות את פרמטרי החיפוש או לנקות את הפילטרים.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13.5,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onClear,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              ),
              child: const Text(
                'נקה סינון',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
