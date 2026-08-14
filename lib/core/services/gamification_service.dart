import 'dart:math';

import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GamificationService {
  static const int _dailySuperLikes = 3;
  static const String _superLikeCountKey = 'sl_count';
  static const String _superLikeDateKey = 'sl_date';

  // ─── Trust Score (0-100) ───────────────────────────────────────────────────

  static int computeTrustScore(TenantProfile profile, List<AppReview> reviews) {
    var score = 0;

    if (profile.photoUrls.isNotEmpty) score += 20;
    if (profile.name.trim().length >= 2) score += 10;
    if (profile.bio.trim().length >= 15) score += 15;
    if (profile.budgetMax < 9000) score += 10; // changed from default
    if (profile.desiredRooms > 0) score += 5;
    if (profile.moveInWindow.isNotEmpty && profile.moveInWindow != 'גמיש') {
      score += 10;
    }
    if (profile.importantDetails.isNotEmpty) score += 10;
    if (profile.photoUrls.length >= 2) score += 5; // bonus for multi-photo

    final reviewScore = min(reviews.length * 5, 15);
    score += reviewScore;

    return min(score, 100);
  }

  static String trustScoreLabel(int score) {
    if (score >= 85) return 'מצוין';
    if (score >= 70) return 'טוב מאוד';
    if (score >= 50) return 'טוב';
    if (score >= 30) return 'בינוני';
    return 'חדש';
  }

  // ─── Profile Completion (0-100) ────────────────────────────────────────────

  static int computeProfileCompletion(TenantProfile profile) {
    var pct = 0;
    if (profile.photoUrls.isNotEmpty) pct += 20;
    if (profile.name.trim().length >= 2) pct += 10;
    if (profile.bio.trim().length >= 15) pct += 20;
    if (profile.budgetMax < 9000) pct += 15;
    if (profile.desiredRooms > 0) pct += 10;
    if (profile.moveInWindow.isNotEmpty && profile.moveInWindow != 'גמיש') {
      pct += 15;
    }
    if (profile.importantDetails.isNotEmpty) pct += 10;
    return min(pct, 100);
  }

  static String nextCompletionHint(TenantProfile profile, AppLocalizations l10n) {
    if (profile.photoUrls.isEmpty) return l10n.gamificationHintAddPhoto;
    if (profile.bio.trim().length < 15) return l10n.gamificationHintWriteBio;
    if (profile.budgetMax >= 9000) return l10n.gamificationHintSetBudget;
    if (profile.moveInWindow.isEmpty || profile.moveInWindow == 'גמיש') {
      return l10n.gamificationHintMoveInDate;
    }
    if (profile.importantDetails.isEmpty) return l10n.gamificationHintAddRequirements;
    if (profile.name.trim().length < 2) return l10n.gamificationHintAddName;
    return l10n.gamificationHintAlmostDone;
  }

  // ─── Super Likes ───────────────────────────────────────────────────────────

  static Future<int> getRemainingSuperlikes() async {
    final prefs = await SharedPreferences.getInstance();
    _resetIfNewDay(prefs);
    return _dailySuperLikes - (prefs.getInt(_superLikeCountKey) ?? 0);
  }

  static Future<bool> consumeSuperLike() async {
    final prefs = await SharedPreferences.getInstance();
    _resetIfNewDay(prefs);
    final used = prefs.getInt(_superLikeCountKey) ?? 0;
    if (used >= _dailySuperLikes) return false;
    await prefs.setInt(_superLikeCountKey, used + 1);
    return true;
  }

  /// Give back a consumed super-like (e.g. the user undid the swipe). No-op if
  /// none were used today.
  static Future<void> refundSuperLike() async {
    final prefs = await SharedPreferences.getInstance();
    _resetIfNewDay(prefs);
    final used = prefs.getInt(_superLikeCountKey) ?? 0;
    if (used > 0) await prefs.setInt(_superLikeCountKey, used - 1);
  }

  static Duration timeUntilSuperLikeReset() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    return midnight.difference(now);
  }

  static void _resetIfNewDay(SharedPreferences prefs) {
    final today = _todayString();
    final saved = prefs.getString(_superLikeDateKey) ?? '';
    if (saved != today) {
      prefs.setInt(_superLikeCountKey, 0);
      prefs.setString(_superLikeDateKey, today);
    }
  }

  static String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  // ─── FOMO — Property Signals ───────────────────────────────────────────────

  static bool isHotProperty(RentalProperty p, Set<String> likedIds) {
    return p.marketSignals.likesTodayFor(DateTime.now()) > 0;
  }

  static bool isNewProperty(RentalProperty p) {
    return p.isNewListing;
  }

  @Deprecated('Use RentalProperty.marketSignals.liveViewers instead.')
  static int simulateLiveViewers(RentalProperty p) {
    return p.marketSignals.liveViewers;
  }

  @Deprecated('Use RentalProperty.marketSignals.likesTodayFor instead.')
  static int simulateLikesCount(RentalProperty p) {
    return p.marketSignals.likesTodayFor(DateTime.now());
  }

  // ─── FOMO — Match Expiry ───────────────────────────────────────────────────

  static Duration matchTimeRemaining(RentalMatch match) {
    final expiry = match.createdAt.add(const Duration(hours: 24));
    final remaining = expiry.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  static bool isMatchExpiringSoon(RentalMatch match) {
    return matchTimeRemaining(match).inHours < 6;
  }

  static String formatMatchCountdown(Duration d) {
    if (d == Duration.zero) return 'פג תוקף';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h > 0) return '$hש׳ $mד׳';
    return '$mד׳ ${d.inSeconds.remainder(60)}ש׳';
  }

  static String formatSuperLikeReset(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return 'מתחדש בעוד $hש׳ $mד׳';
  }
}
