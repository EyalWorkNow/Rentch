import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/kiri_3d_service.dart';
import 'package:dating_app/core/services/pending_scan_store.dart';
import 'package:dating_app/core/services/roomplan_service.dart';
import 'package:dating_app/data/models/scan3d_job.dart';
import 'package:dating_app/data/models/scanned_room.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/presentation/features/scan3d/scan3d_viewer.dart';

// ScannedRoom now lives in the data layer so the persisted PropertyModel3d can
// carry the full room list. Re-exported here so existing importers of this file
// keep compiling unchanged.
export 'package:dating_app/data/models/scanned_room.dart' show ScannedRoom;
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_compress/video_compress.dart';

// ════════════════════════════════════════════════════════════════════════════
// PER-ROOM 3D SCAN FLOW
// ────────────────────────────────────────────────────────────────────────────
// The founder's chosen primary path: high-quality 3D, captured ONE ROOM AT A
// TIME, then linked together (just like the 360° tour links panorama points).
//
// For each room we route by device tier:
//   • iPhone Pro (LiDAR / RoomPlan supported)  → "סריקה מהירה" (RoomPlanService).
//       returns a USDZ path; we confirm capture (USDZ→GLB display is a backend
//       follow-up, so we just mark the room "נסרק").
//   • Everything else                          → guided CLOUD capture: walk the
//       user through recording a slow VIDEO walkthrough in-app (big record
//       button, live timer), then Kiri3dService.runScan(...) (KIRI /3dgs/video)
//       with a calm full-screen progress state. Video is far more foolproof for
//       an older user than aiming 20 stills, and it's what KIRI reconstructs best.
//
// Designed for OLDER, non-technical users: big text, ONE action per step, no
// jargon, clear progress, graceful errors with "נסה שוב".
//
// The screen returns the full List<ScannedRoom> to the caller (or pops with the
// current list on back), so add_property can persist it on the draft.
// ════════════════════════════════════════════════════════════════════════════

/// Remembers the one-time interior-scan consent so we never nag a returning
/// landlord. Backed by SharedPreferences (no new model field needed).
class _ScanConsentStore {
  static const _key = 'rently_interior_scan_consent_v1';

  static Future<bool> isGranted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> grant() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, true);
    } catch (_) {/* best-effort */}
  }
}

// ════════════════════════════════════════════════════════════════════════════
// ENTRY SCREEN — list of scanned rooms + "add a room"
// ════════════════════════════════════════════════════════════════════════════

class RoomScanFlowScreen extends StatefulWidget {
  const RoomScanFlowScreen({
    super.key,
    required this.propertyId,
    this.initialRooms = const [],
  });

  final String propertyId;
  final List<ScannedRoom> initialRooms;

  /// Opens the per-room flow and returns the (possibly updated) room list.
  static Future<List<ScannedRoom>?> open(
    BuildContext context, {
    required String propertyId,
    List<ScannedRoom> initialRooms = const [],
  }) {
    return Navigator.of(context).push<List<ScannedRoom>>(
      MaterialPageRoute(
        builder: (_) => RoomScanFlowScreen(
          propertyId: propertyId,
          initialRooms: initialRooms,
        ),
      ),
    );
  }

  @override
  State<RoomScanFlowScreen> createState() => _RoomScanFlowScreenState();
}

class _RoomScanFlowScreenState extends State<RoomScanFlowScreen> {
  late List<ScannedRoom> _rooms;

  @override
  void initState() {
    super.initState();
    _rooms = List.of(widget.initialRooms);
  }

  Future<void> _addRoom() async {
    // 1) Consent gate — only the FIRST time (per device), remembered.
    if (!await _ScanConsentStore.isGranted()) {
      if (!mounted) return;
      final ok = await _showConsentSheet(context);
      if (ok != true) return;
      await _ScanConsentStore.grant();
    }
    if (!mounted) return;

    // 2) Tier routing. RoomPlan (iPhone-Pro LiDAR) is DISABLED: it produces a
    // local USDZ that nothing uploads or converts to a viewable mesh, so the
    // "fast scan" was a silent dead end (captured, then the temp file purged and
    // the work lost). Until a backend USDZ→GLB step exists, route EVERYONE to the
    // guided-video → KIRI cloud path, which actually produces a viewable room.
    const supportsRoomPlan = false;
    if (!mounted) return;

    final room = await Navigator.of(context).push<ScannedRoom>(
      MaterialPageRoute(
        builder: (_) => _SingleRoomCaptureScreen(
          propertyId: widget.propertyId,
          roomNumber: _rooms.length + 1,
          supportsRoomPlan: supportsRoomPlan,
        ),
      ),
    );
    if (room != null && mounted) {
      setState(() => _rooms.add(room));
    }
  }

  void _removeRoom(int i) {
    setState(() => _rooms.removeAt(i));
  }

  void _previewRoom(ScannedRoom room) {
    if (!room.hasViewableAsset) return;
    Scan3dViewerScreen.open(
      context,
      meshGlbUrl: room.meshGlbUrl,
      splatUrl: room.splatUrl,
      title: room.name,
    );
  }

  void _done() => Navigator.of(context).pop(_rooms);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Directionality(
      textDirection: Directionality.of(context),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _done();
        },
        child: Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            foregroundColor: AppColors.navy,
            title: Text(
              l10n.roomScanFlow9049b05d,
              style: const TextStyle(
                color: AppColors.navy,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_forward_rounded),
              onPressed: _done,
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      Text(
                        '${l10n.roomScanFlow0d99078b}${l10n.roomScanFlowE7aea75e}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_rooms.isEmpty)
                        _emptyState(l10n)
                      else
                        ..._rooms.asMap().entries.map(
                              (e) => _RoomCard(
                                room: e.value,
                                onPreview: () => _previewRoom(e.value),
                                onRemove: () => _removeRoom(e.key),
                              ),
                            ),
                    ],
                  ),
                ),
                _bottomBar(l10n),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.primaryLight2,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.view_in_ar_rounded,
              size: 56, color: AppColors.primary),
          const SizedBox(height: 14),
          Text(
            l10n.roomScanFlowDf2e3b66,
            style: const TextStyle(
              color: AppColors.navy,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            l10n.roomScanFlow47a4cbbf,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(AppLocalizations l10n) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.borderLight)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BigButton(
            label: l10n.roomScanFlow5a5e46b8,
            icon: Icons.add_rounded,
            onTap: _addRoom,
          ),
          if (_rooms.isNotEmpty) ...[
            const SizedBox(height: 10),
            _BigButton(
              label: l10n.roomScanFlow6b609163(_rooms.length),
              icon: Icons.check_rounded,
              filled: false,
              onTap: _done,
            ),
          ],
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  _RoomCard({
    required this.room,
    required this.onPreview,
    required this.onRemove,
  });

  final ScannedRoom room;
  final VoidCallback onPreview;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final viewable = room.hasViewableAsset;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryLight2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.view_in_ar_rounded,
                color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.name,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 14, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text(
                      viewable ? l10n.roomScanFlowDcc3a16f : l10n.roomScanFlowA30bf1a9,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (viewable)
            IconButton(
              onPressed: onPreview,
              icon: Icon(Icons.play_circle_fill_rounded,
                  color: AppColors.primary, size: 30),
              tooltip: l10n.roomScanFlow750be052,
            ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppColors.coral, size: 24),
            tooltip: l10n.roomScanFlow7c8173fa,
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SINGLE-ROOM CAPTURE — tier routing → capture → name → return ScannedRoom
// ════════════════════════════════════════════════════════════════════════════

class _SingleRoomCaptureScreen extends StatefulWidget {
  const _SingleRoomCaptureScreen({
    required this.propertyId,
    required this.roomNumber,
    required this.supportsRoomPlan,
  });

  final String propertyId;
  final int roomNumber;
  final bool supportsRoomPlan;

  @override
  State<_SingleRoomCaptureScreen> createState() =>
      _SingleRoomCaptureScreenState();
}

class _SingleRoomCaptureScreenState extends State<_SingleRoomCaptureScreen> {
  final _roomPlan = const RoomPlanService();
  bool _busy = false;
  String? _error;

  Future<void> _startRoomPlan() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final usdzPath = await _roomPlan.startScan();
      if (!mounted) return;
      if (usdzPath == null) {
        // User cancelled — back to the chooser.
        setState(() => _busy = false);
        return;
      }
      final named = await _askRoomName();
      if (named == null || !mounted) {
        setState(() => _busy = false);
        return;
      }
      Navigator.of(context).pop(
        ScannedRoom(name: named, usdzPath: usdzPath, source: 'roomplan'),
      );
    } on RoomPlanException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendlyRoomPlanError(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppLocalizations.of(context)!.roomScanFlowA78ba1c3;
      });
    }
  }

  Future<void> _startCloudCapture() async {
    if (!Kiri3dService.instance.isConfigured) {
      _showComingSoon();
      return;
    }
    // Preflight BEFORE asking the landlord to film: the client can't see the
    // backend's config, so without this they would record a full guided video +
    // wait for the transcode only to hit "not configured". Catch it up front.
    if (!await Kiri3dService.instance.probeAvailable(widget.propertyId)) {
      if (mounted) _showComingSoon();
      return;
    }
    if (!mounted) return;
    final video = await Navigator.of(context).push<File>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const _GuidedVideoCaptureScreen(),
      ),
    );
    if (video == null || !mounted) return;

    final job = await Navigator.of(context).push<Scan3dJob>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _CloudReconstructScreen(
          propertyId: widget.propertyId,
          files: [video],
        ),
      ),
    );
    if (job == null || !mounted) return;
    // Poll timed out but the reconstruction is still running on the backend —
    // NOT a failure. The pending record was kept, so the finalizer will attach
    // the room automatically. Tell the user honestly; never say "film again".
    if (job.timedOut) {
      await _showScanContinuingInBackground();
      return;
    }
    if (!job.isReady) {
      setState(() => _error =
          '${AppLocalizations.of(context)!.roomScanFlowDd0b1d27}'
          '${AppLocalizations.of(context)!.roomScanFlow9aebce63}');
      return;
    }

    final named = await _askRoomName();
    if (!mounted) return;
    // Never throw away a completed, minutes-long, billed reconstruction: if the
    // landlord dismisses the name sheet we keep the room with a default name
    // (they can rename it) instead of silently discarding the scan.
    final roomName = (named == null || named.trim().isEmpty)
        ? AppLocalizations.of(context)!.roomScanFlow48cddcd0(widget.roomNumber)
        : named.trim();
    Navigator.of(context).pop(
      ScannedRoom(
        name: roomName,
        meshGlbUrl: job.meshGlbUrl,
        splatUrl: job.splatUrl,
        source: 'cloud',
      ),
    );
  }

  Future<String?> _askRoomName() => showRoomNameSheet(context);

  // The foreground poll ended but KIRI is still reconstructing — reassure the
  // user; the background finalizer attaches the room when it's ready.
  Future<void> _showScanContinuingInBackground() => showDialog<void>(
        context: context,
        builder: (_) => Directionality(
          textDirection: Directionality.of(context),
          child: AlertDialog(
            title: Text(AppLocalizations.of(context)!.roomScanFlow22b2a582,
                style: const TextStyle(fontWeight: FontWeight.w900)),
            content: Text(
              '${AppLocalizations.of(context)!.roomScanFlow26ddb26d}'
              '${AppLocalizations.of(context)!.roomScanFlowE50dd7a2}',
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(AppLocalizations.of(context)!.roomScanFlow5e9909a0),
              ),
            ],
          ),
        ),
      );

  void _showComingSoon() {
    showDialog<void>(
      context: context,
      builder: (_) => Directionality(
        textDirection: Directionality.of(context),
        child: AlertDialog(
          title: Text(AppLocalizations.of(context)!.roomScanFlowC1053462,
              style: const TextStyle(fontWeight: FontWeight.w900)),
          content: Text(
            '${AppLocalizations.of(context)!.roomScanFlow3b8e87c3}'
            '${AppLocalizations.of(context)!.roomScanFlow824a4b58}',
            style: const TextStyle(fontSize: 15, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(AppLocalizations.of(context)!.roomScanFlow5e9909a0),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          foregroundColor: AppColors.navy,
          title: Text(
            l10n.roomScanFlow48cddcd0(widget.roomNumber),
            style: const TextStyle(
              color: AppColors.navy,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Text(
                l10n.roomScanFlow87e9bce3,
                style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 18),
              if (_error != null) ...[
                _errorBanner(_error!),
                const SizedBox(height: 14),
              ],
              if (widget.supportsRoomPlan)
                _OptionCard(
                  title: l10n.roomScanFlow6e238cd1,
                  subtitle: l10n.roomScanFlowD9e43328,
                  icon: Icons.bolt_rounded,
                  highlighted: true,
                  busy: _busy,
                  onTap: _busy ? null : _startRoomPlan,
                ),
              if (widget.supportsRoomPlan) const SizedBox(height: 12),
              _OptionCard(
                title: l10n.roomScanFlow814b4b51,
                subtitle:
                    '${l10n.roomScanFlow480cd36b}${l10n.roomScanFlow161d5837}',
                icon: Icons.videocam_rounded,
                highlighted: !widget.supportsRoomPlan,
                busy: false,
                onTap: _busy ? null : _startCloudCapture,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorBanner(String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.coral.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.coral.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.coral),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.navy,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _friendlyRoomPlanError(RoomPlanException e) {
    final l10n = AppLocalizations.of(context)!;
    switch (e.code) {
      case 'unsupported':
        return l10n.roomScanFlowFea48952;
      case 'scan_busy':
        return l10n.roomScanFlowA143b471;
      default:
        return l10n.roomScanFlow666d07c4;
    }
  }
}

// ════════════════════════════════════════════════════════════════════════════
// GUIDED VIDEO CAPTURE — in-app camera, big record button, live timer
// ────────────────────────────────────────────────────────────────────────────
// Far more foolproof for an older user than aiming 20 stills: they press record
// and WALK SLOWLY through/around the room. KIRI reconstructs video best (it
// submits to /3dgs/video with the videoFile field). Resolution is capped at
// 1080p (KIRI max is 1920×1080) — we use 720p for a reliably-uploadable size.
//
// THE #1 FAILURE: 3D Gaussian-splat reconstruction NEEDS PARALLAX. If the user
// just rotates in place (like filming a panorama) there's no parallax and the
// reconstruction collapses to a meaningless scatter of points. So the whole UX
// here is built to drive ONE behaviour: WALK slowly THROUGH/AROUND the space.
// A pre-capture steps card hammers this home, and during recording we use the
// gyroscope (sensors_plus, fail-soft) to warn "לאט יותר" on too-fast turns.
// ════════════════════════════════════════════════════════════════════════════

class _GuidedVideoCaptureScreen extends StatefulWidget {
  const _GuidedVideoCaptureScreen();

  @override
  State<_GuidedVideoCaptureScreen> createState() =>
      _GuidedVideoCaptureScreenState();
}

class _GuidedVideoCaptureScreenState extends State<_GuidedVideoCaptureScreen> {
  // Soft minimum: keep "סיום" disabled until ~10s of footage so the room is
  // covered while walking (matches the "10–40 שניות" coaching). Hard cap:
  // auto-stop at 2.5 min, safely under KIRI's 3-min limit (and keeps the upload
  // size manageable).
  static const Duration _minDuration = Duration(seconds: 10);
  static const Duration _maxDuration = Duration(seconds: 150);

  CameraController? _cam;
  String? _error;
  bool _recording = false;
  bool _stopping = false;
  Duration _elapsed = Duration.zero;
  // Wall-clock start so the timer stays accurate even if a frame is dropped.
  DateTime? _startedAt;

  // Pre-capture coaching: show the steps card first; recording can't start until
  // the user taps "הבנתי, מתחילים". This is where we make "WALK, don't rotate"
  // unmissable for a non-expert.
  bool _showSteps = true;

  // Live too-fast-motion coaching via the gyroscope (fail-soft: if the sensor
  // isn't available we simply never warn). Above this rotation rate the user is
  // spinning rather than walking, which kills parallax.
  static const double _tooFastRadPerSec = 1.2;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  bool _tooFast = false;
  DateTime? _tooFastUntil;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) throw StateError('no camera');
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      // ResolutionPreset.high == 720p — under KIRI's 1920×1080 cap, with a
      // reliably-uploadable file size. (veryHigh == 1080p is the hard ceiling.)
      final ctrl = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await ctrl.initialize();
      if (!mounted) {
        await ctrl.dispose();
        return;
      }
      setState(() => _cam = ctrl);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = AppLocalizations.of(context)!.roomScanFlow0456e9f5);
      }
    }
  }

  Future<void> _startRecording() async {
    final cam = _cam;
    if (cam == null || _recording || _stopping) return;
    try {
      await cam.startVideoRecording();
      if (!mounted) return;
      _startedAt = DateTime.now();
      setState(() {
        _recording = true;
        _elapsed = Duration.zero;
      });
      _tick();
      _listenMotion();
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = AppLocalizations.of(context)!.roomScanFlow07c6ea97);
      }
    }
  }

  /// Re-arms a ~250ms timer that refreshes the on-screen clock and auto-stops
  /// at the hard cap. Uses wall-clock time so it never drifts.
  void _tick() {
    if (!_recording || !mounted) return;
    Future<void>.delayed(const Duration(milliseconds: 250)).then((_) {
      if (!_recording || !mounted) return;
      final started = _startedAt;
      if (started == null) return;
      setState(() => _elapsed = DateTime.now().difference(started));
      if (_elapsed >= _maxDuration) {
        _stopAndFinish();
      } else {
        _tick();
      }
    });
  }

  /// Listens to the gyroscope while recording and flags too-fast rotation, so we
  /// can flash "לאט יותר". Fully fail-soft — any sensor error just disables it.
  void _listenMotion() {
    _gyroSub?.cancel();
    try {
      _gyroSub = gyroscopeEventStream().listen(
        (e) {
          if (!_recording || !mounted) return;
          final rate = e.x.abs() + e.y.abs() + e.z.abs();
          if (rate > _tooFastRadPerSec) {
            _tooFastUntil = DateTime.now().add(const Duration(milliseconds: 900));
            if (!_tooFast) setState(() => _tooFast = true);
          } else if (_tooFast &&
              (_tooFastUntil == null ||
                  DateTime.now().isAfter(_tooFastUntil!))) {
            setState(() => _tooFast = false);
          }
        },
        onError: (_) {/* sensor unavailable — coaching stays silent */},
        cancelOnError: true,
      );
    } catch (_) {/* no gyro on this device — fail soft */}
  }

  Future<void> _stopAndFinish() async {
    final cam = _cam;
    if (cam == null || !_recording || _stopping) return;
    _gyroSub?.cancel();
    setState(() {
      _stopping = true;
      _recording = false;
      _tooFast = false;
    });
    try {
      final file = await cam.stopVideoRecording();
      if (!mounted) return;
      Navigator.of(context).pop(File(file.path));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stopping = false;
        _error = AppLocalizations.of(context)!.roomScanFlow2e7c798b;
      });
    }
  }

  bool get _reachedMin => _elapsed >= _minDuration;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  void dispose() {
    _gyroSub?.cancel();
    // If we're still mid-recording when leaving, stop it so the controller can
    // be disposed cleanly (best-effort — never throw out of dispose).
    final cam = _cam;
    if (cam != null && cam.value.isRecordingVideo) {
      cam.stopVideoRecording().catchError((_) => XFile('')).whenComplete(
            cam.dispose,
          );
    } else {
      cam?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: _error != null
            ? _errorView()
            : SafeArea(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_cam != null)
                      CameraPreview(_cam!)
                    else
                      const Center(
                        child:
                            CircularProgressIndicator(color: Colors.white),
                      ),
                    if (_showSteps)
                      _PreCaptureSteps(
                        onStart: () => setState(() => _showSteps = false),
                        onCancel: () => Navigator.of(context).pop(),
                      )
                    else ...[
                      _topGuide(),
                      _bottomControls(),
                    ],
                  ],
                ),
              ),
      ),
    );
  }

  Widget _errorView() {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_rounded,
                  color: Colors.white, size: 56),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontSize: 16, height: 1.4),
              ),
              const SizedBox(height: 20),
              _BigButton(
                label: l10n.roomScanFlow8c634e7d,
                icon: Icons.refresh_rounded,
                onTap: () {
                  setState(() => _error = null);
                  _init();
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  l10n.roomScanFlow10a2352b,
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topGuide() {
    final l10n = AppLocalizations.of(context)!;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Text(
              l10n.roomScanFlow6adc6ba3,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _recording
                  ? l10n.roomScanFlowE75f74eb
                  : '${l10n.roomScanFlowB47f0996}${l10n.roomScanFlow31a6628a}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 14, height: 1.4),
            ),
            if (_recording && _tooFast) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.coral,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.slow_motion_video_rounded,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      l10n.roomScanFlowA4e445a8,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bottomControls() {
    final l10n = AppLocalizations.of(context)!;
    final canFinish = _recording && _reachedMin && !_stopping;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // live timer pill
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_recording) ...[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppColors.coral,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    _recording ? _fmt(_elapsed) : l10n.roomScanFlow38abfe79,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (_recording && !_reachedMin) ...[
              const SizedBox(height: 8),
              Text(
                l10n.roomScanFlow1378e918(_minDuration.inSeconds),
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                // cancel
                _CircleAction(
                  icon: Icons.close_rounded,
                  onTap: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                // big record / stop button
                GestureDetector(
                  onTap: _stopping
                      ? null
                      : (_recording
                          ? (canFinish ? _stopAndFinish : null)
                          : _startRecording),
                  child: Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(
                          color: AppColors.coral, width: 5),
                    ),
                    child: _stopping
                        ? const Padding(
                            padding: EdgeInsets.all(26),
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: AppColors.coral,
                            ),
                          )
                        : Center(
                            child: _recording
                                ? Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: canFinish
                                          ? AppColors.coral
                                          : Colors.grey,
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                  )
                                : Container(
                                    width: 64,
                                    height: 64,
                                    decoration: const BoxDecoration(
                                      color: AppColors.coral,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                          ),
                  ),
                ),
                const Spacer(),
                // finish (only meaningful while recording)
                _CircleAction(
                  icon: Icons.check_rounded,
                  enabled: canFinish,
                  highlighted: canFinish,
                  onTap: _stopAndFinish,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  _CircleAction({
    required this.icon,
    required this.onTap,
    this.enabled = true,
    this.highlighted = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: highlighted
              ? AppColors.primary
              : Colors.black.withValues(alpha: 0.55),
        ),
        child: Icon(
          icon,
          color: enabled ? Colors.white : Colors.white38,
          size: 28,
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// PRE-CAPTURE STEPS — the coaching card shown before recording starts
// ────────────────────────────────────────────────────────────────────────────
// Big, simple, older-user friendly. The non-negotiable message — WALK slowly,
// don't rotate in place — is given the loudest, most prominent treatment because
// it's the #1 reason a scan comes out as scattered garbage.
// ════════════════════════════════════════════════════════════════════════════

class _PreCaptureSteps extends StatelessWidget {
  const _PreCaptureSteps({required this.onStart, required this.onCancel});

  final VoidCallback onStart;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      color: Colors.black.withValues(alpha: 0.82),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      l10n.roomScanFlow61451131,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.roomScanFlow2b81583a,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // THE big one — walk, don't rotate. Loudest treatment.
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.coral.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.coral, width: 2),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.directions_walk_rounded,
                              color: Colors.white, size: 46),
                          const SizedBox(height: 10),
                          Text(
                            l10n.roomScanFlow1850a1a2,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${l10n.roomScanFlowDff3d215}${l10n.roomScanFlow0547a915}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    _StepRow(
                      icon: Icons.loop_rounded,
                      text: l10n.roomScanFlow0bbdefc1,
                    ),
                    _StepRow(
                      icon: Icons.timelapse_rounded,
                      text: l10n.roomScanFlowBacd6c42,
                    ),
                    _StepRow(
                      icon: Icons.wb_sunny_rounded,
                      text: l10n.roomScanFlow9486adab,
                    ),
                    _StepRow(
                      icon: Icons.timer_rounded,
                      text: l10n.roomScanFlow1950d47d,
                    ),
                  ],
                ),
              ),
              _BigButton(
                label: l10n.roomScanFlow308645b1,
                icon: Icons.videocam_rounded,
                onTap: onStart,
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: onCancel,
                child: Text(
                  l10n.roomScanFlowA7c55a8d,
                  style: const TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// CLOUD RECONSTRUCT — calm full-screen progress while KIRI builds the room
// ════════════════════════════════════════════════════════════════════════════

class _CloudReconstructScreen extends StatefulWidget {
  const _CloudReconstructScreen({
    required this.propertyId,
    required this.files,
  });

  final String propertyId;
  final List<File> files;

  @override
  State<_CloudReconstructScreen> createState() =>
      _CloudReconstructScreenState();
}

class _CloudReconstructScreenState extends State<_CloudReconstructScreen> {
  late String _stage;
  bool _failed = false;
  String _failMessage = '';
  // Set once KIRI accepts the job: from this point the reconstruction continues
  // in the BACKGROUND, so the user can safely leave and we'll surface the model
  // on the property when it's ready (via the finalizer).
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _stage = AppLocalizations.of(context)!.roomScanFlow99a47392;
    _run();
  }

  // A raw recording (iOS HEVC ~72MB/30s) loses the S3 upload race on cellular,
  // so the job never starts. We MUST transcode down before uploading — never
  // fall back to the giant original. Above this, abort with a clear message.
  static const int _maxUploadBytes = 40 * 1024 * 1024; // ~40MB

  Future<void> _run() async {
    try {
      // iOS records HEVC/.mov, which KIRI rejects (uploads fine but fails
      // reconstruction). Transcode to a small H.264 mp4 first. This is NOT
      // fail-soft: if we can't produce a sane-sized file we abort with a clear
      // message rather than silently uploading a 72MB raw clip that 403s out.
      var files = widget.files;
      if (files.isNotEmpty) {
        if (mounted) {
          setState(() =>
              _stage = AppLocalizations.of(context)!.roomScanFlow01b0a145);
        }
        final prepared = await _prepareVideo(files.first);
        if (prepared == null) {
          if (!mounted) return;
          setState(() {
            _failed = true;
            _failMessage = AppLocalizations.of(context)!.roomScanFlow9f0b5118;
          });
          return;
        }
        files = [prepared];
      }
      final job = await Kiri3dService.instance.runScan(
        propertyId: widget.propertyId,
        captureType: Scan3dCaptureType.video,
        files: files,
        // Fast mode: splat-only (KIRI isMesh=0) — much quicker, and the Gaussian
        // splat already serves both the 360 look-around and the 3D walkthrough.
        fast: true,
        onSubmitted: (jobId) {
          // KIRI now owns the job and keeps reconstructing even if this screen
          // closes. Persist it so the background finalizer fetches the finished
          // model and attaches it to the property — the user can leave now.
          unawaited(PendingScanStore.instance.add(PendingScan(
            jobId: jobId,
            propertyId: widget.propertyId,
            submittedAt: DateTime.now().toUtc(),
          )));
          if (mounted) setState(() => _submitted = true);
        },
        onUpdate: (j) {
          if (!mounted) return;
          setState(() => _stage = _stageLabel(j.status));
        },
      );
      if (!mounted) return;
      // A client-side poll TIMEOUT is not terminal — KIRI keeps reconstructing.
      // KEEP the pending record so the background finalizer attaches the finished
      // model; removing it here would orphan a billed reconstruction. Only drop
      // the record on a genuine terminal (ready / server-failed).
      if (!job.timedOut) {
        unawaited(PendingScanStore.instance.remove(job.jobId));
      }
      Navigator.of(context).pop(job);
    } on Kiri3dException catch (e) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _failMessage = _failMessageFor(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _failMessage = AppLocalizations.of(context)!.roomScanFlow7544bafb;
      });
    }
  }

  /// Transcodes [source] to a small H.264 mp4 suitable for a reliable mobile
  /// upload. Retries once on failure. Returns the prepared file, or null if we
  /// couldn't produce a sane-sized file (caller shows a clear error and never
  /// uploads the raw original).
  Future<File?> _prepareVideo(File source) async {
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final info = await VideoCompress.compressVideo(
          source.path,
          // MediumQuality ≈ 720p low-bitrate (~5–15MB/30s): reliable mobile
          // upload + plenty of detail for KIRI frame extraction. HighestQuality
          // ballooned a 30s clip to ~72MB and the S3 upload kept failing.
          quality: VideoQuality.MediumQuality,
          deleteOrigin: false,
          includeAudio: false,
        );
        final out = info?.path;
        if (out == null || out.trim().isEmpty) {
          debugPrint('room_scan_flow: transcode returned null (attempt $attempt)');
          continue;
        }
        final file = File(out);
        final size = await file.length();
        debugPrint('room_scan_flow: transcoded to ${size ~/ 1024}KB (attempt $attempt)');
        if (size > _maxUploadBytes) {
          // Still too big to upload reliably — abort rather than lose the race.
          debugPrint('room_scan_flow: transcode still >${_maxUploadBytes ~/ (1024 * 1024)}MB, aborting');
          return null;
        }
        return file;
      } catch (e) {
        debugPrint('room_scan_flow: transcode failed (attempt $attempt): $e');
      }
    }
    return null;
  }

  String _failMessageFor(Kiri3dException e) {
    final l10n = AppLocalizations.of(context)!;
    final code = e.statusCode;
    // runScan tags upload failures with "Failed to upload capture …": a 403/401
    // here is an EXPIRED/rejected presigned S3 PUT (not an app-auth gate), a 5xx
    // is S3 server trouble, and a null code means the PUT never reached a server.
    if (e.message.contains('upload')) {
      if (code == 403 || code == 401) {
        return l10n.roomScanFlowAdcb2cfd;
      }
      if (code != null && code >= 500) {
        return l10n.roomScanFlowE70ac353;
      }
      return l10n.roomScanFlow26def34f;
    }
    // Otherwise the code comes from OUR API (createJob/start): 401/403 = auth,
    // 503 = not-yet-configured → feature gate.
    if (e.isUnauthorized || code == 503) {
      return l10n.roomScanFlow300d9689;
    }
    // Every exception that reaches here is PRE-reconstruction (job creation or
    // KIRI submission), so it is NEVER about the user's video — refilming can't
    // help. A 5xx (KIRI submit error / out-of-credits / server overload) or any
    // other create/start failure is a SERVICE issue: say so honestly instead of
    // blaming the capture. (Genuine bad-video failures surface separately, as a
    // non-ready terminal job → the "film again" message in _startCloudCapture.)
    return l10n.roomScanFlow00bc930c;
  }

  String _stageLabel(Scan3dStatus status) {
    final l10n = AppLocalizations.of(context)!;
    switch (status) {
      case Scan3dStatus.created:
      case Scan3dStatus.uploading:
        return l10n.roomScanFlow99a47392;
      case Scan3dStatus.processing:
        return l10n.roomScanFlow759375ce;
      case Scan3dStatus.ready:
        return l10n.roomScanFlow896799e7;
      case Scan3dStatus.failed:
        return l10n.roomScanFlow898d60f3;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        backgroundColor: AppColors.navy,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: _failed ? _failView() : _progressView(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _progressView() {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 64,
          height: 64,
          child: CircularProgressIndicator(
            strokeWidth: 5,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 28),
        Text(
          _stage,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _submitted
              ? '${l10n.roomScanFlow8ee8ef51}${l10n.roomScanFlow0014a7cc}'
              : l10n.roomScanFlowB412b4d4,
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white70, fontSize: 15, height: 1.4),
        ),
        if (_submitted) ...[
          const SizedBox(height: 28),
          _BigButton(
            label: l10n.roomScanFlow5ebf63d5,
            icon: Icons.check_rounded,
            filled: false,
            onTap: () {
              // Leave the in-flight job in the pending store; the finalizer will
              // attach the model to the property when it's ready.
              Navigator.of(context).pop();
            },
          ),
        ],
      ],
    );
  }

  Widget _failView() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.sentiment_dissatisfied_rounded,
            color: Colors.white, size: 64),
        const SizedBox(height: 20),
        Text(
          _failMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 28),
        _BigButton(
          label: AppLocalizations.of(context)!.roomScanFlow10a2352b,
          icon: Icons.arrow_forward_rounded,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SHARED WIDGETS + SHEETS
// ════════════════════════════════════════════════════════════════════════════

/// One large, finger-friendly action button.
class _BigButton extends StatelessWidget {
  _BigButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: Material(
        color: filled ? AppColors.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: filled
                  ? null
                  : Border.all(color: AppColors.primary, width: 2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    color: filled ? Colors.white : AppColors.primary,
                    size: 24),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    color: filled ? Colors.white : AppColors.primary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  _OptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.highlighted,
    required this.busy,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool highlighted;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: highlighted ? AppColors.primaryLight2 : AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: highlighted ? AppColors.primary : AppColors.borderLight,
              width: highlighted ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: highlighted ? AppColors.primary : AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: highlighted ? Colors.white : AppColors.primary,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.navy,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (busy)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.primary,
                    ),
                  ),
                )
              else
                const Icon(Icons.chevron_left_rounded,
                    color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// Short, plain-language interior-scan consent. One approve button.
Future<bool?> _showConsentSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final l10n = AppLocalizations.of(context)!;
      return Directionality(
        textDirection: Directionality.of(context),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 22),
                Icon(Icons.privacy_tip_rounded,
                    color: AppColors.primary, size: 48),
                const SizedBox(height: 16),
                Text(
                  l10n.roomScanFlowDb00bbc5,
                  style: const TextStyle(
                    color: AppColors.navy,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${l10n.roomScanFlow72a231e3}${l10n.roomScanFlow4181010d}'
                  '${l10n.roomScanFlow3998aa13}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),
                _BigButton(
                  label: l10n.roomScanFlow86690080,
                  icon: Icons.check_rounded,
                  onTap: () => Navigator.of(ctx).pop(true),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text(
                    l10n.roomScanFlow98c8a5b8,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

/// Asks the user to name the room. Returns the chosen name or null on cancel.
Future<String?> showRoomNameSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  final suggestions = [
    l10n.roomScanFlowC8bdd6d8,
    l10n.roomScanFlowF5ed1ccb,
    l10n.roomScanFlow9c1d4cb5,
    l10n.roomScanFlow76fd685b,
    l10n.roomScanFlow9e01255f,
    l10n.roomScanFlow86425fcf,
    l10n.roomScanFlow71b2324b,
    l10n.roomScanFlow0744519a,
  ];
  final controller = TextEditingController();

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Directionality(
        textDirection: Directionality.of(context),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.borderLight,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.roomScanFlow28944cb8,
                    style: const TextStyle(
                      color: AppColors.navy,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: suggestions
                        .map(
                          (s) => GestureDetector(
                            onTap: () => Navigator.of(ctx).pop(s),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight2,
                                borderRadius: BorderRadius.circular(30),
                                border: Border.all(
                                    color: AppColors.borderLight),
                              ),
                              child: Text(
                                s,
                                style: const TextStyle(
                                  color: AppColors.navy,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: controller,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      hintText: l10n.roomScanFlow3e705bfd,
                      filled: true,
                      fillColor: AppColors.background,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: AppColors.borderLight),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _BigButton(
                    label: l10n.roomScanFlowE6932339,
                    icon: Icons.check_rounded,
                    onTap: () {
                      final name = controller.text.trim();
                      Navigator.of(ctx)
                          .pop(name.isEmpty ? l10n.roomScanFlow463d28e8 : name);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
