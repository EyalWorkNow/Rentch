import 'dart:io';
import 'dart:ui' as ui;

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/data/models/panorama_tour.dart';
import 'package:dating_app/presentation/features/panorama/panorama_map_placement.dart';
import 'package:dating_app/presentation/features/panorama/panorama_pole_capture.dart';
import 'package:dating_app/presentation/features/panorama/panorama_psv_tour.dart';
import 'package:dating_app/presentation/features/panorama/panorama_wide_capture.dart';
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

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _nodes.addAll(widget.initial!.nodes);
  }

  // Sequentially link points: each gets a forward arrow to the next and a back
  // arrow to the previous. (Hotspots are placed ahead/behind by default.)
  PropertyPanoramaTour _buildTour() {
    final linked = <PanoramaNode>[];
    for (var i = 0; i < _nodes.length; i++) {
      final hotspots = <PanoramaHotspot>[];
      if (i + 1 < _nodes.length) {
        hotspots.add(PanoramaHotspot(
            targetNodeId: _nodes[i + 1].id,
            longitude: 0,
            label: _nodes[i + 1].label));
      }
      if (i - 1 >= 0) {
        hotspots.add(PanoramaHotspot(
            targetNodeId: _nodes[i - 1].id,
            longitude: 180,
            label: 'חזרה'));
      }
      linked.add(_nodes[i].copyWith(hotspots: hotspots));
    }
    return PropertyPanoramaTour(nodes: linked);
  }

  // Cap imported panoramas at this width: WebGL MAX_TEXTURE_SIZE is 4096 on many
  // mobile GPUs and Pannellum refuses larger images. image_picker downscales
  // natively at pick time (cheap + low memory), so the result always renders.
  static const double _maxPanoWidth = 4096;

  // Import a ready equirectangular panorama from the gallery.
  Future<void> _addPoint(ImageSource source) async {
    if (_busy) return;
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: _maxPanoWidth,
        imageQuality: 90,
      );
      if (picked == null || !mounted) return;

      // A true Photo Sphere is equirectangular (~2:1).
      final aspect = await _imageAspect(picked.path);
      if (!mounted) return;
      if (aspect != null && (aspect < 1.85 || aspect > 2.2)) {
        final proceed = await _warnNotSpherical(aspect);
        if (proceed != true || !mounted) return;
      }
      await _uploadAndAdd(path: picked.path, contentType: 'image/jpeg');
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  // In-app wide (ultra-wide) capture → shown as a partial panorama. haov/vaov
  // are device-FOV estimates (calibration knobs) so Pannellum renders the single
  // shot without stretching it to a full sphere.
  Future<void> _captureWide() async {
    if (_busy) return;
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const PanoramaWideCaptureScreen()),
    );
    if (path == null || !mounted) return;
    await _uploadAndAdd(
        path: path, contentType: 'image/jpeg', haov: 100, vaov: 70);
  }

  // Shared: name → mandatory upload → place on the map → add the node.
  Future<void> _uploadAndAdd({
    required String path,
    required String contentType,
    double haov = 360,
    double vaov = 180,
  }) async {
    final label = await _askLabel('נקודה ${_nodes.length + 1}');
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
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: _maxPanoWidth,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;

    final aspect = await _imageAspect(picked.path) ?? 4.0;
    if (!mounted) return;
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
          stripPath: picked.path,
          poles: poles,
          vaov: fov.vaov,
          fallbackHaov: fov.haov);
      if (ok || !mounted) return; // composite added the node (or screen gone)
      // else fall through to the plain partial-FOV strip below.
    }

    await _uploadAndAdd(
        path: picked.path,
        contentType: 'image/jpeg',
        haov: fov.haov,
        vaov: fov.vaov);
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

  Future<bool?> _warnNotSpherical(double aspect) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('זו לא תמונה כדורית',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
        content: Text(
          'התמונה ביחס ${aspect.toStringAsFixed(1)}:1, אבל סיור 360° תקין צריך '
          'תמונה כדורית ביחס 2:1 (מצב «כדור תמונה» / Photo Sphere). אם תוסיף '
          'אותה, ייתכן שהסיור ייראה מעוות.',
          style: const TextStyle(color: Color(0xFF475569), height: 1.4),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ביטול')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('הוסף בכל זאת'),
          ),
        ],
      ),
    );
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
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                children: [
                  // Primary: capture a real horizontal 360° on the phone.
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _busy ? null : _capturePano,
                      icon: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(IconsaxPlusBold.camera),
                      label: const Text('הוסף פנורמה',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            side: BorderSide(color: AppColors.primary),
                          ),
                          onPressed: _busy ? null : _captureWide,
                          icon: const Icon(IconsaxPlusLinear.camera, size: 18),
                          label: const Text('צלם רחב',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            side: BorderSide(color: AppColors.primary),
                          ),
                          onPressed:
                              _busy ? null : () => _addPoint(ImageSource.gallery),
                          icon: const Icon(IconsaxPlusLinear.gallery, size: 18),
                          label: const Text('ייבא 360°',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ],
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
              text: TextSpan(
                style: const TextStyle(
                    color: AppColors.navy, fontSize: 13, height: 1.45),
                children: [
                  const TextSpan(
                      text: 'איך יוצרים סיור 360°:\n',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const TextSpan(
                      text:
                          '1. בכל חדר פתח את אפליקציית המצלמה במצב «פנורמה», עמוד במרכז וסובב לאט סיבוב אחד (כמה שניות).\n2. חזור לכאן, הקש «הוסף פנורמה» ובחר את התמונה — היא תוצג כסיור 360°.\n3. תן שם לנקודה (סלון, מטבח…), סמן על המפה, וחזור בכל חדר — הנקודות נקשרות אוטומטית.\n'),
                  TextSpan(
                      text:
                          'אפשר גם «ייבא 360°» (תמונה כדורית מלאה מ-Street View / Insta360), או «צלם רחב» לתצוגה חלקית מהירה.',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: AppColors.primary)),
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
  });
  final int index;
  final PanoramaNode node;
  final VoidCallback onDelete;
  final VoidCallback onRename;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2ECF1)),
      ),
      child: ListTile(
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
        subtitle: Text('נקודה ${index + 1} · גרור לסידור',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(IconsaxPlusLinear.edit_2,
                  color: AppColors.primary, size: 20),
              onPressed: onRename,
              tooltip: 'שנה שם',
            ),
            IconButton(
              icon: const Icon(IconsaxPlusLinear.trash,
                  color: AppColors.coral, size: 20),
              onPressed: onDelete,
              tooltip: 'מחק',
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
      ),
    );
  }

  Widget _thumbFallback() => Container(
        color: AppColors.primaryLight2,
        child: Icon(IconsaxPlusLinear.gallery, color: AppColors.primary),
      );
}
