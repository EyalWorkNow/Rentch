// FTRL closure — step 1: the online learner must LEARN from swipes and SURVIVE
// serialization, so a per-user model can persist across sessions.
import 'dart:convert';
import 'package:dating_app/core/search/engine/preference_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('learner shifts toward liked feature patterns', () {
    final l = OnlineLogisticLearner();
    // "cheap+verified" liked; "expensive+unverified" skipped — 40 rounds.
    for (var i = 0; i < 40; i++) {
      l.update({'value_score': 1.0, 'verified': 1.0}, 1.0); // like
      l.update({'value_score': -1.0, 'verified': 0.0}, 0.0); // skip
    }
    final pLike = l.predict({'value_score': 1.0, 'verified': 1.0});
    final pSkip = l.predict({'value_score': -1.0, 'verified': 0.0});
    expect(pLike, greaterThan(pSkip));
    expect(pLike, greaterThan(0.5));
    expect(l.updates, 80);
    expect(l.confidence, greaterThan(0.9)); // 80 updates → confident
  });

  test('toJson → fromJson round-trips the learned state exactly', () {
    final l = OnlineLogisticLearner();
    for (var i = 0; i < 30; i++) {
      l.update({'trust': 1.0, 'value_score': 0.8}, i.isEven ? 1.0 : 0.0);
    }
    final restored = OnlineLogisticLearner.fromJson(
        jsonDecode(jsonEncode(l.toJson())) as Map<String, dynamic>);
    expect(restored.updates, l.updates);
    for (final x in [
      {'trust': 1.0, 'value_score': 0.8},
      {'trust': 0.0, 'value_score': -0.5},
      {'trust': 0.5},
    ]) {
      expect(restored.predict(x), closeTo(l.predict(x), 1e-9),
          reason: 'restored predictions must match the original');
    }
  });

  test('a persisted learner keeps learning where it left off', () {
    final l = OnlineLogisticLearner();
    for (var i = 0; i < 20; i++) {
      l.update({'value_score': 1.0}, 1.0);
    }
    final resumed = OnlineLogisticLearner.fromJson(l.toJson());
    for (var i = 0; i < 20; i++) {
      resumed.update({'value_score': 1.0}, 1.0);
    }
    expect(resumed.updates, 40); // 20 restored + 20 new
    expect(resumed.predict({'value_score': 1.0}), greaterThan(0.5));
  });

  test('corrupt / partial blobs degrade to a cold learner (never throw)', () {
    for (final bad in <Map<String, dynamic>>[
      {},
      {'z': 'oops', 'n': 5, 'u': 'x'},
      {'z': {'k': 'NaNish'}, 'u': 3.0},
    ]) {
      final l = OnlineLogisticLearner.fromJson(bad);
      expect(l.predict({'value_score': 1.0}), inInclusiveRange(0.0, 1.0));
    }
  });
}
