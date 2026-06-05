import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/presentation/widgets/safe_media.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/rentch_icon.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({
    super.key,
    required this.media,
    required this.initialIndex,
    this.title = '',
  });

  final List<PropertyMedia> media;
  final int initialIndex;
  final String title;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen>
    with SingleTickerProviderStateMixin {
  late final PageController _pageCtrl;
  late int _current;
  late final AnimationController _entryCtrl;
  late final Animation<double> _fade;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _current = _safeMediaIndex(widget.initialIndex);
    _pageCtrl = PageController(initialPage: _current);
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entryCtrl.forward();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  int _safeMediaIndex(int index) {
    if (widget.media.isEmpty) return 0;
    return index.clamp(0, widget.media.length - 1).toInt();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _entryCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _close() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final safeCurrent = _safeMediaIndex(_current);

    return FadeTransition(
      opacity: _fade,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const RentchIcon(IconsaxPlusLinear.arrow_right,
                  color: Colors.white, size: 18),
            ),
            onPressed: _close,
          ),
          title: Column(
            children: [
              if (widget.title.isNotEmpty)
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              Text(
                widget.media.isEmpty
                    ? '0 / 0'
                    : '${safeCurrent + 1} / ${widget.media.length}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        body: GestureDetector(
          onVerticalDragUpdate: (d) {
            setState(() => _dragOffset += d.delta.dy);
          },
          onVerticalDragEnd: (d) {
            if (_dragOffset.abs() > 100 ||
                d.velocity.pixelsPerSecond.dy.abs() > 600) {
              _close();
            } else {
              setState(() => _dragOffset = 0);
            }
          },
          child: Transform.translate(
            offset: Offset(0, _dragOffset),
            child: Opacity(
              opacity: (1 - _dragOffset.abs() / 400).clamp(0.3, 1.0),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Main gallery
                  widget.media.isEmpty
                      ? const Center(
                          child: RentchIcon(
                            IconsaxPlusLinear.gallery,
                            color: Colors.white38,
                            size: 64,
                          ),
                        )
                      : PageView.builder(
                          controller: _pageCtrl,
                          onPageChanged: (i) => setState(() => _current = i),
                          itemCount: widget.media.length,
                          itemBuilder: (_, i) =>
                              _GalleryPage(media: widget.media[i]),
                        ),

                  // Dot indicator bottom
                  if (widget.media.length > 1)
                    Positioned(
                      bottom: 40 + MediaQuery.of(context).padding.bottom,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(widget.media.length, (i) {
                          final active = i == safeCurrent;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: active ? 20 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: active
                                  ? AppColors.primary
                                  : Colors.white.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          );
                        }),
                      ),
                    ),

                  // Swipe-to-close hint
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 80,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: _dragOffset == 0 ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RentchIcon(IconsaxPlusLinear.arrow_up,
                                color: Colors.white54, size: 18),
                            SizedBox(height: 3),
                            Text(
                              'גרור למעלה לסגירה',
                              style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GalleryPage extends StatelessWidget {
  const _GalleryPage({required this.media});
  final PropertyMedia media;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.8,
      maxScale: 4.0,
      child: Center(
        child: media.url.isEmpty
            ? Container(
                color: AppColors.navy,
                child: const Center(
                  child: RentchIcon(IconsaxPlusLinear.gallery,
                      color: Colors.white30, size: 64),
                ),
              )
            : SafeMedia(
                media: media,
                fit: BoxFit.contain,
                videoMode: SafeVideoDisplayMode.playback,
                fallback: Container(
                  color: AppColors.navy,
                  child: const Center(
                    child: RentchIcon(
                      IconsaxPlusLinear.gallery,
                      color: Colors.white30,
                      size: 64,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
