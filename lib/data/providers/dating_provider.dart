import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:dating_app/core/chat/slot_message.dart';
import 'package:dating_app/core/security/input_sanitizer.dart';
import 'package:dating_app/core/security/rate_limiter.dart'
    show RateLimiter, WriteDebouncer;
import 'package:dating_app/core/services/notification_service.dart';
import 'package:dating_app/data/models/availability_slot.dart';
import 'package:dating_app/data/repositories/availability_repository.dart';
import 'package:dating_app/core/services/cache_service.dart';
import 'package:dating_app/core/services/event_service.dart';
import 'package:dating_app/core/services/gamification_service.dart';
import 'package:dating_app/core/matching/match_engine.dart';
import 'package:dating_app/core/matching/match_models.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/core/search/engine/preference_model.dart'
    show OnlineLogisticLearner;
import 'package:dating_app/core/search/cohort_model.dart';
import 'package:dating_app/core/search/nearby_relevance.dart'
    show nearbyKindToDimension;
import 'package:dating_app/core/services/tenant_consent_service.dart';
import 'package:dating_app/data/models/tenant_data_consent.dart';
import 'package:dating_app/core/search/smart_search.dart' show SearchQuery, ScoredProperty;
import 'package:dating_app/core/matching/ranked_lead.dart';
import 'package:dating_app/core/services/kiri_3d_service.dart';
import 'package:dating_app/core/services/local_storage.dart';
import 'package:dating_app/core/services/pending_scan_store.dart';
import 'package:dating_app/core/services/property_3d_scan_service.dart';
import 'package:dating_app/core/services/rental_data_service.dart';
import 'package:dating_app/data/models/broker_design_models.dart';
import 'package:dating_app/data/models/panorama_tour.dart';
import 'package:dating_app/data/models/profile_tags.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/models/subscription.dart';
import 'package:dating_app/data/models/scanned_room.dart';
import 'package:dating_app/data/models/user_signals.dart';
import 'package:dating_app/data/models/persona_profile.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/core/services/appwrite_client.dart' show ID;
import 'package:dating_app/core/services/interaction_service.dart';
import 'package:dating_app/core/services/signature_service.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/data/models/rental_contract.dart';
import 'package:dating_app/data/repositories/broker_cloud_sync.dart';
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
  void rebuildTheme() => notifyListeners();

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
  // App display language — 'he' (default), 'en', 'ar', 'fr', 'es'. Drives
  // MaterialApp.locale + the app-wide RTL/LTR Directionality in main.dart.
  String _languageCode = 'he';
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
  // Last-known landlord subscription snapshot (paywall gate + billing screen).
  // Persisted with the rest of the state so the publish gate keeps working
  // offline; refreshed from the backend when a landlord session binds.
  Subscription? _subscription;
  TenantProfile? _tenantProfile;
  final Map<String, TenantProfile> _cachedProfiles = {};
  final Set<String> _loadingProfileIds = {};
  SearchFilters _filters = _defaultFilters;
  List<RentalProperty> _baseProperties = const [];
  List<RentalProperty> _customProperties = [];
  List<SearchArea> _searchAreas = const [];
  List<AppReview> _tenantReviews = const [];
  Map<String, List<AppReview>> _propertyReviews = <String, List<AppReview>>{};
  // ── FTRL online personalization (closed loop) ──────────────────────────────
  // A per-user FTRL learner that learns P(like|features) from real swipes and
  // is blended into ranking (confidence-gated, so it's inert until it has data).
  // Persisted with the rest of the local state so it accumulates across sessions.
  OnlineLogisticLearner _learner = OnlineLogisticLearner();
  // propertyId → the learner feature vector of a SHOWN listing, stashed at render
  // by the ranker (learnerFeatureSink) so a swipe can feed the learner in O(1).
  final Map<String, Map<String, double>> _pfvCache = {};

  // The searchId of the most recent backend search that surfaced these cards.
  // PropertySearchRepository is screen-local (each search screen owns its own
  // instance + _lastSearchId), so the swipe/detail/contact handlers here cannot
  // reach it directly — the search screen pushes it in via [setLastSearchId].
  // Null-guarded everywhere: when unset (deck browsed without a prior search),
  // outcome POSTs are simply skipped.
  String? _lastSearchId;
  String? get lastSearchId => _lastSearchId;

  /// Records the searchId minted by the last backend search so subsequent
  /// outcomes (swipe/click/contact) on the surfaced cards can be labelled.
  /// Ignores empty/null so a non-backend fallback never clears a real id.
  void setLastSearchId(String? searchId) {
    if (searchId != null && searchId.isNotEmpty) _lastSearchId = searchId;
  }

  // ── Phase-2: keep the server-side USER EMBEDDING fresh ──────────────────────
  // Post the ids of listings the tenant liked so the server pools their
  // embeddings into a user vector (drives personalised semantic ranking).
  // Debounced: only every few new likes, fail-soft, never blocks the UI.
  int _lastUserEmbLikeCount = 0;

  void _maybeRefreshUserEmbedding({bool force = false}) {
    final n = _likedPropertyIds.length;
    if (n < 3 || !AwsApiClient.instance.isConfigured) return;
    if (!force && n - _lastUserEmbLikeCount < 3) return; // every ~3 new likes
    _lastUserEmbLikeCount = n;
    unawaited(
      AwsApiClient.instance.post('/user/embedding', {
        'liked': _likedPropertyIds.toList(),
      }).catchError((_) => <String, dynamic>{}),
    );
  }

  // Phase-1: the DISCOVER swipe deck is ranked on-device and never went through
  // the server /search/log path, so its swipes produced NO training rows. But
  // each card carries the server-canonical `rankFeatures`, so a swipe there IS a
  // valid (features, label) pair. We mint one stable searchId per session and,
  // at swipe time, log the impression + let the swipe outcome join to it.
  String? _discoverSearchIdCache;
  String get _discoverSearchId =>
      _discoverSearchIdCache ??= 'discover_${DateTime.now().microsecondsSinceEpoch}';

  /// Fire-and-forget: log ONE discover impression (the server feature vector the
  /// card carries) so the swipe outcome has an impression to join to. No-op when
  /// the card has no server rankFeatures (on-device-only listing) or offline.
  void _logDiscoverImpression(RentalProperty p, int rank) {
    final rf = p.rankFeatures;
    if (rf == null || rf.isEmpty || !AwsApiClient.instance.isConfigured) return;
    unawaited(
      AwsApiClient.instance.post('/search/log', {
        'searchId': _discoverSearchId,
        'impressions': [
          {
            'propertyId': p.id,
            'rankFeatures': rf,
            'rank': rank,
            if (p.abVariant != null) 'abVariant': p.abVariant,
            'outcome': 'impression',
          }
        ],
      }).catchError((_) => <String, dynamic>{}),
    );
  }

  /// Best-effort label for the search that surfaced [propertyId]. Fires
  /// `POST /search/outcome` with the real outcome so the backend records a
  /// training label joinable to the impression logged at search time. Fully
  /// non-blocking and error-swallowing — never affects the swipe/save UX. No-op
  /// when there is no active searchId (deck browsed outside a search).
  void _postSearchOutcome(
    String propertyId,
    String outcome, {
    int? dwellMs,
  }) =>
      _postOutcomeWith(_lastSearchId, propertyId, outcome, dwellMs: dwellMs);

  /// Post a training label under an EXPLICIT searchId (so the discover deck can
  /// label against its own session id without clobbering a live AI-search id).
  void _postOutcomeWith(
    String? searchId,
    String propertyId,
    String outcome, {
    int? dwellMs,
  }) {
    if (searchId == null ||
        searchId.isEmpty ||
        propertyId.isEmpty ||
        !AwsApiClient.instance.isConfigured) {
      return;
    }
    unawaited(
      AwsApiClient.instance.post('/search/outcome', {
        'searchId': searchId,
        'propertyId': propertyId,
        'outcome': outcome,
        if (dwellMs != null && dwellMs >= 0) 'dwellMs': dwellMs,
      }).catchError((_) => <String, dynamic>{}),
    );
  }

  /// Lazily populates [_pfvCache] with the learner feature vector for a single
  /// deck card that was NOT surfaced via search (so a swipe on it can train the
  /// FTRL learner). Reuses the EXACT feature computation [recommendForTenant]
  /// uses — RecommendationEngine.recommend fills the [learnerFeatureSink] as a
  /// side effect — scoped to just this property. Fail-soft: any error leaves the
  /// cache untouched and the swipe still logs its label.
  Map<String, double>? _ensureLearnerFeatures(RentalProperty property) {
    final cached = _pfvCache[property.id];
    if (cached != null) return cached;
    try {
      RecommendationEngine.recommend(
        candidates: [property],
        query: _queryFromFilters(_effectiveScoringFilters(_filters)),
        profile: _tenantProfile,
        limit: 1,
        learner: _learner,
        workLat: _tenantProfile?.workLat,
        workLon: _tenantProfile?.workLon,
        learnerFeatureSink: _pfvCache,
      );
    } catch (_) {/* fail-soft: swipe still records without a training example */}
    return _pfvCache[property.id];
  }

  Set<String> _likedPropertyIds = <String>{};
  Set<String> _passedPropertyIds = <String>{};
  Set<String> _ownerAcceptedPropertyIds = <String>{};
  Set<String> _ownerRejectedPropertyIds = <String>{};
  List<RentalMatch> _matches = const [];
  // Matches the user explicitly unmatched — suppressed so a backend reload can't
  // bring the conversation back. Persisted.
  Set<String> _unmatchedIds = <String>{};
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
  // The deck's best-match score per property from the last sort — the PREDICTION
  // that ordered the card, attached to the swipe outcome so each swipe is a
  // (prediction, label) calibration row.
  Map<String, int> _deckMatchScore = const {};
  // Per-property RecommendationEngine relevance [0,1] for the current deck — the
  // UNIFIED structural core of the deck score (same ranker as the search surface).
  // Populated in _sortProperties; a cache miss falls back to an on-demand score.
  Map<String, double> _engineRelevance = const {};

  // ── Main-feed impression logging + ε-greedy exploration (Phase 0) ───────────
  // Stable id for the CURRENT deck ordering. Re-minted every time _sortProperties
  // rebuilds the deck (filter/sort/catalog change), so it groups all impressions
  // of one feed and lets the backend join later swipe/click outcomes back to the
  // exact feed that surfaced the card — the same role searchId plays on the
  // search surface. Impression logging is skipped until it exists.
  String? _feedSearchId;
  // Dedup: one impression per property per feed session. Keyed by propertyId,
  // cleared whenever _feedSearchId changes (a genuinely new feed).
  final Set<String> _loggedDeckImpressions = <String>{};
  // Session-cumulative count of how many times each listing has been shown at/near
  // the top of the deck — the "under-explored" signal the ε-greedy promotion reads
  // (fewer prior impressions ⇒ more likely to be promoted). Not cleared per feed.
  final Map<String, int> _deckImpressionCount = <String, int>{};
  // The listing (if any) the ε-greedy rule promoted into a top-K slot for the
  // CURRENT feed, so its impression is tagged explored:true. Null on greedy feeds.
  String? _exploredPropertyId;

  // ε-greedy exploration knobs. With probability [_epsilonExplore] a single
  // under-explored listing is promoted into slot [_exploreSlot] of the top-K,
  // injecting position variance for future debiasing and surfacing cold inventory.
  // Bounded to EXACTLY ONE promotion per feed so exploration never dominates, and
  // gated to best-match sort (an explicit price/size sort is left untouched).
  static const double _epsilonExplore = 0.10;
  static const int _exploreTopK = 3; // promote from outside the greedy top-3…
  static const int _exploreSlot = 2; // …into the 3rd slot (visible, not the #1).
  // Impressions are logged for this many cards from the current top of the deck.
  static const int _impressionWindow = 3;
  // Collaborative-filtering recommendations from the backend (`POST /reco/cf`),
  // ordered highest-cfScore first. Consumed as a gentle deck boost via [_cfBoost]
  // and exposed (see [cfRecommendedIds]) so a "מומלץ בשבילך" section can use them.
  List<String> _cfRecommendedIds = const [];
  // O(1) rank lookup for [_cfBoost]: propertyId → 0-based CF rank.
  Map<String, int> _cfRank = const {};
  List<String>? _availableFeaturesCache;
  List<String>? _availablePropertyTypesCache;
  List<String>? _availableConditionsCache;
  List<String>? _availableCitiesCache;
  Map<String, double>? _featureWeightCache;
  _MarketIndex? _marketIndexCache;
  int _catalogRevision = 0;
  int _filterRevision = 0;
  int _filterLayoutRevision = 0;
  // Swipe-deck STRUCTURAL revision: bumps only when the deck is genuinely
  // replaced (filter/sort/catalog change), NOT on a per-swipe card removal. The
  // CardSwiper keys on THIS so a swipe advances it internally instead of tearing
  // down and rebuilding the whole deck (the "stutter between swipes").
  int _deckRevision = 0;
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

  // Retained structural weights: market-value drives a best-match tiebreak and
  // listing-confidence is a post-band business-readiness bonus. The rest of the
  // old hand-tuned structural scorer is gone — search-fit is now the unified
  // RecommendationEngine relevance (see _matchScoreForContext).
  static const double _marketValueWeight = 12;
  static const double _listingConfidenceWeight = 12;

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
  // Max bounded boost a CF-recommended listing gets in the deck sort — the same
  // small magnitude as the learned tag/area deltas, so CF complements the score
  // rather than dominating it. The top CF pick gets the full boost, decaying
  // linearly down the CF list.
  static const double _maxCfBoost = 8.0;

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
    // Dedup by id — the current user's own ACTIVE listings live in BOTH
    // _baseProperties (public status=active fetch) and _customProperties (owner
    // fetch). A plain concat double-counted them (twice in search/CMA/market
    // stats, +1 in filtered counts). The custom copy is the fresher/owner one,
    // so it wins.
    final byId = <String, RentalProperty>{};
    for (final p in _baseProperties.map(_propertyWithSignalOverride)) {
      byId[p.id] = p;
    }
    for (final p in _customProperties
        .where(_isDiscoverableCustomProperty)
        .map(_propertyWithSignalOverride)) {
      byId[p.id] = p; // custom overrides the base copy of the same listing
    }
    return _allPropertiesCache = byId.values.toList();
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
    _deckRevision++; // structural deck change → the swiper may re-key
    _filteredPropertiesCache = null;
    // The unified engine relevance is filter-dependent — drop it so a match score
    // read after a filter change recomputes fresh instead of returning a stale
    // deck value (otherwise widening the budget wouldn't move the score).
    _engineRelevance = const {};
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

  // ── Subscription / paywall ─────────────────────────────────────────────────

  /// The last-known landlord subscription snapshot (null until first fetched).
  Subscription? get subscription => _subscription;

  /// True when the landlord is entitled to publish beyond the free limit.
  bool get isSubscribed => _subscription?.entitled ?? false;

  /// Fetches the subscription snapshot, stores it, and notifies. Fail-soft:
  /// never throws (keeps the cached snapshot on error).
  Future<void> refreshSubscription() async {
    try {
      final sub = await AwsApiClient.instance.getSubscription();
      if (sub == null) return;
      _subscription = sub;
      unawaited(_persist());
      notifyListeners();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('DatingProvider.refreshSubscription: $error');
      }
    }
  }

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
    // Phase-0 guardrail: a present-but-restrictive versioned consent record
    // overrides the caller's legacy export flag and blocks the dataset export.
    // With NO versioned record yet, we keep the prior behaviour so nothing
    // regresses before the new consent flow ships.
    final consent = _tenantConsent;
    if (consent.hasConsent &&
        !TenantConsentService.instance.allowsPersonaExport(consent)) {
      return;
    }
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
      learner: _learner, // read side: blended in (confidence-gated)
      learnerFeatureSink: _pfvCache, // stash shown listings' feature vectors
    );
    // Keep the stash bounded (feature vectors of recently-shown listings only).
    if (_pfvCache.length > 800) {
      for (final k in _pfvCache.keys.take(_pfvCache.length - 800).toList()) {
        _pfvCache.remove(k);
      }
    }
    // BOOST: a paid "הקפצה" floats a listing to the top of the feed until its
    // boostedUntil passes. Three stable bands (each preserves the engine's rank
    // order within it): Ultra (×5) first, then regular (×2), then everyone else —
    // so an Ultra boost out-reaches a regular one.
    final ultra = <dynamic>[];
    final boosted = <dynamic>[];
    final rest = <dynamic>[];
    for (final r in recs) {
      if (r.property.isUltraBoosted) {
        ultra.add(r);
      } else if (r.property.isBoosted) {
        boosted.add(r);
      } else {
        rest.add(r);
      }
    }
    final ordered = (ultra.isEmpty && boosted.isEmpty)
        ? recs
        : [...ultra, ...boosted, ...rest];
    // Calibration: log the engine's OWN prediction for every result it surfaces,
    // so a later swipe/contact outcome (joined by propertyId+sessionId) tells us
    // how well the hand-tuned fit% actually predicts behaviour. Fire-and-forget.
    for (var i = 0; i < ordered.length; i++) {
      AppEvents.instance.service.logRankedImpression(
        propertyId: ordered[i].property.id,
        fitPct: ordered[i].fitPct,
        rank: i,
        dims: ordered[i].dimensionBreakdown,
      );
    }
    return [
      for (final r in ordered)
        ScoredProperty(
          r.property,
          r.fitScore / 100.0,
          // Locale-neutral: no "match" word baked in here (this provider has no
          // BuildContext to localize with) — the number-only tag is parsed by
          // consumers (e.g. why_details.dart) or re-labelled with a localized
          // "N% match" string at the widget layer (map_style_property_card.dart,
          // assistant_property_card.dart) where a BuildContext is available.
          ['${r.fitPct}%', ...r.highlights],
          r.trainKm,
          r.strictMatch,
          r.scorecard,
        ),
    ];
  }
  List<SearchArea> get searchAreas => _searchAreas;
  List<AppReview> get tenantReviews => const []; // reviews feature removed
  // Tenant side previously had NO per-user filter at all (unlike the landlord
  // branch below) — whatever sat in the in-memory _matches list was shown
  // verbatim. Combined with the device-scoped remote-state issue fixed in
  // forgetDeviceRemoteState, this meant one tenant's private match/chat list
  // could show up under a different tenant account on the same device. Uses
  // the same matchId "match-<propertyId>~<tenantUid>" convention already
  // relied on by _matchedTenantsFor — RentalMatch carries no dedicated uid
  // field to filter on otherwise.
  List<RentalMatch> get matches {
    if (isLandlord) {
      return _matches.where((match) {
        final property = propertyById(match.propertyId);
        return property != null && _belongsToCurrentLandlord(property);
      }).toList(growable: false);
    }
    final myUid = _tenantProfile?.id;
    if (myUid == null || myUid.isEmpty) return _matches;
    return _matches.where((match) {
      final sep = match.id.lastIndexOf('~');
      // No parseable uid suffix (legacy/demo id) — can't determine ownership,
      // fall back to showing it rather than risk hiding a real match.
      if (sep < 0) return true;
      return match.id.substring(sep + 1) == myUid;
    }).toList(growable: false);
  }
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
    if (_filters.preferredNearby.isNotEmpty) count++;
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

  /// Structural deck revision for the CardSwiper key — changes only when the
  /// deck is replaced (filter/sort/catalog), never on a single swipe, so the
  /// swiper advances internally instead of rebuilding every card each swipe.
  int get deckRevision => _deckRevision;

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
    if (!_passesLandlordEligibility(property)) return false;
    return _passesFilters(property, filters, now, area);
  }

  /// F2 client-side audience gate — a best-effort SECOND layer over the
  /// AUTHORITATIVE server-side cohort gate (GET /properties already filters
  /// fail-open). Hides an audience-exclusive listing only when the tenant is
  /// PROVABLY ineligible; every uncertain case fails open (shows it).
  bool _passesLandlordEligibility(RentalProperty property) {
    return passesAudienceGate(
      exclusive: property.exclusiveToAudience,
      audienceCohorts: property.audienceCohorts,
      tenantCohort: _resolvedTenantCohort(),
      isOwner: _belongsToCurrentLandlord(property),
    );
  }

  /// Pure decision for the F2 audience gate, extracted for unit testing.
  /// Returns true (SHOW) unless the listing is [exclusive], has a non-empty
  /// [audienceCohorts] list, the viewer is not the owner, and [tenantCohort] is
  /// a KNOWN value that is NOT in that list — the only case that HIDES. All
  /// unknowns (not exclusive / empty list / owner / null-or-empty cohort) fail
  /// open, mirroring the server's fail-open contract.
  static bool passesAudienceGate({
    required bool exclusive,
    required List<String> audienceCohorts,
    required String? tenantCohort,
    required bool isOwner,
  }) {
    if (!exclusive) return true;
    if (audienceCohorts.isEmpty) return true;
    if (isOwner) return true;
    final cohort = tenantCohort?.trim() ?? '';
    if (cohort.isEmpty) return true; // can't determine cohort → fail open
    return audienceCohorts.contains(cohort); // known & not targeted → hide
  }

  /// The tenant's resolved cohort in the landlord AUDIENCE taxonomy
  /// (young_professional / family / couple / single / …), or null when it can't
  /// be resolved on-device. TODAY this is always null by necessity: the app
  /// sends raw cohort SIGNALS (household / religiousStream / carFree / …) to the
  /// backend `resolveCohort`, which owns the 14-cohort resolution — no single
  /// authoritative cohort key exists client-side, and guessing one would be a
  /// fabricated gate. So [passesAudienceGate] is pass-through here and the SERVER
  /// gate is the real enforcement. When a client-resolved cohort lands, return
  /// it from this method and the gate above begins enforcing — nothing else
  /// needs to change.
  String? _resolvedTenantCohort() => null;

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
    return _cityNameMatch(a, b);
  }

  /// Whole-word prefix match on already-normalized city names. Accepts an exact
  /// match or one being a leading whole word of the other ("תל אביב" ⊂
  /// "תל אביב יפו"), but rejects mid/suffix containment across a word boundary
  /// so "יבנה" no longer matches "גן יבנה" (a different municipality).
  static bool _cityNameMatch(String a, String b) {
    if (a == b) return true;
    final shorter = a.length <= b.length ? a : b;
    final longer = a.length <= b.length ? b : a;
    return longer.startsWith('$shorter ');
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
    // A new deck ordering begins here → mint a fresh feed id, reset the per-feed
    // impression dedup, and clear last feed's exploration mark. All deck
    // impressions logged until the next re-sort group under this one id.
    _feedSearchId = ID.unique();
    _loggedDeckImpressions.clear();
    _exploredPropertyId = null;
    final matchContext = _MatchContext(
      filters: filters,
      now: now,
      area: area,
      featureWeights: _featureWeights,
      marketIndex: _marketIndex,
    );
    // Compute the unified engine relevance for the WHOLE deck once, so each
    // property's match score reads from the cache instead of re-ranking per call.
    _engineRelevance = filters.sortBy == SearchSortOption.bestMatch
        ? RecommendationEngine.relevance(
            candidates: properties,
            query: _queryFromFilters(_effectiveScoringFilters(filters)),
            profile: _tenantProfile,
            marketSource: _allProperties,
          )
        : const <String, double>{};
    final scoreCache = filters.sortBy == SearchSortOption.bestMatch
        ? <String, int>{
            for (final property in properties)
              property.id: _matchScoreForContext(property, matchContext),
          }
        : const <String, int>{};
    // Remember the scores that ordered this deck so a swipe can log its own
    // prediction (calibration). Only meaningful for best-match sort.
    if (scoreCache.isNotEmpty) _deckMatchScore = scoreCache;

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

    // ε-greedy exploration (best-match only): with probability ε, promote one
    // under-explored listing into a top-K slot in place of the greedy pick.
    if (filters.sortBy == SearchSortOption.bestMatch) {
      _applyExploration(properties);
    }
  }

  /// ε-GREEDY EXPLORATION (data-engine / landmine #4). With probability
  /// [_epsilonExplore] (=0.10) this promotes a SINGLE under-explored listing out
  /// of the greedy tail and into slot [_exploreSlot] of the top-K, so the deck
  /// occasionally shows fresh/cold inventory and — crucially — injects position
  /// variance the backend can later use to debias the click log. Bounded to at
  /// most one promotion per feed, so it never dominates the greedy order.
  ///
  /// Determinism: the explore/greedy coin is a DETERMINISTIC hash of the deck's
  /// content + filter/catalog revisions — NOT Random()/DateTime.now() — so the
  /// same feed always makes the same decision (reproducible for debugging and
  /// stable across the rebuilds a single feed undergoes), while distinct feeds
  /// vary (≈ε of them explore). Promotion target = the most under-explored
  /// listing: fewest prior impressions THIS session, tie-broken by lowest server
  /// popularity (marketSignals engagement), then id for a total order.
  void _applyExploration(List<RentalProperty> properties) {
    if (properties.length <= _exploreTopK) return;

    // Deterministic coin in [0,1) seeded from stable, non-time content.
    final seed = Object.hash(
      _filterRevision,
      _catalogRevision,
      properties.length,
      properties[0].id,
      properties[1].id,
      properties[2].id,
    );
    final u = (seed & 0x7fffffff) / 0x80000000;
    if (u >= _epsilonExplore) return; // greedy feed — leave the order untouched.

    // Pick the most under-explored listing from OUTSIDE the greedy top-K.
    var bestIndex = -1;
    var bestImpressions = 1 << 30;
    var bestPopularity = 1 << 30;
    for (var i = _exploreTopK; i < properties.length; i++) {
      final p = properties[i];
      final impressions = _deckImpressionCount[p.id] ?? 0;
      final popularity = _serverPopularity(p);
      if (impressions < bestImpressions ||
          (impressions == bestImpressions && popularity < bestPopularity)) {
        bestIndex = i;
        bestImpressions = impressions;
        bestPopularity = popularity;
      }
    }
    if (bestIndex < 0) return;

    final promoted = properties.removeAt(bestIndex);
    properties.insert(_exploreSlot, promoted);
    _exploredPropertyId = promoted.id;
  }

  /// Cheap server-popularity proxy (lower = more under-explored). Mirrors the
  /// search repo's engagement weighting over the embedded market signals.
  int _serverPopularity(RentalProperty p) {
    final m = p.marketSignals;
    return m.likes * 2 + m.saves * 3 + m.contactRequests * 4 + m.views;
  }

  /// Photos + video + 360 count for a listing (media already holds images and
  /// videos; a panorama tour is the separate 360 asset). Sent with interactions
  /// so the backend can length-normalize dwell.
  int _mediaCountOf(RentalProperty p) =>
      p.media.length + (p.hasPanoramaTour ? 1 : 0);

  /// Length of the listing's descriptive text. [RentalProperty] has no dedicated
  /// description field, so its [searchableText] (city/neighborhood/features/…) is
  /// used as the best available content-length proxy for dwell normalization.
  int _descLenOf(RentalProperty p) => p.searchableText.length;

  /// MAIN-FEED IMPRESSION LOGGING (landmine #2). Logs one impression per listing
  /// SHOWN at/near the top of the deck, so "shown-then-passed" becomes a real
  /// negative distinct from "never shown". Carries the server [rankFeatures] /
  /// [abVariant] VERBATIM (parity — landmine #1), the deck [rank], the per-feed
  /// [_feedSearchId] join key, and the ε-greedy explored flag. Deduped to one row
  /// per property per feed. Fire-and-forget; never blocks or reorders the deck.
  void logDeckImpression(RentalProperty property, int rank) {
    final feedId = _feedSearchId;
    if (feedId == null ||
        property.id.isEmpty ||
        !AwsApiClient.instance.isConfigured) {
      return;
    }
    if (!_loggedDeckImpressions.add(property.id)) return; // one per feed.
    _deckImpressionCount[property.id] =
        (_deckImpressionCount[property.id] ?? 0) + 1;
    // Bound the session map so a long browse can't grow it without limit.
    if (_deckImpressionCount.length > 2000) {
      for (final k in _deckImpressionCount.keys
          .take(_deckImpressionCount.length - 2000)
          .toList()) {
        _deckImpressionCount.remove(k);
      }
    }
    unawaited(
      AwsApiClient.instance.post('/search/log', {
        'searchId': feedId,
        'source': 'deck',
        'ts': DateTime.now().toUtc().toIso8601String(),
        'impressions': [
          {
            'propertyId': property.id,
            'rank': math.max(0, rank),
            'explored': property.id == _exploredPropertyId,
            // VERBATIM server fields — omitted (not faked) when the backend
            // didn't attach them, e.g. the bundled-asset fallback catalog.
            if (property.rankFeatures != null)
              'rankFeatures': property.rankFeatures,
            if (property.abVariant != null) 'abVariant': property.abVariant,
          },
        ],
      }).catchError((_) => <String, dynamic>{}),
    );
  }

  /// Logs impressions for the [_impressionWindow] cards from [from] in [deck]
  /// (the cards that just surfaced at/near the top). Dedup makes it safe to call
  /// on every deck build and after every swipe.
  void logVisibleDeckImpressions(List<RentalProperty> deck, {int from = 0}) {
    if (from < 0) from = 0;
    final end = math.min(deck.length, from + _impressionWindow);
    for (var i = from; i < end; i++) {
      logDeckImpression(deck[i], i);
    }
  }

  List<RentalProperty>? _ownerLeadsCache;
  int _ownerLeadsSig = -1;

  // ── Phase-0: server-side two-sided lead ranking (POST /match/leads) ─────────
  // The STRONG landlord←tenant scorer (scoreLandlordToTenant: tags, deal-breakers,
  // affordability) lives on the server. We fetch it and prefer it over the weak
  // local leadFitScore, keyed by (propertyId, tenantId) so it matches the exact
  // representative liker the deck shows. Fail-soft: empty on any error/unconfigured
  // → the local heuristic still ranks, so nothing regresses when the endpoint is
  // unavailable.
  final Map<String, RankedLead> _serverLeadByKey = {};
  int _serverLeadsRevision = 0;
  bool _rankedLeadsLoading = false;

  String _leadKey(String propertyId, String tenantId) =>
      '$propertyId::$tenantId';

  /// The server's ranked lead for [property]'s representative liker, or null when
  /// the server ranking hasn't loaded / doesn't cover this exact tenant.
  RankedLead? _serverLeadFor(RentalProperty property) {
    if (_serverLeadByKey.isEmpty) return null;
    final tid = _representativeLikerFor(property)?.tenantId;
    if (tid == null || tid.isEmpty) return null;
    return _serverLeadByKey[_leadKey(property.id, tid)];
  }

  /// One real server-authored reason this candidate fits (tags/afford/deal-break),
  /// or null. Lets the candidate card show the strong scorer's explanation.
  String? rankedLeadReasonFor(RentalProperty property) {
    final l = _serverLeadFor(property);
    return (l != null && l.reasons.isNotEmpty) ? l.reasons.first : null;
  }

  /// True when the server two-sided model flagged a hard deal-breaker conflict
  /// for this candidate (so the UI can mark it honestly).
  bool rankedLeadExcluded(RentalProperty property) =>
      _serverLeadFor(property)?.excluded ?? false;

  /// Phase-0: pull the server's two-sided lead ranking and prefer it over the
  /// local heuristic for the landlord candidate deck. Fail-soft + debounced;
  /// call it when the landlord opens the candidates surface.
  Future<void> refreshRankedLeads() async {
    if (!isLandlord || _rankedLeadsLoading) return;
    if (!AwsApiClient.instance.isConfigured) return;
    _rankedLeadsLoading = true;
    try {
      final leads = await fetchRankedLeads();
      if (leads.isEmpty) return;
      _applyRankedLeads(leads);
    } finally {
      _rankedLeadsLoading = false;
    }
  }

  void _applyRankedLeads(List<RankedLead> leads) {
    _serverLeadByKey
      ..clear()
      ..addEntries(leads
          .where((l) => l.tenantId.isNotEmpty && l.propertyId.isNotEmpty)
          .map((l) => MapEntry(_leadKey(l.propertyId, l.tenantId), l)));
    _serverLeadsRevision++;
    _ownerLeadsCache = null; // force a re-sort using the server scores
    notifyListeners();
  }

  /// Test seam: inject server ranked leads without a network call.
  @visibleForTesting
  void debugApplyRankedLeads(List<RankedLead> leads) => _applyRankedLeads(leads);

  /// Test seam: seed the cross-user incoming likes the deck ranks over.
  @visibleForTesting
  void debugSetIncomingLikes(Map<String, List<PropertyLike>> byProperty) {
    _incomingLikesByProperty = Map.of(byProperty);
    _ownerLeadsCache = null;
    notifyListeners();
  }

  // ── Phase-0: persisted, evolving SOFT cohort membership ─────────────────────
  // A per-user probability vector over the 14 cohorts that sharpens across
  // sessions (vs the server's throwaway single-label per request). Persisted in
  // app_state via [_persist], restored in restoreState. Groundwork for the
  // eventual server multi-label + look-alike targeting.
  CohortBelief _cohortBelief = CohortBelief();

  CohortBelief get cohortBelief => _cohortBelief;

  /// The person's current best-guess cohort, or null before any evidence.
  String? get primaryCohort => _cohortBelief.top;

  /// The top cohorts the person belongs to — their "audience".
  List<String> get audienceCohorts => _cohortBelief.topK(3);

  /// Fold a query's cohort signals (from `SmartSearch.cohortSignals`) into the
  /// evolving belief and persist. No-op on empty/evidence-free signals.
  void observeCohortSignals(Map<String, String> signals) {
    if (signals.isEmpty) return;
    final before = _cohortBelief.observations;
    _cohortBelief.observe(signals);
    if (_cohortBelief.observations == before) return; // no evidence → nothing changed
    unawaited(_persist());
    notifyListeners();
  }

  // ── Phase-0: versioned tenant DATA consent (guardrail) ──────────────────────
  // A real, auditable, versioned record (vs the old SharedPreferences boolean)
  // gating whether behavioural/persona data may be exported for cross-user
  // modelling. Persisted in app_state; restored in restoreState.
  TenantDataConsent _tenantConsent = TenantDataConsent.none;

  TenantDataConsent get tenantDataConsent => _tenantConsent;

  /// Current-version consent to fold the persona into the exportable dataset.
  bool get canExportPersonaData =>
      TenantConsentService.instance.allowsPersonaExport(_tenantConsent);

  /// A stamped consent exists but on a stale version → the UI should re-ask.
  bool get tenantConsentNeedsRenewal =>
      TenantConsentService.instance.needsRenewal(_tenantConsent);

  /// Record the tenant's explicit data-use choice (a decline is still a stamped,
  /// current-version record with all rights false).
  void recordTenantDataConsent({
    required bool behavioralAnalytics,
    required bool personaDataset,
    required bool aiTraining,
    String source = 'app',
  }) {
    _tenantConsent = TenantConsentService.instance.grantConsent(
      source: source,
      behavioralAnalytics: behavioralAnalytics,
      personaDataset: personaDataset,
      aiTraining: aiTraining,
    );
    unawaited(_persist());
    notifyListeners();
  }

  List<RentalProperty> get ownerLeads {
    // Memoize: this getter is read inside Consumer builders, so without a cache it
    // re-ran a full .where()+leadFitScore()+sort() over the whole catalogue on EVERY
    // rebuild (incl. every pagination notify and every swipe). Recompute only when a
    // lead-affecting input actually changed (cheap size/revision signature).
    final sig = Object.hash(
      _catalogRevision,
      _likedPropertyIds.length,
      _ownerAcceptedPropertyIds.length,
      _ownerRejectedPropertyIds.length,
      _matches.length,
      _incomingLikesByProperty.length,
      // Total likers, not just how many properties have likes — otherwise a
      // SECOND liker arriving on an existing lead wouldn't bust the cache.
      _incomingLikesByProperty.values.fold<int>(0, (a, b) => a + b.length),
      identityHashCode(_tenantProfile),
      _serverLeadsRevision, // re-sort when server ranking arrives
    );
    final cached = _ownerLeadsCache;
    if (cached != null && sig == _ownerLeadsSig) return cached;

    final leads = _allProperties.where((property) {
      if (!_belongsToCurrentLandlord(property)) return false;
      // Real cross-user likes: a lead while ANY liker is still un-actioned.
      if (_openLikersFor(property).isNotEmpty) return true;
      // Locally-seeded demo like (no cross-user liker): property-level, as
      // before — actioned via the empty-tenant key.
      if (_likedPropertyIds.contains(property.id)) {
        final demoKey = _ownerActionKey(property.id, '');
        return !_ownerAcceptedPropertyIds.contains(demoKey) &&
            !_ownerRejectedPropertyIds.contains(demoKey) &&
            !_matches.any((match) => match.propertyId == property.id);
      }
      return false;
    }).toList();

    // Surface the best-fit candidate first. Each lead is a property the
    // landlord owns that an interested tenant liked; we rank by how well that
    // tenant genuinely fits THIS property, using only real profile data
    // (budget vs asking rent, move-in timing, and the existing trust score).
    // Stable: ties fall back to id so ordering is deterministic and the lead
    // membership the rest of the app relies on is unchanged — only reordered.
    final tenant = _tenantProfile;
    if (tenant == null || leads.length < 2) {
      _ownerLeadsSig = sig;
      return _ownerLeadsCache = leads;
    }

    final scores = <String, double>{
      for (final property in leads) property.id: leadFitScore(property),
    };
    leads.sort((a, b) {
      final delta = (scores[b.id] ?? 0).compareTo(scores[a.id] ?? 0);
      if (delta != 0) return delta;
      return a.id.compareTo(b.id);
    });
    _ownerLeadsSig = sig;
    return _ownerLeadsCache = leads;
  }

  // ── Candidate (lead) ranking ────────────────────────────────────────────
  // The score below the [_highFitLeadScore] threshold gets no "high match"
  // badge — it is honest: a candidate only earns the badge when the real
  // signals line up. Score is in [0, 100].
  static const double _highFitLeadScore = 70;
  static const double _leadBudgetWeight = 60; // budget vs asking rent
  static const double _leadTimingWeight = 25; // move-in timing match
  static const double _leadTrustWeight = 15; // existing trust-score signal

  /// Accept/reject is keyed per (property, tenant), NOT per property, so a
  /// second interested tenant stays actionable and rejecting one candidate never
  /// blocks the property for future likers. Demo leads (no cross-user liker) use
  /// an empty tenant → a property-level key.
  String _ownerActionKey(String propertyId, String tenantId) =>
      '$propertyId|$tenantId';

  /// Tenant uids that already have a match on [propertyId] — parsed from the
  /// matchId "match-<propertyId>~<tenantUid>" (RentalMatch carries no uid field).
  Set<String> _matchedTenantsFor(String propertyId) {
    final out = <String>{};
    for (final m in _matches) {
      if (m.propertyId != propertyId) continue;
      final sep = m.id.lastIndexOf('~');
      if (sep >= 0) out.add(m.id.substring(sep + 1));
    }
    return out;
  }

  /// The likers of [property] the landlord hasn't acted on yet — not accepted,
  /// not rejected, not already matched. This is what keeps a property a live
  /// lead while ANY interested tenant is still open.
  List<PropertyLike> _openLikersFor(RentalProperty property) {
    final likes = _incomingLikesByProperty[property.id];
    if (likes == null || likes.isEmpty) return const [];
    final matched = _matchedTenantsFor(property.id);
    return likes.where((l) {
      final k = _ownerActionKey(property.id, l.tenantId);
      return !_ownerAcceptedPropertyIds.contains(k) &&
          !_ownerRejectedPropertyIds.contains(k) &&
          !matched.contains(l.tenantId);
    }).toList();
  }

  /// The representative liker for a property lead — the BEST-fitting interested
  /// tenant (Phase-0: was arbitrarily the first). Prefers the server's two-sided
  /// score when loaded, else a local budget-fit proxy; deterministic tie-break by
  /// tenantId. Considers only OPEN likers, so after accepting/rejecting one the
  /// next candidate surfaces. Null for a demo lead with no incoming like yet.
  PropertyLike? _representativeLikerFor(RentalProperty property) {
    final likes = _openLikersFor(property);
    if (likes.isEmpty) return null;
    if (likes.length == 1) return likes.first;
    double scoreOf(PropertyLike l) {
      final sv = _serverLeadByKey[_leadKey(property.id, l.tenantId)];
      if (sv != null) return sv.score.toDouble();
      return _leadBudgetFit(l.budgetMax, property) * 100; // local proxy [0,100]
    }

    var best = likes.first;
    var bestScore = scoreOf(best);
    for (final l in likes.skip(1)) {
      final s = scoreOf(l);
      if (s > bestScore ||
          (s == bestScore && l.tenantId.compareTo(best.tenantId) < 0)) {
        best = l;
        bestScore = s;
      }
    }
    return best;
  }

  /// The best-fitting interested tenant for [property] (public; the deck uses it
  /// so the card and the score describe the SAME candidate).
  PropertyLike? bestLikerFor(RentalProperty property) =>
      _representativeLikerFor(property);

  /// How many OTHER tenants are interested in [property] beyond the one shown —
  /// drives a "+N מתעניינים" affordance so extra likers aren't invisible.
  int additionalInterestedCount(String propertyId) {
    final n = _incomingLikesByProperty[propertyId]?.length ?? 0;
    return n > 1 ? n - 1 : 0;
  }

  /// Honest fit score in [0, 100] for the tenant who liked [property]. Scored
  /// against the REAL representative LIKER's snapshotted values (budget, move-in,
  /// verification) when a like exists; falls back to the current tenant profile
  /// only for demo leads with no incoming like. Drives both the ranking order
  /// and the "התאמה גבוהה" badge — no fabricated trust. Fail-soft.
  double leadFitScore(RentalProperty property) {
    // Phase-0: prefer the server's two-sided score for this exact liker — it
    // weighs tags, deal-breakers and affordability, not just budget/timing/trust.
    // Falls through to the local heuristic when the server ranking is absent.
    final serverLead = _serverLeadFor(property);
    if (serverLead != null) {
      return serverLead.score.clamp(0, 100).toDouble();
    }

    var tenant = _tenantProfile;
    if (isLandlord && tenant?.id == 'tenant-local') {
      tenant = getCachedProfile('tenant-test') ?? tenant;
    }
    final liker = _representativeLikerFor(property);
    if (tenant == null && liker == null) return 0;

    // Budget: the liker's snapshotted max when present, else the profile's.
    final budget = liker?.budgetMax ?? tenant?.budgetMax;
    final budgetFit = _leadBudgetFit(budget, property); // [0, 1]

    // Timing: the liker's move-in snapshot when present, else the profile's.
    final window = (liker?.moveInSnapshot.trim().isNotEmpty ?? false)
        ? liker!.moveInSnapshot
        : (tenant?.moveInWindow ?? '');
    final timingFit = _leadTimingFit(window, property); // [0, 1] or null

    // Trust: for a real liker the one cross-device signal we carry is their
    // verification flag; demo leads reuse the profile's computed trust score.
    final double trustFit;
    if (liker != null) {
      trustFit = (liker.verified ?? false) ? 1.0 : 0.5;
    } else {
      trustFit = GamificationService.computeTrustScore(tenant!, const []) / 100.0;
    }

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
  /// out. Budget is checked first (the strongest signal), then timing. Returns
  /// a stable [LeadFitReason] key (not a display string) — this provider has
  /// no BuildContext to localize with; callers (e.g. explore_screen.dart)
  /// translate the key with a widget-local label map.
  LeadFitReason? leadFitReason(RentalProperty property) {
    final tenant = _tenantProfile;
    final liker = _representativeLikerFor(property);
    if (tenant == null && liker == null) return null;

    final budget = liker?.budgetMax ?? tenant?.budgetMax;
    if (budget != null &&
        _hasKnownPrice(property) &&
        budget >= property.price &&
        _leadBudgetFit(budget, property) >= 0.8) {
      return LeadFitReason.budgetFits;
    }
    final window = (liker?.moveInSnapshot.trim().isNotEmpty ?? false)
        ? liker!.moveInSnapshot
        : (tenant?.moveInWindow ?? '');
    final timingFit = _leadTimingFit(window, property);
    if (timingFit != null && timingFit >= 0.8) {
      return LeadFitReason.timingFits;
    }
    return null;
  }

  // Budget fit in [0, 1]: a tenant whose budget meets the asking rent and sits
  // close to it scores high; a budget far BELOW the rent scores low (they
  // likely can't afford it). A comfortable margin above is fine, not penalised
  // hard. Unknown price → neutral 0.5 (we can't claim a fit we can't measure).
  double _leadBudgetFit(int? budget, RentalProperty property) {
    if (budget == null ||
        !_hasKnownPrice(property) ||
        property.price <= 0) return 0.5;
    final ratio = budget / property.price;
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
  double? _leadTimingFit(String moveInWindow, RentalProperty property) {
    final entryDate = property.entryDateValue;
    if (entryDate == null) return null;
    final window = moveInWindow.trim();
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

  // ── Viewing confirmations → bookings (global, reactive, idempotent) ─────────
  // LATE so the repo (whose ctor eagerly calls SharedPreferences.getInstance)
  // is built only on first use — never at provider construction — keeping
  // pure-provider unit tests free of a SharedPreferences plugin dependency.
  late final AvailabilityRepository _availabilityRepo = AvailabilityRepository();

  /// Confirm slotIds already turned into a booking + reminder this session, so
  /// repeated scans can't double-schedule (repo-level booking is idempotent too).
  final Set<String> _processedConfirmSlotIds = {};

  /// Re-entrancy guard so two overlapping triggers (per-chat + merged screen)
  /// can't run the async scan concurrently.
  bool _processingConfirms = false;

  /// Landlord-side: scan EVERY match thread for tenant `[[SLOT_CONFIRM]]`
  /// messages and, for each not-yet-processed confirm, book the matching OPEN
  /// slot and schedule the landlord's 1h-before reminder. Making this global +
  /// reactive (invoked when the landlord opens the merged לקוחות screen as well
  /// as any individual chat) means a confirmation is booked even if the landlord
  /// never opens that specific thread (SCHED-4).
  ///
  /// Idempotent: a per-session guard set, a "only claim a slot that's still
  /// open" check and fixed reminder ids mean running it repeatedly never
  /// double-books or double-schedules. The reminder is scheduled ONLY inside the
  /// open-slot booking block, so no reminder fires when nothing was actually
  /// booked (slot deleted / already taken) (SCHED-2). Fail-soft — never throws
  /// into the UI. Notifies listeners when a booking is made so dependent widgets
  /// (e.g. the dashboard "next viewing" card) can refresh (SCHED-3).
  Future<void> processViewingConfirms(AppLocalizations l10n) async {
    if (!isLandlord) return;
    if (_processingConfirms) return;
    _processingConfirms = true;
    try {
      final pending =
          <({SlotConfirm confirm, String who, String propertyId})>[];
      for (final match in matches) {
        for (final m in match.messages) {
          final parsed = SlotMessageCodec.parse(m.text);
          if (parsed is SlotConfirmMessage &&
              !_processedConfirmSlotIds.contains(parsed.confirm.slotId)) {
            final who = m.sender.trim().isEmpty
                ? l10n.datingProviderTenantFallbackName
                : m.sender.trim();
            pending.add((
              confirm: parsed.confirm,
              who: who,
              propertyId: match.propertyId,
            ));
          }
        }
      }
      if (pending.isEmpty) return;

      // Mark processed up front so a concurrent trigger can't re-enter the
      // same ids while we await the repo.
      for (final p in pending) {
        _processedConfirmSlotIds.add(p.confirm.slotId);
      }

      final all = await _availabilityRepo.loadAll();
      var bookedAny = false;
      for (final p in pending) {
        final c = p.confirm;
        AvailabilitySlot? slot;
        for (final s in all) {
          if (s.id == c.slotId) {
            slot = s;
            break;
          }
        }
        // Double-book guard: only claim a slot that's still open — and only
        // then schedule the reminder, so a deleted/already-booked slot never
        // fires a phantom reminder (SCHED-2).
        //
        // KNOWN LOCAL-MVP LIMITATION (SCHED-1): a second tenant who confirms a
        // slot this landlord already booked for a first tenant still sees
        // "מאושר" on their own device. Resolving that race needs server-side
        // slot state; locally we simply never re-book here.
        if (slot != null && slot.status == SlotStatus.open) {
          await _availabilityRepo.save(slot.copyWith(
            status: SlotStatus.booked,
            bookedByName: p.who,
            // Auto-tag the booked viewing to its property so the calendar card
            // can show which apartment it's for (the slot may have been a
            // general/any-listing window before it was booked).
            propertyId: p.propertyId.isNotEmpty ? p.propertyId : null,
          ));
          bookedAny = true;
          final property = propertyById(p.propertyId);
          final address = (property?.address.trim().isNotEmpty ?? false)
              ? property!.address.trim()
              : l10n.datingProviderPropertyFallbackName;
          final time = '${c.start.hour.toString().padLeft(2, '0')}:'
              '${c.start.minute.toString().padLeft(2, '0')}';
          // Fixed id per slot → rescheduling replaces rather than duplicates.
          await NotificationService.instance.scheduleReminder(
            id: NotificationService.instance.viewingReminderId(c.slotId),
            title: l10n.datingProviderViewingReminderTitle,
            body: l10n.datingProviderViewingReminderBody(p.who, address, time),
            when: c.start.subtract(const Duration(hours: 1)),
          );
        }
      }
      if (bookedAny) notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('processViewingConfirms: $e');
    } finally {
      _processingConfirms = false;
    }
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
      // Merge, not replace: a null result means the fetch failed for that
      // property — keep its prior likes rather than dropping the tenants.
      final next = <String, List<PropertyLike>>{};
      for (final e in entries) {
        final likes = e.value;
        if (likes == null) {
          final prior = _incomingLikesByProperty[e.key];
          if (prior != null && prior.isNotEmpty) next[e.key] = prior;
        } else if (likes.isNotEmpty) {
          next[e.key] = likes;
        }
      }
      _incomingLikesByProperty = next;
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
      // Fail-soft: the app-state blob is remote-synced and may come from another
      // device / older schema / a truncated write. A throwing fromJson deep inside
      // _hydrateFromState must NOT wedge startup (initialize() is fire-and-forget,
      // so an unhandled throw would leave _isLoading true → permanent spinner).
      // On any corruption, reseed — same as a missing blob.
      try {
        _hydrateFromState(storedState);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('DatingProvider.initialize: corrupt cached state, reseeding: $e');
        }
        _seedInitialState();
        _hasActiveSession = false;
      }
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
      // Phase-2: refresh the server user vector on launch for a returning user
      // who already has likes (so personalised semantic ranking works without
      // needing 3 fresh swipes first). Fire-and-forget, fail-soft.
      _maybeRefreshUserEmbedding(force: true);
      unawaited(_refreshCurrentTenantReviewsAfterAuth());
      // Pull mutual matches a landlord created for this tenant on another device,
      // so the chat shows up in their conversations (was local-only → invisible).
      unawaited(_loadMatchesFromBackend());
      // Restore the broker's tools (clients/leads/deals/viewings/exclusivity) from
      // the cloud so their book survives a lost/replaced device + syncs across
      // devices — the #1 gap every agent flagged.
      if (isBroker) {
        unawaited(BrokerCloudSync.instance.pullAllToLocal());
        unawaited(_pullBrokerBranding());
      }
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

    // PERF: we no longer eager-preload ~1500 properties at startup. That bulk
    // load appended + re-ranked the whole growing catalogue on the UI isolate
    // during the first ~15 s (the startup "rebuild storm"), while all the swipe
    // deck needs is loadMorePropertiesIfNeeded() (paged on demand as the user
    // swipes). The full catalogue is only needed for the Lasso/map overview, so
    // it's now loaded on demand when that opens — see ensureFullCatalogLoaded().
  }

  bool _fullCatalogRequested = false;

  /// Loads every remaining DB page — call when a view that needs the WHOLE
  /// catalogue opens (the Lasso/map overview). Idempotent: the heavy paginated
  /// load runs once per session, off the startup/first-frame path.
  Future<void> ensureFullCatalogLoaded() async {
    if (_fullCatalogRequested || !_hasMoreProperties) return;
    _fullCatalogRequested = true;
    await _fetchAllRemainingPages();
  }

  /// Fetches all pages after the first one without blocking the UI.
  /// Waits between pages so network bursts don't compete with UI rendering.
  /// Capped at 20 pages (~10 000 properties) to prevent runaway loading.
  Future<void> _fetchAllRemainingPages() async {
    // ~1500 properties is plenty for the lasso/overview; loading up to 10k pushed
    // memory + rebuild cost hard on device. Halved.
    const maxExtraPages = 10;
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
          // Throttle: notifying (and thus re-ranking the whole catalogue on the UI
          // isolate) on EVERY page caused a ~20× rebuild storm during startup — the
          // main freeze. Notify only every few pages; a final notify runs after the
          // loop so the last batch always lands.
          if (pagesLoaded % 4 == 0) notifyListeners();
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
    notifyListeners(); // final refresh with the full preloaded set
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

  static const kSupportedLanguageCodes = ['he', 'en', 'ar', 'fr', 'es'];
  static const kRtlLanguageCodes = ['he', 'ar'];

  String get languageCode => _languageCode;
  bool get isRtl => kRtlLanguageCodes.contains(_languageCode);

  Future<void> setLanguageCode(String code) async {
    if (!kSupportedLanguageCodes.contains(code) || code == _languageCode) {
      return;
    }
    _languageCode = code;
    await _persist();
    notifyListeners();
  }

  Future<void> setUserRole(String role, {bool explicit = false}) async {
    _userRole = role;
    _isGuestMode = false;
    _hasActiveSession = true;
    if (explicit) _roleExplicitlyChosen = true;
    // Don't block the login → home transition on a full catalog re-fetch. The
    // startup already loaded the feed; refresh it in the BACKGROUND (it calls
    // notifyListeners when it lands) so sign-in feels instant.
    unawaited(_refreshRemoteCatalogAfterAuth());
    await _persist();
    AppEvents.instance.log(UserEventType.roleChanged, metadata: {'role': role});
    notifyListeners();
  }

  Future<void> updateBrokerBranding(BrokerBrandingConfig branding) async {
    if (!isBroker) return;
    var config = branding;
    // A locally-picked logo is a device-only file path that gets stripped on
    // remote sync — upload it to S3 so `logoPath` is an https URL that follows
    // the broker across devices.
    final logo = config.logoPath.trim();
    if (logo.isNotEmpty && !logo.startsWith('http')) {
      try {
        final url = await AwsApiClient.instance
            .uploadFile(logo, folder: 'broker/logos');
        if (url != null && url.isNotEmpty) {
          config = config.copyWith(logoPath: url);
        }
      } catch (_) {/* keep the local path as a fallback */}
    }
    _brokerBranding = config;
    await _persist();
    notifyListeners();
    // Cross-device sync (uid-scoped) — fire-and-forget, mirrors the other
    // broker tools' cloud backup.
    unawaited(BrokerCloudSync.instance
        .push('broker_branding', jsonEncode(config.toJson())));
  }

  // Restore the broker's branding from the cloud on login (survives a new
  // device). Kept separate from pullAllToLocal because branding lives in
  // provider state, not a SharedPreferences key.
  Future<void> _pullBrokerBranding() async {
    final raw = await BrokerCloudSync.instance.pull('broker_branding');
    if (raw == null || raw.isEmpty) return;
    try {
      _brokerBranding = BrokerBrandingConfig.fromJson(jsonDecode(raw));
      await _persist();
      notifyListeners();
    } catch (_) {/* keep local branding on a bad blob */}
  }

  Future<void> _refreshRemoteCatalogAfterAuth() async {
    if (_isRefreshingRemoteCatalog) return;
    if (!_hasAuthenticatedFirebaseUser) return;

    _isRefreshingRemoteCatalog = true;
    try {
      // Sign-in just minted a fresh token — use it (getIdToken() returns the
      // cached one), don't force a redundant network refresh that delays login.
      await _firebaseAuthOrNull?.currentUser?.getIdToken();
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

  // Bumped every time a REAL (non-anonymous) sign-in binds successfully — see
  // _ensureAnonymousFirebaseSession for why this exists.
  int _authGeneration = 0;

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
    // BUG THIS GUARDS AGAINST: this call is fire-and-forget from guest mode /
    // cold start and can still be in flight (native signInAnonymously has no
    // real cancellation) when the user completes a REAL sign-in (Google/email)
    // in the meantime. Firebase's signInAnonymously() unconditionally replaces
    // currentUser on success — so a stale anonymous call landing AFTER a real
    // sign-in silently swaps the active session back to a fresh anonymous UID.
    // Every subsequent network call mints its JWT from currentUser at request
    // time, so uploads (e.g. new properties) get stamped under that orphan
    // anonymous UID while the app's local state still shows the real user's
    // data — properties then vanish on the next server-truth reload. Fix:
    // snapshot the auth generation before waiting, and if a real sign-in bound
    // while we waited, discard this stale anonymous session immediately —
    // signed-out-and-401ing on the next call is a visible, recoverable failure,
    // unlike silently writing data under the wrong owner.
    final genBefore = _authGeneration;
    try {
      if (auth.currentUser == null) {
        // 10-second cap: on a slow/offline simulator signInAnonymously can
        // block for the iOS default socket timeout (~60 s). We degrade
        // gracefully — the JWT will be obtained on the next successful call.
        await auth
            .signInAnonymously()
            .timeout(const Duration(seconds: 10));
        if (_authGeneration != genBefore) {
          await auth.signOut();
        }
      }
    } catch (_) {}
  }

  Future<void> enterGuestMode(String role, AppLocalizations l10n) async {
    _seedGuestDemoState(role, l10n);
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
    // Rotates the device-pinned remote-state row (see forgetDeviceRemoteState)
    // so the next account signed in on this device can never inherit this
    // account's synced profile/matches/saved-properties.
    await _localStorageService.forgetDeviceRemoteState();
    _customProperties = [];
    _invalidateCatalogCache();
    _userRole = 'tenant';
    _isGuestMode = false;
    _hasActiveSession = false;
    // Back to the entry flow → must render the neutral teal brand again, even
    // if the user was previously an in-app broker (black). Without this reset a
    // logged-out broker would briefly see black accents on the entry screens.
    _isInsideApp = false;
    // Clear cross-account matching state so the next user who signs in on this
    // device never sees the previous landlord's incoming likes / ranked leads.
    // (_seedInitialState resets accepted/rejected/matches, but not these.)
    _incomingLikesByProperty = {};
    _serverLeadByKey.clear();
    _lastIncomingLikesRefresh = null;
    _swipeHistory.clear();
    _ownerLeadsCache = null;
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

    // 3. Clear all local state and end any residual session — same
    //    device-pinned remote-state rotation as logout() (see
    //    forgetDeviceRemoteState), even more important here since the
    //    account itself is gone and can never come back to overwrite it.
    await _localStorageService.forgetDeviceRemoteState();
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
    // Engine relevance folds in the profile (budget/rooms/persona), so a profile
    // change must drop the cached deck scores — else a match score read next would
    // reflect the OLD profile.
    _engineRelevance = const {};
    await _persist();
    // Sync to discovery table so this user appears in other users' feeds.
    unawaited(_userRepository.upsertProfile(
      updatedProfile,
      role: _userRole,
      discoverable: !_isGuestMode,
    ));
    // Bridge the eligibility-relevant attributes to the backend
    // `users.searchProfile` that the per-listing gate reads. Best-effort and
    // non-blocking: fired unawaited and fully swallowing errors inside
    // updateProfileFields, so it can never block or fail the local save.
    unawaited(_syncEligibilityFields(updatedProfile));
    AppEvents.instance
      ..setUserId(updatedProfile.id)
      ..log(UserEventType.profileUpdated);
    notifyListeners();
  }

  // Maps the tenant profile's eligibility-relevant attributes to the backend
  // searchProfile keys and pushes them via POST /profile/fields. Field map is a
  // LOCKED contract with the gate:
  //   occupation  ← occupation (English key), only if non-null
  //   priceMax    ← budgetMax
  //   minRooms    ← desiredRooms (number)
  //   moveInBucket← moveInBucketOf(moveInWindow) — canonical bucket token
  //   numChildren ← numChildren (only if non-null)
  //   hasPets     ← hasPets (only if non-null)
  //   carFree     ← !hasCar   (INVERTED; omitted when hasCar is null)
  //   wfh              ← wfh              (1:1, only if non-null)
  //   household        ← household        (English key, only if non-null)
  //   lifeStage        ← lifeStage        (English key, only if non-null)
  //   isOleh           ← isOleh           (1:1, only if non-null)
  //   age              ← age              (only if non-null)
  //   accessibilityNeed← accessibilityNeed(1:1, only if non-null)
  // Fully fail-soft: updateProfileFields swallows all errors, so this never
  // blocks the local save.
  Future<void> _syncEligibilityFields(TenantProfile profile) async {
    final fields = <String, dynamic>{
      'priceMax': profile.budgetMax,
      'minRooms': profile.desiredRooms,
      'moveInBucket': moveInBucketOf(profile.moveInWindow),
      if (profile.occupation != null) 'occupation': profile.occupation,
      if (profile.numChildren != null) 'numChildren': profile.numChildren,
      if (profile.hasPets != null) 'hasPets': profile.hasPets,
      if (profile.hasCar != null) 'carFree': !profile.hasCar!,
      if (profile.wfh != null) 'wfh': profile.wfh,
      if (profile.household != null) 'household': profile.household,
      if (profile.lifeStage != null) 'lifeStage': profile.lifeStage,
      if (profile.isOleh != null) 'isOleh': profile.isOleh,
      if (profile.age != null) 'age': profile.age,
      if (profile.accessibilityNeed != null)
        'accessibilityNeed': profile.accessibilityNeed,
    };
    await AwsApiClient.instance.updateProfileFields(fields);
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
    final previousOwnerUserId = _currentOwnerUserId;
    final uid = _firebaseAuthOrNull?.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    // Every caller of this function binds a REAL sign-in (Google/email/
    // session-restore, never anonymous) — bump so any anonymous session still
    // in flight from earlier knows to discard itself if it lands afterward.
    _authGeneration++;

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
    if (isLandlord) {
      _retagCurrentLandlordProperties(
        previousOwnerUserId: previousOwnerUserId,
        nextOwnerUserId: _currentOwnerUserId,
      );
    }
    // Same placeholder-id problem as the property retag above, but for the
    // TENANT side: a match created (via _createMatch) while this device's
    // profile.id was still a placeholder gets an id like
    // match-<propertyId>~guest_tenant, which the real account's uid never
    // matches — so a landlord who approved a lead from a not-yet-signed-in
    // tenant leaves that tenant's own app with no visible conversation, ever,
    // even after the tenant signs in. Retag every local match still keyed to
    // a placeholder and push the correction to the server.
    _retagCurrentTenantMatches(
      previousTenantUid: previousOwnerUserId,
      nextTenantUid: _currentOwnerUserId,
    );

    // Backfill any candidate rejection made before this sync existed (or
    // before real sign-in) — safe to repeat every time: the server write is
    // a plain idempotent flag set, not a create, so there's no "already
    // synced, don't touch it again" concern like the message backfill above.
    if (isLandlord) {
      for (final key in _ownerRejectedPropertyIds) {
        final parts = key.split('|');
        if (parts.length != 2 || parts[1].isEmpty) continue;
        unawaited(_syncLeadRejectionToBackend(propertyId: parts[0], tenantId: parts[1]));
      }
    }

    // Backfill likes made while this device's profile.id was still a
    // placeholder (see _syncPropertyLike) — ONLY when the previous id was
    // actually a placeholder, not on every sign-in, since re-pushing a large
    // like history every time would be unbounded, wasted network calls.
    final wasPlaceholder = _legacyOwnerPlaceholders.contains(previousOwnerUserId) ||
        previousOwnerUserId.startsWith('guest_');
    if (wasPlaceholder && previousOwnerUserId != _currentOwnerUserId) {
      final now = DateTime.now();
      for (final propertyId in _likedPropertyIds) {
        unawaited(_syncPropertyLike(propertyId, now));
      }
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

    // Pull in saves made on another device (or before toggleSave synced them
    // at all, pre-fix) — union with the local set, never a destructive
    // overwrite, so a save made offline on THIS device isn't dropped.
    final savedRemote = await InteractionService.instance.fetchSaved();
    if (savedRemote.isNotEmpty) {
      _savedPropertyIds = {..._savedPropertyIds, ...savedRemote};
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

    // Refresh the subscription snapshot so the publish paywall gate is accurate
    // for this landlord. Fail-soft (refreshSubscription never throws).
    if (isLandlord) unawaited(refreshSubscription());
  }

  // Known placeholder owner ids _currentOwnerUserId has ever handed out
  // before a real Firebase uid was bound. A property can be stuck under one
  // of these from a PAST sign-in even when previousOwnerUserId (this run's
  // pre-bind value) is already the real uid — e.g. the local device cache
  // still holds a row from before this retag existed, or from before the
  // user ever signed in this session. Sweeping all of them (not just
  // previousOwnerUserId) is what actually heals already-broken data.
  static const Set<String> _legacyOwnerPlaceholders = {
    _guestLandlordOwnerId,
    _localLandlordOwnerId,
    'tenant-local',
  };

  void _retagCurrentLandlordProperties({
    required String previousOwnerUserId,
    required String nextOwnerUserId,
  }) {
    if (nextOwnerUserId.trim().isEmpty) return;

    // Rows saved under a placeholder owner id (guest mode's 'guest_landlord',
    // or the pre-sign-in 'local_landlord'/'tenant-local' fallbacks in
    // _currentOwnerUserId) only got fixed HERE, in memory — the DB row kept
    // the placeholder forever. That made the listing invisible to any query
    // keyed on the real uid (the website's "my properties", /match/leads,
    // another device signing into the same account), even though this
    // device's own local cache looked correct. Push the corrected owner id
    // back to the server for every row this retags, not just locally.
    final retagged = <RentalProperty>[];
    _customProperties = _customProperties.map((property) {
      if (_isGuestDemoProperty(property)) return property;
      final ownerUserId = property.ownerUserId.trim();
      final isStale = ownerUserId.isEmpty ||
          ownerUserId == previousOwnerUserId ||
          _legacyOwnerPlaceholders.contains(ownerUserId);
      if (!isStale || ownerUserId == nextOwnerUserId) return property;
      final retaggedProperty = property.copyWith(ownerUserId: nextOwnerUserId);
      retagged.add(retaggedProperty);
      return retaggedProperty;
    }).toList(growable: false);

    if (retagged.isEmpty) return;
    _invalidateCatalogCache();
    for (final property in retagged) {
      unawaited(
        _propertyRepository
            .saveProperty(
              property,
              ownerUserId: nextOwnerUserId,
              status: property.isActive
                  ? PropertyRecordStatus.active
                  : PropertyRecordStatus.paused,
            )
            .then((result) {
          if (!result.isOk && kDebugMode) {
            debugPrint(
                '_retagCurrentLandlordProperties: remote rejected ${property.id} — ${result.userMessage}');
          }
        }),
      );
    }
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
  // Returns whether the property actually landed on the server. Previously
  // fire-and-forget (unawaited): the UI showed "published successfully" and
  // navigated away regardless of whether the write really succeeded, with no
  // retry/reconciliation — a transient network failure or rejected write
  // silently vanished, and the landlord had no idea their listing was never
  // actually live anywhere but their own device. The optimistic local add
  // still happens immediately (so the UI updates without waiting on the
  // network), but is ROLLED BACK if the server write fails, and the caller
  // now gets an honest answer to gate its success/error feedback on.
  Future<bool> addLandlordProperty(
    RentalProperty property, {
    PropertyRecordStatus status = PropertyRecordStatus.active,
  }) async {
    final ownedProperty = _ownedByCurrentLandlord(property);
    _customProperties = [..._customProperties, ownedProperty];
    _invalidateCatalogCache();
    await _persist();
    notifyListeners();
    final result = await _propertyRepository.saveProperty(ownedProperty,
        ownerUserId: ownedProperty.ownerUserId, status: status);
    if (result.isRealFailure) {
      if (kDebugMode) {
        debugPrint(
            'addLandlordProperty: remote rejected — ${result.userMessage}');
      }
      _customProperties =
          _customProperties.where((p) => p.id != ownedProperty.id).toList();
      _invalidateCatalogCache();
      await _persist();
      notifyListeners();
      return false;
    }
    AppEvents.instance.log(
      UserEventType.propertyAdded,
      propertyId: ownedProperty.id,
      metadata: {
        'city': ownedProperty.city,
        'type': ownedProperty.propertyType,
        'status': status.name,
      },
    );
    return true;
  }

  // See addLandlordProperty's doc — same await-and-report-honestly fix, same
  // rollback-on-failure. Also closes a second bug: previously this early-
  // returned `void` when the property no longer existed locally (e.g. it was
  // just deleted elsewhere), so a caller editing a stale/deleted property saw
  // NO signal that nothing happened and showed "saved successfully" anyway.
  Future<bool> updateLandlordProperty(RentalProperty updated) async {
    final existing = _customPropertyById(updated.id);
    if (existing == null || !_belongsToCurrentLandlord(existing)) return false;
    final ownedProperty = _ownedByCurrentLandlord(updated);
    _customProperties = _customProperties
        .map((p) => p.id == ownedProperty.id ? ownedProperty : p)
        .toList();
    _invalidateCatalogCache();
    await _persist();
    notifyListeners();
    final result = await _propertyRepository.saveProperty(
      ownedProperty,
      ownerUserId: ownedProperty.ownerUserId,
      status: ownedProperty.isActive
          ? PropertyRecordStatus.active
          : PropertyRecordStatus.paused,
      // Optimistic-locking token — see PropertyRepository.saveProperty. If
      // another device edited this property since `existing` was last
      // fetched, the server rejects with 409/conflict instead of silently
      // letting this stale edit clobber the newer changes.
      expectedUpdatedAt: existing.serverUpdatedAt,
    );
    if (result.isRealFailure) {
      if (kDebugMode) {
        debugPrint(
            'updateLandlordProperty: remote rejected — ${result.userMessage}');
      }
      _customProperties = _customProperties
          .map((p) => p.id == existing.id ? existing : p)
          .toList();
      _invalidateCatalogCache();
      await _persist();
      notifyListeners();
      return false;
    }
    AppEvents.instance
        .log(UserEventType.propertyUpdated, propertyId: ownedProperty.id);
    return true;
  }

  // See addLandlordProperty's doc — same fix. On failure the property (and
  // its base-catalog copy) is restored rather than staying "deleted" locally
  // while still live server-side, which previously could make a property
  // silently "resurrect" on the next reload with no explanation.
  Future<bool> removeLandlordProperty(String propertyId) async {
    final existing = _customPropertyById(propertyId);
    if (existing == null || !_belongsToCurrentLandlord(existing)) return false;
    final previousCustomProperties = _customProperties;
    final previousBaseProperties = _baseProperties;
    _customProperties =
        _customProperties.where((p) => p.id != propertyId).toList();
    // Also drop the copy that lives in the PUBLIC base catalog — otherwise the
    // already-materialized _baseProperties snapshot keeps showing the removed
    // listing in this device's search/map/deck until a relaunch.
    _baseProperties =
        _baseProperties.where((p) => p.id != propertyId).toList();
    _invalidateCatalogCache();
    // Drop it from the browse/search cache immediately so seekers stop seeing it.
    AppCache.instance.propertyPages.clear();
    await _persist();
    notifyListeners();
    // SOFT delete: keep the row in the DB (audit/history) but flip its status off
    // 'active' so apartment-seekers no longer see it in search/discovery.
    final result = await _propertyRepository.saveProperty(existing,
        ownerUserId: existing.ownerUserId,
        status: PropertyRecordStatus.removed);
    if (result.isRealFailure) {
      if (kDebugMode) {
        debugPrint(
            'removeLandlordProperty: remote rejected — ${result.userMessage}');
      }
      _customProperties = previousCustomProperties;
      _baseProperties = previousBaseProperties;
      _invalidateCatalogCache();
      AppCache.instance.propertyPages.clear();
      await _persist();
      notifyListeners();
      return false;
    }
    return true;
  }

  // Stamp a boost window on a listing IN MEMORY right after a successful server
  // boost, so it floats to the top of the feed this session (isBoosted reads
  // boostedUntil) without waiting for a full server refetch.
  void applyLocalBoost(String propertyId, DateTime boostedUntil,
      {PropertyBoostTier tier = PropertyBoostTier.regular}) {
    var changed = false;
    List<RentalProperty> stamp(List<RentalProperty> list) => list.map((p) {
          if (p.id != propertyId) return p;
          changed = true;
          return p.copyWith(boostedUntil: boostedUntil, boostTier: tier);
        }).toList();
    _customProperties = stamp(_customProperties);
    _baseProperties = stamp(_baseProperties);
    if (changed) {
      _invalidateCatalogCache();
      notifyListeners();
    }
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

  /// APPENDS a finished scan as a ROOM to the property's 3D model, instead of
  /// replacing the whole model3d. This is what makes background multi-room
  /// completion work: two rooms finished off-screen both land in model3d.rooms
  /// rather than the second overwriting the first. Deduped by asset url so a
  /// re-run of the finalizer can't double-add. Also mirrors the first viewable
  /// room into the legacy single-scan urls for back-compat readers.
  Future<void> appendScanRoom({
    required String propertyId,
    required ScannedRoom room,
  }) async {
    if (!room.hasViewableAsset) return;
    var changed = false;
    final updated = _customProperties.map((property) {
      if (property.id != propertyId) return property;
      if (!_belongsToCurrentLandlord(property)) return property;
      final current = property.model3d ?? const PropertyModel3d();
      final dup = current.rooms.any((r) =>
          (room.splatUrl != null && r.splatUrl == room.splatUrl) ||
          (room.meshGlbUrl != null && r.meshGlbUrl == room.meshGlbUrl));
      if (dup) return property;
      final rooms = [...current.rooms, room];
      final firstViewable =
          rooms.firstWhere((r) => r.hasViewableAsset, orElse: () => room);
      changed = true;
      return property.copyWith(
        model3d: current.copyWith(
          rooms: rooms,
          glbUrl: firstViewable.meshGlbUrl ?? current.glbUrl,
          plyUrl: firstViewable.splatUrl ?? current.plyUrl,
          scanDate: DateTime.now().toUtc(),
        ),
      );
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
          debugPrint('appendScanRoom: remote rejected — ${result.userMessage}');
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
      // Give-up guard: a KIRI job finishes well within an hour. A record older
      // than this is either stuck server-side or its backend meta is gone (a 404
      // the client can't distinguish from 'processing'). Drop it so it stops
      // polling forever instead of lingering until the 12h store purge.
      final submitted = scan.submittedAt;
      if (submitted != null &&
          DateTime.now().toUtc().difference(submitted.toUtc()) >
              const Duration(minutes: 90)) {
        await PendingScanStore.instance.remove(scan.jobId);
        continue;
      }
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
          // APPEND as a room (multi-room safe) — no name was known at submit
          // time (naming happens after the scan), so default to the next number.
          final existing =
              _customPropertyById(scan.propertyId)?.model3d?.rooms.length ?? 0;
          // No hardcoded Hebrew default here — this provider has no
          // BuildContext to localize with. An empty name falls back to a
          // localized "Room N" label at the widget layer (scan3d_viewer.dart,
          // room_scan_flow.dart).
          final name = scan.roomName;
          await appendScanRoom(
            propertyId: scan.propertyId,
            room: ScannedRoom(
              name: name,
              meshGlbUrl: job.meshGlbUrl,
              splatUrl: job.splatUrl,
              source: 'cloud',
            ),
          );
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

  // In-memory: when a Gaussian-splat scan was just imported, the server is
  // converting the heavy .ply into a fast .ksplat (~30-60s). Drives the
  // "מעבד… (timer)" notice on the listing. Auto-expires after 3 min so it never
  // sticks even if we miss the completion signal.
  final Map<String, DateTime> _scanOptimizingSince = {};

  /// Mark that [propertyId]'s scan is optimizing (server .ksplat conversion).
  void markScanOptimizing(String propertyId) {
    if (propertyId.trim().isEmpty) return;
    _scanOptimizingSince[propertyId] = DateTime.now();
    notifyListeners();
  }

  /// When optimization started for [propertyId], or null if it isn't optimizing
  /// (or the ~3-min window elapsed). Prunes stale entries.
  DateTime? scanOptimizingSince(String propertyId) {
    final t = _scanOptimizingSince[propertyId];
    if (t == null) return null;
    if (DateTime.now().difference(t).inMinutes >= 3) {
      _scanOptimizingSince.remove(propertyId);
      return null;
    }
    return t;
  }

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
    // SCALE: this polled every 15s and fired heartbeatViewSession (a write) PLUS
    // refreshPropertySignals (TWO 200-row queries) each tick — ~20k req/s at
    // 500k viewers, and O(V²) reads on a viral listing. Now every 60s, and the
    // heavy signal refresh only on alternate ticks (~every 2 min): live counts
    // change slowly, so this is an 8× cut in the heavy reads with no real UX loss.
    var tick = 0;
    session.heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) {
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
      if (tick++ % 2 == 0) unawaited(refreshPropertySignals(propertyId));
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
    // A detail open is a 'click' outcome for the search that surfaced the card.
    _postSearchOutcome(propertyId, 'click');
    notifyListeners();
  }

  /// A user initiated contact on [propertyId] (strongest funnel outcome). Fires
  /// the search 'contact' label; [viewToContactMs] carries the dwell-to-contact.
  /// Best-effort/non-blocking — safe to call from the detail-screen contact path.
  void recordContactOutcome(
    String propertyId, {
    int? viewToContactMs,
    String? entrySource,
    int? entryRank,
  }) {
    _postSearchOutcome(propertyId, 'contact', dwellMs: viewToContactMs);
    // Strongest engagement action for the per-property interaction store.
    final property = propertyById(propertyId);
    unawaited(InteractionService.instance.record(
      propertyId: propertyId,
      action: 'contact',
      dwellMs: viewToContactMs,
      entrySource: entrySource,
      entryRank: entryRank,
      // Listing size → backend length-normalizes dwell.
      mediaCount: property == null ? null : _mediaCountOf(property),
      descLen: property == null ? null : _descLenOf(property),
    ));
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
    unawaited(_syncPropertyLike(propertyId, now));
    unawaited(refreshPropertySignals(propertyId));
  }

  /// Cross-user like: writes the row the property's landlord can read, so a
  /// like from this device is visible to the owner on theirs. Don't like your
  /// own. Split out from [_recordPropertyLike] so [_bindFirebaseIdentity] can
  /// re-run just the sync (not the local like-counter bump) to retag a like
  /// made while this device's profile.id was still a placeholder — same
  /// problem as properties/matches, but there's no local "pending like"
  /// record to rewrite in place, so this just re-submits under the real uid
  /// (a deterministic id per (propertyId, tenantId) — an upsert, never a
  /// duplicate — the stale placeholder-id row is simply orphaned, not deleted).
  Future<void> _syncPropertyLike(String propertyId, DateTime at) async {
    final property = propertyById(propertyId);
    if (property == null ||
        property.ownerUserId.isEmpty ||
        property.ownerUserId == _currentOwnerUserId) {
      return;
    }
    // Snapshot the tenant's REAL attributes into the like so they reach the
    // landlord's candidate deck (and its filters) cross-device. Fail-soft:
    // when there's no profile in scope, every extra field stays null and the
    // payload is identical to an old-style like.
    final tp = _tenantProfile;
    await _propertyLikesRepository.addLike(
      propertyId: propertyId,
      ownerUserId: property.ownerUserId,
      tenantId: _currentAnalyticsUserId,
      // No hardcoded Hebrew placeholder — leave blank when the tenant has no
      // name yet. Every UI consumer of PropertyLike.tenantName (see
      // explore_screen.dart's `displayName` getter) already falls back to a
      // locally-known name when this is empty, so an empty string here is
      // safe and correctly localized at render time.
      tenantName: tp?.name ?? '',
      tenantPhotoUrl:
          tp?.photoUrls.isNotEmpty == true ? tp!.photoUrls.first : '',
      moveInSnapshot: tp?.moveInWindow ?? '',
      budgetMax: tp?.budgetMax,
      rooms: tp?.desiredRooms,
      occupation: tp?.occupation,
      numChildren: tp?.numChildren,
      hasPets: tp?.hasPets,
      hasCar: tp?.hasCar,
      wfh: tp?.wfh,
      household: tp?.household,
      lifeStage: tp?.lifeStage,
      monthlyIncome: tp?.monthlyIncome,
      age: tp?.age,
      isOleh: tp?.isOleh,
      smoker: tp?.smoker,
      hasGuarantor: tp?.hasGuarantor,
      leaseMonths: tp?.leaseMonths,
      incomeProofReady: tp?.incomeProofReady,
      religiousLifestyle: tp?.religiousLifestyle,
      shabbatObservant: tp?.shabbatObservant,
      keepsKosher: tp?.keepsKosher,
      petType: tp?.petType,
      hostsGuests: tp?.hostsGuests,
      playsInstrument: tp?.playsInstrument,
      urgency: tp?.urgency,
      workLat: tp?.workLat,
      workLon: tp?.workLon,
      // No explicit tenant "verified" flag exists; derive it from the app's
      // real trust signal (photo/bio/budget/etc.), the same score shown in
      // the profile. Only stamped when there's a profile to score.
      verified: tp == null
          ? null
          : GamificationService.computeTrustScore(tp, const []) >= 70,
      at: at,
    );
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
      // null = fetch failed → don't clobber the real persisted counts with 0.
      if (views == null || likes == null) return;
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
      // Undoing a super-like gives the quota back.
      if (last.superLike) {
        await GamificationService.refundSuperLike();
        _remainingSuperLikes =
            await GamificationService.getRemainingSuperlikes();
      }
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
    CardSwiperDirection direction, {
    RentalProperty? swiped,
    required AppLocalizations l10n,
  }) async {
    // The swiper now advances a STABLE deck snapshot, so [previousIndex] indexes
    // that snapshot, not the live (shrinking) filteredProperties. The caller
    // passes the exact [swiped] property — use it directly. Fall back to the
    // index only for any legacy caller that still relies on it.
    final RentalProperty property;
    if (swiped != null) {
      property = swiped;
    } else {
      final deck = filteredProperties;
      if (previousIndex < 0 || previousIndex >= deck.length) return false;
      property = deck[previousIndex];
    }
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
      _recordSwipeSignal(property, SwipeDirection.skip,
          dwellMs: decisionMs, entryRank: previousIndex);
      // Phase-1: the swipe IS the primary label. A left-swipe is the NEGATIVE
      // class for the learned ranker (previously only click/contact were sent,
      // so the training set had zero negatives-vs-positives balance). Log the
      // discover impression + join the label to it via the session searchId.
      _logDiscoverImpression(property, previousIndex);
      _postOutcomeWith(_discoverSearchId, property.id, 'skip',
          dwellMs: decisionMs);
    } else if (direction == CardSwiperDirection.right ||
        direction == CardSwiperDirection.top) {
      final isNewLike = _likedPropertyIds.add(property.id);
      if (isNewLike) _recordPropertyLike(property.id);
      final isSuperLike = direction == CardSwiperDirection.top;
      _swipeHistory.add(_SwipeRecord(
          propertyId: property.id, liked: true, superLike: isSuperLike));
      final eventType =
          isSuperLike ? UserEventType.superLike : UserEventType.swipeRight;
      AppEvents.instance.log(eventType, propertyId: property.id);
      _recordSwipeSignal(
        property,
        isSuperLike ? SwipeDirection.superlike : SwipeDirection.like,
        dwellMs: decisionMs,
        entryRank: previousIndex,
      );
      // Phase-1: a right/up-swipe is the POSITIVE class — the label the model
      // learns to predict. Log the discover impression + join the label to it.
      _logDiscoverImpression(property, previousIndex);
      _postOutcomeWith(_discoverSearchId, property.id,
          isSuperLike ? 'superlike' : 'like',
          dwellMs: decisionMs);
      // Phase-2: refresh the server user vector as likes accumulate (debounced).
      _maybeRefreshUserEmbedding();

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
          _ownerAcceptedPropertyIds.add(_ownerActionKey(property.id, ''));
          _createMatch(property, l10n: l10n);
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
    int? entryRank,
  }) {
    final now = DateTime.now();
    // Upsert the swipe decision to the per-property interaction store: the
    // deck is where these cards were surfaced, [entryRank] is their deck slot,
    // and [dwellMs] the time-to-decision. Best-effort / non-blocking.
    unawaited(InteractionService.instance.record(
      propertyId: property.id,
      action: switch (direction) {
        SwipeDirection.superlike => 'superlike',
        SwipeDirection.like => 'like',
        SwipeDirection.skip => 'pass',
      },
      dwellMs: dwellMs,
      entrySource: 'deck',
      entryRank: entryRank,
      // Listing size → backend length-normalizes dwell.
      mediaCount: _mediaCountOf(property),
      descLen: _descLenOf(property),
    ));
    final ratio = _priceToBudgetRatio(property);
    final liked = direction != SwipeDirection.skip;

    // ── Close the FTRL loop: feed this real swipe into the online learner using
    // the feature vector stashed when the listing was ranked (O(1), no recompute).
    // Main-deck cards are NOT surfaced via search, so their vector is absent —
    // compute it lazily for just this one property (same engine feature path) so
    // deck swipes become training examples too. The learner is persisted with the
    // rest of the state (see _persist / restore).
    final feats = _ensureLearnerFeatures(property);
    if (feats != null) _learner.update(feats, liked ? 1.0 : 0.0);

    AppEvents.instance.service.logSwipeOutcome(
      propertyId: property.id,
      direction: direction,
      priceToBudgetRatio: ratio,
      dwellMs: dwellMs,
      predictedFit: _deckMatchScore[property.id]?.toDouble(),
      searchId: _lastSearchId,
    );
    // Real training label for the search that surfaced this card (best-effort).
    _postSearchOutcome(
      property.id,
      switch (direction) {
        SwipeDirection.superlike => 'superlike',
        SwipeDirection.like => 'like',
        SwipeDirection.skip => 'skip',
      },
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

  void toggleAutoLike(AppLocalizations l10n) {
    _autoLikeEnabled = !_autoLikeEnabled;
    if (_autoLikeEnabled) {
      _processAutoLikes(l10n);
    }
    _persist();
    notifyListeners();
  }

  void setTabIndex(int index) {
    _currentTabIndex = index;
    notifyListeners();
  }

  /// Bumped when the user taps the apartment-search tab, so DiscoverScreen resets
  /// to the swipe deck (instead of whatever view — grid/map — it was left on).
  int _discoverSwipesSignal = 0;
  int get discoverSwipesSignal => _discoverSwipesSignal;
  void requestDiscoverSwipes() {
    _discoverSwipesSignal++;
    notifyListeners();
  }

  void _processAutoLikes(AppLocalizations l10n) {
    final leads = ownerLeads;
    if (leads.isEmpty) return;

    for (final property in leads) {
      final tenantId = _acceptedTenantOf(property) ?? '';
      _ownerAcceptedPropertyIds.add(_ownerActionKey(property.id, tenantId));
      _createMatch(property,
          tenantUserId: tenantId.isEmpty ? null : tenantId, l10n: l10n);
    }
  }

  /// The tenant uid the chat thread should connect to when the landlord accepts
  /// a lead. This MUST be the candidate the landlord actually saw on the card —
  /// the best-fit "representative" liker (same one scored/shown) — not an
  /// arbitrary first liker, or the landlord would end up matched with a
  /// different tenant than the one they chose.
  String? _acceptedTenantOf(RentalProperty property) =>
      _representativeLikerFor(property)?.tenantId ?? _firstLikerOf(property.id);

  String? _firstLikerOf(String propertyId) {
    final likers = _incomingLikesByProperty[propertyId];
    return (likers != null && likers.isNotEmpty) ? likers.first.tenantId : null;
  }

  Future<bool> handleOwnerSwipe(
    int previousIndex,
    int? currentIndex,
    CardSwiperDirection direction, {
    List<RentalProperty>? visibleLeads,
    required AppLocalizations l10n,
  }) async {
    // Resolve the swiped index against the EXACT list the deck rendered. When
    // the candidate filters are active the deck shows a subset of [ownerLeads],
    // so falling back to the full list here would accept/reject the wrong
    // property. Defaults to [ownerLeads] for the unfiltered path (identical).
    final leads = visibleLeads ?? ownerLeads;
    if (previousIndex < 0 || previousIndex >= leads.length) return false;

    final property = leads[previousIndex];
    // Key the decision to the SPECIFIC candidate shown (not the whole property),
    // so other likers on the same property stay actionable.
    final tenantId = _acceptedTenantOf(property) ?? '';
    final key = _ownerActionKey(property.id, tenantId);
    if (direction == CardSwiperDirection.left) {
      _ownerRejectedPropertyIds.add(key);
      // Used to be LOCAL ONLY — the same candidate reappeared as pending on
      // any other device or the website, since the rejection never reached
      // the server. Fire-and-forget; the local hide above is unchanged.
      if (tenantId.isNotEmpty) {
        unawaited(_syncLeadRejectionToBackend(
          propertyId: property.id,
          tenantId: tenantId,
        ));
      }
    } else if (direction == CardSwiperDirection.right ||
        direction == CardSwiperDirection.top) {
      _ownerAcceptedPropertyIds.add(key);
      _createMatch(property,
          tenantUserId: tenantId.isEmpty ? null : tenantId, l10n: l10n);
    } else {
      return false;
    }

    await _persist();
    notifyListeners();
    return true;
  }

  /// POSTs a landlord's candidate rejection so it's dismissed everywhere (see
  /// handleOwnerSwipe's left-swipe branch). Fail-soft: the local hide already
  /// happened regardless.
  Future<void> _syncLeadRejectionToBackend({
    required String propertyId,
    required String tenantId,
  }) async {
    try {
      await AwsApiClient.instance.post('/match/reject', {
        'propertyId': propertyId,
        'tenantId': tenantId,
      });
    } catch (_) {/* fail-soft */}
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

  /// Resolves a listing by id for deep links: returns the in-memory copy when
  /// the catalog already holds it, otherwise fetches it straight from the
  /// backend (so shared links to listings not currently loaded still open the
  /// apartment). Fail-soft — null when the id is unknown/removed.
  Future<RentalProperty?> fetchPropertyById(String id) async {
    final local = propertyById(id);
    if (local != null) return local;
    return _propertyRepository.fetchProperty(id);
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

  /// Landlord drafts + sends a rental contract for a match. [l10n] is
  /// required only to localize the fallback names/chat text below — this
  /// provider has no BuildContext of its own, so every caller (a widget with
  /// context) passes its own `AppLocalizations.of(context)!`.
  Future<RentalContract?> createRentalContract({
    required String matchId,
    required int monthlyRent,
    required int deposit,
    required int durationMonths,
    required DateTime startDate,
    required String terms,
    required AppLocalizations l10n,
  }) async {
    final match = matchById(matchId);
    final property = propertyById(match?.propertyId ?? '');
    if (match == null || property == null) return null;

    final landlordUserId = property.ownerUserId.isNotEmpty
        ? property.ownerUserId
        : _currentOwnerUserId;
    final landlordName = property.ownerName.isNotEmpty
        ? property.ownerName
        : (_tenantProfile?.name ?? l10n.datingProviderLandlordFallbackName);

    final likes = incomingLikesFor(property.id);
    final tenantLike = likes.isNotEmpty ? likes.first : null;
    final tenantUserId = tenantLike?.tenantId ?? _firstLikerOf(property.id) ?? '';
    final tenantName = (tenantLike?.tenantName.isNotEmpty ?? false)
        ? tenantLike!.tenantName
        : l10n.datingProviderTenantFallbackName;

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
              text: l10n.datingProviderContractSentMessage(
                  monthlyRent, durationMonths),
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
  /// the device) plus an optional handwritten signature image. [l10n] is
  /// required only to localize the fallback name/chat text below — this
  /// provider has no BuildContext of its own, so every caller (a widget with
  /// context) passes its own `AppLocalizations.of(context)!`.
  Future<RentalContract?> signRentalContract(
    RentalContract contract, {
    required bool asOwner,
    required AppLocalizations l10n,
    Uint8List? signatureImage,
  }) async {
    final role = asOwner ? 'landlord' : 'tenant';
    final signerName = asOwner
        ? (contract.landlordName.isNotEmpty
            ? contract.landlordName
            : l10n.datingProviderLandlordFallbackName)
        : (_tenantProfile?.name ??
            (contract.tenantName.isNotEmpty
                ? contract.tenantName
                : l10n.datingProviderTenantFallbackName));

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
                  ? l10n.datingProviderSignedAsLandlord
                  : l10n.datingProviderSignedAsTenant,
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
    final bool saved;
    if (_savedPropertyIds.contains(propertyId)) {
      _savedPropertyIds.remove(propertyId);
      saved = false;
    } else {
      _savedPropertyIds.add(propertyId);
      saved = true;
    }
    // Capture the favorite/unfavorite as a behavioral signal (best-effort). The
    // local set + persistence above is unchanged; this only adds the event.
    AppEvents.instance.service
        .logSaveToggled(propertyId: propertyId, saved: saved);
    // This used to be LOCAL ONLY — it looked saved immediately but never
    // reached the backend, so the list never appeared on another device, the
    // website, or survived a reinstall. Fire-and-forget, always keyed by the
    // verified caller uid server-side (never a stale placeholder).
    unawaited(InteractionService.instance.record(
      propertyId: propertyId,
      action: saved ? 'save' : 'unsave',
    ));
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
  /// Phase-3: the LOOK-ALIKE audience for one of the landlord's listings — how
  /// many tenants in the population are the best-fit target (by embedding
  /// similarity), and their scores. Returns (count, topScore%) — empty/0 when
  /// the server ranking is dormant (no user vectors yet) or off-network.
  Future<({int count, int topScore})> fetchListingAudience(String propertyId,
      {int topK = 25}) async {
    if (propertyId.isEmpty || !AwsApiClient.instance.isConfigured) {
      return (count: 0, topScore: 0);
    }
    try {
      final res = await AwsApiClient.instance.post(
        '/listing/audience',
        {'propertyId': propertyId, 'topK': topK},
      );
      final list = res['audience'];
      final count = (res['audienceCount'] as num?)?.toInt() ??
          (list is List ? list.length : 0);
      int top = 0;
      if (list is List && list.isNotEmpty) {
        final first = list.first;
        if (first is Map) top = (first['score'] as num?)?.toInt() ?? 0;
      }
      return (count: count, topScore: top);
    } catch (error) {
      if (kDebugMode) debugPrint('fetchListingAudience: $error');
      return (count: 0, topScore: 0);
    }
  }

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

  /// Build the engine's [SearchQuery] from the current filter state so the deck
  /// is ranked by the SAME RecommendationEngine relevance as the search surface.
  /// Only real, user-set constraints are mapped (an unset budget/rooms stays null
  /// so the engine uses its priors, not a synthetic ceiling).
  SearchQuery _queryFromFilters(SearchFilters f) {
    final type = f.transactionType;
    final hasMaxBudget =
        f.maxBudget > 0 && f.maxBudget < _defaultMaxBudgetFor(type);
    return SearchQuery(
      city: f.city.trim().isEmpty ? null : f.city.trim(),
      minPrice: f.minBudget > 0 ? f.minBudget : null,
      maxPrice: hasMaxBudget ? f.maxBudget : null,
      minRooms: f.minRooms > 0 ? f.minRooms : null,
      maxRooms: f.maxRooms > 0 && f.maxRooms < _unsetMaxRooms ? f.maxRooms : null,
      amenities: {...f.requiredFeatures, ...f.preferredFeatures},
      requiredFeatures: f.requiredFeatures,
      transactionType: type,
      propertyType: f.propertyTypes.isNotEmpty ? f.propertyTypes.first : null,
      // Boost the ranking dimensions for the nearby-place categories the seeker
      // marked important (vets/parking map to null → display-only, skipped).
      preferredNearbyDims:
          f.preferredNearby.map(nearbyKindToDimension).whereType<String>().toSet(),
    );
  }

  /// The unified engine relevance for [p] under [filters]: the cached deck value
  /// when available (the common path — a sort just computed the whole deck), else
  /// an on-demand single-property score against the full-catalogue baseline.
  double _engineRelevanceFor(RentalProperty p, SearchFilters filters) {
    final cached = _engineRelevance[p.id];
    if (cached != null) return cached;
    final rel = RecommendationEngine.relevance(
      candidates: [p],
      query: _queryFromFilters(filters),
      profile: _tenantProfile,
      marketSource: _allProperties,
    );
    return rel[p.id] ?? 0.5;
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

    // UNIFIED STRUCTURAL CORE: the deck's budget/value/location/size/amenities/
    // trust fit is now the SAME RecommendationEngine relevance that ranks the
    // search surface — one scoring brain, so the deck inherits the engine's
    // catalogue-wide value baseline, block-level gov geo (stat-areas/centrality/
    // safety) and de-collinearity instead of the old hand-tuned sub-scores. It's
    // mapped into the same [0, _structuralCeiling] band, leaving headroom for the
    // deck-unique business layer added AFTER: two-sided tenant↔landlord tag
    // compatibility and the on-device learned deltas. (The gov-geo nudge that used
    // to live here is gone — the engine already accounts for it.)
    final relevance = _engineRelevanceFor(p, filters); // 0..1 honest search-fit
    final compressed = relevance * _structuralCeiling;
    final score = compressed +
        tagCompatibilityScore +
        _learnedScoreDelta(p) +
        // Collaborative-filtering nudge: gently lift listings that users with
        // similar behaviour engaged with. Bounded like the learned deltas so it
        // complements — never dominates — the structural fit.
        _cfBoost(p.id) +
        // Business-readiness (verification / media richness / completeness) is a
        // real listing-quality signal ORTHOGONAL to search-fit — kept as a small
        // post-band bonus so a verified, well-documented listing still edges out a
        // bare one at the same fit.
        _listingConfidenceScore(p);

    return _clampDouble(score, 0, 100).round();
  }


  /// Ordered collaborative-filtering recommendations (highest cfScore first),
  /// exposed so a "מומלץ בשבילך" section can surface them. Empty until
  /// [loadCfRecommendations] has run.
  List<String> get cfRecommendedIds => List.unmodifiable(_cfRecommendedIds);

  /// Fetches CF recommendations from the backend and stores them (ordered) so
  /// [_cfBoost] can gently lift them in the deck sort and a future recommended
  /// section can list them. Fail-soft: leaves the current set intact on error /
  /// empty response, and never throws.
  Future<void> loadCfRecommendations({int limit = 20}) async {
    try {
      final ids = await InteractionService.instance.cfRecommendations(limit: limit);
      if (ids.isEmpty) return;
      _cfRecommendedIds = ids;
      _cfRank = {for (var i = 0; i < ids.length; i++) ids[i]: i};
      _invalidateFilterCache(); // deck score depends on CF now → re-sort
      notifyListeners();
    } catch (_) {/* fail-soft */}
  }

  /// The bounded CF boost for [propertyId]: the top CF pick gets [_maxCfBoost],
  /// decaying linearly to 0 across the CF list, 0 for anything not recommended.
  double _cfBoost(String propertyId) {
    final rank = _cfRank[propertyId];
    if (rank == null) return 0;
    final n = _cfRecommendedIds.length;
    if (n <= 0) return 0;
    return _maxCfBoost * (1 - rank / n);
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

  // A perfect structural fit maps to this score, reserving the remaining
  // headroom up to 100 for honest persona/tag boosts.
  static const double _structuralCeiling = 88;

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

  void _seedGuestDemoState(String role, AppLocalizations l10n) {
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
        // Demo 360° tour: one point with TWO real renders (from the sample
        // panoramas) so guests can try the in-viewer version switcher.
        panoramaTour: const PropertyPanoramaTour(nodes: [
          PanoramaNode(
            id: 'demo-node-1',
            imageUrl: 'asset://assets/demo/office_360_v1.jpg',
            label: 'הסלון',
            activeVersion: 0,
            versions: [
              PanoVersion(
                imageUrl: 'asset://assets/demo/office_360_v1.jpg',
                source: 'מקור',
              ),
              PanoVersion(
                imageUrl: 'asset://assets/demo/office_360_v2.jpg',
                source: 'מסודר ✨',
              ),
              PanoVersion(
                imageUrl: 'asset://assets/demo/office_360_v3.jpg',
                source: 'ערב 🌇',
              ),
              PanoVersion(
                imageUrl: 'asset://assets/demo/office_360_v4.jpg',
                source: 'לילה 🌙',
              ),
            ],
          ),
        ]),
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
        // Demo 3D scan: multiple rooms so guests can try the room-picker in the
        // 3D viewer. Uses public sample GLB meshes (loaded over the network by
        // model-viewer) as stand-ins for real KIRI room reconstructions.
        model3d: const PropertyModel3d(rooms: [
          ScannedRoom(
            name: 'סלון',
            meshGlbUrl:
                'https://modelviewer.dev/shared-assets/models/SheenChair.glb',
            source: 'cloud',
          ),
          ScannedRoom(
            name: 'מטבח',
            meshGlbUrl:
                'https://modelviewer.dev/shared-assets/models/RobotExpressive.glb',
            source: 'cloud',
          ),
          ScannedRoom(
            name: 'חדר שינה',
            meshGlbUrl:
                'https://modelviewer.dev/shared-assets/models/Astronaut.glb',
            source: 'cloud',
          ),
        ]),
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
    // Demo accepts use the empty-tenant (property-level) key format.
    _ownerAcceptedPropertyIds = <String>{
      'demo-prop-1|',
      'demo-prop-2|',
      'demo-prop-3|',
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
            sender: l10n.datingProviderSystemSenderName,
            text: l10n.datingProviderDemoMatchMessage1,
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
            sender: l10n.datingProviderSystemSenderName,
            text: l10n.datingProviderDemoMatchMessage2,
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
            sender: l10n.datingProviderSystemSenderName,
            text: l10n.datingProviderDemoMatchMessage3,
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
    final learnerJson = storedState['learner'];
    if (learnerJson is Map) {
      _learner = OnlineLogisticLearner.fromJson(
          Map<String, dynamic>.from(learnerJson));
    }
    final cohortJson = storedState['cohortBelief'];
    if (cohortJson is Map) {
      _cohortBelief =
          CohortBelief.fromJson(Map<String, dynamic>.from(cohortJson));
    }
    final consentJson = storedState['tenantConsent'];
    if (consentJson is Map) {
      _tenantConsent =
          TenantDataConsent.fromJson(Map<String, dynamic>.from(consentJson));
    }
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
    _unmatchedIds = (storedState['unmatchedIds'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toSet();
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
    final storedLang = storedState['languageCode'] as String?;
    _languageCode = kSupportedLanguageCodes.contains(storedLang)
        ? storedLang!
        : 'he';
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
    final subscriptionJson = storedState['subscription'];
    if (subscriptionJson is Map) {
      // Guarded: a malformed/foreign-shaped subscription blob (the app-state is
      // remote-synced) must never throw and wedge the whole restore. On any
      // error we just skip the cached subscription — refreshSubscription() will
      // repopulate it from the server.
      try {
        _subscription =
            Subscription.fromJson(Map<String, dynamic>.from(subscriptionJson));
      } catch (_) {
        _subscription = null;
      }
    }
    _pendingMatchPropertyId = null;
    _invalidateCatalogCache();
  }

  void _createMatch(RentalProperty property,
      {String? tenantUserId, required AppLocalizations l10n}) {
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
            sender: l10n.datingProviderSystemSenderName,
            text: l10n.datingProviderMatchCreatedMessage,
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
  // [landlordUid] defaults to the CURRENT device's signed-in user (the normal
  // case: this runs on the landlord's own device) — pass it explicitly when
  // calling from the tenant's device instead (retagging an old match), where
  // the current user IS the tenant and the landlord uid has to come from the
  // property's own ownerUserId.
  Future<void> _syncMatchToBackend({
    required String matchId,
    required String propertyId,
    required String tenantUid,
    String? landlordUid,
  }) async {
    final resolvedLandlordUid =
        landlordUid ?? _firebaseAuthOrNull?.currentUser?.uid;
    if (resolvedLandlordUid == null ||
        resolvedLandlordUid.isEmpty ||
        tenantUid.isEmpty ||
        tenantUid == resolvedLandlordUid) {
      return;
    }
    try {
      await AwsApiClient.instance.post('/matches', {
        'id': matchId,
        'propertyId': propertyId,
        'tenantUid': tenantUid,
        'landlordUid': resolvedLandlordUid,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (_) {/* fail-soft */}
  }

  /// Mirrors [_retagCurrentLandlordProperties] for the tenant side of a match,
  /// PLUS closes a second gap: [requestToMessage] (a one-sided "message the
  /// landlord" thread with no mutual like yet) has always been LOCAL ONLY —
  /// it never called [_syncMatchToBackend] at all, synced or not. So a tenant
  /// can have real open conversations in the app that were never pushed to
  /// the server under ANY uid, placeholder or real, and no website/other-
  /// device view can ever see them no matter what gets retagged.
  ///
  /// So this does two things on every identity bind (sign-in, session
  /// restore — not just once): re-key any match still on a stale/placeholder
  /// id (as before), AND unconditionally (re-)push every local match where
  /// THIS device is the tenant (id suffix == my uid) to the server. The
  /// second part is a no-op for matches already synced (same POST, same id —
  /// an upsert) and is what actually fixes an unsynced [requestToMessage]
  /// thread, which retagging alone can't since its id was never wrong.
  void _retagCurrentTenantMatches({
    required String previousTenantUid,
    required String nextTenantUid,
  }) {
    if (nextTenantUid.trim().isEmpty) return;
    _matches = _matches.map((m) {
      final tildeAt = m.id.lastIndexOf('~');
      if (tildeAt < 0) return m;
      final ownerSuffix = m.id.substring(tildeAt + 1);
      final isStale = ownerSuffix == previousTenantUid ||
          _legacyOwnerPlaceholders.contains(ownerSuffix);
      if (!isStale || ownerSuffix == nextTenantUid) return m;
      final newId = '${m.id.substring(0, tildeAt)}~$nextTenantUid';
      if (_matches.any((other) => other.id == newId)) return m;
      return RentalMatch(
        id: newId,
        propertyId: m.propertyId,
        createdAt: m.createdAt,
        messages: m.messages,
        contractSent: m.contractSent,
        ownerSigned: m.ownerSigned,
        tenantSigned: m.tenantSigned,
        isRequest: m.isRequest,
      );
    }).toList(growable: false);

    final mine = _matches.where((m) => m.id.endsWith('~$nextTenantUid'));
    for (final m in mine) {
      final landlordUid = propertyById(m.propertyId)?.ownerUserId;
      unawaited(() async {
        await _syncMatchToBackend(
          matchId: m.id,
          propertyId: m.propertyId,
          tenantUid: nextTenantUid,
          landlordUid: (landlordUid == null || landlordUid.isEmpty)
              ? null
              : landlordUid,
        );
        // Message backfill is scoped to isRequest threads ONLY — those are
        // the proven-broken, ALWAYS-local-only category (requestToMessage
        // never synced anything, ever). A regular mutual match's messages
        // already flow through RealtimeChatService/the WebSocket path, which
        // was never broken.
        if (!m.isRequest || m.messages.isEmpty) return;
        // Re-posting an already-synced message is a same-id upsert (never a
        // duplicate row) — but the server stamps createdAt itself on every
        // write (anti-clock-skew), so a repeat post would bump an old
        // message's timestamp to "now" on every single sign-in forever,
        // scrambling the thread's real chronological order. So: check ONCE
        // whether this thread has ever been synced at all, and only backfill
        // when it truly hasn't — never re-touch an already-synced thread.
        try {
          final existing = await AwsApiClient.instance
              .get('/messages', query: {'matchId': m.id});
          final items = existing['items'];
          if (items is List && items.isNotEmpty) return;
        } catch (_) {
          return; // can't confirm it's empty — don't risk a timestamp-bump
        }
        for (final msg in m.messages) {
          await _syncMessageToBackend(matchId: m.id, id: msg.id, text: msg.text);
        }
      }());
    }
  }

  /// Public re-pull of the user's matches — call it in-session (app resume, an
  /// incoming match/message push, opening the matches tab) so a match created
  /// while the app was open/backgrounded (e.g. a landlord accepted a like)
  /// appears WITHOUT a relaunch. Safe to call repeatedly (deduped by match id).
  Future<void> refreshMatchesFromBackend() => _loadMatchesFromBackend();

  /// Unmatch: remove the conversation locally, remember it so a backend reload
  /// can't resurrect it, and delete the server row (fire-and-forget) so it's
  /// gone for the other party too on their next refresh.
  Future<void> unmatch(String matchId) async {
    if (matchId.isEmpty) return;
    _matches = _matches.where((m) => m.id != matchId).toList();
    _unmatchedIds.add(matchId);
    _invalidateCatalogCache();
    await _persist();
    notifyListeners();
    try {
      await AwsApiClient.instance.delete('/matches/$matchId');
    } catch (_) {/* local removal + suppress-set still holds */}
  }

  // Backend → local: restore matches this user is part of, so a match made on
  // another device (or before a logout) reappears as a real match, not a
  // pending like. A person is on BOTH sides of matching — tenant (they liked a
  // property) AND landlord (they accepted a tenant) — so we query BOTH indexes:
  //   tenantUid  → matches where this user is the tenant
  //   landlordUid→ matches where this user accepted a candidate  ← the fix for
  //                "approved a tenant, logged out, and it reverted to pending".
  Future<void> _loadMatchesFromBackend() async {
    final uid = _firebaseAuthOrNull?.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    var added = false;
    for (final keyField in const ['tenantUid', 'landlordUid']) {
      try {
        final resp = await AwsApiClient.instance
            .get('/matches', query: {keyField: uid});
        final items = resp['items'];
        if (items is! List) continue;
        for (final it in items) {
          if (it is! Map) continue;
          final matchId = (it['id'] ?? '').toString();
          final propertyId = (it['propertyId'] ?? '').toString();
          if (matchId.isEmpty || propertyId.isEmpty) continue;
          if (_unmatchedIds.contains(matchId)) continue; // stays unmatched
          if (_matches.any((m) => m.id == matchId)) continue;
          _matches = [
            ..._matches,
            RentalMatch(
              id: matchId,
              propertyId: propertyId,
              createdAt:
                  DateTime.tryParse((it['createdAt'] ?? '').toString()) ??
                      DateTime.now(),
              contractSent: false,
              ownerSigned: false,
              tenantSigned: false,
              messages: const [],
            ),
          ];
          // A restored landlord match means this property's incoming like was
          // already accepted — mark it so ownerLeads shows it as matched, not
          // pending, even though the local accepted-set was wiped on logout.
          _ownerAcceptedPropertyIds.add(propertyId);
          added = true;
        }
      } catch (_) {/* fail-soft; try the other index */}
    }
    if (added) {
      await _persist();
      notifyListeners();
    }
  }

  /// A tenant with no mutual like asks to message the owner. Creates (or appends
  /// to) a private thread flagged as a request → it shows under "מבקשים לשלוח
  /// הודעה" for the owner until they reply.
  Future<void> requestToMessage(RentalProperty property,
      {String note = '', required AppLocalizations l10n}) async {
    final matchId = 'match-${property.id}~$_currentOwnerUserId';
    final now = DateTime.now();
    final myName = _tenantProfile?.name ?? l10n.datingProviderTenantFallbackName;
    final text = note.trim().isEmpty
        ? l10n.datingProviderDefaultContactMessage
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
    // This thread has no mutual like, so it's never created by the landlord
    // side (_createMatch) — without an explicit sync here (both the match row
    // AND the message text, in order — the message endpoint gates on thread
    // membership, which the match row establishes) it stays LOCAL ONLY
    // forever: no website view, no other device, not even the landlord's own
    // app ever sees it, regardless of which uid it's keyed to. Idempotent
    // upsert either way, so safe to call again when appending to a thread
    // that predates this fix and was never synced.
    unawaited(() async {
      await _syncMatchToBackend(
        matchId: matchId,
        propertyId: property.id,
        tenantUid: _currentOwnerUserId,
        landlordUid:
            property.ownerUserId.isEmpty ? null : property.ownerUserId,
      );
      await _syncMessageToBackend(matchId: matchId, id: msg.id, text: msg.text);
    }());
    await _persist();
    notifyListeners();
  }

  /// POSTs one chat message to the shared /messages contract. [id] is
  /// required — the backend's generic write path keys every row by an
  /// explicit id and never generates one (verified directly against the live
  /// API: a POST without it 400s "Missing id"). senderId/createdAt are
  /// stamped server-side from the caller's auth token. Fail-soft: the local
  /// thread still holds the message either way.
  Future<void> _syncMessageToBackend({
    required String matchId,
    required String id,
    required String text,
  }) async {
    if (text.trim().isEmpty) return;
    try {
      await AwsApiClient.instance.post('/messages', {
        'id': id,
        'matchId': matchId,
        'text': text,
      });
    } catch (_) {/* fail-soft */}
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
      'learner': _learner.toJson(), // per-user FTRL model (z/n/updates)
      'cohortBelief': _cohortBelief.toJson(), // evolving soft cohort membership
      'tenantConsent': _tenantConsent.toJson(), // versioned data-use consent
      'filters': _filters.toJson(),
      'likedPropertyIds': _likedPropertyIds.toList(),
      'passedPropertyIds': _passedPropertyIds.toList(),
      'ownerAcceptedPropertyIds': _ownerAcceptedPropertyIds.toList(),
      'ownerRejectedPropertyIds': _ownerRejectedPropertyIds.toList(),
      'matches': _matches.map((m) => m.toJson()).toList(),
      'unmatchedIds': _unmatchedIds.toList(),
      'tenantReviews': _tenantReviews.map((r) => r.toJson()).toList(),
      'propertyReviews': _propertyReviews.map(
        (key, value) => MapEntry(key, value.map((r) => r.toJson()).toList()),
      ),
      'customProperties': _customProperties.map((p) => p.toJson()).toList(),
      'userRole': InputSanitizer.sanitizeRole(_userRole),
      'languageCode': _languageCode,
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
      'subscription': _subscription?.toJson(),
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
  const _SwipeRecord(
      {required this.propertyId, required this.liked, this.superLike = false});
  final String propertyId;
  final bool liked;
  final bool superLike;
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

/// Stable reason keys for [DatingProvider.leadFitReason] — the provider has
/// no BuildContext to localize with, so callers translate the key.
enum LeadFitReason { budgetFits, timingFits }

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
