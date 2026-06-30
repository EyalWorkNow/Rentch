import 'package:firebase_auth/firebase_auth.dart';

/// ─── ADMIN GATE ─────────────────────────────────────────────────────────────
///
/// The Firebase user `notifi@notifi.com` carries the custom claim
/// `notifAdmin: true`. On login we read the ID-token claims and route the admin
/// to the broadcast console instead of [HomeScreen].
///
/// Fully fail-soft: any error (no user, Firebase unavailable, offline) resolves
/// to `false` so a normal user is never accidentally gated.
class NotifAdminGate {
  NotifAdminGate._();

  /// Resolves to `true` iff the signed-in user holds `notifAdmin == true`.
  static Future<bool> isAdmin() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      final result = await user.getIdTokenResult();
      return result.claims?['notifAdmin'] == true;
    } catch (_) {
      return false;
    }
  }
}
