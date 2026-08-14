import 'dart:async';
import 'package:dating_app/core/ui/platform_fx.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/data/models/rental_contract.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/presentation/features/billing/boost_flow.dart';
import 'package:dating_app/presentation/screens/add_property_screen.dart'
    show AddPropertyScreen, EditPropertyScreen;
import 'package:dating_app/presentation/screens/contract_detail_screen.dart';
import 'package:dating_app/presentation/screens/contract_form_screen.dart';
import 'package:dating_app/presentation/screens/property_detail_screen.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:dating_app/presentation/widgets/swipe_to_confirm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';
import 'package:dating_app/presentation/widgets/scale_bounce.dart';
import 'package:dating_app/presentation/widgets/pulse_widget.dart';
import 'package:provider/provider.dart';

class LandlordPropertiesScreen extends StatefulWidget {
  const LandlordPropertiesScreen({super.key});

  @override
  State<LandlordPropertiesScreen> createState() =>
      _LandlordPropertiesScreenState();
}

class _LandlordPropertiesScreenState extends State<LandlordPropertiesScreen>
    with WidgetsBindingObserver {
  static const double _floatingActionBottomInset = 102;
  static const double _listBottomInset = 132;

  String _query = '';
  String _activeFilter =
      'all'; // 'all', 'expensive', 'rooms3', 'agency', 'private'
  String _sortBy = 'recent'; // 'recent', 'price_asc', 'price_desc', 'rooms'
  final _searchCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _fabExpanded = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
    WidgetsBinding.instance.addObserver(this);
    // On opening the owner's properties, re-check any background 3D scans so a
    // KIRI reconstruction that finished while away gets attached to its listing,
    // AND re-sync from the server — this list previously only ever refreshed at
    // COLD APP START, so a property created/edited/deleted on another surface
    // (the website's publisher portal, another device) while the app was just
    // backgrounded (not killed) never showed up until a full relaunch.
    WidgetsBinding.instance.addPostFrameCallback((_) => _finalizeScans());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _finalizeScans();
  }

  void _finalizeScans() {
    if (!mounted) return;
    final provider = context.read<DatingProvider>();
    unawaited(provider.refreshScanProcessingCache());
    unawaited(provider.finalizePendingScans());
    unawaited(provider.refreshMyProperties());
  }

  void _scrollListener() {
    if (_scrollController.position.userScrollDirection == ScrollDirection.reverse) {
      if (_fabExpanded) {
        setState(() => _fabExpanded = false);
      }
    } else if (_scrollController.position.userScrollDirection == ScrollDirection.forward) {
      if (!_fabExpanded) {
        setState(() => _fabExpanded = true);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
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

  /// Makes contracts reachable straight from a property card. If a contract
  /// already exists for the property, opens its detail; otherwise opens the
  /// draft form for one of the property's matched tenants. Contracts are bound
  /// to a match, so with no match yet we explain that instead of dead-ending.
  void _openContract(
    BuildContext context, {
    required RentalContract? existing,
    required List<RentalMatch> matches,
  }) {
    if (existing != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ContractDetailScreen(
            contractId: existing.id,
            matchId: existing.matchId,
          ),
        ),
      );
      return;
    }
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              AppLocalizations.of(context)!.landlordPropertiesScreenContractNeedsMatch),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContractFormScreen(matchId: matches.first.id),
      ),
    );
  }

  /// Entry point for the card's "חוזה" action.
  ///
  /// • If a contract already exists, opening it can lead to (re)sending it, so
  ///   we first ask the landlord to slide-to-confirm before proceeding.
  /// • If no contract exists yet, we offer a simple choice: create their own
  ///   contract, or use Rently's standard lawyers' template — both continue to
  ///   the existing ContractFormScreen (the form itself lets them pick the
  ///   standard template vs. their own terms).
  Future<void> _handleContractAction(
    BuildContext context, {
    required RentalContract? existing,
    required List<RentalMatch> matches,
  }) async {
    if (existing != null) {
      final l10n = AppLocalizations.of(context)!;
      final ok = await SwipeToConfirmSheet.show(
        context,
        title: l10n.landlordPropertiesScreenSendContractTitle,
        message: l10n.landlordPropertiesScreenSendContractMessage,
      );
      if (!ok || !context.mounted) return;
      _openContract(context, existing: existing, matches: matches);
      return;
    }

    if (matches.isEmpty) {
      // No match → no contract can be drafted yet. Reuse the existing notice.
      _openContract(context, existing: null, matches: matches);
      return;
    }

    final useOurs = await _askContractSource(context);
    if (useOurs == null || !context.mounted) return;
    // Both choices open the same form; the form defaults to (and lets the user
    // pick) the standard Rently template, so no extra wiring is needed here.
    _openContract(context, existing: null, matches: matches);
  }

  /// Simple, large-tap choice for an older user: create their own contract or
  /// use Rently's standard template. Returns `true` for "ours", `false` for
  /// "own", or `null` if dismissed.
  Future<bool?> _askContractSource(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.landlordPropertiesScreenContractSourceTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 18),
              _ContractSourceButton(
                icon: IconsaxPlusLinear.shield_tick,
                title: l10n.landlordPropertiesScreenUseOurContract,
                subtitle: l10n.landlordPropertiesScreenOurContractSubtitle,
                filled: true,
                onTap: () => Navigator.of(ctx).pop(true),
              ),
              const SizedBox(height: 12),
              _ContractSourceButton(
                icon: IconsaxPlusLinear.edit_2,
                title: l10n.landlordPropertiesScreenCreateOwnContract,
                subtitle: l10n.landlordPropertiesScreenOwnContractSubtitle,
                filled: false,
                onTap: () => Navigator.of(ctx).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSortSheet() {
    final hasActiveFilterOrSort = _activeFilter != 'all' || _sortBy != 'recent';
    final l10n = AppLocalizations.of(context)!;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final sortOptions = [
          ('recent', l10n.landlordPropertiesScreenSortDefault),
          ('price_asc', l10n.landlordPropertiesScreenSortPriceAsc),
          ('price_desc', l10n.landlordPropertiesScreenSortPriceDesc),
          ('rooms', l10n.landlordPropertiesScreenSortRooms),
        ];

        final filterOptions = [
          ('all', l10n.landlordPropertiesScreenFilterAll),
          ('high_priority', l10n.landlordPropertiesScreenFilterHighPriority),
          ('luxury', l10n.landlordPropertiesScreenFilterLuxury),
          ('immediate', l10n.landlordPropertiesScreenFilterImmediate),
          ('large', l10n.landlordPropertiesScreenFilterLarge),
          ('agency', l10n.landlordPropertiesScreenFilterAgency),
          ('private', l10n.landlordPropertiesScreenFilterPrivate),
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
                    Expanded(
                      child: Text(
                        l10n.landlordPropertiesScreenFilterSortTitle,
                        style: const TextStyle(
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
                        child: Text(l10n.landlordPropertiesScreenReset),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  l10n.landlordPropertiesScreenFilterByTags,
                  style: const TextStyle(
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
                Text(
                  l10n.landlordPropertiesScreenSortByLabel,
                  style: const TextStyle(
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

  // Boost ("הקפצת מודעה"): gated by an active subscription + monthly quota.
  // No subscription → open the paywall. Otherwise confirm, call the server, and
  // reflect the result (server is authoritative on entitlement/quota).
  Future<void> _handleBoost(RentalProperty property) =>
      showBoostFlow(context, property);

  @override
  Widget build(BuildContext context) {
    return Consumer<DatingProvider>(
      builder: (context, provider, _) {
        final l10n = AppLocalizations.of(context)!;
        final allProperties = provider.myProperties;
        final filtered = _applyFiltersAndSort(allProperties);
        final isFiltered = _query.isNotEmpty || _activeFilter != 'all';
        final canPop = Navigator.of(context).canPop();

        final hasActiveFilterOrSort =
            _sortBy != 'recent' || _activeFilter != 'all';

        return Scaffold(
          backgroundColor: AppColors.background,
          // Title + "X דירות פעילות" removed — the search/filter/tags rise to
          // the top. Keep a minimal bar only for the back arrow when pushed.
          appBar: canPop
              ? AppBar(
                  automaticallyImplyLeading: false,
                  backgroundColor: AppColors.background,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  toolbarHeight: 52,
                  leading: IconButton(
                    icon: const RentlyIcon(IconsaxPlusLinear.arrow_right,
                        color: AppColors.navy),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                )
              : null,
          floatingActionButton: Padding(
            padding: const EdgeInsets.only(bottom: _floatingActionBottomInset),
            child: ScaleBounce(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AddPropertyScreen(),
                ),
              ),
              scaleDownTo: 0.90,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                height: 38,
                padding: EdgeInsets.symmetric(horizontal: _fabExpanded ? 12 : 11),
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const RentlyIcon(
                      IconsaxPlusLinear.add,
                      color: Colors.white,
                      size: 16,
                    ),
                    if (_fabExpanded) ...[
                      const SizedBox(width: 4),
                      Text(
                        l10n.landlordPropertiesScreenAddLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
          body: provider.isLoading
              ? Center(
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
                                      color: AppColors.border),
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
                                    const RentlyIcon(
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
                                        style: const TextStyle(
                                          fontSize: 14,
                                          color: AppColors.navy,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: l10n.landlordPropertiesScreenSearchHint,
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
                                        icon: const RentlyIcon(
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
                                      : AppColors.slate100,
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
                                child: RentlyIcon(
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
                            children: [
                              _FilterPill(
                                label: l10n.landlordPropertiesScreenFilterAll,
                                isSelected: _activeFilter == 'all',
                                onTap: () => _setActiveFilter('all'),
                              ),
                              const SizedBox(width: 8),
                              _FilterPill(
                                label: l10n.landlordPropertiesScreenFilterImmediate,
                                isSelected: _activeFilter == 'immediate',
                                onTap: () => _setActiveFilter('immediate'),
                              ),
                              const SizedBox(width: 8),
                              _FilterPill(
                                label: l10n.landlordPropertiesScreenPillLarge,
                                isSelected: _activeFilter == 'large',
                                onTap: () => _setActiveFilter('large'),
                              ),
                              const SizedBox(width: 8),
                              _FilterPill(
                                label: l10n.landlordPropertiesScreenPillPrivate,
                                isSelected: _activeFilter == 'private',
                                onTap: () => _setActiveFilter('private'),
                              ),
                              const SizedBox(width: 8),
                              _FilterPill(
                                label: l10n.landlordPropertiesScreenPillAgency,
                                isSelected: _activeFilter == 'agency',
                                onTap: () => _setActiveFilter('agency'),
                              ),
                              const SizedBox(width: 8),
                              _FilterPill(
                                label: l10n.landlordPropertiesScreenPillLuxury,
                                isSelected: _activeFilter == 'luxury',
                                onTap: () => _setActiveFilter('luxury'),
                              ),
                              const SizedBox(width: 8),
                              _FilterPill(
                                label: l10n.landlordPropertiesScreenPillHighPriority,
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
                              l10n.landlordPropertiesScreenResultsCount(
                                  filtered.length, allProperties.length),
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
                            ? _EmptyPropertiesState()
                            : filtered.isEmpty
                                ? _EmptyFilteredState(
                                    onClear: _clearSearchAndFilters,
                                  )
                                : ListView.separated(
                                    controller: _scrollController,
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 0, 16, _listBottomInset),
                                    itemBuilder: (context, index) {
                                      final property = filtered[index];
                                      final propertyMatches = provider.matches
                                          .where((m) =>
                                              m.propertyId == property.id)
                                          .toList();
                                      final matchCount = propertyMatches.length;
                                      // Cheapest existing contract for this
                                      // property (any party), to surface status.
                                      RentalContract? contract;
                                      for (final c in provider.contracts) {
                                        if (c.propertyId == property.id) {
                                          contract = c;
                                          break;
                                        }
                                      }
                                      return StaggeredEntrance(
                                        index: index,
                                        child: _PropertyManageCard(
                                          property: property,
                                          matchCount: matchCount,
                                          contractStatus: contract?.status,
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
                                          onOpen: () => Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => PropertyDetailScreen(
                                                property: property,
                                                isLandlordPreview: true,
                                              ),
                                            ),
                                          ),
                                          onContract: () => _handleContractAction(
                                            context,
                                            existing: contract,
                                            matches: propertyMatches,
                                          ),
                                          onBoost: () => _handleBoost(property),
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
    required this.contractStatus,
    required this.onRemove,
    required this.onEdit,
    required this.onOpen,
    required this.onContract,
    required this.onBoost,
  });

  final RentalProperty property;
  final int matchCount;
  final ContractStatus? contractStatus;
  // Future<bool>: removeLandlordProperty now reports whether the delete
  // actually landed on the server (see dating_provider.dart) so this button
  // can show an honest error instead of assuming success.
  final Future<bool> Function() onRemove;
  final VoidCallback onEdit;
  final VoidCallback onBoost;

  /// Tapping anywhere on the card opens the property (detail/preview).
  final VoidCallback onOpen;
  final VoidCallback onContract;

  /// Short label for the property's contract state, or null if none.
  String? _contractStatusLabel(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (contractStatus) {
      case ContractStatus.draft:
        return l10n.landlordPropertiesScreenContractDraft;
      case ContractStatus.sent:
        return l10n.landlordPropertiesScreenContractSent;
      case ContractStatus.signed:
        return l10n.landlordPropertiesScreenContractSigned;
      case ContractStatus.declined:
      case ContractStatus.cancelled:
      case null:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final contractStatusLabel = _contractStatusLabel(context);
    final boostFrame = property.isUltraBoosted
        ? AppColors.amber
        : (property.isBoosted ? AppColors.primary : null);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: boostFrame != null
            ? Border.all(color: boostFrame, width: 2.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: boostFrame != null
                ? boostFrame.withValues(alpha: 0.4)
                : Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        // Matches the discover/swipe property card's corner radius (18) for
        // visual consistency between the two card components.
        borderRadius: BorderRadius.circular(18),
        // Whole card is tappable → opens the property (detail/preview).
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onOpen,
            child: AspectRatio(
              // Shorter, more compact card.
              aspectRatio: 1.55,
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
                            Colors.black.withValues(alpha: 0.28),
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.85),
                          ],
                          stops: const [0.0, 0.4, 1.0],
                        ),
                      ),
                    ),
                  ),
                  // Top Row: status dot + key glass tags + contract tag.
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Row(
                      children: [
                        _StatusDot(isActive: property.isActive),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                if (property.isUltraBoosted) ...[
                                  const _GlassTag(
                                    icon: Icons.workspace_premium_rounded,
                                    label: 'Ultra',
                                    gold: true,
                                  ),
                                  const SizedBox(width: 6),
                                ] else if (property.isBoosted) ...[
                                  _GlassTag(
                                    icon: Icons.bolt_rounded,
                                    label: l10n.landlordPropertiesScreenBoostedTag,
                                    accent: true,
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                _GlassTag(
                                  icon: Icons.king_bed_outlined,
                                  label: l10n.landlordPropertiesScreenRoomsTag(
                                      property.roomsLabel),
                                ),
                                const SizedBox(width: 6),
                                _GlassTag(
                                  icon: Icons.space_dashboard_outlined,
                                  label: l10n.landlordPropertiesScreenSizeTag(
                                      property.sizeM2),
                                ),
                                if (contractStatusLabel != null) ...[
                                  const SizedBox(width: 6),
                                  _GlassTag(
                                    icon: Icons.description_outlined,
                                    label: l10n.landlordPropertiesScreenContractLabel(
                                        contractStatusLabel),
                                  ),
                                ],
                                // Phase-3: look-alike target audience (renders
                                // only when the server has scored an audience).
                                const SizedBox(width: 6),
                                _AudienceChip(propertyId: property.id),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Bottom: price + address, with Contract & Edit actions.
                  Positioned(
                    bottom: 12,
                    left: 14,
                    right: 14,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                property.priceLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.location_on_rounded,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                  const SizedBox(width: 3),
                                  Expanded(
                                    child: Text(
                                      property.address,
                                      style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: 0.9),
                                        fontSize: 13,
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
                        const SizedBox(width: 10),
                        // Actions: Boost + Contract + Edit (eye removed — card tap opens).
                        _GlassAction(
                          icon: IconsaxPlusLinear.flash_1,
                          onTap: onBoost,
                        ),
                        const SizedBox(width: 8),
                        _GlassAction(
                          icon: IconsaxPlusLinear.document_text,
                          onTap: onContract,
                        ),
                        const SizedBox(width: 8),
                        _GlassAction(
                          icon: IconsaxPlusLinear.edit_2,
                          onTap: onEdit,
                        ),
                        const SizedBox(width: 8),
                        // onRemove was passed into this card from day one but
                        // never actually wired to a visible action — the only
                        // reachable delete path was inside the Edit screen.
                        // Same confirm-dialog copy/style as that screen's own
                        // delete button (add_property_screen.dart) so the UX
                        // is consistent wherever a landlord deletes a listing.
                        _GlassAction(
                          icon: IconsaxPlusLinear.trash,
                          onTap: () => _confirmRemove(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text(
          AppLocalizations.of(context)!.addPropertyScreeneb255ed5,
          style:
              const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w900),
        ),
        content: Text(
          AppLocalizations.of(context)!.addPropertyScreendb2a79db(property.address),
          style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppLocalizations.of(context)!.addPropertyScreena7c55a8d,
                style: const TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.coral,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppLocalizations.of(context)!.addPropertyScreen10666b28),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted = await onRemove();
    if (!deleted && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(milliseconds: 3000),
        content: Text(AppLocalizations.of(context)!.addPropertyScreen79286e19),
        backgroundColor: AppColors.coral,
      ));
    }
  }
}

/// Phase-3: look-alike TARGET-AUDIENCE chip. Fetches how many tenants in the
/// population best-fit this listing (by embedding similarity) and shows a small
/// glass tag — only when > 0 (dormant until user vectors exist → renders
/// nothing, so no empty clutter today). Fail-soft, one call per card.
class _AudienceChip extends StatefulWidget {
  _AudienceChip({required this.propertyId});
  final String propertyId;

  @override
  State<_AudienceChip> createState() => _AudienceChipState();
}

class _AudienceChipState extends State<_AudienceChip> {
  int _count = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final r = await context
          .read<DatingProvider>()
          .fetchListingAudience(widget.propertyId);
      if (mounted && r.count > 0) setState(() => _count = r.count);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_count <= 0) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return _GlassTag(
      icon: Icons.track_changes_rounded,
      label: l10n.landlordPropertiesScreenAudienceCount(_count),
    );
  }
}

/// Small glassmorphic circular action button used on the property card.
class _GlassAction extends StatelessWidget {
  const _GlassAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ScaleBounce(
      onTap: onTap,
      scaleDownTo: 0.88,
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(8), sigmaY: PlatformFx.blurSigma(8)),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.20),
                width: 1,
              ),
            ),
            child: Center(
              child: RentlyIcon(icon, color: Colors.white, size: 16),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact active/inactive indicator (replaces the large status circle).
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(8), sigmaY: PlatformFx.blurSigma(8)),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isActive
                ? AppColors.success.withValues(alpha: 0.25)
                : Colors.white.withValues(alpha: 0.12),
            border: Border.all(
              color: isActive
                  ? AppColors.success.withValues(alpha: 0.40)
                  : Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Center(
            child: isActive
                ? PulseWidget(
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.success,
                      ),
                    ),
                  )
                : Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white60,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ─── Thumbnail ───────────────────────────────────────────────────────────────

class _PropertyThumb extends StatelessWidget {
  _PropertyThumb({required this.media});

  final PropertyMedia? media;

  @override
  Widget build(BuildContext context) {
    return SafeMedia(
      media: media,
      fallback: _fallback(),
      fit: BoxFit.cover,
      alignment: Alignment.center,
    );
  }

  // Matches the branded fallback on the tenant-facing discover card
  // (profile_card.dart's _ImageFallback) instead of a flat, unbranded tint —
  // a landlord looking at their own draft/photo-less listings previously saw
  // a visibly different, less-finished-looking empty state here.
  Widget _fallback() => Container(
        color: AppColors.navy,
        child: Center(
          child: RentlyIcon(
            IconsaxPlusLinear.building,
            size: 42,
            color: AppColors.primary.withValues(alpha: 0.5),
          ),
        ),
      );
}

// ─── Glassmorphism Tag ────────────────────────────────────────────────────────

class _GlassTag extends StatelessWidget {
  const _GlassTag({
    required this.icon,
    required this.label,
    this.gold = false,
    this.accent = false,
  });

  final IconData icon;
  final String label;
  final bool gold; // Ultra boost — gold fill
  final bool accent; // regular boost — brand accent fill

  @override
  Widget build(BuildContext context) {
    final fill = gold
        ? AppColors.amberDark.withValues(alpha: 0.85)
        : (accent
            ? AppColors.primary.withValues(alpha: 0.85)
            : Colors.black.withValues(alpha: 0.25));
    final borderCol = (gold || accent)
        ? Colors.white.withValues(alpha: 0.45)
        : Colors.white.withValues(alpha: 0.20);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: PlatformFx.blurSigma(8), sigmaY: PlatformFx.blurSigma(8)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: borderCol,
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
  _EmptyPropertiesState();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
              child: RentlyIcon(
                IconsaxPlusLinear.buildings,
                size: 36,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              l10n.landlordPropertiesScreenEmptyTitle,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.landlordPropertiesScreenEmptyBody,
              textAlign: TextAlign.center,
              style: const TextStyle(
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
  _EmptyFilteredState({required this.onClear});

  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
              child: const RentlyIcon(
                IconsaxPlusLinear.search_normal,
                size: 30,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.landlordPropertiesScreenNoResultsTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.landlordPropertiesScreenNoResultsBody,
              textAlign: TextAlign.center,
              style: const TextStyle(
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
              child: Text(
                l10n.landlordPropertiesScreenClearFilters,
                style: const TextStyle(
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
  _FilterPill({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ScaleBounce(
      onTap: onTap,
      scaleDownTo: 0.94,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.navy : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected ? AppColors.navy : AppColors.border,
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

/// Big, friendly choice row for the "create or use ours" contract sheet.
class _ContractSourceButton extends StatelessWidget {
  _ContractSourceButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : AppColors.navy;
    return ScaleBounce(
      onTap: onTap,
      scaleDownTo: 0.96,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: filled ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: filled ? AppColors.primary : AppColors.borderLight,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: filled
                    ? Colors.white.withValues(alpha: 0.18)
                    : AppColors.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: RentlyIcon(
                  icon,
                  color: filled ? Colors.white : AppColors.primary,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: fg,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: filled
                          ? Colors.white.withValues(alpha: 0.85)
                          : AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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

class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({
    super.key,
    required this.index,
    required this.child,
  });
  final int index;
  final Widget child;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacityAnimation;
  late final Animation<double> _slideAnimation;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<double>(begin: 32.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    final delayMs = math.min(widget.index * 60, 400);
    _timer = Timer(Duration(milliseconds: delayMs), () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Transform.translate(
            offset: Offset(0, _slideAnimation.value),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

