import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/models/renter_dossier.dart';
import 'package:dating_app/data/repositories/property_likes_repository.dart';
import 'package:flutter_test/flutter_test.dart';

// Verifies the "תיק שוכר" model: json round-trip, doc replace/remove,
// completeness scoring against the profile, and the lead payload carrying the
// dossier summary (doc-type keys, never URLs).
void main() {
  final doc = DossierDoc(
    type: DossierDocType.paySlip,
    url: 'https://s3/x.jpg',
    uploadedAt: DateTime.utc(2026, 8, 1),
  );

  test('json round-trip preserves everything; unknown doc kinds are dropped',
      () {
    final d = RenterDossier(
      docs: [doc],
      employerName: 'אינטל',
      referenceName: 'דוד לוי',
      referenceText: 'שוכר מצוין, שילם תמיד בזמן',
      dataFirstMode: true,
    );
    final back = RenterDossier.fromJson(d.toJson());
    expect(back.docs.single.type, DossierDocType.paySlip);
    expect(back.employerName, 'אינטל');
    expect(back.referenceText, contains('בזמן'));
    expect(back.dataFirstMode, isTrue);

    final withUnknown = Map<String, dynamic>.from(d.toJson());
    (withUnknown['docs'] as List).add({'type': 'hologram', 'url': 'x'});
    expect(RenterDossier.fromJson(withUnknown).docs.length, 1);
  });

  test('withDoc replaces same-type doc; withoutDoc removes', () {
    final d = const RenterDossier().withDoc(doc).withDoc(DossierDoc(
          type: DossierDocType.paySlip,
          url: 'https://s3/newer.jpg',
          uploadedAt: DateTime.utc(2026, 8, 2),
        ));
    expect(d.docs.length, 1);
    expect(d.docs.single.url, contains('newer'));
    expect(d.withoutDoc(DossierDocType.paySlip).docs, isEmpty);
  });

  test('completeness climbs with profile fields, docs and reference', () {
    const profile = TenantProfile(
      id: 't1',
      name: 'נועה',
      bio: '',
      photoUrls: [],
      budgetMax: 3000,
      desiredRooms: 2,
      moveInWindow: '',
      importantDetails: [],
      occupation: 'hightech',
      monthlyIncome: 12000,
      hasGuarantor: true,
    );
    const empty = RenterDossier();
    final full = RenterDossier(
      docs: [doc],
      employerName: 'אינטל',
      referenceText: 'מומלץ בחום',
    );
    expect(empty.completeness(null), 0);
    final base = empty.completeness(profile); // occupation+income+guarantor
    expect(base, closeTo(0.45, 0.001));
    expect(full.completeness(profile), closeTo(1.0, 0.001));
  });

  test('lead payload carries doc-type keys and flags — never URLs', () {
    final body = PropertyLikesRepository.buildAddLikeBody(
      propertyId: 'p1',
      ownerUserId: 'o1',
      tenantId: 't1',
      tenantName: 'נועה',
      dossierDocTypes: const ['paySlip', 'landlordReference'],
      dossierDataFirst: true,
      dossierReference: true,
    );
    expect(body['dossierDocTypes'], ['paySlip', 'landlordReference']);
    expect(body['dossierDataFirst'], isTrue);
    expect(body['dossierReference'], isTrue);
    expect(body.toString(), isNot(contains('s3')));
  });
}
