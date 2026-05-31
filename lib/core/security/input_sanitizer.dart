import 'package:dating_app/core/security/security_config.dart';
import 'package:path_provider/path_provider.dart';

// All user-supplied data must pass through this class before persistence or display.
// Prevents: XSS-equivalent injection, path traversal, oversized payloads,
// and malicious URL schemes.
class InputSanitizer {
  InputSanitizer._();

  // ── Text inputs ──────────────────────────────────────────────────────────────

  static String sanitizeText(String input, {int maxLength = 500}) {
    return input
        // Remove null bytes (potential injection vector)
        .replaceAll('\x00', '')
        // Remove most control characters except newline, tab, carriage return
        .replaceAll(RegExp(r'[\x01-\x08\x0b\x0c\x0e-\x1f\x7f]'), '')
        .trim()
        // Enforce max length after cleaning
        .substring(0, input.trim().length.clamp(0, maxLength));
  }

  static String sanitizeName(String name) {
    return sanitizeText(name, maxLength: SecurityConfig.maxNameLength);
  }

  static String sanitizeBio(String bio) {
    return sanitizeText(bio, maxLength: SecurityConfig.maxBioLength);
  }

  static String sanitizeMessage(String message) {
    return sanitizeText(message, maxLength: SecurityConfig.maxMessageLength);
  }

  static String sanitizeAddress(String address) {
    return sanitizeText(address, maxLength: SecurityConfig.maxAddressLength);
  }

  // ── Numeric property bounds ───────────────────────────────────────────────────

  static int clampPrice(int price) {
    return price.clamp(
      SecurityConfig.minPropertyPrice,
      SecurityConfig.maxPropertyPrice,
    );
  }

  static double clampRooms(double rooms) {
    return rooms.clamp(SecurityConfig.minRooms, SecurityConfig.maxRooms);
  }

  static int clampSize(int sizeM2) {
    return sizeM2.clamp(SecurityConfig.minSizeM2, SecurityConfig.maxSizeM2);
  }

  // ── URL validation ────────────────────────────────────────────────────────────
  //
  // SEC-9 / SEC-2: Blocks javascript:, data:, vbscript:, and file: schemes.
  // Remote images must use http or https only.

  static String? sanitizeImageUrl(String? raw) {
    final sanitized = sanitizeMediaUrl(raw);
    if (sanitized == null) return null;
    final trimmed = sanitized.trim();
    if (trimmed.startsWith('/') || trimmed.startsWith('file://')) {
      return isImageExtensionAllowed(trimmed) ? trimmed : null;
    }
    return sanitized;
  }

  static String? sanitizeMediaUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.length > SecurityConfig.maxUrlLength) return null;

    final trimmed = raw.trim();

    // Allow local absolute paths — validated separately by isValidLocalPath()
    if (trimmed.startsWith('/') || trimmed.startsWith('file://')) {
      return isMediaExtensionAllowed(trimmed) ? trimmed : null;
    }

    Uri? uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      return null;
    }

    if (!SecurityConfig.allowedRemoteSchemes
        .contains(uri.scheme.toLowerCase())) {
      return null; // Block javascript:, data:, vbscript:, etc.
    }

    // Must have a host
    if (uri.host.isEmpty) return null;

    return trimmed;
  }

  // ── File path traversal prevention ───────────────────────────────────────────
  //
  // SEC-9: A URL like "/../../../etc/passwd" could let a malicious actor read
  // arbitrary device files if passed to Image.file(). This validator ensures
  // the path stays within the app's documents directory.

  static Future<bool> isValidLocalImagePath(String path) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final appRoot = docsDir.path;

      // Normalise to catch tricks like /a/b/../../etc
      final normalised = Uri.file(path).normalizePath().path;

      // Path must be inside the app docs directory
      if (!normalised.startsWith(appRoot)) return false;

      // Must not traverse upward relative to the app root
      if (normalised.contains('..')) return false;

      // Must have an image extension
      final ext = normalised.split('.').last.toLowerCase();
      return SecurityConfig.allowedImageExtensions.contains(ext);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isValidLocalMediaPath(String path) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final appRoot = docsDir.path;
      final normalised = Uri.file(path).normalizePath().path;

      if (!normalised.startsWith(appRoot)) return false;
      if (normalised.contains('..')) return false;

      final ext = normalised.split('.').last.toLowerCase();
      return SecurityConfig.allowedImageExtensions.contains(ext) ||
          SecurityConfig.allowedVideoExtensions.contains(ext);
    } catch (_) {
      return false;
    }
  }

  // Synchronous check (weaker — use async version when possible)
  static bool isValidLocalPathSync(String path) {
    if (path.contains('..')) return false;
    if (path.contains('\x00')) return false;
    final ext = path.split('.').last.toLowerCase();
    return SecurityConfig.allowedImageExtensions.contains(ext);
  }

  static bool isValidLocalMediaPathSync(String path) {
    if (path.contains('..')) return false;
    if (path.contains('\x00')) return false;
    final ext = path.split('.').last.toLowerCase();
    return SecurityConfig.allowedImageExtensions.contains(ext) ||
        SecurityConfig.allowedVideoExtensions.contains(ext);
  }

  // ── File size validation ─────────────────────────────────────────────────────

  static bool isFileSizeAllowed(int bytes) {
    return isImageFileSizeAllowed(bytes);
  }

  static bool isFileExtensionAllowed(String path) {
    return isImageExtensionAllowed(path);
  }

  static bool isImageFileSizeAllowed(int bytes) {
    return bytes > 0 && bytes <= SecurityConfig.maxImageSizeBytes;
  }

  static bool isVideoFileSizeAllowed(int bytes) {
    return bytes > 0 && bytes <= SecurityConfig.maxVideoSizeBytes;
  }

  static bool isImageExtensionAllowed(String path) {
    final ext = path.split('.').last.toLowerCase();
    return SecurityConfig.allowedImageExtensions.contains(ext);
  }

  static bool isVideoExtensionAllowed(String path) {
    final ext = path.split('.').last.toLowerCase();
    return SecurityConfig.allowedVideoExtensions.contains(ext);
  }

  static bool isMediaExtensionAllowed(String path) {
    return isImageExtensionAllowed(path) || isVideoExtensionAllowed(path);
  }

  static bool isLikelyVideoPath(String url) {
    final ext = url.split('.').last.toLowerCase().split('?').first;
    return SecurityConfig.allowedVideoExtensions.contains(ext);
  }

  // ── User role validation ─────────────────────────────────────────────────────
  //
  // SEC-4: Role must come from a fixed allowlist, not arbitrary client input.

  static const Set<String> _allowedRoles = {'tenant', 'landlord', 'guest'};

  static String sanitizeRole(String role) {
    if (_allowedRoles.contains(role)) return role;
    return 'tenant'; // Safe default
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  static bool isMessageTooLong(String text) {
    return text.length > SecurityConfig.maxMessageLength;
  }

  static int remainingChars(String text) {
    return (SecurityConfig.maxMessageLength - text.length)
        .clamp(0, SecurityConfig.maxMessageLength);
  }
}
