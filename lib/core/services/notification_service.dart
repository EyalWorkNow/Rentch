import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/data/models/saved_search.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  /// Stable Android channel for tenant saved-search "new listing" alerts.
  static const String _searchChannelId = 'saved_search_alerts';
  static const String _searchChannelName = 'התראות על דירות חדשות';
  static const String _searchChannelDescription =
      'נודיע לך כשעולה דירה חדשה שמתאימה לחיפוש ששמרת';

  /// Notification ids for saved-search alerts live above the lease range so they
  /// never collide with landlord reminders.
  static const int _searchIdBase = 2000000;

  /// Prefs key holding the set of property ids we've already alerted about, so
  /// we notify once per listing even if [checkSavedSearches] runs every
  /// foreground.
  static const String _notifiedKey = 'saved_search_notified_ids';

  /// Reserved id-space so auto-scheduled lease reminders never collide with the
  /// manual ones the landlord adds in the reminders screen. Lease ids are
  /// derived from the contract id (see [scheduleLeaseExpiry]); keep manual ids
  /// below this offset.
  static const int leaseIdBase = 1000000;

  /// Reserved id-space for viewing (apartment-tour) reminders. A DELIBERATELY
  /// SMALL 19-bit mask (see [viewingReminderId]) caps the span at 512k so the
  /// band 4_000_000..4_524_287 stays disjoint from the lease band (1M + key*2,
  /// up to ~9.4M with a 22-bit key) and the saved-search band (2M + key) — a
  /// wider mask here would let viewing ids collide with those (SCHED-5).
  static const int viewingReminderBase = 4000000;

  /// Stable, non-negative notification id for a viewing reminder keyed by
  /// [slotId]. Masked to 19 bits so it never leaves the reserved viewing band.
  int viewingReminderId(String slotId) {
    var h = 0;
    for (final unit in slotId.codeUnits) {
      h = (h * 31 + unit) & 0x7FFFF; // ≤ 524_287 → band stays 4.0M..4_524_287
    }
    return viewingReminderBase + h;
  }

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

  // ── Tenant: saved-search new-listing alerts ─────────────────────────────────

  /// On app-foreground, look for NEW listings ([RentalProperty.isNewListing])
  /// that match an alerts-on [SavedSearch] and fire a friendly local
  /// notification for each — once per property (deduped via prefs). Returns the
  /// property ids we notified about this run (empty if nothing new / on error).
  ///
  /// Fail-soft: never throws into the tenant's UI.
  Future<List<String>> checkSavedSearches(
    List<SavedSearch> searches,
    List<RentalProperty> properties,
  ) async {
    final active = searches.where((s) => s.alertsOn).toList();
    if (active.isEmpty) return const [];
    if (!await init()) return const [];

    try {
      final prefs = await SharedPreferences.getInstance();
      final notified = (prefs.getStringList(_notifiedKey) ?? const <String>[])
          .toSet();

      final fired = <String>[];
      for (final property in properties) {
        if (!property.isNewListing) continue;
        if (notified.contains(property.id)) continue;

        SavedSearch? hit;
        for (final search in active) {
          if (search.matches(property)) {
            hit = search;
            break;
          }
        }
        if (hit == null) continue;

        await _fireListingAlert(property, hit);
        notified.add(property.id);
        fired.add(property.id);
      }

      if (fired.isNotEmpty) {
        // Cap the dedupe set so it can't grow without bound.
        var ids = notified.toList();
        if (ids.length > 500) ids = ids.sublist(ids.length - 500);
        await prefs.setStringList(_notifiedKey, ids);
      }
      return fired;
    } catch (e) {
      if (kDebugMode) debugPrint('NotificationService.checkSavedSearches: $e');
      return const [];
    }
  }

  /// Fire a sample saved-search alert (for a "send me a test" button / QA).
  Future<void> testFireSavedSearch() async {
    if (!await init()) return;
    await _show(
      _searchIdBase,
      'דירה חדשה שמתאימה לך!',
      'כך תיראה התראה כשתעלה דירה חדשה שמתאימה לחיפוש ששמרת.',
    );
  }

  Future<void> _fireListingAlert(
    RentalProperty property,
    SavedSearch search,
  ) async {
    final where = property.city.trim().isEmpty ? '' : ' ב${property.city.trim()}';
    final rooms = property.rooms;
    final roomsText =
        rooms == rooms.roundToDouble() ? rooms.round().toString() : '$rooms';
    final body = 'דירת $roomsText חדרים$where ב-${property.price} ₪ '
        'מתאימה לחיפוש "${search.name}". מהר — דירות טובות נחטפות בימים.';
    await _show(
      _searchIdBase + _stableKey(property.id),
      'דירה חדשה שמתאימה לך!',
      body,
    );
  }

  Future<void> _show(int id, String title, String body) async {
    try {
      await _plugin.show(id, title, body, _searchDetails());
    } catch (e) {
      if (kDebugMode) debugPrint('NotificationService._show: $e');
    }
  }

  /// Display an incoming FCM push while the app is in the FOREGROUND — the OS does
  /// NOT auto-show notification messages when the app is open, so without this the
  /// user sees nothing while using the app. Uses the high-importance `rently_alerts`
  /// channel so it heads-up (banner + sound), just like a WhatsApp notification.
  Future<void> showForegroundPush(String title, String body) async {
    if (title.trim().isEmpty && body.trim().isEmpty) return;
    try {
      await init(); // idempotent — the plugin may not be initialised yet at launch
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch.remainder(0x7fffffff),
        title.isEmpty ? 'Rently' : title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'rently_alerts',
            'Rently',
            channelDescription: 'התראות Rently',
            importance: Importance.high,
            priority: Priority.high,
          ),
          // Foreground banner + sound on iOS (default suppresses it while open).
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            presentBanner: true,
          ),
          macOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            presentBanner: true,
          ),
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('NotificationService.showForegroundPush: $e');
    }
  }

  // ── Internals ───────────────────────────────────────────────────────────────

  NotificationDetails _searchDetails() {
    const android = AndroidNotificationDetails(
      _searchChannelId,
      _searchChannelName,
      channelDescription: _searchChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    const darwin = DarwinNotificationDetails();
    return const NotificationDetails(android: android, iOS: darwin, macOS: darwin);
  }

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
