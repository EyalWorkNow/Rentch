import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dating_app/core/security/input_sanitizer.dart';
import 'package:dating_app/core/security/rate_limiter.dart'
    show RateLimiter, WriteDebouncer;
import 'package:dating_app/core/services/cache_service.dart';
import 'package:dating_app/core/services/event_service.dart';
import 'package:dating_app/core/services/gamification_service.dart';
import 'package:dating_app/core/matching/match_engine.dart';
import 'package:dating_app/core/matching/match_models.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/core/search/smart_search.dart' show SearchQuery, ScoredProperty;
import 'package:dating_app/core/matching/ranked_lead.dart';
import 'package:dating_app/core/services/kiri_3d_service.dart';
import 'package:dating_app/core/services/local_storage.dart';
import 'package:dating_app/core/services/pending_scan_store.dart';
import 'package:dating_app/core/services/property_3d_scan_service.dart';
import 'package:dating_app/core/services/rental_data_service.dart';
import 'package:dating_app/data/models/broker_design_models.dart';
import 'package:dating_app/data/models/profile_tags.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/models/user_signals.dart';
import 'package:dating_app/data/models/persona_profile.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/core/services/signature_service.dart';
import 'package:dating_app/data/models/rental_contract.dart';
import 'package:dating_app/data/repositories/contract_repository.dart';
import 'package:dating_app/data/repositories/moderation_repository.dart';
import 'package:dating_app/data/repositories/property_analytics_repository.dart';
import 'package:dating_app/data/repositories/property_likes_repository.dart';
import 'package:dating_app/data/repositories/property_repository.dart';
import 'package:dating_app/data/repositories/review_repository.dart';
import 'package:dating_app/data/repositories/user_repository.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_card_swiper/flutter_card_swiper.dart';
import 'package:latlong2/latlong.dart';

/// Thrown by [DatingProvider.deleteAccount] when Firebase requires the user to
/// have logged in recently before deleting their account. The UI should ask the
/// user to re-authenticate and then retry the deletion.
///
/// For email/password accounts [needsPassword] is true and [email] is set, so
/// the UI can prompt for the password inline and retry the deletion in-flow via
/// `deleteAccount(reauthPassword: ...)` — the account is still removed without
/// the user ever leaving the deletion flow.
class ReauthRequiredException implements Exception {
  const ReauthRequiredException({this.needsPassword = false, this.email});
  final bool needsPassword;
  final String? email;
  @override
  String toString() => 'ReauthRequiredException';
}

class DatingProvider extends ChangeNotifier {
  DatingProvider({
    RentalDataService? rentalDataService,
    LocalStorageService? localStorageService,
    PropertyRepository? propertyRepository,
    PropertyAnalyticsRepository? propertyAnalyticsRepository,
    UserRepository? userRepository,
    ModerationRepository? moderationRepository,
    ReviewRepository? reviewRepository,
    PropertyLikesRepository? propertyLikesRepository,
  })  : _rentalDataService = rentalDataService ?? RentalDataService(),
        _localStorageService = localStorageService ?? LocalStorageService(),
        _propertyRepository = propertyRepository ?? PropertyRepository(),
        _propertyAnalyticsRepository =
            propertyAnalyticsRepository ?? PropertyAnalyticsRepository(),
        _userRepository = userRepository ?? UserRepository(),
        _moderationRepository = moderationRepository ?? ModerationRepository(),
        _reviewRepository = reviewRepository ?? ReviewRepository(),
        _propertyLikesRepository =
            propertyLikesRepository ?? PropertyLikesRepository();

  final RentalDataService _rentalDataService;
  final LocalStorageService _localStorageService;
  final PropertyRepository _propertyRepository;
  final PropertyAnalyticsRepository _propertyAnalyticsRepository;
  final UserRepository _userRepository;
  final ModerationRepository _moderationRepository;
  final Property3dScanService _scanService = Property3dScanService();
  ContractRepository? _contractRepositoryInstance;
  SignatureService? _signatureServiceInstance;
  ContractRepository get _contractRepository =>
      _contractRepositoryInstance ??= ContractRepository();
  SignatureService get _signatureService =>
      _signatureServiceInstance ??= SignatureService();
  List<RentalContract> _contracts = [];
  final ReviewRepository _reviewRepository;
  final PropertyLikesRepository _propertyLikesRepository;

  // Incoming likes on the current landlord's properties (propertyId → likers),
  // fetched from the backend so a tenant's like on another device is visible.
  Map<String, List<PropertyLike>> _incomingLikesByProperty = {};

  // Batches rapid successive writes so we don't hammer Appwrite on every swipe.
  // With 10k concurrent users, unbatched writes would exhaust API rate limits.
  final _writeDebouncer = WriteDebouncer();

  final CardSwiperController propertySwiperController = CardSwiperController();
  final CardSwiperController ownerSwiperController = CardSwiperController();

  bool _isLoading = true;
  String _userRole = 'tenant';
  bool _isGuestMode = false;
  bool _hasActiveSession = false;
  bool _roleExplicitlyChosen = false;
  // True ONLY once the user is actually inside the in-app experience
  // (HomeScreen is mounted). This is the SOLE gate for broker-black theming —
  // see [themeRole]. It is deliberately NOT persisted: it is a transient
  // "what is on screen right now" flag, re-established on every launch by the
  // startup gate (returning users) or by the entry screens at the moment they
  // navigate into HomeScreen. Because no onboarding / login / signup / role-
  // picker / guest-entry code sets it, the entire entry flow is structurally
  // incapable of turning broker-black.
  bool _isInsideApp = false;
  TenantProfile? _tenantProfile;
  final Map<String, TenantProfile> _cachedProfiles = {};
  final Set<String> _loadingProfileIds = {};
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
  // When the current top card became visible — for swipe latency-to-decision.
  DateTime? _topCardShownAt;
  Set<String> _savedPropertyIds = <String>{};
  int _lastSeenMatchCount = 0;
  int _remainingSuperLikes = 3;
  Set<String> _blockedOwnerNames = <String>{};
  Set<String> _reportedPropertyIds = <String>{};
  Map<String, PropertyMarketSignals> _propertySignalOverrides =
      <String, PropertyMarketSignals>{};
  BrokerBrandingConfig _brokerBranding = BrokerBrandingConfig.defaults;
  final Map<String, _PropertyDetailSession> _activeDetailSessions =
      <String, _PropertyDetailSession>{};
  bool _autoLikeEnabled = false;
  int _currentTabIndex = 0;

  // Per-user revealed-preference aggregate, folded out of the raw swipe/dwell
  // event stream (see [UserSignals]). Loaded from the same local_storage snapshot
  // the rest of the provider state lives in, updated optimistically on each swipe
  // decision, and folded back into the match score so the algorithm personalises
  // from what the user actually does — not just what they declared.
  UserSignals _userSignals = const UserSignals();

  // Declared/inferred persona the assistant accumulates. Local-first (always
  // improves this user's own personalisation); a consent-gated snapshot is
  // exported to the dataset. Accuracy safeguards live inside [PersonaProfile].
  PersonaProfile _persona = PersonaProfile.empty();

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
  static const String _guestLandlordOwnerId = 'guest_landlord';
  static const String _localLandlordOwnerId = 'local_landlord';
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

  // ── Persona weighting (the tenant's "חשוב" / "קריטי" choices) ──────────────
  // These act on the property DIRECTLY (via its own features), so the displayed
  // match % responds to what the tenant marked even when we have no landlord
  // profile to cross-reference. IMPORTANT details give a meaningful boost; a
  // failed CRITICAL deal-breaker applies a heavy penalty that sinks the % so a
  // property that misses a non-negotiable can never look like a strong match.
  static const double _importantPersonaBoost = 9; // per met IMPORTANT detail
  static const double _criticalPersonaPenalty = 45; // per unmet CRITICAL gate

  // ── Learned-signal folding (revealed preferences → score) ──────────────────
  // These deltas are deliberately SMALL: learned behaviour nudges the score, it
  // never re-saturates it. A prior audit compressed the structural band below
  // 100 on purpose; these bounds keep the learned layer from undoing that.
  //
  // revealedBudgetTolerance widens the *effective* max-budget the budget-fit
  // curve is measured against, but only up to this cap, so a user who keeps
  // liking ~15%-over listings stops being punished for being just over their
  // stated cap — without making any price look on-budget.
  static const double _maxLearnedBudgetWiden = 1.20; // never widen past +20%
  // Per matching feature, tagAffinity in [-1, 1] scales to at most this many
  // points (so a strongly-liked feature adds ≤ +_learnedTagWeight and a
  // strongly-disliked one subtracts the same).
  static const double _learnedTagWeight = 4.0;
  // The whole tag-affinity contribution is additionally clamped so a long tag
  // list can't stack into a large swing.
  static const double _maxLearnedTagDelta = 8.0;
  // A liked-area centroid within this radius of the property adds a small
  // location-affinity bonus, scaled by how many likes back the centroid.
  static const double _learnedAreaWeight = 4.0;
  static const double _learnedAreaRadiusKm = 5.0;

  // Tenant preference match-keys that correspond to a concrete property feature,
  // so they can be evaluated against the property alone (no landlord profile
  // needed). Keys absent here are landlord-policy/lifestyle concepts that only a
  // landlord profile can answer, so they're left to the two-sided path.
  static const Map<String, String> _personaKeyToFeatureKey = {
    'parking': 'parking',
    'furnished': 'furnished',
    'elevator': 'elevator',
    'balcony': 'balcony',
    'shelter': 'mamad',
    'ac': 'airConditioning',
    'accessible': 'accessible',
    'pets_allowed': 'petsAllowed',
    'pets': 'petsAllowed',
  };

  // Combined property list: base (from JSON) + landlord-added
  List<RentalProperty> get _allProperties {
    final cached = _allPropertiesCache;
    if (cached != null) return cached;
    return _allPropertiesCache = [
      ..._baseProperties.map(_propertyWithSignalOverride),
      ..._customProperties
          .where(_isDiscoverableCustomProperty)
          .map(_propertyWithSignalOverride),
    ];
  }

  // Full real catalog (base + landlord-added) for the AI search assistant to
  // rank over — independent of the discover-feed filter state.
  List<RentalProperty> get allProperties => _allProperties;

  bool _isDiscoverableCustomProperty(RentalProperty property) {
    if (_isGuestDemoProperty(property)) return _isGuestMode;
    final ownerUserId = property.ownerUserId.trim();
    if (ownerUserId.isEmpty) return true;
    return ownerUserId == _currentOwnerUserId;
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

  /// Brokers (מתווך) manage properties and leads exactly like a private
  /// landlord, so the property-side experience keys off [isLandlord] for both.
  bool get isLandlord => _userRole == 'landlord' || _userRole == 'broker';
  bool get isBroker => _userRole == 'broker';
  String get userRole => _userRole;

  /// True once the user is actually inside the in-app experience (HomeScreen
  /// mounted). The sole gate for broker-black theming.
  bool get isInsideApp => _isInsideApp;

  /// Marks that the user has crossed the entry/in-app boundary — i.e. the app
  /// is now showing [HomeScreen]. Called at the exact navigation seam by the
  /// three (and only three) places that show HomeScreen: the startup gate for
  /// a returning user, and the auth/onboarding screens when they navigate in.
  /// Idempotent and safe to call from a post-frame callback.
  void markEnteredApp() {
    if (_isInsideApp) return;
    _isInsideApp = true;
    notifyListeners();
  }

  /// ponytail: SINGLE SOURCE OF TRUTH for the app-wide brand accent.
  ///
  /// The global accent (teal vs broker-black) MUST be derived from this getter
  /// and nothing else. It returns the broker identity ONLY when the user is a
  /// confirmed broker AND is actually INSIDE the app ([_isInsideApp] — set only
  /// when HomeScreen is reached). Crucially it does NOT key off session state:
  /// a session is established by `setUserRole` / `enterGuestMode` WHILE the user
  /// is still on the entry screens (e.g. right after picking the broker role in
  /// signup, or after a social/guest broker entry, before the success sheet is
  /// dismissed and HomeScreen is pushed). Gating on session there is exactly
  /// what let black leak into the entry flow. Gating on "inside the app"
  /// instead makes that structurally impossible:
  ///   • true first launch → `_isInsideApp = false` → teal for the whole
  ///     onboarding/login/signup/role-pick/guest-entry flow, regardless of the
  ///     chosen role or whether a session was just created.
  ///   • relaunch of a confirmed broker → the startup gate routes them straight
  ///     to HomeScreen and calls [markEnteredApp], so 'broker' (black) is
  ///     correct — and only AFTER HomeScreen is the active screen.
  ///   • logout returns to the entry flow and resets `_isInsideApp = false`, so
  ///     the next sign-up/role-pick is teal again.
  ///
  /// Guarantee: `themeRole == 'broker'` ⟺ a broker is operating INSIDE the app.
  /// Any entry-flow / tenant / landlord / not-yet-entered state ⟹ neutral teal.
  String get themeRole =>
      (_userRole == 'broker' && _isInsideApp) ? 'broker' : 'tenant';
  BrokerBrandingConfig get brokerBranding =>
      isBroker ? _brokerBranding : BrokerBrandingConfig.defaults;
  bool get autoLikeEnabled => _autoLikeEnabled;
  int get currentTabIndex => _currentTabIndex;

  /// The per-user revealed-preference aggregate folded into the match score.
  /// Read-only; mutated only via the swipe path and the [UserSignals] reducer.
  UserSignals get userSignals => _userSignals;

  PersonaProfile get personaProfile => _persona;

  // High-confidence persona reads used to personalise defaults for returning
  // users (null when we aren't sure enough — never guess).
  String? get personaReligiosity =>
      _persona.value('religiosity', now: DateTime.now()) as String?;
  String? get personaCity =>
      _persona.value('city', now: DateTime.now()) as String?;
  int? get personaMaxBudget =>
      (_persona.value('maxBudget', now: DateTime.now()) as num?)?.toInt();

  /// Folds one or more observed persona facts in (each value validated + merged
  /// with confidence/recency/conflict rules), persists locally, and — only when
  /// [export] (the user consented) — emits the consent-gated dataset snapshot.
  /// [export] never affects the local, own-personalisation accumulation.
  void observePersona(
    Map<String, Object?> facts,
    PersonaSource source, {
    bool export = false,
  }) {
    final now = DateTime.now();
    var next = _persona;
    facts.forEach((k, v) => next = next.observe(k, v, source, now: now));
    if (next.version == _persona.version) return; // nothing valid changed
    _persona = next;
    unawaited(_persist());
    if (export) _exportPersona(now);
  }

  /// Emit the current persona snapshot to the dataset once (call only after the
  /// user grants consent — e.g. they said yes after we'd already accumulated).
  void exportPersonaSnapshot() {
    if (_persona.version == 0) return;
    _exportPersona(DateTime.now());
  }

  void _exportPersona(DateTime now) {
    final meta = _persona.toEventMetadata(now);
    // 1) Append-only event row (history/analytics) — inherits the events
    //    pipeline's userId / circuit-breaker / fail-soft guards.
    AppEvents.instance.log(
      UserEventType.personaProfileUpdated,
      metadata: meta,
    );
    // 2) Upsert the single authoritative per-user persona row (the dataset the
    //    backend targeting reads). Row id is forced to the uid server-side; a
    //    higher [version] lets the server ignore a stale out-of-order write.
    final uid = _tenantProfile?.id ?? '';
    if (uid.isEmpty) return;
    unawaited(() async {
      try {
        await AwsApiClient.instance.upsertPersona(uid, {
          ...meta,
          'userId': uid,
          'updatedAt': now.toIso8601String(),
        });
      } catch (_) {/* fail-soft: local persona + event row still recorded */}
    }());
  }
  bool get roleExplicitlyChosen => _roleExplicitlyChosen;
  bool get isGuestMode => _isGuestMode;
  bool get hasActiveSession => _hasActiveSession;
  TenantProfile? get tenantProfile => _tenantProfile;
  SearchFilters get filters => _filters;

  /// Commute-aware recommendation entry point. Threads the tenant's stored work
  /// coordinates into [RecommendationEngine.recommend] so the "מרחק מהעבודה"
  /// scorecard dimension is populated automatically when a work location exists
  /// (otherwise behaviour is unchanged). Returns the legacy [ScoredProperty]
  /// shape the search UI already renders.
  List<ScoredProperty> recommendForTenant(
    List<RentalProperty> candidates,
    SearchQuery query, {
    int limit = 10,
  }) {
    final recs = RecommendationEngine.recommend(
      candidates: candidates,
      query: query,
      profile: _tenantProfile,
      limit: limit,
      workLat: _tenantProfile?.workLat,
      workLon: _tenantProfile?.workLon,
    );
    return [
      for (final r in recs)
        ScoredProperty(
          r.property,
          r.fitScore / 100.0,
          ['${r.fitPct}% התאמה', ...r.highlights],
          r.trainKm,
          r.strictMatch,
          r.scorecard,
        ),
    ];
  }
  List<SearchArea> get searchAreas => _searchAreas;
  List<AppReview> get tenantReviews => const []; // reviews feature removed
  List<RentalMatch> get matches => isLandlord
      ? _matches.where((match) {
          final property = propertyById(match.propertyId);
          return property != null && _belongsToCurrentLandlord(property);
        }).toList(growable: false)
      : _matches;
  int get likesCount => _likedPropertyIds.length;
  Set<String> get likedPropertyIds => _likedPropertyIds;
  int get passedCount => _passedPropertyIds.length;
  int get matchesCount => matches.length;
  bool get canUndo => _swipeHistory.isNotEmpty;
  int get remainingSuperLikes => _remainingSuperLikes;
  String get _currentOwnerUserId {
    if (_isGuestMode && isLandlord) return _guestLandlordOwnerId;
    final profileId = _tenantProfile?.id.trim();
    if (profileId != null && profileId.isNotEmpty) return profileId;
    return _isGuestMode ? 'guest_$_userRole' : _localLandlordOwnerId;
  }

  int get trustScore => _tenantProfile == null
      ? 0
      : GamificationService.computeTrustScore(_tenantProfile!, const []);

  int get profileCompletion => _tenantProfile == null
      ? 0
      : GamificationService.computeProfileCompletion(_tenantProfile!);

  String get profileCompletionHint => _tenantProfile == null
      ? ''
      : GamificationService.nextCompletionHint(_tenantProfile!);
  RentalProperty? get pendingMatchProperty =>
      propertyById(_pendingMatchPropertyId);
  List<RentalProperty> get myProperties => _customProperties
      .where(_belongsToCurrentLandlord)
      .toList(growable: false);
  int get unseenMatchCount =>
      (matches.length - _lastSeenMatchCount).clamp(0, 99);
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
    final allCatalogFeatures = PropertyFeatureCatalog.allLabels.toSet();
    final propertiesFeatures = <String>{};
    for (final property in _allProperties) {
      propertiesFeatures.addAll(property.features);
    }
    final combined = {...allCatalogFeatures, ...propertiesFeatures}.toList()..sort();
    return _availableFeaturesCache = combined;
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

  /// Single source of truth for "does this property show up under [filters]".
  /// Combines the filter predicate with the same blocked-owner / reported
  /// exclusions the swipe deck applies, so the count, preview, average price
  /// and the actual displayed list can never disagree. Previously the count
  /// used only [_passesFilters] and so over-reported by including blocked or
  /// reported properties that never appear in the deck.
  bool _isVisibleUnderFilters(
    RentalProperty property,
    SearchFilters filters,
    DateTime now,
    SearchArea area,
  ) {
    if (_blockedOwnerNames.contains(property.ownerName)) return false;
    if (_reportedPropertyIds.contains(property.id)) return false;
    return _passesFilters(property, filters, now, area);
  }

  int filteredCountFor(SearchFilters filters) {
    if (_searchAreas.isEmpty) return 0;
    final now = DateTime.now();
    final area = _areaFor(filters);
    var count = 0;
    for (final property in _allProperties) {
      if (_isVisibleUnderFilters(property, filters, now, area)) count++;
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
      if (_isVisibleUnderFilters(property, filters, now, area)) {
        count++;
        total += property.price;
      }
    }
    return count == 0 ? 0 : total / count;
  }

  List<RentalProperty> previewFilteredProperties(
    SearchFilters filters, {
    int limit = 500,
  }) {
    if (_searchAreas.isEmpty || limit <= 0) return const [];
    final now = DateTime.now();
    final area = _areaFor(filters);
    final preview = <RentalProperty>[];
    for (final property in _allProperties) {
      if (_isVisibleUnderFilters(property, filters, now, area)) {
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
            _isVisibleUnderFilters(property, filters, now, area))
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

  // Israeli city names have many spellings ("תל אביב" / "תל אביב-יפו" / "תל אביב
  // יפו"). Normalise (hyphens→space, drop the יפו suffix, collapse spaces) and
  // accept an either-way containment so a valid city search isn't emptied by a
  // format mismatch between the parsed city and the stored one.
  static String _normCity(String s) {
    var t = s
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[־\-,]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Drop a trailing " יפו" (תל אביב יפו → תל אביב) but keep "יפו" on its own.
    t = t.replaceAll(RegExp(r'\sיפו$'), '').trim();
    return t;
  }

  static bool _cityMatches(String propertyCity, String filterCity) {
    final a = _normCity(propertyCity);
    final b = _normCity(filterCity);
    if (a.isEmpty || b.isEmpty) return true; // unknown → don't exclude
    return a == b || a.contains(b) || b.contains(a);
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
        !_cityMatches(property.city, filters.city)) {
      return false;
    }

    if (filters.hasQuery) {
      final query = filters.query.trim().toLowerCase();
      final searchableText = property.searchableText.toLowerCase();
      if (!searchableText.contains(query) &&
          !property.address.toLowerCase().contains(query)) {
        return false;
      }
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

    if (filters.hasCustomArea) {
      return area.contains(property.point);
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
      // Over-budget: best-match normally allows a soft near-miss (×1.22) so the
      // deck can still surface close options. But an explicit typed "עד X"
      // (strictMaxBudget) is a HARD ceiling — previously a ₪4,700 flat showed
      // for a ₪4,000 cap, which reads as a bug.
      final budgetCeiling = filters.strictMaxBudget
          ? filters.maxBudget
          : (filters.maxBudget * 1.22).round();
      if (filters.maxBudget < _defaultMaxBudgetFor(filters.transactionType) &&
          property.price > budgetCeiling) {
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
    final leads = _allProperties.where((property) {
      final hasIncoming =
          _incomingLikesByProperty[property.id]?.isNotEmpty ?? false;
      return _belongsToCurrentLandlord(property) &&
          // A real tenant liked it (cross-user) OR a locally-seeded demo like.
          (hasIncoming || _likedPropertyIds.contains(property.id)) &&
          !_ownerAcceptedPropertyIds.contains(property.id) &&
          !_ownerRejectedPropertyIds.contains(property.id) &&
          !_matches.any((match) => match.propertyId == property.id);
    }).toList();

    // Surface the best-fit candidate first. Each lead is a property the
    // landlord owns that an interested tenant liked; we rank by how well that
    // tenant genuinely fits THIS property, using only real profile data
    // (budget vs asking rent, move-in timing, and the existing trust score).
    // Stable: ties fall back to id so ordering is deterministic and the lead
    // membership the rest of the app relies on is unchanged — only reordered.
    final tenant = _tenantProfile;
    if (tenant == null || leads.length < 2) return leads;

    final scores = <String, double>{
      for (final property in leads) property.id: leadFitScore(property),
    };
    leads.sort((a, b) {
      final delta = (scores[b.id] ?? 0).compareTo(scores[a.id] ?? 0);
      if (delta != 0) return delta;
      return a.id.compareTo(b.id);
    });
    return leads;
  }

  // ── Candidate (lead) ranking ────────────────────────────────────────────
  // The score below the [_highFitLeadScore] threshold gets no "high match"
  // badge — it is honest: a candidate only earns the badge when the real
  // signals line up. Score is in [0, 100].
  static const double _highFitLeadScore = 70;
  static const double _leadBudgetWeight = 60; // budget vs asking rent
  static const double _leadTimingWeight = 25; // move-in timing match
  static const double _leadTrustWeight = 15; // existing trust-score signal

  /// Honest fit score in [0, 100] for the tenant who liked [property], scored
  /// against the current tenant profile's REAL fields only. Drives both the
  /// ranking order and the "התאמה גבוהה" badge — no fabricated trust.
  double leadFitScore(RentalProperty property) {
    final tenant = _tenantProfile;
    if (tenant == null) return 0;

    final budgetFit = _leadBudgetFit(tenant, property); // [0, 1]
    final timingFit = _leadTimingFit(tenant, property); // [0, 1] or null
    // Reuse the app's real trust signal (photo/bio/budget/etc.), normalised.
    final trustFit =
        GamificationService.computeTrustScore(tenant, const []) / 100.0;

    var score = budgetFit * _leadBudgetWeight + trustFit * _leadTrustWeight;
    // Only let timing move the score when we actually have a property entry
    // date to compare against — otherwise skip it honestly (no invented fit).
    if (timingFit != null) score += timingFit * _leadTimingWeight;
    return score.clamp(0, 100).toDouble();
  }

  /// True when the candidate's fit is genuinely strong (top tier) — used for
  /// the honest "התאמה גבוהה" badge.
  bool isHighFitLead(RentalProperty property) =>
      leadFitScore(property) >= _highFitLeadScore;

  /// One concrete, real reason this candidate fits — or null if none stands
  /// out. Budget is checked first (the strongest signal), then timing.
  String? leadFitReason(RentalProperty property) {
    final tenant = _tenantProfile;
    if (tenant == null) return null;
    if (_hasKnownPrice(property) &&
        tenant.budgetMax >= property.price &&
        _leadBudgetFit(tenant, property) >= 0.8) {
      return 'התקציב מתאים למחיר';
    }
    final timingFit = _leadTimingFit(tenant, property);
    if (timingFit != null && timingFit >= 0.8) {
      return 'כניסה בזמן שמתאים לך';
    }
    return null;
  }

  // Budget fit in [0, 1]: a tenant whose budget meets the asking rent and sits
  // close to it scores high; a budget far BELOW the rent scores low (they
  // likely can't afford it). A comfortable margin above is fine, not penalised
  // hard. Unknown price → neutral 0.5 (we can't claim a fit we can't measure).
  double _leadBudgetFit(TenantProfile tenant, RentalProperty property) {
    if (!_hasKnownPrice(property) || property.price <= 0) return 0.5;
    final ratio = tenant.budgetMax / property.price;
    if (ratio >= 1.0) {
      // Budget covers rent. Closest-to-rent is the strongest signal; a very
      // large budget gap is fine but no longer a tighter "match", so it eases
      // off gently rather than dropping.
      final over = ratio - 1.0;
      return (1.0 - (over * 0.4)).clamp(0.6, 1.0);
    }
    // Budget below rent: ramps down to 0 by the time they're 30% short.
    return (1.0 - (1.0 - ratio) / 0.30).clamp(0.0, 1.0);
  }

  // Move-in timing fit in [0, 1], or null when the property has no entry date
  // to compare against (so we never invent a timing match). Compares the
  // tenant's declared move-in window against the property's available-from
  // date: the sooner the tenant can move relative to availability, the better.
  double? _leadTimingFit(TenantProfile tenant, RentalProperty property) {
    final entryDate = property.entryDateValue;
    if (entryDate == null) return null;
    final window = tenant.moveInWindow.trim();
    if (window.isEmpty) return null;

    final tenantReadyDays = _tenantMoveInDays(window);
    if (tenantReadyDays == null) return null; // unrecognised/flexible

    final daysUntilAvailable =
        entryDate.difference(DateTime.now()).inDays.clamp(0, 3650);
    // The tenant fits the timing when they're ready by the time the property
    // is available. If the property is available well before the tenant is
    // ready, fit tapers off (landlord waits longer than they'd like).
    if (tenantReadyDays <= daysUntilAvailable) return 1.0;
    final gap = tenantReadyDays - daysUntilAvailable;
    return (1.0 - gap / 120.0).clamp(0.0, 1.0);
  }

  // Maps a declared move-in window to an approximate "ready in N days". A
  // flexible/blank window returns null (no timing signal to score on).
  int? _tenantMoveInDays(String window) {
    if (window.contains('מיידי')) return 0;
    if (window.contains('תוך חודש') || window.contains('30')) return 30;
    if (window.contains('1-3') || window.contains('60')) return 90;
    if (window.contains('3-6')) return 180;
    return null;
  }

  /// Total number of tenant likes across the current landlord's properties —
  /// drives the "interest" badge so the owner sees that a like came in.
  int get incomingLikesCount =>
      _incomingLikesByProperty.values.fold(0, (sum, l) => sum + l.length);

  /// The tenants who liked a specific owned property.
  List<PropertyLike> incomingLikesFor(String propertyId) =>
      _incomingLikesByProperty[propertyId] ?? const [];

  DateTime? _lastIncomingLikesRefresh;

  /// Landlord: pull the likes on every owned property from the backend so a
  /// tenant's like (made on another device) becomes visible here. Throttled so
  /// it can be called freely from UI builds.
  Future<void> refreshIncomingLikes({bool force = false}) async {
    if (!isLandlord || !_propertyLikesRepository.isConfigured) return;
    final now = DateTime.now();
    if (!force &&
        _lastIncomingLikesRefresh != null &&
        now.difference(_lastIncomingLikesRefresh!).inSeconds < 15) {
      return;
    }
    _lastIncomingLikesRefresh = now;
    final ownedIds = _allProperties
        .where(_belongsToCurrentLandlord)
        .map((p) => p.id)
        .toSet();
    if (ownedIds.isEmpty) {
      if (_incomingLikesByProperty.isNotEmpty) {
        _incomingLikesByProperty = {};
        notifyListeners();
      }
      return;
    }
    try {
      final entries = await Future.wait(ownedIds.map((id) async {
        final likes = await _propertyLikesRepository.likesForProperty(id);
        return MapEntry(id, likes);
      }));
      _incomingLikesByProperty = {
        for (final e in entries)
          if (e.value.isNotEmpty) e.key: e.value,
      };
      notifyListeners();
    } catch (_) {/* best-effort */}
  }

  bool _belongsToCurrentLandlord(RentalProperty property) {
    final ownerUserId = property.ownerUserId.trim();
    if (ownerUserId.isNotEmpty) {
      return ownerUserId == _currentOwnerUserId;
    }

    if (_isGuestDemoProperty(property)) {
      return _isGuestMode && isLandlord;
    }

    // Legacy locally-added listings predate ownerUserId. Keep them visible for
    // the active landlord account, but never treat imported/base listings as
    // owned just because they lack ownership metadata.
    return !_isGuestMode &&
        isLandlord &&
        _customProperties.any((custom) => custom.id == property.id);
  }

  bool _isGuestDemoProperty(RentalProperty property) {
    return property.id.startsWith('demo-prop-') ||
        property.ownerUserId == _guestLandlordOwnerId;
  }

  RentalProperty? _customPropertyById(String propertyId) {
    for (final property in _customProperties) {
      if (property.id == propertyId) return property;
    }
    return null;
  }

  RentalProperty _ownedByCurrentLandlord(RentalProperty property) {
    final existing = _customPropertyById(property.id);
    final existingOwnerUserId = existing?.ownerUserId.trim() ?? '';
    if (existingOwnerUserId.isNotEmpty) {
      return property.copyWith(ownerUserId: existingOwnerUserId);
    }
    return property.copyWith(ownerUserId: _currentOwnerUserId);
  }

  RentalProperty? get activeLandlordProxy {
    final properties = isLandlord ? myProperties : _allProperties;
    if (properties.isEmpty) return null;
    if (_likedPropertyIds.isNotEmpty) {
      final liked = propertyById(_likedPropertyIds.first);
      if (liked != null && properties.any((p) => p.id == liked.id)) {
        return liked;
      }
    }
    if (!isLandlord && filteredProperties.isNotEmpty) {
      return filteredProperties.first;
    }
    return properties.first;
  }

  List<RentalProperty> get landlordProxyPortfolio {
    final featured = <RentalProperty>[];
    final active = activeLandlordProxy;
    if (active != null) {
      featured.add(active);
    }
    for (final property in isLandlord ? myProperties : _allProperties) {
      if (featured.length >= 2) break;
      if (active != null && property.id == active.id) continue;
      featured.add(property);
    }
    return featured;
  }

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      final firstPage = await _rentalDataService
          .loadFirstPage(areaId: _filters.areaId)
          .timeout(const Duration(seconds: 20));
      _baseProperties = firstPage.items;
      _hasMoreProperties = firstPage.hasMore;
      _propertiesOffset = firstPage.items.length;
      _propertiesCursor = firstPage.nextCursor;
    } catch (_) {
      // Network unavailable or timeout — proceed with empty catalog.
      // Properties will appear once connectivity is restored.
      _baseProperties = [];
      _hasMoreProperties = false;
      _propertiesOffset = 0;
      _propertiesCursor = null;
    }
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

    // Ensure every session has a Firebase JWT before the first _persist() so
    // the API Gateway authorizer doesn't reject backend calls with 401.
    // Authenticated users already have a real token; everyone else gets an
    // anonymous one so property loads and saves work out of the box.
    // Fire-and-forget so a slow network never blocks app startup.
    if (!_hasAuthenticatedFirebaseUser) {
      unawaited(_ensureAnonymousFirebaseSession());
    }

    await _persist();

    if (_hasAuthenticatedFirebaseUser) {
      // Recover the returning user's UID binding + their own listings from the
      // backend before refreshing the public catalog. Without this, a relaunch
      // after a cleared local cache (logout/reinstall) shows zero of the user's
      // own uploads even though they're safely stored server-side.
      unawaited(restoreAuthenticatedSession());
      unawaited(_refreshRemoteCatalogAfterAuth());
      unawaited(_refreshCurrentTenantReviewsAfterAuth());
      // Pull mutual matches a landlord created for this tenant on another device,
      // so the chat shows up in their conversations (was local-only → invisible).
      unawaited(_loadMatchesFromBackend());
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

    // After 3 seconds (UI is settled), proactively load remaining DB pages in
    // the background so the Lasso grid shows every property, not just 150.
    if (_hasMoreProperties) {
      Future<void>.delayed(const Duration(seconds: 3))
          .then((_) => _fetchAllRemainingPages());
    }
  }

  /// Fetches all pages after the first one without blocking the UI.
  /// Waits between pages so network bursts don't compete with UI rendering.
  /// Capped at 20 pages (~10 000 properties) to prevent runaway loading.
  Future<void> _fetchAllRemainingPages() async {
    const maxExtraPages = 20;
    int pagesLoaded = 0;
    while (_hasMoreProperties && pagesLoaded < maxExtraPages) {
      if (_isLoadingMoreProperties) return;
      _isLoadingMoreProperties = true;
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
          pagesLoaded++;
          if (kDebugMode) {
            debugPrint(
              'DatingProvider.preload page $pagesLoaded: '
              '+${page.items.length} (total: ${_baseProperties.length}, hasMore: $_hasMoreProperties)',
            );
          }
          notifyListeners();
        } else {
          _hasMoreProperties = false;
          _propertiesCursor = null;
        }
      } catch (_) {
        break;
      } finally {
        _isLoadingMoreProperties = false;
      }
      // Brief pause between pages — lets the UI breathe between network bursts.
      if (_hasMoreProperties) {
        await Future<void>.delayed(const Duration(milliseconds: 800));
      }
    }
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

  Future<void> setUserRole(String role, {bool explicit = false}) async {
    _userRole = role;
    _isGuestMode = false;
    _hasActiveSession = true;
    if (explicit) _roleExplicitlyChosen = true;
    await _refreshRemoteCatalogAfterAuth();
    await _persist();
    AppEvents.instance.log(UserEventType.roleChanged, metadata: {'role': role});
    notifyListeners();
  }

  Future<void> updateBrokerBranding(BrokerBrandingConfig branding) async {
    if (!isBroker) return;
    _brokerBranding = branding;
    await _persist();
    notifyListeners();
  }

  Future<void> _refreshRemoteCatalogAfterAuth() async {
    if (_isRefreshingRemoteCatalog) return;
    if (!_hasAuthenticatedFirebaseUser) return;

    _isRefreshingRemoteCatalog = true;
    try {
      await _firebaseAuthOrNull?.currentUser?.getIdToken(true);
      AppCache.instance.propertyPages.clear();

      final firstPage = await _rentalDataService.loadFirstPage(
        areaId: _filters.areaId,
      );

      final items = firstPage.items;
      if (items.isEmpty) return;

      _baseProperties = items;
      _hasMoreProperties = firstPage.hasMore;
      _propertiesOffset = items.length;
      _propertiesCursor = firstPage.nextCursor;
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
      notifyListeners();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('DatingProvider.refreshRemoteCatalog failed: $error');
      }
    } finally {
      _isRefreshingRemoteCatalog = false;
    }
  }

  bool get _hasAuthenticatedFirebaseUser {
    return _firebaseAuthOrNull?.currentUser != null;
  }

  FirebaseAuth? get _firebaseAuthOrNull {
    if (Firebase.apps.isEmpty) return null;
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  Future<void> _ensureAnonymousFirebaseSession() async {
    final auth = _firebaseAuthOrNull;
    if (auth == null) return;
    try {
      if (auth.currentUser == null) {
        // 10-second cap: on a slow/offline simulator signInAnonymously can
        // block for the iOS default socket timeout (~60 s). We degrade
        // gracefully — the JWT will be obtained on the next successful call.
        await auth
            .signInAnonymously()
            .timeout(const Duration(seconds: 10));
      }
    } catch (_) {}
  }

  Future<void> enterGuestMode(String role) async {
    _seedGuestDemoState(role);
    _hasActiveSession = true;
    // Fire-and-forget the anonymous Firebase session so the UI never blocks
    // on network availability. The JWT will arrive within a few seconds in
    // the background; the first backend calls may get a 401 and retry.
    unawaited(_ensureAnonymousFirebaseSession());
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
    // Back to the entry flow → must render the neutral teal brand again, even
    // if the user was previously an in-app broker (black). Without this reset a
    // logged-out broker would briefly see black accents on the entry screens.
    _isInsideApp = false;
    _seedInitialState();
    await _persist();
    // Clear circuit breakers and rate-limit buckets on logout.
    RateLimiter.instance.reset();
    notifyListeners();
  }

  /// Permanently deletes the user's account (App Store Guideline 5.1.1(v)).
  ///
  /// Deletes the Firebase Auth credential FIRST so the account itself is gone —
  /// not just the profile data. If Firebase requires a fresh login it throws
  /// [ReauthRequiredException] before any data is touched, so the caller can ask
  /// the user to re-authenticate and retry without losing data prematurely.
  Future<void> deleteAccount({String? reauthPassword}) async {
    final userId = _tenantProfile?.id ?? '';
    final auth = _firebaseAuthOrNull;
    final user = auth?.currentUser;

    // 1. Remove the Firebase Auth credential (the actual "account").
    if (user != null) {
      try {
        await user.delete();
      } on FirebaseAuthException catch (e) {
        if (e.code == 'requires-recent-login') {
          final email = user.email;
          final isPasswordUser =
              user.providerData.any((p) => p.providerId == 'password');
          // Email/password account: re-authenticate inline (with the password
          // the UI just collected) and retry the delete so the flow completes
          // without bouncing the user back to the login screen.
          if (isPasswordUser && reauthPassword != null && email != null) {
            try {
              await user.reauthenticateWithCredential(
                EmailAuthProvider.credential(
                  email: email,
                  password: reauthPassword,
                ),
              );
              await user.delete();
            } on FirebaseAuthException {
              // Wrong password / still stale → let the UI re-prompt.
              throw ReauthRequiredException(
                  needsPassword: true, email: email);
            }
          } else if (isPasswordUser) {
            // Need the password from the UI before we can proceed.
            throw ReauthRequiredException(needsPassword: true, email: email);
          } else {
            // OAuth (Google/Apple) — UI routes to a fresh sign-in + retry.
            throw const ReauthRequiredException();
          }
        }
        // Any other auth error: still purge data + sign out below.
      } catch (_) {}
    }

    AppEvents.instance.log(UserEventType.sessionEnded,
        metadata: {'reason': 'account_deleted'});

    // 2. Purge the user's own content: their listings (user-generated content)
    //    and their profile row from the backend.
    for (final property in _customProperties) {
      unawaited(_propertyRepository.deleteProperty(property.id));
    }
    if (userId.isNotEmpty) {
      await _userRepository.deleteProfile(userId);
    }

    // 3. Clear all local state and end any residual session.
    await _localStorageService.clearAppState();
    try {
      await auth?.signOut();
    } catch (_) {}

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

  // Binds the in-memory profile to the real Firebase UID and pulls the user's
  // stored profile + listings from the backend. Call this from EVERY non-guest
  // sign-in path (Google, Apple, email/password login, email registration) so a
  // returning user always recovers their own data and uploads are tagged with
  // their UID — never the shared local default.
  Future<void> applyAuthenticatedIdentity({
    required String displayName,
    String? photoUrl,
    String source = 'password',
  }) =>
      _bindFirebaseIdentity(
        displayName: displayName,
        photoUrl: photoUrl,
        source: source,
        overwriteIdentityFields: true,
      );

  // Backward-compatible alias for existing social-login call sites.
  Future<void> applyGoogleIdentity({
    required String displayName,
    String? photoUrl,
    String source = 'google',
  }) =>
      applyAuthenticatedIdentity(
        displayName: displayName,
        photoUrl: photoUrl,
        source: source,
      );

  // Called on app startup when a persisted, non-anonymous Firebase session is
  // restored from disk. Recovers the UID binding + backend listings WITHOUT
  // touching the display name / photo the user already has locally. Without this
  // a returning user who simply relaunches the app (and whose local cache was
  // cleared, e.g. by a prior logout or reinstall) would never see their uploads.
  Future<void> restoreAuthenticatedSession() async {
    final user = _firebaseAuthOrNull?.currentUser;
    if (user == null || user.isAnonymous) return;
    await _bindFirebaseIdentity(
      displayName: '',
      photoUrl: null,
      source: 'session-restore',
      overwriteIdentityFields: false,
    );
  }

  Future<void> _bindFirebaseIdentity({
    required String displayName,
    String? photoUrl,
    required String source,
    required bool overwriteIdentityFields,
  }) async {
    // Bind the profile to the real Firebase UID so each user's data is isolated.
    final wasGuestMode = _isGuestMode;
    final previousOwnerUserId = _currentOwnerUserId;
    final uid = _firebaseAuthOrNull?.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    // Load the user's EXISTING profile from the backend first, so a returning
    // user gets their saved data instead of a fresh local default (and so we
    // never overwrite their stored profile with an empty one on re-login).
    final remoteProfile = await _userRepository.getProfile(uid);

    final base = remoteProfile ??
        _tenantProfile ??
        _rentalDataService.createDefaultTenantProfile();
    final current = base.id != uid ? base.copyWith(id: uid) : base;

    if (overwriteIdentityFields) {
      final nextPhotos = <String>[
        if (photoUrl != null && photoUrl.trim().isNotEmpty) photoUrl.trim(),
        ...current.photoUrls.where((url) => url != photoUrl),
      ];
      _tenantProfile = current.copyWith(
        name: displayName.trim().isEmpty ? current.name : displayName.trim(),
        photoUrls: nextPhotos,
      );
    } else {
      _tenantProfile = current;
    }

    _isGuestMode = false;
    if (isLandlord && !wasGuestMode) {
      _retagCurrentLandlordProperties(
        previousOwnerUserId: previousOwnerUserId,
        nextOwnerUserId: _currentOwnerUserId,
      );
    }

    // Load the user's own properties from the backend and merge them in, so
    // the landlord sees every listing they ever uploaded — on any device.
    final ownerProps = await _rentalDataService.loadPropertiesByOwner(uid);
    if (ownerProps.isNotEmpty) {
      final merged = [..._customProperties];
      for (final prop in ownerProps) {
        final idx = merged.indexWhere((p) => p.id == prop.id);
        if (idx >= 0) {
          merged[idx] = prop;
        } else {
          merged.add(prop);
        }
      }
      _customProperties = merged;
      _invalidateCatalogCache();
    }

    await _persist();
    unawaited(_userRepository.upsertProfile(
      _tenantProfile!,
      role: _userRole,
      discoverable: true,
    ));
    AppEvents.instance
      ..setUserId(_tenantProfile!.id)
      ..log(UserEventType.profileUpdated, metadata: {'source': source});
    notifyListeners();

    // Now that the landlord's own properties are loaded, pull who liked them.
    unawaited(refreshIncomingLikes());
  }

  void _retagCurrentLandlordProperties({
    required String previousOwnerUserId,
    required String nextOwnerUserId,
  }) {
    if (nextOwnerUserId.trim().isEmpty ||
        previousOwnerUserId == nextOwnerUserId) {
      return;
    }

    var changed = false;
    _customProperties = _customProperties.map((property) {
      if (_isGuestDemoProperty(property)) return property;
      final ownerUserId = property.ownerUserId.trim();
      if (ownerUserId.isNotEmpty && ownerUserId != previousOwnerUserId) {
        return property;
      }
      changed = true;
      return property.copyWith(ownerUserId: nextOwnerUserId);
    }).toList(growable: false);

    if (changed) _invalidateCatalogCache();
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
    final ownedProperty = _ownedByCurrentLandlord(property);
    _customProperties = [..._customProperties, ownedProperty];
    _invalidateCatalogCache();
    await _persist();
    unawaited(
      _propertyRepository
          .saveProperty(ownedProperty,
              ownerUserId: ownedProperty.ownerUserId, status: status)
          .then((result) {
        if (!result.isOk && kDebugMode) {
          debugPrint(
              'addLandlordProperty: remote rejected — ${result.userMessage}');
        }
      }),
    );
    AppEvents.instance.log(
      UserEventType.propertyAdded,
      propertyId: ownedProperty.id,
      metadata: {
        'city': ownedProperty.city,
        'type': ownedProperty.propertyType,
        'status': status.name,
      },
    );
    notifyListeners();
  }

  Future<void> updateLandlordProperty(RentalProperty updated) async {
    final existing = _customPropertyById(updated.id);
    if (existing == null || !_belongsToCurrentLandlord(existing)) return;
    final ownedProperty = _ownedByCurrentLandlord(updated);
    _customProperties = _customProperties
        .map((p) => p.id == ownedProperty.id ? ownedProperty : p)
        .toList();
    _invalidateCatalogCache();
    await _persist();
    unawaited(
      _propertyRepository
          .saveProperty(
            ownedProperty,
            ownerUserId: ownedProperty.ownerUserId,
            status: ownedProperty.isActive
                ? PropertyRecordStatus.active
                : PropertyRecordStatus.paused,
          )
          .then((result) {
        if (!result.isOk && kDebugMode) {
          debugPrint(
              'updateLandlordProperty: remote rejected — ${result.userMessage}');
        }
      }),
    );
    AppEvents.instance
        .log(UserEventType.propertyUpdated, propertyId: ownedProperty.id);
    notifyListeners();
  }

  Future<void> removeLandlordProperty(String propertyId) async {
    final existing = _customPropertyById(propertyId);
    if (existing == null || !_belongsToCurrentLandlord(existing)) return;
    _customProperties =
        _customProperties.where((p) => p.id != propertyId).toList();
    _invalidateCatalogCache();
    // Drop it from the browse/search cache immediately so seekers stop seeing it.
    AppCache.instance.propertyPages.clear();
    await _persist();
    // SOFT delete: keep the row in the DB (audit/history) but flip its status off
    // 'active' so apartment-seekers no longer see it in search/discovery.
    unawaited(_propertyRepository.saveProperty(existing,
        ownerUserId: existing.ownerUserId,
        status: PropertyRecordStatus.removed));
    notifyListeners();
  }

  Future<void> attachPropertyVirtualTour({
    required String propertyId,
    required PropertyVirtualTour tour,
  }) async {
    var changed = false;
    final updated = _customProperties.map((property) {
      if (property.id != propertyId) return property;
      if (!_belongsToCurrentLandlord(property)) return property;
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

  /// Re-checks the live Teleport state for a property whose 3D tour is still in
  /// flight and persists the result. Without this the tour status is frozen at
  /// whatever it was at upload time, so a capture that finished (READY) — or,
  /// critically, that FAILED on Teleport's side minutes later — would keep
  /// showing "בעיבוד" forever (the reported "stuck for 5 hours" bug). Safe to
  /// call from any screen; it only acts on the owner's own in-flight tours.
  Future<void> refreshPropertyTour(String propertyId) async {
    final property = _customPropertyById(propertyId);
    final tour = property?.virtualTour;
    if (property == null || tour == null) return;
    if (!_belongsToCurrentLandlord(property)) return;
    // Only poll tours that can still change.
    if (!(tour.isProcessing || tour.needsBackendUpload)) return;
    if (tour.id.trim().isEmpty) return;
    try {
      final updated = await _scanService.refresh(tour);
      if (updated.status != tour.status ||
          updated.viewerUrl != tour.viewerUrl ||
          updated.errorMessage != tour.errorMessage) {
        await attachPropertyVirtualTour(propertyId: propertyId, tour: updated);
      }
    } catch (error) {
      if (kDebugMode) debugPrint('refreshPropertyTour($propertyId): $error');
    }
  }

  /// Refreshes every in-flight owned tour at once — used on the landlord's
  /// screens / app resume so statuses update without opening each listing.
  Future<void> refreshOwnedTours() async {
    final pending = _customProperties
        .where((p) =>
            _belongsToCurrentLandlord(p) &&
            (p.virtualTour?.isProcessing == true ||
                p.virtualTour?.needsBackendUpload == true))
        .map((p) => p.id)
        .toList();
    for (final id in pending) {
      await refreshPropertyTour(id);
    }
    // KIRI 3D-scan jobs run in the background too — re-check them on the same
    // hooks so a finished model surfaces without re-opening the capture screen.
    await finalizePendingScans();
  }

  /// Attaches a finished KIRI 3D-scan model to an owned property and persists it,
  /// then surfaces the "סריקת תלת-מימד" viewer. Mirrors [attachPropertyVirtualTour]:
  /// it only ever touches the current landlord's own listings.
  Future<void> attachPropertyModel3d({
    required String propertyId,
    required PropertyModel3d model3d,
  }) async {
    var changed = false;
    final updated = _customProperties.map((property) {
      if (property.id != propertyId) return property;
      if (!_belongsToCurrentLandlord(property)) return property;
      changed = true;
      return property.copyWith(model3d: model3d);
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
              'attachPropertyModel3d: remote rejected — ${result.userMessage}');
        }
      }));
      AppEvents.instance
          .log(UserEventType.tourUploaded, propertyId: propertyId);
    }
    notifyListeners();
  }

  /// Re-checks every locally-persisted in-flight 3D scan against the backend
  /// (which polls KIRI; on KIRI status==2 it fetches+extracts the model zip,
  /// re-hosts the assets, and marks the job ready). When a job is ready we attach
  /// its model to the property and drop the record; failed jobs are also dropped.
  /// Safe to call from any owner-facing screen / on app resume — never throws.
  Future<void> finalizePendingScans() async {
    if (!Kiri3dService.instance.isConfigured) return;
    final List<PendingScan> pending;
    try {
      pending = await PendingScanStore.instance.all();
    } catch (_) {
      return;
    }
    if (pending.isEmpty) return;
    for (final scan in pending) {
      // Only act on the current landlord's own listings.
      final property = _customPropertyById(scan.propertyId);
      if (property == null || !_belongsToCurrentLandlord(property)) continue;
      try {
        // Close the create→start gap: if a submit ever didn't take (no
        // `serialize` on the backend job), `start` is idempotent — it submits a
        // still-"pending" job to KIRI and is a no-op once already submitted.
        try {
          await Kiri3dService.instance.start(scan.jobId);
        } catch (_) {/* best-effort; getStatus below still reports state */}
        final job = await Kiri3dService.instance.result(scan.jobId);
        if (job.isReady && job.hasAssets) {
          final model = PropertyModel3d(
            glbUrl: job.meshGlbUrl ?? '',
            plyUrl: job.splatUrl ?? '',
            scanDate: DateTime.now().toUtc(),
          );
          await attachPropertyModel3d(propertyId: scan.propertyId, model3d: model);
          await PendingScanStore.instance.remove(scan.jobId);
        } else if (job.isFailed) {
          // Reconstruction failed on KIRI — stop polling it.
          await PendingScanStore.instance.remove(scan.jobId);
        }
        // Otherwise still processing — leave it for the next finalize pass.
      } catch (error) {
        if (kDebugMode) debugPrint('finalizePendingScans(${scan.jobId}): $error');
      }
    }
    // Reflect any newly-removed (ready/failed) jobs in the cached processing set.
    await refreshScanProcessingCache();
  }

  // In-memory mirror of the property ids with an in-flight background scan, so
  // widgets can read the "processing" state synchronously during build (the
  // store itself is async). Refreshed by [refreshScanProcessingCache] and kept
  // current by [finalizePendingScans].
  Set<String> _scanProcessingPropertyIds = const {};

  /// Synchronous: does [propertyId] currently have a 3D scan reconstructing in
  /// the background? Drives the "מעבד… נודיע כשמוכן" notice on the listing.
  bool isScanProcessing(String propertyId) =>
      _scanProcessingPropertyIds.contains(propertyId);

  /// Reloads the cached set of property ids with an in-flight scan and notifies
  /// listeners if it changed. Cheap and safe to call from any owner screen.
  Future<void> refreshScanProcessingCache() async {
    try {
      final pending = await PendingScanStore.instance.all();
      final ids = pending.map((s) => s.propertyId).toSet();
      if (!setEquals(ids, _scanProcessingPropertyIds)) {
        _scanProcessingPropertyIds = ids;
        notifyListeners();
      }
    } catch (_) {/* fail-soft */}
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
    // Cross-user like: write a row the property's landlord can read, so a like
    // from this device is visible to the owner on theirs. Don't like your own.
    final property = propertyById(propertyId);
    if (property != null &&
        property.ownerUserId.isNotEmpty &&
        property.ownerUserId != _currentOwnerUserId) {
      unawaited(
        _propertyLikesRepository.addLike(
          propertyId: propertyId,
          ownerUserId: property.ownerUserId,
          tenantId: _currentAnalyticsUserId,
          tenantName: _tenantProfile?.name ?? 'מתעניין/ת',
          tenantPhotoUrl: _tenantProfile?.photoUrls.isNotEmpty == true
              ? _tenantProfile!.photoUrls.first
              : '',
          at: now,
        ),
      );
    }
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
    unawaited(
      _propertyLikesRepository.removeLike(
        propertyId: propertyId,
        tenantId: _currentAnalyticsUserId,
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

  // ── Real engagement counts (views + likes) ──────────────────────────────────

  final Set<String> _viewedThisSession = <String>{};

  /// Call when a listing is opened: records a (distinct) view on the server and
  /// refreshes its real view/like counts. Owners don't inflate their own views.
  Future<void> recordPropertyView(String propertyId) async {
    if (!_viewedThisSession.contains(propertyId)) {
      _viewedThisSession.add(propertyId);
      final property = propertyById(propertyId);
      if (property != null &&
          property.ownerUserId.isNotEmpty &&
          property.ownerUserId != _currentOwnerUserId) {
        unawaited(_propertyLikesRepository.recordView(
          propertyId: propertyId,
          viewerId: _currentAnalyticsUserId,
        ));
      }
    }
    unawaited(refreshEngagement(propertyId));
  }

  /// Pulls the authoritative view + like counts from the backend into the
  /// property's market signals, so the UI shows real numbers.
  Future<void> refreshEngagement(String propertyId) async {
    if (!_propertyLikesRepository.isConfigured || propertyId.isEmpty) return;
    try {
      final counts = await Future.wait([
        _propertyLikesRepository.viewCount(propertyId),
        _propertyLikesRepository.likeCount(propertyId),
      ]);
      final views = counts[0];
      final likes = counts[1];
      final current = _signalsFor(propertyId).normalizedForToday(DateTime.now());
      _setPropertySignals(
        propertyId,
        current.copyWith(views: views, likes: likes),
      );
      notifyListeners();
    } catch (_) {/* best-effort */}
  }

  DateTime? _lastOwnedEngagementRefresh;

  /// Refreshes engagement counts for all of the current landlord's properties
  /// (for the dashboard totals). Throttled so it can be called from UI builds.
  Future<void> refreshOwnedEngagement({bool force = false}) async {
    if (!isLandlord || !_propertyLikesRepository.isConfigured) return;
    final now = DateTime.now();
    if (!force &&
        _lastOwnedEngagementRefresh != null &&
        now.difference(_lastOwnedEngagementRefresh!).inSeconds < 20) {
      return;
    }
    _lastOwnedEngagementRefresh = now;
    final owned =
        _allProperties.where(_belongsToCurrentLandlord).map((p) => p.id).toList();
    for (final id in owned) {
      await refreshEngagement(id);
    }
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
    // Latency-to-decision: card visible → swipe. Null on the first card of a
    // deck (no prior shown-time). Reset the clock for the next top card.
    // ponytail: first swipe's latency is lost; acceptable vs threading a
    // card-shown callback through the swiper widget.
    final shownAt = _topCardShownAt;
    final decisionMs =
        shownAt == null ? null : DateTime.now().difference(shownAt).inMilliseconds;
    _topCardShownAt = DateTime.now();
    if (direction == CardSwiperDirection.left) {
      _passedPropertyIds.add(property.id);
      _swipeHistory.add(_SwipeRecord(propertyId: property.id, liked: false));
      AppEvents.instance.log(UserEventType.swipeLeft, propertyId: property.id);
      _recordSwipeSignal(property, SwipeDirection.skip, dwellMs: decisionMs);
    } else if (direction == CardSwiperDirection.right ||
        direction == CardSwiperDirection.top) {
      final isNewLike = _likedPropertyIds.add(property.id);
      if (isNewLike) _recordPropertyLike(property.id);
      _swipeHistory.add(_SwipeRecord(propertyId: property.id, liked: true));
      final isSuperLike = direction == CardSwiperDirection.top;
      final eventType =
          isSuperLike ? UserEventType.superLike : UserEventType.swipeRight;
      AppEvents.instance.log(eventType, propertyId: property.id);
      _recordSwipeSignal(
        property,
        isSuperLike ? SwipeDirection.superlike : SwipeDirection.like,
        dwellMs: decisionMs,
      );

      // A tenant right-swipe registers the LIKE only — it is NOT a match. A
      // match is two-sided and is created when the other side (the landlord)
      // accepts the lead, via [handleOwnerSwipe] / [_processAutoLikes]. The
      // sole exception is the guest/demo walkthrough, where there is no real
      // landlord on the other side: there we simulate the owner accepting an
      // owned demo listing the guest super-likes (or any owned demo listing
      // when auto-like is on) so the demo can showcase the match flow. Real
      // swipes never blanket-match.
      if (_isGuestMode && _isGuestDemoProperty(property)) {
        final acceptsDemo = isSuperLike || _autoLikeEnabled;
        if (acceptsDemo) {
          _ownerAcceptedPropertyIds.add(property.id);
          _createMatch(property);
        }
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

  // ── Revealed-preference capture (the learning loop) ────────────────────────

  /// The budget the revealed signals are measured against: the tenant's stated
  /// profile budget when set, else the active max-budget filter. Used both to
  /// derive `priceToBudgetRatio` for [EventService.logSwipeOutcome] and to widen
  /// the effective budget in scoring.
  double get _signalBudget {
    final profileBudget = _tenantProfile?.budgetMax ?? 0;
    if (profileBudget >= _missingPriceThreshold) return profileBudget.toDouble();
    final filterMax = _filters.maxBudget;
    if (filterMax > 0 && filterMax < _unsetBudget) return filterMax.toDouble();
    return 0;
  }

  double _priceToBudgetRatio(RentalProperty property) {
    final budget = _signalBudget;
    if (budget <= 0 || !_hasKnownPrice(property)) return 1.0;
    return property.price / budget;
  }

  /// Emits the raw behavioral row(s) for a swipe decision AND folds the same
  /// event into the in-memory [_userSignals] aggregate (optimistic update), so
  /// the next match score already reflects this swipe. Cheap: the heavy state
  /// write is debounced via [_persist], already called on the swipe path.
  void _recordSwipeSignal(
    RentalProperty property,
    SwipeDirection direction, {
    int? dwellMs,
  }) {
    final now = DateTime.now();
    final ratio = _priceToBudgetRatio(property);
    final liked = direction != SwipeDirection.skip;

    AppEvents.instance.service.logSwipeOutcome(
      propertyId: property.id,
      direction: direction,
      priceToBudgetRatio: ratio,
      dwellMs: dwellMs,
    );
    _foldUserSignal('swipeOutcome', {
      'direction': direction.name,
      'priceToBudgetRatio': ratio,
    }, now);

    if (liked) {
      // A like reveals a preferred location and reinforces the tags the
      // property carries.
      if (property.lat != 0 || property.lon != 0) {
        AppEvents.instance.service.logLikedLocation(
          propertyId: property.id,
          lat: property.lat,
          lng: property.lon,
        );
        _foldUserSignal(
          'likedLocation',
          {'lat': property.lat, 'lng': property.lon},
          now,
        );
      }
      for (final tag in _matchableTagsOf(property)) {
        _foldUserSignal('tagLiked', {'tag': tag}, now);
      }
    } else {
      // A skip that violated one of the tenant's deal-breakers / IMPORTANT tags
      // is the strongest negative signal — record it explicitly and lower the
      // affinity for the violated tag.
      _recordDealBreakerMisses(property);
    }
    // The swipe path persists immediately after this returns, so the updated
    // aggregate is written without scheduling a second redundant write here.
  }

  /// Folds one raw event into [_userSignals] using the pure reducer. Kept tiny
  /// so it's safe to call on the hot swipe path.
  void _foldUserSignal(
    String type,
    Map<String, dynamic> event,
    DateTime at,
  ) {
    _userSignals = UserSignals.update(
      _userSignals,
      type: type,
      event: event,
      at: at,
    );
  }

  /// The persona match-keys the tenant marked IMPORTANT/CRITICAL that this
  /// property FAILS to satisfy — i.e. the deal-breakers a skip just confirmed.
  void _recordDealBreakerMisses(RentalProperty property) {
    final profile = _tenantProfile;
    if (profile == null) return;
    final now = DateTime.now();
    final criticalKeys = ProfileTagCatalog.matchKeysFor(profile.dealBreakers,
        isLandlord: false);
    final importantKeys = ProfileTagCatalog.matchKeysFor(profile.importantDetails,
        isLandlord: false);

    final context = _MatchContext(
      filters: _filters,
      now: now,
      area: selectedArea,
      featureWeights: _featureWeights,
      marketIndex: _marketIndex,
    );

    for (final key in {...criticalKeys, ...importantKeys}) {
      final met = _propertyMeetsPersonaKey(property, key, profile, context);
      if (met == false) {
        final critical = criticalKeys.contains(key);
        AppEvents.instance.service.logDealBreakerApplied(
          propertyId: property.id,
          tag: key,
          kind: critical ? DealBreakerKind.critical : DealBreakerKind.important,
        );
        _foldUserSignal('dealBreakerApplied', {'tag': key}, now);
      }
    }
  }

  /// The property's matching tags, expressed as the same affinity keys scoring
  /// uses — the feature keys present on the property that map to a persona
  /// match-key (so liking a property with parking raises 'parking' affinity).
  Iterable<String> _matchableTagsOf(RentalProperty property) {
    final keys = <String>{};
    _personaKeyToFeatureKey.forEach((personaKey, featureKey) {
      if (property.featureFlags.isEnabled(featureKey)) keys.add(personaKey);
    });
    return keys;
  }

  Future<void> ownerSwipeLeft() async {
    ownerSwiperController.swipe(CardSwiperDirection.left);
  }

  Future<void> ownerSwipeRight() async {
    ownerSwiperController.swipe(CardSwiperDirection.right);
  }

  void toggleAutoLike() {
    _autoLikeEnabled = !_autoLikeEnabled;
    if (_autoLikeEnabled) {
      _processAutoLikes();
    }
    _persist();
    notifyListeners();
  }

  void setTabIndex(int index) {
    _currentTabIndex = index;
    notifyListeners();
  }

  void _processAutoLikes() {
    final leads = ownerLeads;
    if (leads.isEmpty) return;

    for (final property in leads) {
      _ownerAcceptedPropertyIds.add(property.id);
      _createMatch(property, tenantUserId: _firstLikerOf(property.id));
    }
  }

  /// The tenant uid that should own the chat thread when the landlord accepts a
  /// lead — the first real liker, so the thread connects to that tenant.
  String? _firstLikerOf(String propertyId) {
    final likers = _incomingLikesByProperty[propertyId];
    return (likers != null && likers.isNotEmpty) ? likers.first.tenantId : null;
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
      _createMatch(property, tenantUserId: _firstLikerOf(property.id));
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

  // Reviews feature removed — always empty.
  List<AppReview> propertyReviews(String propertyId) => const [];

  double reviewAverage(List<AppReview> reviews) {
    if (reviews.isEmpty) return 0;
    final total = reviews.fold<int>(0, (sum, r) => sum + r.rating);
    return total / reviews.length;
  }

  Future<void> addPropertyReview({
    required String propertyId,
    required int rating,
    required String text,
    String matchId = '',
  }) async {
    final targetPropertyId =
        InputSanitizer.sanitizeText(propertyId, maxLength: 96);
    final sanitizedText = InputSanitizer.sanitizeText(text, maxLength: 1000);
    if (targetPropertyId.isEmpty || sanitizedText.isEmpty) return;

    final now = DateTime.now();
    final safeRating = rating.clamp(1, 5);
    final property = propertyById(targetPropertyId);
    final review = AppReview(
      id: 'property-review-${now.microsecondsSinceEpoch}',
      authorName: _tenantProfile?.name ?? 'שוכר',
      rating: safeRating,
      text: sanitizedText,
    );
    final current = _propertyReviews[targetPropertyId] ?? const [];
    _propertyReviews = {
      ..._propertyReviews,
      targetPropertyId: [
        ...current,
        review,
      ],
    };
    await _persist();
    unawaited(
      _reviewRepository.saveReview(
        ReviewRecord(
          id: review.id,
          targetType: ReviewTargetType.property,
          targetId: targetPropertyId,
          reviewerUserId: _currentAnalyticsUserId,
          reviewerRole: isLandlord ? 'landlord' : 'tenant',
          authorName: review.authorName,
          rating: safeRating,
          text: sanitizedText,
          createdAt: now,
          matchId: matchId,
          propertyId: targetPropertyId,
          revieweeUserId: property?.ownerUserId ?? '',
        ),
      ),
    );
    notifyListeners();
  }

  Future<void> addTenantReview({
    required int rating,
    required String text,
    String tenantId = '',
    String matchId = '',
    String propertyId = '',
  }) async {
    final targetTenantId = InputSanitizer.sanitizeText(tenantId, maxLength: 96);
    final resolvedTenantId = targetTenantId.isNotEmpty
        ? targetTenantId
        : InputSanitizer.sanitizeText(
            _tenantProfile?.id ?? 'tenant-$matchId',
            maxLength: 96,
          );
    final sanitizedText = InputSanitizer.sanitizeText(text, maxLength: 1000);
    if (resolvedTenantId.isEmpty || sanitizedText.isEmpty) return;

    final now = DateTime.now();
    final safeRating = rating.clamp(1, 5);
    final review = AppReview(
      id: 'tenant-review-${now.microsecondsSinceEpoch}',
      authorName: isLandlord ? (_tenantProfile?.name ?? 'בעל דירה') : 'שוכר',
      rating: safeRating,
      text: sanitizedText,
    );
    _tenantReviews = [
      ..._tenantReviews,
      review,
    ];
    await _persist();
    unawaited(
      _reviewRepository.saveReview(
        ReviewRecord(
          id: review.id,
          targetType: ReviewTargetType.tenant,
          targetId: resolvedTenantId,
          reviewerUserId: _currentAnalyticsUserId,
          reviewerRole: isLandlord ? 'landlord' : 'tenant',
          authorName: review.authorName,
          rating: safeRating,
          text: sanitizedText,
          createdAt: now,
          matchId: matchId,
          propertyId: propertyId,
          revieweeUserId: resolvedTenantId,
        ),
      ),
    );
    notifyListeners();
  }

  Future<void> refreshPropertyReviews(String propertyId) async {
    final targetPropertyId =
        InputSanitizer.sanitizeText(propertyId, maxLength: 96);
    if (!_hasAuthenticatedFirebaseUser || targetPropertyId.isEmpty) return;
    final remoteReviews = await _reviewRepository.fetchReviews(
      targetType: ReviewTargetType.property,
      targetId: targetPropertyId,
    );
    if (remoteReviews.isEmpty) return;
    _propertyReviews = {
      ..._propertyReviews,
      targetPropertyId: _mergeReviews(
        _propertyReviews[targetPropertyId] ?? const [],
        remoteReviews,
      ),
    };
    await _persist();
    notifyListeners();
  }

  Future<void> _refreshCurrentTenantReviewsAfterAuth() async {
    final targetTenantId = _tenantProfile?.id.trim() ?? '';
    if (!_hasAuthenticatedFirebaseUser || targetTenantId.isEmpty) return;
    final remoteReviews = await _reviewRepository.fetchReviews(
      targetType: ReviewTargetType.tenant,
      targetId: targetTenantId,
    );
    if (remoteReviews.isEmpty) return;
    _tenantReviews = _mergeReviews(_tenantReviews, remoteReviews);
    await _persist();
    notifyListeners();
  }

  List<AppReview> _mergeReviews(
    List<AppReview> current,
    List<AppReview> incoming,
  ) {
    final byId = <String, AppReview>{
      for (final review in current) review.id: review,
    };
    for (final review in incoming) {
      byId[review.id] = review;
    }
    return byId.values.toList(growable: false);
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

  // ── Rental contracts with end-to-end e-signatures ──────────────────────────
  List<RentalContract> get contracts => List.unmodifiable(_contracts);

  RentalContract? contractForMatch(String matchId) {
    for (final c in _contracts) {
      if (c.matchId == matchId) return c;
    }
    return null;
  }

  Future<void> loadContracts() async {
    if (!_contractRepository.isEnabled) return;
    try {
      final remote = await _contractRepository.listForUser();
      if (remote.isNotEmpty) {
        _contracts = remote;
        notifyListeners();
      }
    } catch (error) {
      if (kDebugMode) debugPrint('loadContracts: $error');
    }
  }

  /// Landlord drafts + sends a rental contract for a match.
  Future<RentalContract?> createRentalContract({
    required String matchId,
    required int monthlyRent,
    required int deposit,
    required int durationMonths,
    required DateTime startDate,
    required String terms,
  }) async {
    final match = matchById(matchId);
    final property = propertyById(match?.propertyId ?? '');
    if (match == null || property == null) return null;

    final landlordUserId = property.ownerUserId.isNotEmpty
        ? property.ownerUserId
        : _currentOwnerUserId;
    final landlordName = property.ownerName.isNotEmpty
        ? property.ownerName
        : (_tenantProfile?.name ?? 'בעל הדירה');

    final likes = incomingLikesFor(property.id);
    final tenantLike = likes.isNotEmpty ? likes.first : null;
    final tenantUserId = tenantLike?.tenantId ?? _firstLikerOf(property.id) ?? '';
    final tenantName = tenantLike?.tenantName ?? 'השוכר';

    final now = DateTime.now().toUtc();
    var contract = RentalContract(
      id: 'contract-${property.id}-${now.microsecondsSinceEpoch}',
      matchId: matchId,
      propertyId: property.id,
      propertyTitle: property.address,
      landlordUserId: landlordUserId,
      landlordName: landlordName,
      tenantUserId: tenantUserId,
      tenantName: tenantName,
      monthlyRent: monthlyRent,
      deposit: deposit,
      durationMonths: durationMonths,
      startDate: startDate,
      additionalTerms: terms,
      status: ContractStatus.sent,
      createdAt: now,
      updatedAt: now,
    );

    try {
      final saved = await _contractRepository.create(contract);
      if (saved != null) contract = saved;
    } catch (error) {
      if (kDebugMode) debugPrint('createRentalContract: $error');
    }

    _contracts = [contract, ..._contracts.where((c) => c.id != contract.id)];

    final index = _matches.indexWhere((m) => m.id == matchId);
    if (index != -1) {
      _replaceMatch(
        index,
        _matches[index].copyWith(
          contractSent: true,
          messages: [
            ..._matches[index].messages,
            ChatMessage(
              id: 'contract-${now.microsecondsSinceEpoch}',
              sender: landlordName,
              text: 'שלחתי חוזה שכירות דיגיטלי לחתימה: '
                  '₪$monthlyRent לחודש, ל-$durationMonths חודשים.',
              createdAt: DateTime.now(),
            ),
          ],
        ),
      );
    }
    await _persist();
    notifyListeners();
    return contract;
  }

  /// Signs [contract] with this device's Ed25519 key (private key never leaves
  /// the device) plus an optional handwritten signature image.
  Future<RentalContract?> signRentalContract(
    RentalContract contract, {
    required bool asOwner,
    Uint8List? signatureImage,
  }) async {
    final role = asOwner ? 'landlord' : 'tenant';
    final signerName = asOwner
        ? (contract.landlordName.isNotEmpty
            ? contract.landlordName
            : 'בעל הדירה')
        : (_tenantProfile?.name ?? contract.tenantName);

    final hash = contract.contentHash;
    final publicKey = await _signatureService.publicKeyBase64();
    final signature = await _signatureService.sign(hash);

    var imageUrl = '';
    if (signatureImage != null) {
      imageUrl = await _uploadSignatureImage(contract.id, role, signatureImage);
    }

    final sig = ContractSignature(
      role: role,
      signerUserId: _currentOwnerUserId,
      signerName: signerName,
      publicKey: publicKey,
      signature: signature,
      signedHash: hash,
      signatureImageUrl: imageUrl,
      signedAt: DateTime.now().toUtc(),
    );

    var updated = contract.copyWith(
      landlordSignature: asOwner ? sig : contract.landlordSignature,
      tenantSignature: asOwner ? contract.tenantSignature : sig,
      updatedAt: DateTime.now().toUtc(),
    );
    if (updated.isFullySigned) {
      updated = updated.copyWith(status: ContractStatus.signed);
    }

    try {
      final saved = await _contractRepository.sign(contract.id, sig);
      if (saved != null) updated = saved;
    } catch (error) {
      if (kDebugMode) debugPrint('signRentalContract: $error');
    }

    _contracts = [updated, ..._contracts.where((c) => c.id != updated.id)];

    final index = _matches.indexWhere((m) => m.id == contract.matchId);
    if (index != -1) {
      _replaceMatch(
        index,
        _matches[index].copyWith(
          ownerSigned: asOwner ? true : _matches[index].ownerSigned,
          tenantSigned: asOwner ? _matches[index].tenantSigned : true,
          messages: [
            ..._matches[index].messages,
            ChatMessage(
              id: 'signature-${DateTime.now().microsecondsSinceEpoch}',
              sender: signerName,
              text: asOwner
                  ? 'חתמתי על החוזה כבעל הדירה. ✍️'
                  : 'חתמתי על החוזה כשוכר/ת. ✍️',
              createdAt: DateTime.now(),
            ),
          ],
        ),
      );
    }
    await _persist();
    notifyListeners();
    return updated;
  }

  /// Cryptographically verifies a party's signature against the contract's
  /// current terms. Returns false if the terms were altered after signing.
  Future<bool> verifyContractSignature(
    RentalContract contract,
    ContractSignature sig,
  ) {
    return _signatureService.verify(
      contentHashBase64: contract.contentHash,
      signatureBase64: sig.signature,
      publicKeyBase64: sig.publicKey,
    );
  }

  Future<String> _uploadSignatureImage(
    String contractId,
    String role,
    Uint8List bytes,
  ) async {
    try {
      final file = File('${Directory.systemTemp.path}/sig_${contractId}_$role.png');
      await file.writeAsBytes(bytes);
      final url = await AwsApiClient.instance.uploadFile(
        file.path,
        contentType: 'image/png',
        folder: 'contract_signatures',
      );
      return url ?? '';
    } catch (error) {
      if (kDebugMode) debugPrint('_uploadSignatureImage: $error');
      return '';
    }
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
    final visibleCount = matches.length;
    if (_lastSeenMatchCount >= visibleCount) return;
    _lastSeenMatchCount = visibleCount;
    notifyListeners();
  }

  Future<void> resetPassed() async {
    _passedPropertyIds.clear();
    _swipeHistory.removeWhere((r) => !r.liked);
    _invalidateFilterCache();
    await _persist();
    notifyListeners();
  }

  TenantProfile? getCachedProfile(String userId) {
    if (userId.trim().isEmpty) return null;

    final cached = _cachedProfiles[userId];
    if (cached != null) return cached;

    if (_loadingProfileIds.contains(userId)) return null;

    _loadingProfileIds.add(userId);
    _userRepository.getProfile(userId).then((profile) {
      _loadingProfileIds.remove(userId);
      if (profile != null) {
        _cachedProfiles[userId] = profile;
        notifyListeners();
      }
    }).catchError((_) {
      _loadingProfileIds.remove(userId);
    });

    return null;
  }

  int matchScore(RentalProperty p) {
    if (_searchAreas.isEmpty) return 0;
    return _matchScoreFor(p, _filters, DateTime.now(), selectedArea);
  }

  /// Whether there is a genuine basis for showing a tenant→property match
  /// percentage. The raw [matchScore] awards every structural weight in full
  /// when no preferences are set, so an empty/guest persona scores ~100 — a
  /// misleading "perfect match". We therefore only surface the match badge
  /// when the user has actually expressed what they want, via either real
  /// search filters or real profile preferences (budget / rooms / important
  /// details). Guests (demo personas) never qualify.
  bool get hasMatchPersona {
    if (_isGuestMode) return false;
    if (activeFilterCount > 0) return true;
    final profile = _tenantProfile;
    if (profile == null) return false;
    return profile.importantDetails.isNotEmpty ||
        profile.dealBreakers.isNotEmpty ||
        profile.budgetMax > 0 ||
        profile.desiredRooms > 0;
  }

  /// The match percentage to display on a card, or `null` when there is no
  /// honest basis for one (see [hasMatchPersona]). The UI hides the badge on
  /// `null` rather than show a fabricated number.
  int? displayMatchScore(RentalProperty p) {
    if (!hasMatchPersona) return null;
    final score = matchScore(p);
    return score > 0 ? score : null;
  }

  static const MatchEngine _matchEngine = MatchEngine();

  /// Full two-sided, explainable match assessment for a property: combines the
  /// tuned tenant→property fit ([matchScore]) with the landlord→tenant fit and
  /// surfaces the reasons + tier. Used for the "why this match" UI. Cached per
  /// property until the catalog/filter/profile revision changes.
  MatchOutcome matchOutcome(RentalProperty p) {
    final cacheKey = '${p.id}|$_filterRevision|$_catalogRevision';
    final cached = _matchOutcomeCache[cacheKey];
    if (cached != null) return cached;

    final tenantProfile = _tenantProfile;
    final tenant = TenantSignals(
      budgetMax: tenantProfile?.budgetMax ?? _filters.maxBudget,
      desiredRooms: tenantProfile?.desiredRooms ?? 0,
      tags: tenantProfile?.importantDetails ?? const [],
      dealBreakers: tenantProfile?.dealBreakers ?? const [],
      searchCity: _filters.city,
    );

    final ownerId = p.ownerUserId.isNotEmpty
        ? p.ownerUserId
        : (_isGuestDemoProperty(p) ? 'guest_landlord' : '');
    final landlordProfile = ownerId.isEmpty ? null : getCachedProfile(ownerId);
    final landlord = landlordProfile == null
        ? LandlordSignals.unknown
        : LandlordSignals(
            tags: landlordProfile.importantDetails,
            dealBreakers: landlordProfile.dealBreakers,
          );

    final property = PropertySignals(
      price: p.price,
      rooms: p.rooms,
      sizeM2: p.sizeM2,
      city: p.city,
      features: p.features,
      verified: p.isVerifiedListing,
      hasReadyTour: p.hasReadyVirtualTour,
      photoCount: p.media.length,
    );

    final outcome = _matchEngine.evaluate(
      tenant: tenant,
      landlord: landlord,
      property: property,
      propertyFitScore: matchScore(p),
    );
    if (_matchOutcomeCache.length > 400) _matchOutcomeCache.clear();
    _matchOutcomeCache[cacheKey] = outcome;
    return outcome;
  }

  final Map<String, MatchOutcome> _matchOutcomeCache = {};

  /// Server-side ranked tenant leads (the two-sided model applied across the
  /// landlord's interested tenants). Scales without loading every tenant's
  /// profile on-device. Returns [] when offline/unconfigured.
  Future<List<RankedLead>> fetchRankedLeads() async {
    if (!AwsApiClient.instance.isConfigured) {
      return const [];
    }
    try {
      final res = await AwsApiClient.instance.post('/match/leads', const {});
      final rows = res['leads'];
      if (rows is! List) return const [];
      return rows
          .whereType<Map>()
          .map((r) => RankedLead.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    } catch (error) {
      if (kDebugMode) debugPrint('fetchRankedLeads: $error');
      return const [];
    }
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

  /// Returns [filters] with the tenant profile's stated budget / rooms folded
  /// in for the dimensions the user left at their default. A profile preference
  /// only fills a gap — an explicit filter the user set always wins, so opening
  /// the filter sheet still overrides the profile. Returns [filters] unchanged
  /// when there is no profile or nothing to inherit (the common, fast path).
  SearchFilters _effectiveScoringFilters(SearchFilters filters) {
    final profile = _tenantProfile;
    if (profile == null) return filters;

    final type = filters.transactionType;
    final hasExplicitMaxBudget =
        filters.maxBudget < _defaultMaxBudgetFor(type);
    final hasExplicitMinRooms = filters.minRooms > 0;

    final inheritBudget =
        !hasExplicitMaxBudget && profile.budgetMax >= _missingPriceThreshold;
    final inheritRooms = !hasExplicitMinRooms && profile.desiredRooms > 0;
    if (!inheritBudget && !inheritRooms) return filters;

    final maxBudgetCeiling = _defaultMaxBudgetFor(type);
    return filters.copyWith(
      maxBudget: inheritBudget
          ? profile.budgetMax.clamp(filters.minBudget, maxBudgetCeiling)
          : filters.maxBudget,
      // Use the profile's desired rooms as a soft floor; the existing rooms-fit
      // curve rewards being at/above it and gently penalises being under.
      minRooms: inheritRooms
          ? _clampDouble(profile.desiredRooms, 0, _unsetMaxRooms)
          : filters.minRooms,
    );
  }

  int _matchScoreForContext(RentalProperty p, _MatchContext context) {
    // Fold the tenant profile's stated budget / rooms into the scoring filters
    // when the user hasn't set those filters explicitly. Without this, a tenant
    // whose PROFILE says "max ₪4,000 / 5 rooms" but who never opened the filter
    // sheet would still see a property at ₪6,000 / 3 rooms scored as a full-fit
    // — the displayed % would contradict their own profile. The gates below
    // (required features / types / conditions / sources) keep using the user's
    // real filters, so only the budget / rooms soft scores inherit the profile.
    final filters = _effectiveScoringFilters(context.filters);
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

    double tagCompatibilityScore = 0.0;
    final tenantProfile = _tenantProfile;
    if (tenantProfile != null) {
      final ownerId = p.ownerUserId.isNotEmpty
          ? p.ownerUserId
          : (_isGuestDemoProperty(p) ? 'guest_landlord' : '');
      final landlordProfile = getCachedProfile(ownerId);
      if (landlordProfile == null) {
        // No landlord profile to cross-reference, so honour the tenant's own
        // "חשוב"/"קריטי" choices against the property's own attributes. This is
        // what makes the displayed % react to the persona for the common case
        // (most listings have no landlord profile loaded).
        tagCompatibilityScore += _personaFitScore(p, tenantProfile, context);
      } else {
        // Catalog-driven compatibility: a renter preference and an owner offer
        // that resolve to the same `matchKey` (e.g. wants parking ↔ has
        // parking) reward the pair. See [ProfileTagCatalog].
        final tenantKeys = ProfileTagCatalog.matchKeysFor(
            tenantProfile.importantDetails,
            isLandlord: false);
        final landlordKeys = ProfileTagCatalog.matchKeysFor(
            landlordProfile.importantDetails,
            isLandlord: true);

        final sharedKeys = tenantKeys.intersection(landlordKeys);
        tagCompatibilityScore += sharedKeys.length * 5.0;

        // Deal-breakers: a non-negotiable preference the other side can't meet
        // sinks the match (large negative, floored at 0 after clamping) rather
        // than merely forfeiting the matching bonus.
        for (final key in ProfileTagCatalog.matchKeysFor(
            tenantProfile.dealBreakers,
            isLandlord: false)) {
          if (!landlordKeys.contains(key)) tagCompatibilityScore -= 40.0;
        }
        for (final key in ProfileTagCatalog.matchKeysFor(
            landlordProfile.dealBreakers,
            isLandlord: true)) {
          if (!tenantKeys.contains(key)) tagCompatibilityScore -= 40.0;
        }

        // Completeness bonus when both sides invested in their profile.
        if (tenantProfile.importantDetails.length >= 3 &&
            landlordProfile.importantDetails.length >= 3) {
          tagCompatibilityScore += 5.0;
        }
      }
    }

    final structural = _budgetFitScore(p, filters) +
        _marketValueScore(p, context) +
        _locationScore(p, context) +
        _spaceFitScore(p, filters) +
        _moveInScore(p, filters, context.now) +
        _featureFitScore(p, context) +
        _listingConfidenceScore(p) +
        _businessReadinessScore(p, context);

    // The raw structural weights sum to ~108 at a perfect fit, so they alone
    // clamp to 100 for almost any decent listing — which made the displayed
    // "% התאמה" saturate and swallowed every persona/tag boost (the boost was
    // applied above the ceiling and never showed). We compress the structural
    // total into a sub-100 band so that:
    //   • a perfect structural fit lands at [_structuralCeiling] (≈88), leaving
    //     real headroom for IMPORTANT/shared-tag boosts to be visible, and
    //   • the displayed number genuinely moves with how well the property fits
    //     the user's budget / rooms / location / size / features.
    // Persona deltas (tag compatibility, IMPORTANT boosts, CRITICAL penalties)
    // are added AFTER compression so they shift the visible score rather than
    // being absorbed by the clamp.
    final compressed = _compressStructural(structural);
    final score = compressed + tagCompatibilityScore + _learnedScoreDelta(p);

    return _clampDouble(score, 0, 100).round();
  }

  /// The bounded personalisation layer: small ± nudges folded out of the user's
  /// own revealed behaviour ([_userSignals]). Added AFTER structural compression
  /// — exactly like the persona deltas — so it shifts the visible score honestly
  /// instead of being absorbed by the clamp, and is deliberately small so it can
  /// never re-saturate the score back to 100.
  ///
  ///  • tagAffinity → ± up to [_learnedTagWeight] per matching feature, with the
  ///    total clamped to ±[_maxLearnedTagDelta]. A feature the user keeps liking
  ///    nudges similar listings up; one they keep skipping nudges them down.
  ///  • preferredAreas → up to +[_learnedAreaWeight] when the property sits near
  ///    a centroid the user has revealed a preference for (no penalty — absence
  ///    of a known area is simply neutral).
  double _learnedScoreDelta(RentalProperty property) {
    var delta = 0.0;

    final affinities = _userSignals.tagAffinity;
    if (affinities.isNotEmpty) {
      var tagDelta = 0.0;
      for (final personaKey in _matchableTagsOf(property)) {
        final affinity = affinities[personaKey];
        if (affinity != null) {
          tagDelta += affinity.clamp(-1.0, 1.0) * _learnedTagWeight;
        }
      }
      delta += tagDelta.clamp(-_maxLearnedTagDelta, _maxLearnedTagDelta);
    }

    delta += _learnedAreaAffinity(property);
    return delta;
  }

  /// Small positive bonus when the property is near a liked-area centroid, scaled
  /// both by proximity and by how many likes back that centroid (more-revealed
  /// areas count for more), capped at [_learnedAreaWeight].
  double _learnedAreaAffinity(RentalProperty property) {
    final areas = _userSignals.preferredAreas;
    if (areas.isEmpty) return 0.0;
    if (property.lat == 0 && property.lon == 0) return 0.0;

    var best = 0.0;
    for (final area in areas) {
      final km =
          _haversineKm(area.lat, area.lng, property.lat, property.lon);
      if (km >= _learnedAreaRadiusKm) continue;
      final proximity = 1.0 - (km / _learnedAreaRadiusKm); // 0..1
      // Confidence saturates by ~3 backing likes so a single like doesn't max it.
      final confidence = (area.weight / 3.0).clamp(0.0, 1.0);
      best = math.max(best, proximity * confidence);
    }
    return best * _learnedAreaWeight;
  }

  static double _haversineKm(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLng = (lng2 - lng1) * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  // The theoretical maximum of the structural weights, used to normalise the
  // raw sum before mapping it into the visible [0, _structuralCeiling] band.
  static const double _maxStructuralScore = _budgetWeight +
      _marketValueWeight +
      _locationWeight +
      _roomsWeight +
      _sizeWeight +
      _floorWeight +
      _timingWeight +
      _requiredFeatureWeight +
      _preferredFeatureWeight +
      _preferredPropertyTypeWeight +
      _preferredConditionWeight +
      _preferredListingSourceWeight +
      _listingConfidenceWeight +
      _businessReadinessWeight;

  // A perfect structural fit maps to this score, reserving the remaining
  // headroom up to 100 for honest persona/tag boosts.
  static const double _structuralCeiling = 88;

  /// Maps the raw structural sum (0.._maxStructuralScore) into 0.._structuralCeiling
  /// so the base never saturates at 100 on its own and persona boosts stay
  /// visible. Monotonic: a better structural fit always yields a higher result.
  double _compressStructural(double structural) {
    final ratio = _clampDouble(structural / _maxStructuralScore, 0, 1);
    return ratio * _structuralCeiling;
  }

  /// Scores the property against the tenant's own persona choices when there is
  /// no landlord profile to cross-reference (the common case). IMPORTANT details
  /// ("חשוב") that the property satisfies add a meaningful boost; CRITICAL
  /// deal-breakers ("קריטי") that the property FAILS apply a heavy penalty, so a
  /// property missing a non-negotiable can never display as a strong match.
  ///
  /// Only persona keys that map to a concrete property attribute (a feature, or
  /// budget/rooms/city) are evaluated here — lifestyle/landlord-policy keys are
  /// left to the two-sided path, since the property alone can't answer them.
  double _personaFitScore(
    RentalProperty property,
    TenantProfile profile,
    _MatchContext context,
  ) {
    final importantKeys = ProfileTagCatalog.matchKeysFor(
        profile.importantDetails,
        isLandlord: false);
    final criticalKeys = ProfileTagCatalog.matchKeysFor(profile.dealBreakers,
        isLandlord: false);
    if (importantKeys.isEmpty && criticalKeys.isEmpty) return 0;

    double delta = 0;

    // CRITICAL gates first — a failed deal-breaker is a hard penalty. A key only
    // counts as "evaluable" (and therefore as a possible miss) when the property
    // exposes the matching attribute; we never penalise for a key we can't read.
    for (final key in criticalKeys) {
      final met = _propertyMeetsPersonaKey(property, key, profile, context);
      if (met == false) {
        delta -= _criticalPersonaPenalty;
      }
    }

    // IMPORTANT details — a satisfied "חשוב" boosts; an UNMET one applies a
    // softer penalty. Penalising the miss (not just rewarding the hit) keeps the
    // ordering honest even when the base score is already near the 100 ceiling:
    // a property lacking what the tenant cares about always scores below one
    // that has it.
    for (final key in importantKeys) {
      if (criticalKeys.contains(key)) continue; // already weighted as critical
      final met = _propertyMeetsPersonaKey(property, key, profile, context);
      if (met == true) {
        delta += _importantPersonaBoost;
      } else if (met == false) {
        delta -= _importantPersonaBoost;
      }
    }

    return delta;
  }

  /// Whether [property] satisfies a persona match-[key]. Returns `null` when the
  /// property can't answer the key (so neither boost nor penalty applies).
  bool? _propertyMeetsPersonaKey(
    RentalProperty property,
    String key,
    TenantProfile profile,
    _MatchContext context,
  ) {
    final featureKey = _personaKeyToFeatureKey[key];
    if (featureKey != null) {
      return property.featureFlags.isEnabled(featureKey);
    }
    // A handful of persona keys map onto structured attributes rather than
    // feature flags.
    switch (key) {
      case 'immediate':
        final entry = property.entryDateValue;
        if (entry == null) return null;
        return !entry.isAfter(context.now.add(const Duration(days: 30)));
      default:
        return null; // lifestyle/policy key — not answerable from the property
    }
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

    // Revealed budget tolerance: a user who demonstrably keeps liking listings
    // over their stated cap shouldn't be harshly penalised for being just over.
    // We widen ONLY the ceiling the overage is measured against (clamped to
    // +20%), so listings the user has shown they'll consider stop reading as a
    // poor budget fit. This never makes an over-budget listing look on-budget —
    // a strongly over-budget listing still decays — it just softens the cliff at
    // the stated cap up to the revealed tolerance.
    final tolerance =
        _userSignals.revealedBudgetTolerance.clamp(1.0, _maxLearnedBudgetWiden);
    final effectiveMax = filters.maxBudget * tolerance;

    final price = property.price.toDouble();
    if ((!hasMin || price >= filters.minBudget) &&
        (!hasMax || price <= effectiveMax)) {
      return _budgetWeight;
    }

    if (hasMin && price < filters.minBudget) {
      final gap = (filters.minBudget - price) / filters.minBudget;
      return _budgetWeight * _expDecay(gap / 0.3, 1.2);
    }

    final overage = (price - effectiveMax) / effectiveMax;
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
          id: isOwner ? 'tenant-local' : 'tenant-test',
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
              ? const ['ניסיון בניהול נכסים', 'חוזה מסודר', 'תגובה מהירה', 'מאפשר בעלי חיים', 'מתאים ללא מעשנים']
              : const [
                  'אישור הכנסה מוכן',
                  'שוכרת כבר 5 שנים רצוף',
                  'זמינה לסיור גם בערב',
                  'מחפשת חוזה לשנה לפחות',
                  'ללא חיות מחמד',
                  'ללא עישון',
                ],
        );

    // Seed cached profiles for scoring
    final mockLandlord = TenantProfile(
      id: 'guest_landlord',
      name: 'יואב כהן',
      bio: 'בעל נכסים בתל אביב והסביבה. מחפש שוכרים אמינים לטווח ארוך. מגיב תוך 24 שעות ומאמין בתקשורת פתוחה.',
      photoUrls: const [],
      budgetMax: 0,
      desiredRooms: 0,
      moveInWindow: '',
      importantDetails: const [
        'ניסיון בניהול נכסים',
        'חוזה מסודר',
        'תגובה מהירה',
        'מאפשר בעלי חיים',
        'מתאים ללא מעשנים',
      ],
    );
    _cachedProfiles['guest_landlord'] = mockLandlord;

    final mockSeeker = TenantProfile(
      id: 'tenant-test',
      name: 'נועה לוי',
      bio: 'מחפשת דירת 2-3 חדרים בצפון תל אביב או רמת גן. כבר כמה שבועות פעילה באפליקציה, עם תגובות מהירות, מסמכים מוכנים והעדפה לבניין מטופח.',
      photoUrls: const [
        'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&w=900&q=80',
        'https://images.unsplash.com/photo-1517841905240-472988babdf9?auto=format&fit=crop&w=900&q=80',
      ],
      budgetMax: 11200,
      desiredRooms: 2.5,
      moveInWindow: 'כניסה תוך 30 יום',
      importantDetails: const [
        'אישור הכנסה מוכן',
        'שוכרת כבר 5 שנים רצוף',
        'זמינה לסיור גם בערב',
        'מחפשת חוזה לשנה לפחות',
        'ללא חיות מחמד',
        'ללא עישון',
      ],
    );
    _cachedProfiles['tenant-test'] = mockSeeker;

    final propertyPool = _baseProperties.take(6).toList();
    if (propertyPool.length < 4) {
      _seedInitialState();
      _isGuestMode = true;
      _userRole = role;
      _invalidateFilterCache();
      return;
    }

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
        createdAt: DateTime.now().subtract(const Duration(hours: 4)),
        url: '',
        ownerUserId: _guestLandlordOwnerId,
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
        createdAt: DateTime.now().subtract(const Duration(hours: 12)),
        url: '',
        ownerUserId: _guestLandlordOwnerId,
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
        createdAt: DateTime.now().subtract(const Duration(days: 1)),
        url: '',
        ownerUserId: _guestLandlordOwnerId,
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
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        url: '',
        ownerUserId: _guestLandlordOwnerId,
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
      'demo-prop-4',
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
    _autoLikeEnabled = storedState['autoLikeEnabled'] as bool? ?? false;
    _hasActiveSession =
        storedState['hasActiveSession'] as bool? ?? _isGuestMode;
    _roleExplicitlyChosen =
        storedState['roleExplicitlyChosen'] as bool? ?? false;
    _brokerBranding =
        BrokerBrandingConfig.fromJson(storedState['brokerBranding']);

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
    final userSignalsJson = storedState['userSignals'];
    _userSignals = userSignalsJson is Map
        ? UserSignals.fromJson(Map<String, dynamic>.from(userSignalsJson))
        : const UserSignals();
    // Restore the accumulated persona; a higher stored version never regresses.
    final personaJson = storedState['personaProfile'];
    if (personaJson is Map) {
      final restored =
          PersonaProfile.fromJson(Map<String, dynamic>.from(personaJson));
      if (restored.version >= _persona.version) _persona = restored;
    }
    _pendingMatchPropertyId = null;
    _invalidateCatalogCache();
  }

  void _createMatch(RentalProperty property, {String? tenantUserId}) {
    // The chat thread is keyed by the TENANT's uid so the landlord and that
    // specific tenant share one private thread (a property can have several
    // interested tenants, each in their own thread).
    final threadUser = (tenantUserId != null && tenantUserId.trim().isNotEmpty)
        ? tenantUserId.trim()
        : _currentOwnerUserId;
    final matchId = 'match-${property.id}~$threadUser';
    if (_matches.any((m) => m.id == matchId)) return;

    // matchId embeds the current user's id so each user gets a private thread
    // per property (the backend `messages` rows are keyed by this id). Without
    // the suffix, two different users interested in the same property would
    // share — and could read — one another's conversation. The server derives
    // membership from this format: match-<propertyId>~<uid>. The '~' delimiter
    // is safe: neither sanitized property ids nor Firebase uids contain it.
    _matches = [
      ..._matches,
      RentalMatch(
        id: matchId,
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
    // SYNC the match to the backend so the TENANT's app learns about it (matches
    // were local-only → the tenant never saw the chat). Fire-and-forget.
    _syncMatchToBackend(
        matchId: matchId, propertyId: property.id, tenantUid: threadUser);
  }

  // Landlord → backend: persist a mutual match so the tenant can fetch it and the
  // server pushes them "you have a match". Fail-soft (the local match still holds).
  Future<void> _syncMatchToBackend({
    required String matchId,
    required String propertyId,
    required String tenantUid,
  }) async {
    final landlordUid = _firebaseAuthOrNull?.currentUser?.uid;
    if (landlordUid == null ||
        landlordUid.isEmpty ||
        tenantUid.isEmpty ||
        tenantUid == landlordUid) {
      return;
    }
    try {
      await AwsApiClient.instance.post('/matches', {
        'id': matchId,
        'propertyId': propertyId,
        'tenantUid': tenantUid,
        'landlordUid': landlordUid,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {/* fail-soft */}
  }

  // Tenant → backend: fetch matches created by landlords who accepted this user, so
  // the chat appears in their conversations even though the match was made on
  // another device. Merges any not already present locally.
  Future<void> _loadMatchesFromBackend() async {
    final uid = _firebaseAuthOrNull?.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    try {
      final resp =
          await AwsApiClient.instance.get('/matches', query: {'tenantUid': uid});
      final items = resp['items'];
      if (items is! List) return;
      var added = false;
      for (final it in items) {
        if (it is! Map) continue;
        final matchId = (it['id'] ?? '').toString();
        final propertyId = (it['propertyId'] ?? '').toString();
        if (matchId.isEmpty || propertyId.isEmpty) continue;
        if (_matches.any((m) => m.id == matchId)) continue;
        _matches = [
          ..._matches,
          RentalMatch(
            id: matchId,
            propertyId: propertyId,
            createdAt: DateTime.tryParse((it['createdAt'] ?? '').toString()) ??
                DateTime.now(),
            contractSent: false,
            ownerSigned: false,
            tenantSigned: false,
            messages: const [],
          ),
        ];
        added = true;
      }
      if (added) {
        await _persist();
        notifyListeners();
      }
    } catch (_) {/* fail-soft */}
  }

  /// A tenant with no mutual like asks to message the owner. Creates (or appends
  /// to) a private thread flagged as a request → it shows under "מבקשים לשלוח
  /// הודעה" for the owner until they reply.
  Future<void> requestToMessage(RentalProperty property,
      {String note = ''}) async {
    final matchId = 'match-${property.id}~$_currentOwnerUserId';
    final now = DateTime.now();
    final myName = _tenantProfile?.name ?? 'מתעניין/ת';
    final text = note.trim().isEmpty
        ? 'שלום, אשמח לשמוע עוד פרטים על הדירה 🙂'
        : note.trim();
    final msg = ChatMessage(
      id: 'req-${property.id}-${now.microsecondsSinceEpoch}',
      sender: myName,
      text: text,
      createdAt: now,
    );
    final idx = _matches.indexWhere((m) => m.id == matchId);
    if (idx >= 0) {
      final m = _matches[idx];
      final updated = [..._matches];
      updated[idx] = m.copyWith(messages: [...m.messages, msg]);
      _matches = updated;
    } else {
      _matches = [
        ..._matches,
        RentalMatch(
          id: matchId,
          propertyId: property.id,
          createdAt: now,
          contractSent: false,
          ownerSigned: false,
          tenantSigned: false,
          isRequest: true,
          messages: [msg],
        ),
      ];
    }
    await _persist();
    notifyListeners();
  }

  /// Whether the current user already has a thread/request for this property.
  bool hasThreadForProperty(String propertyId) =>
      _matches.any((m) => m.id == 'match-$propertyId~$_currentOwnerUserId');

  /// One-sided "request to message" threads, for the dedicated messages section.
  List<RentalMatch> get messageRequests =>
      matches.where((m) => m.isRequest).toList();

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
      'roleExplicitlyChosen': _roleExplicitlyChosen,
      'brokerBranding': _brokerBranding.toJson(),
      'savedPropertyIds': _savedPropertyIds.toList(),
      'blockedOwnerNames': _blockedOwnerNames.toList(),
      'reportedPropertyIds': _reportedPropertyIds.toList(),
      'propertySignalOverrides': _propertySignalOverrides.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
      'lastSeenMatchCount': _lastSeenMatchCount,
      'autoLikeEnabled': _autoLikeEnabled,
      'userSignals': _userSignals.toJson(),
      'personaProfile': _persona.toJson(),
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
