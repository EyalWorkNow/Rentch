import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/l10n/app_localizations.dart';

/// ─── FIRST-LAUNCH NOTIFICATION PERMISSION ────────────────────────────────────
///
/// On the user's FIRST entry into the app we show a friendly Hebrew rationale,
/// then request notification permission. `FirebaseMessaging.requestPermission()`
/// covers iOS and triggers the Android 13+ POST_NOTIFICATIONS runtime prompt.
///
/// A "asked already" flag is persisted in shared_preferences so we ask exactly
/// once. Fully fail-soft: any error (e.g. Firebase unavailable) is swallowed and
/// the flag is still set so we never nag the user on every launch.
class NotificationPermissionService {
  NotificationPermissionService._();

  static const _kAskedFlag = 'notif_permission_asked_v1';

  /// Shows the rationale + requests permission once, the first time it's called
  /// for a given install. Safe to call on every entry to [HomeScreen]; it
  /// returns immediately on subsequent runs.
  static Future<void> maybeRequestOnFirstLaunch(BuildContext context) async {
    SharedPreferences prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }
    if (prefs.getBool(_kAskedFlag) == true) return;

    // Mark asked up-front so a crash/close mid-flow doesn't re-prompt forever.
    await prefs.setBool(_kAskedFlag, true);

    if (!context.mounted) return;
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _RationaleDialog(),
    );
    if (proceed != true) return;

    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {
      // Fail-soft: user can still enable from system settings later.
    }
  }
}

class _RationaleDialog extends StatelessWidget {
  const _RationaleDialog();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Directionality(
      textDirection: Directionality.of(context),
      child: AlertDialog(
        backgroundColor: AppColors.surface,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.notifications_active_rounded,
                color: AppColors.primary, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.notificationPermissionService95b74d9c,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
        content: Text(
          '${l10n.notificationPermissionServiceC4d3318f}'
          '${l10n.notificationPermissionService18ca271e}',
          style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.notificationPermissionService98c8a5b8,
                style: const TextStyle(color: AppColors.textDisabled)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.notificationPermissionService1540caea),
          ),
        ],
      ),
    );
  }
}
