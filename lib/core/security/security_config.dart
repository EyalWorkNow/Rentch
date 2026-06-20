// Central registry for all security limits and policies.
// Change here to apply globally — never scatter magic numbers across the codebase.
class SecurityConfig {
  SecurityConfig._();

  // ── Input length limits ──────────────────────────────────────────────────────
  static const int maxMessageLength = 2000;
  static const int maxNameLength = 100;
  static const int maxBioLength = 500;
  static const int maxAddressLength = 200;
  static const int maxUrlLength = 2048;
  static const int maxPropertyNotes = 1000;

  // ── File upload limits ────────────────────────────────────────────────────────
  static const int maxImageSizeBytes = 10 * 1024 * 1024; // 10 MB
  // 3D-scan walkthroughs (Teleport) are minute-long videos and routinely exceed
  // 80 MB; Teleport + the chunked S3 upload handle large files, so allow 400 MB.
  static const int maxVideoSizeBytes = 400 * 1024 * 1024; // 400 MB
  static const int maxFileSizeBytes = maxImageSizeBytes;
  static const int maxPropertyMediaItems = 8;
  static const Set<String> allowedImageExtensions = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
  };
  static const Set<String> allowedVideoExtensions = {
    'mp4',
    'mov',
    'm4v',
    'webm',
  };

  // ── URL scheme allowlist ─────────────────────────────────────────────────────
  // Only http/https are accepted for remote images.
  // javascript:, data:, vbscript:, and file: are blocked.
  static const Set<String> allowedRemoteSchemes = {'https', 'http'};

  // ── Rate limiting ─────────────────────────────────────────────────────────────
  static const int maxStateWritesPerMinute = 15;
  static const int maxSwipesPerMinute = 60;
  static const int maxMessagesPerMinute = 30;
  static const int maxPropertyAddsPerHour = 10;
  static const int maxImageUploadsPerSession = 30;

  // ── Property value bounds (server-side enforcement must mirror these) ─────────
  static const int minPropertyPrice = 0;
  static const int maxPropertyPrice = 150000;
  static const double minRooms = 0;
  static const double maxRooms = 50.0;
  static const int minSizeM2 = 10;
  static const int maxSizeM2 = 1000;

  // ── State document scoping ────────────────────────────────────────────────────
  // Prefix used to generate per-device state document IDs.
  // Never use a fixed string like 'global_state' — that causes all users to
  // share the same Appwrite document (data corruption under concurrent writes).
  static const String stateDocumentPrefix = 'rentch_state_';
}
