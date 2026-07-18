import 'package:dating_app/data/repositories/property_likes_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PropertyLike.fromRow — defensive attribute parsing', () {
    test('parses numbers whether returned as num or String', () {
      final like = PropertyLike.fromRow(<String, dynamic>{
        'propertyId': 'p1',
        'tenantId': 't1',
        'tenantName': 'דנה',
        'budgetMax': 6500, // num
        'rooms': '3.5', // String
        'numChildren': '2', // String
        'monthlyIncome': 18000, // num
        'age': 34, // num
      });
      expect(like.budgetMax, 6500);
      expect(like.rooms, 3.5);
      expect(like.numChildren, 2);
      expect(like.monthlyIncome, 18000);
      expect(like.age, 34);
    });

    test('parses booleans from bool, "true"/"false", 1/0', () {
      final like = PropertyLike.fromRow(<String, dynamic>{
        'propertyId': 'p1',
        'tenantId': 't1',
        'tenantName': 'דנה',
        'hasPets': true,
        'hasCar': 'false',
        'wfh': 1,
        'isOleh': 0,
        'verified': 'true',
      });
      expect(like.hasPets, isTrue);
      expect(like.hasCar, isFalse);
      expect(like.wfh, isTrue);
      expect(like.isOleh, isFalse);
      expect(like.verified, isTrue);
    });

    test('missing / blank attributes stay null (old likes unchanged)', () {
      final like = PropertyLike.fromRow(<String, dynamic>{
        'propertyId': 'p1',
        'tenantId': 't1',
        'tenantName': 'דנה',
        'occupation': '  ',
      });
      expect(like.budgetMax, isNull);
      expect(like.rooms, isNull);
      expect(like.occupation, isNull); // blank → null
      expect(like.hasPets, isNull);
      expect(like.verified, isNull);
    });

    test('string fields trimmed and populated', () {
      final like = PropertyLike.fromRow(<String, dynamic>{
        'propertyId': 'p1',
        'tenantId': 't1',
        'tenantName': 'דנה',
        'occupation': ' hightech ',
        'household': 'family',
        'lifeStage': 'young-professional',
      });
      expect(like.occupation, 'hightech');
      expect(like.household, 'family');
      expect(like.lifeStage, 'young-professional');
    });
  });
}
