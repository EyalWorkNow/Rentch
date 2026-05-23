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

  final CardSwiperController propertySwiperController = CardSwiperController();
  final CardSwiperController ownerSwiperController = CardSwiperController();

  bool _isLoading = true;
  String _userRole = 'tenant';
  TenantProfile? _tenantProfile;
  SearchFilters _filters = const SearchFilters(
    maxBudget: 9000,
    minRooms: 2,
    areaId: 'gush_dan',
    requiredFeatures: <String>{},
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

  // Combined property list: base (from JSON) + landlord-added
  List<RentalProperty> get _allProperties =>
      [..._baseProperties, ..._customProperties];

  bool get isLoading => _isLoading;
  bool get isLandlord => _userRole == 'landlord';
  String get userRole => _userRole;
  TenantProfile? get tenantProfile => _tenantProfile;
  SearchFilters get filters => _filters;
  List<SearchArea> get searchAreas => _searchAreas;
  List<AppReview> get tenantReviews => _tenantReviews;
  List<RentalMatch> get matches => _matches;
  int get likesCount => _likedPropertyIds.length;
  int get passedCount => _passedPropertyIds.length;
  int get matchesCount => _matches.length;
  bool get canUndo => _swipeHistory.isNotEmpty;
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
    final features = <String>{};
    for (final property in _allProperties) {
      features.addAll(property.features);
    }
    final sorted = features.toList()..sort();
    return sorted;
  }

  List<RentalProperty> get filteredProperties {
    if (_searchAreas.isEmpty) return const [];

    return _allProperties.where((property) {
      if (_likedPropertyIds.contains(property.id) ||
          _passedPropertyIds.contains(property.id)) {
        return false;
      }
      if (property.price > _filters.maxBudget) return false;
      if (property.rooms < _filters.minRooms) return false;
      if (!_filters.requiredFeatures.every(property.features.contains)) {
        return false;
      }
      return selectedArea.contains(property.point);
    }).toList();
  }

  List<RentalProperty> get ownerLeads {
    return _allProperties.where((property) {
      return _likedPropertyIds.contains(property.id) &&
          !_ownerAcceptedPropertyIds.contains(property.id) &&
          !_ownerRejectedPropertyIds.contains(property.id) &&
          !_matches.any((match) => match.propertyId == property.id);
    }).toList();
  }

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    _baseProperties = await _rentalDataService.loadListings();
    _searchAreas = _rentalDataService.createSearchAreas();

    final storedState = await _localStorageService.loadAppState();
    if (storedState == null || storedState['schema'] != 'rental_match_v1') {
      _seedInitialState();
    } else {
      _hydrateFromState(storedState);
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> setUserRole(String role) async {
    _userRole = role;
    await _persist();
    notifyListeners();
  }

  Future<void> logout() async {
    await _localStorageService.clearAppState();
    _customProperties = [];
    _userRole = 'tenant';
    _seedInitialState();
    notifyListeners();
  }

  Future<void> updateTenantProfile(TenantProfile updatedProfile) async {
    _tenantProfile = updatedProfile;
    await _persist();
    notifyListeners();
  }

  Future<void> updateFilters(SearchFilters filters) async {
    _filters = filters;
    await _persist();
    notifyListeners();
  }

  Future<void> addLandlordProperty(RentalProperty property) async {
    _customProperties = [..._customProperties, property];
    await _persist();
    notifyListeners();
  }

  Future<void> removeLandlordProperty(String propertyId) async {
    _customProperties =
        _customProperties.where((p) => p.id != propertyId).toList();
    await _persist();
    notifyListeners();
  }

  Future<void> likeProperty(String propertyId) async {
    if (!_likedPropertyIds.contains(propertyId)) {
      _likedPropertyIds.add(propertyId);
      _swipeHistory
          .add(_SwipeRecord(propertyId: propertyId, liked: true));
      if (_swipeHistory.length > 10) _swipeHistory.removeAt(0);
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

  Future<void> superLikeProperty() async {
    propertySwiperController.swipe(CardSwiperDirection.top);
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
    for (final property in _allProperties) {
      if (property.id == propertyId) return property;
    }
    return null;
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
    await _persist();
    notifyListeners();
  }

  int matchScore(RentalProperty p) {
    int score = 0;
    if (p.price <= _filters.maxBudget) {
      score += 40;
    } else if (p.price <= (_filters.maxBudget * 1.15).round()) {
      score += 20;
    }
    if (p.rooms >= _filters.minRooms) {
      score += 30;
    } else if (p.rooms >= _filters.minRooms - 0.5) {
      score += 15;
    }
    if (_searchAreas.isNotEmpty && selectedArea.contains(p.point)) {
      score += 20;
    } else {
      score += 10;
    }
    if (_filters.requiredFeatures.isEmpty) {
      score += 10;
    } else {
      final matched =
          _filters.requiredFeatures.where(p.features.contains).length;
      score += (matched / _filters.requiredFeatures.length * 10).round();
    }
    return score.clamp(0, 100);
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
      maxBudget: 9000,
      minRooms: 2,
      areaId: 'gush_dan',
      requiredFeatures: <String>{},
    );
    _likedPropertyIds = <String>{};
    _passedPropertyIds = <String>{};
    _ownerAcceptedPropertyIds = <String>{};
    _ownerRejectedPropertyIds = <String>{};
    _matches = const [];
    _pendingMatchPropertyId = null;
    _savedPropertyIds = <String>{};
    _lastSeenMatchCount = 0;
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

    if (_tenantReviews.isEmpty) {
      _tenantReviews = _rentalDataService.createTenantReviews();
    }
    _savedPropertyIds = Set<String>.from(
      storedState['savedPropertyIds'] as List<dynamic>? ?? const [],
    );
    _lastSeenMatchCount = storedState['lastSeenMatchCount'] as int? ?? 0;
    _pendingMatchPropertyId = null;
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
    await _localStorageService.saveAppState({
      'schema': 'rental_match_v1',
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
      'userRole': _userRole,
      'savedPropertyIds': _savedPropertyIds.toList(),
      'lastSeenMatchCount': _lastSeenMatchCount,
    });
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

  double get conversionRate => totalCandidatesSeen == 0
      ? 0
      : matchesCount / totalCandidatesSeen * 100;
}
