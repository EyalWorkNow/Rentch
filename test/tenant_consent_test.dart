import 'package:dating_app/core/services/tenant_consent_service.dart';
import 'package:dating_app/data/models/tenant_data_consent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const svc = TenantConsentService.instance;

  test('granted consent is current-version and reflects the rights', () {
    final c = svc.grantConsent(
        source: 'test', personaDataset: true, behavioralAnalytics: true);
    expect(c.hasConsent, isTrue);
    expect(svc.hasValidConsent(c), isTrue);
    expect(svc.allowsPersonaExport(c), isTrue);
    expect(svc.allowsBehavioralAnalytics(c), isTrue);
    expect(svc.allowsAiTraining(c), isFalse); // not granted
    expect(svc.needsRenewal(c), isFalse);
  });

  test('a decline is a real record that permits nothing', () {
    final c = svc.grantConsent(source: 'test'); // all false
    expect(c.hasConsent, isTrue); // still a stamped record
    expect(svc.hasValidConsent(c), isTrue);
    expect(svc.allowsPersonaExport(c), isFalse);
    expect(svc.allowsAiTraining(c), isFalse);
  });

  test('the never-asked state permits nothing and needs no renewal', () {
    const c = TenantDataConsent.none;
    expect(c.hasConsent, isFalse);
    expect(svc.hasValidConsent(c), isFalse);
    expect(svc.allowsPersonaExport(c), isFalse);
    expect(svc.needsRenewal(c), isFalse);
    expect(svc.consentFailureReason(c), isNotNull);
  });

  test('a stale-version record is invalid and needs renewal', () {
    final stale = TenantDataConsent(
      personaDatasetAllowed: true,
      consentVersion: 'v0.old',
      consentTimestamp: DateTime.utc(2020),
      consentSource: 'test',
    );
    expect(svc.hasValidConsent(stale), isFalse);
    expect(svc.allowsPersonaExport(stale), isFalse);
    expect(svc.needsRenewal(stale), isTrue);
    expect(svc.consentFailureReason(stale), contains('עודכנו'));
  });

  test('JSON round-trip preserves rights + version + timestamp', () {
    final c = svc.grantConsent(
        source: 's', personaDataset: true, aiTraining: true);
    final back = TenantDataConsent.fromJson(c.toJson());
    expect(back.personaDatasetAllowed, isTrue);
    expect(back.aiTrainingAllowed, isTrue);
    expect(back.behavioralAnalyticsAllowed, isFalse);
    expect(back.consentVersion, c.consentVersion);
    expect(back.consentTimestamp?.toIso8601String(),
        c.consentTimestamp?.toIso8601String());
  });
}
