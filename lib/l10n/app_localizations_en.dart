// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get onboardingHeadline => 'Your apartment is waiting here';

  @override
  String get onboardingSubtitle =>
      'Smart search based on what really matters to you — budget, area, and lifestyle. List an apartment in just a few taps, with all your matches and chats in one place.';

  @override
  String get getStarted => 'Get Started';

  @override
  String get next => 'Next';

  @override
  String get introSwipeTitle => 'Discover apartments by swiping';

  @override
  String get introSwipeBody =>
      'Swipe right 👍 to save an apartment you like, left 👎 to skip. You can also search with Ati (smart search), in the gallery, or on the map.';

  @override
  String get introAtiTitle => 'Ati — Smart Search';

  @override
  String get introAtiBody =>
      'Tell Ati what you\'re looking for, in your own words, and she\'ll find the best-matching apartments for you.';

  @override
  String get introTourTitle => '3D Tours';

  @override
  String get introTourBody =>
      'Step inside before you even leave home — a 360° tour and a 3D experience right from your screen.';

  @override
  String get introMatchTitle => 'Matches & Chat';

  @override
  String get introMatchBody =>
      'When there\'s a mutual match, you can chat directly, schedule a viewing, and close the deal — all in one place.';

  @override
  String get introProfileTitle => 'Your Profile';

  @override
  String get introProfileBody =>
      'Fill in your details to get more accurate matches. The more complete your profile, the better the matches.';

  @override
  String get skip => 'Skip';

  @override
  String get letsGetStarted => 'Let\'s Get Started!';
}
