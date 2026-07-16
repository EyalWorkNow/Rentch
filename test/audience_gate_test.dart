import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DatingProvider.passesAudienceGate (F2 client gate)', () {
    test('fails open when the tenant cohort is unknown (null/empty)', () {
      expect(
          DatingProvider.passesAudienceGate(
            exclusive: true,
            audienceCohorts: const ['family'],
            tenantCohort: null,
            isOwner: false,
          ),
          isTrue);
      expect(
          DatingProvider.passesAudienceGate(
            exclusive: true,
            audienceCohorts: const ['family'],
            tenantCohort: '   ',
            isOwner: false,
          ),
          isTrue);
    });

    test('hides on a known cohort NOT in the target list', () {
      expect(
          DatingProvider.passesAudienceGate(
            exclusive: true,
            audienceCohorts: const ['family', 'couple'],
            tenantCohort: 'student',
            isOwner: false,
          ),
          isFalse);
    });

    test('shows on a known cohort that IS in the target list', () {
      expect(
          DatingProvider.passesAudienceGate(
            exclusive: true,
            audienceCohorts: const ['family', 'couple'],
            tenantCohort: 'couple',
            isOwner: false,
          ),
          isTrue);
    });

    test('fails open for the owner, an empty list, or non-exclusive listings',
        () {
      expect(
          DatingProvider.passesAudienceGate(
            exclusive: true,
            audienceCohorts: const ['family'],
            tenantCohort: 'student',
            isOwner: true,
          ),
          isTrue);
      expect(
          DatingProvider.passesAudienceGate(
            exclusive: true,
            audienceCohorts: const [],
            tenantCohort: 'student',
            isOwner: false,
          ),
          isTrue);
      expect(
          DatingProvider.passesAudienceGate(
            exclusive: false,
            audienceCohorts: const ['family'],
            tenantCohort: 'student',
            isOwner: false,
          ),
          isTrue);
    });
  });
}
