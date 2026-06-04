import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/network/circuit_breaker.dart';
import 'package:dating_app/core/network/retry_policy.dart';
import 'package:dating_app/core/services/appwrite_client.dart';
import 'package:flutter/foundation.dart';

// Sends user reports and blocks to Appwrite so the developer receives them.
//
// Apple Guideline 1.2 requires:
//   "A mechanism for users to flag objectionable content"
//   "A mechanism for users to block abusive users. Blocking should also
//    NOTIFY THE DEVELOPER of the inappropriate content."
//   "The developer must act on objectionable content reports within 24 hours."
//
// This repository is the server-side delivery path. Each report/block row
// written here appears in the admin dashboard (or can trigger a webhook).
//
// Table IDs (env vars):
//   APPWRITE_REPORTS_TABLE_ID — content reports
//   APPWRITE_BLOCKS_TABLE_ID  — user blocks

class ModerationRepository {
  ModerationRepository({
    String? reportsTableId,
    String? blocksTableId,
  })  : _reportsTableId =
            reportsTableId ?? AppConfig.appwriteReportsTableId,
        _blocksTableId =
            blocksTableId ?? AppConfig.appwriteBlocksTableId;

  final String _reportsTableId;
  final String _blocksTableId;
  final _breaker = CircuitBreaker(name: 'appwrite-moderation');

  bool get _reportsConfigured =>
      AppConfig.hasAppwriteCoreConfig &&
      AppConfig.appwriteDatabaseId.isNotEmpty &&
      _reportsTableId.isNotEmpty;

  bool get _blocksConfigured =>
      AppConfig.hasAppwriteCoreConfig &&
      AppConfig.appwriteDatabaseId.isNotEmpty &&
      _blocksTableId.isNotEmpty;

  // ── Report ────────────────────────────────────────────────────────────────────

  // Call when a user taps "Report" on a listing.
  // The row written here is what Apple expects the developer to review within 24h.
  Future<void> reportContent({
    required String reporterUserId,
    required String propertyId,
    required String ownerName,
    required String reason,
  }) async {
    if (!_reportsConfigured) {
      _logMissing('reports');
      return;
    }

    final now = DateTime.now().toUtc();
    try {
      await _breaker.call(
        () => RetryPolicy.transient.execute(
          () => tables.createRow(
            databaseId: appwriteDatabaseId,
            tableId: _reportsTableId,
            rowId: 'rep_${now.microsecondsSinceEpoch}',
            data: {
              'reporterUserId': reporterUserId,
              'propertyId': propertyId,
              'ownerName': ownerName,
              'reason': reason,
              'status': 'pending',   // pending | reviewed | actioned | dismissed
              'createdAt': now.toIso8601String(),
            },
          ),
        ),
      );
      if (kDebugMode) {
        debugPrint('ModerationRepository: report sent — $propertyId / $reason');
      }
    } on CircuitOpenException {
      // Silently drop — local block already removed it from the user's feed.
    } catch (e) {
      if (kDebugMode) debugPrint('ModerationRepository.reportContent error: $e');
    }
  }

  // ── Block ─────────────────────────────────────────────────────────────────────

  // Call when a user blocks an owner.
  // Apple: "Blocking should also notify the developer of the inappropriate content."
  Future<void> reportBlock({
    required String reporterUserId,
    required String blockedOwnerName,
    String note = '',
  }) async {
    if (!_blocksConfigured) {
      _logMissing('blocks');
      return;
    }

    final now = DateTime.now().toUtc();
    try {
      await _breaker.call(
        () => RetryPolicy.transient.execute(
          () => tables.createRow(
            databaseId: appwriteDatabaseId,
            tableId: _blocksTableId,
            rowId: 'blk_${now.microsecondsSinceEpoch}',
            data: {
              'reporterUserId': reporterUserId,
              'blockedOwnerName': blockedOwnerName,
              'note': note,
              'status': 'pending',
              'createdAt': now.toIso8601String(),
            },
          ),
        ),
      );
      if (kDebugMode) {
        debugPrint(
            'ModerationRepository: block notified — $blockedOwnerName');
      }
    } on CircuitOpenException {
      // Silently drop — local block already hid the content from the user.
    } catch (e) {
      if (kDebugMode) debugPrint('ModerationRepository.reportBlock error: $e');
    }
  }

  void _logMissing(String table) {
    if (!kDebugMode) return;
    debugPrint(
      'ModerationRepository: $table table not configured — '
      'set APPWRITE_${table.toUpperCase()}_TABLE_ID to enable developer notifications.',
    );
  }
}
