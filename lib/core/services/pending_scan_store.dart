import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ════════════════════════════════════════════════════════════════════════════
// PENDING 3D-SCAN STORE
// ────────────────────────────────────────────────────────────────────────────
// KIRI reconstructs a video sweep in the BACKGROUND — it takes several minutes.
// The capture screen's foreground poll dies the moment the user leaves, so the
// finished model was never fetched and the job's S3 meta stayed "processing"
// forever (the reported "scan never shows up" bug).
//
// The fix: the instant a scan is submitted to KIRI we persist {jobId, propertyId,
// roomName} here, backed by SharedPreferences, so it survives leaving the screen
// and even an app restart. A finalizer (on the scan screen, on property/dashboard
// open, and on app resume) re-reads these records, polls the backend, and — when
// a job is ready — attaches the model to its property and drops the record.
// ════════════════════════════════════════════════════════════════════════════

/// One submitted scan job awaiting reconstruction.
@immutable
class PendingScan {
  const PendingScan({
    required this.jobId,
    required this.propertyId,
    this.roomName = '',
    this.submittedAt,
  });

  final String jobId;
  final String propertyId;

  /// Optional Hebrew room name chosen at capture time, surfaced on the property.
  final String roomName;

  /// When the scan was submitted (best-effort, for stale cleanup).
  final DateTime? submittedAt;

  Map<String, dynamic> toJson() => {
        'jobId': jobId,
        'propertyId': propertyId,
        if (roomName.isNotEmpty) 'roomName': roomName,
        if (submittedAt != null)
          'submittedAt': submittedAt!.toUtc().toIso8601String(),
      };

  factory PendingScan.fromJson(Map<String, dynamic> json) => PendingScan(
        jobId: json['jobId']?.toString() ?? '',
        propertyId: json['propertyId']?.toString() ?? '',
        roomName: json['roomName']?.toString() ?? '',
        submittedAt: DateTime.tryParse(json['submittedAt']?.toString() ?? ''),
      );

  bool get isValid => jobId.isNotEmpty && propertyId.isNotEmpty;
}

/// Tiny SharedPreferences-backed list of in-flight scan jobs. All methods are
/// best-effort and never throw — a persistence hiccup must never crash the app
/// or block a capture.
class PendingScanStore {
  PendingScanStore._();
  static final PendingScanStore instance = PendingScanStore._();

  static const _key = 'rently_pending_3d_scans_v1';

  /// Drop records older than this so a permanently-stuck job doesn't poll
  /// forever (KIRI 3DGS finishes well within an hour).
  static const Duration _maxAge = Duration(hours: 12);

  Future<List<PendingScan>> all() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final now = DateTime.now();
      return decoded
          .whereType<Map>()
          .map((e) => PendingScan.fromJson(Map<String, dynamic>.from(e)))
          .where((s) => s.isValid)
          .where((s) =>
              s.submittedAt == null ||
              now.difference(s.submittedAt!) < _maxAge)
          .toList(growable: false);
    } catch (e) {
      if (kDebugMode) debugPrint('PendingScanStore.all: $e');
      return const [];
    }
  }

  /// Records a freshly-submitted scan. Idempotent on [PendingScan.jobId].
  Future<void> add(PendingScan scan) async {
    if (!scan.isValid) return;
    try {
      final current = await all();
      final next = [
        for (final s in current)
          if (s.jobId != scan.jobId) s,
        scan,
      ];
      await _write(next);
    } catch (e) {
      if (kDebugMode) debugPrint('PendingScanStore.add: $e');
    }
  }

  /// Removes a finished (or failed) scan so it is no longer polled.
  Future<void> remove(String jobId) async {
    if (jobId.isEmpty) return;
    try {
      final current = await all();
      await _write([for (final s in current) if (s.jobId != jobId) s]);
    } catch (e) {
      if (kDebugMode) debugPrint('PendingScanStore.remove: $e');
    }
  }

  /// All pending scans for a single property.
  Future<List<PendingScan>> forProperty(String propertyId) async {
    if (propertyId.isEmpty) return const [];
    final all = await this.all();
    return all.where((s) => s.propertyId == propertyId).toList(growable: false);
  }

  Future<void> _write(List<PendingScan> scans) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(scans.map((s) => s.toJson()).toList()),
    );
  }
}
