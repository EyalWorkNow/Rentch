import 'dart:io';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/presentation/features/panorama/panorama_sweep_capture.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:image_picker/image_picker.dart';

/// Compose a FULL 360° panorama from several native phone panoramas.
///
/// One native pano (especially iPhone Panorama mode at 0.5× ultra-wide) only
/// covers ~149° horizontally — not a full turn. Here the landlord imports 2+
/// native panos and ARRANGES them on a 360° track: dragging each band sets WHERE
/// it sits in the rotation, dragging its EDGES fine-tunes exactly where one pano
/// ends and the next begins (with overlap). A 3-way selector marks each pano's
/// vertical band (אופקי / תקרה / רצפה). On "סיים", every pano + its arranged
/// position is uploaded and the SERVER stitches them into one equirectangular
/// panorama; we pop a finished [PanoramaSweepResult] so it flows into `_addNode`
/// exactly like the sweep/video/import paths.
class PanoramaAlignScreen extends StatefulWidget {
  const PanoramaAlignScreen({super.key});

  @override
  State<PanoramaAlignScreen> createState() => _PanoramaAlignScreenState();
}

/// Vertical band a pano covers. 'horizontal' is the default eye-level row;
/// 'top' is the ceiling cap, 'bottom' is the floor cap.
enum _PanoRow { horizontal, top, bottom }

extension _PanoRowWire on _PanoRow {
  String get wire => switch (this) {
        _PanoRow.horizontal => 'horizontal',
        _PanoRow.top => 'top',
        _PanoRow.bottom => 'bottom',
      };
  String get label => switch (this) {
        _PanoRow.horizontal => 'אופקי',
        _PanoRow.top => 'תקרה',
        _PanoRow.bottom => 'רצפה',
      };
}

/// One imported pano placed on the track.
class _PanoBand {
  _PanoBand({required this.path, required this.startDeg, required this.widthDeg});

  final String path;

  /// Where the pano begins on the rotation, 0..360 (wraps).
  double startDeg;

  /// Angular width of the pano, clamped to a sane min/full turn.
  double widthDeg;

  _PanoRow row = _PanoRow.horizontal;

  /// Fraction of the SOURCE image trimmed off each side (0..0.9), so overlapping
  /// or bad edges are removed and adjacent panos meet cleanly. Applied server-side
  /// before placement.
  double cropLeft = 0.0;
  double cropRight = 0.0;

  double get endDeg => startDeg + widthDeg; // may exceed 360 (wraps visually)
}

class _PanoramaAlignScreenState extends State<PanoramaAlignScreen> {
  final _picker = ImagePicker();
  final List<_PanoBand> _bands = [];

  bool _busy = false;
  bool _stitching = false;
  String _stitchMsg = '';
  String? _stitchError;

  // iPhone native Panorama at 0.5× ultra-wide covers ~149° horizontally — the
  // sensible default width for a freshly imported pano.
  static const double _kPanoFovDeg = 149;
  static const double _kMinWidthDeg = 30;
  // Higher-res stitch inputs → a higher-res stitched 360 (pano-stitch runs at
  // 3 GB / 300 s, so 8192 inputs are fine). PSV downscales the output per-device.
  static const double _kMaxPanoWidth = 8192;

  // ── Import ─────────────────────────────────────────────────────────────────

  Future<void> _addPano() async {
    if (_busy) return;
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: _kMaxPanoWidth,
      imageQuality: 90,
    );
    if (picked == null || !mounted) return;
    setState(() {
      // Drop each new band next to the previous one so they tile the turn and
      // the user just nudges from there. First pano starts at 0°.
      final start = _bands.isEmpty
          ? 0.0
          : (_bands.last.startDeg + _bands.last.widthDeg) % 360;
      _bands.add(_PanoBand(
          path: picked.path, startDeg: start, widthDeg: _kPanoFovDeg));
    });
  }

  void _removeBand(int i) {
    if (i < 0 || i >= _bands.length) return;
    setState(() => _bands.removeAt(i));
  }

  void _setRow(int i, _PanoRow row) {
    setState(() => _bands[i].row = row);
  }

  // Open the crop editor for a pano — trim its left/right edges so overlapping or
  // bad edges are removed and it meets the neighbouring pano cleanly.
  Future<void> _openCrop(int i) async {
    if (i < 0 || i >= _bands.length) return;
    final b = _bands[i];
    final res = await showModalBottomSheet<(double, double)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _CropEditor(path: b.path, cropLeft: b.cropLeft, cropRight: b.cropRight),
    );
    if (res != null && mounted) {
      setState(() {
        _bands[i].cropLeft = res.$1;
        _bands[i].cropRight = res.$2;
      });
    }
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final b = _bands.removeAt(oldIndex);
      _bands.insert(newIndex, b);
    });
  }

  // Drag a whole band left/right → moves where it sits in the rotation.
  void _moveBand(int i, double deltaDeg) {
    setState(() {
      var s = (_bands[i].startDeg + deltaDeg) % 360;
      if (s < 0) s += 360;
      _bands[i].startDeg = s;
    });
  }

  // Drag the LEADING edge → moves start, keeps end fixed (changes width).
  void _dragStartEdge(int i, double deltaDeg) {
    setState(() {
      final b = _bands[i];
      final newWidth = (b.widthDeg - deltaDeg).clamp(_kMinWidthDeg, 360.0);
      final consumed = b.widthDeg - newWidth; // actual change applied
      b.startDeg = (b.startDeg + consumed) % 360;
      if (b.startDeg < 0) b.startDeg += 360;
      b.widthDeg = newWidth;
    });
  }

  // Drag the TRAILING edge → keeps start fixed, changes width.
  void _dragEndEdge(int i, double deltaDeg) {
    setState(() {
      _bands[i].widthDeg =
          (_bands[i].widthDeg + deltaDeg).clamp(_kMinWidthDeg, 360.0);
    });
  }

  // ── Finish: upload + arrange + stitch ───────────────────────────────────────

  Future<void> _finish() async {
    if (_bands.length < 2) {
      _toast('הוסיפו לפחות שתי פנורמות כדי להרכיב סיבוב מלא.');
      return;
    }
    setState(() {
      _busy = true;
      _stitching = true;
      _stitchError = null;
      _stitchMsg = 'מתחילים להרכיב את ה-360°...';
    });

    final panos = _bands
        .map((b) => <String, dynamic>{
              'startDeg': double.parse(b.startDeg.toStringAsFixed(1)),
              'widthDeg': double.parse(b.widthDeg.toStringAsFixed(1)),
              'row': b.row.wire,
              if (b.cropLeft > 0.001)
                'cropLeft': double.parse(b.cropLeft.toStringAsFixed(3)),
              if (b.cropRight > 0.001)
                'cropRight': double.parse(b.cropRight.toStringAsFixed(3)),
            })
        .toList();

    try {
      // No property exists yet while the draft is being filled; group under a
      // one-off id the server uses only as a folder key.
      final groupId = 'draft_${DateTime.now().millisecondsSinceEpoch}';
      final job = await AwsApiClient.instance
          .createArrangedPanoramaJob(propertyId: groupId, panos: panos);
      if (job == null || job.uploadUrls.length < _bands.length) {
        _failStitch('לא הצלחנו להתחיל את ההרכבה. בדקו את החיבור לאינטרנט.');
        return;
      }

      // Upload each pano to its presigned URL, in the SAME order as panos.
      for (var i = 0; i < _bands.length; i++) {
        if (!mounted) return;
        setState(() => _stitchMsg = 'מעלים פנורמות... ${i + 1}/${_bands.length}');
        final ok = await AwsApiClient.instance
            .uploadToPresignedUrl(job.uploadUrls[i], _bands[i].path);
        if (!ok) {
          _failStitch('ההעלאה נכשלה באמצע. בדקו את החיבור ונסו שוב.');
          return;
        }
      }

      if (!mounted) return;
      setState(() => _stitchMsg = 'מחברים את הפנורמות לסיבוב מלא...');
      await AwsApiClient.instance.startPanoramaStitch(job.jobId);

      const maxPolls = 60; // ~2 min at 2 s
      for (var i = 0; i < maxPolls; i++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        final status = await AwsApiClient.instance.getPanorama(job.jobId);
        if (status == null) continue;
        if (status.status == 'ready' && status.imageUrl.isNotEmpty) {
          if (!mounted) return;
          Navigator.of(context).pop(PanoramaSweepResult(
            imageUrl: status.imageUrl,
            haov: status.haov,
            vaov: status.vaov,
          ));
          return;
        }
        if (status.status == 'failed') {
          _failStitch('ההרכבה נכשלה. נסו לסדר מחדש שתתקבל חפיפה ברורה בין הפנורמות.');
          return;
        }
        setState(() => _stitchMsg = 'מחברים את הפנורמות לסיבוב מלא...');
      }
      _failStitch('ההרכבה לוקחת יותר מדי זמן. נסו שוב מאוחר יותר.');
    } catch (e) {
      _failStitch('משהו השתבש. בדקו את החיבור ונסו שוב.');
    }
  }

  void _failStitch(String msg) {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _stitchError = msg;
      _stitching = true;
    });
  }

  void _retryFromError() {
    setState(() {
      _stitching = false;
      _stitchError = null;
    });
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(milliseconds: 3200),
      content: Text(msg),
    ));
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            title: const Text('הרכבת 360° מכמה פנורמות'),
          ),
          body: Column(
            children: [
              const _Guidance(),
              Expanded(
                child: _bands.isEmpty
                    ? _EmptyState(onAdd: _busy ? null : _addPano)
                    : SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _PreviewStrip(bands: _bands),
                            const SizedBox(height: 14),
                            _SectionLabel(
                                'גררו כדי לסדר על הסיבוב (0° → 360°)'),
                            const SizedBox(height: 8),
                            _Track(
                              bands: _bands,
                              onMove: _moveBand,
                              onDragStart: _dragStartEdge,
                              onDragEnd: _dragEndEdge,
                            ),
                            const SizedBox(height: 16),
                            _SectionLabel('הפנורמות שלכם'),
                            const SizedBox(height: 8),
                            ReorderableListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              buildDefaultDragHandles: false,
                              itemCount: _bands.length,
                              onReorder: _reorder,
                              itemBuilder: (_, i) => _BandTile(
                                key: ValueKey(_bands[i].path),
                                index: i,
                                band: _bands[i],
                                onRow: (r) => _setRow(i, r),
                                onRemove: () => _removeBand(i),
                                onCrop: () => _openCrop(i),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              if (_bands.isNotEmpty)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: BorderSide(color: AppColors.primary, width: 1.4),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _busy ? null : _addPano,
                        icon: const Icon(IconsaxPlusLinear.gallery_add, size: 22),
                        label: const Text('הוסף פנורמה',
                            style: TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 17)),
                      ),
                    ),
                  ),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed:
                          (_busy || _bands.length < 2) ? null : _finish,
                      icon: const Icon(IconsaxPlusBold.tick_circle, size: 22),
                      label: const Text('סיים והרכב 360°',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 18)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_stitching)
          _StitchOverlay(
            message: _stitchMsg,
            error: _stitchError,
            onRetry: _retryFromError,
            onClose: () => Navigator.of(context).pop(),
          ),
      ],
    );
  }
}

// ── Guidance banner ───────────────────────────────────────────────────────────

class _Guidance extends StatelessWidget {
  const _Guidance();

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
          const Expanded(
            child: Text(
              'צלמו פנורמה אחת בטלפון, ואז עוד אחת מהצד השני. הוסיפו אותן כאן וגררו '
              'כדי שיתחברו לסיבוב מלא — אנחנו נחבר אותן ל-360° חלק.',
              style: TextStyle(
                  color: AppColors.navy, fontSize: 15, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.primaryLight2,
                shape: BoxShape.circle,
              ),
              child: Icon(IconsaxPlusBold.gallery_add,
                  size: 44, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            const Text('הוסיפו את הפנורמות שצילמתם',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: AppColors.navy)),
            const SizedBox(height: 6),
            const Text('כל פנורמה מכסה חלק מהסיבוב. הוסיפו שתיים או יותר.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15, color: AppColors.textSecondary, height: 1.4)),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: onAdd,
                icon: const Icon(IconsaxPlusBold.gallery_add, size: 22),
                label: const Text('הוסף פנורמה',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            fontWeight: FontWeight.w900, fontSize: 16, color: AppColors.navy));
  }
}

// ── Live preview strip ────────────────────────────────────────────────────────

/// Unrolled 0°→360° composite: each pano drawn at its arranged position and
/// width, overlaps visible. A simple side-by-side of the imported thumbnails on
/// the track — the SERVER does the quality stitch.
class _PreviewStrip extends StatelessWidget {
  const _PreviewStrip({required this.bands});
  final List<_PanoBand> bands;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('כך נראה ה-360° שלכם'),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, c) {
          final w = c.maxWidth;
          return Container(
            height: 92,
            decoration: BoxDecoration(
              color: AppColors.navy.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                for (final band in bands)
                  Positioned(
                    left: (band.startDeg / 360) * w,
                    width: (band.widthDeg / 360) * w,
                    top: 0,
                    bottom: 0,
                    child: Opacity(
                      opacity: 0.92,
                      child: Image.file(File(band.path),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              Container(color: AppColors.primaryLight2)),
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ── The 360° track ────────────────────────────────────────────────────────────

class _Track extends StatelessWidget {
  const _Track({
    required this.bands,
    required this.onMove,
    required this.onDragStart,
    required this.onDragEnd,
  });

  final List<_PanoBand> bands;
  final void Function(int i, double deltaDeg) onMove;
  final void Function(int i, double deltaDeg) onDragStart;
  final void Function(int i, double deltaDeg) onDragEnd;

  static const _bandColors = <Color>[
    AppColors.superLike,
    AppColors.amber,
    AppColors.emerald,
    AppColors.red,
    AppColors.violet,
    Color(0xFF14B8A6),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      double pxToDeg(double px) => (px / w) * 360;
      const trackH = 76.0;
      const edgeW = 26.0; // big touch targets for the edge handles

      return Container(
        height: trackH + 26,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Stack(
          children: [
            // Degree ticks + labels along the bottom.
            Positioned(
              left: 0,
              right: 0,
              bottom: 4,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final d in ['0°', '90°', '180°', '270°', '360°'])
                    Text(d,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            // Bands.
            for (var i = 0; i < bands.length; i++)
              ..._buildBand(i, bands[i], w, pxToDeg, trackH, edgeW),
          ],
        ),
      );
    });
  }

  List<Widget> _buildBand(int i, _PanoBand band, double w,
      double Function(double) pxToDeg, double trackH, double edgeW) {
    final color = _bandColors[i % _bandColors.length];
    final left = (band.startDeg / 360) * w;
    final bandW = (band.widthDeg / 360) * w;

    Widget core() => Positioned(
          left: left,
          top: 6,
          width: bandW,
          height: trackH,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => onMove(i, pxToDeg(d.delta.dx)),
            child: Container(
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white, width: 2),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(IconsaxPlusBold.arrow_3, color: Colors.white, size: 18),
                  Text('${band.startDeg.round()}°–${(band.startDeg + band.widthDeg).round() % 360}°',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12)),
                  Text(band.row.label,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11)),
                ],
              ),
            ),
          ),
        );

    Widget edge({required bool leading}) => Positioned(
          left: leading ? (left - edgeW / 2) : (left + bandW - edgeW / 2),
          top: 6,
          width: edgeW,
          height: trackH,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (d) => leading
                ? onDragStart(i, pxToDeg(d.delta.dx))
                : onDragEnd(i, pxToDeg(d.delta.dx)),
            child: Center(
              child: Container(
                width: 8,
                height: trackH - 16,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color, width: 2),
                ),
                child:
                    Icon(IconsaxPlusLinear.more, color: color, size: 12),
              ),
            ),
          ),
        );

    return [core(), edge(leading: true), edge(leading: false)];
  }
}

// ── Per-pano tile (row selector + reorder + remove) ──────────────────────────

class _BandTile extends StatelessWidget {
  const _BandTile({
    super.key,
    required this.index,
    required this.band,
    required this.onRow,
    required this.onRemove,
    required this.onCrop,
  });

  final int index;
  final _PanoBand band;
  final void Function(_PanoRow) onRow;
  final VoidCallback onRemove;
  final VoidCallback onCrop;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: Image.file(File(band.path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          color: AppColors.primaryLight2,
                          child: Icon(IconsaxPlusLinear.gallery,
                              color: AppColors.primary))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('פנורמה ${index + 1}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                        '${band.startDeg.round()}° → ${(band.startDeg + band.widthDeg).round() % 360}° · רוחב ${band.widthDeg.round()}°',
                        style: const TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                    if (band.cropLeft > 0.001 || band.cropRight > 0.001) ...[
                      const SizedBox(height: 2),
                      Text(
                          '✂ נחתך ${(band.cropLeft * 100).round()}% משמאל · ${(band.cropRight * 100).round()}% מימין',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: Icon(IconsaxPlusLinear.crop,
                    color: AppColors.primary, size: 22),
                onPressed: onCrop,
                tooltip: 'חתוך התאמה',
              ),
              IconButton(
                icon: const Icon(IconsaxPlusLinear.trash,
                    color: AppColors.coral, size: 22),
                onPressed: onRemove,
                tooltip: 'מחק',
              ),
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(right: 2, left: 4),
                  child: Icon(IconsaxPlusLinear.menu_1,
                      color: AppColors.textSecondary, size: 22),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 3-way vertical-band selector. Big segmented buttons.
          Row(
            children: [
              for (final r in _PanoRow.values)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: _RowChip(
                      label: r.label,
                      selected: band.row == r,
                      onTap: () => onRow(r),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RowChip extends StatelessWidget {
  const _RowChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : AppColors.primaryLight2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: selected ? Colors.white : AppColors.navy)),
        ),
      ),
    );
  }
}

// ── Stitch / progress overlay ────────────────────────────────────────────────

class _StitchOverlay extends StatelessWidget {
  const _StitchOverlay({
    required this.message,
    required this.error,
    required this.onRetry,
    required this.onClose,
  });

  final String message;
  final String? error;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final isError = error != null;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.72),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isError)
                const SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 3),
                )
              else
                const Icon(IconsaxPlusBold.warning_2,
                    color: Colors.white, size: 48),
              const SizedBox(height: 18),
              Text(isError ? error! : message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      height: 1.4,
                      fontWeight: FontWeight.w700)),
              if (isError) ...[
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: onRetry,
                    child: const Text('חזרה לסידור',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onClose,
                  child: const Text('סגור',
                      style: TextStyle(color: Colors.white70)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Crop editor ────────────────────────────────────────────────────────────────
// Trim the left/right edges of a source pano so overlap or a bad edge is removed
// and it meets the neighbouring pano cleanly. Returns (cropLeft, cropRight).
class _CropEditor extends StatefulWidget {
  const _CropEditor(
      {required this.path, required this.cropLeft, required this.cropRight});
  final String path;
  final double cropLeft, cropRight;

  @override
  State<_CropEditor> createState() => _CropEditorState();
}

class _CropEditorState extends State<_CropEditor> {
  late double _l = widget.cropLeft.clamp(0.0, 0.8).toDouble(); // left crop frac
  late double _r =
      (1 - widget.cropRight).clamp(0.2, 1.0).toDouble(); // right edge (kept=[_l,_r])
  static const double _minKeep = 0.15;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 14),
          const Text('חתכו את הקצוות כדי שיתאים לפנורמה הסמוכה',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.navy)),
          const SizedBox(height: 4),
          const Text('גררו את הידיות פנימה כדי להסיר חפיפה או קצה לא טוב.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth;
            const h = 200.0;
            const hw = 30.0;
            return SizedBox(
              width: w,
              height: h,
              child: Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                      width: w,
                      height: h,
                      child: Image.file(File(widget.path), fit: BoxFit.cover)),
                ),
                Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: _l * w,
                    child: Container(color: Colors.black.withValues(alpha: 0.6))),
                Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: (1 - _r) * w,
                    child: Container(color: Colors.black.withValues(alpha: 0.6))),
                _handle(_l * w - hw / 2, hw, (dx) => setState(() {
                      _l = (_l + dx / w).clamp(0.0, _r - _minKeep).toDouble();
                    })),
                _handle(_r * w - hw / 2, hw, (dx) => setState(() {
                      _r = (_r + dx / w).clamp(_l + _minKeep, 1.0).toDouble();
                    })),
              ]),
            );
          }),
          const SizedBox(height: 16),
          Row(children: [
            TextButton.icon(
              onPressed: () => setState(() {
                _l = 0;
                _r = 1;
              }),
              icon: Icon(IconsaxPlusLinear.refresh_2,
                  size: 18, color: AppColors.textSecondary),
              label: const Text('איפוס',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            const Spacer(),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12)),
              onPressed: () => Navigator.of(context).pop((_l, 1 - _r)),
              child: const Text('החל חיתוך',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _handle(double left, double width, void Function(double dx) onDrag) =>
      Positioned(
        left: left,
        top: 0,
        bottom: 0,
        width: width,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
          child: Center(
            child: Container(
              width: 6,
              height: double.infinity,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(3),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 4)
                ],
              ),
            ),
          ),
        ),
      );
}
