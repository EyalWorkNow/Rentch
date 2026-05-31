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
        errorBuilder: (_, __, ___) => fallback,
      );
    }

    return Image.network(
      cleaned,
      fit: fit,
      alignment: alignment,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}
