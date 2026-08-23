import 'package:dating_app/core/search/etti_plan.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Etti #1 — family expanding, near parents in Petah Tikva', () {
    final q = EttiPlan.fromJson({
      'hard_constraints': {'city': 'פתח תקווה'},
      'soft_weights': {
        'family_friendly': 1.8,
        'schools_nearby': 1.5,
        'accessibility_stroller': 1.5,
        'quiet_neighborhood': 1.5,
      },
      'inferred_persona': 'young family expanding',
    }).toQuery();

    expect(q.city, 'פתח תקווה'); // hard constraint → gate
    // 1.8 is "very important" → super-linear → ≈1.0 (decisive, not averaged).
    expect(q.weights['family'], closeTo(1.0, 0.01));
    expect(q.weights['schools'], closeTo(0.5, 0.01)); // 1.5 = midpoint, linear
    expect(q.weights['accessible'], closeTo(0.5, 0.01));
    expect(q.weights['quiet'], closeTo(0.5, 0.01));
    expect(q.intents.contains('quiet'), true);
  });

  test('Etti #2 — studio in central TA, near sea, size irrelevant', () {
    final q = EttiPlan.fromJson({
      'hard_constraints': {'city': 'תל אביב-יפו'},
      'soft_weights': {
        'near_sea': 2.0,
        'central_location': 1.8,
        'nightlife': 1.5,
        'size': -1.0,
        'transit': 1.2,
      },
      'inferred_persona': 'single professional/student',
    }).toQuery();

    expect(q.city, 'תל אביב-יפו');
    expect(q.weights['near_sea'], closeTo(1.0, 0.01)); // 2.0 → max
    expect(q.weights['central'], closeTo(1.0, 0.01)); // 1.8 → super-linear ≈1.0
    expect(q.weights['transit'], closeTo(0.2, 0.01)); // 1.2 → linear 0.2
    // size: −1.0 ("willing to sacrifice size") → a small EXPLICIT
    // de-prioritisation (~0.03) that REPLACES the default weight. It used to
    // be dropped entirely, making "sacrifice X for Y" indistinguishable from
    // never mentioning X.
    expect(q.weights['size'], closeTo(0.03, 0.01));
    // near_sea is a spatial intent → the near-sea gate will fire.
    expect(q.intents.contains('near_sea'), true);
  });

  test('Etti #3 — Ashkelon, mamad MANDATORY, ground-floor preference', () {
    final q = EttiPlan.fromJson({
      'hard_constraints': {'city': 'אשקלון', 'mamad': true},
      'soft_weights': {
        'ground_floor': 1.5,
        'security': 2.0,
        'accessibility': 1.2,
      },
      'inferred_persona': 'security-driven search in the South',
    }).toQuery();

    expect(q.city, 'אשקלון');
    // mamad is a HARD constraint → becomes a required feature (deal-breaker).
    expect(q.amenities.contains('feat_mamad'), true);
    // security 2.0 (and the mamad deal-breaker) → safety weighted to the max.
    expect(q.weights['safety'], closeTo(1.0, 0.001));
    // ground_floor + accessibility both map to accessibility.
    expect(q.weights['accessible']! > 0, true);
  });

  test('deterministic FALLBACK fills gaps Etti missed (explicit numbers)', () {
    // Etti extracted only the vibe; SmartSearch caught the explicit "עד 6000".
    final fb = SmartSearch.parse('דירה בתל אביב קרוב לים עד 6000');
    final q = EttiPlan.fromJson({
      'hard_constraints': {},
      'soft_weights': {'near_sea': 2.0},
      'inferred_persona': 'beach lover',
    }).toQuery(fallback: fb);

    expect(q.maxPrice, 6000); // from the deterministic fallback
    expect(q.city, 'תל אביב'); // from the fallback
    expect(q.weights['near_sea'], closeTo(1.0, 0.001)); // from Etti
  });
}
