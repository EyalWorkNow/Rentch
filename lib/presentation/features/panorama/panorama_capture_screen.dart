import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/core/services/pending_pano_store.dart';
import 'package:dating_app/data/models/panorama_tour.dart';
import 'package:dating_app/presentation/features/panorama/panorama_align_screen.dart';
import 'package:dating_app/presentation/features/panorama/panorama_map_placement.dart';
import 'package:dating_app/presentation/features/panorama/panorama_pole_capture.dart';
import 'package:dating_app/presentation/features/panorama/panorama_psv_tour.dart';
import 'package:dating_app/presentation/features/panorama/panorama_sphere_capture.dart';
import 'package:dating_app/presentation/features/panorama/panorama_sweep_capture.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:image_picker/image_picker.dart';

/// Guided creation of a Street-View-style 360° tour: the landlord adds one
/// panorama per point in the apartment; points are auto-linked into a walkable
/// path. Returns the built [PropertyPanoramaTour] via Navigator.pop.
class PanoramaCaptureScreen extends StatefulWidget {
  const PanoramaCaptureScreen({super.key, this.initial});

  final PropertyPanoramaTour? initial;

  @override
  State<PanoramaCaptureScreen> createState() => _PanoramaCaptureScreenState();
}

class _PanoramaCaptureScreenState extends State<PanoramaCaptureScreen> {
  final _picker = ImagePicker();
  final List<PanoramaNode> _nodes = [];
  bool _busy = false;
  String? _floorPlanPath; // optional floor-plan image, reused across points
  // Node ids currently auto-completing to full 360 in the background (silent —
  // shows a small spinner on the tile, never a blocking modal).
  final Set<String> _enhancing = {};

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _nodes.addAll(widget.initial!.nodes);
    // Reconnect any enhance jobs left running when the screen was last closed.
    unawaited(_resumePendingEnhances());
  }

  // Sequentially link points: each gets a forward arrow to the next and a back
  // arrow to the previous. (Hotspots are placed ahead/behind by default.)
  // Walk-between-rooms tour (Street-View style): every point links to every other
  // point, and each arrow points toward that room's REAL position on the floor
  // map (bearing from this point to the target), so navigation follows the layout
  // you placed — not a fixed forward/back chain.
  PropertyPanoramaTour _buildTour() {
    final linked = <PanoramaNode>[];
    for (var i = 0; i < _nodes.length; i++) {
      final from = _nodes[i];
      final hotspots = <PanoramaHotspot>[];
      for (var j = 0; j < _nodes.length; j++) {
        if (j == i) continue;
        final to = _nodes[j];
        double bearing;
        if (from.hasPosition || to.hasPosition) {
          // Map coords: x = left→right, y = top→bottom. Treat "up" (−y) as
          // forward; bearing 0°=forward, clockwise. Approximate (the pano's north
          // isn't calibrated to the map) but gives consistent directional arrows.
          final dx = (to.x ?? 0.5) - (from.x ?? 0.5);
          final dy = (to.y ?? 0.5) - (from.y ?? 0.5);
          bearing = (dx == 0 && dy == 0)
              ? 0.0
              : (math.atan2(dx, -dy) * 180 / math.pi + 360) % 360;
        } else {
          // No floor placement (e.g. a bulk gallery import): spread the arrows
          // evenly around the ring so they don't all stack on one spot.
          bearing = (j * 360.0 / _nodes.length) % 360;
        }
        hotspots.add(PanoramaHotspot(
          targetNodeId: to.id,
          longitude: bearing,
          label: to.label,
        ));
      }
      linked.add(from.copyWith(hotspots: hotspots));
    }
    return PropertyPanoramaTour(nodes: linked);
  }

  // Cap imported panoramas at this width: WebGL MAX_TEXTURE_SIZE is 4096 on many
  // mobile GPUs and Pannellum refuses larger images. image_picker downscales
  // natively at pick time (cheap + low memory), so the result always renders.
  static const double _maxPanoWidth = 4096;

  // Shared: name → mandatory upload → place on the map → add the node.
  Future<void> _uploadAndAdd({
    required String path,
    required String contentType,
    double haov = 360,
    double vaov = 180,
    String? autoLabel,
  }) async {
    // Bulk imports pass an autoLabel so the landlord isn't prompted per image.
    final label = autoLabel ?? await _askLabel('נקודה ${_nodes.length + 1}');
    if (label == null || !mounted) return;

    setState(() => _busy = true);
    // Upload is MANDATORY: a tour must live at a network URL so tenants on other
    // devices can view it. A local path would only work on this phone.
    String? url;
    try {
      url = await AwsApiClient.instance
          .uploadFile(path, folder: 'panoramas', contentType: contentType);
    } catch (_) {
      url = null;
    }
    if (!mounted) return;
    if (url == null || url.isEmpty) {
      setState(() => _busy = false);
      _toast('ההעלאה נכשלה — בדוק את החיבור ונסה שוב. '
          'הסיור חייב להיות מועלה כדי שאחרים יוכלו לצפות.');
      return;
    }
    setState(() => _busy = false);
    await _addNode(url: url, label: label, haov: haov, vaov: vaov);
  }

  // Add a real panorama shot with the phone's NATIVE panorama mode (one smooth
  // sweep, a few seconds — far better quality than frame-by-frame OpenCV
  // stitching, and no server round-trip). A phone pano is a wide cylindrical
  // strip with partial vertical FOV, so we display it as a partial panorama
  // (haov/vaov) rather than forcing a full sphere: Pannellum places it at the
  // correct latitude band with honest, un-stretched poles.
  Future<void> _capturePano() async {
    if (_busy) return;

    // GUIDED FIRST: show the big explainer with TWO clear choices. PRIMARY =
    // the in-app guided sweep (one slow spin; the yaw/gyro/blur/crop are now
    // fixed so a single real turn = one full 360° ring). SECONDARY = import a
    // panorama the landlord already shot in the phone's native camera mode.
    final choice = await Navigator.of(context).push<_CaptureChoice>(
      MaterialPageRoute(builder: (_) => const _PanoramaGuideScreen()),
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case _CaptureChoice.photo:
        await _captureWithPhotos();
      case _CaptureChoice.sweep:
        await _captureWithSweep();
      case _CaptureChoice.arranged:
        await _composeFromPanoramas();
      case _CaptureChoice.gallery:
        await _importFromGallery();
      case _CaptureChoice.ai:
        await _generateWithAi();
    }
  }

  // HIGH-QUALITY path: import several NATIVE phone panoramas and arrange them on
  // a 360° track; the server stitches them into one full equirectangular pano.
  // Returns a finished [PanoramaSweepResult] — added as a node exactly like the
  // sweep/video/import results (same _addNode call).
  Future<void> _composeFromPanoramas() async {
    final result = await Navigator.of(context).push<PanoramaSweepResult>(
      MaterialPageRoute(builder: (_) => const PanoramaAlignScreen()),
    );
    if (result == null || !mounted) return;

    final label = await _askLabel('נקודה ${_nodes.length + 1}');
    if (label == null || !mounted) return;
    await _addNode(
      url: result.imageUrl,
      label: label,
      haov: result.haov,
      vaov: result.vaov,
    );
  }

  // PRIMARY (default): the guided 10-PHOTO 360° capture. The user stands in one
  // spot and shoots 10 overlapping stills at 0.5× ultra-wide; the screen uploads
  // them with their known poses, runs the server stitch, and returns a finished
  // [PanoramaSweepResult] — we add it as a node EXACTLY like the sweep/import
  // result (same _addNode call). This replaces the broken video→360 flow.
  Future<void> _captureWithPhotos() async {
    final result = await Navigator.of(context).push<PanoramaSweepResult>(
      MaterialPageRoute(builder: (_) => const PanoramaSphereCaptureScreen()),
    );
    if (result == null || !mounted) return;

    final label = await _askLabel('נקודה ${_nodes.length + 1}');
    if (label == null || !mounted) return;
    // Already uploaded + stitched by the video screen — add it directly.
    await _addNode(
      url: result.imageUrl,
      label: label,
      haov: result.haov,
      vaov: result.vaov,
    );
  }

  // PRIMARY: in-app guided 360° camera sweep. The sweep screen captures frames,
  // builds the panorama on the server itself, and returns a finished stitched
  // panorama URL + angle of view — we add it as a node exactly like an import.
  Future<void> _captureWithSweep() async {
    final result = await Navigator.of(context).push<PanoramaSweepResult>(
      MaterialPageRoute(builder: (_) => const PanoramaSweepCaptureScreen()),
    );
    // null = the user backed out (or hit an error and chose "סגור"); the sweep
    // screen already showed its own clear message, so just return quietly.
    if (result == null || !mounted) return;

    final label = await _askLabel('נקודה ${_nodes.length + 1}');
    if (label == null || !mounted) return;
    // The panorama is already uploaded by the sweep screen — add it directly.
    await _addNode(
      url: result.imageUrl,
      label: label,
      haov: result.haov,
      vaov: result.vaov,
    );
  }

  // Import one or SEVERAL ready panoramas from the gallery. Picking MULTIPLE adds
  // each as its own tour point — they auto-link into a walkable tour (this is the
  // "upload several panoramas and connect them" flow). A single pick keeps the
  // careful path (manual FOV calibration + optional pole-fill).
  Future<void> _importFromGallery() async {
    final picks = await _picker.pickMultiImage(
      maxWidth: _maxPanoWidth,
      imageQuality: 90,
    );
    if (picks.isEmpty || !mounted) return;

    if (picks.length == 1) {
      await _importSinglePano(picks.first.path);
      return;
    }

    // BULK: each image becomes a point. Estimate the vertical FOV from the aspect
    // ratio (a 2:1 export = a full sphere) so the landlord isn't asked to
    // calibrate every one — they just pick and go; points auto-link in _buildTour.
    for (final pick in picks) {
      if (!mounted) return;
      final aspect = await _imageAspect(pick.path) ?? 2.0;
      final vaov = (360.0 / aspect).clamp(60.0, 180.0);
      await _uploadAndAdd(
        path: pick.path,
        contentType: 'image/jpeg',
        haov: 360,
        vaov: vaov,
        autoLabel: 'נקודה ${_nodes.length + 1}',
      );
    }
  }

  // SECONDARY fallback: import a single panorama the landlord already shot.
  Future<void> _importSinglePano(String pickedPath) async {
    final aspect = await _imageAspect(pickedPath) ?? 4.0;
    if (!mounted) return;
    // A ~2:1 image is ALREADY a full 360°×180° equirectangular sphere (exported
    // from Street View, an AI-360 tool, etc.). Add it as a full sphere as-is —
    // do NOT run the phone-strip FOV estimator, which would mislabel a real 360
    // as a narrow ~120°×60° pano (default vaov 60 × aspect 2).
    if (aspect >= 1.8 && aspect <= 2.25) {
      await _uploadAndAdd(
          path: pickedPath, contentType: 'image/jpeg', haov: 360, vaov: 180);
      return;
    }
    // Phone EXIF rarely states the true vertical FOV, so estimate it from the
    // strip's aspect ratio and let the landlord nudge it until the horizon sits
    // level (the calibration knob a fixed model can't infer).
    final fov = await _askPanoFov(aspect);
    if (fov == null || !mounted) return;

    // OPTIONAL honest-poles step: a horizontal phone pano has no real ceiling/
    // floor. Offer to add them — fully skippable for older landlords.
    final poles = await _offerPoleEnhance();
    if (!mounted) return;
    if (poles != null && poles.hasAny) {
      final ok = await _uploadCompositedPano(
          stripPath: pickedPath,
          poles: poles,
          vaov: fov.vaov,
          fallbackHaov: fov.haov);
      if (ok || !mounted) return; // composite added the node (or screen gone)
      // else fall through to the plain partial-FOV strip below.
    }

    await _uploadAndAdd(
        path: pickedPath,
        contentType: 'image/jpeg',
        haov: fov.haov,
        vaov: fov.vaov);
  }

  // AI 360: the landlord picks up to 6 room photos; the server runs gpt-image-2
  // to merge them into ONE seamless equirectangular 360. MORE photos (each wall)
  // = far less the model has to invent, so accuracy rises with coverage. Takes
  // ~1–3 min (async on the server); we show a progress dialog and poll. The node
  // is labelled with ✨ so it reads honestly as AI-generated.
  Future<void> _generateWithAi() async {
    final picks = await _picker.pickMultiImage(imageQuality: 92);
    if (picks.isEmpty || !mounted) return;
    final imgs = picks.take(6).toList(); // gpt-image-2 path takes up to 6 images
    if (mounted && picks.length < 3) {
      _toast('טיפ: בחרו 2–3 פנורמות של אותו החדר (או תמונות של כל קיר) — ה-AI מרכיב מהן 360° מדויק.');
    }
    final label = await _askLabel('נקודה ${_nodes.length + 1}');
    if (label == null || !mounted) return;

    final msg = ValueNotifier<String>('מכינים…');
    _showAiProgress(msg);
    var dialogOpen = true;
    void close() {
      if (dialogOpen && mounted) {
        dialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    try {
      final job = await AwsApiClient.instance.createAiPanoramaJob(
        propertyId: 'draft_${DateTime.now().millisecondsSinceEpoch}',
        imageCount: imgs.length,
      );
      if (job == null) {
        close();
        _toast('לא הצלחנו להתחיל. בדקו את החיבור לאינטרנט.');
        return;
      }
      msg.value = 'מעלים תמונות…';
      for (var i = 0; i < imgs.length; i++) {
        final ok = await AwsApiClient.instance
            .uploadToPresignedUrl(job.uploadUrls[i], imgs[i].path);
        if (!ok) {
          close();
          _toast('ההעלאה נכשלה. בדקו את החיבור ונסו שוב.');
          return;
        }
      }
      msg.value = 'ה-AI יוצר את ה-360° באיכות גבוהה… (1–3 דקות)';
      await AwsApiClient.instance.startAiPanoramaGenerate(job.jobId);

      // Poll up to ~5 min (gpt-image-2 quality:high takes ~2.5min + upload/queue).
      for (var i = 0; i < 150; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        final st = await AwsApiClient.instance.getPanorama(job.jobId);
        if (st == null) continue;
        if (st.status == 'ready' && st.imageUrl.isNotEmpty) {
          close();
          await _addNode(
              url: st.imageUrl, label: '$label ✨', haov: st.haov, vaov: st.vaov);
          return;
        }
        if (st.status == 'failed') {
          close();
          _toast('היצירה נכשלה. נסו תמונה אחרת, ברורה ורחבה.');
          return;
        }
      }
      close();
      _toast('העיבוד לוקח יותר מדי זמן. נסו שוב מאוחר יותר.');
    } catch (e) {
      close();
      _toast('משהו השתבש. בדקו את החיבור ונסו שוב.');
    }
  }

  void _showAiProgress(ValueNotifier<String> msg) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('✨', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              const Text('יוצרים 360° עם AI',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 19)),
              const SizedBox(height: 16),
              CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              ValueListenableBuilder<String>(
                valueListenable: msg,
                builder: (_, m, __) => Text(m,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 15, height: 1.4)),
              ),
              const SizedBox(height: 6),
              const Text('אל תסגרו את המסך',
                  style: TextStyle(color: AppColors.textDisabled, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  // Ask whether to add real floor+ceiling, then run the guided pole capture.
  // Returns null if the landlord declined (keeps the cheap partial-FOV poles).
  Future<PolePhotos?> _offerPoleEnhance() async {
    final wants = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('שפר רצפה ותקרה',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        content: const Text(
          'לפנורמה אופקית אין תקרה ורצפה אמיתיות. אפשר להוסיף אותן בשתי תמונות '
          'נוספות — צילום אחד כלפי מטה (רצפה) ואחד כלפי מעלה (תקרה). זה לא חובה.',
          style: TextStyle(color: Color(0xFF475569), height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('דלג')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('שפר'),
          ),
        ],
      ),
    );
    if (wants != true || !mounted) return null;
    return Navigator.of(context).push<PolePhotos>(
      MaterialPageRoute(builder: (_) => const PanoramaPoleCaptureScreen()),
    );
  }

  // Upload the strip + pole photos and ask the server to composite real caps into
  // a full equirectangular pano (server/pole_fill). On success, adds the node as a
  // full sphere (haov 360 / vaov 180). Returns false if compositing is unavailable
  // so the caller can fall back to the plain partial-FOV strip.
  Future<bool> _uploadCompositedPano({
    required String stripPath,
    required PolePhotos poles,
    required double vaov,
    required double fallbackHaov,
  }) async {
    final label = await _askLabel('נקודה ${_nodes.length + 1}');
    if (label == null || !mounted) return false;

    setState(() => _busy = true);
    try {
      final stripUrl = await AwsApiClient.instance.uploadFile(stripPath,
          folder: 'panoramas', contentType: 'image/jpeg');
      if (stripUrl == null || stripUrl.isEmpty) {
        if (mounted) {
          setState(() => _busy = false);
          _toast('ההעלאה נכשלה — בדוק את החיבור ונסה שוב.');
        }
        return true; // upload failed entirely; don't double-add a plain strip.
      }
      final floorUrl = poles.floorPath == null
          ? null
          : await AwsApiClient.instance.uploadFile(poles.floorPath!,
              folder: 'panoramas/poles', contentType: 'image/jpeg');
      final ceilingUrl = poles.ceilingPath == null
          ? null
          : await AwsApiClient.instance.uploadFile(poles.ceilingPath!,
              folder: 'panoramas/poles', contentType: 'image/jpeg');

      // Ask the server to composite. Endpoint may not be deployed yet — any
      // failure falls back to the partial-FOV strip we already uploaded.
      try {
        final res = await AwsApiClient.instance.post('/panorama/pole-fill', {
          'stripUrl': stripUrl,
          if (floorUrl != null) 'floorUrl': floorUrl,
          if (ceilingUrl != null) 'ceilingUrl': ceilingUrl,
          'vaov': vaov,
        });
        final data = res['data'] as Map<String, dynamic>?;
        final composedUrl = (data?['imageUrl'] ?? res['imageUrl']) as String?;
        if (composedUrl != null && composedUrl.isNotEmpty) {
          if (!mounted) return true;
          setState(() => _busy = false);
          await _addNode(
              url: composedUrl, label: label, haov: 360, vaov: 180);
          return true;
        }
      } catch (_) {
        // server unavailable → use the strip we already uploaded as a partial pano
      }

      if (!mounted) return true;
      setState(() => _busy = false);
      // Server compositing unavailable: still add the strip (already uploaded) as a
      // partial-FOV pano with honest empty poles — no work is lost.
      await _addNode(
          url: stripUrl, label: label, haov: fallbackHaov, vaov: vaov);
      return true;
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      return false;
    }
  }

  // For a cylindrical strip, horizontal FOV ≈ vertical FOV × (width/height); we
  // clamp horizontal at a full 360° turn. The slider tunes the vertical FOV.
  Future<({double haov, double vaov})?> _askPanoFov(double aspect) {
    double vaov = 60; // typical phone-pano vertical FOV
    double haovFor(double v) => (v * aspect).clamp(30.0, 360.0);
    return showDialog<({double haov, double vaov})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final haov = haovFor(vaov);
          return AlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('כיוון הפנורמה',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'הסיבוב מכסה כ-${haov.round()}° לרוחב · ${vaov.round()}° לגובה. '
                  'אם האופק נראה מתוח, כוונן את שדה הראייה האנכי.',
                  style: const TextStyle(color: Color(0xFF475569), height: 1.4),
                ),
                const SizedBox(height: 8),
                Slider(
                  value: vaov,
                  min: 40,
                  max: 90,
                  divisions: 50,
                  label: '${vaov.round()}°',
                  activeColor: AppColors.primary,
                  onChanged: (v) => setLocal(() => vaov = v),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('ביטול')),
              FilledButton(
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: () =>
                    Navigator.pop(ctx, (haov: haovFor(vaov), vaov: vaov)),
                child: const Text('הוסף'),
              ),
            ],
          );
        },
      ),
    );
  }

  // onReorderItem already adjusts newIndex for the removed item.
  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      final item = _nodes.removeAt(oldIndex);
      _nodes.insert(newIndex, item);
    });
  }

  Future<void> _renameNode(int i) async {
    if (i < 0 || i >= _nodes.length) return;
    final current = _nodes[i].label.isNotEmpty ? _nodes[i].label : 'נקודה ${i + 1}';
    final name = await _askLabel(current);
    if (name == null || name.isEmpty || !mounted) return;
    setState(() => _nodes[i] = _nodes[i].copyWith(label: name));
  }

  // Complete a captured/imported panorama into a FULL 360: the server fills the
  // missing ceiling & floor and closes the 360 wrap (cube-face inpaint, strict
  // "continue the surface, invent nothing"), then we swap in the enhanced image.
  // Manual ✨ trigger from a node tile: complete this pano to a full 360. Shows
  // a modal (the landlord asked for it), but the job is ALSO persisted so it
  // survives leaving the screen — same resilient path as the auto pass.
  Future<void> _enhanceNode(int i) async {
    if (i < 0 || i >= _nodes.length) return;
    final node = _nodes[i];
    if (node.isLocal) {
      _toast('צריך חיבור לאינטרנט — הפנורמה עדיין לא הועלתה.');
      return;
    }
    await _startEnhance(node.id, showModal: true);
  }

  // Unified enhance entry (auto, manual, resume all funnel here). Persists the
  // job to [PendingPanoStore] the instant it's submitted, so closing/reopening
  // the capture screen resumes it instead of orphaning it. [showModal] drives
  // the blocking "מתחילים…" dialog for the manual path; the auto path is silent.
  Future<void> _startEnhance(String nodeId, {bool showModal = false}) async {
    if (_enhancing.contains(nodeId)) return;
    final node = _nodeById(nodeId);
    if (node == null || node.isLocal) return;

    ValueNotifier<String>? msg;
    var modalOpen = false;
    void closeModal() {
      if (modalOpen && mounted) {
        modalOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (showModal) {
      msg = ValueNotifier<String>('מתחילים…');
      _showAiProgress(msg);
      modalOpen = true;
    }
    setState(() => _enhancing.add(nodeId));
    try {
      final jobId = await AwsApiClient.instance.createEnhancePanoramaJob(
        propertyId: 'draft_${DateTime.now().millisecondsSinceEpoch}',
        srcUrl: node.imageUrl,
      );
      if (jobId == null) {
        if (showModal) _toast('לא הצלחנו להתחיל. בדקו את החיבור לאינטרנט.');
        return;
      }
      // Persist BEFORE starting so a crash between start and the first poll is
      // still recoverable on the next capture-screen open.
      await PendingPanoStore.instance
          .add(PendingPano(jobId: jobId, nodeId: nodeId, submittedAt: DateTime.now()));
      msg?.value = 'ה-AI משלים תקרה, רצפה וסוגר 360°… (1–2 דקות)';
      await AwsApiClient.instance.startEnhancePanorama(jobId);
      await _pollEnhanceJob(jobId, nodeId, showedModal: showModal);
    } catch (_) {
      if (showModal) _toast('שגיאה בהשלמה. נסו שוב.');
    } finally {
      closeModal();
      if (mounted) setState(() => _enhancing.remove(nodeId));
    }
  }

  // Polls one enhance job to a terminal state and, on success, adds the
  // completed 360 as a 'משופר ✨' version of [nodeId] (non-destructive — the
  // original stays as 'מקור'). Leaving the screen ends the loop WITHOUT dropping
  // the persisted record, so a later resume can finish the job.
  Future<void> _pollEnhanceJob(String jobId, String nodeId,
      {bool showedModal = false}) async {
    for (var t = 0; t < 150; t++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return; // record kept → resumed on re-entry
      final s = await AwsApiClient.instance.getPanorama(jobId);
      if (s == null) continue;
      if (s.status == 'ready' && s.imageUrl.isNotEmpty) {
        await PendingPanoStore.instance.remove(jobId);
        final i = _nodes.indexWhere((n) => n.id == nodeId);
        if (i < 0) return; // node deleted while enhancing
        setState(() => _nodes[i] = _nodes[i].addVersion(
              PanoVersion(
                  imageUrl: s.imageUrl, haov: 360, vaov: 180, source: 'משופר ✨'),
            ));
        final name = _nodes[i].label.isNotEmpty ? _nodes[i].label : 'הנקודה';
        _toast('נוספה גרסה משופרת ל־$name ✨ — אפשר להשוות ולבחור');
        return;
      }
      if (s.status == 'failed') {
        await PendingPanoStore.instance.remove(jobId);
        if (showedModal) _toast('ההשלמה נכשלה. נסו שוב.');
        return;
      }
    }
    // Timed out this session — keep the record (within _maxAge) so a later
    // resume can still pick up a slow job.
  }

  // On capture-screen entry, resume any persisted enhance jobs whose node is in
  // this tour (e.g. the user left mid-enhance and came back). Jobs for nodes not
  // present are left alone — they age out of the store.
  Future<void> _resumePendingEnhances() async {
    final pending = await PendingPanoStore.instance.all();
    if (!mounted) return;
    for (final p in pending) {
      if (_enhancing.contains(p.nodeId)) continue;
      if (_nodes.indexWhere((n) => n.id == p.nodeId) < 0) continue;
      setState(() => _enhancing.add(p.nodeId));
      unawaited(() async {
        try {
          await _pollEnhanceJob(p.jobId, p.nodeId);
        } finally {
          if (mounted) setState(() => _enhancing.remove(p.nodeId));
        }
      }());
    }
  }

  // Quick look at a single point (no links) so the landlord can verify the 360.
  void _previewNode(PanoramaNode node) {
    PanoramaPsvTourView.open(
      context,
      PropertyPanoramaTour(nodes: [node.copyWith(hotspots: const [])]),
      title: node.label.isNotEmpty ? node.label : 'תצוגה מקדימה',
    );
  }

  // Place the new point on the floor map (mini-map), then add it.
  Future<void> _addNode({
    required String url,
    required String label,
    required double haov,
    required double vaov,
  }) async {
    final pos = await _placeOnMap(label);
    final placed = pos ?? _autoPosition();
    final id = 'pano_${DateTime.now().microsecondsSinceEpoch}';
    setState(() {
      _nodes.add(PanoramaNode(
        id: id,
        imageUrl: url,
        label: label,
        x: placed.dx,
        y: placed.dy,
        haov: haov,
        vaov: vaov,
      ));
    });
    // AUTO: a partial pano (not a full sphere) is auto-completed to a full 360
    // in the background — the enhanced result lands as a 'משופר ✨' version the
    // landlord can compare against 'מקור'. Full spheres (sweep/AI) skip this.
    final isFull = haov >= 359 && vaov >= 179;
    final isNetwork = !(url.startsWith('/') || url.startsWith('file://'));
    if (!isFull && isNetwork) unawaited(_startEnhance(id));
  }

  PanoramaNode? _nodeById(String id) {
    final i = _nodes.indexWhere((n) => n.id == id);
    return i < 0 ? null : _nodes[i];
  }

  // Spread auto-placed points along a diagonal so an un-mapped tour still has a
  // usable mini-map.
  Offset _autoPosition() {
    final i = _nodes.length;
    final t = (i + 1) / 8.0;
    return Offset((0.2 + 0.6 * (t % 1.0)).clamp(0.05, 0.95),
        (0.2 + 0.12 * i).clamp(0.05, 0.95));
  }

  Future<Offset?> _placeOnMap(String label) async {
    return Navigator.of(context).push<Offset>(
      MaterialPageRoute(
        builder: (_) => PanoramaMapPlacementScreen(
          label: label,
          existing: List.unmodifiable(_nodes),
          floorPlanPath: _floorPlanPath,
          onFloorPlanPicked: (p) => _floorPlanPath = p,
        ),
      ),
    );
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 3200),
      content: Text(msg),
    ));
  }

  // Width/height ratio of an image file (null if it can't be decoded).
  Future<double?> _imageAspect(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final w = frame.image.width, h = frame.image.height;
      frame.image.dispose();
      return h > 0 ? w / h : null;
    } catch (_) {
      return null;
    }
  }



  // Landlord curates which renders tenants can flip to in the 360 viewer.
  // Long-press a version chip to hide/show it; the last visible one can't hide.
  void _toggleVersionHidden(int i, int v) {
    if (i < 0 || i >= _nodes.length) return;
    final updated = _nodes[i].toggleVersionHidden(v);
    if (identical(updated, _nodes[i])) {
      _toast('חייבת להישאר לפחות גרסה אחת גלויה לדיירים');
      return;
    }
    setState(() => _nodes[i] = updated);
    _toast(updated.allVersions[v].hidden
        ? 'הגרסה תוסתר מהדיירים 👁️'
        : 'הגרסה תוצג לדיירים 👁️');
  }

  Future<String?> _askLabel(String fallback) async {
    final ctrl = TextEditingController(text: fallback);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('שם הנקודה',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(hintText: 'לדוגמה: סלון, מטבח'),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: [
                for (final s in ['סלון', 'מטבח', 'חדר שינה', 'מרפסת', 'חדר רחצה'])
                  ActionChip(
                    label: Text(s),
                    onPressed: () => Navigator.pop(ctx, s),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ביטול')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('הוסף'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('צילום סיור 360°'),
        backgroundColor: AppColors.background,
        actions: [
          if (_nodes.length >= 2)
            TextButton(
              onPressed: () =>
                  PanoramaPsvTourView.open(context, _buildTour(),
                      title: 'תצוגה מקדימה'),
              child: const Text('תצוגה מקדימה'),
            ),
        ],
      ),
      body: Column(
        children: [
          _Instructions(),
          Expanded(
            child: _nodes.isEmpty
                ? const Center(
                    child: Text('עוד לא הוספת נקודות',
                        style: TextStyle(color: AppColors.textSecondary)),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    itemCount: _nodes.length,
                    onReorderItem: _reorder,
                    itemBuilder: (_, i) => _NodeTile(
                      key: ValueKey(_nodes[i].id),
                      index: i,
                      node: _nodes[i],
                      onDelete: () => setState(() => _nodes.removeAt(i)),
                      onRename: () => _renameNode(i),
                      onPreview: () => _previewNode(_nodes[i]),
                      onEnhance: () => _enhanceNode(i),
                      onSelectVersion: (v) => setState(
                          () => _nodes[i] = _nodes[i].selectVersion(v)),
                      onToggleVersionHidden: (v) => _toggleVersionHidden(i, v),
                      enhancing: _enhancing.contains(_nodes[i].id),
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              // ONE obvious next step: capture/add a panorama. Tapping it opens
              // the guided explainer first, then the picker.
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: _busy ? null : _capturePano,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(IconsaxPlusBold.camera, size: 22),
                  label: const Text('הוסף פנורמה',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 17)),
                ),
              ),
            ),
          ),
          if (_nodes.isNotEmpty)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.navy,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: () => Navigator.of(context).pop(_buildTour()),
                    child: Text('שמור סיור (${_nodes.length} נקודות)',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Instructions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryLight2,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(IconsaxPlusBold.info_circle, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: const TextSpan(
                style: TextStyle(
                    color: AppColors.navy, fontSize: 15, height: 1.5),
                children: [
                  TextSpan(
                      text: 'בכל חדר מוסיפים נקודה אחת — והן מתחברות לסיור אחד.\n',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  TextSpan(
                      text:
                          'הקישו «הוסף פנורמה» למטה. פנורמה חלקית? הקישו ✨ ליד הנקודה '
                          'וה-AI ישלים אותה ל-360° מלא (תקרה, רצפה וסגירה).'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    super.key,
    required this.index,
    required this.node,
    required this.onDelete,
    required this.onRename,
    required this.onPreview,
    required this.onEnhance,
    required this.onSelectVersion,
    required this.onToggleVersionHidden,
    this.enhancing = false,
  });
  final int index;
  final PanoramaNode node;
  final VoidCallback onDelete;
  final VoidCallback onRename;
  final VoidCallback onPreview;
  final VoidCallback onEnhance;
  final ValueChanged<int> onSelectVersion;
  final ValueChanged<int> onToggleVersionHidden;

  /// True while a background auto-enhance is running for this node.
  final bool enhancing;

  // A full sphere = 360×180. Anything narrower is a partial pano that can be
  // completed (poles + wrap) into a full 360.
  bool get _isFull => node.haov >= 359 && node.vaov >= 179;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2ECF1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _tile(context),
          // Version picker — appears once the node has more than one 360 render
          // (e.g. מקור + משופר). Lets the landlord compare and pick, so enhance
          // is reversible.
          if (node.hasMultipleVersions) _versionBar(),
        ],
      ),
    );
  }

  Widget _versionBar() {
    final versions = node.allVersions;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        children: [
          Icon(IconsaxPlusLinear.layer, size: 15, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var v = 0; v < versions.length; v++)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: _VersionChip(
                        label: versions[v].source.isNotEmpty
                            ? versions[v].source
                            : 'גרסה ${v + 1}',
                        selected: v == node.activeVersion,
                        hidden: versions[v].hidden,
                        onTap: () => onSelectVersion(v),
                        onLongPress: () => onToggleVersionHidden(v),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Hint: what long-press does (curate what tenants see).
          const Text('החזק להסתרה מדיירים',
              style: TextStyle(
                  color: AppColors.textDisabled,
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context) {
    return ListTile(
        // Tap the thumbnail → quick 360 preview (a small "play" badge hints it).
        leading: GestureDetector(
          onTap: onPreview,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: node.isLocal
                      ? Image.file(File(node.imageUrl), fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _thumbFallback())
                      : Image.network(node.imageUrl, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _thumbFallback()),
                ),
              ),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Icon(IconsaxPlusBold.play,
                    color: Colors.white, size: 13),
              ),
            ],
          ),
        ),
        title: Text(node.label.isNotEmpty ? node.label : 'נקודה ${index + 1}',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Row(children: [
          Icon(
              enhancing
                  ? IconsaxPlusBold.magic_star
                  : (_isFull
                      ? IconsaxPlusBold.tick_circle
                      : IconsaxPlusBold.magic_star),
              size: 13,
              color: _isFull && !enhancing
                  ? AppColors.success
                  : AppColors.primary),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
                enhancing
                    ? 'משלים ל-360° מלא…'
                    : (_isFull ? '360° מלא · גרור לסידור' : 'חלקי · אפשר להשלים ל-360°'),
                style: TextStyle(
                    color: _isFull && !enhancing
                        ? AppColors.textSecondary
                        : AppColors.primaryDark,
                    fontSize: 12,
                    fontWeight:
                        _isFull && !enhancing ? FontWeight.w500 : FontWeight.w700)),
          ),
        ]),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // While auto-completing, show a spinner in place of the ✨ action.
            if (enhancing)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                ),
              )
            // Complete a partial pano to a full 360 (poles + wrap) — manual
            // trigger / retry if the auto pass didn't run or failed.
            else if (!_isFull)
              IconButton(
                icon: const Text('✨', style: TextStyle(fontSize: 17)),
                onPressed: onEnhance,
                tooltip: 'השלם ל-360° מלא',
                visualDensity: VisualDensity.compact,
              ),
            IconButton(
              icon: Icon(IconsaxPlusLinear.edit_2,
                  color: AppColors.primary, size: 20),
              onPressed: onRename,
              tooltip: 'שנה שם',
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(IconsaxPlusLinear.trash,
                  color: AppColors.coral, size: 20),
              onPressed: onDelete,
              tooltip: 'מחק',
              visualDensity: VisualDensity.compact,
            ),
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(right: 2, left: 4),
                child: Icon(IconsaxPlusLinear.menu_1,
                    color: AppColors.textSecondary, size: 20),
              ),
            ),
          ],
        ),
      );
  }

  Widget _thumbFallback() => Container(
        color: AppColors.primaryLight2,
        child: Icon(IconsaxPlusLinear.gallery, color: AppColors.primary),
      );
}

/// A pill in the node's version picker (מקור / משופר ✨ …).
class _VersionChip extends StatelessWidget {
  const _VersionChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    this.hidden = false,
  });

  final String label;
  final bool selected;

  /// Landlord-hidden from the tenant viewer (dimmed, eye-off icon).
  final bool hidden;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: hidden ? 0.55 : 1,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.primaryLight2,
            borderRadius: BorderRadius.circular(999),
            border: hidden
                ? Border.all(color: AppColors.textDisabled, width: 1)
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hidden) ...[
                Icon(IconsaxPlusLinear.eye_slash,
                    size: 12,
                    color: selected ? Colors.white : AppColors.primaryDark),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.primaryDark,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Which capture path the landlord chose on the guide screen.
/// [photo] = guided 10-photo 360° capture (PRIMARY default), [sweep] = the
/// frame-by-frame guided sweep (advanced), [arranged] = compose from native
/// panos, [gallery] = import a native pano.
enum _CaptureChoice { photo, sweep, arranged, gallery, ai }

/// Full-screen, big-text guide shown BEFORE capture. In-app-capture-first for an
/// older, non-technical user: the in-app guided sweep now lands one full 360°
/// ring from a single slow spin (yaw/gyro/blur/crop fixed + pose-assisted
/// stitching), so it's the warm default — the app does the work, the landlord
/// just turns once.
/// PRIMARY button ("צלם עכשיו — בתוך האפליקציה") pops [_CaptureChoice.sweep] →
/// the in-app sweep. A clear SECONDARY button ("כבר צילמתי פנורמה — ייבא תמונה")
/// pops [_CaptureChoice.gallery] → import a panorama already shot in the phone's
/// native camera. Large clear text, one obvious primary action; no false promises.
class _PanoramaGuideScreen extends StatelessWidget {
  const _PanoramaGuideScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: const Text('איך מצלמים סיור 360°'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Friendly hero illustration.
                    Container(
                      height: 130,
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight2,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Icon(IconsaxPlusBold.rotate_right,
                          size: 64, color: AppColors.primary),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'מצלמים פנורמה 360° ומעלים אותה כאן',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 23,
                          color: AppColors.navy),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'הדרך הכי איכותית: אפליקציית Google Street View (חינם) — '
                      'צילום כדור 360° מלא. אחר כך פשוט מעלים את התמונה לכאן.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 16,
                          height: 1.4,
                          color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 22),
                    const _GuideStep(
                      number: '1',
                      icon: IconsaxPlusBold.mobile,
                      title: 'התקינו Google Street View',
                      body:
                          'מה-App Store או Google Play — בחינם. (אפשר גם מצב "פנורמה" '
                          'במצלמת הטלפון, אבל Street View נותן 360° מלא ואיכותי יותר.)',
                    ),
                    const _GuideStep(
                      number: '2',
                      icon: IconsaxPlusBold.camera,
                      title: 'צלמו את החדר ב-360°',
                      body:
                          'בתוך Street View: "צור" ← מצלמה. עומדים במרכז החדר ומכוונים '
                          'את הטלפון אל הנקודות עד שהכדור מתמלא.',
                    ),
                    const _GuideStep(
                      number: '3',
                      icon: IconsaxPlusBold.gallery,
                      title: 'שומרים לגלריה',
                      body:
                          'שומרים/מייצאים את הפנורמה אל התמונות בטלפון.',
                    ),
                    const _GuideStep(
                      number: '4',
                      icon: IconsaxPlusBold.tick_circle,
                      title: 'מעלים כאן',
                      body:
                          'לוחצים על הכפתור למטה ובוחרים את הפנורמה מהגלריה. זהו — הסיור מוכן.',
                      isLast: true,
                    ),
                  ],
                ),
              ),
            ),
            // PRIMARY: upload one or SEVERAL ready panoramas — several become a
            // connected walkable tour (the "upload several and link them" flow).
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 4),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 17),
                  ),
                  onPressed: () =>
                      Navigator.of(context).pop(_CaptureChoice.gallery),
                  icon: const Icon(IconsaxPlusBold.gallery, size: 22),
                  label: const Text('העלה פנורמות מהגלריה',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('אפשר לבחור כמה פנורמות — הן יתחברו לסיור אחד',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ),
            // SECONDARY paths — capture in-app, or stitch several partial phone
            // panoramas into one full 360°.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary, width: 1.3),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: () =>
                        Navigator.of(context).pop(_CaptureChoice.sweep),
                    icon: const Icon(IconsaxPlusBold.camera, size: 19),
                    label: const Text('צלם באפליקציה',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14.5)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(color: AppColors.primary, width: 1.3),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                    onPressed: () =>
                        Navigator.of(context).pop(_CaptureChoice.arranged),
                    icon: const Icon(IconsaxPlusBold.mirror, size: 19),
                    label: const Text('חבר לתמונה אחת',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14.5)),
                  ),
                ),
              ]),
            ),
            // AI path: turn 1–2 ordinary room photos into a 360 with gpt-image-2.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary, width: 1.4),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () => Navigator.of(context).pop(_CaptureChoice.ai),
                  icon: const Text('✨', style: TextStyle(fontSize: 18)),
                  label: const Text('צור 360° מפנורמות/תמונות (AI)',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
    this.isLast = false,
  });

  final String number;
  final IconData icon;
  final String title;
  final String body;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Big numbered badge.
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Text(number,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                              color: AppColors.navy)),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(body,
                    style: const TextStyle(
                        fontSize: 15,
                        height: 1.35,
                        color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
