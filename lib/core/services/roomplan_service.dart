import 'package:flutter/services.dart';

/// Error thrown when a native RoomPlan operation fails (capture or USDZ export).
///
/// A cancelled scan is NOT an error — [RoomPlanService.startScan] returns `null`
/// for that case. This type is reserved for genuine failures (unsupported
/// device, capture session crash, export failure, channel error).
class RoomPlanException implements Exception {
  /// Stable machine-readable code, e.g. `unsupported`, `scan_busy`,
  /// `no_presenter`, `process_failed`, `export_failed`, `session_failed`,
  /// or `channel_error` for unexpected platform-channel failures.
  final String code;

  /// Human-readable description, safe to log.
  final String message;

  const RoomPlanException(this.code, this.message);

  @override
  String toString() => 'RoomPlanException($code): $message';
}

/// Dart wrapper over the native Apple RoomPlan capture channel
/// (`MethodChannel("rently/roomplan")`, implemented in
/// `ios/Runner/RoomPlanChannel.swift`).
///
/// RoomPlan is a Tier-1, LiDAR-only iOS feature (iPhone Pro / iPad Pro on
/// iOS 16+). Always gate UI on [isSupported] before offering a scan: on any
/// other platform or device it returns `false` and [startScan] throws an
/// `unsupported` [RoomPlanException].
///
/// ## Usage (wave-2 wiring)
/// ```dart
/// final roomPlan = RoomPlanService();
///
/// if (await roomPlan.isSupported()) {
///   try {
///     final usdzPath = await roomPlan.startScan();
///     if (usdzPath == null) {
///       // User cancelled the guided capture — no-op.
///     } else {
///       // `usdzPath` is an absolute path to a .usdz file in the app temp dir.
///       // Hand it off (upload / import / preview) before the temp dir is purged.
///     }
///   } on RoomPlanException catch (e) {
///     // Show a friendly message; inspect e.code for handling specific cases.
///   }
/// }
/// ```
class RoomPlanService {
  /// The platform channel name. Must match `RoomPlanChannel.channelName` in
  /// `ios/Runner/RoomPlanChannel.swift`.
  static const MethodChannel _channel = MethodChannel('rently/roomplan');

  const RoomPlanService();

  /// Whether this device can run an Apple RoomPlan capture session.
  ///
  /// Returns `true` only on a LiDAR-equipped iOS 16+ device. Returns `false`
  /// on every other platform (Android, web, desktop), on iOS < 16, on non-LiDAR
  /// iPhones/iPads, and if the native check fails for any reason. Never throws.
  Future<bool> isSupported() async {
    try {
      final result = await _channel.invokeMethod<bool>('isSupported');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // Channel not registered (e.g. Android build) — treat as unsupported.
      return false;
    }
  }

  /// Presents the native guided RoomPlan capture experience modally, runs the
  /// scan, and on a clean finish exports the captured room to a USDZ file.
  ///
  /// Returns the absolute filesystem path to the exported `.usdz` file (located
  /// in the app's temporary directory) on success, or `null` if the user
  /// cancelled the scan.
  ///
  /// The returned file lives in the OS temp directory and may be purged by the
  /// system — copy or upload it promptly.
  ///
  /// Throws a [RoomPlanException] on failure, including:
  /// - `unsupported` — device/OS does not support RoomPlan.
  /// - `scan_busy` — a scan is already in progress.
  /// - `no_presenter` — no view controller available to present the scanner.
  /// - `process_failed` / `export_failed` / `session_failed` — capture or
  ///   USDZ-export problem.
  /// - `channel_error` — unexpected platform-channel failure.
  Future<String?> startScan() async {
    try {
      // A native `nil` (user cancel) arrives here as a Dart `null`.
      final path = await _channel.invokeMethod<String>('startScan');
      return path;
    } on PlatformException catch (e) {
      throw RoomPlanException(e.code, e.message ?? 'RoomPlan scan failed.');
    } on MissingPluginException {
      throw const RoomPlanException(
        'unsupported',
        'RoomPlan is not available on this platform.',
      );
    } catch (e) {
      throw RoomPlanException('channel_error', e.toString());
    }
  }
}
