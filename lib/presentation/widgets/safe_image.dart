import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dating_app/core/config/media_cdn.dart';
import 'package:dating_app/core/security/input_sanitizer.dart';
import 'package:flutter/material.dart';

class SafeImage extends StatefulWidget {
  const SafeImage({
    super.key,
    required this.source,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final String source;
  final Widget fallback;
  final BoxFit fit;
  final Alignment alignment;

  @override
  State<SafeImage> createState() => _SafeImageState();

  /// Warms the framework [ImageCache] for [source] at [width] px, using the
  /// EXACT same [ImageProvider] construction [_SafeImageState._build] uses
  /// (same CachedNetworkImageProvider vs NetworkImage branch, same request
  /// headers, same [ResizeImage] wrapping, same [MediaCdn.thumb] URL).
  ///
  /// Callers (e.g. ProfileCard's neighbor precache) used to build their own
  /// `NetworkImage(...)` + `ResizeImage(...)` here — a DIFFERENT provider
  /// class than the `CachedNetworkImageProvider` this widget actually
  /// resolves through. Flutter's ImageCache key includes the provider's own
  /// `obtainKey()`, and `NetworkImage`/`CachedNetworkImageProvider` never
  /// compare equal to each other (different runtimeType) even for the same
  /// URL — so that precache warmed a cache slot the real widget could never
  /// hit, AND `NetworkImage` doesn't write through cached_network_image's
  /// disk cache at all, so it didn't even pre-fetch the bytes the real
  /// widget would read from disk. Net effect: the "precache" was a no-op for
  /// the real load, which then paid the full network fetch + decode when the
  /// image actually became visible — the flicker/reload this was meant to
  /// prevent. Routing through this single shared helper keeps both call
  /// sites permanently in sync.
  static void precache(BuildContext context, String source, int width) {
    final cleaned = InputSanitizer.sanitizeImageUrl(source);
    if (cleaned == null || cleaned.isEmpty) return;
    if (cleaned.startsWith('/') || cleaned.startsWith('file://')) return;
    final remote = MediaCdn.thumb(cleaned, width);
    final ImageProvider netProvider =
        Platform.environment.containsKey('FLUTTER_TEST')
            ? NetworkImage(remote,
                headers: _SafeImageState._imageRequestHeaders(remote))
            : CachedNetworkImageProvider(remote,
                headers: _SafeImageState._imageRequestHeaders(remote));
    final ImageProvider provider =
        ResizeImage.resizeIfNeeded(width, null, netProvider);
    precacheImage(provider, context, onError: (_, __) {});
  }
}

class _SafeImageState extends State<SafeImage> {
  // Once we've ever painted a decoded frame for this element, we never fade
  // again. This is what kills the residual swipe-card flicker: when the photo
  // SWAPS (the [source] changes while gaplessPlayback holds the old frame),
  // [frameBuilder] briefly reports a null frame for the incoming image. With a
  // fresh AnimatedOpacity that would dip toward 0 and re-fade in — a faint
  // opacity blink. By latching here, swaps are truly instant (full opacity,
  // old frame held until the new one decodes), while the very first load of a
  // never-shown image still gets a gentle fade-in.
  bool _hasShownFrame = false;

  Widget _animatedFrameBuilder(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded || _hasShownFrame) {
      _hasShownFrame = true;
      return child;
    }
    if (frame != null && !_hasShownFrame) {
      _hasShownFrame = true;
    }
    return AnimatedOpacity(
      opacity: frame == null ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Decode to the DISPLAY size, not the source's full resolution. A 4000px CDN
    // photo in a ~400px card otherwise decodes a ~48 MB ARGB bitmap; iOS's large
    // image cache tolerates it, but Android's tight per-app heap evicts + re-
    // decodes (photos flash/reload while scrolling) or OOM-kills. cacheWidth cuts
    // that ~10-100× while preserving quality (it's the on-screen pixel width).
    return LayoutBuilder(
      builder: (context, constraints) => _build(context, _decodeWidth(context, constraints)),
    );
  }

  // On-screen pixel width to decode at: box width × devicePixelRatio, clamped so
  // an unbounded box (Infinity, e.g. inside a Row/Column) or a full-screen gallery
  // never over-decodes. Null → full-res (only if we truly can't size it).
  int? _decodeWidth(BuildContext context, BoxConstraints c) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final w = c.maxWidth.isFinite && c.maxWidth > 0
        ? c.maxWidth
        : (MediaQuery.maybeSizeOf(context)?.width ?? 1080);
    return (w * dpr).round().clamp(64, 2048);
  }

  Widget _build(BuildContext context, int? cacheW) {
    final source = widget.source;
    final fallback = widget.fallback;
    final fit = widget.fit;
    final alignment = widget.alignment;

    final cleaned = InputSanitizer.sanitizeImageUrl(source);
    if (cleaned == null || cleaned.isEmpty) return fallback;

    final isLocal = cleaned.startsWith('/') || cleaned.startsWith('file://');
    if (isLocal) {
      final path =
          cleaned.startsWith('file://') ? cleaned.substring(7) : cleaned;
      if (!InputSanitizer.isValidLocalPathSync(path)) return fallback;
      return Image.file(
        File(path),
        fit: fit,
        alignment: alignment,
        cacheWidth: cacheW,
        gaplessPlayback: true,
        frameBuilder: _animatedFrameBuilder,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    // Remote URLs: a DISK-backed cache (cached_network_image) so a thumbnail is
    // fetched from the external CDN once and then loads instantly on every later
    // open (the map, the deck, detail) — the previous Image.network kept only an
    // in-memory cache, so photos re-downloaded from slow CDNs each session.
    // [ResizeImage] preserves the decode-to-display-size win (cacheWidth). We
    // attach browser-like headers because several CDNs (Yad2, Unsplash) reject a
    // non-browser request, which would otherwise collapse every photo to its
    // placeholder.
    // Under `flutter test` there's no platform temp dir, so the disk cache's
    // path_provider call throws — use the plain in-memory NetworkImage there.
    // Serve our S3 media as a RIGHT-SIZED thumbnail from the thumbnail CDN — the
    // image is resized on-the-fly to the on-screen width (~10-20x smaller than
    // the full-res original) and edge-cached. External URLs / local files pass
    // through unchanged. cacheW is the decode/display width; 1600 covers a
    // full-screen phone view when the box is unsizable.
    final remote = MediaCdn.thumb(cleaned, cacheW ?? 1600);
    final ImageProvider netProvider =
        Platform.environment.containsKey('FLUTTER_TEST')
            ? NetworkImage(remote, headers: _imageRequestHeaders(remote))
            : CachedNetworkImageProvider(remote,
                headers: _imageRequestHeaders(remote));
    final ImageProvider provider =
        ResizeImage.resizeIfNeeded(cacheW, null, netProvider);
    return Image(
      image: provider,
      fit: fit,
      alignment: alignment,
      // Hold the previously-decoded frame until the new one is ready (no blank
      // flash when tapping between the card's photos). Pairs with the neighbor
      // precache in ProfileCard so the swap is instant.
      gaplessPlayback: true,
      frameBuilder: _animatedFrameBuilder,
      errorBuilder: (_, __, ___) => fallback,
    );
  }

  /// Browser-like request headers. Several image CDNs that back the listing
  /// catalog (e.g. Yad2's `img.yad2.co.il`, Unsplash) return 403/empty for
  /// requests with a non-browser `User-Agent` or a missing `Referer` — which
  /// on-device surfaced as every photo collapsing to its placeholder. Sending
  /// a standard UA (plus a same-origin Referer) makes the loads behave exactly
  /// like a browser tab, which we verified returns the real JPEG.
  static Map<String, String> _imageRequestHeaders(String url) {
    const userAgent =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
        'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 '
        'Mobile/15E148 Safari/604.1';
    final headers = <String, String>{'User-Agent': userAgent};
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.contains('yad2')) {
      headers['Referer'] = 'https://www.yad2.co.il/';
    }
    return headers;
  }
}
