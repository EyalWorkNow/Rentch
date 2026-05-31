import 'dart:io';

import 'package:dating_app/core/security/input_sanitizer.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/presentation/widgets/safe_image.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:video_player/video_player.dart';

enum SafeVideoDisplayMode {
  iconOnly,
  playback,
}

class SafeMedia extends StatelessWidget {
  const SafeMedia({
    super.key,
    required this.media,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.videoMode = SafeVideoDisplayMode.iconOnly,
  });

  final PropertyMedia? media;
  final Widget fallback;
  final BoxFit fit;
  final Alignment alignment;
  final SafeVideoDisplayMode videoMode;

  @override
  Widget build(BuildContext context) {
    final item = media;
    if (item == null || item.url.trim().isEmpty) return fallback;
    if (item.isImage) {
      return SafeImage(
        source: item.url,
        fallback: fallback,
        fit: fit,
        alignment: alignment,
      );
    }
    if (videoMode == SafeVideoDisplayMode.playback) {
      return _VideoMediaPlayer(
        media: item,
        fallback: fallback,
        fit: fit,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        fallback,
        Container(color: Colors.black.withValues(alpha: 0.28)),
        const Center(
          child: _VideoOverlayBadge(compact: false),
        ),
      ],
    );
  }
}

class _VideoMediaPlayer extends StatefulWidget {
  const _VideoMediaPlayer({
    required this.media,
    required this.fallback,
    required this.fit,
  });

  final PropertyMedia media;
  final Widget fallback;
  final BoxFit fit;

  @override
  State<_VideoMediaPlayer> createState() => _VideoMediaPlayerState();
}

class _VideoMediaPlayerState extends State<_VideoMediaPlayer> {
  VideoPlayerController? _controller;
  Future<void>? _initializeFuture;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  @override
  void didUpdateWidget(covariant _VideoMediaPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.url != widget.media.url) {
      _disposeController();
      _initializeVideo();
    }
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _initializeVideo() {
    final source = widget.media.url.trim();
    if (source.isEmpty) return;

    final isLocal = source.startsWith('/') || source.startsWith('file://');
    if (isLocal) {
      final path = source.startsWith('file://') ? source.substring(7) : source;
      if (!InputSanitizer.isValidLocalMediaPathSync(path) ||
          !InputSanitizer.isVideoExtensionAllowed(path)) {
        return;
      }
      _controller = VideoPlayerController.file(File(path));
    } else {
      final sanitized = InputSanitizer.sanitizeMediaUrl(source);
      if (sanitized == null) return;
      _controller = VideoPlayerController.networkUrl(Uri.parse(sanitized));
    }

    _initializeFuture = _controller!.initialize().then((_) async {
      await _controller!.setLooping(true);
      if (mounted) {
        setState(() {});
      }
    }).catchError((_) {
      _disposeController();
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _disposeController() {
    _controller?.dispose();
    _controller = null;
    _initializeFuture = null;
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final initializeFuture = _initializeFuture;
    if (controller == null || initializeFuture == null) {
      return widget.fallback;
    }

    return FutureBuilder<void>(
      future: initializeFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !controller.value.isInitialized) {
          return Stack(
            fit: StackFit.expand,
            children: [
              widget.fallback,
              const Center(child: _VideoOverlayBadge(compact: false)),
            ],
          );
        }

        return GestureDetector(
          onTap: _togglePlayback,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.black),
              Center(
                child: FittedBox(
                  fit: widget.fit,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: controller.value.size.width,
                    height: controller.value.size.height,
                    child: VideoPlayer(controller),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: const _VideoOverlayBadge(compact: true),
              ),
              if (!controller.value.isPlaying)
                Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.42),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      IconsaxPlusBold.play,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _VideoOverlayBadge extends StatelessWidget {
  const _VideoOverlayBadge({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 5 : 8,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            IconsaxPlusBold.video,
            color: Colors.white,
            size: compact ? 12 : 15,
          ),
          SizedBox(width: compact ? 4 : 6),
          Text(
            'וידאו',
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
