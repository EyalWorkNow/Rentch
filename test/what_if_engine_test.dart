import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/what_if_engine.dart';
import 'package:flutter_test/flutter_test.dart';

// A minimal stand-in listing + a pure matcher honoring the query's HARD
// constraints (budget / rooms / required features) — exactly what the real
// ranker gates on. The engine only needs a count, so this fully exercises it.
class P {
  P(this.price, this.rooms, [this.features = const <String>{}]);
  final int price;
  final double rooms;
  final Set<String> features;
}

int Function(SearchQuery) matcher(List<P> cat) => (q) => cat.where((p) {
      if (q.maxPrice != null && p.price > q.maxPrice!) return false;
      if (q.minRooms != null && p.rooms < q.minRooms!) return false;
      for (final f in q.requiredFeatures) {
        if (!p.features.contains(f)) return false;
      }
      return true;
    }).length;

void main() {
  test('tight budget → suggests raising it, with the correct gain + rounding', () {
    final cat = [
      for (var i = 0; i < 3; i++) P(4800, 3), // in baseline (≤5000)
      for (var i = 0; i < 5; i++) P(5800, 3), // appear when raised to 6000
    ];
    final q = SearchQuery(maxPrice: 5000);
    final s = WhatIfEngine.suggest(query: q, countMatches: matcher(cat));
    expect(s, hasLength(1));
    expect(s.first.key, 'budget');
    expect(s.first.label, 'עד 6,000 ₪'); // 5000×1.2 → 6000
    expect(s.first.deltaCount, 5);
    expect(s.first.mutated.maxPrice, 6000);
    // and applying it really yields the promised total
    expect(matcher(cat)(s.first.mutated), s.first.baselineCount + 5);
  });

  test('minRooms → suggests accepting one fewer room', () {
    final cat = [
      for (var i = 0; i < 2; i++) P(6000, 4), // baseline (≥4)
      for (var i = 0; i < 4; i++) P(6000, 3), // freed by relaxing to 3
    ];
    final s = WhatIfEngine.suggest(
        query: SearchQuery(minRooms: 4), countMatches: matcher(cat));
    expect(s.single.key, 'rooms');
    expect(s.single.label, 'מ-3 חדרים');
    expect(s.single.deltaCount, 4);
    expect(s.single.mutated.minRooms, 3);
  });

  test('drops the required feature that actually frees listings', () {
    // Everyone has parking; almost nobody has ממ״ד → dropping ממ״ד helps most.
    final cat = [
      P(6000, 3, {'parking'}), // no mamad
      P(6000, 3, {'parking'}),
      P(6000, 3, {'parking'}),
      P(6000, 3, {'parking'}),
      P(6000, 3, {'parking', 'mamad'}), // the only baseline match
    ];
    final q = SearchQuery(requiredFeatures: {'mamad', 'parking'});
    final s = WhatIfEngine.suggest(query: q, countMatches: matcher(cat));
    expect(s.first.key, 'feature:mamad');
    expect(s.first.label, 'בלי ממ״ד');
    expect(s.first.deltaCount, 4); // 1 → 5
    // dropping parking frees nothing (everyone has it) → not surfaced
    expect(s.any((x) => x.key == 'feature:parking'), isFalse);
  });

  test('no suggestion when the gain is below minGain (no noise)', () {
    final cat = [
      P(4800, 3), P(4800, 3),
      P(5800, 3), // only 1 extra at raised budget → below minGain=3
    ];
    final s = WhatIfEngine.suggest(
        query: SearchQuery(maxPrice: 5000), countMatches: matcher(cat));
    expect(s, isEmpty);
  });

  test('sorted by gain, capped at maxSuggestions', () {
    final cat = [
      P(4800, 4, {'mamad'}), // baseline: budget≤5000, rooms≥4, mamad
      // budget raise (→6000) frees these 6
      for (var i = 0; i < 6; i++) P(5800, 4, {'mamad'}),
      // rooms relax (→3) frees these 4
      for (var i = 0; i < 4; i++) P(4800, 3, {'mamad'}),
    ];
    final q = SearchQuery(maxPrice: 5000, minRooms: 4, requiredFeatures: {'mamad'});
    final s = WhatIfEngine.suggest(
        query: q, countMatches: matcher(cat), maxSuggestions: 2);
    expect(s, hasLength(2));
    expect(s.first.key, 'budget'); // biggest gain first
    expect(s.first.deltaCount, greaterThanOrEqualTo(s.last.deltaCount));
  });

  test('no applicable constraints → no suggestions', () {
    final s = WhatIfEngine.suggest(
        query: SearchQuery(city: 'תל אביב'), countMatches: (_) => 10);
    expect(s, isEmpty);
  });
}
