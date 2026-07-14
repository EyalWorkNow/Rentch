import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ════════════════════════════════════════════════════════════════════════════
// PENDING PANORAMA-ENHANCE STORE
// ────────────────────────────────────────────────────────────────────────────
// Completing a partial pano to a full 360 (AI pole-fill + wrap) runs on the
// server for ~1–2 min. The capture screen's foreground poll dies the moment the
// user leaves it, so the finished 360 was never fetched (the "enhanced version
// never showed up" bug).
//
// The fix mirrors [PendingScanStore]: the instant an enhance is submitted we
// persist {jobId, nodeId} here (SharedPreferences), so it survives leaving and
// reopening the capture screen. On re-entry the capture screen re-reads these,
// resumes polling by jobId, and attaches the ready 360 to the matching node.
//
// Ceiling: recovery targets a node by id, so it only reconnects if that node is
// still in the tour (i.e. the tour was kept/saved). A tour abandoned before any
// save has no node to attach to — those records simply age out (_maxAge).
// ════════════════════════════════════════════════════════════════════════════

/// One submitted panorama-enhance job awaiting completion.
@immutable
class PendingPano {
  const PendingPano({
    required this.jobId,
    required this.nodeId,
    this.submittedAt,
    this.label,
  });

  final String jobId;

  /// The [PanoramaNode.id] the completed 360 should be added to as a version.
  final String nodeId;

  /// When it was submitted (best-effort, for stale cleanup).
  final DateTime? submittedAt;

  /// The version name to give the finished 360 (e.g. 'מסודר ✨', 'ערב ✨'). Null
  /// for the plain complete-to-full-360 enhance, which defaults to 'משופר ✨'.
  final String? label;

  Map<String, dynamic> toJson() => {
        'jobId': jobId,
        'nodeId': nodeId,
        if (submittedAt != null)
          'submittedAt': submittedAt!.toUtc().toIso8601String(),
        if (label != null && label!.isNotEmpty) 'label': label,
      };

  factory PendingPano.fromJson(Map<String, dynamic> json) => PendingPano(
        jobId: json['jobId']?.toString() ?? '',
        nodeId: json['nodeId']?.toString() ?? '',
        submittedAt: DateTime.tryParse(json['submittedAt']?.toString() ?? ''),
        label: (json['label']?.toString().isNotEmpty ?? false)
            ? json['label'].toString()
            : null,
      );

  bool get isValid => jobId.isNotEmpty && nodeId.isNotEmpty;
}

/// Tiny SharedPreferences-backed list of in-flight enhance jobs. Best-effort;
/// never throws — a persistence hiccup must not crash the app or block capture.
class PendingPanoStore {
  PendingPanoStore._();
  static final PendingPanoStore instance = PendingPanoStore._();

  static const _key = 'rently_pending_pano_enhance_v1';

  /// Drop records older than this so a permanently-stuck job doesn't poll
  /// forever (enhance finishes well within minutes).
  static const Duration _maxAge = Duration(hours: 6);

  Future<List<PendingPano>> all() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final now = DateTime.now();
      return decoded
          .whereType<Map>()
          .map((e) => PendingPano.fromJson(Map<String, dynamic>.from(e)))
          .where((p) => p.isValid)
          .where((p) =>
              p.submittedAt == null || now.difference(p.submittedAt!) < _maxAge)
          .toList(growable: false);
    } catch (e) {
      if (kDebugMode) debugPrint('PendingPanoStore.all: $e');
      return const [];
    }
  }

  /// Records a freshly-submitted enhance. Idempotent on [PendingPano.jobId].
  Future<void> add(PendingPano pano) async {
    if (!pano.isValid) return;
    try {
      final current = await all();
      await _write([
        for (final p in current)
          if (p.jobId != pano.jobId) p,
        pano,
      ]);
    } catch (e) {
      if (kDebugMode) debugPrint('PendingPanoStore.add: $e');
    }
  }

  /// Removes a finished (or failed) job so it is no longer polled.
  Future<void> remove(String jobId) async {
    if (jobId.isEmpty) return;
    try {
      final current = await all();
      await _write([for (final p in current) if (p.jobId != jobId) p]);
    } catch (e) {
      if (kDebugMode) debugPrint('PendingPanoStore.remove: $e');
    }
  }

  Future<void> _write(List<PendingPano> panos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(panos.map((p) => p.toJson()).toList()),
    );
  }
}
