// ════════════════════════════════════════════════════════════════════════════
// SCAN-3D JOB — high-quality apartment 3D scan (textured mesh GLB + 3D splat)
// ════════════════════════════════════════════════════════════════════════════
//
// A capture (a set of photos or a video sweep of the apartment) is reconstructed
// by our backend proxy — which talks to the KIRI Engine API server-side so the
// KIRI key never ships in the client — into TWO deliverables:
//
//   • meshGlbUrl — a textured polygon mesh (.glb), for AR / model viewers.
//   • splatUrl   — a 3D Gaussian-splat (.ply), for a photoreal walkable view.
//
// This model is the typed view of one such job as returned by:
//   GET /scan3d/{jobId} → {status, meshGlbUrl?, splatUrl?, error?}
//
// It round-trips to/from JSON and parses the status string defensively: any
// value the client doesn't recognise maps to [Scan3dStatus.processing] (a safe,
// non-terminal default) so an unexpected server string never strands the UI in a
// "ready" or "failed" state.
// ════════════════════════════════════════════════════════════════════════════

/// Lifecycle of a 3D-scan reconstruction job.
enum Scan3dStatus {
  /// Job created on the backend; capture files not yet uploaded.
  created,

  /// Capture files are being PUT to their presigned URLs.
  uploading,

  /// Backend (KIRI) is reconstructing the mesh + splat.
  processing,

  /// Done — [Scan3dJob.meshGlbUrl] / [Scan3dJob.splatUrl] are populated.
  ready,

  /// Reconstruction failed (bad capture, server error, …).
  failed;

  /// Wire string used by the backend contract.
  String get wire => switch (this) {
        Scan3dStatus.created => 'created',
        Scan3dStatus.uploading => 'uploading',
        Scan3dStatus.processing => 'processing',
        Scan3dStatus.ready => 'ready',
        Scan3dStatus.failed => 'failed',
      };

  /// Parse a backend status string. Unknown / null values fall back to
  /// [Scan3dStatus.processing] — a safe non-terminal default that keeps the UI
  /// polling rather than wrongly declaring success or failure.
  static Scan3dStatus fromWire(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'created':
      case 'queued':
      case 'pending':
        return Scan3dStatus.created;
      case 'uploading':
        return Scan3dStatus.uploading;
      case 'processing':
      case 'running':
      case 'training':
        return Scan3dStatus.processing;
      case 'ready':
      case 'complete':
      case 'completed':
      case 'done':
        return Scan3dStatus.ready;
      case 'failed':
      case 'error':
      case 'errored':
        return Scan3dStatus.failed;
      default:
        return Scan3dStatus.processing;
    }
  }
}

/// Typed view of one 3D-scan job.
class Scan3dJob {
  const Scan3dJob({
    required this.jobId,
    required this.status,
    this.meshGlbUrl,
    this.splatUrl,
    this.error,
  });

  /// Backend job id, used for upload / start / poll.
  final String jobId;

  final Scan3dStatus status;

  /// Textured mesh (`.glb`) once [status] is [Scan3dStatus.ready].
  final String? meshGlbUrl;

  /// 3D Gaussian-splat asset (`.ply`) once [status] is [Scan3dStatus.ready].
  final String? splatUrl;

  /// Human-readable failure reason when [status] is [Scan3dStatus.failed].
  final String? error;

  bool get isReady => status == Scan3dStatus.ready;
  bool get isFailed => status == Scan3dStatus.failed;
  bool get isTerminal => isReady || isFailed;

  /// True once at least one deliverable is available.
  bool get hasAssets =>
      (meshGlbUrl?.isNotEmpty ?? false) || (splatUrl?.isNotEmpty ?? false);

  Scan3dJob copyWith({
    String? jobId,
    Scan3dStatus? status,
    String? meshGlbUrl,
    String? splatUrl,
    String? error,
  }) =>
      Scan3dJob(
        jobId: jobId ?? this.jobId,
        status: status ?? this.status,
        meshGlbUrl: meshGlbUrl ?? this.meshGlbUrl,
        splatUrl: splatUrl ?? this.splatUrl,
        error: error ?? this.error,
      );

  factory Scan3dJob.fromJson(Map<String, dynamic> json) {
    // Tolerate the backend nesting the payload under `data` (as the panorama
    // and scan routes do elsewhere).
    final raw = json['data'];
    final data = raw is Map
        ? Map<String, dynamic>.from(raw)
        : json;

    return Scan3dJob(
      jobId: (data['jobId'] ?? data['id'] ?? json['jobId'] ?? '').toString(),
      status: Scan3dStatus.fromWire(
        (data['status'] ?? json['status'])?.toString(),
      ),
      meshGlbUrl: _nonEmpty(data['meshGlbUrl'] ?? data['mesh_glb_url']),
      splatUrl: _nonEmpty(data['splatUrl'] ?? data['splat_url']),
      error: _nonEmpty(data['error'] ?? data['errorMessage']),
    );
  }

  Map<String, dynamic> toJson() => {
        'jobId': jobId,
        'status': status.wire,
        if (meshGlbUrl != null) 'meshGlbUrl': meshGlbUrl,
        if (splatUrl != null) 'splatUrl': splatUrl,
        if (error != null) 'error': error,
      };

  static String? _nonEmpty(Object? value) {
    final s = value?.toString().trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  @override
  String toString() =>
      'Scan3dJob(jobId: $jobId, status: ${status.wire}, '
      'mesh: ${meshGlbUrl != null}, splat: ${splatUrl != null})';
}
