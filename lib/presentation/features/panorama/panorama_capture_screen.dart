import 'dart:io';
import 'dart:ui' as ui;

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/data/models/panorama_tour.dart';
import 'package:dating_app/presentation/features/panorama/panorama_web_tour.dart';
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
      final label = await _askLabel('נקודה ${_nodes.length + 1}');
      if (label == null || !mounted) return;

      setState(() => _busy = true);
      // Upload is MANDATORY: a tour must live at a network URL so tenants on
      // other devices can view it. A local path would only work on this phone.
      String? url;
      try {
        url = await AwsApiClient.instance.uploadFile(
          picked.path,
          folder: 'panoramas',
          contentType: 'image/jpeg',
        );
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

      final id = 'pano_${DateTime.now().microsecondsSinceEpoch}';
      setState(() {
        _nodes.add(PanoramaNode(id: id, imageUrl: url!, label: label));
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
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
                  PanoramaWebTourView.open(context, _buildTour(),
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
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    itemCount: _nodes.length,
                    itemBuilder: (_, i) => _NodeTile(
                      key: ValueKey(_nodes[i].id),
                      index: i,
                      node: _nodes[i],
                      onDelete: () => setState(() => _nodes.removeAt(i)),
                    ),
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _busy ? null : () => _addPoint(ImageSource.gallery),
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(IconsaxPlusLinear.gallery),
                  label: const Text('ייבא תמונת 360°',
                      style: TextStyle(fontWeight: FontWeight.w800)),
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
              text: TextSpan(
                style: const TextStyle(
                    color: AppColors.navy, fontSize: 13, height: 1.45),
                children: [
                  const TextSpan(
                      text: 'איך יוצרים סיור 360°:\n',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const TextSpan(
                      text:
                          '1. בכל חדר צלם תמונת 360° כדורית (equirectangular) — עם מצלמת 360° (Insta360 / Ricoh Theta) או אפליקציית «כדור תמונה» חינמית.\n2. הקש «ייבא תמונת 360°» ובחר אותה מהגלריה, ותן לה שם (סלון, מטבח…).\n3. חזור בכל חדר — נקשר ביניהן אוטומטית לסיור הליכה.\n'),
                  TextSpan(
                      text:
                          'התמונה צריכה להיות כדורית ביחס 2:1. פנורמה אופקית רגילה לא מספיקה.',
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
  });
  final int index;
  final PanoramaNode node;
  final VoidCallback onDelete;

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
        leading: ClipRRect(
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
        title: Text(node.label.isNotEmpty ? node.label : 'נקודה ${index + 1}',
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('נקודה ${index + 1}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        trailing: IconButton(
          icon: const Icon(IconsaxPlusLinear.trash, color: AppColors.coral),
          onPressed: onDelete,
        ),
      ),
    );
  }

  Widget _thumbFallback() => Container(
        color: AppColors.primaryLight2,
        child: Icon(IconsaxPlusLinear.gallery, color: AppColors.primary),
      );
}
