import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/data/models/rental_models.dart';

// Legal consent enforcement for property listings.
//
// Why this matters:
//   The `legal` field exists in the schema and the Dart model but nothing in
//   the app currently populates it — every property is saved with the default
//   PropertyLegal() which has all fields false/null.
//
//   This service:
//     1. Generates a consent record when the owner explicitly agrees to terms.
//     2. Validates that a consent record is current before allowing a save.
//     3. Rejects saves where consent is missing or on a stale version.
//
// Consent version is set in AppConfig.legalConsentVersion (env-overridable).
// Bump the version when the terms change to force re-consent from all owners.

class LegalConsentService {
  const LegalConsentService._();
  static const LegalConsentService instance = LegalConsentService._();

  // ── Version ───────────────────────────────────────────────────────────────────

  static String get currentVersion => AppConfig.legalConsentVersion;

  // ── Consent generation ────────────────────────────────────────────────────────

  // Call when the user taps "I agree" on the consent screen.
  // [source] describes how consent was captured: 'registration_screen',
  // 'add_property_screen', 'consent_dialog', etc.
  PropertyLegal grantConsent({
    String source = 'app',
    bool thirdPartyTransfer = false,
    bool commercialSale = false,
    bool aiTraining = false,
  }) {
    return PropertyLegal(
      thirdPartyTransferAllowed: thirdPartyTransfer,
      commercialSaleAllowed: commercialSale,
      aiTrainingAllowed: aiTraining,
      consentVersion: currentVersion,
      consentTimestamp: DateTime.now().toUtc(),
      consentSource: source,
    );
  }

  // ── Validation ────────────────────────────────────────────────────────────────

  // Returns true when the legal record contains valid, current consent.
  bool hasValidConsent(PropertyLegal legal) {
    if (!legal.hasConsent) return false;
    return legal.consentVersion == currentVersion;
  }

  // Returns a human-readable reason why consent is invalid, or null if valid.
  String? consentFailureReason(PropertyLegal legal) {
    if (legal.consentTimestamp == null) {
      return 'לא נמצאה הסכמה לתנאי השימוש. יש לאשר את התנאים לפני פרסום הנכס.';
    }
    if (legal.consentVersion.isEmpty) {
      return 'גרסת ההסכמה חסרה.';
    }
    if (legal.consentVersion != currentVersion) {
      return 'תנאי השימוש עודכנו (גרסה $currentVersion). יש לאשר מחדש לפני פרסום.';
    }
    return null;
  }

  // ── Convenience ───────────────────────────────────────────────────────────────

  // Returns a PropertyLegal stamped with the current version but with all
  // permissions false — use this to represent a user who has agreed to the
  // basic terms but has not granted any additional data rights.
  PropertyLegal basicConsent({String source = 'app'}) =>
      grantConsent(source: source);

  // Returns true if the consent needs to be renewed (version mismatch).
  bool needsRenewal(PropertyLegal legal) =>
      legal.hasConsent && legal.consentVersion != currentVersion;
}
