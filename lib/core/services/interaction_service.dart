import 'package:dating_app/core/services/aws_client.dart';
import 'package:flutter/foundation.dart';

// ─── Per-property interaction store + CF recommendations ──────────────────────
//
// Captures the rich engagement signals the app already measures — how long the
// user dwelt on each apartment, how many photos they viewed, whether they opened
// the 360 / 3D / video, how far they scrolled, where they entered from and at
// which rank — and upserts them to the backend interaction store, which
// accumulates them and returns the computed implicit score.
//
// Backend contracts (LOCKED):
//   POST /interactions {propertyId, dwellMs, photosViewed, opened360, opened3d,
//                       openedVideo, scrollDepth, entrySource, entryRank, action}
//                       → {ok, score}. action ∈ view/like/superlike/pass/contact/bounce
//   POST /reco/cf {limit} → {items:[{propertyId, cfScore}]}
//
// EVERY call here is best-effort / non-blocking: errors are swallowed so a
// network blip can never break the swipe / detail / contact UX.
class InteractionService {
  InteractionService._();
  static final InteractionService instance = InteractionService._();

  /// Upserts one engagement record for [propertyId]. Only non-null fields are
  /// sent so the server accumulates partial signals across calls. Fail-soft:
  /// swallows every error and never throws.
  Future<void> record({
    required String propertyId,
    int? dwellMs,
    int? photosViewed,
    bool? opened360,
    bool? opened3d,
    bool? openedVideo,
    double? scrollDepth,
    String? entrySource,
    int? entryRank,
    String? action,
    int? mediaCount,
    int? descLen,
  }) async {
    if (propertyId.trim().isEmpty || !AwsApiClient.instance.isConfigured) return;
    try {
      await AwsApiClient.instance.post('/interactions', {
        'propertyId': propertyId,
        if (dwellMs != null && dwellMs >= 0) 'dwellMs': dwellMs,
        if (photosViewed != null && photosViewed >= 0)
          'photosViewed': photosViewed,
        if (opened360 != null) 'opened360': opened360,
        if (opened3d != null) 'opened3d': opened3d,
        if (openedVideo != null) 'openedVideo': openedVideo,
        if (scrollDepth != null) 'scrollDepth': scrollDepth.clamp(0.0, 1.0),
        if (entrySource != null && entrySource.isNotEmpty)
          'entrySource': entrySource,
        if (entryRank != null && entryRank >= 0) 'entryRank': entryRank,
        if (action != null && action.isNotEmpty) 'action': action,
        // Listing "size" so the backend can length-normalize dwell (a media-rich
        // or long-description listing earns more dwell for the same interest).
        if (mediaCount != null && mediaCount >= 0) 'mediaCount': mediaCount,
        if (descLen != null && descLen >= 0) 'descLen': descLen,
      });
    } catch (error) {
      if (kDebugMode) debugPrint('InteractionService.record: $error');
    }
  }

  /// The caller's saved (favorited) property ids, per the server's own record —
  /// always keyed by the verified caller uid server-side, never spoofable and
  /// never tagged to a stale local placeholder id. Fail-soft: empty on error.
  Future<List<String>> fetchSaved() async {
    if (!AwsApiClient.instance.isConfigured) return const [];
    try {
      final res = await AwsApiClient.instance.get('/interactions/saved');
      final ids = (res['propertyIds'] as List?) ?? const [];
      return ids.map((e) => e.toString()).where((id) => id.isNotEmpty).toList(growable: false);
    } catch (error) {
      if (kDebugMode) debugPrint('InteractionService.fetchSaved: $error');
      return const [];
    }
  }

  /// Fetches collaborative-filtering recommendations, returning the propertyIds
  /// in server-ranked order (highest cfScore first). Fail-soft: returns an empty
  /// list when unconfigured or on any error.
  Future<List<String>> cfRecommendations({int limit = 20}) async {
    if (!AwsApiClient.instance.isConfigured) return const [];
    try {
      final res = await AwsApiClient.instance.post('/reco/cf', {'limit': limit});
      final items = (res['items'] as List?) ?? const [];
      return items
          .whereType<Map>()
          .map((m) => (m['propertyId'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toList(growable: false);
    } catch (error) {
      if (kDebugMode) debugPrint('InteractionService.cfRecommendations: $error');
      return const [];
    }
  }
}
