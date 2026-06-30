import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import 'package:dating_app/core/services/aws_client.dart';
import 'package:dating_app/data/providers/dating_provider.dart';

/// ─── HOME-SCREEN WIDGET DATA SERVICE ─────────────────────────────────────────
///
/// Computes the user's ACTIVITY SUMMARY — new matches, unread messages, likes —
/// from the existing app state and publishes it to the native home-screen
/// widgets via `home_widget`.
///
/// Data is written under these EXACT keys (the native widgets, built by other
/// agents, read them verbatim):
///   • `w_matches` (int)  — current match count
///   • `w_unread`  (int)  — unread notifications/messages
///   • `w_likes`   (int)  — likes (role-aware: incoming for landlord, sent for tenant)
///   • `w_updated` (int)  — epoch-ms of this write
///
/// iOS App Group id is `group.com.eyalatiyawork.rentch`.
///
/// Fully fail-soft: never throws into callers. Call on app resume and after any
/// relevant data change (new match / like / read).
class HomeWidgetService {
  HomeWidgetService._();

  static const String iosAppGroupId = 'group.com.eyalatiyawork.rentch';

  // Exact widget data keys the native widgets read.
  static const String kMatches = 'w_matches';
  static const String kUnread = 'w_unread';
  static const String kLikes = 'w_likes';
  static const String kUpdated = 'w_updated';

  static bool _appGroupSet = false;

  /// Computes the summary from [provider], writes the keys, and refreshes the
  /// native widgets. `unread` comes from the notifications backend (fail-soft to
  /// the provider's unseen-match count when unavailable).
  static Future<void> sync(DatingProvider provider) async {
    try {
      if (!_appGroupSet) {
        // Required so iOS reads/writes land in the shared App Group container.
        await HomeWidget.setAppGroupId(iosAppGroupId);
        _appGroupSet = true;
      }

      final matches = provider.matchesCount;
      final likes =
          provider.isLandlord ? provider.incomingLikesCount : provider.likesCount;

      // Unread comes from the server-backed notifications inbox; fall back to
      // the locally-tracked unseen matches when the backend is unconfigured.
      int unread;
      try {
        final res = await AwsApiClient.instance.getNotifications();
        unread = res.unread;
      } catch (_) {
        unread = provider.unseenMatchCount;
      }

      await Future.wait([
        HomeWidget.saveWidgetData<int>(kMatches, matches),
        HomeWidget.saveWidgetData<int>(kUnread, unread),
        HomeWidget.saveWidgetData<int>(kLikes, likes),
        HomeWidget.saveWidgetData<int>(
            kUpdated, DateTime.now().millisecondsSinceEpoch),
      ]);

      await HomeWidget.updateWidget(
        // qualifiedAndroidName bypasses the plugin's applicationId prefix: the
        // provider lives in the gradle `namespace` com.rentch.app, NOT the
        // applicationId com.eyalatiyawork.rentch — `name:`/`androidName:` would
        // throw ClassNotFoundException and the widget would never refresh.
        qualifiedAndroidName: 'com.rentch.app.RentlyWidgetProvider',
        iOSName: 'RentlyWidget', // iOS widget kind (RentlyWidget.swift)
      );
    } catch (e) {
      // Never let widget plumbing crash the app (e.g. simulator / no widget).
      debugPrint('HomeWidgetService.sync skipped: $e');
    }
  }
}
