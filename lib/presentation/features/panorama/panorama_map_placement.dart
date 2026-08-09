import 'dart:io';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/panorama_tour.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:image_picker/image_picker.dart';

/// Lets the landlord mark where a point was captured. Background is a blank grid
/// by default, or a real floor-plan image the user uploads (kept across points).
/// The user taps the canvas; returns the normalized (0..1) position via pop, or
/// null if skipped.
class PanoramaMapPlacementScreen extends StatefulWidget {
  const PanoramaMapPlacementScreen({
    super.key,
    required this.label,
    this.existing = const [],
    this.floorPlanPath,
    this.onFloorPlanPicked,
  });

  final String label;
  final List<PanoramaNode> existing;

  /// A floor-plan image to show behind the dots (local path), if the user added
  /// one earlier. [onFloorPlanPicked] reports a newly-picked plan back so the
  /// caller can reuse it for the next point.
  final String? floorPlanPath;
  final ValueChanged<String>? onFloorPlanPicked;

  @override
  State<PanoramaMapPlacementScreen> createState() =>
      _PanoramaMapPlacementScreenState();
}

class _PanoramaMapPlacementScreenState
    extends State<PanoramaMapPlacementScreen> {
  Offset? _placed; // normalized 0..1
  String? _floor; // floor-plan image path
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _floor = widget.floorPlanPath;
  }

  Future<void> _pickFloorPlan() async {
    final picked = await _picker.pickImage(
        source: ImageSource.gallery, maxWidth: 2000, imageQuality: 90);
    if (picked == null || !mounted) return;
    setState(() => _floor = picked.path);
    widget.onFloorPlanPicked?.call(picked.path);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final placedNodes =
        widget.existing.where((n) => n.hasPosition).toList();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text(l10n.panoramaMapPlacement89efe952),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              l10n.panoramaMapPlacement9b8a163d(widget.label),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.navy,
                  fontSize: 15,
                  fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              l10n.panoramaMapPlacementE8290949,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12.5),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _pickFloorPlan,
                icon: const Icon(IconsaxPlusLinear.gallery_add, size: 18),
                label: Text(_floor == null
                    ? l10n.panoramaMapPlacement167194cf
                    : l10n.panoramaMapPlacement17cdf785),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth, h = c.maxHeight;
                  return GestureDetector(
                    onTapDown: (d) {
                      setState(() => _placed = Offset(
                            (d.localPosition.dx / w).clamp(0.0, 1.0),
                            (d.localPosition.dy / h).clamp(0.0, 1.0),
                          ));
                    },
                    child: Container(
                      width: w,
                      height: h,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Stack(
                          children: [
                            // background: uploaded floor plan, else a soft grid
                            Positioned.fill(
                              child: _floor != null
                                  ? Image.file(File(_floor!),
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) =>
                                          CustomPaint(painter: _FloorPainter()))
                                  : CustomPaint(painter: _FloorPainter()),
                            ),
                            Stack(
                              children: [
                              // existing points
                              for (final n in placedNodes)
                                _Dot(
                                  x: n.x! * w,
                                  y: n.y! * h,
                                  label: n.label,
                                  active: false,
                                ),
                              // the new point
                              if (_placed != null)
                                _Dot(
                                  x: _placed!.dx * w,
                                  y: _placed!.dy * h,
                                  label: widget.label,
                                  active: true,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.panoramaMapPlacement80a413c5),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _placed == null
                          ? null
                          : () => Navigator.of(context).pop(_placed),
                      icon: const Icon(IconsaxPlusLinear.tick_circle),
                      label: Text(l10n.panoramaMapPlacement1bc95f85,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  _Dot(
      {required this.x,
      required this.y,
      required this.label,
      required this.active});
  final double x, y;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: x - 13,
      top: y - 13,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: active ? AppColors.primary : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                  color: active ? Colors.white : AppColors.primary, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: Icon(IconsaxPlusBold.location,
                size: 14, color: active ? Colors.white : AppColors.primary),
          ),
          if (label.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}

// Soft grid background so the canvas reads as a floor plan.
class _FloorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = AppColors.slate100
      ..strokeWidth = 1;
    const step = 28.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
