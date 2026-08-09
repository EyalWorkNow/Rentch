import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_he.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('he')
  ];

  /// Onboarding screen main headline
  ///
  /// In he, this message translates to:
  /// **'הדירה שלך מחכה כאן'**
  String get onboardingHeadline;

  /// Onboarding screen subtitle explaining the app
  ///
  /// In he, this message translates to:
  /// **'חיפוש חכם לפי מה שבאמת חשוב לך — תקציב, אזור וסגנון חיים. פרסום דירה בכמה נגיעות, וכל ההתאמות והשיחות במקום אחד.'**
  String get onboardingSubtitle;

  /// Primary CTA button on the onboarding entry screen
  ///
  /// In he, this message translates to:
  /// **'מתחילים'**
  String get getStarted;

  /// Generic 'Next' button used across onboarding steps
  ///
  /// In he, this message translates to:
  /// **'הבא'**
  String get next;

  /// Onboarding intro slide 1 title
  ///
  /// In he, this message translates to:
  /// **'גלה דירות בהחלקה'**
  String get introSwipeTitle;

  /// Onboarding intro slide 1 body
  ///
  /// In he, this message translates to:
  /// **'החליקו ימינה 👍 כדי לשמור דירה שאהבתם, שמאלה 👎 כדי לדלג. אפשר גם לחפש דרך אתי (חיפוש חכם), בגלריה או במפה.'**
  String get introSwipeBody;

  /// Onboarding intro slide 2 title (Ati is the AI assistant's proper name)
  ///
  /// In he, this message translates to:
  /// **'אתי — החיפוש החכם'**
  String get introAtiTitle;

  /// Onboarding intro slide 2 body
  ///
  /// In he, this message translates to:
  /// **'ספרו לאתי מה אתם מחפשים בשפה חופשית, והיא תמצא עבורכם את הדירות המתאימות ביותר.'**
  String get introAtiBody;

  /// Onboarding intro slide 3 title
  ///
  /// In he, this message translates to:
  /// **'סיורים תלת-ממדיים'**
  String get introTourTitle;

  /// Onboarding intro slide 3 body
  ///
  /// In he, this message translates to:
  /// **'נכנסים לדירה עוד לפני שיוצאים מהבית — סיור 360° וחוויית תלת-ממד ישר מהמסך.'**
  String get introTourBody;

  /// Onboarding intro slide 4 title
  ///
  /// In he, this message translates to:
  /// **'התאמות וצ׳אט'**
  String get introMatchTitle;

  /// Onboarding intro slide 4 body
  ///
  /// In he, this message translates to:
  /// **'כשיש התאמה הדדית תוכלו לשוחח ישירות, לתאם סיור ולסגור עניין — הכל במקום אחד.'**
  String get introMatchBody;

  /// Onboarding intro slide 5 title
  ///
  /// In he, this message translates to:
  /// **'הפרופיל שלכם'**
  String get introProfileTitle;

  /// Onboarding intro slide 5 body
  ///
  /// In he, this message translates to:
  /// **'מלאו את הפרטים שלכם כדי לקבל התאמות מדויקות יותר. ככל שהפרופיל שלם יותר — כך ההתאמות טובות יותר.'**
  String get introProfileBody;

  /// Skip button for the onboarding intro carousel
  ///
  /// In he, this message translates to:
  /// **'דלג'**
  String get skip;

  /// Final CTA button on the onboarding intro carousel (distinct from getStarted)
  ///
  /// In he, this message translates to:
  /// **'מתחילים!'**
  String get letsGetStarted;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en', 'es', 'fr', 'he'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'he':
      return AppLocalizationsHe();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
