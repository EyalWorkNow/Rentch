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
      case 'expensive':
        list = list.where((p) => p.price >= 8000).toList();
      case 'rooms3':
        list = list.where((p) => p.rooms >= 3).toList();
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final options = [
          ('recent', 'ברירת מחדל'),
          ('price_asc', 'לפי מחיר עולה'),
          ('price_desc', 'לפי מחיר יורד'),
          ('rooms', 'לפי חדרים'),
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'מיון נכסים',
                  style: TextStyle(
                    color: AppColors.navy,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 16),
                ...options.map((opt) {
                  final isSelected = _sortBy == opt.$1;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
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
                      setState(() => _sortBy = opt.$1);
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
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final allProperties = provider.myProperties;
        final filtered = _applyFiltersAndSort(allProperties);
        final isFiltered = _query.isNotEmpty || _activeFilter != 'all';

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: AppColors.background,
            title: const Text('הדירות שלי'),
          ),
          body: provider.isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                )
              : SafeArea(
                  child: Column(
                    children: [
                      // Properties header with add button
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                        child: _PropertiesHeader(
                          count: allProperties.length,
                          onAdd: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AddPropertyScreen(),
                            ),
                          ),
                        ),
                      ),
                      // Search row + sort button
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
                                  color: _sortBy != 'recent'
                                      ? AppColors.primary.withValues(alpha: 0.1)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: _sortBy != 'recent'
                                        ? AppColors.primary
                                            .withValues(alpha: 0.4)
                                        : AppColors.borderLight,
                                    width: 1,
                                  ),
                                ),
                                child: Icon(
                                  IconsaxPlusBold.sort,
                                  size: 20,
                                  color: _sortBy != 'recent'
                                      ? AppColors.primary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Filter chips
                      SizedBox(
                        height: 38,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            _FilterChip(
                              label: 'הכל',
                              isActive: _activeFilter == 'all',
                              onTap: () =>
                                  setState(() => _activeFilter = 'all'),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'יקר מ-8K',
                              isActive: _activeFilter == 'expensive',
                              onTap: () =>
                                  setState(() => _activeFilter = 'expensive'),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: '3+ חדרים',
                              isActive: _activeFilter == 'rooms3',
                              onTap: () =>
                                  setState(() => _activeFilter = 'rooms3'),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'סוכנות',
                              isActive: _activeFilter == 'agency',
                              onTap: () =>
                                  setState(() => _activeFilter = 'agency'),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'פרטי',
                              isActive: _activeFilter == 'private',
                              onTap: () =>
                                  setState(() => _activeFilter = 'private'),
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

// ─── Filter chip ─────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isActive ? AppColors.primary : AppColors.borderLight,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : AppColors.navy,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ─── Header ──────────────────────────────────────────────────────────────────

class _PropertiesHeader extends StatelessWidget {
  const _PropertiesHeader({
    required this.count,
    required this.onAdd,
  });

  final int count;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: const [
          BoxShadow(
            color: AppColors.shadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  IconsaxPlusBold.buildings_2,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ניהול דירות',
                      style: TextStyle(
                        color: AppColors.navy,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$count נכסים פעילים בחשבון שלך',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(IconsaxPlusBold.add_square, size: 16),
              label: const Text('הוסף דירה'),
            ),
          ),
        ],
      ),
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
              height: 160,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _PropertyThumb(media: property.primaryMedia),
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
                          color: AppColors.navy.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(999),
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
                      onPressed: onRemove,
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
