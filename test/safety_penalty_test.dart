import 'dart:math' as math;

import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/engine/ranking_engine.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Minimal RentalProperty; GradientBoostedScorer only reads the feature map `f`.
RentalProperty _prop() => RentalProperty(
      id: 'p',
      price: 6000,
      rooms: 3,
      sizeM2: 70,
      floor: '2',
      totalFloors: '5',
      city: 'תל אביב',
      neighborhood: '',
      street: 'הרצל',
      streetNumber: 10,
      lat: 32.07,
      lon: 34.78,
      propertyType: 'דירה',
      entryDate: '',
      condition: 'טוב',
      ownerName: 'בעלים',
      agencyListing: false,
      features: const [],
      media: const [
        PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image),
      ],
    );

// Recover the logit contribution from a calibrated [0,1] score (sigmoid inverse).
double _logit(double s) => math.log(s / (1 - s));

PropertyFeatureVector _fv(Map<String, double> overrides) {
  // Neutral baseline so we isolate the safety/SES/centrality effect.
  final f = <String, double>{};
  f.addAll(overrides);
  return PropertyFeatureVector(_prop(), f);
}

void main() {
  group('safety penalty attenuation', () {
    // Old behavior: a flat -0.45 logit cliff fired whenever safety < 0.3,
    // regardless of socioeconomic standing or centrality.
    const oldHardPenalty = 0.45;

    // Isolate the *safety* contribution by holding SES & centrality fixed and
    // toggling only `safety` from a neutral 0.5 (no penalty) down to 0.01.
    // The marginal logit drop is exactly the high-crime penalty for that area.
    double safetyPenaltyFor(double ses, double centrality) {
      final safe =
          _fv({'safety': 0.5, 'socioeconomic': ses, 'centrality': centrality});
      final crime =
          _fv({'safety': 0.01, 'socioeconomic': ses, 'centrality': centrality});
      return (_logit(GradientBoostedScorer.score(crime)) -
              _logit(GradientBoostedScorer.score(safe)))
          .abs();
    }

    test('high-crime + high-SES/high-centrality center penalized LESS than '
        'the old -0.45 cliff', () {
      final centerPenalty = safetyPenaltyFor(0.9, 0.9); // TLV-like hub
      expect(centerPenalty, greaterThan(0.0), reason: 'safety still a signal');
      expect(centerPenalty, lessThan(oldHardPenalty),
          reason: 'prime center penalized noticeably less than old -0.45');
    });

    test('high-crime + high-SES center penalized LESS than high-crime + '
        'low-SES distressed area', () {
      final centerPenalty = safetyPenaltyFor(0.9, 0.9); // TLV-like hub
      final distressedPenalty = safetyPenaltyFor(0.1, 0.1); // genuinely bad

      expect(centerPenalty, lessThan(distressedPenalty),
          reason: 'distressed area keeps a stronger penalty than a prime center');
      // And the distressed area still gets a meaningful (but softened) hit.
      expect(distressedPenalty, greaterThan(0.0));
      expect(distressedPenalty, lessThanOrEqualTo(0.25 + 1e-9),
          reason: 'magnitude capped at the softened 0.25');
    });
  });
}
