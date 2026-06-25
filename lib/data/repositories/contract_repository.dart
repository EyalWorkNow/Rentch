import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/data/models/rental_contract.dart';
import 'package:flutter/foundation.dart';

/// Backend access for rental contracts. Contracts live in the `contracts` table;
/// the API authorizer guarantees the caller is signed in, and the Lambda only
/// returns/accepts contracts where the caller is the landlord or the tenant.
class ContractRepository {
  ContractRepository({AwsApiClient? api})
      : _api = api ?? AwsApiClient.instance;

  final AwsApiClient _api;

  bool get isEnabled => AppConfig.hasAwsCoreConfig && _api.isConfigured;

  /// Landlord creates + sends a contract. Returns the stored contract.
  Future<RentalContract?> create(RentalContract contract) async {
    if (!isEnabled) return null;
    try {
      final res = await _api.post('/contracts', contract.toJson());
      return _contractFrom(res) ?? contract;
    } on AwsApiException catch (e) {
      if (kDebugMode) debugPrint('ContractRepository.create failed: $e');
      rethrow;
    }
  }

  /// All contracts the caller is a party to (as landlord or tenant).
  Future<List<RentalContract>> listForUser() async {
    if (!isEnabled) return const [];
    try {
      final res = await _api.get('/contracts');
      final rows = res['items'] ?? res['rows'];
      if (rows is! List) return const [];
      return rows
          .whereType<Map>()
          .map((r) => RentalContract.fromJson(Map<String, dynamic>.from(r)))
          .where((c) => c.id.isNotEmpty)
          .toList();
    } catch (e) {
      if (kDebugMode) debugPrint('ContractRepository.listForUser failed: $e');
      return const [];
    }
  }

  Future<RentalContract?> getById(String id) async {
    if (!isEnabled || id.isEmpty) return null;
    try {
      return _contractFrom(await _api.get('/contracts/$id'));
    } catch (e) {
      if (kDebugMode) debugPrint('ContractRepository.getById failed: $e');
      return null;
    }
  }

  /// Submit one party's signature. Returns the updated contract.
  Future<RentalContract?> sign(
    String contractId,
    ContractSignature signature,
  ) async {
    if (!isEnabled) return null;
    try {
      final res = await _api.post(
        '/contracts/$contractId/sign',
        signature.toJson(),
      );
      return _contractFrom(res);
    } on AwsApiException catch (e) {
      if (kDebugMode) debugPrint('ContractRepository.sign failed: $e');
      rethrow;
    }
  }

  /// PAID FEATURE. Sends the draft lease text + property/match facts to the
  /// server, which runs Gemini (key stays server-side) and returns an improved,
  /// tailored Hebrew draft. The server grounds the model strictly and keeps the
  /// "אינו תחליף לייעוץ משפטי" disclaimer. Returns the improved text, or null on
  /// failure so the caller can keep the original draft.
  Future<String?> improveWithAi({
    required String contractText,
    required String propertyTitle,
    required int monthlyRent,
    required int deposit,
    required int durationMonths,
    required String landlordName,
    required String tenantName,
  }) async {
    if (!isEnabled) return null;
    try {
      final res = await _api.post('/contract/improve', {
        'contractText': contractText,
        'propertyTitle': propertyTitle,
        'monthlyRent': monthlyRent,
        'deposit': deposit,
        'durationMonths': durationMonths,
        'landlordName': landlordName,
        'tenantName': tenantName,
      });
      final improved = res['improved'] ?? res['text'];
      final out = improved?.toString().trim() ?? '';
      return out.isEmpty ? null : out;
    } catch (e) {
      if (kDebugMode) debugPrint('ContractRepository.improveWithAi failed: $e');
      return null;
    }
  }

  Future<void> cancel(String contractId) async {
    if (!isEnabled) return;
    try {
      await _api.post('/contracts/$contractId/cancel', const {});
    } catch (e) {
      if (kDebugMode) debugPrint('ContractRepository.cancel failed: $e');
    }
  }

  RentalContract? _contractFrom(Map<String, dynamic> res) {
    final raw = res['item'] ?? res['contract'] ?? res;
    if (raw is Map && (raw['id']?.toString().isNotEmpty ?? false)) {
      return RentalContract.fromJson(Map<String, dynamic>.from(raw));
    }
    return null;
  }
}
