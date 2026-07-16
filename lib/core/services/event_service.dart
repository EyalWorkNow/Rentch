import 'dart:convert';
import 'dart:math' as math;

import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/network/circuit_breaker.dart';
import 'package:dating_app/core/network/retry_policy.dart';
import 'package:dating_app/core/services/appwrite_client.dart';
import 'package:flutter/foundation.dart';

// Structured user-event logger.
//
// Why this replaces the app_state blob approach:
//   The previous design persisted all state in a single JSON payload per device.
//   That means every swipe, filter change, and message was a full overwrite of
//   a ~10 KB document.  At 1M users: 1M × 10 KB = 10 GB/write per sync cycle.
//
//   Structured events are append-only rows (~200 bytes each).  They enable:
//     • Real analytics queries ("how many left-swipes on premium listings?")
//     • Funnel analysis without re-reading every device's blob
//     • Replay / undo at the server level
//     • GDPR deletion of specific event types without touching other state
//
// Table schema (create in Appwrite console):
//   userId     : string  (indexed)
//   eventType  : string  (indexed)
//   propertyId : string  (optional, indexed)
//   matchId    : string  (optional)
//   sessionId  : string
//   metadata   : string  (JSON, max 2 KB)
//   createdAt  : string  (ISO-8601, indexed)
//
// Table ID: APPWRITE_EVENTS_TABLE_ID (env var)

enum UserEventType {
  // Discovery
  propertyViewed,
  swipeRight,
  swipeLeft,
  superLike,
  undoSwipe,
  propertySaved,
  propertyUnsaved,
  saveToggled, // {saved} — favorite/unfavorite from any surface (see logSaveToggled)
  propertyReported,

  // Matching
  matchCreated,
  contractSent,
  ownerSigned,
  tenantSigned,

  // Chat
  messageSent,

  // Search
  filterChanged,
  searchPerformed,
  areaChanged,

  // Profile & account
  profileUpdated,
  photoUploaded,
  consentGranted,
  roleChanged,

  // Session
  sessionStarted,
  sessionEnded,

  // Property management (landlord)
  propertyAdded,
  propertyUpdated,
  propertyDeleted,
  tourUploaded,

  // ── Behavioral signals ──────────────────────────────────────────────────
  // High-value revealed-preference + market-intelligence telemetry. Each
  // carries a typed `metadata` payload (see the logXxx helpers below) on top of
  // the shared userId/sessionId/propertyId?/createdAt envelope.
  cardDwell, // {dwellMs}
  swipeOutcome, // {direction, priceToBudgetRatio}
  detailScrollDepth, // {depth}
  mediaEngagement, // {photosViewed, opened360, opened3d, openedVideo, mediaDwellMs}
  filterChange, // {field, oldValue, newValue}
  dealBreakerApplied, // {tag, kind}
  contactInitiated, // {viewToContactMs}
  sessionContext, // {timeOfDayBucket, dayOfWeek, sessionDurationMs, platform, appVersion, locale}
  likedLocation, // {lat, lng}
  comparisonSet, // {propertyIds}
  funnelStage, // {stage, abandoned}
  priceSensitivity, // {maxOverBudgetRatioLiked}
  personaProfileUpdated, // {version, facts:{key:{value,confidence,source,evidence}}}

  // ── Calibration telemetry ─────────────────────────────────────────────────
  // The ranker is hand-tuned; to ever fit its thresholds/priors/calibration to
  // reality we need (prediction → outcome) pairs. `rankedImpression` records the
  // engine's OWN prediction for each shown listing; the swipe/contact outcome is
  // then joinable by (sessionId, propertyId), and `swipeOutcome` also carries the
  // predicted fit inline so a single swipe row is a complete training example.
  rankedImpression, // {fitPct, rank, dims:{dim:contribution}}

  // ── Navigation & search-style telemetry ───────────────────────────────────
  // Wide behavioural signal about HOW the user moves through the app and shapes
  // their search — used to infer user type (decisive vs explorer), preferences,
  // search style, and what pulls them toward the conversion action (leaving
  // details / contacting a landlord). All fire-and-forget, clamped payloads.
  backNavigated, // {fromRoute, toRoute, dwellMs, isSystemBack} — a back/pop
  searchRefined, // {changedField, direction, refinementCount} — successive tweak
  searchAbandoned, // {resultCount, dwellMs, hadInteraction} — left w/o engaging
  leadFunnelStep, // {step, propertyId, msSincePrevStep} — path toward contact
  hesitationSignal, // {context, dwellMs, reversals} — indecision markers
  explorationBreadth, // {distinctPropertiesViewed, distinctAreas, priceRangeSpan}
  sessionInsights, // per-session behavioural summary (see BehaviorInsights)
}

/// Whether a search refinement widened or narrowed the result set, for
/// [EventService.logSearchRefined]. `lateral` = same breadth, different facet
/// (e.g. moved the area without changing how many results it admits).
enum RefinementDirection { broaden, narrow, lateral }

/// Ordered path a user walks toward leaving their details with a landlord, for
/// [EventService.logLeadFunnelStep]. Declared in funnel order so a consumer can
/// compare `.index` to find the furthest step reached.
enum LeadFunnelStep {
  view, // saw the listing in a feed / result list
  detail, // opened the full detail page
  media, // engaged rich media (photos / 360 / 3D / video)
  contactIntent, // tapped contact / "leave details" (intent, not yet sent)
  contactSubmitted, // actually submitted the contact / lead
}

/// Direction of a swipe decision, as recorded by [EventService.logSwipeOutcome].
enum SwipeDirection { like, skip, superlike }

/// Severity of a violated deal-breaker, for [EventService.logDealBreakerApplied].
enum DealBreakerKind { important, critical }

/// Stage in the rental funnel, for [EventService.logFunnelStage].
enum FunnelStage { search, view, like, contact, contract }

class EventService {
  EventService({
    String? tableId,
    String? sessionId,
  })  : _tableId = tableId ?? AppConfig.appwriteEventsTableId,
        _sessionId = sessionId ?? _newSessionId();

  final String _tableId;
  final String _sessionId;
  final _breaker = CircuitBreaker(name: 'appwrite-events');

  // Lazily resolved once per service instance.
  String _userId = '';

  bool get isConfigured =>
      AppConfig.hasAppwriteCoreConfig &&
      AppConfig.appwriteDatabaseId.isNotEmpty &&
      _tableId.isNotEmpty;

  // Set the current user — call after login/registration.
  void setUserId(String userId) => _userId = userId;

  // ── Log ───────────────────────────────────────────────────────────────────────

  // Fire-and-forget: logs an event without blocking the UI.
  // Failures are swallowed — event loss is acceptable; blocking the user is not.
  void log(
    UserEventType type, {
    String? propertyId,
    String? matchId,
    Map<String, dynamic>? metadata,
  }) {
    if (!isConfigured || _userId.isEmpty) return;
    // Run async but don't await — never block callers.
    _writeEvent(
      type: type,
      propertyId: propertyId,
      matchId: matchId,
      metadata: metadata,
    );
  }

  // ── Behavioral-signal emit API ────────────────────────────────────────────
  //
  // One typed helper per signal. All reuse [log] (the existing fire-and-forget
  // send path), so they inherit the same enable/consent guard (isConfigured &&
  // userId set), circuit breaker, and fail-soft behavior — none ever throw into
  // the UI. Values are clamped/normalized where it cheapens the consumer side.

  /// (1) Time a listing card was visible before the user acted on it.
  void logCardDwell({required String propertyId, required int dwellMs}) => log(
        UserEventType.cardDwell,
        propertyId: propertyId,
        metadata: {'dwellMs': math.max(0, dwellMs)},
      );

  /// (2) Revealed price tolerance at the moment of a swipe decision.
  /// [priceToBudgetRatio] = listing price / user's stated budget (1.0 == on budget).
  /// [dwellMs] = latency-to-decision (card visible → swipe); null when unknown
  /// (e.g. first card of a deck). Co-located with the label (direction) so one
  /// row is a complete training example for the ranker.
  void logSwipeOutcome({
    required String propertyId,
    required SwipeDirection direction,
    required double priceToBudgetRatio,
    int? dwellMs,
    double? predictedFit,
    String? searchId,
  }) =>
      log(
        UserEventType.swipeOutcome,
        propertyId: propertyId,
        metadata: {
          'direction': direction.name,
          'priceToBudgetRatio': priceToBudgetRatio,
          if (dwellMs != null) 'dwellMs': math.max(0, dwellMs),
          // The score the ranker gave this listing when it was shown → paired
          // with the label (direction) this row calibrates prediction vs reality.
          if (predictedFit != null) 'predictedFit': predictedFit,
          // Links this swipe back to the search that surfaced the card, so the
          // /search/outcome label and this behavioral row are joinable.
          if (searchId != null && searchId.isNotEmpty) 'searchId': searchId,
        },
      );

  /// Favorite / unfavorite toggle from any surface. [saved] is the new state
  /// (true = just saved, false = just removed). A captured revealed-preference
  /// signal distinct from a swipe — the user deliberately bookmarked a listing.
  void logSaveToggled({required String propertyId, required bool saved}) => log(
        UserEventType.saveToggled,
        propertyId: propertyId,
        metadata: {'saved': saved},
      );

  /// The ranker's OWN prediction for a shown listing — [fitPct] (0..100) at its
  /// [rank], plus the top contributing dimensions (kept small). Emitted per result
  /// so that, joined to the later swipe/contact outcome on (sessionId, propertyId),
  /// the hand-tuned scores can finally be calibrated against real behaviour.
  // Dedupe impressions per session: recommendForTenant fires one of these per
  // surfaced result, and it re-ranks on every preload page / refresh — so the
  // same property was being POSTed dozens of times, a burst that hammered the
  // events endpoint (and yielded transient 500s) while adding no calibration
  // signal (a property's fit% is stable within a session). One row per property
  // per session is enough — this instance IS the session (sessionId is final),
  // so the set's lifetime is exactly one session.
  final Set<String> _impressionsLogged = <String>{};

  void logRankedImpression({
    required String propertyId,
    required int fitPct,
    required int rank,
    Map<String, double>? dims,
  }) {
    if (propertyId.isEmpty || !_impressionsLogged.add(propertyId)) return;
    log(
      UserEventType.rankedImpression,
      propertyId: propertyId,
      metadata: {
        'fitPct': fitPct.clamp(0, 100),
        'rank': math.max(0, rank),
        if (dims != null && dims.isNotEmpty) 'dims': topDims(dims, 5),
      },
    );
  }

  /// The [n] highest-contribution dimensions, rounded — keeps the impression
  /// payload well under the 2 KB metadata cap while retaining the score's drivers.
  static Map<String, double> topDims(Map<String, double> dims, int n) {
    // Drop non-finite contributions: a NaN/Inf would make jsonEncode throw and
    // silently void the whole metadata row (see _encodeMetadata).
    final entries = dims.entries.where((e) => e.value.isFinite).toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    return {
      for (final e in entries.take(n))
        e.key: (e.value * 1000).roundToDouble() / 1000,
    };
  }

  /// (3) How far (0..1) into the detail view the user scrolled.
  void logDetailScrollDepth({
    required String propertyId,
    required double depth,
  }) =>
      log(
        UserEventType.detailScrollDepth,
        propertyId: propertyId,
        metadata: {'depth': depth.clamp(0.0, 1.0)},
      );

  /// (4) Rich-media engagement on a listing.
  void logMediaEngagement({
    required String propertyId,
    int photosViewed = 0,
    bool opened360 = false,
    bool opened3d = false,
    bool openedVideo = false,
    int mediaDwellMs = 0,
  }) =>
      log(
        UserEventType.mediaEngagement,
        propertyId: propertyId,
        metadata: {
          'photosViewed': math.max(0, photosViewed),
          'opened360': opened360,
          'opened3d': opened3d,
          'openedVideo': openedVideo,
          'mediaDwellMs': math.max(0, mediaDwellMs),
        },
      );

  /// (5) A single filter field changed value.
  void logFilterChange({
    required String field,
    required Object? oldValue,
    required Object? newValue,
  }) =>
      log(
        UserEventType.filterChange,
        metadata: {
          'field': field,
          'oldValue': oldValue,
          'newValue': newValue,
        },
      );

  /// (6) A skipped listing violated one of the user's deal-breakers.
  void logDealBreakerApplied({
    required String propertyId,
    required String tag,
    required DealBreakerKind kind,
  }) =>
      log(
        UserEventType.dealBreakerApplied,
        propertyId: propertyId,
        metadata: {'tag': tag, 'kind': kind.name},
      );

  /// (7) User initiated contact; [viewToContactMs] is time from first view.
  void logContactInitiated({
    required String propertyId,
    required int viewToContactMs,
  }) =>
      log(
        UserEventType.contactInitiated,
        propertyId: propertyId,
        metadata: {'viewToContactMs': math.max(0, viewToContactMs)},
      );

  /// (8) Ambient session context, typically emitted once per session.
  void logSessionContext({
    required String timeOfDayBucket,
    required int dayOfWeek,
    required int sessionDurationMs,
    required String platform,
    required String appVersion,
    required String locale,
  }) =>
      log(
        UserEventType.sessionContext,
        metadata: {
          'timeOfDayBucket': timeOfDayBucket,
          'dayOfWeek': dayOfWeek,
          'sessionDurationMs': math.max(0, sessionDurationMs),
          'platform': platform,
          'appVersion': appVersion,
          'locale': locale,
        },
      );

  /// (9) Geographic point of a liked listing (for area-preference centroids).
  void logLikedLocation({
    required String propertyId,
    required double lat,
    required double lng,
  }) =>
      log(
        UserEventType.likedLocation,
        propertyId: propertyId,
        metadata: {'lat': lat, 'lng': lng},
      );

  /// (10) The set of listings viewed consecutively before a decision.
  void logComparisonSet({required List<String> propertyIds}) => log(
        UserEventType.comparisonSet,
        metadata: {'propertyIds': List<String>.from(propertyIds)},
      );

  /// (11) Funnel stage reached; [abandoned] marks a drop-off at that stage.
  void logFunnelStage({
    required FunnelStage stage,
    bool abandoned = false,
    String? propertyId,
  }) =>
      log(
        UserEventType.funnelStage,
        propertyId: propertyId,
        metadata: {'stage': stage.name, 'abandoned': abandoned},
      );

  /// (12) Derived snapshot of how far over budget the user is willing to like.
  void logPriceSensitivity({required double maxOverBudgetRatioLiked}) => log(
        UserEventType.priceSensitivity,
        metadata: {'maxOverBudgetRatioLiked': maxOverBudgetRatioLiked},
      );

  // ── Navigation & search-style emit API ────────────────────────────────────
  //
  // Same fire-and-forget contract as the signals above. These capture HOW the
  // user navigates and refines — a wide, privacy-safe behavioural signal for the
  // ranker and product insights. Route/context labels are screen names, never PII.

  /// (13) A back/pop navigation. [fromRoute] is the screen the user backed OUT
  /// of, [toRoute] the screen they returned TO (both privacy-safe screen names,
  /// never a URL/PII). [dwellMs] is time on the popped screen (didPush→didPop).
  /// [isSystemBack] = true for an OS/gesture back (Android hardware back, iOS
  /// edge-swipe) vs a tapped in-app back affordance, when distinguishable
  /// (best-effort — defaults to system when an in-app back wasn't announced).
  void logBackNavigation({
    required String fromRoute,
    required String toRoute,
    required int dwellMs,
    required bool isSystemBack,
  }) =>
      log(
        UserEventType.backNavigated,
        metadata: {
          'fromRoute': _clampLabel(fromRoute),
          'toRoute': _clampLabel(toRoute),
          'dwellMs': math.max(0, dwellMs),
          'isSystemBack': isSystemBack,
        },
      );

  /// (14) A successive query/filter tweak. [changedField] is the facet touched
  /// (e.g. 'price', 'area', 'rooms'); [direction] says whether it widened or
  /// narrowed the result set; [refinementCount] is the running number of tweaks
  /// this session (1-based) — a high count signals an explorer / picky searcher.
  void logSearchRefined({
    required String changedField,
    required RefinementDirection direction,
    required int refinementCount,
  }) =>
      log(
        UserEventType.searchRefined,
        metadata: {
          'changedField': _clampLabel(changedField),
          'direction': direction.name,
          'refinementCount': math.max(0, refinementCount),
        },
      );

  /// (15) User left a search/result surface without engaging any result.
  /// [resultCount] = results shown, [dwellMs] = time on the surface,
  /// [hadInteraction] = whether they scrolled/tapped anything short of opening a
  /// result. A cluster of these on rich result sets flags mismatch/frustration.
  void logSearchAbandoned({
    required int resultCount,
    required int dwellMs,
    required bool hadInteraction,
  }) =>
      log(
        UserEventType.searchAbandoned,
        metadata: {
          'resultCount': math.max(0, resultCount),
          'dwellMs': math.max(0, dwellMs),
          'hadInteraction': hadInteraction,
        },
      );

  /// (16) One step on the path toward leaving details with a landlord.
  /// [step] is the ordered [LeadFunnelStep]; [msSincePrevStep] is latency from
  /// the previous step for this property (null for the first step). Emitting each
  /// step — not just the final contact — reconstructs the full conversion path
  /// and reveals where users stall before converting.
  void logLeadFunnelStep({
    required LeadFunnelStep step,
    required String propertyId,
    int? msSincePrevStep,
  }) =>
      log(
        UserEventType.leadFunnelStep,
        propertyId: propertyId,
        metadata: {
          'step': step.name,
          'stepIndex': step.index,
          if (msSincePrevStep != null)
            'msSincePrevStep': math.max(0, msSincePrevStep),
        },
      );

  /// (17) An indecision marker. [context] labels where it happened (e.g.
  /// 'card', 'detail', 'contactForm'); [dwellMs] the lingering time; [reversals]
  /// the count of back-and-forth actions (opened→backed→reopened, toggles). High
  /// reversals distinguish a hesitant user from a decisive one.
  void logHesitationSignal({
    required String context,
    required int dwellMs,
    required int reversals,
  }) =>
      log(
        UserEventType.hesitationSignal,
        metadata: {
          'context': _clampLabel(context),
          'dwellMs': math.max(0, dwellMs),
          'reversals': math.max(0, reversals),
        },
      );

  /// (18) Session-level breadth of exploration. [distinctPropertiesViewed] and
  /// [distinctAreas] size the search; [priceRangeSpan] is the max−min price of
  /// listings the user engaged. Low breadth ⇒ decisive/targeted; high ⇒ explorer.
  void logExplorationBreadth({
    required int distinctPropertiesViewed,
    required int distinctAreas,
    required double priceRangeSpan,
  }) =>
      log(
        UserEventType.explorationBreadth,
        metadata: {
          'distinctPropertiesViewed': math.max(0, distinctPropertiesViewed),
          'distinctAreas': math.max(0, distinctAreas),
          'priceRangeSpan': math.max(0.0, priceRangeSpan),
        },
      );

  /// (19) A rolled-up per-session behavioural summary produced on-device by
  /// [BehaviorInsights]. [summary] is a pre-built, bounded map describing the
  /// user's session (counts, dwell distribution, refinement direction tally,
  /// exploration breadth, furthest funnel step) — see BehaviorInsights for its
  /// exact shape. Passed through verbatim; the shared 2 KB cap still applies.
  void logSessionInsights(Map<String, dynamic> summary) => log(
        UserEventType.sessionInsights,
        metadata: summary,
      );

  /// Normalize a free-form label to a compact, privacy-safe token: trimmed and
  /// hard-capped so no accidental long/PII string bloats a metadata row.
  static String _clampLabel(String s, {int max = 64}) {
    final t = s.trim();
    return t.length <= max ? t : t.substring(0, max);
  }

  Future<void> _writeEvent({
    required UserEventType type,
    String? propertyId,
    String? matchId,
    Map<String, dynamic>? metadata,
  }) async {
    if (_breaker.isOpen) return;
    try {
      final now = DateTime.now().toUtc();
      final rowId = 'ev_${now.microsecondsSinceEpoch}_'
          '${_rng.nextInt(0xFFFF).toRadixString(16)}';

      final data = <String, dynamic>{
        'userId': _userId,
        'eventType': type.name,
        'sessionId': _sessionId,
        'createdAt': now.toIso8601String(),
        if (propertyId != null && propertyId.isNotEmpty)
          'propertyId': propertyId,
        if (matchId != null && matchId.isNotEmpty) 'matchId': matchId,
        if (metadata != null && metadata.isNotEmpty)
          'metadata': _encodeMetadata(metadata),
      };

      await _breaker.call(
        () => RetryPolicy.none.execute(
          // Don't retry events — a duplicate event is worse than a missing one.
          () => tables.createRow(
            databaseId: appwriteDatabaseId,
            tableId: _tableId,
            rowId: rowId,
            data: data,
          ),
        ),
      );
    } on CircuitOpenException {
      // Silently drop
    } catch (e) {
      if (kDebugMode) debugPrint('EventService: failed to log ${type.name}: $e');
    }
  }

  String _encodeMetadata(Map<String, dynamic> metadata) {
    try {
      final encoded = jsonEncode(metadata);
      // Cap at 2 KB to avoid oversized rows
      return encoded.length <= 2048 ? encoded : encoded.substring(0, 2048);
    } catch (_) {
      return '{}';
    }
  }

  static final _rng = math.Random.secure();

  static String _newSessionId() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = _rng.nextInt(0xFFFFFF).toRadixString(16);
    return 'sess_${ts}_$rand';
  }
}

// Singleton shared across the app.  Replace [userId] after each login.
//
// Usage:
//   AppEvents.instance.setUserId(uid);
//   AppEvents.instance.log(UserEventType.swipeRight, propertyId: prop.id);
class AppEvents {
  AppEvents._();
  static final AppEvents instance = AppEvents._();
  final _service = EventService();

  EventService get service => _service;

  void setUserId(String userId) => _service.setUserId(userId);

  void log(
    UserEventType type, {
    String? propertyId,
    String? matchId,
    Map<String, dynamic>? metadata,
  }) =>
      _service.log(
        type,
        propertyId: propertyId,
        matchId: matchId,
        metadata: metadata,
      );
}
