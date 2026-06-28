import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// On-device scheduled reminders for landlords (rent-due / lease-expiry).
///
/// FCM (see [push_notification_service.dart]) handles *server* push, but it
/// cannot schedule an alarm to fire at a specific future local time. This
/// service uses `flutter_local_notifications` to do exactly that — e.g. "the
/// lease ends in a month, renew?" 30 days before a contract ends.
///
/// Everything here is **fail-soft**: every public method swallows its errors and
/// logs in debug only, so a notification problem can never throw into the UI of
/// an older, less technical landlord.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialised = false;

  /// Stable Android channel for landlord reminders.
  static const String _channelId = 'landlord_reminders';
  static const String _channelName = 'תזכורות בעל דירה';
  static const String _channelDescription =
      'תזכורות על מועדי גביית שכר וסיום חוזה';

  /// Reserved id-space so auto-scheduled lease reminders never collide with the
  /// manual ones the landlord adds in the reminders screen. Lease ids are
  /// derived from the contract id (see [scheduleLeaseExpiry]); keep manual ids
  /// below this offset.
  static const int leaseIdBase = 1000000;

  // ── Init ──────────────────────────────────────────────────────────────────

  /// Initialise the plugin + timezone database. Safe to call more than once.
  /// Returns `true` if the service is ready to schedule.
  Future<bool> init() async {
    if (_initialised) return true;
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Jerusalem'));

      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinInit = DarwinInitializationSettings(
        // We request permission explicitly in [requestPermissions]; don't prompt
        // on init so we can choose the moment (e.g. after onboarding).
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const settings = InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
        macOS: darwinInit,
      );

      await _plugin.initialize(settings);
      _initialised = true;
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('NotificationService.init failed: $e');
      return false;
    }
  }

  /// Ask the OS for permission to show notifications. Call once, e.g. the first
  /// time the landlord opens the reminders screen. Fail-soft → returns `false`
  /// on any error or denial.
  Future<bool> requestPermissions() async {
    if (!await init()) return false;
    try {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        final granted = await ios.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        return granted ?? false;
      }

      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        // Android 13+ runtime notification permission.
        final notif = await android.requestNotificationsPermission();
        // Exact alarms (Android 12+) let reminders fire at the precise time.
        await android.requestExactAlarmsPermission();
        return notif ?? true;
      }

      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('NotificationService.requestPermissions: $e');
      return false;
    }
  }

  // ── Core API ──────────────────────────────────────────────────────────────

  /// Schedule a one-off local reminder. If [when] is in the past it is skipped.
  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    if (!await init()) return;
    try {
      final scheduled = tz.TZDateTime.from(when, tz.local);
      if (scheduled.isBefore(tz.TZDateTime.now(tz.local))) return;

      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        _details(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        // No matchDateTimeComponents → one-shot, not repeating.
      );
    } catch (e) {
      if (kDebugMode) debugPrint('NotificationService.scheduleReminder: $e');
    }
  }

  /// Cancel a single scheduled reminder by id. No-op if it doesn't exist.
  Future<void> cancel(int id) async {
    if (!_initialised) return;
    try {
      await _plugin.cancel(id);
    } catch (e) {
      if (kDebugMode) debugPrint('NotificationService.cancel: $e');
    }
  }

  /// Cancel every scheduled reminder this app owns.
  Future<void> cancelAll() async {
    if (!_initialised) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      if (kDebugMode) debugPrint('NotificationService.cancelAll: $e');
    }
  }

  /// The reminders we've already queued with the OS — lets the screen show the
  /// landlord what's pending. Empty on any error.
  Future<List<PendingNotificationRequest>> pending() async {
    if (!await init()) return const [];
    try {
      return await _plugin.pendingNotificationRequests();
    } catch (e) {
      if (kDebugMode) debugPrint('NotificationService.pending: $e');
      return const [];
    }
  }

  // ── Convenience: lease expiry ───────────────────────────────────────────────

  /// Schedule the two gentle lease-expiry nudges for a signed contract: ~30 days
  /// and ~7 days before [endDate]. [contractId] keys the notification ids so a
  /// re-schedule replaces (rather than duplicates) prior reminders for the same
  /// contract. Pass [contractIndex] to keep ids unique when the source id can't
  /// be hashed to a small int (defaults to a stable hash of [contractId]).
  Future<void> scheduleLeaseExpiry({
    required String propertyTitle,
    required DateTime endDate,
    String contractId = '',
    int? contractIndex,
  }) async {
    if (!await init()) return;

    final title = propertyTitle.trim().isEmpty ? 'הדירה' : propertyTitle.trim();
    final key = contractIndex ?? _stableKey(contractId.isEmpty ? title : contractId);

    // ~1 month before.
    await scheduleReminder(
      id: leaseIdBase + key * 2,
      title: 'חוזה שכירות מסתיים בקרוב',
      body: 'החוזה בדירה "$title" מסתיים בעוד חודש — רוצה לחדש?',
      when: endDate.subtract(const Duration(days: 30)),
    );

    // ~1 week before.
    await scheduleReminder(
      id: leaseIdBase + key * 2 + 1,
      title: 'החוזה מסתיים בעוד שבוע',
      body: 'החוזה בדירה "$title" מסתיים בעוד שבוע — כדאי לסגור חידוש או פינוי.',
      when: endDate.subtract(const Duration(days: 7)),
    );
  }

  /// Cancel both lease-expiry reminders previously queued for a contract.
  Future<void> cancelLeaseExpiry({
    required String contractId,
    int? contractIndex,
  }) async {
    final key = contractIndex ?? _stableKey(contractId);
    await cancel(leaseIdBase + key * 2);
    await cancel(leaseIdBase + key * 2 + 1);
  }

  // ── Internals ───────────────────────────────────────────────────────────────

  NotificationDetails _details() {
    const android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    const darwin = DarwinNotificationDetails();
    return const NotificationDetails(android: android, iOS: darwin, macOS: darwin);
  }

  /// Small, stable, non-negative key derived from a string (so the same contract
  /// always maps to the same notification id). Kept well under the int32 range
  /// the platform schedulers expect.
  int _stableKey(String s) {
    var h = 0;
    for (final unit in s.codeUnits) {
      h = (h * 31 + unit) & 0x3FFFFF; // ≤ ~4.1M, * 2 + base stays in int range
    }
    return h;
  }
}
