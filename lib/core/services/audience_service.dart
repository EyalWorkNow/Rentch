import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter/foundation.dart';

// ─── Audience suggestion service (F1) ─────────────────────────────────────────
//
// Thin wrapper over the shared AwsApiClient (same Firebase-token + x-api-key
// auth as every other authed call — see AwsApiClient._headers) that asks the
// backend which of the 14 tenant cohorts a listing best fits.
//
//   POST /audience/suggest
//   { listing: {price,rooms,sizeM2,city,neighborhood,propertyType,condition,
//               featureLabels:[...]}, declaredCohorts:[...], note:"..." }
//   → 200 { suggestions:[{cohort, confidence, reason}] }  (≤5, sorted desc)
//
// Fail-soft: returns [] on any error or when the backend is unconfigured, so
// the upload wizard never blocks on it.
class AudienceService {
  AudienceService._();
  static final AudienceService instance = AudienceService._();

  /// Asks the backend to suggest target cohorts for the given listing. Mirrors
  /// the fail-soft pattern of DatingProvider.fetchRankedLeads: never throws,
  /// returns an empty list on any failure.
  Future<List<AudienceSuggestion>> suggest({
    required int price,
    required double rooms,
    required int sizeM2,
    required String city,
    required String neighborhood,
    required String propertyType,
    required String condition,
    required List<String> featureLabels,
    required List<String> declaredCohorts,
    required String note,
  }) async {
    if (!AwsApiClient.instance.isConfigured) return const [];
    try {
      final res = await AwsApiClient.instance.post('/audience/suggest', {
        'listing': {
          'price': price,
          'rooms': rooms,
          'sizeM2': sizeM2,
          'city': city,
          'neighborhood': neighborhood,
          'propertyType': propertyType,
          'condition': condition,
          'featureLabels': featureLabels,
        },
        'declaredCohorts': declaredCohorts,
        'note': note,
      });
      final raw = res['suggestions'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((m) => AudienceSuggestion.fromJson(Map<String, dynamic>.from(m)))
          .where((s) => s.cohort.isNotEmpty)
          .toList(growable: false);
    } catch (error) {
      if (kDebugMode) debugPrint('AudienceService.suggest: $error');
      return const [];
    }
  }
}
