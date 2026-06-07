import 'dart:async';
import 'dart:math' as math;

import 'package:dating_app/core/security/input_sanitizer.dart';
import 'package:dating_app/core/security/rate_limiter.dart'
    show RateLimiter, WriteDebouncer;
import 'package:dating_app/core/services/cache_service.dart';
import 'package:dating_app/core/services/event_service.dart';
import 'package:dating_app/core/services/gamification_service.dart';
import 'package:dating_app/core/services/local_storage.dart';
import 'package:dating_app/core/services/rental_data_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/repositories/moderation_repository.dart';
import 'package:dating_app/data/repositories/property_analytics_repository.dart';
import 'package:dating_app/data/repositories/property_repository.dart';
import 'package:dating_app/data/repositories/user_repository.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:latlong2/latlong.dart';

class DatingProvider extends ChangeNotifier {
  DatingProvider({
    RentalDataService? rentalDataService,
    LocalStorageService? localStorageService,
    PropertyRepository? propertyRepository,
    PropertyAnalyticsRepository? propertyAnalyticsRepository,
    UserRepository? userRepository,
    ModerationRepository? moderationRepository,
  })  : _rentalDataService = rentalDataService ?? RentalDataService(),
        _localStorageService = localStorageService ?? LocalStorageService(),
        _propertyRepository = propertyRepository ?? PropertyRepository(),
        _propertyAnalyticsRepository =
            propertyAnalyticsRepository ?? PropertyAnalyticsRepository(),
        _userRepository = userRepository ?? UserRepository(),
        _moderationRepository = moderationRepository ?? ModerationRepository();

  final RentalDataService _rentalDataService;
  final LocalStorageService _localStorageService;
  final PropertyRepository _propertyRepository;
  final PropertyAnalyticsRepository _propertyAnalyticsRepository;
  final UserRepository _userRepository;
  final ModerationRepository _moderationRepository;

  // Batches rapid successive writes so we don't hammer Appwrite on every swipe.
  // With 10k concurrent users, unbatched writes would exhaust API rate limits.
  final _writeDebouncer = WriteDebouncer();

  final CardSwiperController propertySwiperController = CardSwiperController();
  final CardSwiperController ownerSwiperController = CardSwiperController();

  bool _isLoading = true;
  String _userRole = 'tenant';
  bool _isGuestMode = false;
  bool _hasActiveSession = false;
  TenantProfile? _tenantProfile;
  SearchFilters _filters = _defaultFilters;
  List<RentalProperty> _baseProperties = const [];
  List<RentalProperty> _customProperties = [];
  List<SearchArea> _searchAreas = const [];
  List<AppReview> _tenantReviews = const [];
  Map<String, List<AppReview>> _propertyReviews = <String, List<AppReview>>{};
  Set<String> _likedPropertyIds = <String>{};
  Set<String> _passedPropertyIds = <String>{};
  Set<String> _ownerAcceptedPropertyIds = <String>{};
  Set<String> _ownerRejectedPropertyIds = <String>{};
  List<RentalMatch> _matches = const [];
  String? _pendingMatchPropertyId;
  final List<_SwipeRecord> _swipeHistory = [];
  Set<String> _savedPropertyIds = <String>{};
  int _lastSeenMatchCount = 0;
  int _remainingSuperLikes = 3;
  Set<String> _blockedOwnerNames = <String>{};
  Set<String> _reportedPropertyIds = <String>{};
  Map<String, PropertyMarketSignals> _propertySignalOverrides =
      <String, PropertyMarketSignals>{};
  final Map<String, _PropertyDetailSession> _activeDetailSessions =
      <String, _PropertyDetailSession>{};

  // Pagination state — properties are loaded in pages to avoid loading the
  // entire catalog upfront (which would be prohibitive at scale).
  bool _hasMoreProperties = false;
  bool _isLoadingMoreProperties = false;
  bool _isRefreshingRemoteCatalog = false;
  int _propertiesOffset = 0;
  String? _propertiesCursor;

  List<RentalProperty>? _allPropertiesCache;
  Map<String, RentalProperty>? _propertyByIdCache;
  List<RentalProperty>? _filteredPropertiesCache;
  List<String>? _availableFeaturesCache;
  List<String>? _availablePropertyTypesCache;
  List<String>? _availableConditionsCache;
  List<String>? _availableCitiesCache;
  Map<String, double>? _featureWeightCache;
  _MarketIndex? _marketIndexCache;
  int _catalogRevision = 0;
  int _filterRevision = 0;
  int _filterLayoutRevision = 0;
  int _filteredCatalogRevision = -1;
  int _filteredFilterRevision = -1;
  int _featureWeightCatalogRevision = -1;
  int _marketIndexCatalogRevision = -1;

  static const int _missingPriceThreshold = 600;
  static const int _defaultMinBudget = 600;
  static const int _defaultMaxBudget = 40000;
  static const int _saleMinBudget = 100000;
  static const int _saleMaxBudget = 10000000;
  static const int _unsetBudget = 2000000000;
  static const double _unsetMaxRooms = 10;
  static const int _unsetMaxSizeM2 = 1000000;
  static const SearchFilters _defaultFilters = SearchFilters(
    query: '',
    minBudget: _defaultMinBudget,
    maxBudget: _unsetBudget,
    minRooms: 0,
    maxRooms: _unsetMaxRooms,
    areaId: 'all_israel',
    requiredFeatures: <String>{},
    preferredFeatures: <String>{},
    minSizeM2: 0,
    maxSizeM2: _unsetMaxSizeM2,
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

  static const double _budgetWeight = 22;
  static const double _marketValueWeight = 12;
  static const double _locationWeight = 14;
  static const double _roomsWeight = 8;
  static const double _sizeWeight = 5;
  static const double _floorWeight = 1;
  static const double _timingWeight = 8;
  static const double _preferredFeatureWeight = 10;
  static const double _preferredPropertyTypeWeight = 4;
  static const double _preferredConditionWeight = 3;
  static const double _preferredListingSourceWeight = 2;
  static const double _requiredFeatureWeight = 4;
  static const double _listingConfidenceWeight = 12;
  static const double _businessReadinessWeight = 4;

  // Combined property list: base (from JSON) + landlord-added
  List<RentalProperty> get _allProperties {
    final cached = _allPropertiesCache;
    if (cached != null) return cached;
    return _allPropertiesCache = [
      ..._baseProperties.map(_propertyWithSignalOverride),
      ..._customProperties.map(_propertyWithSignalOverride),
    ];
  }

  RentalProperty _propertyWithSignalOverride(RentalProperty property) {
    final signals = _propertySignalOverrides[property.id];
    return signals == null
        ? property
        : property.copyWith(marketSignals: signals);
  }

  void _invalidateCatalogCache() {
    _catalogRevision++;
    _allPropertiesCache = null;
    _propertyByIdCache = null;
    _availableFeaturesCache = null;
    _availablePropertyTypesCache = null;
    _availableConditionsCache = null;
    _availableCitiesCache = null;
    _featureWeightCache = null;
    _marketIndexCache = null;
    _featureWeightCatalogRevision = -1;
    _marketIndexCatalogRevision = -1;
    _invalidateFilterCache();
  }

  void _invalidateFilterCache() {
    _filterRevision++;
    _filterLayoutRevision++;
    _filteredPropertiesCache = null;
  }

  void _removeFromFilteredCache(String propertyId) {
    final cached = _filteredPropertiesCache;
    _filterRevision++;
    _filterLayoutRevision++;
    if (cached == null ||
        _filteredCatalogRevision != _catalogRevision ||
        _filteredFilterRevision < 0) {
      _filteredPropertiesCache = null;
      return;
    }
    _filteredPropertiesCache = [
      for (final property in cached)
        if (property.id != propertyId) property,
    ];
    _filteredCatalogRevision = _catalogRevision;
    _filteredFilterRevision = _filterRevision;
  }

  bool get isLoading => _isLoading;
  bool get isLandlord => _userRole == 'landlord';
  String get userRole => _userRole;
  bool get isGuestMode => _isGuestMode;
  bool get hasActiveSession => _hasActiveSession;
  TenantProfile? get tenantProfile => _tenantProfile;
  SearchFilters get filters => _filters;
  List<SearchArea> get searchAreas => _searchAreas;
  List<AppReview> get tenantReviews => _tenantReviews;
  List<RentalMatch> get matches => _matches;
  int get likesCount => _likedPropertyIds.length;
  Set<String> get likedPropertyIds => _likedPropertyIds;
  int get passedCount => _passedPropertyIds.length;
  int get matchesCount => _matches.length;
  bool get canUndo => _swipeHistory.isNotEmpty;
  int get remainingSuperLikes => _remainingSuperLikes;
  String get _currentOwnerUserId {
    final profileId = _tenantProfile?.id.trim();
    if (profileId != null && profileId.isNotEmpty) return profileId;
    return _isGuestMode ? 'guest_landlord' : 'local_landlord';
  }

  int get trustScore => _tenantProfile == null
      ? 0
      : GamificationService.computeTrustScore(_tenantProfile!, _tenantReviews);

  int get profileCompletion => _tenantProfile == null
      ? 0
      : GamificationService.computeProfileCompletion(_tenantProfile!);

  String get profileCompletionHint => _tenantProfile == null
      ? ''
      : GamificationService.nextCompletionHint(_tenantProfile!);
  RentalProperty? get pendingMatchProperty =>
      propertyById(_pendingMatchPropertyId);
  List<RentalProperty> get myProperties => _customProperties;
  int get unseenMatchCount =>
      (_matches.length - _lastSeenMatchCount).clamp(0, 99);
  List<RentalProperty> get savedProperties =>
      _allProperties.where((p) => _savedPropertyIds.contains(p.id)).toList();
  bool isSaved(String id) => _savedPropertyIds.contains(id);
  LandlordStats get landlordStats => LandlordStats(
        propertiesCount: myProperties.length,
        totalCandidatesSeen: _ownerAcceptedPropertyIds.length +
            _ownerRejectedPropertyIds.length +
            ownerLeads.length,
        matchesCount: matchesCount,
        pendingCount: ownerLeads.length,
      );

  SearchArea get selectedArea {
    if (_filters.hasCustomArea) {
      return SearchArea.custom(polygon: _filters.customAreaPolygon);
    }
    return _searchAreas.firstWhere(
      (area) => area.id == _filters.areaId,
      orElse: () => _searchAreas.first,
    );
  }

  List<String> get availableFeatures {
    final cached = _availableFeaturesCache;
    if (cached != null) return cached;
    final features = <String>{};
    for (final property in _allProperties) {
      features.addAll(property.features);
    }
    final sorted = features.toList()..sort();
    return _availableFeaturesCache = sorted;
  }

  List<String> get availablePropertyTypes {
    final cached = _availablePropertyTypesCache;
    if (cached != null) return cached;
    final types = _allProperties
        .map((property) => property.propertyType.trim())
        .where((type) => type.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return _availablePropertyTypesCache = types;
  }

  List<String> get availableConditions {
    final cached = _availableConditionsCache;
    if (cached != null) return cached;
    final conditions = _allProperties
        .map((property) => property.condition.trim())
        .where((condition) => condition.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return _availableConditionsCache = conditions;
  }

  List<String> get availableCities {
    final cached = _availableCitiesCache;
    if (cached != null) return cached;
    final cities = _allProperties
        .map((property) => property.city.trim())
        .where((city) => city.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return _availableCitiesCache = cities;
  }

  Map<String, double> get _featureWeights {
    final cached = _featureWeightCache;
    if (cached != null && _featureWeightCatalogRevision == _catalogRevision) {
      return cached;
    }

    final frequency = <String, int>{};
    for (final property in _allProperties) {
      for (final feature in property.features.toSet()) {
        frequency[feature] = (frequency[feature] ?? 0) + 1;
      }
    }

    final total = math.max(_allProperties.length, 1);
    final weights = <String, double>{};
    for (final entry in frequency.entries) {
      final idf = math.log((total + 1) / (entry.value + 1)) + 1;
      weights[entry.key] = _clampDouble(idf, 1, 2.4);
    }

    _featureWeightCache = weights;
    _featureWeightCatalogRevision = _catalogRevision;
    return weights;
  }

  _MarketIndex get _marketIndex {
    final cached = _marketIndexCache;
    if (cached != null && _marketIndexCatalogRevision == _catalogRevision) {
      return cached;
    }

    final index = _MarketIndex.fromProperties(_allProperties);
    _marketIndexCache = index;
    _marketIndexCatalogRevision = _catalogRevision;
    return index;
  }

  int get activeFilterCount {
    var count = 0;
    if (_filters.minBudget > _defaultMinBudgetFor(_filters.transactionType)) {
      count++;
    }
    if (_filters.maxBudget < _defaultMaxBudgetFor(_filters.transactionType)) {
      count++;
    }
    if (_filters.minRooms != 0) count++;
    if (_filters.maxRooms < _unsetMaxRooms) count++;
    if (_filters.minSizeM2 > 0) count++;
    if (_filters.maxSizeM2 < _unsetMaxSizeM2) count++;
    if (_filters.minFloor > 0) count++;
    if (_filters.requiredFeatures.isNotEmpty ||
        _filters.preferredFeatures.isNotEmpty) {
      count++;
    }
    if (_filters.propertyTypes.isNotEmpty ||
        _filters.preferredPropertyTypes.isNotEmpty) {
      count++;
    }
    if (_filters.conditions.isNotEmpty ||
        _filters.preferredConditions.isNotEmpty) {
      count++;
    }
    if (_filters.requiredListingSources.isNotEmpty ||
        _filters.preferredListingSources.isNotEmpty ||
        _filters.listingSource != ListingSourceFilter.any) {
      count++;
    }
    if (_filters.requiredMoveInFilters.isNotEmpty ||
        _filters.preferredMoveInFilters.isNotEmpty ||
        _filters.moveInFilter != MoveInFilter.any) {
      count++;
    }
    if (_filters.sortBy != SearchSortOption.bestMatch) count++;
    if (_filters.city.trim().isNotEmpty) count++;
    if (_filters.transactionType != TransactionTypeFilter.any) count++;
    if (_filters.areaId != 'all_israel' || _filters.hasCustomArea) count++;
    if (_filters.includeUnknownPriceListings) count++;
    return count;
  }

  int _defaultMinBudgetFor(TransactionTypeFilter type) {
    switch (type) {
      case TransactionTypeFilter.sale:
        return _saleMinBudget;
      case TransactionTypeFilter.any:
      case TransactionTypeFilter.rent:
        return _defaultMinBudget;
    }
  }

  int _defaultMaxBudgetFor(TransactionTypeFilter type) {
    switch (type) {
      case TransactionTypeFilter.sale:
        return _saleMaxBudget;
      case TransactionTypeFilter.any:
      case TransactionTypeFilter.rent:
        return _defaultMaxBudget;
    }
  }

  SearchFilters _normalizeFilters(SearchFilters filters) {
    final minBudgetFloor = _defaultMinBudgetFor(filters.transactionType);
    final maxBudgetCeiling = _defaultMaxBudgetFor(filters.transactionType);
    final budgetLooksCrossMode = filters.minBudget > maxBudgetCeiling ||
        filters.maxBudget < minBudgetFloor;
    final rawMinBudget =
        budgetLooksCrossMode ? minBudgetFloor : filters.minBudget;
    final rawMaxBudget =
        budgetLooksCrossMode || filters.maxBudget == _unsetBudget
            ? maxBudgetCeiling
            : filters.maxBudget;
    final normalizedMinBudget =
        rawMinBudget.clamp(minBudgetFloor, maxBudgetCeiling);
    final normalizedMaxBudget =
        rawMaxBudget.clamp(normalizedMinBudget, maxBudgetCeiling);
    final normalizedMinRooms =
        _clampDouble(filters.minRooms, 0, _unsetMaxRooms);
    final normalizedMaxRooms =
        _clampDouble(filters.maxRooms, normalizedMinRooms, _unsetMaxRooms);
    final normalizedMinSize = filters.minSizeM2.clamp(0, _unsetMaxSizeM2);
    final normalizedMaxSize =
        filters.maxSizeM2.clamp(normalizedMinSize, _unsetMaxSizeM2);

    return filters.copyWith(
      query: '',
      minBudget: normalizedMinBudget,
      maxBudget: normalizedMaxBudget,
      minRooms: normalizedMinRooms,
      maxRooms: normalizedMaxRooms,
      minSizeM2: normalizedMinSize,
      maxSizeM2: normalizedMaxSize,
      preferredFeatures:
          filters.preferredFeatures.difference(filters.requiredFeatures),
      preferredPropertyTypes:
          filters.preferredPropertyTypes.difference(filters.propertyTypes),
      preferredConditions:
          filters.preferredConditions.difference(filters.conditions),
      requiredListingSources: _normalizedListingSourceRequired(filters),
      preferredListingSources: _normalizedListingSourcePreferred(filters),
      listingSource: ListingSourceFilter.any,
      requiredMoveInFilters: _normalizedMoveInRequired(filters),
      preferredMoveInFilters: _normalizedMoveInPreferred(filters),
      moveInFilter: MoveInFilter.any,
    );
  }

  double get averageFilteredPrice {
    final properties = filteredProperties;
    if (properties.isEmpty) return 0;
    final total =
        properties.fold<int>(0, (sum, property) => sum + property.price);
    return total / properties.length;
  }

  double get averageFilteredSize {
    final properties = filteredProperties;
    if (properties.isEmpty) return 0;
    final total =
        properties.fold<int>(0, (sum, property) => sum + property.sizeM2);
    return total / properties.length;
  }

  List<RentalProperty> get filteredProperties {
    final cached = _filteredPropertiesCache;
    if (cached != null &&
        _filteredCatalogRevision == _catalogRevision &&
        _filteredFilterRevision == _filterRevision) {
      return cached;
    }
    final filtered = _computeFilteredProperties(_filters, sort: true);
    _filteredPropertiesCache = filtered;
    _filteredCatalogRevision = _catalogRevision;
    _filteredFilterRevision = _filterRevision;
    return filtered;
  }

  int get filteredPropertiesRevision => _filterLayoutRevision;

  int filteredCountFor(SearchFilters filters) {
    if (_searchAreas.isEmpty) return 0;
    final now = DateTime.now();
    final area = _areaFor(filters);
    var count = 0;
    for (final property in _allProperties) {
      if (_passesFilters(property, filters, now, area)) count++;
    }
    return count;
  }

  double averagePriceFor(SearchFilters filters) {
    if (_searchAreas.isEmpty) return 0;
    final now = DateTime.now();
    final area = _areaFor(filters);
    var count = 0;
    var total = 0;
    for (final property in _allProperties) {
      if (!_hasKnownPrice(property)) continue;
      if (_passesFilters(property, filters, now, area)) {
        count++;
        total += property.price;
      }
    }
    return count == 0 ? 0 : total / count;
  }

  List<RentalProperty> previewFilteredProperties(
    SearchFilters filters, {
    int limit = 18,
  }) {
    if (_searchAreas.isEmpty || limit <= 0) return const [];
    final now = DateTime.now();
    final area = _areaFor(filters);
    final preview = <RentalProperty>[];
    for (final property in _allProperties) {
      if (_passesFilters(property, filters, now, area)) {
        preview.add(property);
        if (preview.length >= limit) break;
      }
    }
    return preview;
  }

  List<RentalProperty> _computeFilteredProperties(
    SearchFilters filters, {
    required bool sort,
  }) {
    if (_searchAreas.isEmpty) return const [];
    final now = DateTime.now();
    final area = _areaFor(filters);

    final filtered = _allProperties
        .where((property) =>
            !_blockedOwnerNames.contains(property.ownerName) &&
            !_reportedPropertyIds.contains(property.id) &&
            _passesFilters(property, filters, now, area))
        .toList();

    if (!sort) return filtered;
    _sortProperties(filtered, filters, now, area);
    return filtered;
  }

  SearchArea _areaFor(SearchFilters filters) {
    if (filters.hasCustomArea) {
      return SearchArea.custom(polygon: filters.customAreaPolygon);
    }
    return _searchAreas.firstWhere(
      (area) => area.id == filters.areaId,
      orElse: () => _searchAreas.first,
    );
  }

  bool _passesFilters(
    RentalProperty property,
    SearchFilters filters,
    DateTime now,
    SearchArea area,
  ) {
    if (!_passesStructuralFilters(property, filters, area)) return false;

    if (filters.sortBy == SearchSortOption.bestMatch) {
      return _passesBestMatchCandidateGate(property, filters, now);
    }

    return _passesStrictFitFilters(property, filters, now);
  }

  bool _passesStructuralFilters(
    RentalProperty property,
    SearchFilters filters,
    SearchArea area,
  ) {
    if (_likedPropertyIds.contains(property.id) ||
        _passedPropertyIds.contains(property.id)) {
      return false;
    }

    if (filters.city.trim().isNotEmpty &&
        property.city.trim() != filters.city.trim()) {
      return false;
    }

    if (filters.transactionType == TransactionTypeFilter.rent &&
        property.transactionType != PropertyTransactionType.rent) {
      return false;
    }

    if (filters.transactionType == TransactionTypeFilter.sale &&
        property.transactionType != PropertyTransactionType.sale) {
      return false;
    }

    if (filters.propertyTypes.isNotEmpty &&
        !filters.propertyTypes.contains(property.propertyType)) {
      return false;
    }

    if (filters.conditions.isNotEmpty &&
        !filters.conditions.contains(property.condition)) {
      return false;
    }

    final listingSource = _listingSourceFor(property);
    if (filters.requiredListingSources.isNotEmpty &&
        !filters.requiredListingSources.contains(listingSource)) {
      return false;
    }

    if (!filters.requiredFeatures.every(property.features.contains)) {
      return false;
    }

    if (filters.city.trim().isNotEmpty) return true;
    if (filters.areaId == 'all_israel') return true;
    return area.contains(property.point);
  }

  bool _passesStrictFitFilters(
    RentalProperty property,
    SearchFilters filters,
    DateTime now,
  ) {
    final hasKnownPrice = _hasKnownPrice(property);
    if (!hasKnownPrice && !filters.includeUnknownPriceListings) return false;
    if (hasKnownPrice) {
      if (property.price < filters.minBudget) return false;
      if (property.price > filters.maxBudget) return false;
    }
    if (property.rooms < filters.minRooms) return false;
    if (property.rooms > filters.maxRooms) return false;
    if (property.sizeM2 < filters.minSizeM2) return false;
    if (property.sizeM2 > filters.maxSizeM2) return false;
    if (property.floorNumber != null &&
        property.floorNumber! < filters.minFloor) {
      return false;
    }

    return _passesRequiredMoveInFilters(property, filters, now);
  }

  bool _passesBestMatchCandidateGate(
    RentalProperty property,
    SearchFilters filters,
    DateTime now,
  ) {
    final hasKnownPrice = _hasKnownPrice(property);
    if (!hasKnownPrice) {
      if (!filters.includeUnknownPriceListings) return false;
    } else {
      if (filters.minBudget > _defaultMinBudgetFor(filters.transactionType) &&
          property.price < (filters.minBudget * 0.82).round()) {
        return false;
      }
      if (filters.maxBudget < _defaultMaxBudgetFor(filters.transactionType) &&
          property.price > (filters.maxBudget * 1.22).round()) {
        return false;
      }
    }

    if (filters.minRooms > 0 && property.rooms < filters.minRooms - 0.5) {
      return false;
    }
    if (filters.maxRooms < _unsetMaxRooms &&
        property.rooms > filters.maxRooms + 0.5) {
      return false;
    }

    if (filters.minSizeM2 > 0 &&
        property.sizeM2 < (filters.minSizeM2 * 0.78).round()) {
      return false;
    }

    if (filters.maxSizeM2 < _unsetMaxSizeM2 &&
        property.sizeM2 > (filters.maxSizeM2 * 1.4).round()) {
      return false;
    }

    final floorNumber = property.floorNumber;
    if (floorNumber != null &&
        filters.minFloor > 0 &&
        floorNumber < filters.minFloor - 1) {
      return false;
    }

    if (!_passesPreferredMoveInCandidateGate(property, filters, now)) {
      return false;
    }
    return _passesRequiredMoveInFilters(property, filters, now);
  }

  bool _passesRequiredMoveInFilters(
    RentalProperty property,
    SearchFilters filters,
    DateTime now,
  ) {
    if (filters.requiredMoveInFilters.isEmpty) return true;
    return filters.requiredMoveInFilters.any(
      (option) => _matchesMoveInOption(property, option, now),
    );
  }

  bool _passesPreferredMoveInCandidateGate(
    RentalProperty property,
    SearchFilters filters,
    DateTime now,
  ) {
    if (filters.preferredMoveInFilters.isEmpty) return true;
    final deadlines = filters.preferredMoveInFilters
        .map((option) => _moveInDeadlineFor(option, now))
        .whereType<DateTime>()
        .toList();
    if (deadlines.isEmpty) return true;

    final entryDate = property.entryDateValue;
    if (entryDate == null) return false;

    final latestUsefulDate = deadlines
        .map((deadline) => deadline.add(Duration(
            days: _moveInGraceDaysForDeadline(deadline, filters, now))))
        .reduce((a, b) => a.isAfter(b) ? a : b);
    return !entryDate.isAfter(latestUsefulDate);
  }

  DateTime? _moveInDeadlineFor(MoveInFilter option, DateTime now) {
    switch (option) {
      case MoveInFilter.any:
        return null;
      case MoveInFilter.immediate:
        return now;
      case MoveInFilter.within30Days:
        return now.add(const Duration(days: 30));
      case MoveInFilter.within90Days:
        return now.add(const Duration(days: 90));
    }
  }

  int _moveInGraceDaysFor(MoveInFilter option) {
    switch (option) {
      case MoveInFilter.any:
        return 0;
      case MoveInFilter.immediate:
        return 14;
      case MoveInFilter.within30Days:
        return 21;
      case MoveInFilter.within90Days:
        return 30;
    }
  }

  int _moveInGraceDaysForDeadline(
    DateTime deadline,
    SearchFilters filters,
    DateTime now,
  ) {
    for (final option in filters.preferredMoveInFilters) {
      final optionDeadline = _moveInDeadlineFor(option, now);
      if (optionDeadline == deadline) {
        return _moveInGraceDaysFor(option);
      }
    }
    return 0;
  }

  void _sortProperties(
    List<RentalProperty> properties,
    SearchFilters filters,
    DateTime now,
    SearchArea area,
  ) {
    final matchContext = _MatchContext(
      filters: filters,
      now: now,
      area: area,
      featureWeights: _featureWeights,
      marketIndex: _marketIndex,
    );
    final scoreCache = filters.sortBy == SearchSortOption.bestMatch
        ? <String, int>{
            for (final property in properties)
              property.id: _matchScoreForContext(property, matchContext),
          }
        : const <String, int>{};

    properties.sort((a, b) {
      switch (filters.sortBy) {
        case SearchSortOption.priceLowToHigh:
          return a.price.compareTo(b.price);
        case SearchSortOption.priceHighToLow:
          return b.price.compareTo(a.price);
        case SearchSortOption.newestEntry:
          final aDate =
              a.entryDateValue ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bDate =
              b.entryDateValue ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bDate.compareTo(aDate);
        case SearchSortOption.biggestFirst:
          return b.sizeM2.compareTo(a.sizeM2);
        case SearchSortOption.bestMatch:
          final scoreDelta =
              (scoreCache[b.id] ?? 0).compareTo(scoreCache[a.id] ?? 0);
          if (scoreDelta != 0) return scoreDelta;
          final valueDelta = _marketValueScore(b, matchContext)
              .compareTo(_marketValueScore(a, matchContext));
          if (valueDelta != 0) return valueDelta;
          final confidenceDelta =
              _listingConfidenceScore(b).compareTo(_listingConfidenceScore(a));
          if (confidenceDelta != 0) return confidenceDelta;
          final priceDelta = a.price.compareTo(b.price);
          if (priceDelta != 0) return priceDelta;
          return a.id.compareTo(b.id);
      }
    });
  }

  List<RentalProperty> get ownerLeads {
    return _allProperties.where((property) {
      return _likedPropertyIds.contains(property.id) &&
          !_ownerAcceptedPropertyIds.contains(property.id) &&
          !_ownerRejectedPropertyIds.contains(property.id) &&
          !_matches.any((match) => match.propertyId == property.id);
    }).toList();
  }

  RentalProperty? get activeLandlordProxy {
    if (_allProperties.isEmpty) return null;
    if (_likedPropertyIds.isNotEmpty) {
      return propertyById(_likedPropertyIds.first);
    }
    return filteredProperties.isNotEmpty
        ? filteredProperties.first
        : _allProperties.first;
  }

  List<RentalProperty> get landlordProxyPortfolio {
    final featured = <RentalProperty>[];
    final active = activeLandlordProxy;
    if (active != null) {
      featured.add(active);
    }
    for (final property in _allProperties) {
      if (featured.length >= 2) break;
      if (active != null && property.id == active.id) continue;
      featured.add(property);
    }
    return featured;
  }

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    final firstPage = await _rentalDataService.loadFirstPage(
      areaId: _filters.areaId,
    );
    _baseProperties = firstPage.items;
    _hasMoreProperties = firstPage.hasMore;
    _propertiesOffset = firstPage.items.length;
    _propertiesCursor = firstPage.nextCursor;
    _invalidateCatalogCache();
    _searchAreas = _rentalDataService.createSearchAreas();
    if (kDebugMode) {
      debugPrint(
        'DatingProvider.initialize: loaded ${_baseProperties.length} base properties'
        ' (hasMore: $_hasMoreProperties)',
      );
      if (_baseProperties.isNotEmpty) {
        final first = _baseProperties.first;
        debugPrint(
          'DatingProvider.initialize: first property ${first.id} ${first.city} ${first.priceLabel}',
        );
      }
    }

    final storedState = await _localStorageService.loadAppState();
    if (storedState == null || storedState['schema'] != 'rental_match_v2') {
      _seedInitialState();
      _hasActiveSession = false;
    } else {
      _hydrateFromState(storedState);
    }

    _useRemoteCatalogDefaults();
    _filters = _normalizeFilters(_filters);
    _ensureVisibleListings();
    await _persist();

    if (_hasAuthenticatedFirebaseUser) {
      unawaited(_refreshRemoteCatalogAfterAuth());
    }

    _isLoading = false;
    notifyListeners();

    // Log session start after state is ready; set userId if profile exists.
    final profileId = _tenantProfile?.id ?? '';
    if (profileId.isNotEmpty) AppEvents.instance.setUserId(profileId);
    AppEvents.instance.log(UserEventType.sessionStarted, metadata: {
      'role': _userRole,
      'propertiesLoaded': _baseProperties.length,
    });
  }

  bool get hasMoreProperties => _hasMoreProperties;
  bool get isLoadingMoreProperties => _isLoadingMoreProperties;

  // Loads the next property page from Appwrite when the swipe deck runs low.
  // Call from handlePropertySwipe() or when the user scrolls near the end.
  Future<void> loadMorePropertiesIfNeeded() async {
    if (!_hasMoreProperties || _isLoadingMoreProperties) return;
    // Only fetch when the visible deck is running low.
    if (filteredProperties.length > 30) return;

    _isLoadingMoreProperties = true;
    notifyListeners();

    try {
      final page = await _rentalDataService.loadPage(
        offset: _propertiesOffset,
        cursor: _propertiesCursor,
        areaId: _filters.areaId,
      );
      if (page.items.isNotEmpty) {
        _baseProperties = [..._baseProperties, ...page.items];
        _propertiesOffset += page.items.length;
        _hasMoreProperties = page.hasMore;
        _propertiesCursor = page.nextCursor;
        _invalidateCatalogCache();
        if (kDebugMode) {
          debugPrint(
            'DatingProvider.loadMore: +${page.items.length} properties '
            '(total: ${_baseProperties.length}, hasMore: $_hasMoreProperties)',
          );
        }
      } else {
        _hasMoreProperties = false;
        _propertiesCursor = null;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('DatingProvider.loadMore error: $e');
    } finally {
      _isLoadingMoreProperties = false;
      notifyListeners();
    }
  }

  void _useRemoteCatalogDefaults() {
    if (_baseProperties.length < 1000) return;

    _filters = _normalizeFilters(_defaultFilters);
    _likedPropertyIds.clear();
    _passedPropertyIds.clear();
    _invalidateFilterCache();

    if (kDebugMode) {
      debugPrint(
        'DatingProvider.initialize: using open filters for remote catalog',
      );
    }
  }

  void _ensureVisibleListings() {
    if (_baseProperties.isEmpty || filteredProperties.isNotEmpty) return;

    _filters = _filters.copyWith(
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
    _invalidateFilterCache();

    if (filteredProperties.isNotEmpty) {
      if (kDebugMode) {
        debugPrint(
          'DatingProvider.initialize: widened filters to show remote listings',
        );
      }
      return;
    }

    _likedPropertyIds.clear();
    _passedPropertyIds.clear();
    _invalidateFilterCache();

    if (kDebugMode) {
      debugPrint(
        'DatingProvider.initialize: cleared swipe history to restore visible listings',
      );
    }
  }

  Future<void> setUserRole(String role) async {
    _userRole = role;
    _isGuestMode = false;
    _hasActiveSession = true;
    await _refreshRemoteCatalogAfterAuth();
    await _persist();
    AppEvents.instance.log(UserEventType.roleChanged, metadata: {'role': role});
    notifyListeners();
  }

  Future<void> _refreshRemoteCatalogAfterAuth() async {
    if (_isRefreshingRemoteCatalog) return;
    if (!_hasAuthenticatedFirebaseUser) return;

    _isRefreshingRemoteCatalog = true;
    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      AppCache.instance.propertyPages.clear();

      final firstPage = await _rentalDataService.loadFirstPage(
        areaId: _filters.areaId,
      );

      var items = firstPage.items;
      var hasMore = firstPage.hasMore;
      var cursor = firstPage.nextCursor;
      var offset = firstPage.items.length;
      var pagesLoaded = 1;

      while (
          hasMore && cursor != null && cursor.isNotEmpty && pagesLoaded < 50) {
        final page = await _rentalDataService.loadPage(
          offset: offset,
          cursor: cursor,
          areaId: _filters.areaId,
        );
        if (page.items.isEmpty) break;
        items = [...items, ...page.items];
        offset += page.items.length;
        hasMore = page.hasMore;
        cursor = page.nextCursor;
        pagesLoaded += 1;
      }

      if (items.isEmpty) return;

      _baseProperties = items;
      _hasMoreProperties = hasMore;
      _propertiesOffset = offset;
      _propertiesCursor = cursor;
      _invalidateCatalogCache();
      _useRemoteCatalogDefaults();
      _filters = _normalizeFilters(_filters);
      _ensureVisibleListings();
      if (kDebugMode) {
        debugPrint(
          'DatingProvider.refreshRemoteCatalog: loaded ${_baseProperties.length} base properties'
          ' (hasMore: $_hasMoreProperties)',
        );
      }
    } catch (error) {
      if (kDebugMode) {
        debugPrint('DatingProvider.refreshRemoteCatalog failed: $error');
      }
    } finally {
      _isRefreshingRemoteCatalog = false;
    }
  }

  bool get _hasAuthenticatedFirebaseUser {
    if (Firebase.apps.isEmpty) return false;
    try {
      return FirebaseAuth.instance.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> enterGuestMode(String role) async {
    _seedGuestDemoState(role);
    _hasActiveSession = true;
    await _persist();
    notifyListeners();
  }

  Future<void> logout() async {
    AppEvents.instance.log(UserEventType.sessionEnded);
    await _localStorageService.clearAppState();
    _customProperties = [];
    _invalidateCatalogCache();
    _userRole = 'tenant';
    _isGuestMode = false;
    _hasActiveSession = false;
    _seedInitialState();
    await _persist();
    // Clear circuit breakers and rate-limit buckets on logout.
    RateLimiter.instance.reset();
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    final userId = _tenantProfile?.id ?? '';
    AppEvents.instance.log(UserEventType.sessionEnded,
        metadata: {'reason': 'account_deleted'});
    await _localStorageService.clearAppState();
    if (userId.isNotEmpty) {
      unawaited(_userRepository.deleteProfile(userId));
    }
    _customProperties = [];
    _invalidateCatalogCache();
    _tenantProfile = null;
    _userRole = 'tenant';
    _isGuestMode = false;
    _hasActiveSession = false;
    _likedPropertyIds.clear();
    _passedPropertyIds.clear();
    _swipeHistory.clear();
    _invalidateFilterCache();
    _matches = const [];
    notifyListeners();
  }

  Future<void> updateTenantProfile(TenantProfile updatedProfile) async {
    _tenantProfile = updatedProfile;
    await _persist();
    // Sync to discovery table so this user appears in other users' feeds.
    unawaited(_userRepository.upsertProfile(
      updatedProfile,
      role: _userRole,
      discoverable: !_isGuestMode,
    ));
    AppEvents.instance
      ..setUserId(updatedProfile.id)
      ..log(UserEventType.profileUpdated);
    notifyListeners();
  }

  Future<void> applyGoogleIdentity({
    required String displayName,
    String? photoUrl,
  }) async {
    final current =
        _tenantProfile ?? _rentalDataService.createDefaultTenantProfile();
    final nextPhotos = <String>[
      if (photoUrl != null && photoUrl.trim().isNotEmpty) photoUrl.trim(),
      ...current.photoUrls.where((url) => url != photoUrl),
    ];
    _tenantProfile = current.copyWith(
      name: displayName.trim().isEmpty ? current.name : displayName.trim(),
      photoUrls: nextPhotos,
    );
    _isGuestMode = false;
    await _persist();
    unawaited(_userRepository.upsertProfile(
      _tenantProfile!,
      role: _userRole,
      discoverable: true,
    ));
    AppEvents.instance
      ..setUserId(_tenantProfile!.id)
      ..log(UserEventType.profileUpdated, metadata: {'source': 'google'});
    notifyListeners();
  }

  Future<void> updateFilters(SearchFilters filters) async {
    _filters = _normalizeFilters(filters);
    _invalidateFilterCache();
    await _persist();
    notifyListeners();
  }

  // [status] defaults to active. Pass [PropertyRecordStatus.draft] when
  // creating an incomplete property (e.g. during registration) so consent
  // enforcement is skipped for drafts and applied only on active listings.
  Future<void> addLandlordProperty(
    RentalProperty property, {
    PropertyRecordStatus status = PropertyRecordStatus.active,
  }) async {
    _customProperties = [..._customProperties, property];
    _invalidateCatalogCache();
    await _persist();
    unawaited(
      _propertyRepository
          .saveProperty(property,
              ownerUserId: _currentOwnerUserId, status: status)
          .then((result) {
        if (!result.isOk && kDebugMode) {
          debugPrint(
              'addLandlordProperty: remote rejected — ${result.userMessage}');
        }
      }),
    );
    AppEvents.instance.log(
      UserEventType.propertyAdded,
      propertyId: property.id,
      metadata: {
        'city': property.city,
        'type': property.propertyType,
        'status': status.name,
      },
    );
    notifyListeners();
  }

  Future<void> updateLandlordProperty(RentalProperty updated) async {
    _customProperties =
        _customProperties.map((p) => p.id == updated.id ? updated : p).toList();
    _invalidateCatalogCache();
    await _persist();
    unawaited(
      _propertyRepository
          .saveProperty(updated, ownerUserId: _currentOwnerUserId)
          .then((result) {
        if (!result.isOk && kDebugMode) {
          debugPrint(
              'updateLandlordProperty: remote rejected — ${result.userMessage}');
        }
      }),
    );
    AppEvents.instance
        .log(UserEventType.propertyUpdated, propertyId: updated.id);
    notifyListeners();
  }

  Future<void> removeLandlordProperty(String propertyId) async {
    _customProperties =
        _customProperties.where((p) => p.id != propertyId).toList();
    _invalidateCatalogCache();
    await _persist();
    unawaited(_propertyRepository.deleteProperty(propertyId));
    notifyListeners();
  }

  Future<void> attachPropertyVirtualTour({
    required String propertyId,
    required PropertyVirtualTour tour,
  }) async {
    var changed = false;
    final updated = _customProperties.map((property) {
      if (property.id != propertyId) return property;
      changed = true;
      return property.copyWith(virtualTour: tour);
    }).toList();
    if (!changed) return;
    _customProperties = updated;
    _invalidateCatalogCache();
    await _persist();
    final property = propertyById(propertyId);
    if (property != null) {
      unawaited(_propertyRepository
          .saveProperty(property, ownerUserId: _currentOwnerUserId)
          .then((result) {
        if (!result.isOk && kDebugMode) {
          debugPrint(
              'attachPropertyVirtualTour: remote rejected — ${result.userMessage}');
        }
      }));
      AppEvents.instance
          .log(UserEventType.tourUploaded, propertyId: propertyId);
    }
    notifyListeners();
  }

  void beginPropertyDetailView(String propertyId) {
    if (propertyId.trim().isEmpty ||
        _activeDetailSessions.containsKey(propertyId)) {
      return;
    }

    final now = DateTime.now();
    final session = _PropertyDetailSession(
      propertyId: propertyId,
      sessionId: _newDetailSessionId(propertyId),
      startedAt: now,
    );
    session.heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      final activeSession = _activeDetailSessions[propertyId];
      if (activeSession == null) return;
      unawaited(
        _propertyAnalyticsRepository.heartbeatViewSession(
          sessionId: activeSession.sessionId,
          startedAt: activeSession.startedAt,
          photoSwipeCount: activeSession.photoSwipeCount,
          currentPhotoIndex: activeSession.currentPhotoIndex,
        ),
      );
      unawaited(refreshPropertySignals(propertyId));
    });
    _activeDetailSessions[propertyId] = session;

    final current = _signalsFor(propertyId).normalizedForToday(now);
    _setPropertySignals(
      propertyId,
      current.copyWith(
        views: current.views + 1,
        detailViews: current.detailViews + 1,
        liveViewers: current.liveViewers + 1,
        lastViewedAt: now,
      ),
    );

    unawaited(
      _propertyAnalyticsRepository.startViewSession(
        sessionId: session.sessionId,
        propertyId: propertyId,
        userId: _currentAnalyticsUserId,
        startedAt: now,
      ),
    );
    unawaited(refreshPropertySignals(propertyId));
    unawaited(_persist());
    notifyListeners();
  }

  void recordPropertyGallerySwipe(String propertyId, int currentPhotoIndex) {
    final session = _activeDetailSessions[propertyId];
    if (session == null) return;

    session.photoSwipeCount += 1;
    session.currentPhotoIndex = currentPhotoIndex;
    final current = _signalsFor(propertyId).normalizedForToday(DateTime.now());
    _setPropertySignals(
      propertyId,
      current.copyWith(gallerySwipes: current.gallerySwipes + 1),
    );
    unawaited(
      _propertyAnalyticsRepository.heartbeatViewSession(
        sessionId: session.sessionId,
        startedAt: session.startedAt,
        photoSwipeCount: session.photoSwipeCount,
        currentPhotoIndex: session.currentPhotoIndex,
      ),
    );
    unawaited(_persist());
    notifyListeners();
  }

  Future<void> endPropertyDetailView(String propertyId) async {
    final session = _activeDetailSessions.remove(propertyId);
    if (session == null) return;

    session.heartbeatTimer?.cancel();
    final endedAt = DateTime.now();
    final durationSeconds =
        math.max(0, endedAt.difference(session.startedAt).inSeconds);
    final current = _signalsFor(propertyId).normalizedForToday(endedAt);
    final completedBefore = math.max(0, current.detailViews - 1);
    final avgStay = completedBefore <= 0
        ? durationSeconds
        : ((current.avgDetailStaySeconds * completedBefore) +
                durationSeconds) ~/
            (completedBefore + 1);

    _setPropertySignals(
      propertyId,
      current.copyWith(
        liveViewers: math.max(0, current.liveViewers - 1),
        avgDetailStaySeconds: avgStay,
        lastViewedAt: endedAt,
      ),
    );

    await _propertyAnalyticsRepository.endViewSession(
      sessionId: session.sessionId,
      startedAt: session.startedAt,
      photoSwipeCount: session.photoSwipeCount,
      currentPhotoIndex: session.currentPhotoIndex,
      endedAt: endedAt,
    );
    unawaited(refreshPropertySignals(propertyId));
    await _persist();
    notifyListeners();
  }

  Future<void> refreshPropertySignals(String propertyId) async {
    final snapshot =
        await _propertyAnalyticsRepository.fetchSnapshot(propertyId);
    if (snapshot == null) return;

    final current = _signalsFor(propertyId).normalizedForToday(DateTime.now());
    _setPropertySignals(
      propertyId,
      current.copyWith(
        liveViewers: snapshot.liveViewers,
        likesToday: snapshot.likesToday,
        likesTodayDate: snapshot.likesTodayDate,
      ),
    );
    await _persist();
    notifyListeners();
  }

  Future<void> likeProperty(String propertyId) async {
    if (!_likedPropertyIds.contains(propertyId)) {
      _likedPropertyIds.add(propertyId);
      _recordPropertyLike(propertyId);
      _swipeHistory.add(_SwipeRecord(propertyId: propertyId, liked: true));
      if (_swipeHistory.length > 10) _swipeHistory.removeAt(0);
      _removeFromFilteredCache(propertyId);
      await _persist();
      notifyListeners();
    }
  }

  void _recordPropertyLike(String propertyId) {
    final now = DateTime.now();
    final current = _signalsFor(propertyId).normalizedForToday(now);
    _setPropertySignals(
      propertyId,
      current.copyWith(
        likes: current.likes + 1,
        likesToday: current.likesToday + 1,
        likesTodayDate: _todayKey(now),
      ),
    );
    unawaited(
      _propertyAnalyticsRepository.recordLike(
        propertyId: propertyId,
        userId: _currentAnalyticsUserId,
        likedAt: now,
      ),
    );
    unawaited(refreshPropertySignals(propertyId));
  }

  void _removePropertyLike(String propertyId) {
    final now = DateTime.now();
    final current = _signalsFor(propertyId).normalizedForToday(now);
    _setPropertySignals(
      propertyId,
      current.copyWith(
        likes: math.max(0, current.likes - 1),
        likesToday: math.max(0, current.likesToday - 1),
        likesTodayDate: _todayKey(now),
      ),
    );
    unawaited(
      _propertyAnalyticsRepository.removeLike(
        propertyId: propertyId,
        userId: _currentAnalyticsUserId,
        likedAt: now,
      ),
    );
    unawaited(refreshPropertySignals(propertyId));
  }

  PropertyMarketSignals _signalsFor(String propertyId) {
    final override = _propertySignalOverrides[propertyId];
    if (override != null) return override;
    return propertyById(propertyId)?.marketSignals ??
        const PropertyMarketSignals();
  }

  void _setPropertySignals(String propertyId, PropertyMarketSignals signals) {
    _propertySignalOverrides[propertyId] = signals;
    _baseProperties = _baseProperties
        .map((property) => property.id == propertyId
            ? property.copyWith(marketSignals: signals)
            : property)
        .toList();
    _customProperties = _customProperties
        .map((property) => property.id == propertyId
            ? property.copyWith(marketSignals: signals)
            : property)
        .toList();
    _invalidateCatalogCache();
  }

  String get _currentAnalyticsUserId {
    final profileId = _tenantProfile?.id.trim();
    if (profileId != null && profileId.isNotEmpty) return profileId;
    if (_isGuestMode) return 'guest_$_userRole';
    return 'local_user';
  }

  String _newDetailSessionId(String propertyId) {
    final raw = 'view_${propertyId}_${DateTime.now().microsecondsSinceEpoch}_'
        '${math.Random().nextInt(999999)}';
    return raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  }

  String _todayKey(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  Future<void> swipePropertyLeft() async {
    propertySwiperController.swipe(CardSwiperDirection.left);
  }

  Future<void> swipePropertyRight() async {
    propertySwiperController.swipe(CardSwiperDirection.right);
  }

  Future<bool> superLikeProperty() async {
    final ok = await GamificationService.consumeSuperLike();
    if (!ok) return false;
    _remainingSuperLikes = await GamificationService.getRemainingSuperlikes();
    notifyListeners();
    propertySwiperController.swipe(CardSwiperDirection.top);
    return true;
  }

  Future<void> refreshSuperLikes() async {
    _remainingSuperLikes = await GamificationService.getRemainingSuperlikes();
    notifyListeners();
  }

  Future<void> undoSwipe() async {
    if (_swipeHistory.isEmpty) return;
    final last = _swipeHistory.removeLast();
    if (last.liked) {
      _likedPropertyIds.remove(last.propertyId);
      _removePropertyLike(last.propertyId);
    } else {
      _passedPropertyIds.remove(last.propertyId);
    }
    propertySwiperController.undo();
    _invalidateFilterCache();
    await _persist();
    notifyListeners();
  }

  Future<bool> handlePropertySwipe(
    int previousIndex,
    int? currentIndex,
    CardSwiperDirection direction,
  ) async {
    final deck = filteredProperties;
    if (previousIndex < 0 || previousIndex >= deck.length) return false;

    final property = deck[previousIndex];
    if (direction == CardSwiperDirection.left) {
      _passedPropertyIds.add(property.id);
      _swipeHistory.add(_SwipeRecord(propertyId: property.id, liked: false));
      AppEvents.instance.log(UserEventType.swipeLeft, propertyId: property.id);
    } else if (direction == CardSwiperDirection.right ||
        direction == CardSwiperDirection.top) {
      final isNewLike = _likedPropertyIds.add(property.id);
      if (isNewLike) _recordPropertyLike(property.id);
      _swipeHistory.add(_SwipeRecord(propertyId: property.id, liked: true));
      final eventType = direction == CardSwiperDirection.top
          ? UserEventType.superLike
          : UserEventType.swipeRight;
      AppEvents.instance.log(eventType, propertyId: property.id);

      // Simulate owner acceptance: ~40% chance for regular swipe, 100% for super-like.
      // In production this would be replaced by a real server-side mutual match signal.
      final matchChance = direction == CardSwiperDirection.top ? 1.0 : 0.40;
      if (math.Random().nextDouble() < matchChance) {
        _ownerAcceptedPropertyIds.add(property.id);
        _createMatch(property);
      }
    } else {
      return false;
    }
    if (_swipeHistory.length > 10) _swipeHistory.removeAt(0);
    _removeFromFilteredCache(property.id);

    await _persist();
    notifyListeners();

    // Proactively fetch next page when the deck is getting short.
    unawaited(loadMorePropertiesIfNeeded());
    return true;
  }

  Future<void> ownerSwipeLeft() async {
    ownerSwiperController.swipe(CardSwiperDirection.left);
  }

  Future<void> ownerSwipeRight() async {
    ownerSwiperController.swipe(CardSwiperDirection.right);
  }

  Future<bool> handleOwnerSwipe(
    int previousIndex,
    int? currentIndex,
    CardSwiperDirection direction,
  ) async {
    final leads = ownerLeads;
    if (previousIndex < 0 || previousIndex >= leads.length) return false;

    final property = leads[previousIndex];
    if (direction == CardSwiperDirection.left) {
      _ownerRejectedPropertyIds.add(property.id);
    } else if (direction == CardSwiperDirection.right ||
        direction == CardSwiperDirection.top) {
      _ownerAcceptedPropertyIds.add(property.id);
      _createMatch(property);
    } else {
      return false;
    }

    await _persist();
    notifyListeners();
    return true;
  }

  void clearPendingMatch() {
    if (_pendingMatchPropertyId == null) return;
    _pendingMatchPropertyId = null;
    notifyListeners();
  }

  RentalProperty? propertyById(String? propertyId) {
    if (propertyId == null) return null;
    final cached = _propertyByIdCache;
    if (cached != null) return cached[propertyId];
    final byId = <String, RentalProperty>{
      for (final property in _allProperties) property.id: property,
    };
    _propertyByIdCache = byId;
    return byId[propertyId];
  }

  RentalMatch? matchById(String matchId) {
    for (final match in _matches) {
      if (match.id == matchId) return match;
    }
    return null;
  }

  List<AppReview> propertyReviews(String propertyId) {
    return _propertyReviews[propertyId] ?? const [];
  }

  double reviewAverage(List<AppReview> reviews) {
    if (reviews.isEmpty) return 0;
    final total = reviews.fold<int>(0, (sum, r) => sum + r.rating);
    return total / reviews.length;
  }

  Future<void> addPropertyReview({
    required String propertyId,
    required int rating,
    required String text,
  }) async {
    final current = _propertyReviews[propertyId] ?? const [];
    _propertyReviews = {
      ..._propertyReviews,
      propertyId: [
        ...current,
        AppReview(
          id: 'property-review-${DateTime.now().microsecondsSinceEpoch}',
          authorName: _tenantProfile?.name ?? 'שוכר',
          rating: rating,
          text: text,
        ),
      ],
    };
    await _persist();
    notifyListeners();
  }

  Future<void> addTenantReview({
    required int rating,
    required String text,
  }) async {
    _tenantReviews = [
      ..._tenantReviews,
      AppReview(
        id: 'tenant-review-${DateTime.now().microsecondsSinceEpoch}',
        authorName: 'בעל דירה',
        rating: rating,
        text: text,
      ),
    ];
    await _persist();
    notifyListeners();
  }

  Future<void> sendMessage({
    required String matchId,
    required String sender,
    required String text,
  }) async {
    final index = _matches.indexWhere((m) => m.id == matchId);
    if (index == -1 || text.trim().isEmpty) return;

    final match = _matches[index];
    final updatedMatch = match.copyWith(
      messages: [
        ...match.messages,
        ChatMessage(
          id: 'message-${DateTime.now().microsecondsSinceEpoch}',
          sender: sender,
          text: text.trim(),
          createdAt: DateTime.now(),
        ),
      ],
    );
    _replaceMatch(index, updatedMatch);
    await _persist();
    notifyListeners();
  }

  Future<void> sendContract(String matchId) async {
    final index = _matches.indexWhere((m) => m.id == matchId);
    if (index == -1) return;

    final match = _matches[index];
    final updatedMatch = match.copyWith(
      contractSent: true,
      messages: [
        ...match.messages,
        ChatMessage(
          id: 'contract-${DateTime.now().microsecondsSinceEpoch}',
          sender: 'בעל הדירה',
          text: 'שלחתי חוזה דיגיטלי וטפסים לחתימה.',
          createdAt: DateTime.now(),
        ),
      ],
    );
    _replaceMatch(index, updatedMatch);
    await _persist();
    notifyListeners();
  }

  Future<void> signContract(String matchId, {required bool asOwner}) async {
    final index = _matches.indexWhere((m) => m.id == matchId);
    if (index == -1) return;

    final match = _matches[index];
    final updatedMatch = match.copyWith(
      ownerSigned: asOwner ? true : match.ownerSigned,
      tenantSigned: asOwner ? match.tenantSigned : true,
      messages: [
        ...match.messages,
        ChatMessage(
          id: 'signature-${DateTime.now().microsecondsSinceEpoch}',
          sender: asOwner ? 'בעל הדירה' : _tenantProfile?.name ?? 'השוכר',
          text: asOwner ? 'חתמתי כבעל הדירה.' : 'חתמתי כשוכר/ת.',
          createdAt: DateTime.now(),
        ),
      ],
    );
    _replaceMatch(index, updatedMatch);
    await _persist();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final session in _activeDetailSessions.values) {
      session.heartbeatTimer?.cancel();
    }
    _activeDetailSessions.clear();
    propertySwiperController.dispose();
    ownerSwiperController.dispose();
    super.dispose();
  }

  Future<void> toggleSave(String propertyId) async {
    if (_savedPropertyIds.contains(propertyId)) {
      _savedPropertyIds.remove(propertyId);
    } else {
      _savedPropertyIds.add(propertyId);
    }
    await _persist();
    notifyListeners();
  }

  bool isOwnerBlocked(String ownerName) =>
      _blockedOwnerNames.contains(ownerName);

  bool isPropertyReported(String propertyId) =>
      _reportedPropertyIds.contains(propertyId);

  Future<void> reportProperty(String propertyId, String reason) async {
    // 1. Remove from local feed immediately.
    _reportedPropertyIds.add(propertyId);
    _removeFromFilteredCache(propertyId);
    await _persist();
    notifyListeners();

    // 2. Notify developer via Appwrite so the report can be reviewed within 24h.
    //    Apple Guideline 1.2 requires reports reach the developer.
    final property = propertyById(propertyId);
    unawaited(_moderationRepository.reportContent(
      reporterUserId: _tenantProfile?.id ?? 'anonymous',
      propertyId: propertyId,
      ownerName: property?.ownerName ?? '',
      reason: reason,
    ));
    AppEvents.instance.log(UserEventType.propertyReported,
        propertyId: propertyId, metadata: {'reason': reason});
  }

  Future<void> blockOwner(String ownerName) async {
    // 1. Hide all their listings instantly.
    _blockedOwnerNames.add(ownerName);
    _invalidateFilterCache();
    await _persist();
    notifyListeners();

    // 2. Notify developer — Apple requires blocks notify the developer.
    unawaited(_moderationRepository.reportBlock(
      reporterUserId: _tenantProfile?.id ?? 'anonymous',
      blockedOwnerName: ownerName,
    ));
    AppEvents.instance.log(UserEventType.propertyReported,
        metadata: {'action': 'block_owner', 'owner': ownerName});
  }

  void markMatchesSeen() {
    if (_lastSeenMatchCount >= _matches.length) return;
    _lastSeenMatchCount = _matches.length;
    notifyListeners();
  }

  Future<void> resetPassed() async {
    _passedPropertyIds.clear();
    _swipeHistory.removeWhere((r) => !r.liked);
    _invalidateFilterCache();
    await _persist();
    notifyListeners();
  }

  int matchScore(RentalProperty p) {
    if (_searchAreas.isEmpty) return 0;
    return _matchScoreFor(p, _filters, DateTime.now(), selectedArea);
  }

  int _matchScoreFor(
    RentalProperty p,
    SearchFilters filters,
    DateTime now,
    SearchArea area,
  ) {
    return _matchScoreForContext(
      p,
      _MatchContext(
        filters: filters,
        now: now,
        area: area,
        featureWeights: _featureWeights,
        marketIndex: _marketIndex,
      ),
    );
  }

  int _matchScoreForContext(RentalProperty p, _MatchContext context) {
    final filters = context.filters;
    if (!filters.requiredFeatures.every(p.features.contains)) {
      return 0;
    }
    if (filters.propertyTypes.isNotEmpty &&
        !filters.propertyTypes.contains(p.propertyType)) {
      return 0;
    }
    if (filters.conditions.isNotEmpty &&
        !filters.conditions.contains(p.condition)) {
      return 0;
    }
    if (filters.requiredListingSources.isNotEmpty &&
        !filters.requiredListingSources.contains(_listingSourceFor(p))) {
      return 0;
    }
    if (filters.requiredMoveInFilters.isNotEmpty &&
        !filters.requiredMoveInFilters.any(
          (option) => _matchesMoveInOption(p, option, context.now),
        )) {
      return 0;
    }

    final score = _budgetFitScore(p, filters) +
        _marketValueScore(p, context) +
        _locationScore(p, context) +
        _spaceFitScore(p, filters) +
        _moveInScore(p, filters, context.now) +
        _featureFitScore(p, context) +
        _listingConfidenceScore(p) +
        _businessReadinessScore(p, context);

    return _clampDouble(score, 0, 100).round();
  }

  double _budgetFitScore(RentalProperty property, SearchFilters filters) {
    if (!_hasKnownPrice(property)) {
      return filters.includeUnknownPriceListings ? _budgetWeight * 0.2 : 0;
    }

    final hasMin =
        filters.minBudget > _defaultMinBudgetFor(filters.transactionType);
    final hasMax =
        filters.maxBudget < _defaultMaxBudgetFor(filters.transactionType);
    if (!hasMin && !hasMax) return _budgetWeight;

    final price = property.price.toDouble();
    if ((!hasMin || price >= filters.minBudget) &&
        (!hasMax || price <= filters.maxBudget)) {
      return _budgetWeight;
    }

    if (hasMin && price < filters.minBudget) {
      final gap = (filters.minBudget - price) / filters.minBudget;
      return _budgetWeight * _expDecay(gap / 0.3, 1.2);
    }

    final overage = (price - filters.maxBudget) / filters.maxBudget;
    return _budgetWeight * _expDecay(overage / 0.18, 1.45);
  }

  double _marketValueScore(RentalProperty property, _MatchContext context) {
    final pricePerM2 = property.pricePerSquareMeter;
    final stats = context.marketIndex.resolve(property);
    if (pricePerM2 == null || pricePerM2 <= 0 || stats == null) {
      return _marketValueWeight * 0.68;
    }

    final median = stats.medianPricePerM2;
    if (median <= 0) return _marketValueWeight * 0.68;

    if (pricePerM2 <= median) {
      final discount =
          _clampDouble((median - pricePerM2) / median / 0.18, 0, 1);
      return _marketValueWeight * (0.9 + discount * 0.1);
    }

    final overMarket = (pricePerM2 - median) / median;
    final scale = math.max(stats.relativeMad * 1.4, 0.18);
    return _marketValueWeight * _expDecay(overMarket / scale, 1.35);
  }

  double _locationScore(RentalProperty property, _MatchContext context) {
    final filters = context.filters;
    final selectedCity = filters.city.trim();
    if (selectedCity.isNotEmpty) {
      return property.city.trim() == selectedCity ? _locationWeight : 0;
    }

    if (filters.hasCustomArea) {
      return context.area.contains(property.point) ? _locationWeight : 0;
    }
    if (filters.areaId == 'all_israel') return _locationWeight;
    return context.area.contains(property.point) ? _locationWeight : 0;
  }

  double _spaceFitScore(RentalProperty property, SearchFilters filters) {
    return _roomsFitScore(property, filters) +
        _sizeFitScore(property, filters) +
        _floorFitScore(property, filters);
  }

  double _roomsFitScore(RentalProperty property, SearchFilters filters) {
    final hasMin = filters.minRooms > 0;
    final hasMax = filters.maxRooms < _unsetMaxRooms;
    if (!hasMin && !hasMax) return _roomsWeight;

    if ((!hasMin || property.rooms >= filters.minRooms) &&
        (!hasMax || property.rooms <= filters.maxRooms)) {
      return _roomsWeight;
    }

    final shortage = filters.minRooms - property.rooms;
    if (hasMin && shortage > 0) {
      if (shortage <= 0.5) {
        return _roomsWeight * (1 - shortage * 0.9);
      }
      return _roomsWeight * _expDecay(shortage / 0.5, 1.25) * 0.35;
    }

    final excess = property.rooms - filters.maxRooms;
    if (hasMax && excess <= 0.5) {
      return _roomsWeight * (1 - excess * 0.4);
    }
    return _roomsWeight * _expDecay(excess / 0.75, 1.2) * 0.55;
  }

  double _sizeFitScore(RentalProperty property, SearchFilters filters) {
    final hasMin = filters.minSizeM2 > 0;
    final hasMax = filters.maxSizeM2 < _unsetMaxSizeM2;
    if (!hasMin && !hasMax) return _sizeWeight;
    if (property.sizeM2 <= 0) return _sizeWeight * 0.45;

    final size = property.sizeM2.toDouble();
    final minSize = filters.minSizeM2.toDouble();
    final maxSize = filters.maxSizeM2.toDouble();

    if ((!hasMin || size >= minSize) && (!hasMax || size <= maxSize)) {
      return _sizeWeight;
    }

    if (hasMin && size < minSize) {
      final deficit = (minSize - size) / minSize;
      return _sizeWeight * _expDecay(deficit / 0.24, 1.3);
    }

    final oversize = (size - maxSize) / maxSize;
    return _sizeWeight * _expDecay(oversize / 0.75, 1.15);
  }

  double _floorFitScore(RentalProperty property, SearchFilters filters) {
    if (filters.minFloor <= 0) return _floorWeight;

    final floorNumber = property.floorNumber;
    if (floorNumber == null) return _floorWeight * 0.45;
    if (floorNumber >= filters.minFloor) return _floorWeight;
    if (floorNumber == filters.minFloor - 1) return _floorWeight * 0.45;
    return 0;
  }

  double _featureFitScore(RentalProperty property, _MatchContext context) {
    final filters = context.filters;
    final requiredScore = _requiredFeatureWeight;
    final featureScore = filters.preferredFeatures.isEmpty
        ? _preferredFeatureWeight
        : _weightedSetPreferenceScore(
            actualValues: property.features.toSet(),
            preferredValues: filters.preferredFeatures,
            totalWeight: _preferredFeatureWeight,
            weightLookup: (feature) => context.featureWeights[feature] ?? 1,
          );

    return requiredScore +
        featureScore +
        _setPreferenceScore(
          actualValue: property.propertyType,
          preferredValues: filters.preferredPropertyTypes,
          totalWeight: _preferredPropertyTypeWeight,
        ) +
        _setPreferenceScore(
          actualValue: property.condition,
          preferredValues: filters.preferredConditions,
          totalWeight: _preferredConditionWeight,
        ) +
        _setPreferenceScore(
          actualValue: _listingSourceFor(property),
          preferredValues: filters.preferredListingSources,
          totalWeight: _preferredListingSourceWeight,
        );
  }

  /// Concave reward: f(x) = 1 − (1−x)^1.5
  /// Partial tag matches are still rewarded, but full match is best.
  double _concaveReward(double ratio) {
    final clamped = _clampDouble(ratio, 0, 1);
    return 1.0 - math.pow(1.0 - clamped, 1.5).toDouble();
  }

  double _setPreferenceScore<T>({
    required T actualValue,
    required Set<T> preferredValues,
    required double totalWeight,
  }) {
    if (preferredValues.isEmpty) return totalWeight;
    return preferredValues.contains(actualValue) ? totalWeight : 0;
  }

  double _weightedSetPreferenceScore({
    required Set<String> actualValues,
    required Set<String> preferredValues,
    required double totalWeight,
    required double Function(String value) weightLookup,
  }) {
    if (preferredValues.isEmpty) return totalWeight;

    var matchedWeight = 0.0;
    var availableWeight = 0.0;
    for (final value in preferredValues) {
      final weight = weightLookup(value);
      availableWeight += weight;
      if (actualValues.contains(value)) {
        matchedWeight += weight;
      }
    }

    if (availableWeight <= 0) return totalWeight;
    return totalWeight * _concaveReward(matchedWeight / availableWeight);
  }

  double _moveInScore(
    RentalProperty property,
    SearchFilters filters,
    DateTime now,
  ) {
    final prioritizedOptions = filters.requiredMoveInFilters.isNotEmpty
        ? filters.requiredMoveInFilters
        : filters.preferredMoveInFilters;
    if (prioritizedOptions.isEmpty) return _timingWeight;

    final entryDate = property.entryDateValue;
    if (entryDate == null) return _timingWeight * 0.35;

    double bestScore = 0;
    for (final option in prioritizedOptions) {
      final deadline = _moveInDeadlineFor(option, now);
      if (deadline == null) {
        bestScore = math.max(bestScore, _timingWeight);
        continue;
      }
      if (!entryDate.isAfter(deadline)) {
        bestScore = math.max(bestScore, _timingWeight);
        continue;
      }

      final lateDays = math.max(entryDate.difference(deadline).inDays, 1);
      final graceDays = math.max(_moveInGraceDaysFor(option), 1);
      final candidate = _timingWeight * _expDecay(lateDays / graceDays, 1.25);
      bestScore = math.max(bestScore, candidate);
    }
    return bestScore;
  }

  ListingSourceFilter _listingSourceFor(RentalProperty property) {
    return property.agencyListing
        ? ListingSourceFilter.agencyOnly
        : ListingSourceFilter.privateOnly;
  }

  bool _matchesMoveInOption(
    RentalProperty property,
    MoveInFilter option,
    DateTime now,
  ) {
    final deadline = _moveInDeadlineFor(option, now);
    if (deadline == null) return true;
    final entryDate = property.entryDateValue;
    return entryDate != null && !entryDate.isAfter(deadline);
  }

  Set<ListingSourceFilter> _normalizedListingSourceRequired(
    SearchFilters filters,
  ) {
    final required = <ListingSourceFilter>{
      ...filters.requiredListingSources,
    };
    if (required.isEmpty && filters.listingSource != ListingSourceFilter.any) {
      required.add(filters.listingSource);
    }
    return required;
  }

  Set<ListingSourceFilter> _normalizedListingSourcePreferred(
    SearchFilters filters,
  ) {
    return filters.preferredListingSources.difference(
      _normalizedListingSourceRequired(filters),
    );
  }

  Set<MoveInFilter> _normalizedMoveInRequired(SearchFilters filters) {
    final required = <MoveInFilter>{
      ...filters.requiredMoveInFilters,
    };
    if (required.isEmpty && filters.moveInFilter != MoveInFilter.any) {
      required.add(filters.moveInFilter);
    }
    return required;
  }

  Set<MoveInFilter> _normalizedMoveInPreferred(SearchFilters filters) {
    return filters.preferredMoveInFilters.difference(
      _normalizedMoveInRequired(filters),
    );
  }

  double _listingConfidenceScore(RentalProperty property) {
    var score = 0.0;

    if (property.media.isNotEmpty) score += 2;
    if (property.media.length >= 2) score += 1;
    if (property.media.length >= 4) score += 0.5;
    if (property.videoUrls.isNotEmpty) score += 0.5;
    if (property.isVerifiedListing) score += 1.8;
    if (property.hasReadyVirtualTour) {
      score += 1.2;
    } else if (property.virtualTour?.isProcessing == true) {
      score += 0.3;
    }

    if (property.city.trim().isNotEmpty && property.street.trim().isNotEmpty) {
      score += 1.2;
    }
    if (property.streetNumber > 0) score += 0.6;
    if (property.neighborhood.trim().isNotEmpty) score += 0.5;
    if (property.condition.trim().isNotEmpty) score += 0.4;
    if (property.propertyType.trim().isNotEmpty) score += 0.3;

    if (property.ownerName.trim().isNotEmpty) score += 1;
    if (property.url.trim().isNotEmpty) score += 0.6;
    if (_hasUsableCoordinates(property)) score += 0.4;

    final reviews = propertyReviews(property.id);
    if (reviews.isEmpty) {
      score += 0.4;
    } else {
      final avg = reviewAverage(reviews);
      score += _clampDouble(avg / 5, 0, 1) * 1.5;
      score += _clampDouble(reviews.length / 3, 0, 1) * 0.5;
    }

    score += property.agencyListing ? 0.7 : 1;
    return _clampDouble(score, 0, _listingConfidenceWeight);
  }

  double _businessReadinessScore(
    RentalProperty property,
    _MatchContext context,
  ) {
    var score = 0.0;

    if (context.filters.transactionType == TransactionTypeFilter.any) {
      score += 0.7;
    } else {
      score += 1;
    }

    if (_hasKnownPrice(property) && property.sizeM2 > 0) score += 1;
    if (!property.agencyListing) score += 0.8;

    final entryDate = property.entryDateValue;
    if (entryDate == null) {
      if (property.entryDate.trim().isNotEmpty) score += 0.4;
    } else {
      final daysUntilEntry = entryDate.difference(context.now).inDays;
      if (daysUntilEntry <= 90) {
        score += 1;
      } else if (daysUntilEntry <= 180) {
        score += 0.6;
      } else {
        score += 0.3;
      }
    }

    if (property.media.length >= 2 &&
        property.ownerName.trim().isNotEmpty &&
        property.street.trim().isNotEmpty) {
      score += 0.2;
    }

    return _clampDouble(score, 0, _businessReadinessWeight);
  }

  bool _hasUsableCoordinates(RentalProperty property) {
    return property.lat.abs() > 0.01 && property.lon.abs() > 0.01;
  }

  double _expDecay(double value, double exponent) {
    final normalized = math.max(value, 0.0);
    return math.exp(-math.pow(normalized, exponent).toDouble());
  }

  bool _hasKnownPrice(RentalProperty property) =>
      property.price >= _missingPriceThreshold;

  PriceContext priceContext(RentalProperty property) {
    if (!_hasKnownPrice(property)) return PriceContext.average;
    final pricePerM2 = property.pricePerSquareMeter;
    final stats = _marketIndex.resolve(property);
    if (pricePerM2 == null || stats == null) return PriceContext.average;

    final median = stats.medianPricePerM2;
    if (pricePerM2 < median * 0.92) return PriceContext.belowAverage;
    if (pricePerM2 > median * 1.08) return PriceContext.aboveAverage;
    return PriceContext.average;
  }

  void _seedInitialState() {
    _tenantProfile = _rentalDataService.createDefaultTenantProfile();
    _tenantReviews = _rentalDataService.createTenantReviews();
    _propertyReviews = {
      for (final property in _baseProperties.take(12))
        property.id: _rentalDataService.createPropertyReviews(property),
    };
    _filters = _normalizeFilters(_defaultFilters);
    _likedPropertyIds = <String>{};
    _passedPropertyIds = <String>{};
    _ownerAcceptedPropertyIds = <String>{};
    _ownerRejectedPropertyIds = <String>{};
    _matches = const [];
    _pendingMatchPropertyId = null;
    _savedPropertyIds = <String>{};
    _lastSeenMatchCount = 0;
    _invalidateFilterCache();
  }

  void _seedGuestDemoState(String role) {
    // For owner demo: profile = landlord; for tenant demo: profile = tenant
    final isOwner = role == 'owner' || role == 'landlord';
    final tenant = _rentalDataService.createDefaultTenantProfile().copyWith(
          name: isOwner ? 'יואב כהן' : 'נועה לוי',
          photoUrls: isOwner
              ? const [] // landlord has no photo → show initials
              : const [
                  'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=900&q=80',
                  'https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=900&q=80',
                ],
          bio: isOwner
              ? 'בעל נכסים בתל אביב והסביבה. מחפש שוכרים אמינים לטווח ארוך. מגיב תוך 24 שעות ומאמין בתקשורת פתוחה.'
              : 'מחפשת דירת 2-3 חדרים בצפון תל אביב או רמת גן. כבר כמה שבועות פעילה באפליקציה, עם תגובות מהירות, מסמכים מוכנים והעדפה לבניין מטופח.',
          budgetMax: 11200,
          desiredRooms: 2.5,
          moveInWindow: 'כניסה תוך 30 יום',
          importantDetails: isOwner
              ? const ['ניסיון בניהול נכסים', 'חוזה מסודר', 'תגובה מהירה']
              : const [
                  'אישור הכנסה מוכן',
                  'שוכרת כבר 5 שנים רצוף',
                  'זמינה לסיור גם בערב',
                  'מחפשת חוזה לשנה לפחות',
                ],
        );
    final propertyPool = _baseProperties.take(6).toList();
    if (propertyPool.length < 4) {
      _seedInitialState();
      _isGuestMode = true;
      _userRole = role;
      _invalidateFilterCache();
      return;
    }

    final pendingLead = propertyPool[2];
    final savedProperty = propertyPool[3];

    _tenantProfile = tenant;
    _tenantReviews = [
      ..._rentalDataService.createTenantReviews(),
      const AppReview(
        id: 'tenant-review-3',
        authorName: 'דנה, בעלת דירה ברמת גן',
        rating: 5,
        text: 'סגרה מהר, שלחה כל מסמך בזמן ושמרה על קשר רציף לאורך כל התהליך.',
      ),
    ];
    _propertyReviews = {
      for (final property in propertyPool)
        property.id: _rentalDataService.createPropertyReviews(property),
    };
    _filters = _normalizeFilters(_defaultFilters);
    _customProperties = [
      RentalProperty(
        id: 'demo-prop-1',
        url: '',
        price: 8500,
        rooms: 3,
        sizeM2: 82,
        floor: '4',
        totalFloors: '9',
        city: 'תל אביב',
        neighborhood: 'לב תל אביב',
        street: 'דיזנגוף',
        streetNumber: 142,
        lat: 32.0809,
        lon: 34.7742,
        propertyType: 'דירה',
        entryDate: '01/08',
        condition: 'משופץ',
        ownerName: 'יואב כהן',
        agencyListing: false,
        features: ['מעלית', 'מרפסת', 'מזגן', 'חניה', 'אינטרנט כלול'],
        media: const [
          PropertyMedia(
            url:
                'https://images.unsplash.com/photo-1502672260266-1c1ef2d93688?w=900&q=80',
            type: PropertyMediaType.image,
          ),
          PropertyMedia(
            url:
                'https://images.unsplash.com/photo-1554995207-c18203ef2d6f?w=900&q=80',
            type: PropertyMediaType.image,
          ),
          PropertyMedia(
            url:
                'https://images.unsplash.com/photo-1600047509807-ba8f99d2cdde?w=900&q=80',
            type: PropertyMediaType.image,
          ),
        ],
      ),
      RentalProperty(
        id: 'demo-prop-2',
        url: '',
        price: 6900,
        rooms: 4,
        sizeM2: 108,
        floor: '7',
        totalFloors: '12',
        city: 'רמת גן',
        neighborhood: 'בורוכוב',
        street: 'ביאליק',
        streetNumber: 38,
        lat: 32.0748,
        lon: 34.8107,
        propertyType: 'דירה',
        entryDate: '15/09',
        condition: 'תקין',
        ownerName: 'יואב כהן',
        agencyListing: false,
        features: ['חניה', 'מחסן', 'מעלית', 'מזגן', 'חיות מחמד מותר'],
        media: const [
          PropertyMedia(
            url:
                'https://images.unsplash.com/photo-1560448204-e02f11c3d0e2?w=900&q=80',
            type: PropertyMediaType.image,
          ),
          PropertyMedia(
            url:
                'https://images.unsplash.com/photo-1522771739844-6a9f6d5f14af?w=900&q=80',
            type: PropertyMediaType.image,
          ),
          PropertyMedia(
            url:
                'https://images.unsplash.com/photo-1615873968403-89e068629265?w=900&q=80',
            type: PropertyMediaType.image,
          ),
        ],
      ),
      RentalProperty(
        id: 'demo-prop-3',
        url: '',
        price: 7200,
        rooms: 2.5,
        sizeM2: 68,
        floor: '5',
        totalFloors: '5',
        city: 'גבעתיים',
        neighborhood: 'גבעת רמב"ם',
        street: 'כצנלסון',
        streetNumber: 22,
        lat: 32.0693,
        lon: 34.8096,
        propertyType: 'דירת גג',
        entryDate: '01/10',
        condition: 'משופץ',
        ownerName: 'יואב כהן',
        agencyListing: false,
        features: ['מרפסת שמש', 'מזגן', 'אינטרנט כלול', 'ריהוט', 'גינה'],
        media: const [
          PropertyMedia(
            url:
                'https://images.unsplash.com/photo-1600596542815-ffad4c1539a9?w=900&q=80',
            type: PropertyMediaType.image,
          ),
          PropertyMedia(
            url:
                'https://images.unsplash.com/photo-1580587771525-78b9dba3b914?w=900&q=80',
            type: PropertyMediaType.image,
          ),
        ],
      ),
      RentalProperty(
        id: 'demo-prop-4',
        url: '',
        price: 5400,
        rooms: 1.5,
        sizeM2: 44,
        floor: '2',
        totalFloors: '8',
        city: 'הרצליה',
        neighborhood: 'הרצליה פיתוח',
        street: 'מסגר',
        streetNumber: 5,
        lat: 32.1656,
        lon: 34.8451,
        propertyType: 'סטודיו',
        entryDate: 'גמיש',
        condition: 'חדש מקבלן',
        ownerName: 'יואב כהן',
        agencyListing: false,
        features: ['מעלית', 'מזגן', 'חניה', 'ממ"ד', 'בריכה', 'חדר כושר'],
        media: const [
          PropertyMedia(
            url:
                'https://images.unsplash.com/photo-1556020685-ae41abfc9365?w=900&q=80',
            type: PropertyMediaType.image,
          ),
          PropertyMedia(
            url:
                'https://images.unsplash.com/photo-1564013799919-ab600027ffc6?w=900&q=80',
            type: PropertyMediaType.image,
          ),
        ],
      ),
    ];
    _likedPropertyIds = <String>{
      'demo-prop-1',
      'demo-prop-2',
      'demo-prop-3',
      pendingLead.id,
    };
    _passedPropertyIds = <String>{savedProperty.id};
    _ownerAcceptedPropertyIds = <String>{
      'demo-prop-1',
      'demo-prop-2',
      'demo-prop-3',
    };
    _ownerRejectedPropertyIds = <String>{};
    _matches = [
      RentalMatch(
        id: 'guest-match-demo-1',
        propertyId: 'demo-prop-1',
        createdAt: DateTime.now().subtract(const Duration(days: 18)),
        contractSent: true,
        ownerSigned: true,
        tenantSigned: false,
        messages: [
          ChatMessage(
            id: 'd1-1',
            sender: 'מערכת',
            text: 'נוצר מאצ׳ — שני הצדדים הסכימו להתקדם.',
            createdAt: DateTime.now().subtract(const Duration(days: 18)),
          ),
          ChatMessage(
            id: 'd1-2',
            sender: 'יואב כהן',
            text:
                'היי נועה, הדירה עדיין פנויה. נשמח לתאם סיור השבוע — איזה ימים מתאים לך?',
            createdAt: DateTime.now().subtract(const Duration(days: 17)),
          ),
          ChatMessage(
            id: 'd1-3',
            sender: tenant.name,
            text:
                'יום שלישי או רביעי ב-18:30 מצוין. שלחתי גם תלוש שכר ואישור הכנסה.',
            createdAt: DateTime.now().subtract(const Duration(days: 16)),
          ),
          ChatMessage(
            id: 'd1-4',
            sender: 'יואב כהן',
            text:
                'קיבלתי, נראה מסודר מאוד. שלחתי חוזה לעיון — אפשר לחתום דיגיטלית דרך האפליקציה.',
            createdAt: DateTime.now().subtract(const Duration(days: 14)),
          ),
          ChatMessage(
            id: 'd1-5',
            sender: tenant.name,
            text:
                'קראתי את החוזה, הכל נראה טוב. שאלה אחת — מה הסיפור עם ועד הבית, האם זה כלול בשכירות?',
            createdAt: DateTime.now().subtract(const Duration(hours: 5)),
          ),
        ],
      ),
      RentalMatch(
        id: 'guest-match-demo-2',
        propertyId: 'demo-prop-2',
        createdAt: DateTime.now().subtract(const Duration(days: 9)),
        contractSent: false,
        ownerSigned: false,
        tenantSigned: false,
        messages: [
          ChatMessage(
            id: 'd2-1',
            sender: 'מערכת',
            text: 'נוצר מאצ׳ — שני הצדדים מעוניינים.',
            createdAt: DateTime.now().subtract(const Duration(days: 9)),
          ),
          ChatMessage(
            id: 'd2-2',
            sender: tenant.name,
            text:
                'שלום! ראיתי את הדירה ברמת גן — ממש מוצאת חן בעיניי. מה הסיפור עם החניה, מוצמדת לדירה?',
            createdAt: DateTime.now().subtract(const Duration(days: 8)),
          ),
          ChatMessage(
            id: 'd2-3',
            sender: 'יואב כהן',
            text:
                'כן, חניה מוצמדת לדירה כלולה בשכירות. יש גם מחסן בקומת המרתף.',
            createdAt: DateTime.now().subtract(const Duration(days: 7)),
          ),
          ChatMessage(
            id: 'd2-4',
            sender: tenant.name,
            text:
                'מעולה! אפשר לקבוע סיור לשבוע הבא? אנחנו שניים — אני ועוד שותפה.',
            createdAt: DateTime.now().subtract(const Duration(hours: 14)),
          ),
        ],
      ),
      RentalMatch(
        id: 'guest-match-demo-3',
        propertyId: 'demo-prop-3',
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
        contractSent: false,
        ownerSigned: false,
        tenantSigned: false,
        messages: [
          ChatMessage(
            id: 'd3-1',
            sender: 'מערכת',
            text: 'התאמה חדשה! שני הצדדים הראו עניין.',
            createdAt: DateTime.now().subtract(const Duration(days: 3)),
          ),
          ChatMessage(
            id: 'd3-2',
            sender: tenant.name,
            text:
                'היי! האם המרפסת שבתמונה פרטית לגמרי לדירה, או שהיא משותפת עם הקומה?',
            createdAt: DateTime.now().subtract(const Duration(days: 2)),
          ),
        ],
      ),
    ];
    _pendingMatchPropertyId = null;
    _swipeHistory.clear();
    _savedPropertyIds = <String>{'demo-prop-4', savedProperty.id};
    _lastSeenMatchCount = 2;
    _isGuestMode = true;
    _userRole = role;
    _invalidateCatalogCache();
  }

  void _hydrateFromState(Map<String, dynamic> storedState) {
    final tenantJson = storedState['tenantProfile'] as Map<dynamic, dynamic>?;
    _tenantProfile = tenantJson == null
        ? _rentalDataService.createDefaultTenantProfile()
        : TenantProfile.fromJson(Map<String, dynamic>.from(tenantJson));

    _filters = SearchFilters.fromJson(
      Map<String, dynamic>.from(storedState['filters'] as Map? ?? const {}),
    );
    _likedPropertyIds = Set<String>.from(
      storedState['likedPropertyIds'] as List<dynamic>? ?? const [],
    );
    _passedPropertyIds = Set<String>.from(
      storedState['passedPropertyIds'] as List<dynamic>? ?? const [],
    );
    _ownerAcceptedPropertyIds = Set<String>.from(
      storedState['ownerAcceptedPropertyIds'] as List<dynamic>? ?? const [],
    );
    _ownerRejectedPropertyIds = Set<String>.from(
      storedState['ownerRejectedPropertyIds'] as List<dynamic>? ?? const [],
    );
    _matches = (storedState['matches'] as List<dynamic>? ?? const [])
        .map((item) =>
            RentalMatch.fromJson(Map<String, dynamic>.from(item as Map)))
        .toList();
    _tenantReviews =
        (storedState['tenantReviews'] as List<dynamic>? ?? const [])
            .map((item) =>
                AppReview.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();

    final reviewsJson =
        storedState['propertyReviews'] as Map<dynamic, dynamic>? ?? const {};
    _propertyReviews = reviewsJson.map((key, value) {
      return MapEntry(
        key.toString(),
        (value as List<dynamic>)
            .map((item) =>
                AppReview.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList(),
      );
    });

    _customProperties =
        (storedState['customProperties'] as List<dynamic>? ?? const [])
            .map((item) =>
                RentalProperty.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();

    _userRole = storedState['userRole'] as String? ?? 'tenant';
    _isGuestMode = storedState['isGuestMode'] as bool? ?? false;
    _hasActiveSession =
        storedState['hasActiveSession'] as bool? ?? _isGuestMode;

    if (_tenantReviews.isEmpty) {
      _tenantReviews = _rentalDataService.createTenantReviews();
    }
    _savedPropertyIds = Set<String>.from(
      storedState['savedPropertyIds'] as List<dynamic>? ?? const [],
    );
    _blockedOwnerNames = Set<String>.from(
      storedState['blockedOwnerNames'] as List<dynamic>? ?? const [],
    );
    _reportedPropertyIds = Set<String>.from(
      storedState['reportedPropertyIds'] as List<dynamic>? ?? const [],
    );
    final signalsJson =
        storedState['propertySignalOverrides'] as Map<dynamic, dynamic>? ??
            const {};
    _propertySignalOverrides = signalsJson.map((key, value) {
      if (value is! Map) {
        return MapEntry(key.toString(), const PropertyMarketSignals());
      }
      return MapEntry(
        key.toString(),
        PropertyMarketSignals.fromJson(
          Map<String, dynamic>.from(value),
        ),
      );
    });
    _lastSeenMatchCount = storedState['lastSeenMatchCount'] as int? ?? 0;
    _pendingMatchPropertyId = null;
    _invalidateCatalogCache();
  }

  void _createMatch(RentalProperty property) {
    if (_matches.any((m) => m.propertyId == property.id)) return;

    _matches = [
      ..._matches,
      RentalMatch(
        id: 'match-${property.id}',
        propertyId: property.id,
        createdAt: DateTime.now(),
        contractSent: false,
        ownerSigned: false,
        tenantSigned: false,
        messages: [
          ChatMessage(
            id: 'intro-${property.id}',
            sender: 'מערכת',
            text: 'נוצר מאצ׳. אפשר לפתוח צ׳אט, לשלוח חוזה ולנהל חתימות.',
            createdAt: DateTime.now(),
          ),
        ],
      ),
    ];
    _pendingMatchPropertyId = property.id;
  }

  void _replaceMatch(int index, RentalMatch updatedMatch) {
    final updatedMatches = [..._matches];
    updatedMatches[index] = updatedMatch;
    _matches = updatedMatches;
  }

  Future<void> _persist() async {
    // Snapshot all current state
    final snapshot = {
      'schema': 'rental_match_v2',
      'tenantProfile': _tenantProfile?.toJson(),
      'filters': _filters.toJson(),
      'likedPropertyIds': _likedPropertyIds.toList(),
      'passedPropertyIds': _passedPropertyIds.toList(),
      'ownerAcceptedPropertyIds': _ownerAcceptedPropertyIds.toList(),
      'ownerRejectedPropertyIds': _ownerRejectedPropertyIds.toList(),
      'matches': _matches.map((m) => m.toJson()).toList(),
      'tenantReviews': _tenantReviews.map((r) => r.toJson()).toList(),
      'propertyReviews': _propertyReviews.map(
        (key, value) => MapEntry(key, value.map((r) => r.toJson()).toList()),
      ),
      'customProperties': _customProperties.map((p) => p.toJson()).toList(),
      'userRole': InputSanitizer.sanitizeRole(_userRole),
      'isGuestMode': _isGuestMode,
      'hasActiveSession': _hasActiveSession,
      'savedPropertyIds': _savedPropertyIds.toList(),
      'blockedOwnerNames': _blockedOwnerNames.toList(),
      'reportedPropertyIds': _reportedPropertyIds.toList(),
      'propertySignalOverrides': _propertySignalOverrides.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
      'lastSeenMatchCount': _lastSeenMatchCount,
    };

    await _localStorageService.saveAppState(snapshot, syncRemote: false);

    // Debounce only the remote write. Local SharedPreferences must update
    // immediately so state is not lost if Appwrite is slow or rate-limited.
    unawaited(_writeDebouncer.schedule(() async {
      if (RateLimiter.instance.allowStateWrite()) {
        await _localStorageService.syncRemoteAppState(snapshot);
      } else {
        if (kDebugMode) {
          debugPrint('DatingProvider: remote write skipped (rate limit)');
        }
      }
    }));
  }
}

class _MatchContext {
  const _MatchContext({
    required this.filters,
    required this.now,
    required this.area,
    required this.featureWeights,
    required this.marketIndex,
  });

  final SearchFilters filters;
  final DateTime now;
  final SearchArea area;
  final Map<String, double> featureWeights;
  final _MarketIndex marketIndex;
}

class _MarketIndex {
  const _MarketIndex(this._statsByKey);

  final Map<String, _MarketStats> _statsByKey;

  static _MarketIndex fromProperties(List<RentalProperty> properties) {
    final buckets = <String, List<double>>{};

    for (final property in properties) {
      final pricePerM2 = property.pricePerSquareMeter;
      if (pricePerM2 == null || pricePerM2 <= 0) continue;

      final city = _marketToken(property.city);
      final type = _marketToken(property.propertyType);
      final transaction = property.transactionType.name;
      final sample = pricePerM2.toDouble();

      _addSample(buckets, _key(city, transaction, type), sample);
      _addSample(buckets, _key(city, transaction, '*'), sample);
      _addSample(buckets, _key('*', transaction, type), sample);
      _addSample(buckets, _key('*', transaction, '*'), sample);
      _addSample(buckets, _key('*', '*', '*'), sample);
    }

    return _MarketIndex({
      for (final entry in buckets.entries)
        entry.key: _MarketStats.fromSamples(entry.value),
    });
  }

  _MarketStats? resolve(RentalProperty property) {
    final city = _marketToken(property.city);
    final type = _marketToken(property.propertyType);
    final transaction = property.transactionType.name;
    final keys = [
      _key(city, transaction, type),
      _key(city, transaction, '*'),
      _key('*', transaction, type),
      _key('*', transaction, '*'),
      _key('*', '*', '*'),
    ];

    _MarketStats? fallback;
    for (final key in keys) {
      final stats = _statsByKey[key];
      if (stats == null) continue;
      fallback ??= stats;
      if (stats.sampleCount >= 4) return stats;
    }
    return fallback;
  }

  static void _addSample(
    Map<String, List<double>> buckets,
    String key,
    double value,
  ) {
    buckets.putIfAbsent(key, () => <double>[]).add(value);
  }

  static String _key(String city, String transaction, String type) {
    return '$city|$transaction|$type';
  }

  static String _marketToken(String value) {
    final normalized = value.trim().toLowerCase();
    return normalized.isEmpty ? '*' : normalized;
  }
}

class _MarketStats {
  const _MarketStats({
    required this.sampleCount,
    required this.medianPricePerM2,
    required this.relativeMad,
  });

  final int sampleCount;
  final double medianPricePerM2;
  final double relativeMad;

  static _MarketStats fromSamples(List<double> samples) {
    final sorted = [...samples]..sort();
    final median = _median(sorted);
    final deviations = sorted.map((value) => (value - median).abs()).toList()
      ..sort();
    final mad = _median(deviations);
    final relativeMad = median <= 0 ? 0.18 : math.max(mad / median, 0.08);

    return _MarketStats(
      sampleCount: sorted.length,
      medianPricePerM2: median,
      relativeMad: relativeMad,
    );
  }
}

class _SwipeRecord {
  const _SwipeRecord({required this.propertyId, required this.liked});
  final String propertyId;
  final bool liked;
}

class _PropertyDetailSession {
  _PropertyDetailSession({
    required this.propertyId,
    required this.sessionId,
    required this.startedAt,
  });

  final String propertyId;
  final String sessionId;
  final DateTime startedAt;
  int photoSwipeCount = 0;
  int currentPhotoIndex = 0;
  Timer? heartbeatTimer;
}

enum PriceContext { belowAverage, average, aboveAverage }

class LandlordStats {
  const LandlordStats({
    required this.propertiesCount,
    required this.totalCandidatesSeen,
    required this.matchesCount,
    required this.pendingCount,
  });

  final int propertiesCount;
  final int totalCandidatesSeen;
  final int matchesCount;
  final int pendingCount;

  double get conversionRate =>
      totalCandidatesSeen == 0 ? 0 : matchesCount / totalCandidatesSeen * 100;
}

double _median(List<double> sortedValues) {
  if (sortedValues.isEmpty) return 0;
  final middle = sortedValues.length ~/ 2;
  if (sortedValues.length.isOdd) return sortedValues[middle];
  return (sortedValues[middle - 1] + sortedValues[middle]) / 2;
}

double _clampDouble(num value, num min, num max) {
  return value.clamp(min, max).toDouble();
}
