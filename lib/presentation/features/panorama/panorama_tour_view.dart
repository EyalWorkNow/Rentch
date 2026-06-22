import 'dart:io';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/panorama_tour.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:panorama_viewer/panorama_viewer.dart';

/// Full-screen interactive 360° walkthrough: drag or use the gyroscope to look
/// around each capture point, tap an arrow to walk to the next point.
class PanoramaTourView extends StatefulWidget {
  const PanoramaTourView({
    super.key,
    required this.tour,
    this.title = 'סיור 360°',
  });

  final PropertyPanoramaTour tour;
  final String title;

  static Future<void> open(
    BuildContext context,
    PropertyPanoramaTour tour, {
    String title = 'סיור 360°',
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PanoramaTourView(tour: tour, title: title),
      ),
    );
  }

  @override
  State<PanoramaTourView> createState() => _PanoramaTourViewState();
}

class _PanoramaTourViewState extends State<PanoramaTourView> {
  late String _nodeId;
  bool _gyro = false;

  @override
  void initState() {
    super.initState();
    _nodeId = widget.tour.first?.id ?? '';
  }

  PanoramaNode? get _node => widget.tour.nodeById(_nodeId);

  void _goTo(String id) {
    if (widget.tour.nodeById(id) == null) return;
    setState(() => _nodeId = id);
  }

  ImageProvider _imageOf(PanoramaNode node) {
    if (node.isLocal) {
      final path =
          node.imageUrl.startsWith('file://') ? node.imageUrl.substring(7) : node.imageUrl;
      return FileImage(File(path));
    }
    return NetworkImage(node.imageUrl);
  }

  @override
  Widget build(BuildContext context) {
    final node = _node;
    final nodes = widget.tour.nodes;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (node == null)
            const Center(
              child: Text('אין סיור זמין',
                  style: TextStyle(color: Colors.white70)),
            )
          else
            PanoramaViewer(
              // re-create on node change so the new panorama loads
              key: ValueKey(node.id),
              sensorControl:
                  _gyro ? SensorControl.orientation : SensorControl.none,
              animSpeed: _gyro ? 0.0 : 0.3, // gentle auto-pan when not using gyro
              hotspots: [
                for (final h in node.hotspots)
                  Hotspot(
                    latitude: h.latitude,
                    longitude: h.longitude,
                    width: 96,
                    height: 96,
                    widget: _HotspotArrow(
                      label: h.label.isNotEmpty
                          ? h.label
                          : (widget.tour.nodeById(h.targetNodeId)?.label ?? 'המשך'),
                      onTap: () => _goTo(h.targetNodeId),
                    ),
                  ),
              ],
              child: Image(image: _imageOf(node), fit: BoxFit.cover),
            ),

          // top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  children: [
                    _CircleButton(
                      icon: IconsaxPlusLinear.arrow_right_3,
                      onTap: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        node?.label.isNotEmpty == true
                            ? '${widget.title} · ${node!.label}'
                            : widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                        ),
                      ),
                    ),
                    _CircleButton(
                      icon: _gyro
                          ? IconsaxPlusBold.rotate_left
                          : IconsaxPlusLinear.rotate_left,
                      active: _gyro,
                      onTap: () => setState(() => _gyro = !_gyro),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // drag hint
          Positioned(
            bottom: 96,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _gyro ? 'הזז את הטלפון כדי להסתכל מסביב' : 'גרור כדי להסתכל ב-360°',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),

          // bottom point selector
          if (nodes.length > 1)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: SizedBox(
                  height: 56,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: nodes.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final n = nodes[i];
                      final active = n.id == _nodeId;
                      return GestureDetector(
                        onTap: () => _goTo(n.id),
                        child: Container(
                          alignment: Alignment.center,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: active
                                ? AppColors.primary
                                : Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.25)),
                          ),
                          child: Text(
                            n.label.isNotEmpty ? n.label : 'נקודה ${i + 1}',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HotspotArrow extends StatelessWidget {
  const _HotspotArrow({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.9),
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(color: Colors.black45, blurRadius: 8, offset: Offset(0, 3)),
              ],
            ),
            child: const Icon(IconsaxPlusBold.arrow_up_3,
                color: Colors.white, size: 26),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary
              : Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
