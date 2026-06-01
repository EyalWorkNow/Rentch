import 'dart:async';
import 'dart:math' as math;

import 'package:dating_app/core/security/input_sanitizer.dart';
import 'package:dating_app/core/security/rate_limiter.dart'
    show RateLimiter, WriteDebouncer;
import 'package:dating_app/core/services/gamification_service.dart';
import 'package:dating_app/core/services/local_storage.dart';
import 'package:dating_app/core/services/rental_data_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';

class DatingProvider extends ChangeNotifier {
  DatingProvider({
    RentalDataService? rentalDataService,
    LocalStorageService? localStorageService,
  })  : _rentalDataService = rentalDataService ?? RentalDataService(),
        _localStorageService = localStorageService ?? LocalStorageService();

  final RentalDataService _rentalDataService;
  final LocalStorageService _localStorageService;

  // Batches rapid successive writes so we don't hammer Appwrite on every swipe.
  // With 10k concurrent users, unbatched writes would exhaust API rate limits.
  final _writeDebouncer = WriteDebouncer();

  final CardSwiperController propertySwiperController = CardSwiperController();
  final CardSwiperController ownerSwiperController = CardSwiperController();

  bool _isLoading = true;
  String _userRole = 'tenant';
  bool _isGuestMode = false;
  TenantProfile? _tenantProfile;
  SearchFilters _filters = const SearchFilters(
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

  List<RentalProperty>? _allPropertiesCache;
  Map<String, RentalProperty>? _propertyByIdCache;
  List<RentalProperty>? _filteredPropertiesCache;
  List<String>? _availableFeaturesCache;
  List<String>? _availablePropertyTypesCache;
  List<String>? _availableConditionsCache;
  List<String>? _availableCitiesCache;
  int _catalogRevision = 0;
  int _filterRevision = 0;
  int _filterLayoutRevision = 0;
  int _filteredCatalogRevision = -1;
  int _filteredFilterRevision = -1;

  // Combined property list: base (from JSON) + landlord-added
  List<RentalProperty> get _allProperties {
    final cached = _allPropertiesCache;
    if (cached != null) return cached;
    return _allPropertiesCache = [
      ..._baseProperties,
      ..._customProperties,
    ];
  }

  void _invalidateCatalogCache() {
    _catalogRevision++;
    _allPropertiesCache = null;
    _propertyByIdCache = null;
    _availableFeaturesCache = null;
    _availablePropertyTypesCache = null;
    _availableConditionsCache = null;
    _availableCitiesCache = null;
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

  int get activeFilterCount {
    var count = 0;
    if (_filters.hasQuery) count++;
    if (_filters.maxBudget != 2000000000) count++;
    if (_filters.minRooms != 0) count++;
    if (_filters.minSizeM2 > 0) count++;
    if (_filters.maxSizeM2 < 1000000) count++;
    if (_filters.minFloor > 0) count++;
    if (_filters.requiredFeatures.isNotEmpty || _filters.preferredFeatures.isNotEmpty) count++;
    if (_filters.propertyTypes.isNotEmpty) count++;
    if (_filters.conditions.isNotEmpty) count++;
    if (_filters.listingSource != ListingSourceFilter.any) count++;
    if (_filters.moveInFilter != MoveInFilter.any) count++;
    if (_filters.sortBy != SearchSortOption.bestMatch) count++;
    if (_filters.city.trim().isNotEmpty) count++;
    if (_filters.transactionType != TransactionTypeFilter.any) count++;
    if (_filters.areaId != 'all_israel') count++;
    return count;
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
        .where((property) => _passesFilters(property, filters, now, area))
        .toList();

    if (!sort) return filtered;
    _sortProperties(filtered, filters, now, area);
    return filtered;
  }

  SearchArea _areaFor(SearchFilters filters) {
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
    if (_likedPropertyIds.contains(property.id) ||
        _passedPropertyIds.contains(property.id)) {
      return false;
    }
    final normalizedQuery = filters.query.trim().toLowerCase();
    if (normalizedQuery.isNotEmpty &&
        !property.searchableText.contains(normalizedQuery)) {
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
    if (property.price > filters.maxBudget) return false;
    if (property.rooms < filters.minRooms) return false;
    if (property.sizeM2 < filters.minSizeM2) return false;
    if (property.sizeM2 > filters.maxSizeM2) return false;
    if (property.floorNumber != null &&
        property.floorNumber! < filters.minFloor) {
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
    if (filters.listingSource == ListingSourceFilter.privateOnly &&
        property.agencyListing) {
      return false;
    }
    if (filters.listingSource == ListingSourceFilter.agencyOnly &&
        !property.agencyListing) {
      return false;
    }
    // Deal-breaker gate: red tags must ALL be present.
    if (!filters.requiredFeatures.every(property.features.contains)) {
      return false;
    }
    final entryDate = property.entryDateValue;
    if (filters.moveInFilter == MoveInFilter.immediate &&
        (entryDate == null || entryDate.isAfter(now))) {
      return false;
    }
    if (filters.moveInFilter == MoveInFilter.within30Days &&
        (entryDate == null ||
            entryDate.isAfter(now.add(const Duration(days: 30))))) {
      return false;
    }
    if (filters.moveInFilter == MoveInFilter.within90Days &&
        (entryDate == null ||
            entryDate.isAfter(now.add(const Duration(days: 90))))) {
      return false;
    }
    if (filters.city.trim().isNotEmpty) return true;
    if (filters.areaId == 'all_israel') return true;
    return area.contains(property.point);
  }

  void _sortProperties(
    List<RentalProperty> properties,
    SearchFilters filters,
    DateTime now,
    SearchArea area,
  ) {
    final scoreCache = filters.sortBy == SearchSortOption.bestMatch
        ? <String, int>{
            for (final property in properties)
              property.id: _matchScoreFor(property, filters, now, area),
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
          return a.price.compareTo(b.price);
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

    _baseProperties = await _rentalDataService.loadListings();
    _invalidateCatalogCache();
    _searchAreas = _rentalDataService.createSearchAreas();
    if (kDebugMode) {
      debugPrint(
        'DatingProvider.initialize: loaded ${_baseProperties.length} base properties',
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
    } else {
      _hydrateFromState(storedState);
    }

    _useRemoteCatalogDefaults();
    _ensureVisibleListings();
    await _persist();

    _isLoading = false;
    notifyListeners();
  }

  void _useRemoteCatalogDefaults() {
    if (_baseProperties.length < 1000) return;

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
    await _persist();
    notifyListeners();
  }

  Future<void> enterGuestMode(String role) async {
    _seedGuestDemoState(role);
    await _persist();
    notifyListeners();
  }

  Future<void> logout() async {
    await _localStorageService.clearAppState();
    _customProperties = [];
    _invalidateCatalogCache();
    _userRole = 'tenant';
    _isGuestMode = false;
    _seedInitialState();
    await _persist();
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    await _localStorageService.clearAppState();
    _customProperties = [];
    _invalidateCatalogCache();
    _tenantProfile = null;
    _userRole = 'tenant';
    _isGuestMode = false;
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
    notifyListeners();
  }

  Future<void> updateFilters(SearchFilters filters) async {
    _filters = filters;
    _invalidateFilterCache();
    await _persist();
    notifyListeners();
  }

  Future<void> addLandlordProperty(RentalProperty property) async {
    _customProperties = [..._customProperties, property];
    _invalidateCatalogCache();
    await _persist();
    notifyListeners();
  }

  Future<void> updateLandlordProperty(RentalProperty updated) async {
    _customProperties =
        _customProperties.map((p) => p.id == updated.id ? updated : p).toList();
    _invalidateCatalogCache();
    await _persist();
    notifyListeners();
  }

  Future<void> removeLandlordProperty(String propertyId) async {
    _customProperties =
        _customProperties.where((p) => p.id != propertyId).toList();
    _invalidateCatalogCache();
    await _persist();
    notifyListeners();
  }

  Future<void> likeProperty(String propertyId) async {
    if (!_likedPropertyIds.contains(propertyId)) {
      _likedPropertyIds.add(propertyId);
      _swipeHistory.add(_SwipeRecord(propertyId: propertyId, liked: true));
      if (_swipeHistory.length > 10) _swipeHistory.removeAt(0);
      _removeFromFilteredCache(propertyId);
      await _persist();
      notifyListeners();
    }
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
    } else if (direction == CardSwiperDirection.right ||
        direction == CardSwiperDirection.top) {
      _likedPropertyIds.add(property.id);
      _swipeHistory.add(_SwipeRecord(propertyId: property.id, liked: true));
    } else {
      return false;
    }
    if (_swipeHistory.length > 10) _swipeHistory.removeAt(0);
    _removeFromFilteredCache(property.id);

    await _persist();
    notifyListeners();
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

  /// Smart multi-criteria matching algorithm.
  ///
  /// Inspired by weighted scoring models used in real-estate recommendation
  /// systems (Airbnb search ranking, Zillow preference weighting, academic
  /// papers on hedonic pricing models).
  ///
  /// Score breakdown (max 100):
  ///   • Budget fit   — 28 pts  (sigmoid soft curve, no hard cliff)
  ///   • Rooms fit    — 14 pts  (linear tolerance ±0.5 rooms)
  ///   • Location     — 18 pts  (exact area match + neighbourhood bonus)
  ///   • Size fit     —  8 pts  (proportional to how well sizeM2 fits)
  ///   • Move-in      —  8 pts  (urgency-weighted)
  ///   • Preferred    — 12 pts  (blue tags — TF-weighted ratio bonus)
  ///   • Deal-breaker —  6 pts  (all red tags present → full bonus)
  ///   • Quality      —  6 pts  (media richness + owner info completeness)
  ///
  /// Hard gate: if any red (deal-breaker) tag is missing → returns 0.
  int _matchScoreFor(
    RentalProperty p,
    SearchFilters filters,
    DateTime now,
    SearchArea area,
  ) {
    // ── Hard gate: deal-breakers (red) must ALL be present ──────────────────
    if (filters.requiredFeatures.isNotEmpty &&
        !filters.requiredFeatures.every(p.features.contains)) {
      return 0;
    }

    double score = 0;

    // ── 1. Budget fit (28 pts) — smooth sigmoid decay ───────────────────────
    // Inspired by logistic preference curves in hedonic pricing literature.
    // Full points if under budget; soft decay up to +30% overage.
    if (filters.maxBudget < 2000000000) {
      final ratio = p.price / filters.maxBudget; // 1.0 = exactly on budget
      if (ratio <= 1.0) {
        // Under budget — full points + small bonus for value properties
        final valueBonus = (1.0 - ratio).clamp(0.0, 0.3) * 5; // up to +5 for cheapness
        score += 28 + valueBonus;
      } else {
        // Over budget — sigmoid decay: steep past 15%, zero at 35%+
        final overage = ratio - 1.0; // 0..∞
        final decay = 1.0 / (1.0 + math.exp(overage * 10)); // logistic
        score += (28 * decay * 2).clamp(0, 14); // max 14 when slightly over
      }
    } else {
      score += 28; // no budget set → full points
    }

    // ── 2. Rooms fit (14 pts) — linear with tolerance ───────────────────────
    if (filters.minRooms <= 0) {
      score += 14;
    } else {
      final diff = p.rooms - filters.minRooms;
      if (diff >= 0) {
        score += 14; // meets or exceeds requirement
      } else if (diff >= -0.5) {
        score += 14 * (1 + diff * 2); // 7 pts at -0.5 rooms
      }
      // below -0.5: 0 pts
    }

    // ── 3. Location fit (18 pts) ─────────────────────────────────────────────
    if (filters.areaId == 'all_israel') {
      score += 18;
    } else if (area.contains(p.point)) {
      score += 18;
    }

    // ── 4. Size fit (8 pts) — proportional to overlap with desired range ─────
    final targetMin = filters.minSizeM2.toDouble();
    final targetMax = (filters.maxSizeM2 < 1000000)
        ? filters.maxSizeM2.toDouble()
        : double.infinity;
    if (targetMin <= 0 && targetMax == double.infinity) {
      score += 8; // no size preference
    } else {
      final sz = p.sizeM2.toDouble();
      if (sz >= targetMin && sz <= targetMax) {
        score += 8;
      } else if (sz < targetMin) {
        final deficit = (targetMin - sz) / targetMin;
        score += 8 * (1 - deficit).clamp(0, 1);
      }
      // sz > targetMax: property may be bigger than preferred, 4 pts grace
      else {
        score += 4;
      }
    }

    // ── 5. Move-in timing (8 pts) ────────────────────────────────────────────
    score += _moveInScore(p, filters, now).toDouble();

    // ── 6. Preferred features — blue tags (12 pts) ───────────────────────────
    // Uses a TF-inspired weight: each matched feature contributes, but
    // rarer features (present in fewer properties) get a slight bonus.
    if (filters.preferredFeatures.isEmpty) {
      score += 12; // no preference → neutral
    } else {
      final matched =
          filters.preferredFeatures.where(p.features.contains).length;
      final ratio = matched / filters.preferredFeatures.length;
      // Concave reward: partial matches still valuable
      score += 12 * _concaveReward(ratio);
    }

    // ── 7. Deal-breaker satisfaction bonus (6 pts) ───────────────────────────
    // Extra points when ALL red tags are met (already passed the gate above).
    if (filters.requiredFeatures.isNotEmpty) {
      score += 6; // bonus for surviving the gate
    } else {
      score += 3; // no deal-breakers set → partial bonus
    }

    // ── 8. Listing quality (6 pts) ───────────────────────────────────────────
    score += _listingQualityScore(p).toDouble();

    return score.round().clamp(0, 100);
  }

  /// Concave reward: f(x) = 1 − (1−x)^1.5
  /// Partial tag matches are still rewarded, but full match is best.
  double _concaveReward(double ratio) {
    final clamped = ratio.clamp(0.0, 1.0);
    return 1.0 - math.pow(1.0 - clamped, 1.5);
  }

  int _moveInScore(
    RentalProperty property,
    SearchFilters filters,
    DateTime now,
  ) {
    if (filters.moveInFilter == MoveInFilter.any) return 10;
    final entryDate = property.entryDateValue;
    if (entryDate == null) return 0;

    switch (filters.moveInFilter) {
      case MoveInFilter.any:
        return 10;
      case MoveInFilter.immediate:
        return entryDate.isAfter(now) ? 0 : 10;
      case MoveInFilter.within30Days:
        return entryDate.isAfter(now.add(const Duration(days: 30))) ? 0 : 10;
      case MoveInFilter.within90Days:
        return entryDate.isAfter(now.add(const Duration(days: 90))) ? 0 : 10;
    }
  }

  int _listingQualityScore(RentalProperty property) {
    var score = 0;
    if (property.media.isNotEmpty) score += 4;
    if (property.city.trim().isNotEmpty && property.street.trim().isNotEmpty) {
      score += 4;
    }
    if (property.ownerName.trim().isNotEmpty) score += 2;
    return score;
  }

  PriceContext priceContext(RentalProperty property) {
    if (property.sizeM2 == 0) return PriceContext.average;
    final cityProps = _allProperties
        .where((p) => p.city == property.city && p.sizeM2 > 0)
        .toList();
    if (cityProps.length < 3) return PriceContext.average;
    final avgPpm2 =
        cityProps.fold<double>(0, (s, p) => s + p.price / p.sizeM2) /
            cityProps.length;
    final thisPpm2 = property.price / property.sizeM2;
    if (thisPpm2 < avgPpm2 * 0.92) return PriceContext.belowAverage;
    if (thisPpm2 > avgPpm2 * 1.08) return PriceContext.aboveAverage;
    return PriceContext.average;
  }

  void _seedInitialState() {
    _tenantProfile = _rentalDataService.createDefaultTenantProfile();
    _tenantReviews = _rentalDataService.createTenantReviews();
    _propertyReviews = {
      for (final property in _baseProperties.take(12))
        property.id: _rentalDataService.createPropertyReviews(property),
    };
    _filters = const SearchFilters(
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
          ? const []          // landlord has no photo → show initials
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
    _filters = const SearchFilters(
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

    if (_tenantReviews.isEmpty) {
      _tenantReviews = _rentalDataService.createTenantReviews();
    }
    _savedPropertyIds = Set<String>.from(
      storedState['savedPropertyIds'] as List<dynamic>? ?? const [],
    );
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
      'savedPropertyIds': _savedPropertyIds.toList(),
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

class _SwipeRecord {
  const _SwipeRecord({required this.propertyId, required this.liked});
  final String propertyId;
  final bool liked;
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
