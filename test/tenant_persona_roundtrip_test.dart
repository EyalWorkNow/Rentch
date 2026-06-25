import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/repositories/user_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final repo = UserRepository(tableId: 'test-users');

  test('persona survives _profileToRow -> getProfile round-trip', () {
    const profile = TenantProfile(
      id: 'uid-123',
      name: 'דנה',
      bio: 'מחפשת דירה',
      photoUrls: ['https://example.com/a.jpg'],
      budgetMax: 6500,
      desiredRooms: 3,
      moveInWindow: 'מיידי',
      importantDetails: ['מרפסת', 'חיות מחמד', 'קרוב לתחבורה'],
      dealBreakers: ['בלי מעלית'],
    );

    final restored = repo.roundTripForTest(profile);

    expect(restored.importantDetails,
        ['מרפסת', 'חיות מחמד', 'קרוב לתחבורה']);
    expect(restored.dealBreakers, ['בלי מעלית']);
  });

  test('label containing a comma is not split (JSON-encoded, not CSV)', () {
    const profile = TenantProfile(
      id: 'uid-comma',
      name: 'x',
      bio: '',
      photoUrls: [],
      budgetMax: 0,
      desiredRooms: 0,
      moveInWindow: '',
      importantDetails: ['קרוב לים, שקט'],
    );

    final restored = repo.roundTripForTest(profile);

    expect(restored.importantDetails, ['קרוב לים, שקט']);
    expect(restored.dealBreakers, isEmpty);
  });

  test('backward compat: legacy row with no persona columns loads as empty',
      () {
    const profile = TenantProfile(
      id: 'uid-legacy',
      name: 'x',
      bio: '',
      photoUrls: [],
      budgetMax: 0,
      desiredRooms: 0,
      moveInWindow: '',
      importantDetails: [],
    );

    final restored = repo.roundTripForTest(profile);

    expect(restored.importantDetails, isEmpty);
    expect(restored.dealBreakers, isEmpty);
  });
}
