import 'package:flutter_test/flutter_test.dart';
import 'package:dating_app/data/models/rental_models.dart';

TenantProfile _base() => const TenantProfile(
      id: 't1',
      name: 'א',
      bio: '',
      photoUrls: [],
      budgetMax: 6000,
      desiredRooms: 3,
      moveInWindow: 'flexible',
      importantDetails: [],
    );

void main() {
  group('TenantProfile.urgency', () {
    test('defaults to null and is omitted from json', () {
      final p = _base();
      expect(p.urgency, isNull);
      expect(p.toJson().containsKey('urgency'), isFalse);
    });

    test('round-trips through toJson/fromJson', () {
      final p = _base().copyWith(urgency: 'now');
      expect(p.urgency, 'now');
      final round = TenantProfile.fromJson(p.toJson());
      expect(round.urgency, 'now');
    });

    test('all canonical tokens are valid options', () {
      final tokens = kUrgencyOptions.map((o) => o.$1).toList();
      expect(tokens, containsAll(['now', 'soon', 'browsing']));
      for (final t in tokens) {
        expect(TenantProfile.fromJson(_base().copyWith(urgency: t).toJson()).urgency, t);
      }
    });
  });
}
