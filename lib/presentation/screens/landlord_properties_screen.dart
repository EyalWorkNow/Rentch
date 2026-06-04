import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/screens/add_property_screen.dart'
    show AddPropertyScreen, EditPropertyScreen;
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

class LandlordPropertiesScreen extends StatefulWidget {
  const LandlordPropertiesScreen({super.key});

  @override
  State<LandlordPropertiesScreen> createState() =>
      _LandlordPropertiesScreenState();
}

class _LandlordPropertiesScreenState extends State<LandlordPropertiesScreen> {
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

  List<RentalProperty> _applyFiltersAndSort(List<RentalProperty> properties) {
    var list = properties.toList();

    // Search filter
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((p) {
        return p.address.toLowerCase().contains(q) ||
            p.city.toLowerCase().contains(q) ||
            p.neighborhood.toLowerCase().contains(q);
      }).toList();
    }

    // Chip filter
    switch (_activeFilter) {
      case 'high_priority':
        list = list.where((p) => p.price < 6000).toList();
      case 'luxury':
        list = list.where((p) => p.price >= 10000).toList();
      case 'immediate':
        list = list.where((p) => p.entryDate.isEmpty || p.entryDate.toLowerCase().contains('מיידי') || p.entryDate.toLowerCase().contains('immediate') || p.entryDate.toLowerCase().contains('now')).toList();
      case 'large':
        list = list.where((p) => p.rooms >= 4).toList();
      case 'agency':
        list = list.where((p) => p.agencyListing).toList();
      case 'private':
        list = list.where((p) => !p.agencyListing).toList();
      default:
        break;
    }

    // Sort
    switch (_sortBy) {
      case 'price_asc':
        list.sort((a, b) => a.price.compareTo(b.price));
      case 'price_desc':
        list.sort((a, b) => b.price.compareTo(a.price));
      case 'rooms':
        list.sort((a, b) => b.rooms.compareTo(a.rooms));
      default:
        // 'recent' — keep original order
        break;
    }

    return list;
  }

  void _showSortSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
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
                    const Text(
                      'סינון ומיון נכסים',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
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
                            setSheetState(() {
                              _activeFilter = opt.$1;
                            });
                            setState(() {});
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 7),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary
                                  : Colors.white,
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
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.navy,
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
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4),
                        leading: Icon(
                          isSelected
                              ? IconsaxPlusBold.tick_circle
                              : IconsaxPlusBold.record_circle,
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
                          setSheetState(() {
                            _sortBy = opt.$1;
                          });
                          setState(() {});
                          Navigator.of(ctx).pop();
                        },
                      );
                    }),
                  ],
                ),
              ),
            );
          },
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

        final hasActiveFilterOrSort = _sortBy != 'recent' || _activeFilter != 'all';

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
                    icon: const Icon(IconsaxPlusBold.arrow_right,
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
            padding: const EdgeInsets.only(bottom: 96),
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
                    Icon(
                      IconsaxPlusBold.add,
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
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      // Search row + sort/filter button
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: TextField(
                                  controller: _searchCtrl,
                                  onChanged: (v) =>
                                      setState(() => _query = v.trim()),
                                  textDirection: TextDirection.rtl,
                                  decoration: InputDecoration(
                                    hintText: 'חיפוש לפי כתובת, עיר...',
                                    hintStyle: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    prefixIcon: const Icon(
                                      IconsaxPlusBold.search_normal,
                                      size: 18,
                                      color: AppColors.textSecondary,
                                    ),
                                    suffixIcon: _query.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(
                                              IconsaxPlusBold.close_circle,
                                              size: 18,
                                              color: AppColors.textSecondary,
                                            ),
                                            onPressed: () {
                                              _searchCtrl.clear();
                                              setState(() => _query = '');
                                            },
                                          )
                                        : null,
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 0),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                          color: AppColors.borderLight,
                                          width: 1),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                          color: AppColors.borderLight,
                                          width: 1),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                          color: AppColors.primary, width: 1.5),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: _showSortSheet,
                              child: Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: hasActiveFilterOrSort
                                      ? AppColors.primary.withValues(alpha: 0.1)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: hasActiveFilterOrSort
                                        ? AppColors.primary
                                            .withValues(alpha: 0.4)
                                        : AppColors.borderLight,
                                    width: 1,
                                  ),
                                ),
                                child: Icon(
                                  IconsaxPlusBold.filter,
                                  size: 20,
                                  color: hasActiveFilterOrSort
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
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
                                    onClear: () => setState(() {
                                      _query = '';
                                      _activeFilter = 'all';
                                      _searchCtrl.clear();
                                    }),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 0, 16, 120),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image with status badge
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: SizedBox(
              height: 168,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _PropertyThumb(media: property.primaryMedia),
                  // Bottom gradient for visual depth
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 56,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            AppColors.navy.withValues(alpha: 0.55),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Status badge top-left (physical)
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 6,
                              offset: const Offset(0, 2)),
                        ],
                      ),
                      child: const Text(
                        'פעיל',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  // Match count badge top-right (physical)
                  if (matchCount > 0)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.navy.withValues(alpha: 0.80),
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withValues(alpha: 0.15),
                                blurRadius: 6,
                                offset: const Offset(0, 2)),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(IconsaxPlusBold.heart,
                                size: 11, color: AppColors.coral),
                            const SizedBox(width: 4),
                            Text(
                              '$matchCount התאמות',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Address + price
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            property.address,
                            style: const TextStyle(
                              color: AppColors.navy,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (property.city.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              property.city,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        property.priceLabel,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _PropertyMeta(label: '${property.roomsLabel} חדרים'),
                    _PropertyMeta(label: '${property.sizeM2} מ"ר'),
                    _PropertyMeta(
                      label: property.entryDate.isEmpty
                          ? 'כניסה גמישה'
                          : property.entryDate,
                    ),
                    if (property.agencyListing)
                      const _PropertyMeta(label: 'סוכנות'),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    // Remove button
                    OutlinedButton.icon(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(22)),
                            title: const Text(
                              'הסרת נכס',
                              style: TextStyle(
                                  color: AppColors.navy,
                                  fontWeight: FontWeight.w900),
                            ),
                            content: Text(
                              'להסיר את "${property.address}"?\nהפעולה אינה ניתנת לביטול.',
                              style: const TextStyle(
                                  color: AppColors.textSecondary, height: 1.4),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('ביטול',
                                    style: TextStyle(
                                        color: AppColors.textSecondary)),
                              ),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.coral,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12))),
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('הסר'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) onRemove();
                      },
                      icon: const Icon(IconsaxPlusBold.trash, size: 15),
                      label: const Text('הסר'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.coral,
                        side: const BorderSide(color: AppColors.coral),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Edit button
                    FilledButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(IconsaxPlusBold.edit_2, size: 15),
                      label: const Text('ערוך'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.navy.withValues(alpha: 0.08),
                        foregroundColor: AppColors.navy,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        elevation: 0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        decoration: BoxDecoration(
                          color: AppColors.navy.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'מופיע בדשבורד ובסוויפים',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppColors.navy,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
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
        child: const Icon(
          IconsaxPlusBold.building,
          size: 42,
          color: AppColors.primary,
        ),
      );
}

// ─── Meta pill ───────────────────────────────────────────────────────────────

class _PropertyMeta extends StatelessWidget {
  const _PropertyMeta({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryLight2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.navy,
          fontSize: 12,
          fontWeight: FontWeight.w700,
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
              child: const Icon(
                IconsaxPlusBold.buildings,
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
              child: const Icon(
                IconsaxPlusBold.search_normal,
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
