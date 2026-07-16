import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Round-trips the three eligibility attributes added for the per-listing gate:
// numChildren / hasPets / hasCar. Also asserts back-compat: old JSON without
// them decodes to null and toJson omits them.
void main() {
  const base = TenantProfile(
    id: 'tenant-1',
    name: 'Test',
    bio: 'bio',
    photoUrls: [],
    budgetMax: 7000,
    desiredRooms: 3.0,
    moveInWindow: 'גמיש',
    importantDetails: [],
  );

  test('serializes and round-trips the 3 new fields', () {
    final p = base.copyWith(numChildren: 2, hasPets: true, hasCar: false);
    final json = p.toJson();
    expect(json['numChildren'], 2);
    expect(json['hasPets'], true);
    expect(json['hasCar'], false);

    final back = TenantProfile.fromJson(json);
    expect(back.numChildren, 2);
    expect(back.hasPets, true);
    expect(back.hasCar, false);
  });

  test('old JSON without the fields decodes to null and toJson omits them', () {
    final json = base.toJson();
    expect(json.containsKey('numChildren'), isFalse);
    expect(json.containsKey('hasPets'), isFalse);
    expect(json.containsKey('hasCar'), isFalse);

    final back = TenantProfile.fromJson(json);
    expect(back.numChildren, isNull);
    expect(back.hasPets, isNull);
    expect(back.hasCar, isNull);
  });

  test('tolerant bool/int parsing from strings', () {
    final back = TenantProfile.fromJson({
      ...base.toJson(),
      'numChildren': '3',
      'hasPets': 'true',
      'hasCar': '0',
    });
    expect(back.numChildren, 3);
    expect(back.hasPets, true);
    expect(back.hasCar, false);
  });

  test('serializes and round-trips the 6 gate fields', () {
    final p = base.copyWith(
      wfh: true,
      household: 'family',
      lifeStage: 'young-professional',
      isOleh: true,
      age: 30,
      accessibilityNeed: false,
    );
    final json = p.toJson();
    expect(json['wfh'], true);
    expect(json['household'], 'family');
    expect(json['lifeStage'], 'young-professional');
    expect(json['isOleh'], true);
    expect(json['age'], 30);
    expect(json['accessibilityNeed'], false);

    final back = TenantProfile.fromJson(json);
    expect(back.wfh, true);
    expect(back.household, 'family');
    expect(back.lifeStage, 'young-professional');
    expect(back.isOleh, true);
    expect(back.age, 30);
    expect(back.accessibilityNeed, false);
  });

  test('old JSON without the 6 gate fields decodes to null and omits them', () {
    final json = base.toJson();
    expect(json.containsKey('wfh'), isFalse);
    expect(json.containsKey('household'), isFalse);
    expect(json.containsKey('lifeStage'), isFalse);
    expect(json.containsKey('isOleh'), isFalse);
    expect(json.containsKey('age'), isFalse);
    expect(json.containsKey('accessibilityNeed'), isFalse);

    final back = TenantProfile.fromJson(json);
    expect(back.wfh, isNull);
    expect(back.household, isNull);
    expect(back.lifeStage, isNull);
    expect(back.isOleh, isNull);
    expect(back.age, isNull);
    expect(back.accessibilityNeed, isNull);
  });
}
