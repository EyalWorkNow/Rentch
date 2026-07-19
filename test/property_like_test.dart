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

    test('round-trips the 7 new filter attributes (defensive parse)', () {
      final like = PropertyLike.fromRow(<String, dynamic>{
        'propertyId': 'p1',
        'tenantId': 't1',
        'tenantName': 'דנה',
        'smoker': 'false', // String bool
        'hasGuarantor': 1, // num bool
        'leaseMonths': '12', // String int
        'incomeProofReady': true, // bool
        'workLat': '32.0853', // String double
        'workLon': 34.7818, // num double
        'isOleh': 'yes', // String bool
      });
      expect(like.smoker, isFalse);
      expect(like.hasGuarantor, isTrue);
      expect(like.leaseMonths, 12);
      expect(like.incomeProofReady, isTrue);
      expect(like.workLat, 32.0853);
      expect(like.workLon, 34.7818);
      expect(like.isOleh, isTrue);
    });

    test('new attributes stay null when absent (old likes unchanged)', () {
      final like = PropertyLike.fromRow(<String, dynamic>{
        'propertyId': 'p1',
        'tenantId': 't1',
        'tenantName': 'דנה',
      });
      expect(like.smoker, isNull);
      expect(like.hasGuarantor, isNull);
      expect(like.leaseMonths, isNull);
      expect(like.incomeProofReady, isNull);
      expect(like.workLat, isNull);
      expect(like.workLon, isNull);
    });
  });

  group('PropertyLikesRepository.buildAddLikeBody — only-when-present', () {
    test('omits the 7 new fields when null', () {
      final body = PropertyLikesRepository.buildAddLikeBody(
        propertyId: 'p1',
        ownerUserId: 'o1',
        tenantId: 't1',
        tenantName: 'דנה',
      );
      for (final key in const [
        'smoker',
        'hasGuarantor',
        'leaseMonths',
        'incomeProofReady',
        'workLat',
        'workLon',
      ]) {
        expect(body.containsKey(key), isFalse, reason: '$key should be omitted');
      }
      // The always-present keys are still there.
      expect(body['propertyId'], 'p1');
      expect(body['tenantId'], 't1');
      expect(body.containsKey('createdAt'), isTrue);
    });

    test('includes the 7 new fields when provided', () {
      final body = PropertyLikesRepository.buildAddLikeBody(
        propertyId: 'p1',
        ownerUserId: 'o1',
        tenantId: 't1',
        tenantName: 'דנה',
        smoker: false,
        hasGuarantor: true,
        leaseMonths: 24,
        incomeProofReady: true,
        workLat: 32.0853,
        workLon: 34.7818,
      );
      expect(body['smoker'], isFalse);
      expect(body['hasGuarantor'], isTrue);
      expect(body['leaseMonths'], 24);
      expect(body['incomeProofReady'], isTrue);
      expect(body['workLat'], 32.0853);
      expect(body['workLon'], 34.7818);
    });
  });
}
