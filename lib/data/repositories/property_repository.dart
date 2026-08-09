import 'dart:convert';

import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/network/circuit_breaker.dart';
import 'package:dating_app/core/network/retry_policy.dart';
import 'package:dating_app/core/security/input_sanitizer.dart';
import 'package:dating_app/core/services/appwrite_client.dart';
import 'package:dating_app/core/services/legal_consent_service.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter/foundation.dart';

enum PropertyRecordStatus { draft, active, paused, rented, removed }

// Reason a property save was rejected.
enum PropertySaveRejection {
  notConfigured,
  consentMissing,
  consentStale,
  writeFailed,
  // The server rejected an optimistic-locked edit because the row changed
  // since this device last fetched it (see saveProperty's expectedUpdatedAt).
  conflict,
}

class PropertySaveResult {
  const PropertySaveResult.ok() : rejection = null;
  const PropertySaveResult.rejected(this.rejection);

  final PropertySaveRejection? rejection;

  bool get isOk => rejection == null;

  // notConfigured means there's no remote to sync to at all (offline/demo/
  // unconfigured environment) — the app is explicitly designed to work
  // local-only in that case (guest mode, syncRemote:false saves, etc.), so a
  // caller deciding whether to roll back an optimistic local write and show
  // an error should NOT treat this the same as a genuine attempted-and-failed
  // write (writeFailed) or a real policy gate (consent). Those DO mean "we
  // tried to reach the server and it said no" and should roll back + report.
  bool get isRealFailure => !isOk && rejection != PropertySaveRejection.notConfigured;

  // Human-readable message for display in the UI.
  String? get userMessage {
    return switch (rejection) {
      null => null,
      PropertySaveRejection.notConfigured => null,
      PropertySaveRejection.consentMissing =>
        'לא נמצאה הסכמה לתנאי השימוש. יש לאשר את התנאים לפני פרסום הנכס.',
      PropertySaveRejection.consentStale =>
        'תנאי השימוש עודכנו. יש לאשר מחדש לפני פרסום.',
      PropertySaveRejection.writeFailed => 'שגיאה בשמירת הנכס, נסה שוב.',
      PropertySaveRejection.conflict =>
        'הנכס נערך במקום אחר. רענן ונסה שוב.',
    };
  }
}

class PropertyRepository {
  PropertyRepository({String? tableId})
      : _tableId = tableId ?? AppConfig.appwritePropertiesTableId;

  final String _tableId;
  final _breaker = CircuitBreaker(name: 'appwrite-properties-write');
  final _legal = LegalConsentService.instance;

  bool get isConfigured => AppConfig.canUseProperties && _tableId.isNotEmpty;

  // ── Write ─────────────────────────────────────────────────────────────────────

  // Full save with consent validation and circuit-breaker protection.
  // Returns [PropertySaveResult] — check [isOk] and show [userMessage] if not.
  Future<PropertySaveResult> saveProperty(
    RentalProperty property, {
    required String ownerUserId,
    PropertyRecordStatus status = PropertyRecordStatus.active,
    // Optimistic-locking token: pass property.serverUpdatedAt (the value
    // fetched when this edit started) on a genuine UPDATE, never on a fresh
    // CREATE (there's nothing to conflict with yet). The server rejects with
    // 409/conflict if the stored row has changed since.
    String? expectedUpdatedAt,
  }) async {
    if (!isConfigured) {
      return const PropertySaveResult.rejected(
          PropertySaveRejection.notConfigured);
    }

    // Consent is required only for publicly visible listings (active, rented).
    // Draft properties can be saved without consent so the registration onboarding
    // flow and partial wizards don't block users mid-entry.
    final requiresConsent = status == PropertyRecordStatus.active ||
        status == PropertyRecordStatus.rented;

    if (requiresConsent) {
      final reason = _legal.consentFailureReason(property.legal);
      if (reason != null) {
        if (kDebugMode) {
          debugPrint('PropertyRepository: consent rejected — $reason');
        }
        final rejection = _legal.needsRenewal(property.legal)
            ? PropertySaveRejection.consentStale
            : PropertySaveRejection.consentMissing;
        return PropertySaveResult.rejected(rejection);
      }
    }

    try {
      await _breaker.call(
        () => RetryPolicy.transient.execute(
          () => tables.upsertRow(
            databaseId: appwriteDatabaseId,
            tableId: _tableId,
            rowId: _rowId(property.id),
            data: _propertyToRow(
              property,
              ownerUserId: ownerUserId,
              status: status,
              expectedUpdatedAt: expectedUpdatedAt,
            ),
          ),
        ),
      );
      return const PropertySaveResult.ok();
    } on CircuitOpenException {
      return const PropertySaveResult.rejected(
          PropertySaveRejection.writeFailed);
    } on AwsApiException catch (error) {
      _log('save', property.id, error);
      return PropertySaveResult.rejected(error.statusCode == 409
          ? PropertySaveRejection.conflict
          : PropertySaveRejection.writeFailed);
    } catch (error) {
      _log('save', property.id, error);
      return const PropertySaveResult.rejected(
          PropertySaveRejection.writeFailed);
    }
  }

  // Legacy helper — maps to [saveProperty] for call-sites that still use bool.
  // Consent is NOT enforced here — use [saveProperty] for new code.
  Future<bool> upsertProperty(
    RentalProperty property, {
    required String ownerUserId,
    PropertyRecordStatus status = PropertyRecordStatus.active,
  }) async {
    if (!isConfigured) return false;

    try {
      await _breaker.call(
        () => RetryPolicy.transient.execute(
          () => tables.upsertRow(
            databaseId: appwriteDatabaseId,
            tableId: _tableId,
            rowId: _rowId(property.id),
            data: _propertyToRow(
              property,
              ownerUserId: ownerUserId,
              status: status,
            ),
          ),
        ),
      );
      return true;
    } on CircuitOpenException {
      return false;
    } catch (error) {
      _log('upsert', property.id, error);
      return false;
    }
  }

  // ── Read ───────────────────────────────────────────────────────────────────
  // Fetch a single listing by id from the backend (GET /properties/<id>). Used
  // by deep links when the shared apartment isn't in the local catalog (fresh
  // install, filtered out, paginated away). Fail-soft: null on any error / 404
  // (the client coerces 404 → {}, so an empty/idless map means "not found").
  Future<RentalProperty?> fetchProperty(String id) async {
    final trimmed = id.trim();
    if (!isConfigured || trimmed.isEmpty) return null;
    try {
      final doc = await _breaker.call(
        () => RetryPolicy.transient.execute(
          () => tables.getRow(
            databaseId: appwriteDatabaseId,
            tableId: _tableId,
            rowId: trimmed,
          ),
        ),
      );
      final data = doc.data;
      if (data.isEmpty || (data['id'] == null && data['propertyId'] == null)) {
        return null;
      }
      return RentalProperty.fromJson(data);
    } on CircuitOpenException {
      return null;
    } catch (error) {
      _log('fetch', trimmed, error);
      return null;
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────────
  Future<bool> deleteProperty(String propertyId) async {
    if (!isConfigured) return false;

    try {
      await _breaker.call(
        () => RetryPolicy.transient.execute(
          () => tables.deleteRow(
            databaseId: appwriteDatabaseId,
            tableId: _tableId,
            rowId: _rowId(propertyId),
          ),
        ),
      );
      return true;
    } on CircuitOpenException {
      return false;
    } catch (error) {
      _log('delete', propertyId, error);
      return false;
    }
  }

  // ── Row mapping ───────────────────────────────────────────────────────────────

  Map<String, dynamic> _propertyToRow(
    RentalProperty property, {
    required String ownerUserId,
    required PropertyRecordStatus status,
    String? expectedUpdatedAt,
  }) {
    final tour = property.virtualTour;
    final model3d = property.model3d;
    final verification = property.verification;
    final flags = property.featureFlags.values;

    return {
      // ── Core identity ──────────────────────────────────────────────────────
      'propertyId': property.id,
      'ownerUserId': ownerUserId,
      'sourceUrl': property.sourceUrl,
      if (expectedUpdatedAt != null) 'expectedUpdatedAt': expectedUpdatedAt,

      // ── Physical attributes ────────────────────────────────────────────────
      'price': property.price,
      'rooms': property.rooms,
      'sizeM2': property.sizeM2,
      'floor': property.floor,
      'totalFloors': property.totalFloors,
      'city': property.city,
      'neighborhood': property.neighborhood,
      'street': property.street,
      'streetNumber': property.streetNumber,
      'lat': property.lat,
      'lon': property.lon,
      'propertyType': property.propertyType,
      'entryDate': property.entryDate,
      'condition': property.condition,
      'ownerName': property.ownerName,
      'agencyListing': property.agencyListing,

      // ── Features — two representations ────────────────────────────────────
      // 1) JSON blob (backward-compatible read path in rental_data_service)
      'features': jsonEncode(flags),
      'featureLabels': jsonEncode(property.features),

      // 2) Individual boolean columns — enables Appwrite server-side filtering:
      //    Query.equal('feat_balcony', true) — no client-side post-filter needed.
      //    All 23 keys from PropertyFeatureCatalog are written explicitly so
      //    missing keys default to false rather than null.
      'feat_balcony': flags['balcony'] ?? false,
      'feat_parking': flags['parking'] ?? false,
      'feat_storage': flags['storage'] ?? false,
      'feat_airConditioning': flags['airConditioning'] ?? false,
      'feat_mamad': flags['mamad'] ?? false,
      'feat_sunBalcony': flags['sunBalcony'] ?? false,
      'feat_garden': flags['garden'] ?? false,
      'feat_elevator': flags['elevator'] ?? false,
      'feat_furnished': flags['furnished'] ?? false,
      'feat_internetIncluded': flags['internetIncluded'] ?? false,
      'feat_equippedKitchen': flags['equippedKitchen'] ?? false,
      'feat_petsAllowed': flags['petsAllowed'] ?? false,
      'feat_laundryIncluded': flags['laundryIncluded'] ?? false,
      'feat_security': flags['security'] ?? false,
      'feat_accessible': flags['accessible'] ?? false,
      'feat_sharedRoof': flags['sharedRoof'] ?? false,
      'feat_pool': flags['pool'] ?? false,
      'feat_gym': flags['gym'] ?? false,
      'feat_bars': flags['bars'] ?? false,
      'feat_renovated': flags['renovated'] ?? false,
      'feat_roommates': flags['roommates'] ?? false,
      'feat_bombShelter': flags['bombShelter'] ?? false,
      'feat_safeFloorSpace': flags['safeFloorSpace'] ?? false,

      // ── Media ──────────────────────────────────────────────────────────────
      'media': jsonEncode(property.media.map((item) => item.toJson()).toList()),

      // ── Transaction & status ───────────────────────────────────────────────
      'transactionType': property.transactionType.name,
      'status': status.name,
      'createdAt': property.createdAt?.toUtc().toIso8601String() ??
          DateTime.now().toUtc().toIso8601String(),

      // ── Extended data ──────────────────────────────────────────────────────
      'model3d': model3d == null ? '' : jsonEncode(model3d.toJson()),
      'legal': jsonEncode(property.legal.toJson()),
      'priceHistory': jsonEncode(
          property.priceHistory.map((item) => item.toJson()).toList()),
      'marketSignals': jsonEncode(property.marketSignals.toJson()),
      'verification': jsonEncode(verification.toJson()),
      'verifiedListing': property.isVerifiedListing,
      'verificationMethod': verification.method,
      'verificationVideoUrl': verification.videoUrl,
      'verifiedAt': verification.capturedAt?.toUtc().toIso8601String() ?? '',

      // ── Virtual tour ───────────────────────────────────────────────────────
      'virtualTour': tour == null ? '' : jsonEncode(tour.toJson()),
      // 360° tour rides the same JSON-blob convention as virtualTour. Only S3
      // image URLs are stored here (a few KB), not the images themselves.
      'panoramaTour': property.panoramaTour == null
          ? ''
          : jsonEncode(property.panoramaTour!.toJson()),
      'tourStatus': tour?.status.name ??
          (model3d?.hasAnyAsset == true
              ? PropertyTourStatus.ready.name
              : PropertyTourStatus.none.name),
      'tourViewerUrl': tour?.viewerUrl ?? model3d?.viewerUrl ?? '',
      'tourProvider':
          tour?.provider ?? (model3d?.hasAnyAsset == true ? 'asset' : ''),

      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  String _rowId(String propertyId) {
    final sanitized = InputSanitizer.sanitizeText(propertyId, maxLength: 64)
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return sanitized.isEmpty ? ID.unique() : sanitized;
  }

  void _log(String action, String propertyId, Object error) {
    if (!kDebugMode) return;
    debugPrint('PropertyRepository.$action failed for $propertyId: $error');
  }
}
