import 'dart:io';

import 'package:dating_app/core/security/input_sanitizer.dart';
import 'package:flutter/material.dart';

class SafeImage extends StatelessWidget {
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

  Widget _animatedFrameBuilder(
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded) return child;
    return AnimatedOpacity(
      opacity: frame == null ? 0.0 : 1.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
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
        frameBuilder: _animatedFrameBuilder,
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    // Remote URLs: Flutter's [Image.network] keeps an in-memory cache per
    // session (so re-scrolling the deck doesn't re-fetch) and the test binding
    // handles it gracefully. We attach browser-like headers because several
    // image CDNs backing the catalog (Yad2, Unsplash) can reject a non-browser
    // request, which would otherwise collapse every photo to its placeholder.
    return Image.network(
      cleaned,
      fit: fit,
      alignment: alignment,
      headers: _imageRequestHeaders(cleaned),
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
