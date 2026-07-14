import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/kiri_3d_service.dart';
import 'package:dating_app/core/services/pending_scan_store.dart';
import 'package:dating_app/core/services/roomplan_service.dart';
import 'package:dating_app/data/models/scan3d_job.dart';
import 'package:dating_app/data/models/scanned_room.dart';
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
    return Directionality(
      textDirection: TextDirection.rtl,
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
            title: const Text(
              'סריקת חדרים בתלת-מימד',
              style: TextStyle(
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
                      const Text(
                        'סורקים חדר אחרי חדר. כל חדר נשמר באיכות גבוהה, וכולם '
                        'מחוברים יחד לסיור תלת-מימדי של הדירה.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 15,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_rooms.isEmpty)
                        _emptyState()
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
                _bottomBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
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
          const Text(
            'עוד לא נסרקו חדרים',
            style: TextStyle(
              color: AppColors.navy,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'לחצו על "הוספת חדר" כדי להתחיל',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _bottomBar() {
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
            label: 'הוספת חדר',
            icon: Icons.add_rounded,
            onTap: _addRoom,
          ),
          if (_rooms.isNotEmpty) ...[
            const SizedBox(height: 10),
            _BigButton(
              label: 'סיימתי (${_rooms.length} חדרים)',
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
  const _RoomCard({
    required this.room,
    required this.onPreview,
    required this.onRemove,
  });

  final ScannedRoom room;
  final VoidCallback onPreview;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
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
                      viewable ? 'מוכן לצפייה' : 'נסרק',
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
              tooltip: 'צפייה',
            ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppColors.coral, size: 24),
            tooltip: 'מחיקה',
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
        _error = 'הסריקה המהירה נכשלה. אפשר לנסות את הסריקה עם הצילום במקום.';
      });
    }
  }

  Future<void> _startCloudCapture() async {
    if (!Kiri3dService.instance.isConfigured) {
      _showComingSoon();
      return;
    }
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
    if (!job.isReady) {
      setState(() => _error =
          'בניית החדר נכשלה. נסו לצלם סרטון שוב באור טוב, תוך כדי הליכה '
          'איטית בחדר — לא להסתובב במקום.');
      return;
    }

    final named = await _askRoomName();
    if (!mounted) return;
    // Never throw away a completed, minutes-long, billed reconstruction: if the
    // landlord dismisses the name sheet we keep the room with a default name
    // (they can rename it) instead of silently discarding the scan.
    final roomName = (named == null || named.trim().isEmpty)
        ? 'חדר ${widget.roomNumber}'
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

  void _showComingSoon() {
    showDialog<void>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('התכונה תיפתח בקרוב',
              style: TextStyle(fontWeight: FontWeight.w900)),
          content: const Text(
            'סריקת התלת-מימד עדיין לא פעילה בחשבון הזה. בקרוב תוכלו לסרוק '
            'את הדירה חדר-חדר.',
            style: TextStyle(fontSize: 15, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('הבנתי'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          foregroundColor: AppColors.navy,
          title: Text(
            'חדר ${widget.roomNumber}',
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
              const Text(
                'איך תרצו לסרוק את החדר?',
                style: TextStyle(
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
                  title: 'סריקה מהירה (אייפון Pro)',
                  subtitle:
                      'מעבירים את הטלפון לאט סביב החדר. מוכן תוך כמה שניות.',
                  icon: Icons.bolt_rounded,
                  highlighted: true,
                  busy: _busy,
                  onTap: _busy ? null : _startRoomPlan,
                ),
              if (widget.supportsRoomPlan) const SizedBox(height: 12),
              _OptionCard(
                title: 'סריקה עם סרטון (מתקדם)',
                subtitle:
                    'מצלמים סרטון תוך כדי הליכה איטית בחדר, ואנחנו בונים '
                    'אותו בתלת-מימד. האיכות תלויה בצילום — נדריך אתכם צעד-צעד.',
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

  static String _friendlyRoomPlanError(RoomPlanException e) {
    switch (e.code) {
      case 'unsupported':
        return 'המכשיר הזה לא תומך בסריקה המהירה. אפשר לסרוק עם הצילום.';
      case 'scan_busy':
        return 'סריקה כבר פעילה. נסו שוב בעוד רגע.';
      default:
        return 'הסריקה המהירה נכשלה. אפשר לנסות שוב או לסרוק עם הצילום.';
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
        setState(() => _error =
            'לא ניתן לפתוח את המצלמה. בדקו שאישרתם גישה למצלמה ונסו שוב.');
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
        setState(() => _error =
            'לא הצלחנו להתחיל הקלטה. נסו שוב, ובדקו שיש מקום פנוי בטלפון.');
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
        _error = 'שמירת הסרטון נכשלה. נסו לצלם שוב.';
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
      textDirection: TextDirection.rtl,
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
                label: 'נסו שוב',
                icon: Icons.refresh_rounded,
                onTap: () {
                  setState(() => _error = null);
                  _init();
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text(
                  'חזרה',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topGuide() {
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
            const Text(
              'צלמו תוך כדי הליכה איטית',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _recording
                  ? 'המשיכו ללכת לאט סביב החדר — אל תסתובבו במקום'
                  : 'הקיפו את החדר והרהיטים תוך כדי הליכה איטית. '
                      'אל תסתובבו במקום. כ-10–40 שניות, באור טוב.',
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
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.slow_motion_video_rounded,
                        color: Colors.white, size: 18),
                    SizedBox(width: 6),
                    Text(
                      'לאט יותר',
                      style: TextStyle(
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
                    _recording ? _fmt(_elapsed) : 'מוכנים לצילום',
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
                'המשיכו עוד מעט (לפחות ${_minDuration.inSeconds} שניות)',
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
  const _CircleAction({
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
                    const Text(
                      'איך לצלם סריקת חדר טובה',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'סריקה מתקדמת. האיכות תלויה בצילום — קחו את הזמן.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
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
                      child: const Column(
                        children: [
                          Icon(Icons.directions_walk_rounded,
                              color: Colors.white, size: 46),
                          SizedBox(height: 10),
                          Text(
                            'הליכו לאט בחדר — אל תסתובבו במקום!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              height: 1.35,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'הקיפו את החדר והרהיטים תוך כדי הליכה. '
                            'סיבוב במקום (כמו פנורמה) הורס את התלת-מימד.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
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
                      text: 'הקיפו את החדר והרהיטים — צלמו מכמה כיוונים',
                    ),
                    _StepRow(
                      icon: Icons.timelapse_rounded,
                      text: 'שמרו חפיפה — תנועה רציפה ואיטית, בלי קפיצות',
                    ),
                    _StepRow(
                      icon: Icons.wb_sunny_rounded,
                      text: 'תאורה טובה, בלי תזוזות מהירות',
                    ),
                    _StepRow(
                      icon: Icons.timer_rounded,
                      text: 'משך הצילום: כ-10 עד 40 שניות',
                    ),
                  ],
                ),
              ),
              _BigButton(
                label: 'הבנתי, מתחילים',
                icon: Icons.videocam_rounded,
                onTap: onStart,
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: onCancel,
                child: const Text(
                  'ביטול',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
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
  String _stage = 'מעלים את הסרטון…';
  bool _failed = false;
  String _failMessage = '';
  // Set once KIRI accepts the job: from this point the reconstruction continues
  // in the BACKGROUND, so the user can safely leave and we'll surface the model
  // on the property when it's ready (via the finalizer).
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
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
        if (mounted) setState(() => _stage = 'מכינים את הסרטון…');
        final prepared = await _prepareVideo(files.first);
        if (prepared == null) {
          if (!mounted) return;
          setState(() {
            _failed = true;
            _failMessage = 'לא הצלחנו להכין את הסרטון — נסו שוב.';
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
      // Job reached a terminal state while the screen was open — it's no longer
      // pending, so drop the background record before returning the result.
      unawaited(PendingScanStore.instance.remove(job.jobId));
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
        _failMessage = 'משהו השתבש. נסו שוב.';
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

  static String _failMessageFor(Kiri3dException e) {
    final code = e.statusCode;
    // runScan tags upload failures with "Failed to upload capture …": a 403/401
    // here is an EXPIRED/rejected presigned S3 PUT (not an app-auth gate), a 5xx
    // is S3 server trouble, and a null code means the PUT never reached a server.
    if (e.message.contains('upload')) {
      if (code == 403 || code == 401) {
        return 'פג תוקף ההעלאה. נסו שוב — הפעם זה יעלה מהר יותר.';
      }
      if (code != null && code >= 500) {
        return 'תקלת שרת בהעלאה. נסו שוב עוד רגע.';
      }
      return 'ההעלאה נכשלה בגלל החיבור. בדקו את האינטרנט ונסו שוב.';
    }
    // Otherwise the code comes from OUR API (createJob/start): 401/403 = auth,
    // 503 = not-yet-configured → feature gate.
    if (e.isUnauthorized || code == 503) {
      return 'התכונה תיפתח בקרוב.';
    }
    return 'בניית החדר נכשלה. נסו לצלם שוב באור טוב, תוך כדי הליכה '
        'איטית בחדר — לא להסתובב במקום.';
  }

  static String _stageLabel(Scan3dStatus status) {
    switch (status) {
      case Scan3dStatus.created:
      case Scan3dStatus.uploading:
        return 'מעלים את הסרטון…';
      case Scan3dStatus.processing:
        return 'בונים את החדר בתלת-מימד… כמה דקות';
      case Scan3dStatus.ready:
        return 'כמעט מוכן…';
      case Scan3dStatus.failed:
        return 'נכשל';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
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
              ? 'הסריקה ממשיכה ברקע — אפשר לעזוב את המסך. '
                  'המודל יופיע על הדירה כשיהיה מוכן (כמה דקות).'
              : 'אפשר להשאיר את המסך פתוח. אנחנו מודיעים כשמוכן.',
          textAlign: TextAlign.center,
          style: const TextStyle(
              color: Colors.white70, fontSize: 15, height: 1.4),
        ),
        if (_submitted) ...[
          const SizedBox(height: 28),
          _BigButton(
            label: 'המשך ברקע',
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
          label: 'חזרה',
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
  const _BigButton({
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
  const _OptionCard({
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
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
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
              const Text(
                'לפני שמתחילים לסרוק',
                style: TextStyle(
                  color: AppColors.navy,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'הסריקה מצלמת את פנים הדירה. הסריקה תוצג לשוכרים מתעניינים '
                'ועשויה להישמר אצלנו. אל תצלמו מסמכים אישיים או דברים שאתם '
                'לא רוצים להראות.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              _BigButton(
                label: 'הבנתי, אפשר להתחיל',
                icon: Icons.check_rounded,
                onTap: () => Navigator.of(ctx).pop(true),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text(
                  'לא עכשיו',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Asks the user to name the room. Returns the chosen name or null on cancel.
Future<String?> showRoomNameSheet(BuildContext context) {
  const suggestions = [
    'סלון',
    'מטבח',
    'חדר שינה',
    'חדר ילדים',
    'חדר רחצה',
    'מרפסת',
    'פינת אוכל',
    'מסדרון',
  ];
  final controller = TextEditingController();

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Directionality(
        textDirection: TextDirection.rtl,
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
                  const Text(
                    'איך לקרוא לחדר?',
                    style: TextStyle(
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
                      hintText: 'או הקלידו שם אחר',
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
                    label: 'שמירה',
                    icon: Icons.check_rounded,
                    onTap: () {
                      final name = controller.text.trim();
                      Navigator.of(ctx).pop(name.isEmpty ? 'חדר' : name);
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
