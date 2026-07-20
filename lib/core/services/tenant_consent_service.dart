import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/data/models/tenant_data_consent.dart';

/// Versioned enforcement for tenant DATA consent — the tenant-side analogue of
/// [LegalConsentService]. Nothing may repurpose behavioural/persona data for
/// cross-user modelling without a current-version [TenantDataConsent] granting
/// the specific right (Phase-0 targeting-plan guardrail).
///
/// Bump [AppConfig.tenantConsentVersion] when the data terms change to force
/// every tenant to re-consent.
class TenantConsentService {
  const TenantConsentService._();
  static const TenantConsentService instance = TenantConsentService._();

  static String get currentVersion => AppConfig.tenantConsentVersion;

  /// Stamp a consent record when the tenant makes an explicit choice. A decline
  /// is still a real, current-version record with every right false.
  TenantDataConsent grantConsent({
    String source = 'app',
    bool behavioralAnalytics = false,
    bool personaDataset = false,
    bool aiTraining = false,
  }) =>
      TenantDataConsent(
        behavioralAnalyticsAllowed: behavioralAnalytics,
        personaDatasetAllowed: personaDataset,
        aiTrainingAllowed: aiTraining,
        consentVersion: currentVersion,
        consentTimestamp: DateTime.now().toUtc(),
        consentSource: source,
      );

  /// True when the record is present AND on the current version.
  bool hasValidConsent(TenantDataConsent c) =>
      c.hasConsent && c.consentVersion == currentVersion;

  /// Whether a SPECIFIC right is currently granted (version-checked).
  bool allowsPersonaExport(TenantDataConsent c) =>
      hasValidConsent(c) && c.personaDatasetAllowed;
  bool allowsBehavioralAnalytics(TenantDataConsent c) =>
      hasValidConsent(c) && c.behavioralAnalyticsAllowed;
  bool allowsAiTraining(TenantDataConsent c) =>
      hasValidConsent(c) && c.aiTrainingAllowed;

  /// True when a stamped consent is on a stale version and must be renewed.
  bool needsRenewal(TenantDataConsent c) =>
      c.hasConsent && c.consentVersion != currentVersion;

  /// Human-readable reason the consent is invalid, or null when valid.
  String? consentFailureReason(TenantDataConsent c) {
    if (c.consentTimestamp == null) {
      return 'לא נמצאה הסכמה לשימוש בנתונים. יש לאשר לפני שימוש בנתונים אישיים.';
    }
    if (c.consentVersion.isEmpty) return 'גרסת ההסכמה חסרה.';
    if (c.consentVersion != currentVersion) {
      return 'תנאי השימוש בנתונים עודכנו (גרסה $currentVersion). יש לאשר מחדש.';
    }
    return null;
  }
}
