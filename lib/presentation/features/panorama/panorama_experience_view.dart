import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/panorama_tour.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:panorama_viewer/panorama_viewer.dart';

/// A Street-View-style 360° walkthrough: look around (drag/gyro), tap a floor
/// arrow, and the world dollies forward + crossfades into the next point — so it
/// feels like walking, not cutting. See STREETVIEW_ARCHITECTURE.md.
class PanoramaExperienceView extends StatefulWidget {
  const PanoramaExperienceView({
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
        builder: (_) => PanoramaExperienceView(tour: tour, title: title),
      ),
    );
  }

  @override
  State<PanoramaExperienceView> createState() => _PanoramaExperienceViewState();
}

class _PanoramaExperienceViewState extends State<PanoramaExperienceView>
    with SingleTickerProviderStateMixin {
  final _panoKey = GlobalKey();
  final _heading = ValueNotifier<double>(0); // current yaw (longitude)
  late final AnimationController _transition;

  late String _nodeId;
  double _initialLongitude = 0; // heading the live pano is built facing
  bool _gyro = false;
  ui.Image? _overlay; // snapshot of the previous pano during a transition
  bool _navigating = false;
  bool _showHint = true; // the drag/gyro hint auto-hides so it doesn't clutter
  Timer? _hintTimer;

  void _flashHint() {
    _hintTimer?.cancel();
    if (!_showHint) setState(() => _showHint = true);
    _hintTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showHint = false);
    });
  }

  @override
  void initState() {
    super.initState();
    _nodeId = widget.tour.first?.id ?? '';
    _flashHint();
    _transition = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
      value: 1.0, // 1 = settled (no transition in progress)
    )..addStatusListener((s) {
        if (s == AnimationStatus.completed && _overlay != null) {
          setState(() {
            _overlay?.dispose();
            _overlay = null;
            _navigating = false;
          });
        }
      });
    WidgetsBinding.instance.addPostFrameCallback((_) => _preloadNeighbours());
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _transition.dispose();
    _overlay?.dispose();
    _heading.dispose();
    super.dispose();
  }

  PanoramaNode? get _node => widget.tour.nodeById(_nodeId);

  ImageProvider _imageOf(PanoramaNode n) {
    if (n.isLocal) {
      final path = n.imageUrl.startsWith('file://')
          ? n.imageUrl.substring(7)
          : n.imageUrl;
      return FileImage(File(path));
    }
    return NetworkImage(n.imageUrl);
  }

  static double _norm(double deg) {
    var d = deg % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  // Arrive facing forward: away from the link that points back to where we came.
  double _arrivalHeading(PanoramaNode target) {
    for (final h in target.hotspots) {
      if (h.targetNodeId == _nodeId) return _norm(h.longitude + 180);
    }
    return _heading.value; // keep current heading if geometry is unknown
  }

  Future<void> _goTo(String targetId) async {
    if (_navigating || targetId == _nodeId) return;
    final target = widget.tour.nodeById(targetId);
    if (target == null) return;
    _navigating = true;
    _flashHint(); // re-surface the "how to look around" hint in the new room

    // 1. snapshot the current pano for the dolly overlay (best-effort).
    ui.Image? snap;
    try {
      final boundary =
          _panoKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary != null) snap = await boundary.toImage(pixelRatio: 1.4);
    } catch (_) {
      snap = null;
    }
    if (!mounted) {
      snap?.dispose();
      return;
    }

    // 2. swap to the destination, already facing the travel direction, and run
    //    the forward dolly + crossfade.
    setState(() {
      _overlay = snap;
      _nodeId = targetId;
      _initialLongitude = _arrivalHeading(target);
      _heading.value = _initialLongitude;
    });
    _transition.forward(from: 0.0);
    if (snap == null) _navigating = false; // plain fade; nothing to clean up
    _preloadNeighbours();
  }

  void _preloadNeighbours() {
    final node = _node;
    if (node == null) return;
    for (final h in node.hotspots) {
      final n = widget.tour.nodeById(h.targetNodeId);
      if (n != null) {
        precacheImage(_imageOf(n), context).catchError((_) {});
      }
    }
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
                    style: TextStyle(color: Colors.white70)))
          else
            RepaintBoundary(
              key: _panoKey,
              child: AnimatedBuilder(
                animation: _transition,
                builder: (context, child) {
                  final t = _transition.value;
                  // destination pano emerges: slight zoom-out + fade-in
                  return Opacity(
                    opacity: t.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: ui.lerpDouble(1.08, 1.0, t)!,
                      child: child,
                    ),
                  );
                },
                child: PanoramaViewer(
                  key: ValueKey(node.id),
                  longitude: _initialLongitude,
                  animSpeed: _gyro ? 0.0 : 0.25,
                  sensorControl:
                      _gyro ? SensorControl.orientation : SensorControl.none,
                  onViewChanged: (lon, lat, tilt) => _heading.value = lon,
                  hotspots: [
                    for (final h in node.hotspots)
                      Hotspot(
                        latitude: -22, // projected toward the floor
                        longitude: h.longitude,
                        width: 100,
                        height: 100,
                        widget: _GroundArrow(
                          label: h.label.isNotEmpty
                              ? h.label
                              : (widget.tour.nodeById(h.targetNodeId)?.label ??
                                  'המשך'),
                          onTap: () => _goTo(h.targetNodeId),
                        ),
                      ),
                  ],
                  child: Image(image: _imageOf(node), fit: BoxFit.cover),
                ),
              ),
            ),

          // forward-dolly overlay: the previous pano rushes forward and dissolves
          if (_overlay != null)
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _transition,
                  builder: (context, _) {
                    final t = _transition.value;
                    return Opacity(
                      opacity: (1.0 - t).clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: ui.lerpDouble(1.0, 1.7, t)!,
                        child: RawImage(
                          image: _overlay,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

          // top bar: back · title/room · compass · gyro
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
                    _Compass(heading: _heading),
                    const SizedBox(width: 8),
                    _CircleButton(
                      icon: _gyro
                          ? IconsaxPlusBold.gps
                          : IconsaxPlusLinear.gps,
                      active: _gyro,
                      onTap: () => setState(() => _gyro = !_gyro),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // drag hint — auto-hides after a few seconds so it doesn't block the view
          Positioned(
            bottom: 92,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showHint ? 1 : 0,
                duration: const Duration(milliseconds: 450),
                child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _gyro
                        ? 'הזז את הטלפון כדי להסתכל מסביב'
                        : 'גרור כדי להסתכל · הקש על החץ כדי להתקדם',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                ),
              ),
            ),
          ),

          // room selector
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
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
                              fontWeight:
                                  active ? FontWeight.w800 : FontWeight.w600,
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

// On-floor navigation arrow (Street-View style): a forward chevron + label.
class _GroundArrow extends StatelessWidget {
  _GroundArrow({required this.label, required this.onTap});
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
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(
                    color: Colors.black54, blurRadius: 10, offset: Offset(0, 4)),
              ],
            ),
            child: Icon(IconsaxPlusBold.arrow_up_3,
                color: AppColors.primary, size: 30),
          ),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// Compass dial that rotates with the current heading.
class _Compass extends StatelessWidget {
  const _Compass({required this.heading});
  final ValueNotifier<double> heading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: ValueListenableBuilder<double>(
        valueListenable: heading,
        builder: (_, h, __) => Transform.rotate(
          angle: -h * math.pi / 180.0,
          child: const Icon(IconsaxPlusBold.gps, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  _CircleButton(
      {required this.icon, required this.onTap, this.active = false});
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
          color:
              active ? AppColors.primary : Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
