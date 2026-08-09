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

  /// No description provided for @addPropertyScreen01587fc6.
  ///
  /// In he, this message translates to:
  /// **'ייבא קבצי 3D מ-Scaniverse'**
  String get addPropertyScreen01587fc6;

  /// No description provided for @addPropertyScreen019fc466.
  ///
  /// In he, this message translates to:
  /// **'קלאסי'**
  String get addPropertyScreen019fc466;

  /// No description provided for @addPropertyScreen01a07bfa.
  ///
  /// In he, this message translates to:
  /// **'רחוב *'**
  String get addPropertyScreen01a07bfa;

  /// No description provided for @addPropertyScreen01d89307.
  ///
  /// In he, this message translates to:
  /// **'הוסף מדיה'**
  String get addPropertyScreen01d89307;

  /// No description provided for @addPropertyScreen0261e82c.
  ///
  /// In he, this message translates to:
  /// **'אולי מאוחר יותר'**
  String get addPropertyScreen0261e82c;

  /// No description provided for @addPropertyScreen029db6c7.
  ///
  /// In he, this message translates to:
  /// **'שלב נוכחי: {stage}'**
  String addPropertyScreen029db6c7(Object stage);

  /// No description provided for @addPropertyScreen047e630b.
  ///
  /// In he, this message translates to:
  /// **'קומה'**
  String get addPropertyScreen047e630b;

  /// No description provided for @addPropertyScreen0516c738.
  ///
  /// In he, this message translates to:
  /// **'טוען סריקות...'**
  String get addPropertyScreen0516c738;

  /// No description provided for @addPropertyScreen069e6d9c.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בעדכון הנכס. נסה שוב.'**
  String get addPropertyScreen069e6d9c;

  /// No description provided for @addPropertyScreen071559e6.
  ///
  /// In he, this message translates to:
  /// **'מצאנו את המיקום אך לא את הכתובת המדויקת. אנא הזן את הרחוב ידנית.'**
  String get addPropertyScreen071559e6;

  /// No description provided for @addPropertyScreen0774dd22.
  ///
  /// In he, this message translates to:
  /// **'סריקת תלת-מימד (מתקדם)'**
  String get addPropertyScreen0774dd22;

  /// No description provided for @addPropertyScreen080d69d6.
  ///
  /// In he, this message translates to:
  /// **'הסר סריקה'**
  String get addPropertyScreen080d69d6;

  /// No description provided for @addPropertyScreen08bc4b8e.
  ///
  /// In he, this message translates to:
  /// **'זכויות שימוש והסכמה'**
  String get addPropertyScreen08bc4b8e;

  /// No description provided for @addPropertyScreen09c74548.
  ///
  /// In he, this message translates to:
  /// **'פרסום דירה מאומתת'**
  String get addPropertyScreen09c74548;

  /// No description provided for @addPropertyScreen0aa42aa1.
  ///
  /// In he, this message translates to:
  /// **'גיל הזהב'**
  String get addPropertyScreen0aa42aa1;

  /// No description provided for @addPropertyScreen0b9f7ab3.
  ///
  /// In he, this message translates to:
  /// **'מחיר לחודש'**
  String get addPropertyScreen0b9f7ab3;

  /// No description provided for @addPropertyScreen0d1d50d5.
  ///
  /// In he, this message translates to:
  /// **'מכל הזוויות'**
  String get addPropertyScreen0d1d50d5;

  /// No description provided for @addPropertyScreen0dfe6469.
  ///
  /// In he, this message translates to:
  /// **'תיאור חופשי'**
  String get addPropertyScreen0dfe6469;

  /// No description provided for @addPropertyScreen0eb8cbf6.
  ///
  /// In he, this message translates to:
  /// **'מדלן'**
  String get addPropertyScreen0eb8cbf6;

  /// No description provided for @addPropertyScreen0ef54864.
  ///
  /// In he, this message translates to:
  /// **'שירותי המיקום כבויים. אנא הפעל את ה-GPS במכשיר ונסה שוב.'**
  String get addPropertyScreen0ef54864;

  /// No description provided for @addPropertyScreen10666b28.
  ///
  /// In he, this message translates to:
  /// **'הסר'**
  String get addPropertyScreen10666b28;

  /// No description provided for @addPropertyScreen10a2352b.
  ///
  /// In he, this message translates to:
  /// **'חזרה'**
  String get addPropertyScreen10a2352b;

  /// No description provided for @addPropertyScreen11985996.
  ///
  /// In he, this message translates to:
  /// **'קומו'**
  String get addPropertyScreen11985996;

  /// No description provided for @addPropertyScreen12363d34.
  ///
  /// In he, this message translates to:
  /// **'הזיזו את הטלפון באיטיות וברציפות, בלי טלטולים — תנועה מהירה גורמת לטשטוש והסריקה נכשלת.'**
  String get addPropertyScreen12363d34;

  /// No description provided for @addPropertyScreen12a06cf7.
  ///
  /// In he, this message translates to:
  /// **'סה\"כ קומות'**
  String get addPropertyScreen12a06cf7;

  /// No description provided for @addPropertyScreen14bfc214.
  ///
  /// In he, this message translates to:
  /// **'בפרסום מאומת אין העלאה מהגלריה, קישור URL, תמונות או וידאו קיים. וידאו האימות המצולם הוא המדיה היחידה של הדירה.'**
  String get addPropertyScreen14bfc214;

  /// No description provided for @addPropertyScreen167d6757.
  ///
  /// In he, this message translates to:
  /// **'חזרה לתיקון'**
  String get addPropertyScreen167d6757;

  /// No description provided for @addPropertyScreen171d2e69.
  ///
  /// In he, this message translates to:
  /// **'צבע מותאם'**
  String get addPropertyScreen171d2e69;

  /// No description provided for @addPropertyScreen177fad3e.
  ///
  /// In he, this message translates to:
  /// **'מותר להעביר את המידע לצד שלישי'**
  String get addPropertyScreen177fad3e;

  /// No description provided for @addPropertyScreen17f383ab.
  ///
  /// In he, this message translates to:
  /// **'העלה תמונות וסרטונים המראים את הדירה במיטבה'**
  String get addPropertyScreen17f383ab;

  /// No description provided for @addPropertyScreen1a2ea5e9.
  ///
  /// In he, this message translates to:
  /// **'הבנתי, התחל צילום'**
  String get addPropertyScreen1a2ea5e9;

  /// No description provided for @addPropertyScreen1c463eec.
  ///
  /// In he, this message translates to:
  /// **'בחר תאריך כניסה'**
  String get addPropertyScreen1c463eec;

  /// No description provided for @addPropertyScreen1db3ad15.
  ///
  /// In he, this message translates to:
  /// **'{pct}% התאמה'**
  String addPropertyScreen1db3ad15(Object pct);

  /// No description provided for @addPropertyScreen1dec9ba9.
  ///
  /// In he, this message translates to:
  /// **'המיקום זוהה והוזן בהצלחה!'**
  String get addPropertyScreen1dec9ba9;

  /// No description provided for @addPropertyScreen1ef6d872.
  ///
  /// In he, this message translates to:
  /// **'הסר וידאו אימות'**
  String get addPropertyScreen1ef6d872;

  /// No description provided for @addPropertyScreen2110e73c.
  ///
  /// In he, this message translates to:
  /// **'אפשר לצרף עד {max} פריטי מדיה.'**
  String addPropertyScreen2110e73c(Object max);

  /// No description provided for @addPropertyScreen220a89be.
  ///
  /// In he, this message translates to:
  /// **'דירה מאומתת'**
  String get addPropertyScreen220a89be;

  /// No description provided for @addPropertyScreen220d2733.
  ///
  /// In he, this message translates to:
  /// **'פרטי הנכס'**
  String get addPropertyScreen220d2733;

  /// No description provided for @addPropertyScreen25035307.
  ///
  /// In he, this message translates to:
  /// **'מותר שימוש לאימון מודלים ו-AI'**
  String get addPropertyScreen25035307;

  /// No description provided for @addPropertyScreen2661e422.
  ///
  /// In he, this message translates to:
  /// **'תמונות וסרטונים'**
  String get addPropertyScreen2661e422;

  /// No description provided for @addPropertyScreen26b77aa9.
  ///
  /// In he, this message translates to:
  /// **'צלם וידאו'**
  String get addPropertyScreen26b77aa9;

  /// No description provided for @addPropertyScreen26d0e7de.
  ///
  /// In he, this message translates to:
  /// **'מיקום'**
  String get addPropertyScreen26d0e7de;

  /// No description provided for @addPropertyScreen26e3bf17.
  ///
  /// In he, this message translates to:
  /// **'שוכרים שאינם באחד הקהלים שבחרת לא יראו את המודעה בכלל.'**
  String get addPropertyScreen26e3bf17;

  /// No description provided for @addPropertyScreen2793159b.
  ///
  /// In he, this message translates to:
  /// **'הגדר/י מי רואה את הדירה לפי תנאי סף'**
  String get addPropertyScreen2793159b;

  /// No description provided for @addPropertyScreen27a1ebbb.
  ///
  /// In he, this message translates to:
  /// **'הסיור בעיבוד'**
  String get addPropertyScreen27a1ebbb;

  /// No description provided for @addPropertyScreen284dcfc6.
  ///
  /// In he, this message translates to:
  /// **'גודל הדירה הוא שדה חובה'**
  String get addPropertyScreen284dcfc6;

  /// No description provided for @addPropertyScreen29022c25.
  ///
  /// In he, this message translates to:
  /// **'כל הקהלים שהוצעו כבר נבחרו'**
  String get addPropertyScreen29022c25;

  /// No description provided for @addPropertyScreen29eeeaf9.
  ///
  /// In he, this message translates to:
  /// **'עדיין למכירה'**
  String get addPropertyScreen29eeeaf9;

  /// No description provided for @addPropertyScreen2a9831da.
  ///
  /// In he, this message translates to:
  /// **'ב-Scaniverse: Export → Gaussian Splat → פורמט PLY (זה מה שנותן את המראה האמיתי).'**
  String get addPropertyScreen2a9831da;

  /// No description provided for @addPropertyScreen2f99f2f3.
  ///
  /// In he, this message translates to:
  /// **'בחר תאריך'**
  String get addPropertyScreen2f99f2f3;

  /// No description provided for @addPropertyScreen2ff0e6d2.
  ///
  /// In he, this message translates to:
  /// **'סיור 3D מוכן לפרסום'**
  String get addPropertyScreen2ff0e6d2;

  /// No description provided for @addPropertyScreen3105947c.
  ///
  /// In he, this message translates to:
  /// **'מותר שימוש מסחרי ומכירה עסקית של המידע'**
  String get addPropertyScreen3105947c;

  /// No description provided for @addPropertyScreen32fecb03.
  ///
  /// In he, this message translates to:
  /// **'מחיר מבוקש (סה\"כ)'**
  String get addPropertyScreen32fecb03;

  /// No description provided for @addPropertyScreen34c0f6af.
  ///
  /// In he, this message translates to:
  /// **'סריקות מחשבון Niantic Spatial שלך'**
  String get addPropertyScreen34c0f6af;

  /// No description provided for @addPropertyScreen357b4923.
  ///
  /// In he, this message translates to:
  /// **'מצב הנכס'**
  String get addPropertyScreen357b4923;

  /// No description provided for @addPropertyScreen3643cc83.
  ///
  /// In he, this message translates to:
  /// **'צלם סריקה'**
  String get addPropertyScreen3643cc83;

  /// No description provided for @addPropertyScreen3700d2e3.
  ///
  /// In he, this message translates to:
  /// **'קהלי יעד'**
  String get addPropertyScreen3700d2e3;

  /// No description provided for @addPropertyScreen3a1c4b62.
  ///
  /// In he, this message translates to:
  /// **'התחילו מהכניסה ועברו בין כל החללים ברצף אחד עד 60 שניות, בלי לדלג על חדרים.'**
  String get addPropertyScreen3a1c4b62;

  /// No description provided for @addPropertyScreen3af8a1a1.
  ///
  /// In he, this message translates to:
  /// **'לוח שוק'**
  String get addPropertyScreen3af8a1a1;

  /// No description provided for @addPropertyScreen3b32c520.
  ///
  /// In he, this message translates to:
  /// **'צלם מחדש'**
  String get addPropertyScreen3b32c520;

  /// No description provided for @addPropertyScreen3ced3c61.
  ///
  /// In he, this message translates to:
  /// **'דורש צילום תוך כדי הליכה לאט בחלל. (לסיור נאמן ומומלץ השתמשו בסיור ה־360° למעלה.)'**
  String get addPropertyScreen3ced3c61;

  /// No description provided for @addPropertyScreen3f5d2c29.
  ///
  /// In he, this message translates to:
  /// **'בחר סריקה מ-Scaniverse'**
  String get addPropertyScreen3f5d2c29;

  /// No description provided for @addPropertyScreen40625d63.
  ///
  /// In he, this message translates to:
  /// **'בחר קובץ'**
  String get addPropertyScreen40625d63;

  /// No description provided for @addPropertyScreen40b9326f.
  ///
  /// In he, this message translates to:
  /// **'בדירה מאומתת אפשר לצלם רק וידאו אימות מתוך האפליקציה.'**
  String get addPropertyScreen40b9326f;

  /// No description provided for @addPropertyScreen4193112f.
  ///
  /// In he, this message translates to:
  /// **'דתי-לאומי'**
  String get addPropertyScreen4193112f;

  /// No description provided for @addPropertyScreen42ed7e8d.
  ///
  /// In he, this message translates to:
  /// **'סטודנט/ית'**
  String get addPropertyScreen42ed7e8d;

  /// No description provided for @addPropertyScreen43854d31.
  ///
  /// In he, this message translates to:
  /// **'כדי לקבל סריקה פוטוריאליסטית עם טקסטורות אמיתיות:'**
  String get addPropertyScreen43854d31;

  /// No description provided for @addPropertyScreen4543e3ff.
  ///
  /// In he, this message translates to:
  /// **'קהלים מוצעים · הקש/י כדי להוסיף'**
  String get addPropertyScreen4543e3ff;

  /// No description provided for @addPropertyScreen49717ede.
  ///
  /// In he, this message translates to:
  /// **'אורה'**
  String get addPropertyScreen49717ede;

  /// No description provided for @addPropertyScreen4a140235.
  ///
  /// In he, this message translates to:
  /// **'מדיה'**
  String get addPropertyScreen4a140235;

  /// No description provided for @addPropertyScreen4b627a97.
  ///
  /// In he, this message translates to:
  /// **'צילום וידאו האימות נכשל: {error}'**
  String addPropertyScreen4b627a97(Object error);

  /// No description provided for @addPropertyScreen4c43bbb7.
  ///
  /// In he, this message translates to:
  /// **'מוכן'**
  String get addPropertyScreen4c43bbb7;

  /// No description provided for @addPropertyScreen4c5623c0.
  ///
  /// In he, this message translates to:
  /// **'פייסבוק'**
  String get addPropertyScreen4c5623c0;

  /// No description provided for @addPropertyScreen4ca20c2a.
  ///
  /// In he, this message translates to:
  /// **'לחץ על ״החלף סריקה״ לנסות שוב (ייתכן שיש להתחבר תחילה לחשבון).'**
  String get addPropertyScreen4ca20c2a;

  /// No description provided for @addPropertyScreen4ca22f8c.
  ///
  /// In he, this message translates to:
  /// **'הבא →'**
  String get addPropertyScreen4ca22f8c;

  /// No description provided for @addPropertyScreen4ce111ab.
  ///
  /// In he, this message translates to:
  /// **'שכונה (אופציונלי)'**
  String get addPropertyScreen4ce111ab;

  /// No description provided for @addPropertyScreen4d0509a1.
  ///
  /// In he, this message translates to:
  /// **'קריטריונים לשוכר'**
  String get addPropertyScreen4d0509a1;

  /// No description provided for @addPropertyScreen4de5edeb.
  ///
  /// In he, this message translates to:
  /// **'סיור 360° — מומלץ'**
  String get addPropertyScreen4de5edeb;

  /// No description provided for @addPropertyScreen4df994d0.
  ///
  /// In he, this message translates to:
  /// **'זוג'**
  String get addPropertyScreen4df994d0;

  /// No description provided for @addPropertyScreen4e248a37.
  ///
  /// In he, this message translates to:
  /// **'מעלה וידאו לסריקה'**
  String get addPropertyScreen4e248a37;

  /// No description provided for @addPropertyScreen4f4cd24f.
  ///
  /// In he, this message translates to:
  /// **'מספר חדרים'**
  String get addPropertyScreen4f4cd24f;

  /// No description provided for @addPropertyScreen505591bb.
  ///
  /// In he, this message translates to:
  /// **'הרשאות המיקום חסומות בהגדרות. פתח את ההגדרות כדי לאפשר גישה למיקום.'**
  String get addPropertyScreen505591bb;

  /// No description provided for @addPropertyScreen50e1cc8f.
  ///
  /// In he, this message translates to:
  /// **'גודל הנכס במ\"ר *'**
  String get addPropertyScreen50e1cc8f;

  /// No description provided for @addPropertyScreen51e40a86.
  ///
  /// In he, this message translates to:
  /// **'איפה נמצאת הדירה?'**
  String get addPropertyScreen51e40a86;

  /// No description provided for @addPropertyScreen51ea6413.
  ///
  /// In he, this message translates to:
  /// **'קולנועי'**
  String get addPropertyScreen51ea6413;

  /// No description provided for @addPropertyScreen522e3eb2.
  ///
  /// In he, this message translates to:
  /// **'שומר...'**
  String get addPropertyScreen522e3eb2;

  /// No description provided for @addPropertyScreen52572a81.
  ///
  /// In he, this message translates to:
  /// **'כדי לשמור דירה מאומתת צריך לצלם וידאו מתוך האפליקציה.'**
  String get addPropertyScreen52572a81;

  /// No description provided for @addPropertyScreen53c1e86a.
  ///
  /// In he, this message translates to:
  /// **'הצע לי קהלים נוספים'**
  String get addPropertyScreen53c1e86a;

  /// No description provided for @addPropertyScreen587839cb.
  ///
  /// In he, this message translates to:
  /// **'המחיר גבוה מהרגיל 🤔'**
  String get addPropertyScreen587839cb;

  /// No description provided for @addPropertyScreen596fb349.
  ///
  /// In he, this message translates to:
  /// **'אשר/י שהמדיה והמודל שייכים לך או הועלו ברשות, ובחר/י אילו שימושים מותרים.'**
  String get addPropertyScreen596fb349;

  /// No description provided for @addPropertyScreen5a3d760f.
  ///
  /// In he, this message translates to:
  /// **'למי הדירה מתאימה?'**
  String get addPropertyScreen5a3d760f;

  /// No description provided for @addPropertyScreen5a64ad70.
  ///
  /// In he, this message translates to:
  /// **'לא להשכרה / הושכר'**
  String get addPropertyScreen5a64ad70;

  /// No description provided for @addPropertyScreen5b1afce7.
  ///
  /// In he, this message translates to:
  /// **'הורה יחיד'**
  String get addPropertyScreen5b1afce7;

  /// No description provided for @addPropertyScreen5b53dba2.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בבדיקת סטטוס הסריקה. נסה שוב.'**
  String get addPropertyScreen5b53dba2;

  /// No description provided for @addPropertyScreen5d12163b.
  ///
  /// In he, this message translates to:
  /// **'הקובץ יובא. לאיכות פוטוריאליסטית מלאה (כמו הדירה האמיתית) ייצאו מ-Scaniverse בפורמט Gaussian Splat · PLY.'**
  String get addPropertyScreen5d12163b;

  /// No description provided for @addPropertyScreen5ef6e641.
  ///
  /// In he, this message translates to:
  /// **'הסריקה נשמרה כטיוטה. שליחת הסריקה לעיבוד אינה זמינה כרגע.'**
  String get addPropertyScreen5ef6e641;

  /// No description provided for @addPropertyScreen5f3306da.
  ///
  /// In he, this message translates to:
  /// **'עולה חדש'**
  String get addPropertyScreen5f3306da;

  /// No description provided for @addPropertyScreen5f839c99.
  ///
  /// In he, this message translates to:
  /// **'אני מאשר/ת תנאי שימוש, זכויות העלאה וחתימה דיגיטלית לנכס זה'**
  String get addPropertyScreen5f839c99;

  /// No description provided for @addPropertyScreen609fac18.
  ///
  /// In he, this message translates to:
  /// **'למכירה'**
  String get addPropertyScreen609fac18;

  /// No description provided for @addPropertyScreen633c184b.
  ///
  /// In he, this message translates to:
  /// **'המחיר שהזנת נראה נמוך משמעותית מהשוק לגודל ולעיר הזו.\nטווח סביר: {low}–{high}.\n\nאולי נפלה טעות? אפשר לתקן, או להמשיך אם המחיר נכון.'**
  String addPropertyScreen633c184b(Object high, Object low);

  /// No description provided for @addPropertyScreen6454f0d9.
  ///
  /// In he, this message translates to:
  /// **'הקיפו כל חדר'**
  String get addPropertyScreen6454f0d9;

  /// No description provided for @addPropertyScreen65134a55.
  ///
  /// In he, this message translates to:
  /// **'{count} חדרים נסרקו · אפשר להוסיף עוד'**
  String addPropertyScreen65134a55(Object count);

  /// No description provided for @addPropertyScreen660f2d8e.
  ///
  /// In he, this message translates to:
  /// **'יש למלא את השדות הנדרשים'**
  String get addPropertyScreen660f2d8e;

  /// No description provided for @addPropertyScreen6668d49a.
  ///
  /// In he, this message translates to:
  /// **'הגעת ל-3 דירות'**
  String get addPropertyScreen6668d49a;

  /// No description provided for @addPropertyScreen66dab183.
  ///
  /// In he, this message translates to:
  /// **'עדכון הנכס'**
  String get addPropertyScreen66dab183;

  /// No description provided for @addPropertyScreen678addb0.
  ///
  /// In he, this message translates to:
  /// **'יש לאשר את תנאי השימוש והצהרת הזכויות לפני שמירת הנכס.'**
  String get addPropertyScreen678addb0;

  /// No description provided for @addPropertyScreen693dc98a.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בזיהוי המיקום. נסה שוב או הזן כתובת ידנית.'**
  String get addPropertyScreen693dc98a;

  /// No description provided for @addPropertyScreen6ad485fc.
  ///
  /// In he, this message translates to:
  /// **'הוספת תמונה או סרטון'**
  String get addPropertyScreen6ad485fc;

  /// No description provided for @addPropertyScreen6db49fbf.
  ///
  /// In he, this message translates to:
  /// **'טיפ: GLB/OBJ נותנים משטח פשוט ללא מראה אמיתי; PLY נותן איכות מלאה.'**
  String get addPropertyScreen6db49fbf;

  /// No description provided for @addPropertyScreen7157bd90.
  ///
  /// In he, this message translates to:
  /// **'חשיפת הדירה'**
  String get addPropertyScreen7157bd90;

  /// No description provided for @addPropertyScreen71b19dc0.
  ///
  /// In he, this message translates to:
  /// **'ייבוא סריקות אינו זמין כרגע.'**
  String get addPropertyScreen71b19dc0;

  /// No description provided for @addPropertyScreen72daab72.
  ///
  /// In he, this message translates to:
  /// **'מזהה מיקום...'**
  String get addPropertyScreen72daab72;

  /// No description provided for @addPropertyScreen75007f0f.
  ///
  /// In he, this message translates to:
  /// **'סריקת ה־3D נכשלה: {error}'**
  String addPropertyScreen75007f0f(Object error);

  /// No description provided for @addPropertyScreen770b3193.
  ///
  /// In he, this message translates to:
  /// **'פרסום של יותר מ-3 דירות זמין בחשבון סוכן נדל\"ן — ניהול דירות ולקוחות ללא הגבלה, כלים מתקדמים ומיתוג אישי. אפשר לעבור עכשיו בחינם.'**
  String get addPropertyScreen770b3193;

  /// No description provided for @addPropertyScreen773c5c3a.
  ///
  /// In he, this message translates to:
  /// **'וידאו'**
  String get addPropertyScreen773c5c3a;

  /// No description provided for @addPropertyScreen7810f5bc.
  ///
  /// In he, this message translates to:
  /// **'ישראל'**
  String get addPropertyScreen7810f5bc;

  /// No description provided for @addPropertyScreen79286e19.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בשמירת הנכס. נסה שוב.'**
  String get addPropertyScreen79286e19;

  /// No description provided for @addPropertyScreen7a35525f.
  ///
  /// In he, this message translates to:
  /// **'אור חזק'**
  String get addPropertyScreen7a35525f;

  /// No description provided for @addPropertyScreen7affb975.
  ///
  /// In he, this message translates to:
  /// **'מלא עיר ורחוב לפחות'**
  String get addPropertyScreen7affb975;

  /// No description provided for @addPropertyScreen7c7eea47.
  ///
  /// In he, this message translates to:
  /// **'הטקסט מכיל תוכן לא הולם. אנא תקנו ונסו שוב.'**
  String get addPropertyScreen7c7eea47;

  /// No description provided for @addPropertyScreen7d93908e.
  ///
  /// In he, this message translates to:
  /// **'סוג נכס'**
  String get addPropertyScreen7d93908e;

  /// No description provided for @addPropertyScreen831251d3.
  ///
  /// In he, this message translates to:
  /// **'בעיבוד'**
  String get addPropertyScreen831251d3;

  /// No description provided for @addPropertyScreen83b5eecd.
  ///
  /// In he, this message translates to:
  /// **'הסיור המומלץ — נאמן למציאות. צילום מודרך כמו Street View'**
  String get addPropertyScreen83b5eecd;

  /// No description provided for @addPropertyScreen869f5479.
  ///
  /// In he, this message translates to:
  /// **'כל הדירה, 30–60 שניות'**
  String get addPropertyScreen869f5479;

  /// No description provided for @addPropertyScreen886a9c57.
  ///
  /// In he, this message translates to:
  /// **'הצג את הדירה רק לשוכרים מתאימים'**
  String get addPropertyScreen886a9c57;

  /// No description provided for @addPropertyScreen8aa60741.
  ///
  /// In he, this message translates to:
  /// **'הוספת יותר מדי נכסים לאחרונה. נסה שוב מאוחר יותר.'**
  String get addPropertyScreen8aa60741;

  /// No description provided for @addPropertyScreen8c1a2960.
  ///
  /// In he, this message translates to:
  /// **'דירה מאומתת היא דירה שצילמתם בה סרטון קצר ואמיתי מתוך האפליקציה. ככה השוכרים יודעים שהדירה אמיתית — והיא מוצגת ליותר אנשים ומופיעה גבוה יותר ברשימה.'**
  String get addPropertyScreen8c1a2960;

  /// No description provided for @addPropertyScreen8df397b9.
  ///
  /// In he, this message translates to:
  /// **'בחר/י את הקהלים שהדירה מתאימה להם'**
  String get addPropertyScreen8df397b9;

  /// No description provided for @addPropertyScreen8df76593.
  ///
  /// In he, this message translates to:
  /// **'הדליקו אורות ופתחו וילונות. חדר חשוך או נגד-אור פוגע בשחזור התלת-ממדי.'**
  String get addPropertyScreen8df76593;

  /// No description provided for @addPropertyScreen8e578468.
  ///
  /// In he, this message translates to:
  /// **'יש לאשר את תנאי השימוש והצהרת הזכויות לפני פרסום נכס.'**
  String get addPropertyScreen8e578468;

  /// No description provided for @addPropertyScreen8ef7538b.
  ///
  /// In he, this message translates to:
  /// **'משפחה ערבית'**
  String get addPropertyScreen8ef7538b;

  /// No description provided for @addPropertyScreen9150f977.
  ///
  /// In he, this message translates to:
  /// **'עריכת נכס · {step}'**
  String addPropertyScreen9150f977(Object step);

  /// No description provided for @addPropertyScreen926c043f.
  ///
  /// In he, this message translates to:
  /// **'משפחה'**
  String get addPropertyScreen926c043f;

  /// No description provided for @addPropertyScreen949b4a98.
  ///
  /// In he, this message translates to:
  /// **'הסיור התלת־ממדי בעיבוד (בערך שעה). אפשר לשמור את הדירה — הוא יופיע אוטומטית כשיהיה מוכן.'**
  String get addPropertyScreen949b4a98;

  /// No description provided for @addPropertyScreen960b1b81.
  ///
  /// In he, this message translates to:
  /// **'{count} נקודות נוספו · הקש לעריכה או הוספה'**
  String addPropertyScreen960b1b81(Object count);

  /// No description provided for @addPropertyScreen96502cd7.
  ///
  /// In he, this message translates to:
  /// **'הלקוחות יראו כפתור סיור רק כשה־viewer יהיה מוכן.'**
  String get addPropertyScreen96502cd7;

  /// No description provided for @addPropertyScreen97c25fd2.
  ///
  /// In he, this message translates to:
  /// **'בדירה מאומתת סריקות והעלאות ננעלות עד ביטול מצב האימות.'**
  String get addPropertyScreen97c25fd2;

  /// No description provided for @addPropertyScreen9805e992.
  ///
  /// In he, this message translates to:
  /// **'לא נבחרו קהלים — אף שוכר לא יראה את המודעה. בחר/י לפחות קהל אחד.'**
  String get addPropertyScreen9805e992;

  /// No description provided for @addPropertyScreen98c2a61b.
  ///
  /// In he, this message translates to:
  /// **'חד׳'**
  String get addPropertyScreen98c2a61b;

  /// No description provided for @addPropertyScreen9abff18f.
  ///
  /// In he, this message translates to:
  /// **'עיבוד הסריקה לקח יותר מדי זמן. נסה שוב מאוחר יותר.'**
  String get addPropertyScreen9abff18f;

  /// No description provided for @addPropertyScreen9af0e89b.
  ///
  /// In he, this message translates to:
  /// **'קהל יעד'**
  String get addPropertyScreen9af0e89b;

  /// No description provided for @addPropertyScreen9b5409b0.
  ///
  /// In he, this message translates to:
  /// **'ברירת מחדל'**
  String get addPropertyScreen9b5409b0;

  /// No description provided for @addPropertyScreen9b83f0d4.
  ///
  /// In he, this message translates to:
  /// **'המחיר נמוך מהרגיל 🤔'**
  String get addPropertyScreen9b83f0d4;

  /// No description provided for @addPropertyScreen9d7f0ccc.
  ///
  /// In he, this message translates to:
  /// **'תאר/י בכמה מילים למי הדירה הכי מתאימה'**
  String get addPropertyScreen9d7f0ccc;

  /// No description provided for @addPropertyScreen9d93e38a.
  ///
  /// In he, this message translates to:
  /// **'לא למכירה / נמכר'**
  String get addPropertyScreen9d93e38a;

  /// No description provided for @addPropertyScreen9fcb2927.
  ///
  /// In he, this message translates to:
  /// **'כדי לאמת את הדירה צריך לצלם עכשיו וידאו קצר מתוך האפליקציה.'**
  String get addPropertyScreen9fcb2927;

  /// No description provided for @addPropertyScreena0023ea0.
  ///
  /// In he, this message translates to:
  /// **'המחיר נכון, המשך'**
  String get addPropertyScreena0023ea0;

  /// No description provided for @addPropertyScreena0d84eba.
  ///
  /// In he, this message translates to:
  /// **'יד2'**
  String get addPropertyScreena0d84eba;

  /// No description provided for @addPropertyScreena2f81627.
  ///
  /// In he, this message translates to:
  /// **'עדיין להשכרה'**
  String get addPropertyScreena2f81627;

  /// No description provided for @addPropertyScreena3390850.
  ///
  /// In he, this message translates to:
  /// **'מעבר לחשבון סוכן נדל\"ן'**
  String get addPropertyScreena3390850;

  /// No description provided for @addPropertyScreena384ef27.
  ///
  /// In he, this message translates to:
  /// **'בחר וידאו'**
  String get addPropertyScreena384ef27;

  /// No description provided for @addPropertyScreena45d761d.
  ///
  /// In he, this message translates to:
  /// **'בחר את כל המאפיינים הרלוונטיים'**
  String get addPropertyScreena45d761d;

  /// No description provided for @addPropertyScreena52badf2.
  ///
  /// In he, this message translates to:
  /// **'תמונה מהגלריה'**
  String get addPropertyScreena52badf2;

  /// No description provided for @addPropertyScreena638b329.
  ///
  /// In he, this message translates to:
  /// **'{count} קהלים נבחרו'**
  String addPropertyScreena638b329(Object count);

  /// No description provided for @addPropertyScreena75dc6ef.
  ///
  /// In he, this message translates to:
  /// **'וידאו מהגלריה'**
  String get addPropertyScreena75dc6ef;

  /// No description provided for @addPropertyScreena7b9e9c8.
  ///
  /// In he, this message translates to:
  /// **'אימות דורש צילום וידאו מתוך האפליקציה בלבד'**
  String get addPropertyScreena7b9e9c8;

  /// No description provided for @addPropertyScreena7c55a8d.
  ///
  /// In he, this message translates to:
  /// **'ביטול'**
  String get addPropertyScreena7c55a8d;

  /// No description provided for @addPropertyScreena9b90f35.
  ///
  /// In he, this message translates to:
  /// **'קשר סריקה מ-Scaniverse'**
  String get addPropertyScreena9b90f35;

  /// No description provided for @addPropertyScreena9d8a4a6.
  ///
  /// In he, this message translates to:
  /// **'כדי לפרסם דירה מאומתת צריך לצלם וידאו מתוך האפליקציה.'**
  String get addPropertyScreena9d8a4a6;

  /// No description provided for @addPropertyScreenad864fbf.
  ///
  /// In he, this message translates to:
  /// **'{selected} נבחרו מתוך {total}'**
  String addPropertyScreenad864fbf(Object selected, Object total);

  /// No description provided for @addPropertyScreenada826e5.
  ///
  /// In he, this message translates to:
  /// **'תמונה'**
  String get addPropertyScreenada826e5;

  /// No description provided for @addPropertyScreenae219326.
  ///
  /// In he, this message translates to:
  /// **'סריקת תלת-מימד כמו הדירה האמיתית'**
  String get addPropertyScreenae219326;

  /// No description provided for @addPropertyScreenaf3b65b4.
  ///
  /// In he, this message translates to:
  /// **'הרשאת המיקום נדחתה. ניתן להזין את הכתובת ידנית.'**
  String get addPropertyScreenaf3b65b4;

  /// No description provided for @addPropertyScreenb336259f.
  ///
  /// In he, this message translates to:
  /// **'להשכרה'**
  String get addPropertyScreenb336259f;

  /// No description provided for @addPropertyScreenb429eced.
  ///
  /// In he, this message translates to:
  /// **'כרטיס נכס'**
  String get addPropertyScreenb429eced;

  /// No description provided for @addPropertyScreenb51e8e0e.
  ///
  /// In he, this message translates to:
  /// **'חזרו לכאן ובחרו את קובץ ה-PLY שיוצא.'**
  String get addPropertyScreenb51e8e0e;

  /// No description provided for @addPropertyScreenb7cdc163.
  ///
  /// In he, this message translates to:
  /// **'תאריך כניסה'**
  String get addPropertyScreenb7cdc163;

  /// No description provided for @addPropertyScreenb8283dde.
  ///
  /// In he, this message translates to:
  /// **'ערוצי פרסום'**
  String get addPropertyScreenb8283dde;

  /// No description provided for @addPropertyScreenb8d9266b.
  ///
  /// In he, this message translates to:
  /// **'רווק/ה'**
  String get addPropertyScreenb8d9266b;

  /// No description provided for @addPropertyScreenba7e182b.
  ///
  /// In he, this message translates to:
  /// **'איך מצלמים סריקת 3D מוצלחת'**
  String get addPropertyScreenba7e182b;

  /// No description provided for @addPropertyScreenba865047.
  ///
  /// In he, this message translates to:
  /// **'המחיר שהזנת נראה גבוה משמעותית מהשוק לגודל ולעיר הזו.\nטווח סביר: {low}–{high}.\n\nאולי נפלה טעות? אפשר לתקן, או להמשיך אם המחיר נכון.'**
  String addPropertyScreenba865047(Object high, Object low);

  /// No description provided for @addPropertyScreenbd5a7818.
  ///
  /// In he, this message translates to:
  /// **'פרסום הדירה'**
  String get addPropertyScreenbd5a7818;

  /// No description provided for @addPropertyScreenc19510f4.
  ///
  /// In he, this message translates to:
  /// **'מספר'**
  String get addPropertyScreenc19510f4;

  /// No description provided for @addPropertyScreenc471ccde.
  ///
  /// In he, this message translates to:
  /// **'תאורה טובה'**
  String get addPropertyScreenc471ccde;

  /// No description provided for @addPropertyScreenc53121b7.
  ///
  /// In he, this message translates to:
  /// **'סריקה נשמרה וממתינה לעיבוד'**
  String get addPropertyScreenc53121b7;

  /// No description provided for @addPropertyScreenc5ffac09.
  ///
  /// In he, this message translates to:
  /// **'נסה שוב'**
  String get addPropertyScreenc5ffac09;

  /// No description provided for @addPropertyScreenc68a292c.
  ///
  /// In he, this message translates to:
  /// **'החלף סריקה'**
  String get addPropertyScreenc68a292c;

  /// No description provided for @addPropertyScreenc69dd25b.
  ///
  /// In he, this message translates to:
  /// **'הסרטון גדול מדי ({mb} MB). צלם סרטון קצר יותר של עד 60 שניות.'**
  String addPropertyScreenc69dd25b(Object mb);

  /// No description provided for @addPropertyScreenc6c7d5f7.
  ///
  /// In he, this message translates to:
  /// **'בעל הדירה'**
  String get addPropertyScreenc6c7d5f7;

  /// No description provided for @addPropertyScreenc7a300bf.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בהעלאת התמונה לשרת. בדוק את החיבור לאינטרנט ונסה שוב.'**
  String get addPropertyScreenc7a300bf;

  /// No description provided for @addPropertyScreenc9059001.
  ///
  /// In he, this message translates to:
  /// **'סורקים חדר-חדר באיכות גבוהה'**
  String get addPropertyScreenc9059001;

  /// No description provided for @addPropertyScreencc83e982.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בהעלאת הוידאו לשרת. בדוק את החיבור לאינטרנט ונסה שוב.'**
  String get addPropertyScreencc83e982;

  /// No description provided for @addPropertyScreencf0a5531.
  ///
  /// In he, this message translates to:
  /// **'הוסף'**
  String get addPropertyScreencf0a5531;

  /// No description provided for @addPropertyScreencf89b9f4.
  ///
  /// In he, this message translates to:
  /// **'איפה הנכס מפורסם? (Rently מסומן כברירת מחדל)'**
  String get addPropertyScreencf89b9f4;

  /// No description provided for @addPropertyScreend065f1c3.
  ///
  /// In he, this message translates to:
  /// **'הדבק כתובת URL של תמונה או וידאו'**
  String get addPropertyScreend065f1c3;

  /// No description provided for @addPropertyScreend2c66acd.
  ///
  /// In he, this message translates to:
  /// **'בחרו תבנית לדף הנכס וצבע מותאם אישית'**
  String get addPropertyScreend2c66acd;

  /// No description provided for @addPropertyScreend3437839.
  ///
  /// In he, this message translates to:
  /// **'הווידאו נשמר במכשיר. כדי לשלוח לעיבוד יש לוודא שהגדרות השרת תקינות.'**
  String get addPropertyScreend3437839;

  /// No description provided for @addPropertyScreend3709dea.
  ///
  /// In he, this message translates to:
  /// **'חדר אחרי חדר'**
  String get addPropertyScreend3709dea;

  /// No description provided for @addPropertyScreend50e4f12.
  ///
  /// In he, this message translates to:
  /// **'בקרה על מי רואה את המודעה'**
  String get addPropertyScreend50e4f12;

  /// No description provided for @addPropertyScreend59e06c9.
  ///
  /// In he, this message translates to:
  /// **'לא הצלחנו לקבל מיקום (ייתכן שאתה במקום סגור). נסה שוב בחוץ או הזן כתובת ידנית.'**
  String get addPropertyScreend59e06c9;

  /// No description provided for @addPropertyScreend62ffbe2.
  ///
  /// In he, this message translates to:
  /// **'מחפש קהלים...'**
  String get addPropertyScreend62ffbe2;

  /// No description provided for @addPropertyScreend663155d.
  ///
  /// In he, this message translates to:
  /// **'צעיר/ה מקצועי/ת'**
  String get addPropertyScreend663155d;

  /// No description provided for @addPropertyScreend93995bc.
  ///
  /// In he, this message translates to:
  /// **'ייבוא מודל מ-Scaniverse נכשל: {error}'**
  String addPropertyScreend93995bc(Object error);

  /// No description provided for @addPropertyScreend9728103.
  ///
  /// In he, this message translates to:
  /// **'המשך סריקת חדרים'**
  String get addPropertyScreend9728103;

  /// No description provided for @addPropertyScreend9b329d6.
  ///
  /// In he, this message translates to:
  /// **'עיר *'**
  String get addPropertyScreend9b329d6;

  /// No description provided for @addPropertyScreendabf278d.
  ///
  /// In he, this message translates to:
  /// **'צלמו לאט ויציב'**
  String get addPropertyScreendabf278d;

  /// No description provided for @addPropertyScreendb2a79db.
  ///
  /// In he, this message translates to:
  /// **'להסיר את \"{address}\"?\nהפעולה אינה ניתנת לביטול.'**
  String addPropertyScreendb2a79db(Object address);

  /// No description provided for @addPropertyScreendbf53e53.
  ///
  /// In he, this message translates to:
  /// **'הורידו את האפליקציה החינמית Scaniverse וסרקו את הדירה — הליכה איטית, תאורה טובה, חפיפה בין הזוויות.'**
  String get addPropertyScreendbf53e53;

  /// No description provided for @addPropertyScreendc7a9892.
  ///
  /// In he, this message translates to:
  /// **'הורים טריים'**
  String get addPropertyScreendc7a9892;

  /// No description provided for @addPropertyScreenddde6811.
  ///
  /// In he, this message translates to:
  /// **'בדירה מאומתת אי אפשר להוסיף מדיה ידנית או מהגלריה.'**
  String get addPropertyScreenddde6811;

  /// No description provided for @addPropertyScreende01bf6a.
  ///
  /// In he, this message translates to:
  /// **'הנכס עודכן בהצלחה'**
  String get addPropertyScreende01bf6a;

  /// No description provided for @addPropertyScreene08c750c.
  ///
  /// In he, this message translates to:
  /// **'מאפיינים'**
  String get addPropertyScreene08c750c;

  /// No description provided for @addPropertyScreene31d1ebb.
  ///
  /// In he, this message translates to:
  /// **'הוספת קישור למדיה'**
  String get addPropertyScreene31d1ebb;

  /// No description provided for @addPropertyScreene3af9561.
  ///
  /// In he, this message translates to:
  /// **'מאפיינים ויתרונות'**
  String get addPropertyScreene3af9561;

  /// No description provided for @addPropertyScreene49ffe99.
  ///
  /// In he, this message translates to:
  /// **'משקיע'**
  String get addPropertyScreene49ffe99;

  /// No description provided for @addPropertyScreene7066c75.
  ///
  /// In he, this message translates to:
  /// **'וידאו האימות נשמר מתוך המצלמה של האפליקציה.'**
  String get addPropertyScreene7066c75;

  /// No description provided for @addPropertyScreeneb255ed5.
  ///
  /// In he, this message translates to:
  /// **'הסרת נכס'**
  String get addPropertyScreeneb255ed5;

  /// No description provided for @addPropertyScreenede98a87.
  ///
  /// In he, this message translates to:
  /// **'וידאו אימות מוכן'**
  String get addPropertyScreenede98a87;

  /// No description provided for @addPropertyScreenee18cd86.
  ///
  /// In he, this message translates to:
  /// **'התחל סריקת חדרים'**
  String get addPropertyScreenee18cd86;

  /// No description provided for @addPropertyScreenee3ba7dc.
  ///
  /// In he, this message translates to:
  /// **'עוזר לנו להראות את הדירה לשוכרים הנכונים'**
  String get addPropertyScreenee3ba7dc;

  /// No description provided for @addPropertyScreeneed2fbf3.
  ///
  /// In he, this message translates to:
  /// **'גלריה'**
  String get addPropertyScreeneed2fbf3;

  /// No description provided for @addPropertyScreeneff93e0f.
  ///
  /// In he, this message translates to:
  /// **'צלם וידאו אימות'**
  String get addPropertyScreeneff93e0f;

  /// No description provided for @addPropertyScreenf0632a71.
  ///
  /// In he, this message translates to:
  /// **'מחיקת נכס'**
  String get addPropertyScreenf0632a71;

  /// No description provided for @addPropertyScreenf0e12300.
  ///
  /// In he, this message translates to:
  /// **'זהה מיקום אוטומטית לפי ה-GPS'**
  String get addPropertyScreenf0e12300;

  /// No description provided for @addPropertyScreenf221fec9.
  ///
  /// In he, this message translates to:
  /// **'העיבוד נכשל'**
  String get addPropertyScreenf221fec9;

  /// No description provided for @addPropertyScreenf3fd4b5d.
  ///
  /// In he, this message translates to:
  /// **'עיצוב דף הדירה'**
  String get addPropertyScreenf3fd4b5d;

  /// No description provided for @addPropertyScreenf41975d9.
  ///
  /// In he, this message translates to:
  /// **'פתח הגדרות'**
  String get addPropertyScreenf41975d9;

  /// No description provided for @addPropertyScreenf5203dea.
  ///
  /// In he, this message translates to:
  /// **'עובד/ת מרחוק'**
  String get addPropertyScreenf5203dea;

  /// No description provided for @addPropertyScreenf5842882.
  ///
  /// In he, this message translates to:
  /// **'הדירה עלתה! ניקוד מודעה: {score}/100 · {label}'**
  String addPropertyScreenf5842882(Object label, Object score);

  /// No description provided for @addPropertyScreenf6144e67.
  ///
  /// In he, this message translates to:
  /// **'עברו סביב כל חדר וצלמו את הקירות, הפינות והרהיטים מכמה זוויות עם חפיפה ביניהן.'**
  String get addPropertyScreenf6144e67;

  /// No description provided for @addPropertyScreenf6291745.
  ///
  /// In he, this message translates to:
  /// **'פותח מצלמה...'**
  String get addPropertyScreenf6291745;

  /// No description provided for @addPropertyScreenf70797b1.
  ///
  /// In he, this message translates to:
  /// **'לא נמצאו סריקות בחשבון Scaniverse.'**
  String get addPropertyScreenf70797b1;

  /// No description provided for @addPropertyScreenf96bc686.
  ///
  /// In he, this message translates to:
  /// **'בחר מאפיינים ({total} אפשרויות)'**
  String addPropertyScreenf96bc686(Object total);

  /// No description provided for @addPropertyScreenfaf87ec6.
  ///
  /// In he, this message translates to:
  /// **'הזן קישור ידנית (URL)'**
  String get addPropertyScreenfaf87ec6;

  /// No description provided for @addPropertyScreenfed27efc.
  ///
  /// In he, this message translates to:
  /// **'חרדי'**
  String get addPropertyScreenfed27efc;

  /// No description provided for @addPropertyScreenfeddf7c6.
  ///
  /// In he, this message translates to:
  /// **'צלם תמונה'**
  String get addPropertyScreenfeddf7c6;

  /// No description provided for @authScreenE60dc428.
  ///
  /// In he, this message translates to:
  /// **'כניסה עם Google לא מופעלת בסביבת ההרצה הזו'**
  String get authScreenE60dc428;

  /// No description provided for @authScreen014274ee.
  ///
  /// In he, this message translates to:
  /// **'הכניסה עם Google לא זמינה כרגע. נסו שוב מאוחר יותר.'**
  String get authScreen014274ee;

  /// No description provided for @authScreenB840c378.
  ///
  /// In he, this message translates to:
  /// **'הכניסה עם Google נכשלה. נסו שוב.'**
  String get authScreenB840c378;

  /// No description provided for @authScreenE8a66331.
  ///
  /// In he, this message translates to:
  /// **'כניסה עם Apple זמינה במכשירי Apple בלבד.'**
  String get authScreenE8a66331;

  /// No description provided for @authScreen3219b950.
  ///
  /// In he, this message translates to:
  /// **'הכניסה עם Apple נכשלה.\n\nקוד: {code}\nפרטים: {message}'**
  String authScreen3219b950(Object code, Object message);

  /// No description provided for @authScreen129e293c.
  ///
  /// In he, this message translates to:
  /// **'הכניסה עם Apple נכשלה.\n\n{errorType}: {error}'**
  String authScreen129e293c(Object error, Object errorType);

  /// No description provided for @authScreenF8a2e73f.
  ///
  /// In he, this message translates to:
  /// **'כניסה עם Apple לא מופעלת כרגע. נסו שוב מאוחר יותר.'**
  String get authScreenF8a2e73f;

  /// No description provided for @authScreen7859b4af.
  ///
  /// In he, this message translates to:
  /// **'כתובת המייל כבר רשומה עם שיטת כניסה אחרת. נסו להיכנס עם Google.'**
  String get authScreen7859b4af;

  /// No description provided for @authScreenF38c0181.
  ///
  /// In he, this message translates to:
  /// **'פרטי ה-Apple אינם תקינים. נסו שוב.'**
  String get authScreenF38c0181;

  /// No description provided for @authScreen8732894f.
  ///
  /// In he, this message translates to:
  /// **'החשבון הזה הושבת. פנו לתמיכה.'**
  String get authScreen8732894f;

  /// No description provided for @authScreen03eefe21.
  ///
  /// In he, this message translates to:
  /// **'הכניסה עם Apple נכשלה ({code}). נסו שוב.'**
  String authScreen03eefe21(Object code);

  /// No description provided for @authScreenB47b239c.
  ///
  /// In he, this message translates to:
  /// **'כניסה עם Apple'**
  String get authScreenB47b239c;

  /// No description provided for @authScreen55247199.
  ///
  /// In he, this message translates to:
  /// **'סגור'**
  String get authScreen55247199;

  /// No description provided for @authScreenCb3a4292.
  ///
  /// In he, this message translates to:
  /// **'כניסה כאורח'**
  String get authScreenCb3a4292;

  /// No description provided for @authScreen466443ed.
  ///
  /// In he, this message translates to:
  /// **'מחפש/ת דירה'**
  String get authScreen466443ed;

  /// No description provided for @authScreenB651765c.
  ///
  /// In he, this message translates to:
  /// **'בעל/ת דירה'**
  String get authScreenB651765c;

  /// No description provided for @authScreen244b2e78.
  ///
  /// In he, this message translates to:
  /// **'מתווך/ת נדל״ן'**
  String get authScreen244b2e78;

  /// No description provided for @authScreen9a81c6ab.
  ///
  /// In he, this message translates to:
  /// **'סוג חשבון'**
  String get authScreen9a81c6ab;

  /// No description provided for @authScreenD882def5.
  ///
  /// In he, this message translates to:
  /// **'בעל דירה / מתווך'**
  String get authScreenD882def5;

  /// No description provided for @authScreenE94abfe2.
  ///
  /// In he, this message translates to:
  /// **'שינוי'**
  String get authScreenE94abfe2;

  /// No description provided for @authScreen9108bd8e.
  ///
  /// In he, this message translates to:
  /// **'הדרך המהירה\nלמצוא את הבית הבא שלך.'**
  String get authScreen9108bd8e;

  /// No description provided for @authScreen196178b9.
  ///
  /// In he, this message translates to:
  /// **'Rently מחבר שוכרים ומשכירים בחוויה חכמה, מהירה וברורה.'**
  String get authScreen196178b9;

  /// No description provided for @authScreen8ba10a13.
  ///
  /// In he, this message translates to:
  /// **'גלילת דירות חכמה'**
  String get authScreen8ba10a13;

  /// No description provided for @authScreen4726806c.
  ///
  /// In he, this message translates to:
  /// **'מציג רק את מה שמתאים לפרופיל שלך'**
  String get authScreen4726806c;

  /// No description provided for @authScreenB312f1ad.
  ///
  /// In he, this message translates to:
  /// **'התאמה דו-כיוונית'**
  String get authScreenB312f1ad;

  /// No description provided for @authScreenB92874cd.
  ///
  /// In he, this message translates to:
  /// **'שוכרים ומשכירים מאשרים זה את זה'**
  String get authScreenB92874cd;

  /// No description provided for @authScreen4bc28625.
  ///
  /// In he, this message translates to:
  /// **'צ׳אט ישיר'**
  String get authScreen4bc28625;

  /// No description provided for @authScreen4ec7649d.
  ///
  /// In he, this message translates to:
  /// **'תקשורת ממוקדת בין הצדדים'**
  String get authScreen4ec7649d;

  /// No description provided for @authScreen2f6783cd.
  ///
  /// In he, this message translates to:
  /// **'כניסה'**
  String get authScreen2f6783cd;

  /// No description provided for @authScreen070f0a6c.
  ///
  /// In he, this message translates to:
  /// **'הרשמה'**
  String get authScreen070f0a6c;

  /// No description provided for @authScreen0e36c58d.
  ///
  /// In he, this message translates to:
  /// **'התחברות לחשבון'**
  String get authScreen0e36c58d;

  /// No description provided for @authScreen988da9b2.
  ///
  /// In he, this message translates to:
  /// **'התחברו כדי להמשיך'**
  String get authScreen988da9b2;

  /// No description provided for @authScreen20f9f23f.
  ///
  /// In he, this message translates to:
  /// **'אין לך חשבון? '**
  String get authScreen20f9f23f;

  /// No description provided for @authScreenAa4727fb.
  ///
  /// In he, this message translates to:
  /// **'להרשמה'**
  String get authScreenAa4727fb;

  /// No description provided for @authScreenFbff31ee.
  ///
  /// In he, this message translates to:
  /// **'או'**
  String get authScreenFbff31ee;

  /// No description provided for @authScreen7e02b34c.
  ///
  /// In he, this message translates to:
  /// **'המשך כאורח'**
  String get authScreen7e02b34c;

  /// No description provided for @authScreen6bf26430.
  ///
  /// In he, this message translates to:
  /// **'בחרו האם להיכנס כבעל דירה או כדייר שמחפש דירה.'**
  String get authScreen6bf26430;

  /// No description provided for @authScreen10683ed0.
  ///
  /// In he, this message translates to:
  /// **'אורח כדייר מחפש דירה'**
  String get authScreen10683ed0;

  /// No description provided for @authScreen24eb3d5b.
  ///
  /// In he, this message translates to:
  /// **'דירות פעילות ומאצ׳ים פתוחים.'**
  String get authScreen24eb3d5b;

  /// No description provided for @authScreen7e33e9cc.
  ///
  /// In he, this message translates to:
  /// **'אורח כבעל דירה'**
  String get authScreen7e33e9cc;

  /// No description provided for @authScreenBb12d654.
  ///
  /// In he, this message translates to:
  /// **'נכסים פעילים ומועמדים בתהליך.'**
  String get authScreenBb12d654;

  /// No description provided for @authScreen160b6f4f.
  ///
  /// In he, this message translates to:
  /// **'אורח כמתווך נדל״ן'**
  String get authScreen160b6f4f;

  /// No description provided for @authScreen7345afa5.
  ///
  /// In he, this message translates to:
  /// **'ניהול נכסים, לידים והתאמות ללקוחות.'**
  String get authScreen7345afa5;

  /// No description provided for @authScreen405e3450.
  ///
  /// In he, this message translates to:
  /// **'כניסה כבעל דירה'**
  String get authScreen405e3450;

  /// No description provided for @authScreen98539dbe.
  ///
  /// In he, this message translates to:
  /// **'בחרו את סוג החשבון. מחפשי דירה נכנסים כברירת מחדל.'**
  String get authScreen98539dbe;

  /// No description provided for @authScreenF2529a48.
  ///
  /// In he, this message translates to:
  /// **'פרסם נכסים, נהל בקשות ומצא דיירים.'**
  String get authScreenF2529a48;

  /// No description provided for @authScreenA25bd15a.
  ///
  /// In he, this message translates to:
  /// **'תנאי השימוש'**
  String get authScreenA25bd15a;

  /// No description provided for @authScreen6525ddbe.
  ///
  /// In he, this message translates to:
  /// **'יש למלא אימייל וסיסמה'**
  String get authScreen6525ddbe;

  /// No description provided for @authScreen50aeb2c9.
  ///
  /// In he, this message translates to:
  /// **'אימייל או סיסמה שגויים'**
  String get authScreen50aeb2c9;

  /// No description provided for @authScreen831cf0fb.
  ///
  /// In he, this message translates to:
  /// **'החשבון מושבת'**
  String get authScreen831cf0fb;

  /// No description provided for @authScreen19cf13ef.
  ///
  /// In he, this message translates to:
  /// **'יותר מדי ניסיונות, נסה שוב מאוחר יותר'**
  String get authScreen19cf13ef;

  /// No description provided for @authScreenB4d2edd3.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בכניסה, נסה שוב'**
  String get authScreenB4d2edd3;

  /// No description provided for @authScreenCe759227.
  ///
  /// In he, this message translates to:
  /// **'אין חיבור לרשת. בדוק את החיבור לאינטרנט ונסה שוב.'**
  String get authScreenCe759227;

  /// No description provided for @authScreenF887665d.
  ///
  /// In he, this message translates to:
  /// **'הזינו קודם את כתובת האימייל שלכם לאיפוס הסיסמה'**
  String get authScreenF887665d;

  /// No description provided for @authScreen293d3e32.
  ///
  /// In he, this message translates to:
  /// **'שלחנו קישור לאיפוס סיסמה למייל שלך'**
  String get authScreen293d3e32;

  /// No description provided for @authScreen2d361111.
  ///
  /// In he, this message translates to:
  /// **'כתובת האימייל אינה תקינה'**
  String get authScreen2d361111;

  /// No description provided for @authScreenFf749680.
  ///
  /// In he, this message translates to:
  /// **'לא נמצא חשבון עם האימייל הזה'**
  String get authScreenFf749680;

  /// No description provided for @authScreen2c3813b7.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בשליחת קישור האיפוס, נסה שוב'**
  String get authScreen2c3813b7;

  /// No description provided for @authScreenD8d84317.
  ///
  /// In he, this message translates to:
  /// **'ברוכים השבים'**
  String get authScreenD8d84317;

  /// No description provided for @authScreenAdf821d4.
  ///
  /// In he, this message translates to:
  /// **'התחברו עם כתובת האימייל והסיסמה שלכם כדי לגשת לחשבון.'**
  String get authScreenAdf821d4;

  /// No description provided for @authScreen98bcf26f.
  ///
  /// In he, this message translates to:
  /// **'כתובת אימייל'**
  String get authScreen98bcf26f;

  /// No description provided for @authScreen0b490b5e.
  ///
  /// In he, this message translates to:
  /// **'סיסמה'**
  String get authScreen0b490b5e;

  /// No description provided for @authScreen3e35b351.
  ///
  /// In he, this message translates to:
  /// **'זכור אותי'**
  String get authScreen3e35b351;

  /// No description provided for @authScreenD30f1cbd.
  ///
  /// In he, this message translates to:
  /// **'שכחת סיסמה?'**
  String get authScreenD30f1cbd;

  /// No description provided for @authScreen254e07f0.
  ///
  /// In he, this message translates to:
  /// **'התחברות'**
  String get authScreen254e07f0;

  /// No description provided for @authScreen73103765.
  ///
  /// In he, this message translates to:
  /// **'בהתחברות אני מאשר/ת את '**
  String get authScreen73103765;

  /// No description provided for @authScreen7fcb9eb9.
  ///
  /// In he, this message translates to:
  /// **'יש להזין שם מלא'**
  String get authScreen7fcb9eb9;

  /// No description provided for @authScreen574b1fc6.
  ///
  /// In he, this message translates to:
  /// **'יש להזין כתובת אימייל תקינה'**
  String get authScreen574b1fc6;

  /// No description provided for @authScreen2da8e039.
  ///
  /// In he, this message translates to:
  /// **'הסיסמה חייבת להכיל לפחות 8 תווים'**
  String get authScreen2da8e039;

  /// No description provided for @authScreen02f3dc71.
  ///
  /// In he, this message translates to:
  /// **'יש לאשר את תנאי השימוש ומדיניות הפרטיות'**
  String get authScreen02f3dc71;

  /// No description provided for @authScreenEf5731e6.
  ///
  /// In he, this message translates to:
  /// **'בואו נתחיל'**
  String get authScreenEf5731e6;

  /// No description provided for @authScreen5f9edf6e.
  ///
  /// In he, this message translates to:
  /// **'הבא'**
  String get authScreen5f9edf6e;

  /// No description provided for @authScreenE0c41b8a.
  ///
  /// In he, this message translates to:
  /// **'כבר יש לך חשבון? '**
  String get authScreenE0c41b8a;

  /// No description provided for @authScreenC8443e85.
  ///
  /// In he, this message translates to:
  /// **'תנאי השימוש ב-Rently'**
  String get authScreenC8443e85;

  /// No description provided for @authScreen45133532.
  ///
  /// In he, this message translates to:
  /// **'ברוך הבא ל-Rently!\nבשימוש באפליקציה אתה מסכים לתנאים הבאים:'**
  String get authScreen45133532;

  /// No description provided for @authScreen7293f5b9.
  ///
  /// In he, this message translates to:
  /// **'1. תוכן הולם'**
  String get authScreen7293f5b9;

  /// No description provided for @authScreen2b76ec99.
  ///
  /// In he, this message translates to:
  /// **'אין לפרסם תוכן פוגעני, גזעני, מיני, מאיים או כל תוכן שפוגע בזכויות אחרים.'**
  String get authScreen2b76ec99;

  /// No description provided for @authScreenA6ae0dee.
  ///
  /// In he, this message translates to:
  /// **'2. ללא אלימות ואיום'**
  String get authScreenA6ae0dee;

  /// No description provided for @authScreen47b2d219.
  ///
  /// In he, this message translates to:
  /// **'כל צורה של הטרדה, איום, בריונות או התנהגות פוגענית אסורה לחלוטין.'**
  String get authScreen47b2d219;

  /// No description provided for @authScreenD0daea7a.
  ///
  /// In he, this message translates to:
  /// **'3. דיווח תוכן'**
  String get authScreenD0daea7a;

  /// No description provided for @authScreen000cadd8.
  ///
  /// In he, this message translates to:
  /// **'משתמשים יכולים לדווח על תוכן שפוגע בהנחיות. נטפל בכל דיווח תוך 24 שעות.'**
  String get authScreen000cadd8;

  /// No description provided for @authScreen191d3078.
  ///
  /// In he, this message translates to:
  /// **'4. חסימת משתמשים'**
  String get authScreen191d3078;

  /// No description provided for @authScreen7c37683f.
  ///
  /// In he, this message translates to:
  /// **'ניתן לחסום כל משתמש שמתנהג בצורה לא הולמת.'**
  String get authScreen7c37683f;

  /// No description provided for @authScreenFd03e34f.
  ///
  /// In he, this message translates to:
  /// **'5. פרטיות'**
  String get authScreenFd03e34f;

  /// No description provided for @authScreenAde0b8ea.
  ///
  /// In he, this message translates to:
  /// **'אנו מכבדים את פרטיותך. המידע ישמש לצורך התאמת נכסים בלבד.'**
  String get authScreenAde0b8ea;

  /// No description provided for @authScreenA7c55a8d.
  ///
  /// In he, this message translates to:
  /// **'ביטול'**
  String get authScreenA7c55a8d;

  /// No description provided for @authScreen5aa0e747.
  ///
  /// In he, this message translates to:
  /// **'אני מסכים/ה'**
  String get authScreen5aa0e747;

  /// No description provided for @authScreenFde2ad8e.
  ///
  /// In he, this message translates to:
  /// **'הצלחה!'**
  String get authScreenFde2ad8e;

  /// No description provided for @authScreen6253b039.
  ///
  /// In he, this message translates to:
  /// **'החשבון שלך נוצר בהצלחה ומוכן כעת.'**
  String get authScreen6253b039;

  /// No description provided for @authScreenAd82fb71.
  ///
  /// In he, this message translates to:
  /// **'המשך לאפליקציה'**
  String get authScreenAd82fb71;

  /// No description provided for @authScreenE0fe08d4.
  ///
  /// In he, this message translates to:
  /// **'חשבון'**
  String get authScreenE0fe08d4;

  /// No description provided for @authScreenEd927047.
  ///
  /// In he, this message translates to:
  /// **'תפקיד'**
  String get authScreenEd927047;

  /// No description provided for @authScreenA4ce69e7.
  ///
  /// In he, this message translates to:
  /// **'פרטים'**
  String get authScreenA4ce69e7;

  /// No description provided for @authScreenB88c2d71.
  ///
  /// In he, this message translates to:
  /// **'נכס'**
  String get authScreenB88c2d71;

  /// No description provided for @authScreen9c274654.
  ///
  /// In he, this message translates to:
  /// **'יצירת חשבון'**
  String get authScreen9c274654;

  /// No description provided for @authScreen99e0559d.
  ///
  /// In he, this message translates to:
  /// **'מלאו את שמכם המלא, אימייל וסיסמה כדי להירשם ולהתחיל.'**
  String get authScreen99e0559d;

  /// No description provided for @authScreenCbdaff61.
  ///
  /// In he, this message translates to:
  /// **'שם מלא'**
  String get authScreenCbdaff61;

  /// No description provided for @authScreen0e7dc6f6.
  ///
  /// In he, this message translates to:
  /// **'שם ושם משפחה'**
  String get authScreen0e7dc6f6;

  /// No description provided for @authScreen10fb73fe.
  ///
  /// In he, this message translates to:
  /// **'אני מסכים/ה ל'**
  String get authScreen10fb73fe;

  /// No description provided for @authScreen0e3bcbcf.
  ///
  /// In he, this message translates to:
  /// **' ו'**
  String get authScreen0e3bcbcf;

  /// No description provided for @authScreenF52fda14.
  ///
  /// In he, this message translates to:
  /// **'מדיניות הפרטיות'**
  String get authScreenF52fda14;

  /// No description provided for @authScreenFd025bb4.
  ///
  /// In he, this message translates to:
  /// **'תקציב השכירות שלך'**
  String get authScreenFd025bb4;

  /// No description provided for @authScreenC178b5d4.
  ///
  /// In he, this message translates to:
  /// **'הגדר את התקציב החודשי כדי שנוכל להתאים עבורך את הדירות הטובות ביותר.'**
  String get authScreenC178b5d4;

  /// No description provided for @authScreen4094ac8d.
  ///
  /// In he, this message translates to:
  /// **'תקציב חודשי'**
  String get authScreen4094ac8d;

  /// No description provided for @authScreen10a2352b.
  ///
  /// In he, this message translates to:
  /// **'חזרה'**
  String get authScreen10a2352b;

  /// No description provided for @authScreen4bcd0220.
  ///
  /// In he, this message translates to:
  /// **'דלג על שלב זה'**
  String get authScreen4bcd0220;

  /// No description provided for @authScreen220d2733.
  ///
  /// In he, this message translates to:
  /// **'פרטי הנכס'**
  String get authScreen220d2733;

  /// No description provided for @authScreen726d9a57.
  ///
  /// In he, this message translates to:
  /// **'אופציונלי'**
  String get authScreen726d9a57;

  /// No description provided for @authScreen68d09f20.
  ///
  /// In he, this message translates to:
  /// **'הגדר את מאפייני הדירה שלך כדי שנוכל לחבר אותך לשוכרים המתאימים ביותר.'**
  String get authScreen68d09f20;

  /// No description provided for @authScreenDc8aec13.
  ///
  /// In he, this message translates to:
  /// **'עיר / שכונה'**
  String get authScreenDc8aec13;

  /// No description provided for @authScreen012ba394.
  ///
  /// In he, this message translates to:
  /// **'מה יש בנכס?'**
  String get authScreen012ba394;

  /// No description provided for @authScreen4f4cd24f.
  ///
  /// In he, this message translates to:
  /// **'מספר חדרים'**
  String get authScreen4f4cd24f;

  /// No description provided for @authScreen06159b48.
  ///
  /// In he, this message translates to:
  /// **'מצאו את המקום\nהמושלם עבורכם'**
  String get authScreen06159b48;

  /// No description provided for @authScreenB4cc85ed.
  ///
  /// In he, this message translates to:
  /// **'מחפש דירה'**
  String get authScreenB4cc85ed;

  /// No description provided for @authScreen4afeb9ec.
  ///
  /// In he, this message translates to:
  /// **'מפרסם דירה'**
  String get authScreen4afeb9ec;

  /// No description provided for @authScreen559301ee.
  ///
  /// In he, this message translates to:
  /// **'או התחברו באמצעות'**
  String get authScreen559301ee;

  /// No description provided for @authScreen20ef8265.
  ///
  /// In he, this message translates to:
  /// **'כתובת האימייל כבר קיימת במערכת'**
  String get authScreen20ef8265;

  /// No description provided for @authScreen72765f55.
  ///
  /// In he, this message translates to:
  /// **'הסיסמה חלשה מדי'**
  String get authScreen72765f55;

  /// No description provided for @authScreenA2b3bad0.
  ///
  /// In he, this message translates to:
  /// **'כתובת אימייל לא תקינה'**
  String get authScreenA2b3bad0;

  /// No description provided for @authScreen7e95f8ea.
  ///
  /// In he, this message translates to:
  /// **'שגיאה ביצירת החשבון, נסה שוב'**
  String get authScreen7e95f8ea;

  /// No description provided for @discoverScreenE5a47f62.
  ///
  /// In he, this message translates to:
  /// **'לא הצלחתי להבין את החיפוש. נסו למשל: \"3 חדרים בתל אביב עד 6000\"'**
  String get discoverScreenE5a47f62;

  /// No description provided for @discoverScreenC5c195f6.
  ///
  /// In he, this message translates to:
  /// **'{describe}  ·  📍 {city} והסביבה הקרובה'**
  String discoverScreenC5c195f6(Object city, Object describe);

  /// No description provided for @discoverScreenC6efa96a.
  ///
  /// In he, this message translates to:
  /// **'{roomsLabel} חד׳'**
  String discoverScreenC6efa96a(Object roomsLabel);

  /// No description provided for @discoverScreen615d28b8.
  ///
  /// In he, this message translates to:
  /// **'{sizeM2} מ״ר'**
  String discoverScreen615d28b8(Object sizeM2);

  /// No description provided for @discoverScreenF1872f35.
  ///
  /// In he, this message translates to:
  /// **'חזור לפריט הקודם'**
  String get discoverScreenF1872f35;

  /// No description provided for @discoverScreenC4b9553a.
  ///
  /// In he, this message translates to:
  /// **'שוכר'**
  String get discoverScreenC4b9553a;

  /// No description provided for @discoverScreen8a84741d.
  ///
  /// In he, this message translates to:
  /// **'דירה להשכרה'**
  String get discoverScreen8a84741d;

  /// No description provided for @discoverScreen4b403e4b.
  ///
  /// In he, this message translates to:
  /// **'צעד אחד קטן לדירה החדשה שלך'**
  String get discoverScreen4b403e4b;

  /// No description provided for @discoverScreen1b24cc81.
  ///
  /// In he, this message translates to:
  /// **'נמצאה התאמה מושלמת לדירה ב{address}'**
  String discoverScreen1b24cc81(Object address);

  /// No description provided for @discoverScreenB2320205.
  ///
  /// In he, this message translates to:
  /// **'כתיבת הודעה למשכיר'**
  String get discoverScreenB2320205;

  /// No description provided for @discoverScreen4fb78a2e.
  ///
  /// In he, this message translates to:
  /// **'המשך לדפדף'**
  String get discoverScreen4fb78a2e;

  /// No description provided for @discoverScreen8542ba18.
  ///
  /// In he, this message translates to:
  /// **'חדש!'**
  String get discoverScreen8542ba18;

  /// No description provided for @discoverScreen59e95c52.
  ///
  /// In he, this message translates to:
  /// **'חפש דירה במילים שלך…'**
  String get discoverScreen59e95c52;

  /// No description provided for @discoverScreenE8b3a3d5.
  ///
  /// In he, this message translates to:
  /// **'נקה'**
  String get discoverScreenE8b3a3d5;

  /// No description provided for @discoverScreen55247199.
  ///
  /// In he, this message translates to:
  /// **'סגור'**
  String get discoverScreen55247199;

  /// No description provided for @discoverScreen31d3427c.
  ///
  /// In he, this message translates to:
  /// **'נסו: \"3 חדרים בצפון ת״א עד 6000\"'**
  String get discoverScreen31d3427c;

  /// No description provided for @discoverScreenB429a0f3.
  ///
  /// In he, this message translates to:
  /// **'עוד'**
  String get discoverScreenB429a0f3;

  /// No description provided for @discoverScreenA8e71c4c.
  ///
  /// In he, this message translates to:
  /// **'התראות'**
  String get discoverScreenA8e71c4c;

  /// No description provided for @discoverScreen86023c2b.
  ///
  /// In he, this message translates to:
  /// **'חיפושים שמורים'**
  String get discoverScreen86023c2b;

  /// No description provided for @discoverScreen2f416fd3.
  ///
  /// In he, this message translates to:
  /// **'הדירות ששמרתי'**
  String get discoverScreen2f416fd3;

  /// No description provided for @discoverScreen8f28a31a.
  ///
  /// In he, this message translates to:
  /// **'שמור חיפוש'**
  String get discoverScreen8f28a31a;

  /// No description provided for @discoverScreenF50251bc.
  ///
  /// In he, this message translates to:
  /// **'שמור'**
  String get discoverScreenF50251bc;

  /// No description provided for @discoverScreenA43e6e7d.
  ///
  /// In he, this message translates to:
  /// **'אין מחיר'**
  String get discoverScreenA43e6e7d;

  /// No description provided for @discoverScreen74b0b436.
  ///
  /// In he, this message translates to:
  /// **'{count} דירות · {price}'**
  String discoverScreen74b0b436(Object count, Object price);

  /// No description provided for @discoverScreen6c3c338f.
  ///
  /// In he, this message translates to:
  /// **'הכנס מספר'**
  String get discoverScreen6c3c338f;

  /// No description provided for @discoverScreenA7c55a8d.
  ///
  /// In he, this message translates to:
  /// **'ביטול'**
  String get discoverScreenA7c55a8d;

  /// No description provided for @discoverScreen7a683618.
  ///
  /// In he, this message translates to:
  /// **'מינימום'**
  String get discoverScreen7a683618;

  /// No description provided for @discoverScreen6dd38cc5.
  ///
  /// In he, this message translates to:
  /// **'מקסימום'**
  String get discoverScreen6dd38cc5;

  /// No description provided for @discoverScreenCe114a5b.
  ///
  /// In he, this message translates to:
  /// **'דירות ב{city}'**
  String discoverScreenCe114a5b(Object city);

  /// No description provided for @discoverScreenC7d46456.
  ///
  /// In he, this message translates to:
  /// **'החיפוש שלי'**
  String get discoverScreenC7d46456;

  /// No description provided for @discoverScreenEd1b4e42.
  ///
  /// In he, this message translates to:
  /// **'שמירת חיפוש'**
  String get discoverScreenEd1b4e42;

  /// No description provided for @discoverScreenE9b8eecc.
  ///
  /// In he, this message translates to:
  /// **'נשמור את הסינון הנוכחי ונודיע לך כשתעלה דירה חדשה שמתאימה.'**
  String get discoverScreenE9b8eecc;

  /// No description provided for @discoverScreen448f2c74.
  ///
  /// In he, this message translates to:
  /// **'שם לחיפוש'**
  String get discoverScreen448f2c74;

  /// No description provided for @discoverScreen58220e78.
  ///
  /// In he, this message translates to:
  /// **'החיפוש נשמר. נודיע לך על דירות חדשות שמתאימות 🔔'**
  String get discoverScreen58220e78;

  /// No description provided for @discoverScreenA597b860.
  ///
  /// In he, this message translates to:
  /// **'סינון ומיון'**
  String get discoverScreenA597b860;

  /// No description provided for @discoverScreen8aa21a4c.
  ///
  /// In he, this message translates to:
  /// **'מטרה'**
  String get discoverScreen8aa21a4c;

  /// No description provided for @discoverScreen5f8fb8a5.
  ///
  /// In he, this message translates to:
  /// **'הכל'**
  String get discoverScreen5f8fb8a5;

  /// No description provided for @discoverScreen60d47dc4.
  ///
  /// In he, this message translates to:
  /// **'שכירות'**
  String get discoverScreen60d47dc4;

  /// No description provided for @discoverScreen40eb4dca.
  ///
  /// In he, this message translates to:
  /// **'קנייה'**
  String get discoverScreen40eb4dca;

  /// No description provided for @discoverScreenC6c960c3.
  ///
  /// In he, this message translates to:
  /// **'טווח מחירים'**
  String get discoverScreenC6c960c3;

  /// No description provided for @discoverScreen09ae3918.
  ///
  /// In he, this message translates to:
  /// **'ללא הגבלה'**
  String get discoverScreen09ae3918;

  /// No description provided for @discoverScreenFe578531.
  ///
  /// In he, this message translates to:
  /// **'לכלול דירות בלי מחיר'**
  String get discoverScreenFe578531;

  /// No description provided for @discoverScreen25ade83a.
  ///
  /// In he, this message translates to:
  /// **'מחיר מתחת ל-600 ש\"ח נחשב כלא ידוע'**
  String get discoverScreen25ade83a;

  /// No description provided for @discoverScreenB50b3974.
  ///
  /// In he, this message translates to:
  /// **'חדרים'**
  String get discoverScreenB50b3974;

  /// No description provided for @discoverScreenC1779315.
  ///
  /// In he, this message translates to:
  /// **'מ-'**
  String get discoverScreenC1779315;

  /// No description provided for @discoverScreen344c1d0e.
  ///
  /// In he, this message translates to:
  /// **'עד'**
  String get discoverScreen344c1d0e;

  /// No description provided for @discoverScreen26d0e7de.
  ///
  /// In he, this message translates to:
  /// **'מיקום'**
  String get discoverScreen26d0e7de;

  /// No description provided for @discoverScreenE65e9ceb.
  ///
  /// In he, this message translates to:
  /// **'חפש עיר או אזור'**
  String get discoverScreenE65e9ceb;

  /// No description provided for @discoverScreen2c1f2bbd.
  ///
  /// In he, this message translates to:
  /// **'תל אביב'**
  String get discoverScreen2c1f2bbd;

  /// No description provided for @discoverScreen8e0dfe1e.
  ///
  /// In he, this message translates to:
  /// **'ירושלים'**
  String get discoverScreen8e0dfe1e;

  /// No description provided for @discoverScreenCa1cc213.
  ///
  /// In he, this message translates to:
  /// **'חיפה'**
  String get discoverScreenCa1cc213;

  /// No description provided for @discoverScreenEa980134.
  ///
  /// In he, this message translates to:
  /// **'גבעתיים'**
  String get discoverScreenEa980134;

  /// No description provided for @discoverScreen2231ce66.
  ///
  /// In he, this message translates to:
  /// **'רמת גן'**
  String get discoverScreen2231ce66;

  /// No description provided for @discoverScreen982e0598.
  ///
  /// In he, this message translates to:
  /// **'הרצליה'**
  String get discoverScreen982e0598;

  /// No description provided for @discoverScreen96a73cd7.
  ///
  /// In he, this message translates to:
  /// **'ראשון לציון'**
  String get discoverScreen96a73cd7;

  /// No description provided for @discoverScreen835a122a.
  ///
  /// In he, this message translates to:
  /// **'לא נמצאו ערים או אזורים מתאימים'**
  String get discoverScreen835a122a;

  /// No description provided for @discoverScreen1df7e5cb.
  ///
  /// In he, this message translates to:
  /// **'מיון'**
  String get discoverScreen1df7e5cb;

  /// No description provided for @discoverScreen0f95260b.
  ///
  /// In he, this message translates to:
  /// **'טווח גודל'**
  String get discoverScreen0f95260b;

  /// No description provided for @discoverScreen608912c9.
  ///
  /// In he, this message translates to:
  /// **'מ\"ר'**
  String get discoverScreen608912c9;

  /// No description provided for @discoverScreenC67e3688.
  ///
  /// In he, this message translates to:
  /// **'קומה מינימלית'**
  String get discoverScreenC67e3688;

  /// No description provided for @discoverScreenB42b537d.
  ///
  /// In he, this message translates to:
  /// **'קומה {minFloor}+'**
  String discoverScreenB42b537d(Object minFloor);

  /// No description provided for @discoverScreen7d93908e.
  ///
  /// In he, this message translates to:
  /// **'סוג נכס'**
  String get discoverScreen7d93908e;

  /// No description provided for @discoverScreen357b4923.
  ///
  /// In he, this message translates to:
  /// **'מצב הנכס'**
  String get discoverScreen357b4923;

  /// No description provided for @discoverScreen5aa1c77f.
  ///
  /// In he, this message translates to:
  /// **'מקור מודעה'**
  String get discoverScreen5aa1c77f;

  /// No description provided for @discoverScreenF7fab77d.
  ///
  /// In he, this message translates to:
  /// **'ללא בחירה: יוצגו גם פרטיות וגם מתיווך'**
  String get discoverScreenF7fab77d;

  /// No description provided for @discoverScreen1399cd87.
  ///
  /// In he, this message translates to:
  /// **'מועד כניסה'**
  String get discoverScreen1399cd87;

  /// No description provided for @discoverScreen14a99444.
  ///
  /// In he, this message translates to:
  /// **'ללא בחירה: כל מועדי הכניסה רלוונטיים'**
  String get discoverScreen14a99444;

  /// No description provided for @discoverScreen64680a66.
  ///
  /// In he, this message translates to:
  /// **'מאפיינים חשובים'**
  String get discoverScreen64680a66;

  /// No description provided for @discoverScreen485ce069.
  ///
  /// In he, this message translates to:
  /// **'מקומות בסביבה שחשובים לי'**
  String get discoverScreen485ce069;

  /// No description provided for @discoverScreen6ca5e778.
  ///
  /// In he, this message translates to:
  /// **'מה שתבחרו יופיע ראשון בעמוד הדירה וישפיע על הדירוג'**
  String get discoverScreen6ca5e778;

  /// No description provided for @discoverScreenEbbc108b.
  ///
  /// In he, this message translates to:
  /// **'נקה הכל'**
  String get discoverScreenEbbc108b;

  /// No description provided for @discoverScreen51d46fb2.
  ///
  /// In he, this message translates to:
  /// **'הצג {count} דירות'**
  String discoverScreen51d46fb2(Object count);

  /// No description provided for @discoverScreen0a12cf33.
  ///
  /// In he, this message translates to:
  /// **'מועדף'**
  String get discoverScreen0a12cf33;

  /// No description provided for @discoverScreen19662bd6.
  ///
  /// In he, this message translates to:
  /// **'חייב להיות'**
  String get discoverScreen19662bd6;

  /// No description provided for @discoverScreen4b54025b.
  ///
  /// In he, this message translates to:
  /// **'טאפ / דאבל טאפ'**
  String get discoverScreen4b54025b;

  /// No description provided for @discoverScreenE67a269a.
  ///
  /// In he, this message translates to:
  /// **'סוגי סינון'**
  String get discoverScreenE67a269a;

  /// No description provided for @discoverScreen3bb32ddd.
  ///
  /// In he, this message translates to:
  /// **'תקציב'**
  String get discoverScreen3bb32ddd;

  /// No description provided for @discoverScreenE08c750c.
  ///
  /// In he, this message translates to:
  /// **'מאפיינים'**
  String get discoverScreenE08c750c;

  /// No description provided for @discoverScreenE479e555.
  ///
  /// In he, this message translates to:
  /// **'הצג את כל המסננים'**
  String get discoverScreenE479e555;

  /// No description provided for @discoverScreen9ad9fd5e.
  ///
  /// In he, this message translates to:
  /// **'סנן לפי...'**
  String get discoverScreen9ad9fd5e;

  /// No description provided for @discoverScreen8853fa88.
  ///
  /// In he, this message translates to:
  /// **'סינון באזור {areaName}'**
  String discoverScreen8853fa88(Object areaName);

  /// No description provided for @discoverScreenE2349334.
  ///
  /// In he, this message translates to:
  /// **'דירות באזור המסומן'**
  String get discoverScreenE2349334;

  /// No description provided for @discoverScreenC2dc6194.
  ///
  /// In he, this message translates to:
  /// **'{count} תוצאות'**
  String discoverScreenC2dc6194(Object count);

  /// No description provided for @discoverScreen55e539c8.
  ///
  /// In he, this message translates to:
  /// **'שמור אזור'**
  String get discoverScreen55e539c8;

  /// No description provided for @discoverScreenB336259f.
  ///
  /// In he, this message translates to:
  /// **'להשכרה'**
  String get discoverScreenB336259f;

  /// No description provided for @discoverScreen609fac18.
  ///
  /// In he, this message translates to:
  /// **'למכירה'**
  String get discoverScreen609fac18;

  /// No description provided for @discoverScreenD886d07f.
  ///
  /// In he, this message translates to:
  /// **'{roomsLabel} חדרים'**
  String discoverScreenD886d07f(Object roomsLabel);

  /// No description provided for @discoverScreenFdb4eac7.
  ///
  /// In he, this message translates to:
  /// **'{sizeM2} מ״ר'**
  String discoverScreenFdb4eac7(Object sizeM2);

  /// No description provided for @discoverScreenCcc5c5a6.
  ///
  /// In he, this message translates to:
  /// **'קרקע'**
  String get discoverScreenCcc5c5a6;

  /// No description provided for @discoverScreenD068bb57.
  ///
  /// In he, this message translates to:
  /// **'קומה {floor}'**
  String discoverScreenD068bb57(Object floor);

  /// No description provided for @discoverScreenAac4e7a2.
  ///
  /// In he, this message translates to:
  /// **'בטל'**
  String get discoverScreenAac4e7a2;

  /// No description provided for @discoverScreenBed527df.
  ///
  /// In he, this message translates to:
  /// **'אופס! לא מצאנו דירות ב{city}'**
  String discoverScreenBed527df(Object city);

  /// No description provided for @discoverScreenAd918daa.
  ///
  /// In he, this message translates to:
  /// **'אופס! אין דירות שמתאימות'**
  String get discoverScreenAd918daa;

  /// No description provided for @discoverScreen0d8b5e54.
  ///
  /// In he, this message translates to:
  /// **'ראית את כל הדירות!'**
  String get discoverScreen0d8b5e54;

  /// No description provided for @discoverScreen2d250f3a.
  ///
  /// In he, this message translates to:
  /// **'לא נמצאו דירות זמינות לפי החיפוש הזה. אפשר להרחיב טווח, אזור או תקציב 👇'**
  String get discoverScreen2d250f3a;

  /// No description provided for @discoverScreen044d147e.
  ///
  /// In he, this message translates to:
  /// **'הרחב את החיפוש כדי למצוא עוד דירות'**
  String get discoverScreen044d147e;

  /// No description provided for @discoverScreen30fb9443.
  ///
  /// In he, this message translates to:
  /// **'הרחב תקציב ב-₪500'**
  String get discoverScreen30fb9443;

  /// No description provided for @discoverScreen76e4a755.
  ///
  /// In he, this message translates to:
  /// **'הפחת דרישת חדרים ב-0.5'**
  String get discoverScreen76e4a755;

  /// No description provided for @discoverScreen00256770.
  ///
  /// In he, this message translates to:
  /// **'פתח גודל מ-20 מ\"ר'**
  String get discoverScreen00256770;

  /// No description provided for @discoverScreenB80f7438.
  ///
  /// In he, this message translates to:
  /// **'אפס דירות שדילגתי'**
  String get discoverScreenB80f7438;

  /// No description provided for @discoverScreen8b3c043a.
  ///
  /// In he, this message translates to:
  /// **'התאמה חכמה'**
  String get discoverScreen8b3c043a;

  /// No description provided for @discoverScreen4b8d8771.
  ///
  /// In he, this message translates to:
  /// **'מחיר מהנמוך לגבוה'**
  String get discoverScreen4b8d8771;

  /// No description provided for @discoverScreen0126181a.
  ///
  /// In he, this message translates to:
  /// **'מחיר מהגבוה לנמוך'**
  String get discoverScreen0126181a;

  /// No description provided for @discoverScreenC2dd498c.
  ///
  /// In he, this message translates to:
  /// **'כניסה הכי קרובה'**
  String get discoverScreenC2dd498c;

  /// No description provided for @discoverScreen9613740e.
  ///
  /// In he, this message translates to:
  /// **'הכי מרווחות'**
  String get discoverScreen9613740e;

  /// No description provided for @discoverScreenAc35c5b6.
  ///
  /// In he, this message translates to:
  /// **'בעלים פרטיים'**
  String get discoverScreenAc35c5b6;

  /// No description provided for @discoverScreen88edd37e.
  ///
  /// In he, this message translates to:
  /// **'תיווך בלבד'**
  String get discoverScreen88edd37e;

  /// No description provided for @discoverScreenB2136c90.
  ///
  /// In he, this message translates to:
  /// **'עיר'**
  String get discoverScreenB2136c90;

  /// No description provided for @discoverScreen7c0e2040.
  ///
  /// In he, this message translates to:
  /// **'אזור'**
  String get discoverScreen7c0e2040;

  /// No description provided for @discoverScreenE190c982.
  ///
  /// In he, this message translates to:
  /// **'טווח מחיר'**
  String get discoverScreenE190c982;

  /// No description provided for @discoverScreen4ed4e191.
  ///
  /// In he, this message translates to:
  /// **'{minStr}+ מ\"ר'**
  String discoverScreen4ed4e191(Object minStr);

  /// No description provided for @discoverScreen6ba19199.
  ///
  /// In he, this message translates to:
  /// **'{minStr} - 2,000+ מ\"ר'**
  String discoverScreen6ba19199(Object minStr);

  /// No description provided for @discoverScreen9a6ba180.
  ///
  /// In he, this message translates to:
  /// **'{minStr} - {maxSizeM2} מ\"ר'**
  String discoverScreen9a6ba180(Object maxSizeM2, Object minStr);

  /// No description provided for @discoverScreen232628d0.
  ///
  /// In he, this message translates to:
  /// **'כל מועד'**
  String get discoverScreen232628d0;

  /// No description provided for @discoverScreenD02986c3.
  ///
  /// In he, this message translates to:
  /// **'מיידי'**
  String get discoverScreenD02986c3;

  /// No description provided for @discoverScreen402285bd.
  ///
  /// In he, this message translates to:
  /// **'עד 30 יום'**
  String get discoverScreen402285bd;

  /// No description provided for @discoverScreen23bb912d.
  ///
  /// In he, this message translates to:
  /// **'עד 90 יום'**
  String get discoverScreen23bb912d;

  /// No description provided for @discoverScreen5d2540f2.
  ///
  /// In he, this message translates to:
  /// **'חי'**
  String get discoverScreen5d2540f2;

  /// No description provided for @discoverScreenFcde3740.
  ///
  /// In he, this message translates to:
  /// **'בחירת תצוגת דירות'**
  String get discoverScreenFcde3740;

  /// No description provided for @discoverScreenEed2fbf3.
  ///
  /// In he, this message translates to:
  /// **'גלריה'**
  String get discoverScreenEed2fbf3;

  /// No description provided for @discoverScreen2d073fb0.
  ///
  /// In he, this message translates to:
  /// **'במיוחד בשבילך'**
  String get discoverScreen2d073fb0;

  /// No description provided for @discoverScreen876e3baa.
  ///
  /// In he, this message translates to:
  /// **'מפה'**
  String get discoverScreen876e3baa;

  /// No description provided for @discoverScreenFa8c72dc.
  ///
  /// In he, this message translates to:
  /// **'בתי ספר'**
  String get discoverScreenFa8c72dc;

  /// No description provided for @discoverScreenBabfce71.
  ///
  /// In he, this message translates to:
  /// **'גנים'**
  String get discoverScreenBabfce71;

  /// No description provided for @discoverScreen36bca392.
  ///
  /// In he, this message translates to:
  /// **'גני שעשועים'**
  String get discoverScreen36bca392;

  /// No description provided for @discoverScreen387c3b70.
  ///
  /// In he, this message translates to:
  /// **'פארקים'**
  String get discoverScreen387c3b70;

  /// No description provided for @discoverScreenD2d5595e.
  ///
  /// In he, this message translates to:
  /// **'סופרים'**
  String get discoverScreenD2d5595e;

  /// No description provided for @discoverScreen88915bc2.
  ///
  /// In he, this message translates to:
  /// **'קופות חולים'**
  String get discoverScreen88915bc2;

  /// No description provided for @discoverScreen82e78f66.
  ///
  /// In he, this message translates to:
  /// **'בתי מרקחת'**
  String get discoverScreen82e78f66;

  /// No description provided for @discoverScreenFeb803ce.
  ///
  /// In he, this message translates to:
  /// **'בתי חולים'**
  String get discoverScreenFeb803ce;

  /// No description provided for @discoverScreen91db7436.
  ///
  /// In he, this message translates to:
  /// **'תחבורה ציבורית'**
  String get discoverScreen91db7436;

  /// No description provided for @discoverScreen83339279.
  ///
  /// In he, this message translates to:
  /// **'חדרי כושר'**
  String get discoverScreen83339279;

  /// No description provided for @discoverScreenAa390576.
  ///
  /// In he, this message translates to:
  /// **'בריכות'**
  String get discoverScreenAa390576;

  /// No description provided for @discoverScreenB86d6f75.
  ///
  /// In he, this message translates to:
  /// **'מסעדות ובתי קפה'**
  String get discoverScreenB86d6f75;

  /// No description provided for @discoverScreenCc34e5d3.
  ///
  /// In he, this message translates to:
  /// **'בילוי'**
  String get discoverScreenCc34e5d3;

  /// No description provided for @discoverScreen6432de42.
  ///
  /// In he, this message translates to:
  /// **'תרבות'**
  String get discoverScreen6432de42;

  /// No description provided for @discoverScreenF93de50d.
  ///
  /// In he, this message translates to:
  /// **'בתי כנסת'**
  String get discoverScreenF93de50d;

  /// No description provided for @discoverScreen56619b6e.
  ///
  /// In he, this message translates to:
  /// **'גינות כלבים'**
  String get discoverScreen56619b6e;

  /// No description provided for @discoverScreen49d8274a.
  ///
  /// In he, this message translates to:
  /// **'חללי עבודה'**
  String get discoverScreen49d8274a;

  /// No description provided for @discoverScreenA6b678a2.
  ///
  /// In he, this message translates to:
  /// **'חניונים'**
  String get discoverScreenA6b678a2;

  /// No description provided for @exploreScreen041446d3.
  ///
  /// In he, this message translates to:
  /// **'מועמד/ת'**
  String get exploreScreen041446d3;

  /// No description provided for @exploreScreenEb3c6f60.
  ///
  /// In he, this message translates to:
  /// **'מועמדים'**
  String get exploreScreenEb3c6f60;

  /// No description provided for @exploreScreenA4ce69e7.
  ///
  /// In he, this message translates to:
  /// **'פרטים'**
  String get exploreScreenA4ce69e7;

  /// No description provided for @exploreScreen81a45c4e.
  ///
  /// In he, this message translates to:
  /// **'פרטי המועמד'**
  String get exploreScreen81a45c4e;

  /// No description provided for @exploreScreenE702c2a5.
  ///
  /// In he, this message translates to:
  /// **'אשר מועמד'**
  String get exploreScreenE702c2a5;

  /// No description provided for @exploreScreen80a413c5.
  ///
  /// In he, this message translates to:
  /// **'דלג'**
  String get exploreScreen80a413c5;

  /// No description provided for @exploreScreenCaab7e07.
  ///
  /// In he, this message translates to:
  /// **'מתעניין פעיל'**
  String get exploreScreenCaab7e07;

  /// No description provided for @exploreScreen861f28cc.
  ///
  /// In he, this message translates to:
  /// **'בודק אופציות'**
  String get exploreScreen861f28cc;

  /// No description provided for @exploreScreen9592be20.
  ///
  /// In he, this message translates to:
  /// **'צופה בלבד'**
  String get exploreScreen9592be20;

  /// No description provided for @exploreScreen4189b321.
  ///
  /// In he, this message translates to:
  /// **'התעניינות'**
  String get exploreScreen4189b321;

  /// No description provided for @exploreScreen3bb32ddd.
  ///
  /// In he, this message translates to:
  /// **'תקציב'**
  String get exploreScreen3bb32ddd;

  /// No description provided for @exploreScreenB50b3974.
  ///
  /// In he, this message translates to:
  /// **'חדרים'**
  String get exploreScreenB50b3974;

  /// No description provided for @exploreScreenF8eba562.
  ///
  /// In he, this message translates to:
  /// **'{r} חדרים'**
  String exploreScreenF8eba562(Object r);

  /// No description provided for @exploreScreen2f6783cd.
  ///
  /// In he, this message translates to:
  /// **'כניסה'**
  String get exploreScreen2f6783cd;

  /// No description provided for @exploreScreen6b84e37c.
  ///
  /// In he, this message translates to:
  /// **'תעסוקה'**
  String get exploreScreen6b84e37c;

  /// No description provided for @exploreScreenC60ce521.
  ///
  /// In he, this message translates to:
  /// **'{children} ילדים'**
  String exploreScreenC60ce521(Object children);

  /// No description provided for @exploreScreen10f698cd.
  ///
  /// In he, this message translates to:
  /// **'משק בית'**
  String get exploreScreen10f698cd;

  /// No description provided for @exploreScreen07bf27d4.
  ///
  /// In he, this message translates to:
  /// **'הכנסה'**
  String get exploreScreen07bf27d4;

  /// No description provided for @exploreScreen7f1643b2.
  ///
  /// In he, this message translates to:
  /// **'רכב'**
  String get exploreScreen7f1643b2;

  /// No description provided for @exploreScreenAeee4760.
  ///
  /// In he, this message translates to:
  /// **'חיית מחמד'**
  String get exploreScreenAeee4760;

  /// No description provided for @exploreScreenEcddc928.
  ///
  /// In he, this message translates to:
  /// **'עבודה מהבית'**
  String get exploreScreenEcddc928;

  /// No description provided for @exploreScreen7778a202.
  ///
  /// In he, this message translates to:
  /// **'אורח חיים'**
  String get exploreScreen7778a202;

  /// No description provided for @exploreScreenFccc9519.
  ///
  /// In he, this message translates to:
  /// **'♥ מאשר'**
  String get exploreScreenFccc9519;

  /// No description provided for @exploreScreen0d79bffc.
  ///
  /// In he, this message translates to:
  /// **'דוחה'**
  String get exploreScreen0d79bffc;

  /// No description provided for @exploreScreen046a972e.
  ///
  /// In he, this message translates to:
  /// **'התעניין/ה ב: {address}'**
  String exploreScreen046a972e(Object address);

  /// No description provided for @exploreScreen76b35661.
  ///
  /// In he, this message translates to:
  /// **'התאמה גבוהה'**
  String get exploreScreen76b35661;

  /// No description provided for @exploreScreen6c2b3afd.
  ///
  /// In he, this message translates to:
  /// **'+{count} מתעניינים'**
  String exploreScreen6c2b3afd(Object count);

  /// No description provided for @exploreScreen7de9ac58.
  ///
  /// In he, this message translates to:
  /// **'מאומת'**
  String get exploreScreen7de9ac58;

  /// No description provided for @exploreScreenA261278d.
  ///
  /// In he, this message translates to:
  /// **'אין מועמדים חדשים'**
  String get exploreScreenA261278d;

  /// No description provided for @exploreScreen4d90eb93.
  ///
  /// In he, this message translates to:
  /// **'כאשר שוכרים יאהבו את הנכסים שלך הם יופיעו כאן לאישור.'**
  String get exploreScreen4d90eb93;

  /// No description provided for @exploreScreen05ec83de.
  ///
  /// In he, this message translates to:
  /// **'הוסף נכס ראשון — שוכרים שיאהבו אותו יופיעו כאן.'**
  String get exploreScreen05ec83de;

  /// No description provided for @exploreScreen9bcc24df.
  ///
  /// In he, this message translates to:
  /// **'הוסף נכס עכשיו'**
  String get exploreScreen9bcc24df;

  /// No description provided for @exploreScreen567d5a67.
  ///
  /// In he, this message translates to:
  /// **'עבור לשיחות'**
  String get exploreScreen567d5a67;

  /// No description provided for @exploreScreenEde0a5bb.
  ///
  /// In he, this message translates to:
  /// **'סנן העדפות מועמדים'**
  String get exploreScreenEde0a5bb;

  /// No description provided for @exploreScreenB803dad3.
  ///
  /// In he, this message translates to:
  /// **'אישור אוטומטי'**
  String get exploreScreenB803dad3;

  /// No description provided for @exploreScreenE335275c.
  ///
  /// In he, this message translates to:
  /// **'אין מועמדים שתואמים למסננים'**
  String get exploreScreenE335275c;

  /// No description provided for @exploreScreen86ad2dd3.
  ///
  /// In he, this message translates to:
  /// **'נסה להרחיב את המסננים כדי לראות עוד מתעניינים.'**
  String get exploreScreen86ad2dd3;

  /// No description provided for @exploreScreen9c08b083.
  ///
  /// In he, this message translates to:
  /// **'נקה מסננים'**
  String get exploreScreen9c08b083;

  /// No description provided for @exploreScreenEbbc108b.
  ///
  /// In he, this message translates to:
  /// **'נקה הכל'**
  String get exploreScreenEbbc108b;

  /// No description provided for @exploreScreen8f43e338.
  ///
  /// In he, this message translates to:
  /// **'רמת התאמה'**
  String get exploreScreen8f43e338;

  /// No description provided for @exploreScreenDaf1cf49.
  ///
  /// In he, this message translates to:
  /// **'כל רמות ההתאמה'**
  String get exploreScreenDaf1cf49;

  /// No description provided for @exploreScreen4094ac8d.
  ///
  /// In he, this message translates to:
  /// **'תקציב חודשי'**
  String get exploreScreen4094ac8d;

  /// No description provided for @exploreScreenBe539fd6.
  ///
  /// In he, this message translates to:
  /// **'כל התקציבים'**
  String get exploreScreenBe539fd6;

  /// No description provided for @exploreScreenE5aeca16.
  ///
  /// In he, this message translates to:
  /// **'גיל'**
  String get exploreScreenE5aeca16;

  /// No description provided for @exploreScreenE5e69fd1.
  ///
  /// In he, this message translates to:
  /// **'כל הגילאים'**
  String get exploreScreenE5e69fd1;

  /// No description provided for @exploreScreen5c2ad42a.
  ///
  /// In he, this message translates to:
  /// **'מספר חדרים (מינימום)'**
  String get exploreScreen5c2ad42a;

  /// No description provided for @exploreScreenD308ff19.
  ///
  /// In he, this message translates to:
  /// **'שלב חיים'**
  String get exploreScreenD308ff19;

  /// No description provided for @exploreScreenFe95da03.
  ///
  /// In he, this message translates to:
  /// **'עדכניות'**
  String get exploreScreenFe95da03;

  /// No description provided for @exploreScreen4b4fd824.
  ///
  /// In he, this message translates to:
  /// **'רק לייקים מהשבוע האחרון'**
  String get exploreScreen4b4fd824;

  /// No description provided for @exploreScreen959e2dfc.
  ///
  /// In he, this message translates to:
  /// **'הכנסה חודשית מינימלית'**
  String get exploreScreen959e2dfc;

  /// No description provided for @exploreScreen07d495e1.
  ///
  /// In he, this message translates to:
  /// **'ללא סינון לפי הכנסה'**
  String get exploreScreen07d495e1;

  /// No description provided for @exploreScreenB0e336c6.
  ///
  /// In he, this message translates to:
  /// **'מספר ילדים (עד)'**
  String get exploreScreenB0e336c6;

  /// No description provided for @exploreScreen09ae3918.
  ///
  /// In he, this message translates to:
  /// **'ללא הגבלה'**
  String get exploreScreen09ae3918;

  /// No description provided for @exploreScreen8af90dc4.
  ///
  /// In he, this message translates to:
  /// **'עד {value}'**
  String exploreScreen8af90dc4(Object value);

  /// No description provided for @exploreScreen61dc5b0a.
  ///
  /// In he, this message translates to:
  /// **'מועד כניסה לנכס'**
  String get exploreScreen61dc5b0a;

  /// No description provided for @exploreScreen15039c05.
  ///
  /// In he, this message translates to:
  /// **'תחום עיסוק'**
  String get exploreScreen15039c05;

  /// No description provided for @exploreScreen2b9fb355.
  ///
  /// In he, this message translates to:
  /// **'סוג משק בית'**
  String get exploreScreen2b9fb355;

  /// No description provided for @exploreScreenE70cb0b4.
  ///
  /// In he, this message translates to:
  /// **'ללא חיית מחמד'**
  String get exploreScreenE70cb0b4;

  /// No description provided for @exploreScreen7decda58.
  ///
  /// In he, this message translates to:
  /// **'בעל/ת רכב'**
  String get exploreScreen7decda58;

  /// No description provided for @exploreScreen81d92174.
  ///
  /// In he, this message translates to:
  /// **'שמירת מסורת'**
  String get exploreScreen81d92174;

  /// No description provided for @exploreScreen8ac14f86.
  ///
  /// In he, this message translates to:
  /// **'שומר/ת שבת'**
  String get exploreScreen8ac14f86;

  /// No description provided for @exploreScreen30524972.
  ///
  /// In he, this message translates to:
  /// **'שומר/ת כשרות'**
  String get exploreScreen30524972;

  /// No description provided for @exploreScreen00549c82.
  ///
  /// In he, this message translates to:
  /// **'חיות מחמד'**
  String get exploreScreen00549c82;

  /// No description provided for @exploreScreenD2ab88e9.
  ///
  /// In he, this message translates to:
  /// **'רעש ושקט'**
  String get exploreScreenD2ab88e9;

  /// No description provided for @exploreScreenB9558dae.
  ///
  /// In he, this message translates to:
  /// **'לא מארח/ת הרבה'**
  String get exploreScreenB9558dae;

  /// No description provided for @exploreScreen73940096.
  ///
  /// In he, this message translates to:
  /// **'ללא כלי נגינה'**
  String get exploreScreen73940096;

  /// No description provided for @exploreScreen01759509.
  ///
  /// In he, this message translates to:
  /// **'יחס הכנסה/שכ\"ד'**
  String get exploreScreen01759509;

  /// No description provided for @exploreScreen7e55dfd4.
  ///
  /// In he, this message translates to:
  /// **'×{ratio} ומעלה'**
  String exploreScreen7e55dfd4(Object ratio);

  /// No description provided for @exploreScreen5f3306da.
  ///
  /// In he, this message translates to:
  /// **'עולה חדש'**
  String get exploreScreen5f3306da;

  /// No description provided for @exploreScreenCe24a1b8.
  ///
  /// In he, this message translates to:
  /// **'עולה חדש בלבד'**
  String get exploreScreenCe24a1b8;

  /// No description provided for @exploreScreenC48f4680.
  ///
  /// In he, this message translates to:
  /// **'מרחק ממקום העבודה'**
  String get exploreScreenC48f4680;

  /// No description provided for @exploreScreen9b92340a.
  ///
  /// In he, this message translates to:
  /// **'עד {km} ק\"מ'**
  String exploreScreen9b92340a(Object km);

  /// No description provided for @exploreScreen2a6f2e2a.
  ///
  /// In he, this message translates to:
  /// **'עישון'**
  String get exploreScreen2a6f2e2a;

  /// No description provided for @exploreScreen5ad0c26b.
  ///
  /// In he, this message translates to:
  /// **'לא מעשן בלבד'**
  String get exploreScreen5ad0c26b;

  /// No description provided for @exploreScreenA5928b66.
  ///
  /// In he, this message translates to:
  /// **'ערבות'**
  String get exploreScreenA5928b66;

  /// No description provided for @exploreScreenD7297c85.
  ///
  /// In he, this message translates to:
  /// **'עם ערב'**
  String get exploreScreenD7297c85;

  /// No description provided for @exploreScreen9d40aa19.
  ///
  /// In he, this message translates to:
  /// **'משך שכירות מבוקש'**
  String get exploreScreen9d40aa19;

  /// No description provided for @exploreScreenAb462e4c.
  ///
  /// In he, this message translates to:
  /// **'{months}+ חודשים'**
  String exploreScreenAb462e4c(Object months);

  /// No description provided for @exploreScreenAfe8dc6a.
  ///
  /// In he, this message translates to:
  /// **'אסמכתאות הכנסה'**
  String get exploreScreenAfe8dc6a;

  /// No description provided for @exploreScreenA60a4948.
  ///
  /// In he, this message translates to:
  /// **'אסמכתאות הכנסה מוכנות'**
  String get exploreScreenA60a4948;

  /// No description provided for @exploreScreen45e673e6.
  ///
  /// In he, this message translates to:
  /// **'אימות פרופיל'**
  String get exploreScreen45e673e6;

  /// No description provided for @exploreScreenD6dcc370.
  ///
  /// In he, this message translates to:
  /// **'מאומת בלבד'**
  String get exploreScreenD6dcc370;

  /// No description provided for @exploreScreen5c514c37.
  ///
  /// In he, this message translates to:
  /// **'החל מסננים'**
  String get exploreScreen5c514c37;

  /// No description provided for @exploreScreen40d56dee.
  ///
  /// In he, this message translates to:
  /// **'הייטק'**
  String get exploreScreen40d56dee;

  /// No description provided for @exploreScreen6dfb51f1.
  ///
  /// In he, this message translates to:
  /// **'בריאות/רפואה'**
  String get exploreScreen6dfb51f1;

  /// No description provided for @exploreScreen19981c32.
  ///
  /// In he, this message translates to:
  /// **'חינוך/הוראה'**
  String get exploreScreen19981c32;

  /// No description provided for @exploreScreenEbfcd4cb.
  ///
  /// In he, this message translates to:
  /// **'פיננסים/בנקאות'**
  String get exploreScreenEbfcd4cb;

  /// No description provided for @exploreScreen4f8aded7.
  ///
  /// In he, this message translates to:
  /// **'משפטים'**
  String get exploreScreen4f8aded7;

  /// No description provided for @exploreScreen453fe1ed.
  ///
  /// In he, this message translates to:
  /// **'הנדסה'**
  String get exploreScreen453fe1ed;

  /// No description provided for @exploreScreenE1cad55a.
  ///
  /// In he, this message translates to:
  /// **'עצמאי/ת'**
  String get exploreScreenE1cad55a;

  /// No description provided for @exploreScreenCb481f30.
  ///
  /// In he, this message translates to:
  /// **'שירות ציבורי'**
  String get exploreScreenCb481f30;

  /// No description provided for @exploreScreen2834587d.
  ///
  /// In he, this message translates to:
  /// **'מסחר/שירות'**
  String get exploreScreen2834587d;

  /// No description provided for @exploreScreen2157ec10.
  ///
  /// In he, this message translates to:
  /// **'אקדמיה'**
  String get exploreScreen2157ec10;

  /// No description provided for @exploreScreen42ed7e8d.
  ///
  /// In he, this message translates to:
  /// **'סטודנט/ית'**
  String get exploreScreen42ed7e8d;

  /// No description provided for @exploreScreenCdf4bce0.
  ///
  /// In he, this message translates to:
  /// **'אחר'**
  String get exploreScreenCdf4bce0;

  /// No description provided for @exploreScreen926c043f.
  ///
  /// In he, this message translates to:
  /// **'משפחה'**
  String get exploreScreen926c043f;

  /// No description provided for @exploreScreenB8d9266b.
  ///
  /// In he, this message translates to:
  /// **'רווק/ה'**
  String get exploreScreenB8d9266b;

  /// No description provided for @exploreScreen4df994d0.
  ///
  /// In he, this message translates to:
  /// **'זוג'**
  String get exploreScreen4df994d0;

  /// No description provided for @messageScreenFd0ec7ac.
  ///
  /// In he, this message translates to:
  /// **'השוכר'**
  String get messageScreenFd0ec7ac;

  /// No description provided for @messageScreenF41cdb94.
  ///
  /// In he, this message translates to:
  /// **'הודעה ארוכה מדי (מקסימום {maxLen} תווים)'**
  String messageScreenF41cdb94(Object maxLen);

  /// No description provided for @messageScreenF7c12aab.
  ///
  /// In he, this message translates to:
  /// **'שלחת יותר מדי הודעות. המתן רגע.'**
  String get messageScreenF7c12aab;

  /// No description provided for @messageScreen89cca91f.
  ///
  /// In he, this message translates to:
  /// **'ההודעה מכילה תוכן לא הולם ולכן לא נשלחה.'**
  String get messageScreen89cca91f;

  /// No description provided for @messageScreenEfc93a8e.
  ///
  /// In he, this message translates to:
  /// **'לא ניתן לגשת לגלריה'**
  String get messageScreenEfc93a8e;

  /// No description provided for @messageScreenE779f1ba.
  ///
  /// In he, this message translates to:
  /// **'לא ניתן לפתוח את המצלמה'**
  String get messageScreenE779f1ba;

  /// No description provided for @messageScreen210fc1ff.
  ///
  /// In he, this message translates to:
  /// **'יש להתחבר לחשבון כדי לשלוח {noun}'**
  String messageScreen210fc1ff(Object noun);

  /// No description provided for @messageScreen96aac67d.
  ///
  /// In he, this message translates to:
  /// **'אין חיבור לרשת. נסו שוב.'**
  String get messageScreen96aac67d;

  /// No description provided for @messageScreen439e8c64.
  ///
  /// In he, this message translates to:
  /// **'העלאת ה{noun} נכשלה. נסו שוב.'**
  String messageScreen439e8c64(Object noun);

  /// No description provided for @messageScreenAda826e5.
  ///
  /// In he, this message translates to:
  /// **'תמונה'**
  String get messageScreenAda826e5;

  /// No description provided for @messageScreenC6e4a13e.
  ///
  /// In he, this message translates to:
  /// **'נדרשת הרשאת מיקרופון'**
  String get messageScreenC6e4a13e;

  /// No description provided for @messageScreenDfe417f8.
  ///
  /// In he, this message translates to:
  /// **'לא ניתן להתחיל הקלטה'**
  String get messageScreenDfe417f8;

  /// No description provided for @messageScreenEac28ea1.
  ///
  /// In he, this message translates to:
  /// **'ההקלטה קצרה מדי'**
  String get messageScreenEac28ea1;

  /// No description provided for @messageScreen27be9d06.
  ///
  /// In he, this message translates to:
  /// **'הקלטה'**
  String get messageScreen27be9d06;

  /// No description provided for @messageScreenB3f49023.
  ///
  /// In he, this message translates to:
  /// **'שליחת ההקלטה נכשלה'**
  String get messageScreenB3f49023;

  /// No description provided for @messageScreen2461f753.
  ///
  /// In he, this message translates to:
  /// **'חסום משתמש'**
  String get messageScreen2461f753;

  /// No description provided for @messageScreen006255cf.
  ///
  /// In he, this message translates to:
  /// **'האם לחסום את \"{ownerName}\"?\n\nכל המודעות שלהם יוסרו מהפיד שלך מיידית. הדיווח יועבר לצוות Rently.'**
  String messageScreen006255cf(Object ownerName);

  /// No description provided for @messageScreenA7c55a8d.
  ///
  /// In he, this message translates to:
  /// **'ביטול'**
  String get messageScreenA7c55a8d;

  /// No description provided for @messageScreen1257849a.
  ///
  /// In he, this message translates to:
  /// **'חסום'**
  String get messageScreen1257849a;

  /// No description provided for @messageScreen6f321fdb.
  ///
  /// In he, this message translates to:
  /// **'לשלוח חוזה?'**
  String get messageScreen6f321fdb;

  /// No description provided for @messageScreen23895061.
  ///
  /// In he, this message translates to:
  /// **'האם אתה בטוח שאתה רוצה לשלוח חוזה לצד השני?'**
  String get messageScreen23895061;

  /// No description provided for @messageScreen3529112c.
  ///
  /// In he, this message translates to:
  /// **'ממתין שבעל הדירה ישלח חוזה לחתימה'**
  String get messageScreen3529112c;

  /// No description provided for @messageScreen16a8f330.
  ///
  /// In he, this message translates to:
  /// **'החוזה לא נמצא. נסו לרענן את הצ׳אט.'**
  String get messageScreen16a8f330;

  /// No description provided for @messageScreenB94a0f72.
  ///
  /// In he, this message translates to:
  /// **'צפייה בדירה בעוד שעה'**
  String get messageScreenB94a0f72;

  /// No description provided for @messageScreen011b615a.
  ///
  /// In he, this message translates to:
  /// **'צפייה ב{address} בשעה {time}'**
  String messageScreen011b615a(Object address, Object time);

  /// No description provided for @messageScreenE41cd6f3.
  ///
  /// In he, this message translates to:
  /// **'הצפייה אושרה — נשלחה הודעה ונקבעה תזכורת'**
  String get messageScreenE41cd6f3;

  /// No description provided for @messageScreen6fe74d6a.
  ///
  /// In he, this message translates to:
  /// **'מועמד/ת להשכרה'**
  String get messageScreen6fe74d6a;

  /// No description provided for @messageScreenC6c7d5f7.
  ///
  /// In he, this message translates to:
  /// **'בעל הדירה'**
  String get messageScreenC6c7d5f7;

  /// No description provided for @messageScreenCf639c9f.
  ///
  /// In he, this message translates to:
  /// **'מועמד/ת · {city}'**
  String messageScreenCf639c9f(Object city);

  /// No description provided for @messageScreenE374171b.
  ///
  /// In he, this message translates to:
  /// **'בעל הדירה · {city}'**
  String messageScreenE374171b(Object city);

  /// No description provided for @messageScreen64d404c8.
  ///
  /// In he, this message translates to:
  /// **'ההתאמה לא נמצאה'**
  String get messageScreen64d404c8;

  /// No description provided for @messageScreen6f11e9ea.
  ///
  /// In he, this message translates to:
  /// **'הנכס לא נמצא'**
  String get messageScreen6f11e9ea;

  /// No description provided for @messageScreen686a53ea.
  ///
  /// In he, this message translates to:
  /// **'טוען הודעות...'**
  String get messageScreen686a53ea;

  /// No description provided for @messageScreen932b91b9.
  ///
  /// In he, this message translates to:
  /// **'החוזה נחתם על-ידי שני הצדדים ✓'**
  String get messageScreen932b91b9;

  /// No description provided for @messageScreen9ad15d69.
  ///
  /// In he, this message translates to:
  /// **'השוכר/ת'**
  String get messageScreen9ad15d69;

  /// No description provided for @messageScreen8f2415a0.
  ///
  /// In he, this message translates to:
  /// **'{other} חתם/ה · ממתין לחתימתך'**
  String messageScreen8f2415a0(Object other);

  /// No description provided for @messageScreen52607a5e.
  ///
  /// In he, this message translates to:
  /// **'ממתין לחתימתך'**
  String get messageScreen52607a5e;

  /// No description provided for @messageScreenB4cd149c.
  ///
  /// In he, this message translates to:
  /// **'חתמת · ממתין לחתימת {other}'**
  String messageScreenB4cd149c(Object other);

  /// No description provided for @messageScreen132c5cba.
  ///
  /// In he, this message translates to:
  /// **'חתום'**
  String get messageScreen132c5cba;

  /// No description provided for @messageScreen193535e0.
  ///
  /// In he, this message translates to:
  /// **'הצג'**
  String get messageScreen193535e0;

  /// No description provided for @messageScreen9767b9b6.
  ///
  /// In he, this message translates to:
  /// **'חתימת בעלים'**
  String get messageScreen9767b9b6;

  /// No description provided for @messageScreen55859a69.
  ///
  /// In he, this message translates to:
  /// **'זמין אחרי שליחת חוזה'**
  String get messageScreen55859a69;

  /// No description provided for @messageScreen3108cb11.
  ///
  /// In he, this message translates to:
  /// **'הושלם ✓'**
  String get messageScreen3108cb11;

  /// No description provided for @messageScreen5c64f9aa.
  ///
  /// In he, this message translates to:
  /// **'חתום על החוזה'**
  String get messageScreen5c64f9aa;

  /// No description provided for @messageScreen92432ae3.
  ///
  /// In he, this message translates to:
  /// **'חתימת שוכר'**
  String get messageScreen92432ae3;

  /// No description provided for @messageScreen8f1b5e04.
  ///
  /// In he, this message translates to:
  /// **'אשר חתימת שוכר'**
  String get messageScreen8f1b5e04;

  /// No description provided for @messageScreenEc10129a.
  ///
  /// In he, this message translates to:
  /// **'פעולות שיחה'**
  String get messageScreenEc10129a;

  /// No description provided for @messageScreen06c776cc.
  ///
  /// In he, this message translates to:
  /// **'הודעה מהירה'**
  String get messageScreen06c776cc;

  /// No description provided for @messageScreen9c5e5f89.
  ///
  /// In he, this message translates to:
  /// **'קובץ'**
  String get messageScreen9c5e5f89;

  /// No description provided for @messageScreen4a140235.
  ///
  /// In he, this message translates to:
  /// **'מדיה'**
  String get messageScreen4a140235;

  /// No description provided for @messageScreen90b9bf3d.
  ///
  /// In he, this message translates to:
  /// **'חסום משתמש זה'**
  String get messageScreen90b9bf3d;

  /// No description provided for @messageScreen981ea924.
  ///
  /// In he, this message translates to:
  /// **'הסר את \"{ownerName}\" מהפיד שלך'**
  String messageScreen981ea924(Object ownerName);

  /// No description provided for @messageScreenB4610ada.
  ///
  /// In he, this message translates to:
  /// **'הסר משתמש זה מהפיד שלך'**
  String get messageScreenB4610ada;

  /// No description provided for @messageScreenDdc93140.
  ///
  /// In he, this message translates to:
  /// **'שליחת חוזה'**
  String get messageScreenDdc93140;

  /// No description provided for @messageScreen98f8e516.
  ///
  /// In he, this message translates to:
  /// **'החוזה כבר נשלח לצד השני'**
  String get messageScreen98f8e516;

  /// No description provided for @messageScreen848015c2.
  ///
  /// In he, this message translates to:
  /// **'שלח טיוטת חוזה לחתימה דיגיטלית'**
  String get messageScreen848015c2;

  /// No description provided for @messageScreen14cb9c39.
  ///
  /// In he, this message translates to:
  /// **'הצ׳אט מוכן'**
  String get messageScreen14cb9c39;

  /// No description provided for @messageScreen4726b342.
  ///
  /// In he, this message translates to:
  /// **'שלח הודעה כדי להתחיל את השיחה.'**
  String get messageScreen4726b342;

  /// No description provided for @messageScreen9e6a373e.
  ///
  /// In he, this message translates to:
  /// **'לא נשלח'**
  String get messageScreen9e6a373e;

  /// No description provided for @messageScreenB6557f57.
  ///
  /// In he, this message translates to:
  /// **'בטל · שלח'**
  String get messageScreenB6557f57;

  /// No description provided for @messageScreen562b0c99.
  ///
  /// In he, this message translates to:
  /// **'כתיבת הודעה...'**
  String get messageScreen562b0c99;

  /// No description provided for @messageScreen1a1c4d24.
  ///
  /// In he, this message translates to:
  /// **'פתיחה'**
  String get messageScreen1a1c4d24;

  /// No description provided for @messageScreen2925dba0.
  ///
  /// In he, this message translates to:
  /// **'הודעת ברכה'**
  String get messageScreen2925dba0;

  /// No description provided for @messageScreen6567b014.
  ///
  /// In he, this message translates to:
  /// **'שלום! קיבלתי את הבקשה שלך. אשמח לענות על שאלות ולתאם ביקור. מתי נוח לך?'**
  String get messageScreen6567b014;

  /// No description provided for @messageScreen21f42c17.
  ///
  /// In he, this message translates to:
  /// **'אישור עניין'**
  String get messageScreen21f42c17;

  /// No description provided for @messageScreen390e6607.
  ///
  /// In he, this message translates to:
  /// **'תודה על ההתעניינות! הדירה עדיין פנויה. אשמח לתאם ביקור בשבוע הקרוב.'**
  String get messageScreen390e6607;

  /// No description provided for @messageScreen9906bdda.
  ///
  /// In he, this message translates to:
  /// **'ביקור'**
  String get messageScreen9906bdda;

  /// No description provided for @messageScreenB691bc6c.
  ///
  /// In he, this message translates to:
  /// **'תיאום ביקור'**
  String get messageScreenB691bc6c;

  /// No description provided for @messageScreenB3c76e4e.
  ///
  /// In he, this message translates to:
  /// **'אני זמין לביקור ביום __ בשעה __. האם מתאים לך?'**
  String get messageScreenB3c76e4e;

  /// No description provided for @messageScreen9bcbf905.
  ///
  /// In he, this message translates to:
  /// **'אישור ביקור'**
  String get messageScreen9bcbf905;

  /// No description provided for @messageScreen3c4a7e97.
  ///
  /// In he, this message translates to:
  /// **'מעולה! מאשר ביקור ביום __ בשעה __. הכתובת: ___.'**
  String get messageScreen3c4a7e97;

  /// No description provided for @messageScreenF91ded23.
  ///
  /// In he, this message translates to:
  /// **'חוזה'**
  String get messageScreenF91ded23;

  /// No description provided for @messageScreen8ee0ca6b.
  ///
  /// In he, this message translates to:
  /// **'שלחתי את טיוטת החוזה. אנא קרא ותחזור אליי עם הערות.'**
  String get messageScreen8ee0ca6b;

  /// No description provided for @messageScreenFcfb868b.
  ///
  /// In he, this message translates to:
  /// **'בקשה לחתימה'**
  String get messageScreenFcfb868b;

  /// No description provided for @messageScreen293a8ea3.
  ///
  /// In he, this message translates to:
  /// **'הכל מסודר מצידי — אנא חתום על החוזה כדי לסיים את התהליך.'**
  String get messageScreen293a8ea3;

  /// No description provided for @messageScreenF600808f.
  ///
  /// In he, this message translates to:
  /// **'סיום'**
  String get messageScreenF600808f;

  /// No description provided for @messageScreen74cdff02.
  ///
  /// In he, this message translates to:
  /// **'דחייה עדינה'**
  String get messageScreen74cdff02;

  /// No description provided for @messageScreenA6b75beb.
  ///
  /// In he, this message translates to:
  /// **'תודה על ההתעניינות. לצערי מצאנו שוכר מתאים. בהצלחה!'**
  String get messageScreenA6b75beb;

  /// No description provided for @messageScreen4a708a34.
  ///
  /// In he, this message translates to:
  /// **'ברכות כניסה'**
  String get messageScreen4a708a34;

  /// No description provided for @messageScreen010505cb.
  ///
  /// In he, this message translates to:
  /// **'ברוך הבא לדירה! אני כאן לכל שאלה.'**
  String get messageScreen010505cb;

  /// No description provided for @messageScreenF03a8037.
  ///
  /// In he, this message translates to:
  /// **'תבניות הודעה'**
  String get messageScreenF03a8037;

  /// No description provided for @messageScreen9ebe91ae.
  ///
  /// In he, this message translates to:
  /// **'בחר תבנית — ניתן לערוך לפני שליחה'**
  String get messageScreen9ebe91ae;

  /// No description provided for @messageScreen20a086c2.
  ///
  /// In he, this message translates to:
  /// **'הצע זמנים לצפייה'**
  String get messageScreen20a086c2;

  /// No description provided for @messageScreenA4c847ba.
  ///
  /// In he, this message translates to:
  /// **'בחר עד 3 מועדים פנויים לשליחה לשוכר'**
  String get messageScreenA4c847ba;

  /// No description provided for @messageScreenE95891e3.
  ///
  /// In he, this message translates to:
  /// **'בחר עד 3 מועדים פנויים — השוכר יוכל לאשר אחד מהם.'**
  String get messageScreenE95891e3;

  /// No description provided for @messageScreenB22c28b7.
  ///
  /// In he, this message translates to:
  /// **'בחר מועדים לשליחה'**
  String get messageScreenB22c28b7;

  /// No description provided for @messageScreen7eea2f56.
  ///
  /// In he, this message translates to:
  /// **'שלח {count} מועדים לשוכר'**
  String messageScreen7eea2f56(Object count);

  /// No description provided for @messageScreenEe0506aa.
  ///
  /// In he, this message translates to:
  /// **'אין זמנים פנויים'**
  String get messageScreenEe0506aa;

  /// No description provided for @messageScreen8ac80938.
  ///
  /// In he, this message translates to:
  /// **'הוסף מועדים פנויים ביומן כדי שתוכל להציע אותם לשוכר.'**
  String get messageScreen8ac80938;

  /// No description provided for @messageScreen584c93b0.
  ///
  /// In he, this message translates to:
  /// **'הוסף זמנים ביומן'**
  String get messageScreen584c93b0;

  /// No description provided for @messageScreen1aebd38a.
  ///
  /// In he, this message translates to:
  /// **'{time} · {duration} דק׳'**
  String messageScreen1aebd38a(Object duration, Object time);

  /// No description provided for @messageScreenFa77db70.
  ///
  /// In he, this message translates to:
  /// **'רונה'**
  String get messageScreenFa77db70;

  /// No description provided for @messageScreenCf6515cd.
  ///
  /// In he, this message translates to:
  /// **'נובמבר 2026'**
  String get messageScreenCf6515cd;

  /// No description provided for @messageScreen1bcdb486.
  ///
  /// In he, this message translates to:
  /// **'הוזמנת לפגישת סיור בדירה של {name}'**
  String messageScreen1bcdb486(Object name);

  /// No description provided for @messageScreen8270663e.
  ///
  /// In he, this message translates to:
  /// **'מאושר'**
  String get messageScreen8270663e;

  /// No description provided for @messageScreenF21acb6a.
  ///
  /// In he, this message translates to:
  /// **'אישור'**
  String get messageScreenF21acb6a;

  /// No description provided for @messageScreenAbfb1f15.
  ///
  /// In he, this message translates to:
  /// **'{time} · {duration} דק׳'**
  String messageScreenAbfb1f15(Object duration, Object time);

  /// No description provided for @messageScreen354ef2c7.
  ///
  /// In he, this message translates to:
  /// **'אשר'**
  String get messageScreen354ef2c7;

  /// No description provided for @messageScreenC83c4f81.
  ///
  /// In he, this message translates to:
  /// **'ממתין לאישור'**
  String get messageScreenC83c4f81;

  /// No description provided for @messageScreen94eb6af0.
  ///
  /// In he, this message translates to:
  /// **'צפייה מאושרת'**
  String get messageScreen94eb6af0;

  /// No description provided for @messageScreenDae6b270.
  ///
  /// In he, this message translates to:
  /// **'ראשון'**
  String get messageScreenDae6b270;

  /// No description provided for @messageScreen47f34119.
  ///
  /// In he, this message translates to:
  /// **'שני'**
  String get messageScreen47f34119;

  /// No description provided for @messageScreenDb0c22fc.
  ///
  /// In he, this message translates to:
  /// **'שלישי'**
  String get messageScreenDb0c22fc;

  /// No description provided for @messageScreenDa1dae77.
  ///
  /// In he, this message translates to:
  /// **'רביעי'**
  String get messageScreenDa1dae77;

  /// No description provided for @messageScreenCe94cfff.
  ///
  /// In he, this message translates to:
  /// **'חמישי'**
  String get messageScreenCe94cfff;

  /// No description provided for @messageScreen7e718908.
  ///
  /// In he, this message translates to:
  /// **'שישי'**
  String get messageScreen7e718908;

  /// No description provided for @messageScreen4203bd7e.
  ///
  /// In he, this message translates to:
  /// **'שבת'**
  String get messageScreen4203bd7e;

  /// No description provided for @messageScreen89d6e050.
  ///
  /// In he, this message translates to:
  /// **'ינואר'**
  String get messageScreen89d6e050;

  /// No description provided for @messageScreenE974ea8b.
  ///
  /// In he, this message translates to:
  /// **'פברואר'**
  String get messageScreenE974ea8b;

  /// No description provided for @messageScreenC0394ea3.
  ///
  /// In he, this message translates to:
  /// **'מרץ'**
  String get messageScreenC0394ea3;

  /// No description provided for @messageScreenA1ac81be.
  ///
  /// In he, this message translates to:
  /// **'אפריל'**
  String get messageScreenA1ac81be;

  /// No description provided for @messageScreen5fa88202.
  ///
  /// In he, this message translates to:
  /// **'מאי'**
  String get messageScreen5fa88202;

  /// No description provided for @messageScreen4dee19aa.
  ///
  /// In he, this message translates to:
  /// **'יוני'**
  String get messageScreen4dee19aa;

  /// No description provided for @messageScreenCf58b8a7.
  ///
  /// In he, this message translates to:
  /// **'יולי'**
  String get messageScreenCf58b8a7;

  /// No description provided for @messageScreen3551b598.
  ///
  /// In he, this message translates to:
  /// **'אוגוסט'**
  String get messageScreen3551b598;

  /// No description provided for @messageScreenD7106337.
  ///
  /// In he, this message translates to:
  /// **'ספטמבר'**
  String get messageScreenD7106337;

  /// No description provided for @messageScreen45ded998.
  ///
  /// In he, this message translates to:
  /// **'אוקטובר'**
  String get messageScreen45ded998;

  /// No description provided for @messageScreen712a2e4f.
  ///
  /// In he, this message translates to:
  /// **'נובמבר'**
  String get messageScreen712a2e4f;

  /// No description provided for @messageScreen1774bb5f.
  ///
  /// In he, this message translates to:
  /// **'דצמבר'**
  String get messageScreen1774bb5f;

  /// No description provided for @messageScreen95d86d7f.
  ///
  /// In he, this message translates to:
  /// **'היום'**
  String get messageScreen95d86d7f;

  /// No description provided for @messageScreen840835ac.
  ///
  /// In he, this message translates to:
  /// **'מחר'**
  String get messageScreen840835ac;

  /// No description provided for @messageScreenC254edb1.
  ///
  /// In he, this message translates to:
  /// **'יום {weekday}'**
  String messageScreenC254edb1(Object weekday);

  /// No description provided for @messageScreenA118b482.
  ///
  /// In he, this message translates to:
  /// **'{dayPart} · {day} ב{month}'**
  String messageScreenA118b482(Object day, Object dayPart, Object month);

  /// No description provided for @messageScreenBe285a01.
  ///
  /// In he, this message translates to:
  /// **'אתמול'**
  String get messageScreenBe285a01;

  /// No description provided for @propertyDetailScreen1648cbc8.
  ///
  /// In he, this message translates to:
  /// **'הסיור נשמר לנכס ✓'**
  String get propertyDetailScreen1648cbc8;

  /// No description provided for @propertyDetailScreenCfa0c95c.
  ///
  /// In he, this message translates to:
  /// **'{type} ב{street} {number}'**
  String propertyDetailScreenCfa0c95c(
      Object number, Object street, Object type);

  /// No description provided for @propertyDetailScreenC9a1c5dd.
  ///
  /// In he, this message translates to:
  /// **'{type} ב{street}'**
  String propertyDetailScreenC9a1c5dd(Object street, Object type);

  /// No description provided for @propertyDetailScreen0196a48c.
  ///
  /// In he, this message translates to:
  /// **'{type} ב{city}'**
  String propertyDetailScreen0196a48c(Object city, Object type);

  /// No description provided for @propertyDetailScreen18b1f617.
  ///
  /// In he, this message translates to:
  /// **'שאל את Rently'**
  String get propertyDetailScreen18b1f617;

  /// No description provided for @propertyDetailScreen7e8504c2.
  ///
  /// In he, this message translates to:
  /// **'שאלו כל דבר על הדירה — חיות, קומה, תחבורה ועוד'**
  String get propertyDetailScreen7e8504c2;

  /// No description provided for @propertyDetailScreenEed2fbf3.
  ///
  /// In he, this message translates to:
  /// **'גלריה'**
  String get propertyDetailScreenEed2fbf3;

  /// No description provided for @propertyDetailScreen220d2733.
  ///
  /// In he, this message translates to:
  /// **'פרטי הנכס'**
  String get propertyDetailScreen220d2733;

  /// No description provided for @propertyDetailScreenCb66c16b.
  ///
  /// In he, this message translates to:
  /// **'אתר מקור'**
  String get propertyDetailScreenCb66c16b;

  /// No description provided for @propertyDetailScreen5e4548cf.
  ///
  /// In he, this message translates to:
  /// **'צפה במקור'**
  String get propertyDetailScreen5e4548cf;

  /// No description provided for @propertyDetailScreenAe561237.
  ///
  /// In he, this message translates to:
  /// **'נכס זה פורסם במקור באתר {host}. באפשרותך לפתוח את המודעה המקורית לצפייה בפרטים המלאים.'**
  String propertyDetailScreenAe561237(Object host);

  /// No description provided for @propertyDetailScreenDc721374.
  ///
  /// In he, this message translates to:
  /// **'למה ההתאמה הזו'**
  String get propertyDetailScreenDc721374;

  /// No description provided for @propertyDetailScreenC1a89075.
  ///
  /// In he, this message translates to:
  /// **'בעל הנכס'**
  String get propertyDetailScreenC1a89075;

  /// No description provided for @propertyDetailScreenCd77cc3f.
  ///
  /// In he, this message translates to:
  /// **'סיורים'**
  String get propertyDetailScreenCd77cc3f;

  /// No description provided for @propertyDetailScreen2e98c1c0.
  ///
  /// In he, this message translates to:
  /// **'סיור וירטואלי'**
  String get propertyDetailScreen2e98c1c0;

  /// No description provided for @propertyDetailScreenCa52b1de.
  ///
  /// In he, this message translates to:
  /// **'סיור 360°'**
  String get propertyDetailScreenCa52b1de;

  /// No description provided for @propertyDetailScreen49f61379.
  ///
  /// In he, this message translates to:
  /// **'סיור פנורמי אינטראקטיבי — הסתובבו בדירה'**
  String get propertyDetailScreen49f61379;

  /// No description provided for @propertyDetailScreen0774dd22.
  ///
  /// In he, this message translates to:
  /// **'סריקת תלת-מימד (מתקדם)'**
  String get propertyDetailScreen0774dd22;

  /// No description provided for @propertyDetailScreen5364affd.
  ///
  /// In he, this message translates to:
  /// **'✓ הסריקה מוכנה — סובבו והתקרבו מכל זווית'**
  String get propertyDetailScreen5364affd;

  /// No description provided for @propertyDetailScreen5ba546d9.
  ///
  /// In he, this message translates to:
  /// **'סריקת תלת-מימד'**
  String get propertyDetailScreen5ba546d9;

  /// No description provided for @propertyDetailScreen64680a66.
  ///
  /// In he, this message translates to:
  /// **'מאפיינים חשובים'**
  String get propertyDetailScreen64680a66;

  /// No description provided for @propertyDetailScreen1c5efd6c.
  ///
  /// In he, this message translates to:
  /// **'חוות דעת'**
  String get propertyDetailScreen1c5efd6c;

  /// No description provided for @propertyDetailScreen16c30b46.
  ///
  /// In he, this message translates to:
  /// **'{count} ביקורות'**
  String propertyDetailScreen16c30b46(Object count);

  /// No description provided for @propertyDetailScreen26d0e7de.
  ///
  /// In he, this message translates to:
  /// **'מיקום'**
  String get propertyDetailScreen26d0e7de;

  /// No description provided for @propertyDetailScreenC7f1527f.
  ///
  /// In he, this message translates to:
  /// **'סיור 360° אינטראקטיבי — הסתובבו בדירה'**
  String get propertyDetailScreenC7f1527f;

  /// No description provided for @propertyDetailScreen10c20d96.
  ///
  /// In he, this message translates to:
  /// **'סריקת תלת־ממד / וידאו זמינה לצפייה'**
  String get propertyDetailScreen10c20d96;

  /// No description provided for @propertyDetailScreenE41c38fa.
  ///
  /// In he, this message translates to:
  /// **'הסריקה בהכנה — תהיה זמינה בקרוב'**
  String get propertyDetailScreenE41c38fa;

  /// No description provided for @propertyDetailScreenB4499910.
  ///
  /// In he, this message translates to:
  /// **'בקשו סריקת תלת־ממד מבעל הנכס'**
  String get propertyDetailScreenB4499910;

  /// No description provided for @propertyDetailScreenD60a9025.
  ///
  /// In he, this message translates to:
  /// **'וידאו הנכס'**
  String get propertyDetailScreenD60a9025;

  /// No description provided for @propertyDetailScreen5f699c03.
  ///
  /// In he, this message translates to:
  /// **'סיור תלת־ממדי'**
  String get propertyDetailScreen5f699c03;

  /// No description provided for @propertyDetailScreen84d6efd4.
  ///
  /// In he, this message translates to:
  /// **'מייעל את הסריקה לטעינה מהירה…'**
  String get propertyDetailScreen84d6efd4;

  /// No description provided for @propertyDetailScreenAca86e76.
  ///
  /// In he, this message translates to:
  /// **'מעבד סריקת תלת-מימד…'**
  String get propertyDetailScreenAca86e76;

  /// No description provided for @propertyDetailScreenAf2ce96d.
  ///
  /// In he, this message translates to:
  /// **'הסריקה כבר ניתנת לצפייה; מכינים גרסה חדה וקלה שנטענת מהר.'**
  String get propertyDetailScreenAf2ce96d;

  /// No description provided for @propertyDetailScreenEd5f9651.
  ///
  /// In he, this message translates to:
  /// **'בונים את המודל — כמה דקות. אפשר לעזוב, נודיע כשמוכן.'**
  String get propertyDetailScreenEd5f9651;

  /// No description provided for @propertyDetailScreenD886d07f.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חדרים'**
  String propertyDetailScreenD886d07f(Object rooms);

  /// No description provided for @propertyDetailScreenFdb4eac7.
  ///
  /// In he, this message translates to:
  /// **'{size} מ״ר'**
  String propertyDetailScreenFdb4eac7(Object size);

  /// No description provided for @propertyDetailScreenD068bb57.
  ///
  /// In he, this message translates to:
  /// **'קומה {floor}'**
  String propertyDetailScreenD068bb57(Object floor);

  /// No description provided for @propertyDetailScreen51146937.
  ///
  /// In he, this message translates to:
  /// **'מתווך נדל\"ן'**
  String get propertyDetailScreen51146937;

  /// No description provided for @propertyDetailScreenB49f4d60.
  ///
  /// In he, this message translates to:
  /// **'בעל נכס פרטי'**
  String get propertyDetailScreenB49f4d60;

  /// No description provided for @propertyDetailScreen38b3ff8f.
  ///
  /// In he, this message translates to:
  /// **'פרטי בעל הנכס, הדירוגים והערות השוכרים הקודמים זמינים כאן בשקיפות מלאה.'**
  String get propertyDetailScreen38b3ff8f;

  /// No description provided for @propertyDetailScreen37735588.
  ///
  /// In he, this message translates to:
  /// **'פרופיל משכיר'**
  String get propertyDetailScreen37735588;

  /// No description provided for @propertyDetailScreen60c6ffbf.
  ///
  /// In he, this message translates to:
  /// **'({count} חוות דעת)'**
  String propertyDetailScreen60c6ffbf(Object count);

  /// No description provided for @propertyDetailScreenB851d927.
  ///
  /// In he, this message translates to:
  /// **'צפה בכל הדירות של בעל הנכס'**
  String get propertyDetailScreenB851d927;

  /// No description provided for @propertyDetailScreen20fdeb3f.
  ///
  /// In he, this message translates to:
  /// **'בקשה לשלוח הודעה לבעל הנכס'**
  String get propertyDetailScreen20fdeb3f;

  /// No description provided for @propertyDetailScreenA60c8ada.
  ///
  /// In he, this message translates to:
  /// **'כתוב הודעה קצרה… (למשל: מתי אפשר לראות?)'**
  String get propertyDetailScreenA60c8ada;

  /// No description provided for @propertyDetailScreenDfe611d6.
  ///
  /// In he, this message translates to:
  /// **'שלח בקשה'**
  String get propertyDetailScreenDfe611d6;

  /// No description provided for @propertyDetailScreenA8a4ed17.
  ///
  /// In he, this message translates to:
  /// **'הבקשה נשלחה — היא תופיע אצל בעל הנכס תחת \"מבקשים לשלוח הודעה\"'**
  String get propertyDetailScreenA8a4ed17;

  /// No description provided for @propertyDetailScreenD490b1b3.
  ///
  /// In he, this message translates to:
  /// **'הבקשה נשלחה'**
  String get propertyDetailScreenD490b1b3;

  /// No description provided for @propertyDetailScreen35e6ba29.
  ///
  /// In he, this message translates to:
  /// **'בקש לשלוח הודעה'**
  String get propertyDetailScreen35e6ba29;

  /// No description provided for @propertyDetailScreenB5441c0d.
  ///
  /// In he, this message translates to:
  /// **'מתווך נדל\"ן מאומת'**
  String get propertyDetailScreenB5441c0d;

  /// No description provided for @propertyDetailScreen3a3d66cf.
  ///
  /// In he, this message translates to:
  /// **'בעל דירה פרטי'**
  String get propertyDetailScreen3a3d66cf;

  /// No description provided for @propertyDetailScreenF5211c9b.
  ///
  /// In he, this message translates to:
  /// **'{rating} · {count} ביקורות'**
  String propertyDetailScreenF5211c9b(Object count, Object rating);

  /// No description provided for @propertyDetailScreenDf4787e7.
  ///
  /// In he, this message translates to:
  /// **'פתח במפות'**
  String get propertyDetailScreenDf4787e7;

  /// No description provided for @propertyDetailScreen9e8d9316.
  ///
  /// In he, this message translates to:
  /// **'עריכת נכס'**
  String get propertyDetailScreen9e8d9316;

  /// No description provided for @propertyDetailScreen38bf5edd.
  ///
  /// In he, this message translates to:
  /// **'אהבתי'**
  String get propertyDetailScreen38bf5edd;

  /// No description provided for @propertyDetailScreen18078153.
  ///
  /// In he, this message translates to:
  /// **'סריקה בהכנה'**
  String get propertyDetailScreen18078153;

  /// No description provided for @propertyDetailScreen567a5b29.
  ///
  /// In he, this message translates to:
  /// **'העלה סיור 360°'**
  String get propertyDetailScreen567a5b29;

  /// No description provided for @propertyDetailScreenE895a9f6.
  ///
  /// In he, this message translates to:
  /// **'בקש סיור תלת־ממדי'**
  String get propertyDetailScreenE895a9f6;

  /// No description provided for @propertyDetailScreen5e0a5dc3.
  ///
  /// In he, this message translates to:
  /// **'הסריקה התלת־ממדית נכשלה'**
  String get propertyDetailScreen5e0a5dc3;

  /// No description provided for @propertyDetailScreen00ae4acb.
  ///
  /// In he, this message translates to:
  /// **'סריקת ה־3D בעיבוד'**
  String get propertyDetailScreen00ae4acb;

  /// No description provided for @propertyDetailScreenE55088ee.
  ///
  /// In he, this message translates to:
  /// **'הסריקה בתור לעיבוד'**
  String get propertyDetailScreenE55088ee;

  /// No description provided for @propertyDetailScreen19a76d77.
  ///
  /// In he, this message translates to:
  /// **'עדיין אין סיור תלת־ממדי לנכס הזה'**
  String get propertyDetailScreen19a76d77;

  /// No description provided for @propertyDetailScreenA692c8ad.
  ///
  /// In he, this message translates to:
  /// **'העיבוד לא הצליח לשחזר את הדירה מהסרטון. לרוב זה קורה כשהצילום מהיר מדי או חלקי. צלמו שוב לאט, סובבו סביב כל חדר וודאו תאורה טובה — ונסו להעלות מחדש.'**
  String get propertyDetailScreenA692c8ad;

  /// No description provided for @propertyDetailScreen737db867.
  ///
  /// In he, this message translates to:
  /// **'בעל הדירה צילם את הדירה וממתין שהעיבוד יתחיל. הסיור יהיה זמין בקרוב.'**
  String get propertyDetailScreen737db867;

  /// No description provided for @propertyDetailScreen6f8a3ed4.
  ///
  /// In he, this message translates to:
  /// **'כדי לפתוח הליכה חופשית בתוך הדירה צריך שתהיה סריקה או וידאו ייעודי של הנכס. כרגע אפשר להמשיך דרך התמונות והמודעה המקורית.'**
  String get propertyDetailScreen6f8a3ed4;

  /// No description provided for @propertyDetailScreen55247199.
  ///
  /// In he, this message translates to:
  /// **'סגור'**
  String get propertyDetailScreen55247199;

  /// No description provided for @propertyDetailScreenE53b7e24.
  ///
  /// In he, this message translates to:
  /// **'פתח מודעה'**
  String get propertyDetailScreenE53b7e24;

  /// No description provided for @propertyDetailScreen1b33c853.
  ///
  /// In he, this message translates to:
  /// **'שלב עיבוד: {progress}% הושלם. כשיהיה מוכן, הכפתור יפתח סיור אינטראקטיבי.'**
  String propertyDetailScreen1b33c853(Object progress);

  /// No description provided for @propertyDetailScreen57f60266.
  ///
  /// In he, this message translates to:
  /// **'הסריקה ממתינה לתור בשרת. בדרך כלל מתחיל תוך דקה.'**
  String get propertyDetailScreen57f60266;

  /// No description provided for @propertyDetailScreen910fa358.
  ///
  /// In he, this message translates to:
  /// **'מנתח את חללי הדירה ובונה את סביבת ה־3D. עוד כמה דקות.'**
  String get propertyDetailScreen910fa358;

  /// No description provided for @propertyDetailScreen8915c338.
  ///
  /// In he, this message translates to:
  /// **'העיבוד הסתיים, ה־viewer מוכן לפתיחה.'**
  String get propertyDetailScreen8915c338;

  /// No description provided for @propertyDetailScreen2e691011.
  ///
  /// In he, this message translates to:
  /// **'העיבוד בענן פעיל. כשה־viewer יהיה מוכן, הכפתור יפתח סיור אינטראקטיבי.'**
  String get propertyDetailScreen2e691011;

  /// No description provided for @propertyDetailScreen45f39647.
  ///
  /// In he, this message translates to:
  /// **'זמן משוער: 1–3 דקות'**
  String get propertyDetailScreen45f39647;

  /// No description provided for @propertyDetailScreen1aa87a41.
  ///
  /// In he, this message translates to:
  /// **'זמן משוער: 2–5 דקות'**
  String get propertyDetailScreen1aa87a41;

  /// No description provided for @propertyDetailScreenDc5803b6.
  ///
  /// In he, this message translates to:
  /// **'זמן משוער: כמה דקות'**
  String get propertyDetailScreenDc5803b6;

  /// No description provided for @propertyDetailScreen105df502.
  ///
  /// In he, this message translates to:
  /// **'גרור בין קטעי הסיור כדי להרגיש את החלל לפני ביקור פיזי.'**
  String get propertyDetailScreen105df502;

  /// No description provided for @propertyDetailScreen8f880283.
  ///
  /// In he, this message translates to:
  /// **'הסיור האינטראקטיבי נטען רק כשפותחים אותו, כדי לשמור את האפליקציה קלה ומהירה.'**
  String get propertyDetailScreen8f880283;

  /// No description provided for @propertyDetailScreen5ec26848.
  ///
  /// In he, this message translates to:
  /// **'איכות {quality}%'**
  String propertyDetailScreen5ec26848(Object quality);

  /// No description provided for @propertyDetailScreen47a54d83.
  ///
  /// In he, this message translates to:
  /// **'קובץ זמין'**
  String get propertyDetailScreen47a54d83;

  /// No description provided for @propertyDetailScreen4e4ee34f.
  ///
  /// In he, this message translates to:
  /// **'פתח סיור אינטראקטיבי'**
  String get propertyDetailScreen4e4ee34f;

  /// No description provided for @propertyDetailScreenB29bd206.
  ///
  /// In he, this message translates to:
  /// **'לא ניתן לטעון את ההדמיה'**
  String get propertyDetailScreenB29bd206;

  /// No description provided for @propertyDetailScreenEef6e71b.
  ///
  /// In he, this message translates to:
  /// **'הדמיית AI'**
  String get propertyDetailScreenEef6e71b;

  /// No description provided for @propertyDetailScreenB94d2093.
  ///
  /// In he, this message translates to:
  /// **'נוח לתקציב'**
  String get propertyDetailScreenB94d2093;

  /// No description provided for @propertyDetailScreen6d51cdeb.
  ///
  /// In he, this message translates to:
  /// **'מתיחה תקציבית'**
  String get propertyDetailScreen6d51cdeb;

  /// No description provided for @propertyDetailScreen8d3cefa5.
  ///
  /// In he, this message translates to:
  /// **'נטל גבוה'**
  String get propertyDetailScreen8d3cefa5;

  /// No description provided for @propertyDetailScreenE0def62e.
  ///
  /// In he, this message translates to:
  /// **'הוסיפו הכנסה לבדיקת התאמה'**
  String get propertyDetailScreenE0def62e;

  /// No description provided for @propertyDetailScreenE1354b80.
  ///
  /// In he, this message translates to:
  /// **'הזן הכנסה לבדיקת התאמה'**
  String get propertyDetailScreenE1354b80;

  /// No description provided for @propertyDetailScreenB146c814.
  ///
  /// In he, this message translates to:
  /// **'סה״כ עלות כניסה'**
  String get propertyDetailScreenB146c814;

  /// No description provided for @propertyDetailScreen4afd38ca.
  ///
  /// In he, this message translates to:
  /// **'מה הזכויות שלי?'**
  String get propertyDetailScreen4afd38ca;

  /// No description provided for @propertyDetailScreenB2e36464.
  ///
  /// In he, this message translates to:
  /// **'{views} צפו בדירה'**
  String propertyDetailScreenB2e36464(Object views);

  /// No description provided for @propertyDetailScreenA9d0dba3.
  ///
  /// In he, this message translates to:
  /// **'{likes} אהבו'**
  String propertyDetailScreenA9d0dba3(Object likes);

  /// No description provided for @propertyDetailScreen220a89be.
  ///
  /// In he, this message translates to:
  /// **'דירה מאומתת'**
  String get propertyDetailScreen220a89be;

  /// No description provided for @propertyDetailScreenD5424d20.
  ///
  /// In he, this message translates to:
  /// **'דירה הועלתה לאחרונה'**
  String get propertyDetailScreenD5424d20;

  /// No description provided for @propertyDetailScreen67fb588b.
  ///
  /// In he, this message translates to:
  /// **'מסתכל עכשיו'**
  String get propertyDetailScreen67fb588b;

  /// No description provided for @propertyDetailScreen479025fb.
  ///
  /// In he, this message translates to:
  /// **'{count} מסתכלים עכשיו'**
  String propertyDetailScreen479025fb(Object count);

  /// No description provided for @propertyDetailScreenAb15e1c6.
  ///
  /// In he, this message translates to:
  /// **'{count} אהבו היום'**
  String propertyDetailScreenAb15e1c6(Object count);

  /// No description provided for @propertyDetailScreenB50b3974.
  ///
  /// In he, this message translates to:
  /// **'חדרים'**
  String get propertyDetailScreenB50b3974;

  /// No description provided for @propertyDetailScreen451ffaea.
  ///
  /// In he, this message translates to:
  /// **'שטח במ\"ר'**
  String get propertyDetailScreen451ffaea;

  /// No description provided for @propertyDetailScreen047e630b.
  ///
  /// In he, this message translates to:
  /// **'קומה'**
  String get propertyDetailScreen047e630b;

  /// No description provided for @propertyDetailScreen3e20e30e.
  ///
  /// In he, this message translates to:
  /// **'רגיל'**
  String get propertyDetailScreen3e20e30e;

  /// No description provided for @propertyDetailScreen357b4923.
  ///
  /// In he, this message translates to:
  /// **'מצב הנכס'**
  String get propertyDetailScreen357b4923;

  /// No description provided for @propertyDetailScreen1f70207b.
  ///
  /// In he, this message translates to:
  /// **'יש'**
  String get propertyDetailScreen1f70207b;

  /// No description provided for @propertyDetailScreenEa12a4ba.
  ///
  /// In he, this message translates to:
  /// **'אין'**
  String get propertyDetailScreenEa12a4ba;

  /// No description provided for @propertyDetailScreen3ac08c81.
  ///
  /// In he, this message translates to:
  /// **'חנייה'**
  String get propertyDetailScreen3ac08c81;

  /// No description provided for @propertyDetailScreen8d058056.
  ///
  /// In he, this message translates to:
  /// **'מעלית'**
  String get propertyDetailScreen8d058056;

  /// No description provided for @propertyDetailScreen7563e7f9.
  ///
  /// In he, this message translates to:
  /// **'שוכר לשעבר'**
  String get propertyDetailScreen7563e7f9;

  /// No description provided for @propertyDetailScreen48abdfae.
  ///
  /// In he, this message translates to:
  /// **'למה ההתאמה הזו?'**
  String get propertyDetailScreen48abdfae;

  /// No description provided for @propertyDetailScreenF83ca4dc.
  ///
  /// In he, this message translates to:
  /// **'דירוג הדדי — מתחשב גם בהעדפות בעל הדירה'**
  String get propertyDetailScreenF83ca4dc;

  /// No description provided for @propertyDetailScreen98f6f9b2.
  ///
  /// In he, this message translates to:
  /// **'לפי ההעדפות שלך'**
  String get propertyDetailScreen98f6f9b2;

  /// No description provided for @searchChatScreen8e4d1523.
  ///
  /// In he, this message translates to:
  /// **'אתי'**
  String get searchChatScreen8e4d1523;

  /// No description provided for @searchChatScreen7ea53091.
  ///
  /// In he, this message translates to:
  /// **'3 חדרים בתל אביב עד 7000, עם מרפסת'**
  String get searchChatScreen7ea53091;

  /// No description provided for @searchChatScreenC2031464.
  ///
  /// In he, this message translates to:
  /// **'ליד הרכבת, משופצת, לזוג עם כלב'**
  String get searchChatScreenC2031464;

  /// No description provided for @searchChatScreen13a0e834.
  ///
  /// In he, this message translates to:
  /// **'דירה בחיפה עם חניה ומעלית'**
  String get searchChatScreen13a0e834;

  /// No description provided for @searchChatScreen4d424290.
  ///
  /// In he, this message translates to:
  /// **'היי! אני {name} 👋 כיף להכיר.\nאני כאן כדי לעזור לך למצוא בית שבאמת '**
  String searchChatScreen4d424290(Object name);

  /// No description provided for @searchChatScreenE14f1c0d.
  ///
  /// In he, this message translates to:
  /// **'מתאים לך — בלי לחץ ובקצב שלך. ספר לי קצת עליך ועל מה שאתה מחפש, '**
  String get searchChatScreenE14f1c0d;

  /// No description provided for @searchChatScreen997d1274.
  ///
  /// In he, this message translates to:
  /// **'במילים שלך, ואני אדאג לשאר. 🙂'**
  String get searchChatScreen997d1274;

  /// No description provided for @searchChatScreenCcd6fad4.
  ///
  /// In he, this message translates to:
  /// **'אין עדיין חיפושים קודמים'**
  String get searchChatScreenCcd6fad4;

  /// No description provided for @searchChatScreenE13c91de.
  ///
  /// In he, this message translates to:
  /// **'חיפושים אחרונים'**
  String get searchChatScreenE13c91de;

  /// No description provided for @searchChatScreenE8b3a3d5.
  ///
  /// In he, this message translates to:
  /// **'נקה'**
  String get searchChatScreenE8b3a3d5;

  /// No description provided for @searchChatScreen9f2426ad.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חד׳'**
  String searchChatScreen9f2426ad(Object rooms);

  /// No description provided for @searchChatScreen255d7425.
  ///
  /// In he, this message translates to:
  /// **'ליד הרכבת'**
  String get searchChatScreen255d7425;

  /// No description provided for @searchChatScreen679a8520.
  ///
  /// In he, this message translates to:
  /// **'הכי משתלם'**
  String get searchChatScreen679a8520;

  /// No description provided for @searchChatScreen3fd04a29.
  ///
  /// In he, this message translates to:
  /// **'הסינון שלך:'**
  String get searchChatScreen3fd04a29;

  /// No description provided for @searchChatScreen4d756cba.
  ///
  /// In he, this message translates to:
  /// **'עד {rooms}'**
  String searchChatScreen4d756cba(Object rooms);

  /// No description provided for @searchChatScreenB3cd0d47.
  ///
  /// In he, this message translates to:
  /// **'עד ₪{price}'**
  String searchChatScreenB3cd0d47(Object price);

  /// No description provided for @searchChatScreen043b90f3.
  ///
  /// In he, this message translates to:
  /// **'מ-₪{price}'**
  String searchChatScreen043b90f3(Object price);

  /// No description provided for @searchChatScreenF85b1711.
  ///
  /// In he, this message translates to:
  /// **'ניקיתי את הסינון 🙂 ספר לי מה לחפש עכשיו.'**
  String get searchChatScreenF85b1711;

  /// No description provided for @searchChatScreen2611b32a.
  ///
  /// In he, this message translates to:
  /// **'אחרי העדכון לא נשארו התאמות. אפשר להוסיף משהו אחר?'**
  String get searchChatScreen2611b32a;

  /// No description provided for @searchChatScreenA55284d7.
  ///
  /// In he, this message translates to:
  /// **'עדכנתי לפי השינוי 👇'**
  String get searchChatScreenA55284d7;

  /// No description provided for @searchChatScreen6f6b921d.
  ///
  /// In he, this message translates to:
  /// **'מחפש עוד דירות…'**
  String get searchChatScreen6f6b921d;

  /// No description provided for @searchChatScreen4636c484.
  ///
  /// In he, this message translates to:
  /// **'הצג עוד {count} דירות'**
  String searchChatScreen4636c484(Object count);

  /// No description provided for @searchChatScreenCc493224.
  ///
  /// In he, this message translates to:
  /// **'הצג עוד דירות'**
  String get searchChatScreenCc493224;

  /// No description provided for @searchChatScreen7ce13a9c.
  ///
  /// In he, this message translates to:
  /// **'הנה כמה דירות שמתאימות למה שסיפרת 👇'**
  String get searchChatScreen7ce13a9c;

  /// No description provided for @searchChatScreenA6e71e55.
  ///
  /// In he, this message translates to:
  /// **'לא מצאתי דירה מדויקת, אפשר להרחיב אזור או תקציב?'**
  String get searchChatScreenA6e71e55;

  /// No description provided for @searchChatScreen61081906.
  ///
  /// In he, this message translates to:
  /// **'מצאתי {count} דירות שמתאימות, הן מופיעות עכשיו על המסך'**
  String searchChatScreen61081906(Object count);

  /// No description provided for @searchChatScreenC0c2a8be.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חדרים'**
  String searchChatScreenC0c2a8be(Object rooms);

  /// No description provided for @searchChatScreen35e94525.
  ///
  /// In he, this message translates to:
  /// **'עד {price} ₪'**
  String searchChatScreen35e94525(Object price);

  /// No description provided for @searchChatScreen840a3a9f.
  ///
  /// In he, this message translates to:
  /// **'🚉 ליד הרכבת'**
  String get searchChatScreen840a3a9f;

  /// No description provided for @searchChatScreen5a4b1739.
  ///
  /// In he, this message translates to:
  /// **'רגע, בוא נחדד עוד קצת ואמצא לך את המתאימות'**
  String get searchChatScreen5a4b1739;

  /// No description provided for @searchChatScreenBc3b9351.
  ///
  /// In he, this message translates to:
  /// **'מעולה! הנה מה שמצאתי בשבילך 👇'**
  String get searchChatScreenBc3b9351;

  /// No description provided for @searchChatScreen95335c81.
  ///
  /// In he, this message translates to:
  /// **'כדי לחפש לך דירות באזור שלך אני צריכה לדעת איפה את/ה 📍 אפשר לשתף מיקום?'**
  String get searchChatScreen95335c81;

  /// No description provided for @searchChatScreen1daddad9.
  ///
  /// In he, this message translates to:
  /// **'מצאתי כמה אפשרויות שמתאימות למה שתיארת. '**
  String get searchChatScreen1daddad9;

  /// No description provided for @searchChatScreen39e1f421.
  ///
  /// In he, this message translates to:
  /// **'רוצה שאראה לך אותן עכשיו, או שנוסיף עוד משהו? 🙂'**
  String get searchChatScreen39e1f421;

  /// No description provided for @searchChatScreen1f0defdc.
  ///
  /// In he, this message translates to:
  /// **'ספר לי עוד קצת על מה שאתה מחפש'**
  String get searchChatScreen1f0defdc;

  /// No description provided for @searchChatScreen7dae215b.
  ///
  /// In he, this message translates to:
  /// **'דירה'**
  String get searchChatScreen7dae215b;

  /// No description provided for @searchChatScreen320230a9.
  ///
  /// In he, this message translates to:
  /// **'צריך לאשר גישה למיקום בהגדרות 📍 — או פשוט תגיד/י לי באיזו עיר לחפש'**
  String get searchChatScreen320230a9;

  /// No description provided for @searchChatScreenE9aa1c0c.
  ///
  /// In he, this message translates to:
  /// **'לא הצלחתי לזהות מיקום כרגע 🙈 באיזו עיר לחפש?'**
  String get searchChatScreenE9aa1c0c;

  /// No description provided for @searchChatScreen3135f25b.
  ///
  /// In he, this message translates to:
  /// **'לא הצלחתי לזהות מיקום כרגע 🙈 אפשר פשוט להגיד לי באיזו עיר לחפש?'**
  String get searchChatScreen3135f25b;

  /// No description provided for @searchChatScreenF1e58bcd.
  ///
  /// In he, this message translates to:
  /// **'📍 מצאתי אותך — את/ה ב{city}. מחפשת שם עכשיו את מה שהכי מתאים 👇'**
  String searchChatScreenF1e58bcd(Object city);

  /// No description provided for @searchChatScreenD94e281c.
  ///
  /// In he, this message translates to:
  /// **'לא צפו כרגע התאמות מדויקות באזור שלך — נרחיב תקציב או אזור?'**
  String get searchChatScreenD94e281c;

  /// No description provided for @searchChatScreenD42b5de4.
  ///
  /// In he, this message translates to:
  /// **'הנה מה שהכי מתאים לך באזור שלך 👇'**
  String get searchChatScreenD42b5de4;

  /// No description provided for @searchChatScreen6f5e36b8.
  ///
  /// In he, this message translates to:
  /// **'ספר/י לי מה מחפשים — עיר, תקציב, כמה חדרים, ומה חשוב לך 🙂'**
  String get searchChatScreen6f5e36b8;

  /// No description provided for @searchChatScreen3130f977.
  ///
  /// In he, this message translates to:
  /// **'קיבלתי 👍 עוד משהו שחשוב לך, או שאראה לך דירות עכשיו?'**
  String get searchChatScreen3130f977;

  /// No description provided for @searchChatScreenE9c8b415.
  ///
  /// In he, this message translates to:
  /// **'הנה מה שמצאתי בשבילך 👇'**
  String get searchChatScreenE9c8b415;

  /// No description provided for @searchChatScreen4027c8f4.
  ///
  /// In he, this message translates to:
  /// **'הנה הכי קרובות למה שחיפשת 👇'**
  String get searchChatScreen4027c8f4;

  /// No description provided for @searchChatScreen55799661.
  ///
  /// In he, this message translates to:
  /// **'כדי למצוא לך דירות באזור שלך, אני רק צריכה לזהות איפה את/ה 📍\nלשתף את המיקום?'**
  String get searchChatScreen55799661;

  /// No description provided for @searchChatScreen9ccf780f.
  ///
  /// In he, this message translates to:
  /// **'כמה שאלות קצרות כדי לדייק בשבילך 🙂\n\n'**
  String get searchChatScreen9ccf780f;

  /// No description provided for @searchChatScreen37cee5fa.
  ///
  /// In he, this message translates to:
  /// **'תראי לי דירות עכשיו'**
  String get searchChatScreen37cee5fa;

  /// No description provided for @searchChatScreen8b1aa6b1.
  ///
  /// In he, this message translates to:
  /// **'שם'**
  String get searchChatScreen8b1aa6b1;

  /// No description provided for @searchChatScreen8c180264.
  ///
  /// In he, this message translates to:
  /// **'לא מצאתי דירות שעונות בדיוק לבקשה ב{city} עם הסינונים האלה — '**
  String searchChatScreen8c180264(Object city);

  /// No description provided for @searchChatScreenCeed4a22.
  ///
  /// In he, this message translates to:
  /// **'אבל אלה עד 10 ק\"מ מ{city}, עם אותם סינונים בדיוק (לא רחוק!)'**
  String searchChatScreenCeed4a22(Object city);

  /// No description provided for @searchChatScreenF7b15001.
  ///
  /// In he, this message translates to:
  /// **'עד {price} ₪'**
  String searchChatScreenF7b15001(Object price);

  /// No description provided for @searchChatScreenDc2e4dcf.
  ///
  /// In he, this message translates to:
  /// **'אזור {city}'**
  String searchChatScreenDc2e4dcf(Object city);

  /// No description provided for @searchChatScreen616a9ead.
  ///
  /// In he, this message translates to:
  /// **'האזור הזה'**
  String get searchChatScreen616a9ead;

  /// No description provided for @searchChatScreenA62ac675.
  ///
  /// In he, this message translates to:
  /// **'אזור {city}'**
  String searchChatScreenA62ac675(Object city);

  /// No description provided for @searchChatScreenE8ad7744.
  ///
  /// In he, this message translates to:
  /// **'עד {price} ₪'**
  String searchChatScreenE8ad7744(Object price);

  /// No description provided for @searchChatScreen02622166.
  ///
  /// In he, this message translates to:
  /// **'לא מצאתי דירות שעונות לבקשה ב{city} עם הסינונים האלה 😕\n'**
  String searchChatScreen02622166(Object city);

  /// No description provided for @searchChatScreen25b42314.
  ///
  /// In he, this message translates to:
  /// **'אפשר להרחיב את האזור, להעלות תקציב או להוריד סינונים כדי למצוא אופציות מתאימות.'**
  String get searchChatScreen25b42314;

  /// No description provided for @searchChatScreen3a89ba73.
  ///
  /// In he, this message translates to:
  /// **'אלה הכי קרובות למה שחיפשת 👇'**
  String get searchChatScreen3a89ba73;

  /// No description provided for @searchChatScreen94ee5876.
  ///
  /// In he, this message translates to:
  /// **'מצאתי {count} דירות שמתאימות לך 🎯'**
  String searchChatScreen94ee5876(Object count);

  /// No description provided for @searchChatScreenA5a08a80.
  ///
  /// In he, this message translates to:
  /// **'מצאתי {count} שמתאימות בול, והוספתי עוד קרובות '**
  String searchChatScreenA5a08a80(Object count);

  /// No description provided for @searchChatScreen19e1fa38.
  ///
  /// In he, this message translates to:
  /// **'כדי שיהיה ממה לבחור 👇'**
  String get searchChatScreen19e1fa38;

  /// No description provided for @searchChatScreen642c3ded.
  ///
  /// In he, this message translates to:
  /// **'דירגתי כל דירה לפי ציון רב-ממדי — תמורה למחיר, מיקום, '**
  String get searchChatScreen642c3ded;

  /// No description provided for @searchChatScreenB35c8d26.
  ///
  /// In he, this message translates to:
  /// **'קרבה לתחבורה ובטיחות — והצפתי את ההתאמות הטובות ביותר.'**
  String get searchChatScreenB35c8d26;

  /// No description provided for @searchChatScreen316236bf.
  ///
  /// In he, this message translates to:
  /// **'כך בחרתי: שקללתי בעיקר '**
  String get searchChatScreen316236bf;

  /// No description provided for @searchChatScreen5c0f04c1.
  ///
  /// In he, this message translates to:
  /// **'תמורה למחיר ומיקום'**
  String get searchChatScreen5c0f04c1;

  /// No description provided for @searchChatScreenEcd67fb1.
  ///
  /// In he, this message translates to:
  /// **' על בסיס נתוני אמת. '**
  String get searchChatScreenEcd67fb1;

  /// No description provided for @searchChatScreenB3622b1e.
  ///
  /// In he, this message translates to:
  /// **'התאמתי גם להעדפות שלך — {reason}. '**
  String searchChatScreenB3622b1e(Object reason);

  /// No description provided for @searchChatScreen2b144437.
  ///
  /// In he, this message translates to:
  /// **'בראש הרשימה {percent}% התאמה'**
  String searchChatScreen2b144437(Object percent);

  /// No description provided for @searchChatScreenE9fe38e7.
  ///
  /// In he, this message translates to:
  /// **'. הקש \"למה זו?\" על כל דירה לפירוט המלא.'**
  String get searchChatScreenE9fe38e7;

  /// No description provided for @searchChatScreenE7d0c3b9.
  ///
  /// In he, this message translates to:
  /// **'{head} ו{last}'**
  String searchChatScreenE7d0c3b9(Object head, Object last);

  /// No description provided for @searchChatScreen121302b1.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חדרים'**
  String searchChatScreen121302b1(Object rooms);

  /// No description provided for @searchChatScreenD2776ad7.
  ///
  /// In he, this message translates to:
  /// **'ב{city}'**
  String searchChatScreenD2776ad7(Object city);

  /// No description provided for @searchChatScreen74c3e44d.
  ///
  /// In he, this message translates to:
  /// **'הבנתי 😊'**
  String get searchChatScreen74c3e44d;

  /// No description provided for @searchChatScreen034ce5a9.
  ///
  /// In he, this message translates to:
  /// **'מעולה, קלטתי'**
  String get searchChatScreen034ce5a9;

  /// No description provided for @searchChatScreen09cbbf65.
  ///
  /// In he, this message translates to:
  /// **'אחלה, הבנתי'**
  String get searchChatScreen09cbbf65;

  /// No description provided for @searchChatScreen8135ce70.
  ///
  /// In he, this message translates to:
  /// **'סבבה, הבנתי'**
  String get searchChatScreen8135ce70;

  /// No description provided for @searchChatScreen62cb3d3d.
  ///
  /// In he, this message translates to:
  /// **'{opener}. בודקת מה הכי מתאים לך 👇'**
  String searchChatScreen62cb3d3d(Object opener);

  /// No description provided for @searchChatScreen22a8276a.
  ///
  /// In he, this message translates to:
  /// **'{opener} — {summary}. בודקת מה הכי מתאים לך 👇'**
  String searchChatScreen22a8276a(Object opener, Object summary);

  /// No description provided for @searchChatScreen344ff8c5.
  ///
  /// In he, this message translates to:
  /// **'מה הכי חשוב לכם — קרבה לגנים ובתי ספר, ממ״ד, או שקט?'**
  String get searchChatScreen344ff8c5;

  /// No description provided for @searchChatScreen25af8375.
  ///
  /// In he, this message translates to:
  /// **'מעדיפ/ה דירת שותפים או משהו לבד? וכמה קריטית הקרבה לאוניברסיטה?'**
  String get searchChatScreen25af8375;

  /// No description provided for @searchChatScreen4729c6ea.
  ///
  /// In he, this message translates to:
  /// **'זו השקעה לשכירות או לקנייה? ומה הכי חשוב לך בתשואה?'**
  String get searchChatScreen4729c6ea;

  /// No description provided for @searchChatScreenDe6c778e.
  ///
  /// In he, this message translates to:
  /// **'חשוב מעלית וקומה נמוכה? וקרבה לשירותי בריאות?'**
  String get searchChatScreenDe6c778e;

  /// No description provided for @searchChatScreen1a7921f2.
  ///
  /// In he, this message translates to:
  /// **'צריך חדר עבודה נפרד ושקט? ואינטרנט מהיר?'**
  String get searchChatScreen1a7921f2;

  /// No description provided for @searchChatScreen6f0e9087.
  ///
  /// In he, this message translates to:
  /// **'חשוב לכם קרבה לבית כנסת ולמוסדות שמתאימים לכם?'**
  String get searchChatScreen6f0e9087;

  /// No description provided for @searchChatScreenB7874897.
  ///
  /// In he, this message translates to:
  /// **'מה עוד חשוב לך — אווירת שכונה, קומה, או משהו ספציפי בדירה?'**
  String get searchChatScreenB7874897;

  /// No description provided for @searchChatScreenD3cb993d.
  ///
  /// In he, this message translates to:
  /// **'באיזה אזור לחפש?'**
  String get searchChatScreenD3cb993d;

  /// No description provided for @searchChatScreen61710995.
  ///
  /// In he, this message translates to:
  /// **'המיקום קובע כמעט הכל.'**
  String get searchChatScreen61710995;

  /// No description provided for @searchChatScreen2c1f2bbd.
  ///
  /// In he, this message translates to:
  /// **'תל אביב'**
  String get searchChatScreen2c1f2bbd;

  /// No description provided for @searchChatScreen8e0dfe1e.
  ///
  /// In he, this message translates to:
  /// **'ירושלים'**
  String get searchChatScreen8e0dfe1e;

  /// No description provided for @searchChatScreenCa1cc213.
  ///
  /// In he, this message translates to:
  /// **'חיפה'**
  String get searchChatScreenCa1cc213;

  /// No description provided for @searchChatScreenF3acedbf.
  ///
  /// In he, this message translates to:
  /// **'מרכז/השרון'**
  String get searchChatScreenF3acedbf;

  /// No description provided for @searchChatScreen35529032.
  ///
  /// In he, this message translates to:
  /// **'באר שבע'**
  String get searchChatScreen35529032;

  /// No description provided for @searchChatScreen8c19300f.
  ///
  /// In he, this message translates to:
  /// **'תקציב חודשי מקסימלי?'**
  String get searchChatScreen8c19300f;

  /// No description provided for @searchChatScreenDd0caf20.
  ///
  /// In he, this message translates to:
  /// **'שאראה רק דירות אפשריות.'**
  String get searchChatScreenDd0caf20;

  /// No description provided for @searchChatScreen1dc1a458.
  ///
  /// In he, this message translates to:
  /// **'עד 4,000'**
  String get searchChatScreen1dc1a458;

  /// No description provided for @searchChatScreenBbdaa418.
  ///
  /// In he, this message translates to:
  /// **'מעל 9,000'**
  String get searchChatScreenBbdaa418;

  /// No description provided for @searchChatScreen5e0214d0.
  ///
  /// In he, this message translates to:
  /// **'מי גר בדירה?'**
  String get searchChatScreen5e0214d0;

  /// No description provided for @searchChatScreen27e52fe1.
  ///
  /// In he, this message translates to:
  /// **'קובע כמה חדרים וצרכים בשכונה.'**
  String get searchChatScreen27e52fe1;

  /// No description provided for @searchChatScreenCaef6ad4.
  ///
  /// In he, this message translates to:
  /// **'לבד'**
  String get searchChatScreenCaef6ad4;

  /// No description provided for @searchChatScreen4df994d0.
  ///
  /// In he, this message translates to:
  /// **'זוג'**
  String get searchChatScreen4df994d0;

  /// No description provided for @searchChatScreen52204c3c.
  ///
  /// In he, this message translates to:
  /// **'משפחה עם ילדים'**
  String get searchChatScreen52204c3c;

  /// No description provided for @searchChatScreenB5c68bd1.
  ///
  /// In he, this message translates to:
  /// **'שותפים'**
  String get searchChatScreenB5c68bd1;

  /// No description provided for @searchChatScreenEe542324.
  ///
  /// In he, this message translates to:
  /// **'הכי חשוב לך בדירה?'**
  String get searchChatScreenEe542324;

  /// No description provided for @searchChatScreenB86b9b16.
  ///
  /// In he, this message translates to:
  /// **'זה מה שידחוף את ההצעות הנכונות למעלה.'**
  String get searchChatScreenB86b9b16;

  /// No description provided for @searchChatScreenAb3f526d.
  ///
  /// In he, this message translates to:
  /// **'מיקום מרכזי'**
  String get searchChatScreenAb3f526d;

  /// No description provided for @searchChatScreen40d07087.
  ///
  /// In he, this message translates to:
  /// **'שקט'**
  String get searchChatScreen40d07087;

  /// No description provided for @searchChatScreen4e515b14.
  ///
  /// In he, this message translates to:
  /// **'תמורה למחיר'**
  String get searchChatScreen4e515b14;

  /// No description provided for @searchChatScreen68579629.
  ///
  /// In he, this message translates to:
  /// **'דירה מרווחת'**
  String get searchChatScreen68579629;

  /// No description provided for @searchChatScreenCd73f9c6.
  ///
  /// In he, this message translates to:
  /// **'קרוב לעבודה'**
  String get searchChatScreenCd73f9c6;

  /// No description provided for @searchChatScreenC5847f1d.
  ///
  /// In he, this message translates to:
  /// **'כיף, נשמע שיש לך כיוון 🙌 ספר לי עוד קצת — אזור, תקציב, כמה חדרים?'**
  String get searchChatScreenC5847f1d;

  /// No description provided for @searchChatScreenE6d0829f.
  ///
  /// In he, this message translates to:
  /// **'הבנתי אותך. מה הכי חשוב לך בדירה או בשכונה?'**
  String get searchChatScreenE6d0829f;

  /// No description provided for @searchChatScreenC752e50e.
  ///
  /// In he, this message translates to:
  /// **'אהבתי. רוצה שאראה לך כבר כמה אפשרויות, או שנחדד עוד קצת?'**
  String get searchChatScreenC752e50e;

  /// No description provided for @searchChatScreen258a50bf.
  ///
  /// In he, this message translates to:
  /// **'עד ₪{price}'**
  String searchChatScreen258a50bf(Object price);

  /// No description provided for @searchChatScreenF83283b7.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חדרים'**
  String searchChatScreenF83283b7(Object rooms);

  /// No description provided for @searchChatScreen63cd0477.
  ///
  /// In he, this message translates to:
  /// **'עם חניה'**
  String get searchChatScreen63cd0477;

  /// No description provided for @searchChatScreenEe07d486.
  ///
  /// In he, this message translates to:
  /// **'קרוב לרכבת'**
  String get searchChatScreenEe07d486;

  /// No description provided for @searchChatScreen706598a7.
  ///
  /// In he, this message translates to:
  /// **'עם מעלית'**
  String get searchChatScreen706598a7;

  /// No description provided for @searchChatScreenE6452825.
  ///
  /// In he, this message translates to:
  /// **'✨ כן, בוא נדייק'**
  String get searchChatScreenE6452825;

  /// No description provided for @searchChatScreen113aa61a.
  ///
  /// In he, this message translates to:
  /// **'זה מצוין, תודה'**
  String get searchChatScreen113aa61a;

  /// No description provided for @searchChatScreen391e982f.
  ///
  /// In he, this message translates to:
  /// **'מעולה 😊 מה נדייק כדי לצמצם למה שהכי מתאים לך?'**
  String get searchChatScreen391e982f;

  /// No description provided for @searchChatScreenD51433d2.
  ///
  /// In he, this message translates to:
  /// **'מקסים! 🙏 אם תרצה לחדד עוד משהו בהמשך — אני כאן.'**
  String get searchChatScreenD51433d2;

  /// No description provided for @searchChatScreen8b097eb6.
  ///
  /// In he, this message translates to:
  /// **'רוצה עוד אפשרויות מתאימות? נסה לשנות אחד מאלה 👇'**
  String get searchChatScreen8b097eb6;

  /// No description provided for @searchChatScreenC911128e.
  ///
  /// In he, this message translates to:
  /// **'כ-{km} ק״מ מ{city}'**
  String searchChatScreenC911128e(Object city, Object km);

  /// No description provided for @searchChatScreen2820c4fe.
  ///
  /// In he, this message translates to:
  /// **'מעט מעל התקציב'**
  String get searchChatScreen2820c4fe;

  /// No description provided for @searchChatScreen55112a73.
  ///
  /// In he, this message translates to:
  /// **'הרחבתי קצת את התקציב'**
  String get searchChatScreen55112a73;

  /// No description provided for @searchChatScreen917c8977.
  ///
  /// In he, this message translates to:
  /// **'הרחבתי תקציב וויתרתי על חלק מהדרישות'**
  String get searchChatScreen917c8977;

  /// No description provided for @searchChatScreen0b5b99ea.
  ///
  /// In he, this message translates to:
  /// **'לא נמצא בדיוק בעיר הזו — הנה הכי קרוב באזורים אחרים'**
  String get searchChatScreen0b5b99ea;

  /// No description provided for @searchChatScreenB6601495.
  ///
  /// In he, this message translates to:
  /// **'חילוני'**
  String get searchChatScreenB6601495;

  /// No description provided for @searchChatScreen50cb5eda.
  ///
  /// In he, this message translates to:
  /// **'מסורתי'**
  String get searchChatScreen50cb5eda;

  /// No description provided for @searchChatScreen21c1f153.
  ///
  /// In he, this message translates to:
  /// **'דתי'**
  String get searchChatScreen21c1f153;

  /// No description provided for @searchChatScreenFed27efc.
  ///
  /// In he, this message translates to:
  /// **'חרדי'**
  String get searchChatScreenFed27efc;

  /// No description provided for @searchChatScreenA4b6a21f.
  ///
  /// In he, this message translates to:
  /// **'נתתי עדיפות לאזורים שמתאימים לאורח חיים {lifestyle}'**
  String searchChatScreenA4b6a21f(Object lifestyle);

  /// No description provided for @searchChatScreen85c47725.
  ///
  /// In he, this message translates to:
  /// **'ודילגתי על קומות גבוהות בלי מעלית 🛗'**
  String get searchChatScreen85c47725;

  /// No description provided for @searchChatScreen567bc622.
  ///
  /// In he, this message translates to:
  /// **'שמתי לב לכמה דברים: {details}.'**
  String searchChatScreen567bc622(Object details);

  /// No description provided for @searchChatScreenE3396557.
  ///
  /// In he, this message translates to:
  /// **'באיזה אזור או עיר לחפש?'**
  String get searchChatScreenE3396557;

  /// No description provided for @searchChatScreen3afe34bd.
  ///
  /// In he, this message translates to:
  /// **'מרכז'**
  String get searchChatScreen3afe34bd;

  /// No description provided for @searchChatScreen73d294f3.
  ///
  /// In he, this message translates to:
  /// **'מה התקציב החודשי שלך?'**
  String get searchChatScreen73d294f3;

  /// No description provided for @searchChatScreen808024f5.
  ///
  /// In he, this message translates to:
  /// **'עד ₪5,000'**
  String get searchChatScreen808024f5;

  /// No description provided for @searchChatScreenBe87f690.
  ///
  /// In he, this message translates to:
  /// **'עד ₪7,000'**
  String get searchChatScreenBe87f690;

  /// No description provided for @searchChatScreenAe2323e0.
  ///
  /// In he, this message translates to:
  /// **'עד ₪9,000'**
  String get searchChatScreenAe2323e0;

  /// No description provided for @searchChatScreen88a8e951.
  ///
  /// In he, this message translates to:
  /// **'כמה חדרים אתם צריכים?'**
  String get searchChatScreen88a8e951;

  /// No description provided for @searchChatScreen1f57228c.
  ///
  /// In he, this message translates to:
  /// **'2 חדרים'**
  String get searchChatScreen1f57228c;

  /// No description provided for @searchChatScreen535bb0c7.
  ///
  /// In he, this message translates to:
  /// **'3 חדרים'**
  String get searchChatScreen535bb0c7;

  /// No description provided for @searchChatScreen0c3da33f.
  ///
  /// In he, this message translates to:
  /// **'4 חדרים'**
  String get searchChatScreen0c3da33f;

  /// No description provided for @searchChatScreen32cd7c3b.
  ///
  /// In he, this message translates to:
  /// **'רוצה שאזכור את ההעדפות שלך כדי לדייק לך עוד יותר בפעם הבאה? '**
  String get searchChatScreen32cd7c3b;

  /// No description provided for @searchChatScreenD5b92b5a.
  ///
  /// In he, this message translates to:
  /// **'הכל מאובטח, ותמיד אפשר לבטל. 💙'**
  String get searchChatScreenD5b92b5a;

  /// No description provided for @searchChatScreenB2d293af.
  ///
  /// In he, this message translates to:
  /// **'מעולה, תודה! מבטיחה לשמור על זה 🙌'**
  String get searchChatScreenB2d293af;

  /// No description provided for @searchChatScreenB00e7ac4.
  ///
  /// In he, this message translates to:
  /// **'אין בעיה בכלל, נמשיך ככה. 🙂'**
  String get searchChatScreenB00e7ac4;

  /// No description provided for @searchChatScreenFaae8713.
  ///
  /// In he, this message translates to:
  /// **'תבדוק אותי אם אני באמת עוזרת חכמה'**
  String get searchChatScreenFaae8713;

  /// No description provided for @searchChatScreen82c40bcf.
  ///
  /// In he, this message translates to:
  /// **'שיחה חדשה'**
  String get searchChatScreen82c40bcf;

  /// No description provided for @searchChatScreen39e281e5.
  ///
  /// In he, this message translates to:
  /// **'שתף את המיקום שלי'**
  String get searchChatScreen39e281e5;

  /// No description provided for @searchChatScreenFab66f7b.
  ///
  /// In he, this message translates to:
  /// **'אין בעיה — באיזו עיר או אזור לחפש?'**
  String get searchChatScreenFab66f7b;

  /// No description provided for @searchChatScreen542039da.
  ///
  /// In he, this message translates to:
  /// **'אגיד עיר'**
  String get searchChatScreen542039da;

  /// No description provided for @searchChatScreen10289345.
  ///
  /// In he, this message translates to:
  /// **'כן, בשמחה'**
  String get searchChatScreen10289345;

  /// No description provided for @searchChatScreen98c8a5b8.
  ///
  /// In he, this message translates to:
  /// **'לא עכשיו'**
  String get searchChatScreen98c8a5b8;

  /// No description provided for @searchChatScreenD5d02271.
  ///
  /// In he, this message translates to:
  /// **'ספר לי במילים שלך...'**
  String get searchChatScreenD5d02271;

  /// No description provided for @searchChatScreen7de9ac58.
  ///
  /// In he, this message translates to:
  /// **'מאומת'**
  String get searchChatScreen7de9ac58;

  /// No description provided for @searchChatScreenF0f71ca3.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חדרים'**
  String searchChatScreenF0f71ca3(Object rooms);

  /// No description provided for @searchChatScreen615d28b8.
  ///
  /// In he, this message translates to:
  /// **'{size} מ״ר'**
  String searchChatScreen615d28b8(Object size);

  /// No description provided for @areaIntelScreen88218ec9.
  ///
  /// In he, this message translates to:
  /// **'לא הצלחתי לאתר את הכתובת. נסה לבחור מההשלמה או לכתוב עיר + רחוב.'**
  String get areaIntelScreen88218ec9;

  /// No description provided for @areaIntelScreen91db7436.
  ///
  /// In he, this message translates to:
  /// **'תחבורה ציבורית'**
  String get areaIntelScreen91db7436;

  /// No description provided for @areaIntelScreenFa8c72dc.
  ///
  /// In he, this message translates to:
  /// **'בתי ספר'**
  String get areaIntelScreenFa8c72dc;

  /// No description provided for @areaIntelScreen00a5eaf2.
  ///
  /// In he, this message translates to:
  /// **'גני ילדים'**
  String get areaIntelScreen00a5eaf2;

  /// No description provided for @areaIntelScreen088f0923.
  ///
  /// In he, this message translates to:
  /// **'פארקים וגינות'**
  String get areaIntelScreen088f0923;

  /// No description provided for @areaIntelScreen9bd0d581.
  ///
  /// In he, this message translates to:
  /// **'בתי קפה ומסעדות'**
  String get areaIntelScreen9bd0d581;

  /// No description provided for @areaIntelScreen56721218.
  ///
  /// In he, this message translates to:
  /// **'סופרמרקטים וקניות'**
  String get areaIntelScreen56721218;

  /// No description provided for @areaIntelScreen9df69324.
  ///
  /// In he, this message translates to:
  /// **'שירותי בריאות'**
  String get areaIntelScreen9df69324;

  /// No description provided for @areaIntelScreen82e78f66.
  ///
  /// In he, this message translates to:
  /// **'בתי מרקחת'**
  String get areaIntelScreen82e78f66;

  /// No description provided for @areaIntelScreen22f8b507.
  ///
  /// In he, this message translates to:
  /// **'חדרי כושר וספורט'**
  String get areaIntelScreen22f8b507;

  /// No description provided for @areaIntelScreen34df4e2b.
  ///
  /// In he, this message translates to:
  /// **'בתי כנסת ותפילה'**
  String get areaIntelScreen34df4e2b;

  /// No description provided for @areaIntelScreen39cfcba7.
  ///
  /// In he, this message translates to:
  /// **'תרבות ופנאי'**
  String get areaIntelScreen39cfcba7;

  /// No description provided for @areaIntelScreen289b784a.
  ///
  /// In he, this message translates to:
  /// **'גני משחקים'**
  String get areaIntelScreen289b784a;

  /// No description provided for @areaIntelScreenDcabfe76.
  ///
  /// In he, this message translates to:
  /// **'{meters} מ׳'**
  String areaIntelScreenDcabfe76(Object meters);

  /// No description provided for @areaIntelScreen0b2db321.
  ///
  /// In he, this message translates to:
  /// **'{km} ק״מ'**
  String areaIntelScreen0b2db321(Object km);

  /// No description provided for @areaIntelScreenA8bb0310.
  ///
  /// In he, this message translates to:
  /// **'אינטליגנציית אזור'**
  String get areaIntelScreenA8bb0310;

  /// No description provided for @areaIntelScreen51957dd6.
  ///
  /// In he, this message translates to:
  /// **'דרג את כל האזורים בעיר לפי קהל יעד'**
  String get areaIntelScreen51957dd6;

  /// No description provided for @areaIntelScreen3fb539f2.
  ///
  /// In he, this message translates to:
  /// **'עדשת השקעה'**
  String get areaIntelScreen3fb539f2;

  /// No description provided for @areaIntelScreen93a4e30a.
  ///
  /// In he, this message translates to:
  /// **'כל שכבות הנתונים במקום'**
  String get areaIntelScreen93a4e30a;

  /// No description provided for @areaIntelScreenE752c7da.
  ///
  /// In he, this message translates to:
  /// **'מה יש בסביבה'**
  String get areaIntelScreenE752c7da;

  /// No description provided for @areaIntelScreen311b60d7.
  ///
  /// In he, this message translates to:
  /// **'הזן כתובת לבדיקת השקעה — ואקבל את כל הנתונים והשכבות של האזור, '**
  String get areaIntelScreen311b60d7;

  /// No description provided for @areaIntelScreenFd7780b1.
  ///
  /// In he, this message translates to:
  /// **'ולמי הוא הכי מתאים. ככה תדע בדיוק איזה קהל לחפש ומה חוזק המקום.'**
  String get areaIntelScreenFd7780b1;

  /// No description provided for @areaIntelScreen863d9b56.
  ///
  /// In he, this message translates to:
  /// **'כתובת: עיר + רחוב (למשל: תל אביב, דיזנגוף 100)'**
  String get areaIntelScreen863d9b56;

  /// No description provided for @areaIntelScreen0d4d229d.
  ///
  /// In he, this message translates to:
  /// **'נתח'**
  String get areaIntelScreen0d4d229d;

  /// No description provided for @areaIntelScreen65430ae4.
  ///
  /// In he, this message translates to:
  /// **'{pct}% התאמה'**
  String areaIntelScreen65430ae4(Object pct);

  /// No description provided for @areaIntelScreen046ea325.
  ///
  /// In he, this message translates to:
  /// **'האזור פחות מתאים לקהל הזה.'**
  String get areaIntelScreen046ea325;

  /// No description provided for @areaIntelScreen4e635cc2.
  ///
  /// In he, this message translates to:
  /// **'למה זה עובד לקהל הזה:'**
  String get areaIntelScreen4e635cc2;

  /// No description provided for @areaIntelScreen77eb6f43.
  ///
  /// In he, this message translates to:
  /// **'ציון השקעה'**
  String get areaIntelScreen77eb6f43;

  /// No description provided for @areaIntelScreenDa192a5e.
  ///
  /// In he, this message translates to:
  /// **'ביקוש שכירות (קלות השכרה)'**
  String get areaIntelScreenDa192a5e;

  /// No description provided for @areaIntelScreen7c498f0a.
  ///
  /// In he, this message translates to:
  /// **'פוטנציאל השבחה (תשתית מתוכננת)'**
  String get areaIntelScreen7c498f0a;

  /// No description provided for @areaIntelScreen9e3fdc13.
  ///
  /// In he, this message translates to:
  /// **'רמת מחירים באזור (יחסי)'**
  String get areaIntelScreen9e3fdc13;

  /// No description provided for @areaIntelScreenB5585865.
  ///
  /// In he, this message translates to:
  /// **'הערכת תשואה ברוטו'**
  String get areaIntelScreenB5585865;

  /// No description provided for @areaIntelScreenA1448f5a.
  ///
  /// In he, this message translates to:
  /// **'רמת המחירים מבוססת על שווי הלמ״ס 2013 (₪{value}/מ״ר) — מדד יחסי; התשואה הערכה גסה בלבד.'**
  String areaIntelScreenA1448f5a(Object value);

  /// No description provided for @areaIntelScreen9b04c59d.
  ///
  /// In he, this message translates to:
  /// **'ביקוש והשבחה מנתונים עדכניים. אין נתוני שווי לאזור זה.'**
  String get areaIntelScreen9b04c59d;

  /// No description provided for @areaIntelScreen96921b94.
  ///
  /// In he, this message translates to:
  /// **'אשכול סוציו-אקונומי (בלוק)'**
  String get areaIntelScreen96921b94;

  /// No description provided for @areaIntelScreen45ddda67.
  ///
  /// In he, this message translates to:
  /// **'בטיחות (ברמת העיר)'**
  String get areaIntelScreen45ddda67;

  /// No description provided for @areaIntelScreen096a70c8.
  ///
  /// In he, this message translates to:
  /// **'מרכזיות'**
  String get areaIntelScreen096a70c8;

  /// No description provided for @areaIntelScreen984afc87.
  ///
  /// In he, this message translates to:
  /// **'מוסדות חינוך'**
  String get areaIntelScreen984afc87;

  /// No description provided for @areaIntelScreenFae76235.
  ///
  /// In he, this message translates to:
  /// **'חיי לילה ובילוי'**
  String get areaIntelScreenFae76235;

  /// No description provided for @areaIntelScreenA70625cf.
  ///
  /// In he, this message translates to:
  /// **'קרבה לתעסוקה'**
  String get areaIntelScreenA70625cf;

  /// No description provided for @areaIntelScreenB005f878.
  ///
  /// In he, this message translates to:
  /// **'פארקים וירוק'**
  String get areaIntelScreenB005f878;

  /// No description provided for @areaIntelScreen2008eaf1.
  ///
  /// In he, this message translates to:
  /// **'פוטנציאל השבחה'**
  String get areaIntelScreen2008eaf1;

  /// No description provided for @areaIntelScreenE5c70865.
  ///
  /// In he, this message translates to:
  /// **'{cluster} מתוך 10'**
  String areaIntelScreenE5c70865(Object cluster);

  /// No description provided for @areaIntelScreen459fac16.
  ///
  /// In he, this message translates to:
  /// **'נתוני דמוגרפיה אינם זמינים לאזור זה'**
  String get areaIntelScreen459fac16;

  /// No description provided for @areaIntelScreen4089ef4b.
  ///
  /// In he, this message translates to:
  /// **'👶 ילדים (0-19)'**
  String get areaIntelScreen4089ef4b;

  /// No description provided for @areaIntelScreen4d2868ec.
  ///
  /// In he, this message translates to:
  /// **'🧑 עובדים (20-64)'**
  String get areaIntelScreen4d2868ec;

  /// No description provided for @areaIntelScreen3fcced86.
  ///
  /// In he, this message translates to:
  /// **'+ {hidden} נוספים · הצג הכל'**
  String areaIntelScreen3fcced86(Object hidden);

  /// No description provided for @areaIntelScreen6192614d.
  ///
  /// In he, this message translates to:
  /// **'הצג פחות'**
  String get areaIntelScreen6192614d;

  /// No description provided for @searchAssistantScreen2c1f2bbd.
  ///
  /// In he, this message translates to:
  /// **'תל אביב'**
  String get searchAssistantScreen2c1f2bbd;

  /// No description provided for @searchAssistantScreen8e0dfe1e.
  ///
  /// In he, this message translates to:
  /// **'ירושלים'**
  String get searchAssistantScreen8e0dfe1e;

  /// No description provided for @searchAssistantScreen2231ce66.
  ///
  /// In he, this message translates to:
  /// **'רמת גן'**
  String get searchAssistantScreen2231ce66;

  /// No description provided for @searchAssistantScreenEa980134.
  ///
  /// In he, this message translates to:
  /// **'גבעתיים'**
  String get searchAssistantScreenEa980134;

  /// No description provided for @searchAssistantScreenCa1cc213.
  ///
  /// In he, this message translates to:
  /// **'חיפה'**
  String get searchAssistantScreenCa1cc213;

  /// No description provided for @searchAssistantScreen092b4640.
  ///
  /// In he, this message translates to:
  /// **'נתניה'**
  String get searchAssistantScreen092b4640;

  /// No description provided for @searchAssistantScreen982e0598.
  ///
  /// In he, this message translates to:
  /// **'הרצליה'**
  String get searchAssistantScreen982e0598;

  /// No description provided for @searchAssistantScreen35529032.
  ///
  /// In he, this message translates to:
  /// **'באר שבע'**
  String get searchAssistantScreen35529032;

  /// No description provided for @searchAssistantScreenA9655ab3.
  ///
  /// In he, this message translates to:
  /// **'חניה'**
  String get searchAssistantScreenA9655ab3;

  /// No description provided for @searchAssistantScreen86425fcf.
  ///
  /// In he, this message translates to:
  /// **'מרפסת'**
  String get searchAssistantScreen86425fcf;

  /// No description provided for @searchAssistantScreen8d058056.
  ///
  /// In he, this message translates to:
  /// **'מעלית'**
  String get searchAssistantScreen8d058056;

  /// No description provided for @searchAssistantScreenD8e1feaf.
  ///
  /// In he, this message translates to:
  /// **'מרוהט'**
  String get searchAssistantScreenD8e1feaf;

  /// No description provided for @searchAssistantScreenFa8ed531.
  ///
  /// In he, this message translates to:
  /// **'ממ״ד'**
  String get searchAssistantScreenFa8ed531;

  /// No description provided for @searchAssistantScreen0bd4e294.
  ///
  /// In he, this message translates to:
  /// **'משופצת'**
  String get searchAssistantScreen0bd4e294;

  /// No description provided for @searchAssistantScreen27a4567b.
  ///
  /// In he, this message translates to:
  /// **'גינה'**
  String get searchAssistantScreen27a4567b;

  /// No description provided for @searchAssistantScreen40d07087.
  ///
  /// In he, this message translates to:
  /// **'שקט'**
  String get searchAssistantScreen40d07087;

  /// No description provided for @searchAssistantScreen07199e40.
  ///
  /// In he, this message translates to:
  /// **'תוסס'**
  String get searchAssistantScreen07199e40;

  /// No description provided for @searchAssistantScreen23625e37.
  ///
  /// In he, this message translates to:
  /// **'משפחתי'**
  String get searchAssistantScreen23625e37;

  /// No description provided for @searchAssistantScreenC7b03503.
  ///
  /// In he, this message translates to:
  /// **'סטודנטיאלי'**
  String get searchAssistantScreenC7b03503;

  /// No description provided for @searchAssistantScreenE16edce8.
  ///
  /// In he, this message translates to:
  /// **'עוזר חיפוש חכם'**
  String get searchAssistantScreenE16edce8;

  /// No description provided for @searchAssistantScreen6e04f4e9.
  ///
  /// In he, this message translates to:
  /// **'התחל מחדש'**
  String get searchAssistantScreen6e04f4e9;

  /// No description provided for @searchAssistantScreen3c34563c.
  ///
  /// In he, this message translates to:
  /// **'בוא נמצא לך דירה מושלמת! איפה אתה מחפש, ומה התקציב החודשי?'**
  String get searchAssistantScreen3c34563c;

  /// No description provided for @searchAssistantScreenB2136c90.
  ///
  /// In he, this message translates to:
  /// **'עיר'**
  String get searchAssistantScreenB2136c90;

  /// No description provided for @searchAssistantScreen4094ac8d.
  ///
  /// In he, this message translates to:
  /// **'תקציב חודשי'**
  String get searchAssistantScreen4094ac8d;

  /// No description provided for @searchAssistantScreen4ca22f8c.
  ///
  /// In he, this message translates to:
  /// **'הבא →'**
  String get searchAssistantScreen4ca22f8c;

  /// No description provided for @searchAssistantScreen9c507ba2.
  ///
  /// In he, this message translates to:
  /// **'כמה מקום אתה צריך, ומה חובה שיהיה?'**
  String get searchAssistantScreen9c507ba2;

  /// No description provided for @searchAssistantScreen5c2ad42a.
  ///
  /// In he, this message translates to:
  /// **'מספר חדרים (מינימום)'**
  String get searchAssistantScreen5c2ad42a;

  /// No description provided for @searchAssistantScreen49bd69db.
  ///
  /// In he, this message translates to:
  /// **'מתקנים שחובה שיהיו'**
  String get searchAssistantScreen49bd69db;

  /// No description provided for @searchAssistantScreenDb600ba2.
  ///
  /// In he, this message translates to:
  /// **'כמעט סיימנו! איזו אווירת שכונה מתאימה לך?'**
  String get searchAssistantScreenDb600ba2;

  /// No description provided for @searchAssistantScreen4e4d5acc.
  ///
  /// In he, this message translates to:
  /// **'אופי השכונה'**
  String get searchAssistantScreen4e4d5acc;

  /// No description provided for @searchAssistantScreen892418bd.
  ///
  /// In he, this message translates to:
  /// **'סקירה →'**
  String get searchAssistantScreen892418bd;

  /// No description provided for @searchAssistantScreen815a16e3.
  ///
  /// In he, this message translates to:
  /// **'מעולה! זה מה שאספתי. מוכן לחפש?'**
  String get searchAssistantScreen815a16e3;

  /// No description provided for @searchAssistantScreen5f8fb8a5.
  ///
  /// In he, this message translates to:
  /// **'הכל'**
  String get searchAssistantScreen5f8fb8a5;

  /// No description provided for @searchAssistantScreen3bb32ddd.
  ///
  /// In he, this message translates to:
  /// **'תקציב'**
  String get searchAssistantScreen3bb32ddd;

  /// No description provided for @searchAssistantScreenB50b3974.
  ///
  /// In he, this message translates to:
  /// **'חדרים'**
  String get searchAssistantScreenB50b3974;

  /// No description provided for @searchAssistantScreen9ff887ff.
  ///
  /// In he, this message translates to:
  /// **'מתקנים'**
  String get searchAssistantScreen9ff887ff;

  /// No description provided for @searchAssistantScreen1212caa6.
  ///
  /// In he, this message translates to:
  /// **'אווירה'**
  String get searchAssistantScreen1212caa6;

  /// No description provided for @searchAssistantScreen5a7196d6.
  ///
  /// In he, this message translates to:
  /// **'🔍 חפש עכשיו'**
  String get searchAssistantScreen5a7196d6;

  /// No description provided for @searchAssistantScreenD742723c.
  ///
  /// In he, this message translates to:
  /// **'מחפש דירות תואמות...'**
  String get searchAssistantScreenD742723c;

  /// No description provided for @searchAssistantScreenCf4d2620.
  ///
  /// In he, this message translates to:
  /// **'לא נמצאו דירות שתואמות'**
  String get searchAssistantScreenCf4d2620;

  /// No description provided for @searchAssistantScreen284a2e22.
  ///
  /// In he, this message translates to:
  /// **'נסה להרחיב את התקציב או להסיר מתקנים'**
  String get searchAssistantScreen284a2e22;

  /// No description provided for @searchAssistantScreen231c0d9b.
  ///
  /// In he, this message translates to:
  /// **'שנה חיפוש'**
  String get searchAssistantScreen231c0d9b;

  /// No description provided for @searchAssistantScreen1b999b46.
  ///
  /// In he, this message translates to:
  /// **'נמצאו {count} דירות'**
  String searchAssistantScreen1b999b46(Object count);

  /// No description provided for @searchAssistantScreen2b387ae1.
  ///
  /// In he, this message translates to:
  /// **'חיפוש חדש'**
  String get searchAssistantScreen2b387ae1;

  /// No description provided for @searchAssistantScreenC6efa96a.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חד׳'**
  String searchAssistantScreenC6efa96a(Object rooms);

  /// No description provided for @searchAssistantScreen7de9ac58.
  ///
  /// In he, this message translates to:
  /// **'מאומת'**
  String get searchAssistantScreen7de9ac58;

  /// No description provided for @contractDetailScreenF5ee57a7.
  ///
  /// In he, this message translates to:
  /// **'חוזה שכירות'**
  String get contractDetailScreenF5ee57a7;

  /// No description provided for @contractDetailScreen32d6e691.
  ///
  /// In he, this message translates to:
  /// **'תצוגה מקדימה של המסמך'**
  String get contractDetailScreen32d6e691;

  /// No description provided for @contractDetailScreen62afb8c6.
  ///
  /// In he, this message translates to:
  /// **'החוזה לא נמצא'**
  String get contractDetailScreen62afb8c6;

  /// No description provided for @contractDetailScreenC6c7d5f7.
  ///
  /// In he, this message translates to:
  /// **'בעל הדירה'**
  String get contractDetailScreenC6c7d5f7;

  /// No description provided for @contractDetailScreen9ad15d69.
  ///
  /// In he, this message translates to:
  /// **'השוכר/ת'**
  String get contractDetailScreen9ad15d69;

  /// No description provided for @contractDetailScreenC426dab3.
  ///
  /// In he, this message translates to:
  /// **'חתום על החוזה כ{role}'**
  String contractDetailScreenC426dab3(Object role);

  /// No description provided for @contractDetailScreenD346f1e3.
  ///
  /// In he, this message translates to:
  /// **'החוזה נחתם על ידי שני הצדדים'**
  String get contractDetailScreenD346f1e3;

  /// No description provided for @contractDetailScreenD657b4d3.
  ///
  /// In he, this message translates to:
  /// **'החוזה נדחה'**
  String get contractDetailScreenD657b4d3;

  /// No description provided for @contractDetailScreen2f6e4f0e.
  ///
  /// In he, this message translates to:
  /// **'החוזה בוטל'**
  String get contractDetailScreen2f6e4f0e;

  /// No description provided for @contractDetailScreen471364ef.
  ///
  /// In he, this message translates to:
  /// **'ממתין לחתימת הצד השני'**
  String get contractDetailScreen471364ef;

  /// No description provided for @contractDetailScreen2d903955.
  ///
  /// In he, this message translates to:
  /// **'ממתין לחתימות'**
  String get contractDetailScreen2d903955;

  /// No description provided for @contractDetailScreen900c3a51.
  ///
  /// In he, this message translates to:
  /// **'נכס להשכרה'**
  String get contractDetailScreen900c3a51;

  /// No description provided for @contractDetailScreen4dcdda0b.
  ///
  /// In he, this message translates to:
  /// **'שכר דירה חודשי'**
  String get contractDetailScreen4dcdda0b;

  /// No description provided for @contractDetailScreen6977f9a2.
  ///
  /// In he, this message translates to:
  /// **'פיקדון'**
  String get contractDetailScreen6977f9a2;

  /// No description provided for @contractDetailScreen5c4ffbbc.
  ///
  /// In he, this message translates to:
  /// **'תקופה'**
  String get contractDetailScreen5c4ffbbc;

  /// No description provided for @contractDetailScreenA68a769b.
  ///
  /// In he, this message translates to:
  /// **'{months} חודשים'**
  String contractDetailScreenA68a769b(Object months);

  /// No description provided for @contractDetailScreen2f6783cd.
  ///
  /// In he, this message translates to:
  /// **'כניסה'**
  String get contractDetailScreen2f6783cd;

  /// No description provided for @contractDetailScreenF600808f.
  ///
  /// In he, this message translates to:
  /// **'סיום'**
  String get contractDetailScreenF600808f;

  /// No description provided for @contractDetailScreen2ef381ab.
  ///
  /// In he, this message translates to:
  /// **'סעיפים נוספים'**
  String get contractDetailScreen2ef381ab;

  /// No description provided for @contractDetailScreen500341b6.
  ///
  /// In he, this message translates to:
  /// **'חתימה דיגיטלית מאובטחת (Ed25519). המפתח הפרטי נשמר במכשיר בלבד; כל שינוי בתנאים מבטל חתימות שכבר נחתמו.'**
  String get contractDetailScreen500341b6;

  /// No description provided for @contractDetailScreen8c7ea078.
  ///
  /// In he, this message translates to:
  /// **'החתימה נשמרה בהצלחה ✍️'**
  String get contractDetailScreen8c7ea078;

  /// No description provided for @contractDetailScreen8b7b9377.
  ///
  /// In he, this message translates to:
  /// **'יש לחתום במסגרת לפני האישור'**
  String get contractDetailScreen8b7b9377;

  /// No description provided for @contractDetailScreenE6dfccf4.
  ///
  /// In he, this message translates to:
  /// **'חתימה דיגיטלית'**
  String get contractDetailScreenE6dfccf4;

  /// No description provided for @contractDetailScreen07debd21.
  ///
  /// In he, this message translates to:
  /// **'חתמו עם האצבע במסגרת למטה'**
  String get contractDetailScreen07debd21;

  /// No description provided for @contractDetailScreenE8b3a3d5.
  ///
  /// In he, this message translates to:
  /// **'נקה'**
  String get contractDetailScreenE8b3a3d5;

  /// No description provided for @contractDetailScreen10d96dc9.
  ///
  /// In he, this message translates to:
  /// **'חותם…'**
  String get contractDetailScreen10d96dc9;

  /// No description provided for @contractDetailScreen9c07f0d2.
  ///
  /// In he, this message translates to:
  /// **'אשר חתימה'**
  String get contractDetailScreen9c07f0d2;

  /// No description provided for @contractDetailScreen711b15ac.
  ///
  /// In he, this message translates to:
  /// **'ממתין לחתימה'**
  String get contractDetailScreen711b15ac;

  /// No description provided for @contractDetailScreenFbf77ab4.
  ///
  /// In he, this message translates to:
  /// **'מאמת…'**
  String get contractDetailScreenFbf77ab4;

  /// No description provided for @contractDetailScreen53a5fab1.
  ///
  /// In he, this message translates to:
  /// **'חתימה מאומתת{dateStr}'**
  String contractDetailScreen53a5fab1(Object dateStr);

  /// No description provided for @contractDetailScreen2c47c991.
  ///
  /// In he, this message translates to:
  /// **'החתימה אינה תקפה'**
  String get contractDetailScreen2c47c991;

  /// No description provided for @contractDetailScreen0db5078d.
  ///
  /// In he, this message translates to:
  /// **'תצוגה מקדימה של החוזה'**
  String get contractDetailScreen0db5078d;

  /// No description provided for @contractDetailScreenA858ff94.
  ///
  /// In he, this message translates to:
  /// **'הסכם שכירות למגורים'**
  String get contractDetailScreenA858ff94;

  /// No description provided for @contractDetailScreenC627c4b8.
  ///
  /// In he, this message translates to:
  /// **'נחתם דיגיטלית · {date}'**
  String contractDetailScreenC627c4b8(Object date);

  /// No description provided for @contractDetailScreen9d6224ee.
  ///
  /// In he, this message translates to:
  /// **'הסכם זה נערך ונחתם בין **{landlordName}** (\"המשכיר\") לבין **{tenantName}** (\"השוכר\"), בנוגע להשכרת הנכס שכתובתו {propertyTitle}.'**
  String contractDetailScreen9d6224ee(
      Object landlordName, Object propertyTitle, Object tenantName);

  /// No description provided for @contractDetailScreenPropTitleFallback.
  ///
  /// In he, this message translates to:
  /// **'המפורט להלן'**
  String get contractDetailScreenPropTitleFallback;

  /// No description provided for @contractDetailScreenAece3836.
  ///
  /// In he, this message translates to:
  /// **'1. דמי השכירות'**
  String get contractDetailScreenAece3836;

  /// No description provided for @contractDetailScreen68bb0d6c.
  ///
  /// In he, this message translates to:
  /// **'השוכר ישלם למשכיר דמי שכירות חודשיים בסך {rent} ₪, אשר ישולמו מראש עד ה-10 בכל חודש.'**
  String contractDetailScreen68bb0d6c(Object rent);

  /// No description provided for @contractDetailScreen00c967a0.
  ///
  /// In he, this message translates to:
  /// **'2. פיקדון'**
  String get contractDetailScreen00c967a0;

  /// No description provided for @contractDetailScreenBa3a4a53.
  ///
  /// In he, this message translates to:
  /// **'השוכר יפקיד בידי המשכיר פיקדון בסך {deposit} ₪ להבטחת קיום התחייבויותיו.'**
  String contractDetailScreenBa3a4a53(Object deposit);

  /// No description provided for @contractDetailScreen9502e7c7.
  ///
  /// In he, this message translates to:
  /// **'לא נדרש פיקדון.'**
  String get contractDetailScreen9502e7c7;

  /// No description provided for @contractDetailScreenA63d0798.
  ///
  /// In he, this message translates to:
  /// **'3. תקופת השכירות'**
  String get contractDetailScreenA63d0798;

  /// No description provided for @contractDetailScreen06aba07e.
  ///
  /// In he, this message translates to:
  /// **'תקופת השכירות הינה {months} חודשים, החל מיום {startDate} ועד {endDate}.'**
  String contractDetailScreen06aba07e(
      Object endDate, Object months, Object startDate);

  /// No description provided for @contractDetailScreenD798e5f6.
  ///
  /// In he, this message translates to:
  /// **'4. סעיפים ובקשות מיוחדות'**
  String get contractDetailScreenD798e5f6;

  /// No description provided for @contractDetailScreen5c629483.
  ///
  /// In he, this message translates to:
  /// **'חתימות הצדדים'**
  String get contractDetailScreen5c629483;

  /// No description provided for @contractDetailScreen541e72da.
  ///
  /// In he, this message translates to:
  /// **'המשכיר'**
  String get contractDetailScreen541e72da;

  /// No description provided for @contractDetailScreenFd0ec7ac.
  ///
  /// In he, this message translates to:
  /// **'השוכר'**
  String get contractDetailScreenFd0ec7ac;

  /// No description provided for @contractDetailScreenA7ee13e0.
  ///
  /// In he, this message translates to:
  /// **'נחתם'**
  String get contractDetailScreenA7ee13e0;

  /// No description provided for @contractDetailScreen0e43b875.
  ///
  /// In he, this message translates to:
  /// **'ממתין'**
  String get contractDetailScreen0e43b875;

  /// No description provided for @askRentlySheet68d09f0e.
  ///
  /// In he, this message translates to:
  /// **'מותר להחזיק חיות מחמד?'**
  String get askRentlySheet68d09f0e;

  /// No description provided for @askRentlySheet8147268b.
  ///
  /// In he, this message translates to:
  /// **'באיזו קומה הדירה?'**
  String get askRentlySheet8147268b;

  /// No description provided for @askRentlySheetE8be946e.
  ///
  /// In he, this message translates to:
  /// **'יש תחבורה ציבורית קרובה?'**
  String get askRentlySheetE8be946e;

  /// No description provided for @askRentlySheet6449ebed.
  ///
  /// In he, this message translates to:
  /// **'יש חניה?'**
  String get askRentlySheet6449ebed;

  /// No description provided for @askRentlySheetBd196ab4.
  ///
  /// In he, this message translates to:
  /// **'מתי אפשר להיכנס?'**
  String get askRentlySheetBd196ab4;

  /// No description provided for @askRentlySheet47f7f61f.
  ///
  /// In he, this message translates to:
  /// **'אין לי את המידע הזה על הדירה. אפשר לשלוח את השאלה ישירות לבעל הנכס:'**
  String get askRentlySheet47f7f61f;

  /// No description provided for @askRentlySheetD8ba43e9.
  ///
  /// In he, this message translates to:
  /// **'שאלה על הדירה'**
  String get askRentlySheetD8ba43e9;

  /// No description provided for @askRentlySheet700de026.
  ///
  /// In he, this message translates to:
  /// **'השאלה נשלחה לבעל הנכס — תופיע אצלו תחת \"מבקשים לשלוח הודעה\"'**
  String get askRentlySheet700de026;

  /// No description provided for @askRentlySheetD92c26c4.
  ///
  /// In he, this message translates to:
  /// **'שלח את השאלה לבעל הדירה'**
  String get askRentlySheetD92c26c4;

  /// No description provided for @askRentlySheet18b1f617.
  ///
  /// In he, this message translates to:
  /// **'שאל את Rently'**
  String get askRentlySheet18b1f617;

  /// No description provided for @askRentlySheet6864774c.
  ///
  /// In he, this message translates to:
  /// **'שאלות על {listingTitle}'**
  String askRentlySheet6864774c(Object listingTitle);

  /// No description provided for @askRentlySheet3ad32172.
  ///
  /// In he, this message translates to:
  /// **'שאלות על הנכס הזה'**
  String get askRentlySheet3ad32172;

  /// No description provided for @askRentlySheetB728721f.
  ///
  /// In he, this message translates to:
  /// **'סגירה'**
  String get askRentlySheetB728721f;

  /// No description provided for @askRentlySheet108a7146.
  ///
  /// In he, this message translates to:
  /// **'אפשר לשאול אותי כל דבר על הדירה הזו — בעברית פשוטה. הנה כמה דוגמאות:'**
  String get askRentlySheet108a7146;

  /// No description provided for @askRentlySheet804a20ac.
  ///
  /// In he, this message translates to:
  /// **'Rently חושב…'**
  String get askRentlySheet804a20ac;

  /// No description provided for @askRentlySheet3181ba76.
  ///
  /// In he, this message translates to:
  /// **'כתבו שאלה על הדירה…'**
  String get askRentlySheet3181ba76;

  /// No description provided for @availabilityCalendarScreenDae6b270.
  ///
  /// In he, this message translates to:
  /// **'ראשון'**
  String get availabilityCalendarScreenDae6b270;

  /// No description provided for @availabilityCalendarScreen47f34119.
  ///
  /// In he, this message translates to:
  /// **'שני'**
  String get availabilityCalendarScreen47f34119;

  /// No description provided for @availabilityCalendarScreenDb0c22fc.
  ///
  /// In he, this message translates to:
  /// **'שלישי'**
  String get availabilityCalendarScreenDb0c22fc;

  /// No description provided for @availabilityCalendarScreenDa1dae77.
  ///
  /// In he, this message translates to:
  /// **'רביעי'**
  String get availabilityCalendarScreenDa1dae77;

  /// No description provided for @availabilityCalendarScreenCe94cfff.
  ///
  /// In he, this message translates to:
  /// **'חמישי'**
  String get availabilityCalendarScreenCe94cfff;

  /// No description provided for @availabilityCalendarScreen7e718908.
  ///
  /// In he, this message translates to:
  /// **'שישי'**
  String get availabilityCalendarScreen7e718908;

  /// No description provided for @availabilityCalendarScreen4203bd7e.
  ///
  /// In he, this message translates to:
  /// **'שבת'**
  String get availabilityCalendarScreen4203bd7e;

  /// No description provided for @availabilityCalendarScreen89d6e050.
  ///
  /// In he, this message translates to:
  /// **'ינואר'**
  String get availabilityCalendarScreen89d6e050;

  /// No description provided for @availabilityCalendarScreenE974ea8b.
  ///
  /// In he, this message translates to:
  /// **'פברואר'**
  String get availabilityCalendarScreenE974ea8b;

  /// No description provided for @availabilityCalendarScreenC0394ea3.
  ///
  /// In he, this message translates to:
  /// **'מרץ'**
  String get availabilityCalendarScreenC0394ea3;

  /// No description provided for @availabilityCalendarScreenA1ac81be.
  ///
  /// In he, this message translates to:
  /// **'אפריל'**
  String get availabilityCalendarScreenA1ac81be;

  /// No description provided for @availabilityCalendarScreen5fa88202.
  ///
  /// In he, this message translates to:
  /// **'מאי'**
  String get availabilityCalendarScreen5fa88202;

  /// No description provided for @availabilityCalendarScreen4dee19aa.
  ///
  /// In he, this message translates to:
  /// **'יוני'**
  String get availabilityCalendarScreen4dee19aa;

  /// No description provided for @availabilityCalendarScreenCf58b8a7.
  ///
  /// In he, this message translates to:
  /// **'יולי'**
  String get availabilityCalendarScreenCf58b8a7;

  /// No description provided for @availabilityCalendarScreen3551b598.
  ///
  /// In he, this message translates to:
  /// **'אוגוסט'**
  String get availabilityCalendarScreen3551b598;

  /// No description provided for @availabilityCalendarScreenD7106337.
  ///
  /// In he, this message translates to:
  /// **'ספטמבר'**
  String get availabilityCalendarScreenD7106337;

  /// No description provided for @availabilityCalendarScreen45ded998.
  ///
  /// In he, this message translates to:
  /// **'אוקטובר'**
  String get availabilityCalendarScreen45ded998;

  /// No description provided for @availabilityCalendarScreen712a2e4f.
  ///
  /// In he, this message translates to:
  /// **'נובמבר'**
  String get availabilityCalendarScreen712a2e4f;

  /// No description provided for @availabilityCalendarScreen1774bb5f.
  ///
  /// In he, this message translates to:
  /// **'דצמבר'**
  String get availabilityCalendarScreen1774bb5f;

  /// No description provided for @availabilityCalendarScreen782f10b5.
  ///
  /// In he, this message translates to:
  /// **'בחירת תאריך'**
  String get availabilityCalendarScreen782f10b5;

  /// No description provided for @availabilityCalendarScreenA7c55a8d.
  ///
  /// In he, this message translates to:
  /// **'ביטול'**
  String get availabilityCalendarScreenA7c55a8d;

  /// No description provided for @availabilityCalendarScreenF21acb6a.
  ///
  /// In he, this message translates to:
  /// **'אישור'**
  String get availabilityCalendarScreenF21acb6a;

  /// No description provided for @availabilityCalendarScreen0162a6e4.
  ///
  /// In he, this message translates to:
  /// **'דחוף'**
  String get availabilityCalendarScreen0162a6e4;

  /// No description provided for @availabilityCalendarScreenEab14817.
  ///
  /// In he, this message translates to:
  /// **'בלעדי'**
  String get availabilityCalendarScreenEab14817;

  /// No description provided for @availabilityCalendarScreenEa57c7ab.
  ///
  /// In he, this message translates to:
  /// **'טלפוני'**
  String get availabilityCalendarScreenEa57c7ab;

  /// No description provided for @availabilityCalendarScreen9057aef3.
  ///
  /// In he, this message translates to:
  /// **'גמיש'**
  String get availabilityCalendarScreen9057aef3;

  /// No description provided for @availabilityCalendarScreen88e6b612.
  ///
  /// In he, this message translates to:
  /// **'כל החלונות כבר קיימים ביומן'**
  String get availabilityCalendarScreen88e6b612;

  /// No description provided for @availabilityCalendarScreenB30a89dd.
  ///
  /// In he, this message translates to:
  /// **'לא נוסף חלון'**
  String get availabilityCalendarScreenB30a89dd;

  /// No description provided for @availabilityCalendarScreen2baedd1e.
  ///
  /// In he, this message translates to:
  /// **'נוסף חלון פנוי ✅'**
  String get availabilityCalendarScreen2baedd1e;

  /// No description provided for @availabilityCalendarScreen6ef11812.
  ///
  /// In he, this message translates to:
  /// **'נוספו {added} חלונות פנויים ✅'**
  String availabilityCalendarScreen6ef11812(Object added);

  /// No description provided for @availabilityCalendarScreen9ad15d69.
  ///
  /// In he, this message translates to:
  /// **'השוכר/ת'**
  String get availabilityCalendarScreen9ad15d69;

  /// No description provided for @availabilityCalendarScreenCdf3b5e1.
  ///
  /// In he, this message translates to:
  /// **'לבטל צפייה מאושרת?'**
  String get availabilityCalendarScreenCdf3b5e1;

  /// No description provided for @availabilityCalendarScreenAf15dd19.
  ///
  /// In he, this message translates to:
  /// **'צפייה עם {who} בשעה {time} תוסר מהיומן והתזכורת תבוטל.'**
  String availabilityCalendarScreenAf15dd19(Object time, Object who);

  /// No description provided for @availabilityCalendarScreen10a2352b.
  ///
  /// In he, this message translates to:
  /// **'חזרה'**
  String get availabilityCalendarScreen10a2352b;

  /// No description provided for @availabilityCalendarScreen32e0e58c.
  ///
  /// In he, this message translates to:
  /// **'בטל צפייה'**
  String get availabilityCalendarScreen32e0e58c;

  /// No description provided for @availabilityCalendarScreen6b138e97.
  ///
  /// In he, this message translates to:
  /// **'החלון הוסר'**
  String get availabilityCalendarScreen6b138e97;

  /// No description provided for @availabilityCalendarScreen8fee2105.
  ///
  /// In he, this message translates to:
  /// **'הצפייה בוטלה'**
  String get availabilityCalendarScreen8fee2105;

  /// No description provided for @availabilityCalendarScreen6b96632d.
  ///
  /// In he, this message translates to:
  /// **'לא ניתן לחייג'**
  String get availabilityCalendarScreen6b96632d;

  /// No description provided for @availabilityCalendarScreenD1b5aeb8.
  ///
  /// In he, this message translates to:
  /// **'היומן שלי'**
  String get availabilityCalendarScreenD1b5aeb8;

  /// No description provided for @availabilityCalendarScreen914d0f2b.
  ///
  /// In he, this message translates to:
  /// **'הוסף זמן פנוי'**
  String get availabilityCalendarScreen914d0f2b;

  /// No description provided for @availabilityCalendarScreen1dcc1ebd.
  ///
  /// In he, this message translates to:
  /// **'חפשו צפיות וחלונות...'**
  String get availabilityCalendarScreen1dcc1ebd;

  /// No description provided for @availabilityCalendarScreen459ead47.
  ///
  /// In he, this message translates to:
  /// **'יום'**
  String get availabilityCalendarScreen459ead47;

  /// No description provided for @availabilityCalendarScreen53703118.
  ///
  /// In he, this message translates to:
  /// **'כל הקרובים'**
  String get availabilityCalendarScreen53703118;

  /// No description provided for @availabilityCalendarScreen81849937.
  ///
  /// In he, this message translates to:
  /// **'צפיות וחלונות להיום'**
  String get availabilityCalendarScreen81849937;

  /// No description provided for @availabilityCalendarScreenA59492de.
  ///
  /// In he, this message translates to:
  /// **'אין עדיין זמנים פנויים ביום הזה'**
  String get availabilityCalendarScreenA59492de;

  /// No description provided for @availabilityCalendarScreenC5f10ba9.
  ///
  /// In he, this message translates to:
  /// **'הוסיפו חלון מהיר, או «הוסף זמן פנוי» למטה'**
  String get availabilityCalendarScreenC5f10ba9;

  /// No description provided for @availabilityCalendarScreenD741ca0e.
  ///
  /// In he, this message translates to:
  /// **'בוקר'**
  String get availabilityCalendarScreenD741ca0e;

  /// No description provided for @availabilityCalendarScreen300ea530.
  ///
  /// In he, this message translates to:
  /// **'צהריים'**
  String get availabilityCalendarScreen300ea530;

  /// No description provided for @availabilityCalendarScreen33c5e69b.
  ///
  /// In he, this message translates to:
  /// **'ערב'**
  String get availabilityCalendarScreen33c5e69b;

  /// No description provided for @availabilityCalendarScreen57660599.
  ///
  /// In he, this message translates to:
  /// **'אין צפיות או חלונות קרובים'**
  String get availabilityCalendarScreen57660599;

  /// No description provided for @availabilityCalendarScreen94eb6af0.
  ///
  /// In he, this message translates to:
  /// **'צפייה מאושרת'**
  String get availabilityCalendarScreen94eb6af0;

  /// No description provided for @availabilityCalendarScreen4958be48.
  ///
  /// In he, this message translates to:
  /// **'חלון צפייה פנוי'**
  String get availabilityCalendarScreen4958be48;

  /// No description provided for @availabilityCalendarScreenC24d48d2.
  ///
  /// In he, this message translates to:
  /// **'פניית צפייה מתואמת'**
  String get availabilityCalendarScreenC24d48d2;

  /// No description provided for @availabilityCalendarScreen50c4a059.
  ///
  /// In he, this message translates to:
  /// **'פנוי לצפייה ב{propertyLabel}'**
  String availabilityCalendarScreen50c4a059(Object propertyLabel);

  /// No description provided for @availabilityCalendarScreenC90c40a2.
  ///
  /// In he, this message translates to:
  /// **'שוכרים יכולים לתאם מועד לצפייה'**
  String get availabilityCalendarScreenC90c40a2;

  /// No description provided for @availabilityCalendarScreenF604bef9.
  ///
  /// In he, this message translates to:
  /// **'ש'**
  String get availabilityCalendarScreenF604bef9;

  /// No description provided for @availabilityCalendarScreen7bbfbc12.
  ///
  /// In he, this message translates to:
  /// **'סוכן'**
  String get availabilityCalendarScreen7bbfbc12;

  /// No description provided for @availabilityCalendarScreen9c2118be.
  ///
  /// In he, this message translates to:
  /// **'לקוח'**
  String get availabilityCalendarScreen9c2118be;

  /// No description provided for @availabilityCalendarScreenD16264b7.
  ///
  /// In he, this message translates to:
  /// **'זמין להזמנה'**
  String get availabilityCalendarScreenD16264b7;

  /// No description provided for @availabilityCalendarScreenD5bc848b.
  ///
  /// In he, this message translates to:
  /// **'חיוג'**
  String get availabilityCalendarScreenD5bc848b;

  /// No description provided for @availabilityCalendarScreen7d165b83.
  ///
  /// In he, this message translates to:
  /// **'הסר חלון'**
  String get availabilityCalendarScreen7d165b83;

  /// No description provided for @availabilityCalendarScreen9eba4851.
  ///
  /// In he, this message translates to:
  /// **'שעת התחלה של החלון הפנוי'**
  String get availabilityCalendarScreen9eba4851;

  /// No description provided for @availabilityCalendarScreenF29f462e.
  ///
  /// In he, this message translates to:
  /// **'חלון פנוי חדש'**
  String get availabilityCalendarScreenF29f462e;

  /// No description provided for @availabilityCalendarScreen96d116f2.
  ///
  /// In he, this message translates to:
  /// **'שעת התחלה'**
  String get availabilityCalendarScreen96d116f2;

  /// No description provided for @availabilityCalendarScreenE94abfe2.
  ///
  /// In he, this message translates to:
  /// **'שינוי'**
  String get availabilityCalendarScreenE94abfe2;

  /// No description provided for @availabilityCalendarScreenFc655797.
  ///
  /// In he, this message translates to:
  /// **'משך'**
  String get availabilityCalendarScreenFc655797;

  /// No description provided for @availabilityCalendarScreenD5c2c3b6.
  ///
  /// In he, this message translates to:
  /// **'{minutes} דק׳'**
  String availabilityCalendarScreenD5c2c3b6(Object minutes);

  /// No description provided for @availabilityCalendarScreenF2ee1c96.
  ///
  /// In he, this message translates to:
  /// **'{hours} שעות'**
  String availabilityCalendarScreenF2ee1c96(Object hours);

  /// No description provided for @availabilityCalendarScreenE3a2d38d.
  ///
  /// In he, this message translates to:
  /// **'דירה (רשות)'**
  String get availabilityCalendarScreenE3a2d38d;

  /// No description provided for @availabilityCalendarScreen2d69e44a.
  ///
  /// In he, this message translates to:
  /// **'כל הדירות'**
  String get availabilityCalendarScreen2d69e44a;

  /// No description provided for @availabilityCalendarScreen7d46f18c.
  ///
  /// In he, this message translates to:
  /// **'רק היום'**
  String get availabilityCalendarScreen7d46f18c;

  /// No description provided for @availabilityCalendarScreen3563f3df.
  ///
  /// In he, this message translates to:
  /// **'כל השבוע'**
  String get availabilityCalendarScreen3563f3df;

  /// No description provided for @availabilityCalendarScreen155f0dee.
  ///
  /// In he, this message translates to:
  /// **'ימי חול (א׳–ה׳)'**
  String get availabilityCalendarScreen155f0dee;

  /// No description provided for @availabilityCalendarScreen404b7e24.
  ///
  /// In he, this message translates to:
  /// **'סופ״ש (ו׳–ש׳)'**
  String get availabilityCalendarScreen404b7e24;

  /// No description provided for @availabilityCalendarScreen017014f8.
  ///
  /// In he, this message translates to:
  /// **'תווית (רשות)'**
  String get availabilityCalendarScreen017014f8;

  /// No description provided for @availabilityCalendarScreen82b33733.
  ///
  /// In he, this message translates to:
  /// **'הערה (רשות)'**
  String get availabilityCalendarScreen82b33733;

  /// No description provided for @availabilityCalendarScreenF4c3f886.
  ///
  /// In he, this message translates to:
  /// **'לדוגמה: קומה 3, קוד בניין 1234'**
  String get availabilityCalendarScreenF4c3f886;

  /// No description provided for @availabilityCalendarScreenEcfe64b2.
  ///
  /// In he, this message translates to:
  /// **'הוסף ליומן'**
  String get availabilityCalendarScreenEcfe64b2;

  /// No description provided for @availabilityCalendarScreenRepeatLabel.
  ///
  /// In he, this message translates to:
  /// **'חזרה'**
  String get availabilityCalendarScreenRepeatLabel;

  /// No description provided for @availabilityCalendarScreenSkippedSuffix.
  ///
  /// In he, this message translates to:
  /// **'{skipped} דילגו (חופפים)'**
  String availabilityCalendarScreenSkippedSuffix(Object skipped);

  /// No description provided for @eligibilityEditorSheet40d56dee.
  ///
  /// In he, this message translates to:
  /// **'הייטק'**
  String get eligibilityEditorSheet40d56dee;

  /// No description provided for @eligibilityEditorSheet6dfb51f1.
  ///
  /// In he, this message translates to:
  /// **'בריאות/רפואה'**
  String get eligibilityEditorSheet6dfb51f1;

  /// No description provided for @eligibilityEditorSheet19981c32.
  ///
  /// In he, this message translates to:
  /// **'חינוך/הוראה'**
  String get eligibilityEditorSheet19981c32;

  /// No description provided for @eligibilityEditorSheetEbfcd4cb.
  ///
  /// In he, this message translates to:
  /// **'פיננסים/בנקאות'**
  String get eligibilityEditorSheetEbfcd4cb;

  /// No description provided for @eligibilityEditorSheet4f8aded7.
  ///
  /// In he, this message translates to:
  /// **'משפטים'**
  String get eligibilityEditorSheet4f8aded7;

  /// No description provided for @eligibilityEditorSheet453fe1ed.
  ///
  /// In he, this message translates to:
  /// **'הנדסה'**
  String get eligibilityEditorSheet453fe1ed;

  /// No description provided for @eligibilityEditorSheetE1cad55a.
  ///
  /// In he, this message translates to:
  /// **'עצמאי/ת'**
  String get eligibilityEditorSheetE1cad55a;

  /// No description provided for @eligibilityEditorSheetCb481f30.
  ///
  /// In he, this message translates to:
  /// **'שירות ציבורי'**
  String get eligibilityEditorSheetCb481f30;

  /// No description provided for @eligibilityEditorSheet2834587d.
  ///
  /// In he, this message translates to:
  /// **'מסחר/שירות'**
  String get eligibilityEditorSheet2834587d;

  /// No description provided for @eligibilityEditorSheet2157ec10.
  ///
  /// In he, this message translates to:
  /// **'אקדמיה'**
  String get eligibilityEditorSheet2157ec10;

  /// No description provided for @eligibilityEditorSheet42ed7e8d.
  ///
  /// In he, this message translates to:
  /// **'סטודנט/ית'**
  String get eligibilityEditorSheet42ed7e8d;

  /// No description provided for @eligibilityEditorSheetCdf4bce0.
  ///
  /// In he, this message translates to:
  /// **'אחר'**
  String get eligibilityEditorSheetCdf4bce0;

  /// No description provided for @eligibilityEditorSheet926c043f.
  ///
  /// In he, this message translates to:
  /// **'משפחה'**
  String get eligibilityEditorSheet926c043f;

  /// No description provided for @eligibilityEditorSheetB8d9266b.
  ///
  /// In he, this message translates to:
  /// **'רווק/ה'**
  String get eligibilityEditorSheetB8d9266b;

  /// No description provided for @eligibilityEditorSheet4df994d0.
  ///
  /// In he, this message translates to:
  /// **'זוג'**
  String get eligibilityEditorSheet4df994d0;

  /// No description provided for @eligibilityEditorSheetD663155d.
  ///
  /// In he, this message translates to:
  /// **'צעיר/ה מקצועי/ת'**
  String get eligibilityEditorSheetD663155d;

  /// No description provided for @eligibilityEditorSheet0aa42aa1.
  ///
  /// In he, this message translates to:
  /// **'גיל הזהב'**
  String get eligibilityEditorSheet0aa42aa1;

  /// No description provided for @eligibilityEditorSheetD02986c3.
  ///
  /// In he, this message translates to:
  /// **'מיידי'**
  String get eligibilityEditorSheetD02986c3;

  /// No description provided for @eligibilityEditorSheetE9e8cbe3.
  ///
  /// In he, this message translates to:
  /// **'תוך חודש'**
  String get eligibilityEditorSheetE9e8cbe3;

  /// No description provided for @eligibilityEditorSheetDe0def2d.
  ///
  /// In he, this message translates to:
  /// **'תוך 3 חודשים'**
  String get eligibilityEditorSheetDe0def2d;

  /// No description provided for @eligibilityEditorSheetB4d5170f.
  ///
  /// In he, this message translates to:
  /// **'תקציב שוכר חודשי מינימלי ≥'**
  String get eligibilityEditorSheetB4d5170f;

  /// No description provided for @eligibilityEditorSheet976f97ac.
  ///
  /// In he, this message translates to:
  /// **'מספר ילדים מקסימלי'**
  String get eligibilityEditorSheet976f97ac;

  /// No description provided for @eligibilityEditorSheetE70cb0b4.
  ///
  /// In he, this message translates to:
  /// **'ללא חיית מחמד'**
  String get eligibilityEditorSheetE70cb0b4;

  /// No description provided for @eligibilityEditorSheetCb3c47ce.
  ///
  /// In he, this message translates to:
  /// **'בעל/ת רכב'**
  String get eligibilityEditorSheetCb3c47ce;

  /// No description provided for @eligibilityEditorSheet15039c05.
  ///
  /// In he, this message translates to:
  /// **'תחום עיסוק'**
  String get eligibilityEditorSheet15039c05;

  /// No description provided for @eligibilityEditorSheetF5203dea.
  ///
  /// In he, this message translates to:
  /// **'עובד/ת מרחוק'**
  String get eligibilityEditorSheetF5203dea;

  /// No description provided for @eligibilityEditorSheet2b9fb355.
  ///
  /// In he, this message translates to:
  /// **'סוג משק בית'**
  String get eligibilityEditorSheet2b9fb355;

  /// No description provided for @eligibilityEditorSheetD308ff19.
  ///
  /// In he, this message translates to:
  /// **'שלב חיים'**
  String get eligibilityEditorSheetD308ff19;

  /// No description provided for @eligibilityEditorSheet5f3306da.
  ///
  /// In he, this message translates to:
  /// **'עולה חדש'**
  String get eligibilityEditorSheet5f3306da;

  /// No description provided for @eligibilityEditorSheet8f9615bb.
  ///
  /// In he, this message translates to:
  /// **'גיל מינימלי'**
  String get eligibilityEditorSheet8f9615bb;

  /// No description provided for @eligibilityEditorSheetD5777fde.
  ///
  /// In he, this message translates to:
  /// **'גיל מקסימלי'**
  String get eligibilityEditorSheetD5777fde;

  /// No description provided for @eligibilityEditorSheetD83eff6a.
  ///
  /// In he, this message translates to:
  /// **'צרכי נגישות'**
  String get eligibilityEditorSheetD83eff6a;

  /// No description provided for @eligibilityEditorSheetC3912164.
  ///
  /// In he, this message translates to:
  /// **'מספר חדרים מבוקש (מינימום)'**
  String get eligibilityEditorSheetC3912164;

  /// No description provided for @eligibilityEditorSheet29d40b0e.
  ///
  /// In he, this message translates to:
  /// **'זמינות כניסה'**
  String get eligibilityEditorSheet29d40b0e;

  /// No description provided for @eligibilityEditorSheetC476594d.
  ///
  /// In he, this message translates to:
  /// **'חשוב'**
  String get eligibilityEditorSheetC476594d;

  /// No description provided for @eligibilityEditorSheet0d3d4125.
  ///
  /// In he, this message translates to:
  /// **'מועדף'**
  String get eligibilityEditorSheet0d3d4125;

  /// No description provided for @eligibilityEditorSheet116f6cc8.
  ///
  /// In he, this message translates to:
  /// **'חובה'**
  String get eligibilityEditorSheet116f6cc8;

  /// No description provided for @eligibilityEditorSheetA1caeddf.
  ///
  /// In he, this message translates to:
  /// **'מסנן החוצה רק את מי שידוע שלא מתאים'**
  String get eligibilityEditorSheetA1caeddf;

  /// No description provided for @eligibilityEditorSheet44ca4acb.
  ///
  /// In he, this message translates to:
  /// **'משפיע רק על הדירוג'**
  String get eligibilityEditorSheet44ca4acb;

  /// No description provided for @eligibilityEditorSheet03b2388e.
  ///
  /// In he, this message translates to:
  /// **'מי שלא תואם או לא ידוע לא יראה את המודעה'**
  String get eligibilityEditorSheet03b2388e;

  /// No description provided for @eligibilityEditorSheet9786995c.
  ///
  /// In he, this message translates to:
  /// **'לא הוגדרו קריטריונים'**
  String get eligibilityEditorSheet9786995c;

  /// No description provided for @eligibilityEditorSheetFf6c3b61.
  ///
  /// In he, this message translates to:
  /// **'{n} קריטריונים'**
  String eligibilityEditorSheetFf6c3b61(Object n);

  /// No description provided for @eligibilityEditorSheetE4f4cb81.
  ///
  /// In he, this message translates to:
  /// **'{n} קריטריונים · {musts} חובה'**
  String eligibilityEditorSheetE4f4cb81(Object musts, Object n);

  /// No description provided for @eligibilityEditorSheet2d483b2c.
  ///
  /// In he, this message translates to:
  /// **'הגדר קריטריונים מדויקים'**
  String get eligibilityEditorSheet2d483b2c;

  /// No description provided for @eligibilityEditorSheetD3b88de7.
  ///
  /// In he, this message translates to:
  /// **'הפעל/י קריטריון, הגדר/י את הערך שלו ואת רמת ההקפדה.'**
  String get eligibilityEditorSheetD3b88de7;

  /// No description provided for @eligibilityEditorSheetBb9a4c12.
  ///
  /// In he, this message translates to:
  /// **'קריטריון ללא ערך — השוכר חייב לעמוד בו.'**
  String get eligibilityEditorSheetBb9a4c12;

  /// No description provided for @eligibilityEditorSheet20d4985f.
  ///
  /// In he, this message translates to:
  /// **'רמת הקפדה'**
  String get eligibilityEditorSheet20d4985f;

  /// No description provided for @eligibilityEditorSheet7c3236c7.
  ///
  /// In he, this message translates to:
  /// **'לא נבחרו קריטריונים'**
  String get eligibilityEditorSheet7c3236c7;

  /// No description provided for @eligibilityEditorSheet7d5e1b03.
  ///
  /// In he, this message translates to:
  /// **'{count} קריטריונים פעילים'**
  String eligibilityEditorSheet7d5e1b03(Object count);

  /// No description provided for @eligibilityEditorSheetE6932339.
  ///
  /// In he, this message translates to:
  /// **'שמור'**
  String get eligibilityEditorSheetE6932339;

  /// No description provided for @eligibilityEditorSheet10ef20bd.
  ///
  /// In he, this message translates to:
  /// **'סינון שוכרים לפי קריטריונים'**
  String get eligibilityEditorSheet10ef20bd;

  /// No description provided for @eligibilityEditorSheetCdb2baa7.
  ///
  /// In he, this message translates to:
  /// **'הצג את המודעה רק לשוכרים שתואמים לקריטריונים'**
  String get eligibilityEditorSheetCdb2baa7;

  /// No description provided for @eligibilityEditorSheet7f538947.
  ///
  /// In he, this message translates to:
  /// **'קריטריונים מעבר לתקציב/עיסוק תלויים במידע שהשוכר אולי עדיין לא מילא — כך שחסימה נוקשה (\"חובה\") עלולה לצמצם משמעותית את מספר הצופים.'**
  String get eligibilityEditorSheet7f538947;

  /// No description provided for @assistantScreenBe34f590.
  ///
  /// In he, this message translates to:
  /// **'היי, נעים להכיר. קוראים לי עזרא ואני כאן כדי לעזור לך.\nספר לי בכמה מילים על הדירה שברצונך להשכיר — איפה היא, כמה חדרים, וכל מה שתרצה לשתף. ממה שתספר לי אני כבר אבין הרבה, ואשאל רק על מה שחסר.\nאפשר לדבר איתי או לכתוב, מה שנוח לך יותר.'**
  String get assistantScreenBe34f590;

  /// No description provided for @assistantScreen6f3d21fa.
  ///
  /// In he, this message translates to:
  /// **'חושב...'**
  String get assistantScreen6f3d21fa;

  /// No description provided for @assistantScreen378c0a57.
  ///
  /// In he, this message translates to:
  /// **'עזרא מדבר...'**
  String get assistantScreen378c0a57;

  /// No description provided for @assistantScreen01036d5b.
  ///
  /// In he, this message translates to:
  /// **'מקשיב לך...'**
  String get assistantScreen01036d5b;

  /// No description provided for @assistantScreenD8834f5a.
  ///
  /// In he, this message translates to:
  /// **'היי, אני עזרא'**
  String get assistantScreenD8834f5a;

  /// No description provided for @assistantScreen63169c60.
  ///
  /// In he, this message translates to:
  /// **'משהו השתבש. אפשר לנסות שוב.'**
  String get assistantScreen63169c60;

  /// No description provided for @assistantScreen581b78bc.
  ///
  /// In he, this message translates to:
  /// **'הוספתי תמונה לדירה'**
  String get assistantScreen581b78bc;

  /// No description provided for @assistantScreenB6db02ff.
  ///
  /// In he, this message translates to:
  /// **'לא הצלחתי להוסיף את התמונה. נסה שוב.'**
  String get assistantScreenB6db02ff;

  /// No description provided for @assistantScreen594cce8f.
  ///
  /// In he, this message translates to:
  /// **'הוספתי סרטון לדירה'**
  String get assistantScreen594cce8f;

  /// No description provided for @assistantScreenDf89d62b.
  ///
  /// In he, this message translates to:
  /// **'לא הצלחתי להוסיף את הסרטון. נסה שוב.'**
  String get assistantScreenDf89d62b;

  /// No description provided for @assistantScreen5dd972a7.
  ///
  /// In he, this message translates to:
  /// **'רגע — כדי לפרסם צריך לפחות תמונה אחת של הדירה. אפשר לצלם עכשיו או לבחור אחת מהטלפון.'**
  String get assistantScreen5dd972a7;

  /// No description provided for @assistantScreen07192f57.
  ///
  /// In he, this message translates to:
  /// **'מעולה! פרסמתי את הדירה שלך ב{addr} — היא כבר עלתה.'**
  String assistantScreen07192f57(Object addr);

  /// No description provided for @assistantScreen0ad71611.
  ///
  /// In he, this message translates to:
  /// **'מעולה! פרסמתי את הדירה שלך — היא כבר עלתה.'**
  String get assistantScreen0ad71611;

  /// No description provided for @assistantScreen76c2c7b1.
  ///
  /// In he, this message translates to:
  /// **'כשתרצה, אפשר להוסיף עוד תמונות בכל שלב מתוך מסך \"הדירות שלי\".'**
  String get assistantScreen76c2c7b1;

  /// No description provided for @assistantScreen539101b0.
  ///
  /// In he, this message translates to:
  /// **'אני כאן אם תצטרך עוד משהו.'**
  String get assistantScreen539101b0;

  /// No description provided for @assistantScreen163e1f70.
  ///
  /// In he, this message translates to:
  /// **'סליחה, הייתה בעיה בפרסום. אפשר לנסות שוב, או להוסיף תמונות ידנית.'**
  String get assistantScreen163e1f70;

  /// No description provided for @assistantScreen4dc83a95.
  ///
  /// In he, this message translates to:
  /// **'עזרא'**
  String get assistantScreen4dc83a95;

  /// No description provided for @assistantScreen154094c9.
  ///
  /// In he, this message translates to:
  /// **'העוזר האישי שלך'**
  String get assistantScreen154094c9;

  /// No description provided for @assistantScreenC16b3933.
  ///
  /// In he, this message translates to:
  /// **'אפשרויות'**
  String get assistantScreenC16b3933;

  /// No description provided for @assistantScreenC9b9ffef.
  ///
  /// In he, this message translates to:
  /// **'הוספת מדיה לדירה'**
  String get assistantScreenC9b9ffef;

  /// No description provided for @assistantScreen75705b64.
  ///
  /// In he, this message translates to:
  /// **'עדיין לא הוספת תמונות לדירה הזו'**
  String get assistantScreen75705b64;

  /// No description provided for @assistantScreenFeddf7c6.
  ///
  /// In he, this message translates to:
  /// **'צלם תמונה'**
  String get assistantScreenFeddf7c6;

  /// No description provided for @assistantScreenEed2fbf3.
  ///
  /// In he, this message translates to:
  /// **'גלריה'**
  String get assistantScreenEed2fbf3;

  /// No description provided for @assistantScreen26b77aa9.
  ///
  /// In he, this message translates to:
  /// **'צלם וידאו'**
  String get assistantScreen26b77aa9;

  /// No description provided for @assistantScreen4668a8a4.
  ///
  /// In he, this message translates to:
  /// **'סיימתי, המשך בשיחה'**
  String get assistantScreen4668a8a4;

  /// No description provided for @assistantScreenAca7e84c.
  ///
  /// In he, this message translates to:
  /// **'פרסום טיוטת הדירה'**
  String get assistantScreenAca7e84c;

  /// No description provided for @assistantScreen13e63c59.
  ///
  /// In he, this message translates to:
  /// **'עזרא כבר בנה טיוטה — מוכן לפרסום'**
  String get assistantScreen13e63c59;

  /// No description provided for @assistantScreenC47bc8e5.
  ///
  /// In he, this message translates to:
  /// **'הוספת תמונות'**
  String get assistantScreenC47bc8e5;

  /// No description provided for @assistantScreen4610aeb4.
  ///
  /// In he, this message translates to:
  /// **'צלם או בחר תמונות לדירה'**
  String get assistantScreen4610aeb4;

  /// No description provided for @assistantScreen384e9c59.
  ///
  /// In he, this message translates to:
  /// **'השתק קול'**
  String get assistantScreen384e9c59;

  /// No description provided for @assistantScreen1b571629.
  ///
  /// In he, this message translates to:
  /// **'הפעל קול'**
  String get assistantScreen1b571629;

  /// No description provided for @assistantScreenFa9d4e0e.
  ///
  /// In he, this message translates to:
  /// **'עזרא לא ידבר בקול רם'**
  String get assistantScreenFa9d4e0e;

  /// No description provided for @assistantScreenBfb2de50.
  ///
  /// In he, this message translates to:
  /// **'עזרא ידבר את תשובותיו בקול רם'**
  String get assistantScreenBfb2de50;

  /// No description provided for @assistantScreen82c40bcf.
  ///
  /// In he, this message translates to:
  /// **'שיחה חדשה'**
  String get assistantScreen82c40bcf;

  /// No description provided for @assistantScreenAb0463c4.
  ///
  /// In he, this message translates to:
  /// **'מחיקת היסטוריה והתחלה מחדש'**
  String get assistantScreenAb0463c4;

  /// No description provided for @assistantScreen80364adb.
  ///
  /// In he, this message translates to:
  /// **'🚪  {rooms} חדרים'**
  String assistantScreen80364adb(Object rooms);

  /// No description provided for @assistantScreenE910996a.
  ///
  /// In he, this message translates to:
  /// **'🏢  קומה {floor}'**
  String assistantScreenE910996a(Object floor);

  /// No description provided for @assistantScreen8a8c75e3.
  ///
  /// In he, this message translates to:
  /// **'💰  {price} ₪/חודש'**
  String assistantScreen8a8c75e3(Object price);

  /// No description provided for @assistantScreen5f7c4ea0.
  ///
  /// In he, this message translates to:
  /// **'📐  {size} מ״ר'**
  String assistantScreen5f7c4ea0(Object size);

  /// No description provided for @assistantScreenF534575e.
  ///
  /// In he, this message translates to:
  /// **'📅  כניסה: {date}'**
  String assistantScreenF534575e(Object date);

  /// No description provided for @assistantScreen87975ccc.
  ///
  /// In he, this message translates to:
  /// **'טיוטת נכס'**
  String get assistantScreen87975ccc;

  /// No description provided for @assistantScreenA61a9170.
  ///
  /// In he, this message translates to:
  /// **'{count} תמונות נוספו'**
  String assistantScreenA61a9170(Object count);

  /// No description provided for @assistantScreen2e6b8dd3.
  ///
  /// In he, this message translates to:
  /// **'נדרשת לפחות תמונה אחת'**
  String get assistantScreen2e6b8dd3;

  /// No description provided for @assistantScreen2628dacb.
  ///
  /// In he, this message translates to:
  /// **'הוספה או עריכת תמונות'**
  String get assistantScreen2628dacb;

  /// No description provided for @assistantScreen89ac1e56.
  ///
  /// In he, this message translates to:
  /// **'מפרסם את הדירה...'**
  String get assistantScreen89ac1e56;

  /// No description provided for @assistantScreenF3db670c.
  ///
  /// In he, this message translates to:
  /// **'כן, פרסם את הדירה'**
  String get assistantScreenF3db670c;

  /// No description provided for @assistantScreenE4c51425.
  ///
  /// In he, this message translates to:
  /// **'פתח עורך מלא'**
  String get assistantScreenE4c51425;

  /// No description provided for @landlordDashboardScreenC6c7d5f7.
  ///
  /// In he, this message translates to:
  /// **'בעל הדירה'**
  String get landlordDashboardScreenC6c7d5f7;

  /// No description provided for @landlordDashboardScreen235e6256.
  ///
  /// In he, this message translates to:
  /// **'שלום, '**
  String get landlordDashboardScreen235e6256;

  /// No description provided for @landlordDashboardScreen9c8fa644.
  ///
  /// In he, this message translates to:
  /// **'\$pendingCount מועמדים ממתינים לאישורך'**
  String landlordDashboardScreen9c8fa644(Object pendingCount);

  /// No description provided for @landlordDashboardScreen99884c14.
  ///
  /// In he, this message translates to:
  /// **'הכל מעודכן ותחת שליטה ✓'**
  String get landlordDashboardScreen99884c14;

  /// No description provided for @landlordDashboardScreenCce14f4f.
  ///
  /// In he, this message translates to:
  /// **'עוזר אישי'**
  String get landlordDashboardScreenCce14f4f;

  /// No description provided for @landlordDashboardScreen80293f4c.
  ///
  /// In he, this message translates to:
  /// **'סיכום'**
  String get landlordDashboardScreen80293f4c;

  /// No description provided for @landlordDashboardScreen1b17721e.
  ///
  /// In he, this message translates to:
  /// **'סה״כ נכסים'**
  String get landlordDashboardScreen1b17721e;

  /// No description provided for @landlordDashboardScreen17127579.
  ///
  /// In he, this message translates to:
  /// **'פעילים'**
  String get landlordDashboardScreen17127579;

  /// No description provided for @landlordDashboardScreen0b71fe76.
  ///
  /// In he, this message translates to:
  /// **'הכנסה צפויה'**
  String get landlordDashboardScreen0b71fe76;

  /// No description provided for @landlordDashboardScreen3ec09dc0.
  ///
  /// In he, this message translates to:
  /// **'חודשי'**
  String get landlordDashboardScreen3ec09dc0;

  /// No description provided for @landlordDashboardScreen94943464.
  ///
  /// In he, this message translates to:
  /// **'כמה מהמתעניינים הסכמתם להם'**
  String get landlordDashboardScreen94943464;

  /// No description provided for @landlordDashboardScreenEd3747d9.
  ///
  /// In he, this message translates to:
  /// **'\$pendingCount ממתינים לאישור שלך'**
  String landlordDashboardScreenEd3747d9(Object pendingCount);

  /// No description provided for @landlordDashboardScreen8a106a06.
  ///
  /// In he, this message translates to:
  /// **'אין מועמדים שממתינים'**
  String get landlordDashboardScreen8a106a06;

  /// No description provided for @landlordDashboardScreenEec75f83.
  ///
  /// In he, this message translates to:
  /// **'נכסים עם התאמה'**
  String get landlordDashboardScreenEec75f83;

  /// No description provided for @landlordDashboardScreenBc2e631f.
  ///
  /// In he, this message translates to:
  /// **'מתוך {propertiesCount} נכסים פעילים'**
  String landlordDashboardScreenBc2e631f(Object propertiesCount);

  /// No description provided for @landlordDashboardScreenB0164098.
  ///
  /// In he, this message translates to:
  /// **'עם התאמה'**
  String get landlordDashboardScreenB0164098;

  /// No description provided for @landlordDashboardScreenFa311e7d.
  ///
  /// In he, this message translates to:
  /// **'ממתינים'**
  String get landlordDashboardScreenFa311e7d;

  /// No description provided for @landlordDashboardScreen50296d4c.
  ///
  /// In he, this message translates to:
  /// **'שבועי'**
  String get landlordDashboardScreen50296d4c;

  /// No description provided for @landlordDashboardScreen8951e6dc.
  ///
  /// In he, this message translates to:
  /// **'שנתי'**
  String get landlordDashboardScreen8951e6dc;

  /// No description provided for @landlordDashboardScreen43b23f14.
  ///
  /// In he, this message translates to:
  /// **'השבוע'**
  String get landlordDashboardScreen43b23f14;

  /// No description provided for @landlordDashboardScreenAf52bcd6.
  ///
  /// In he, this message translates to:
  /// **'החודש'**
  String get landlordDashboardScreenAf52bcd6;

  /// No description provided for @landlordDashboardScreenBa6767e5.
  ///
  /// In he, this message translates to:
  /// **'השנה'**
  String get landlordDashboardScreenBa6767e5;

  /// No description provided for @landlordDashboardScreen270bf5ed.
  ///
  /// In he, this message translates to:
  /// **'א\\\''**
  String get landlordDashboardScreen270bf5ed;

  /// No description provided for @landlordDashboardScreen8f61d08b.
  ///
  /// In he, this message translates to:
  /// **'ב\\\''**
  String get landlordDashboardScreen8f61d08b;

  /// No description provided for @landlordDashboardScreenAf1c561b.
  ///
  /// In he, this message translates to:
  /// **'ג\\\''**
  String get landlordDashboardScreenAf1c561b;

  /// No description provided for @landlordDashboardScreenC7179c6f.
  ///
  /// In he, this message translates to:
  /// **'ד\\\''**
  String get landlordDashboardScreenC7179c6f;

  /// No description provided for @landlordDashboardScreen5dee9138.
  ///
  /// In he, this message translates to:
  /// **'ה\\\''**
  String get landlordDashboardScreen5dee9138;

  /// No description provided for @landlordDashboardScreen93aec056.
  ///
  /// In he, this message translates to:
  /// **'ו\\\''**
  String get landlordDashboardScreen93aec056;

  /// No description provided for @landlordDashboardScreenBda0900b.
  ///
  /// In he, this message translates to:
  /// **'ש\\\''**
  String get landlordDashboardScreenBda0900b;

  /// No description provided for @landlordDashboardScreenA6b97c1e.
  ///
  /// In he, this message translates to:
  /// **'שב׳ 1'**
  String get landlordDashboardScreenA6b97c1e;

  /// No description provided for @landlordDashboardScreen9aff6d23.
  ///
  /// In he, this message translates to:
  /// **'שב׳ 2'**
  String get landlordDashboardScreen9aff6d23;

  /// No description provided for @landlordDashboardScreenF960defe.
  ///
  /// In he, this message translates to:
  /// **'שב׳ 3'**
  String get landlordDashboardScreenF960defe;

  /// No description provided for @landlordDashboardScreen04e8f590.
  ///
  /// In he, this message translates to:
  /// **'ש׳ 4'**
  String get landlordDashboardScreen04e8f590;

  /// No description provided for @landlordDashboardScreen19035156.
  ///
  /// In he, this message translates to:
  /// **'ינו'**
  String get landlordDashboardScreen19035156;

  /// No description provided for @landlordDashboardScreen8cc85ded.
  ///
  /// In he, this message translates to:
  /// **'פבר'**
  String get landlordDashboardScreen8cc85ded;

  /// No description provided for @landlordDashboardScreenC0394ea3.
  ///
  /// In he, this message translates to:
  /// **'מרץ'**
  String get landlordDashboardScreenC0394ea3;

  /// No description provided for @landlordDashboardScreenDc6b970f.
  ///
  /// In he, this message translates to:
  /// **'אפר'**
  String get landlordDashboardScreenDc6b970f;

  /// No description provided for @landlordDashboardScreen5fa88202.
  ///
  /// In he, this message translates to:
  /// **'מאי'**
  String get landlordDashboardScreen5fa88202;

  /// No description provided for @landlordDashboardScreen477d76d2.
  ///
  /// In he, this message translates to:
  /// **'יונ'**
  String get landlordDashboardScreen477d76d2;

  /// No description provided for @landlordDashboardScreenA1f2e9ed.
  ///
  /// In he, this message translates to:
  /// **'יול'**
  String get landlordDashboardScreenA1f2e9ed;

  /// No description provided for @landlordDashboardScreen574d25b5.
  ///
  /// In he, this message translates to:
  /// **'אוג'**
  String get landlordDashboardScreen574d25b5;

  /// No description provided for @landlordDashboardScreen5a24ce53.
  ///
  /// In he, this message translates to:
  /// **'ספט'**
  String get landlordDashboardScreen5a24ce53;

  /// No description provided for @landlordDashboardScreen4d43f4d5.
  ///
  /// In he, this message translates to:
  /// **'אוק'**
  String get landlordDashboardScreen4d43f4d5;

  /// No description provided for @landlordDashboardScreen6f0a4de2.
  ///
  /// In he, this message translates to:
  /// **'נוב'**
  String get landlordDashboardScreen6f0a4de2;

  /// No description provided for @landlordDashboardScreenD30ca257.
  ///
  /// In he, this message translates to:
  /// **'דצמ'**
  String get landlordDashboardScreenD30ca257;

  /// No description provided for @landlordDashboardScreenA21a4640.
  ///
  /// In he, this message translates to:
  /// **'מתעניינים בנכסים שלך {suffix}'**
  String landlordDashboardScreenA21a4640(Object suffix);

  /// No description provided for @landlordDashboardScreen7203ea03.
  ///
  /// In he, this message translates to:
  /// **'לייקים היום'**
  String get landlordDashboardScreen7203ea03;

  /// No description provided for @landlordDashboardScreen4ff60e81.
  ///
  /// In he, this message translates to:
  /// **'סה״כ פניות'**
  String get landlordDashboardScreen4ff60e81;

  /// No description provided for @landlordDashboardScreenE8a3f079.
  ///
  /// In he, this message translates to:
  /// **'\$totalInquiries פניות'**
  String landlordDashboardScreenE8a3f079(Object totalInquiries);

  /// No description provided for @landlordDashboardScreen66b405bd.
  ///
  /// In he, this message translates to:
  /// **'ממוצע יומי'**
  String get landlordDashboardScreen66b405bd;

  /// No description provided for @landlordDashboardScreenAcc6e3d2.
  ///
  /// In he, this message translates to:
  /// **'ממוצע שבועי'**
  String get landlordDashboardScreenAcc6e3d2;

  /// No description provided for @landlordDashboardScreenE679dd5d.
  ///
  /// In he, this message translates to:
  /// **'ממוצע חודשי'**
  String get landlordDashboardScreenE679dd5d;

  /// No description provided for @landlordDashboardScreen2074036b.
  ///
  /// In he, this message translates to:
  /// **'כלי הסוכן'**
  String get landlordDashboardScreen2074036b;

  /// No description provided for @landlordDashboardScreen0a134a61.
  ///
  /// In he, this message translates to:
  /// **'פנקס לקוחות, התאמות, פייפליין, צפיות ועוד'**
  String get landlordDashboardScreen0a134a61;

  /// No description provided for @landlordDashboardScreen299b769f.
  ///
  /// In he, this message translates to:
  /// **'כלים לבעל הדירה'**
  String get landlordDashboardScreen299b769f;

  /// No description provided for @landlordDashboardScreenC7fa5680.
  ///
  /// In he, this message translates to:
  /// **'עזרה פשוטה לניהול הדירה — בלי כאב ראש'**
  String get landlordDashboardScreenC7fa5680;

  /// No description provided for @landlordDashboardScreenA8bb0310.
  ///
  /// In he, this message translates to:
  /// **'אינטליגנציית אזור'**
  String get landlordDashboardScreenA8bb0310;

  /// No description provided for @landlordDashboardScreen4e175795.
  ///
  /// In he, this message translates to:
  /// **'כתובת → כל נתוני האזור ולמי הוא הכי מתאים להשקעה'**
  String get landlordDashboardScreen4e175795;

  /// No description provided for @landlordDashboardScreenAaafbb6b.
  ///
  /// In he, this message translates to:
  /// **'מס הכנסה — בקלות'**
  String get landlordDashboardScreenAaafbb6b;

  /// No description provided for @landlordDashboardScreenDfd3460d.
  ///
  /// In he, this message translates to:
  /// **'בדיקה מהירה אם צריך לשלם מס על השכירות'**
  String get landlordDashboardScreenDfd3460d;

  /// No description provided for @landlordDashboardScreenCa25d18a.
  ///
  /// In he, this message translates to:
  /// **'תזכורות'**
  String get landlordDashboardScreenCa25d18a;

  /// No description provided for @landlordDashboardScreen8b96a6ac.
  ///
  /// In he, this message translates to:
  /// **'שלא תשכח חידוש חוזה, תשלום או ביטוח'**
  String get landlordDashboardScreen8b96a6ac;

  /// No description provided for @landlordDashboardScreen5308aa0d.
  ///
  /// In he, this message translates to:
  /// **'מעקב תשלומים'**
  String get landlordDashboardScreen5308aa0d;

  /// No description provided for @landlordDashboardScreen9fd83dca.
  ///
  /// In he, this message translates to:
  /// **'הוסיפו דירה כדי לעקוב אחרי תשלומי השכירות'**
  String get landlordDashboardScreen9fd83dca;

  /// No description provided for @landlordDashboardScreen7e05b276.
  ///
  /// In he, this message translates to:
  /// **'בחרו דירה כדי לראות סטטוס, מועד תשלום והערות'**
  String get landlordDashboardScreen7e05b276;

  /// No description provided for @landlordDashboardScreenDae6b270.
  ///
  /// In he, this message translates to:
  /// **'ראשון'**
  String get landlordDashboardScreenDae6b270;

  /// No description provided for @landlordDashboardScreen47f34119.
  ///
  /// In he, this message translates to:
  /// **'שני'**
  String get landlordDashboardScreen47f34119;

  /// No description provided for @landlordDashboardScreenDb0c22fc.
  ///
  /// In he, this message translates to:
  /// **'שלישי'**
  String get landlordDashboardScreenDb0c22fc;

  /// No description provided for @landlordDashboardScreenDa1dae77.
  ///
  /// In he, this message translates to:
  /// **'רביעי'**
  String get landlordDashboardScreenDa1dae77;

  /// No description provided for @landlordDashboardScreenCe94cfff.
  ///
  /// In he, this message translates to:
  /// **'חמישי'**
  String get landlordDashboardScreenCe94cfff;

  /// No description provided for @landlordDashboardScreen7e718908.
  ///
  /// In he, this message translates to:
  /// **'שישי'**
  String get landlordDashboardScreen7e718908;

  /// No description provided for @landlordDashboardScreen4203bd7e.
  ///
  /// In he, this message translates to:
  /// **'שבת'**
  String get landlordDashboardScreen4203bd7e;

  /// No description provided for @landlordDashboardScreen95d86d7f.
  ///
  /// In he, this message translates to:
  /// **'היום'**
  String get landlordDashboardScreen95d86d7f;

  /// No description provided for @landlordDashboardScreen840835ac.
  ///
  /// In he, this message translates to:
  /// **'מחר'**
  String get landlordDashboardScreen840835ac;

  /// No description provided for @landlordDashboardScreen30744d51.
  ///
  /// In he, this message translates to:
  /// **'יום {weekday}'**
  String landlordDashboardScreen30744d51(Object weekday);

  /// No description provided for @landlordDashboardScreen2dd36976.
  ///
  /// In he, this message translates to:
  /// **'יום {weekday} {day}/{month}'**
  String landlordDashboardScreen2dd36976(
      Object day, Object month, Object weekday);

  /// No description provided for @landlordDashboardScreenD1b5aeb8.
  ///
  /// In he, this message translates to:
  /// **'היומן שלי'**
  String get landlordDashboardScreenD1b5aeb8;

  /// No description provided for @landlordDashboardScreen32fb9ba0.
  ///
  /// In he, this message translates to:
  /// **'טוען...'**
  String get landlordDashboardScreen32fb9ba0;

  /// No description provided for @landlordDashboardScreenF12b53ff.
  ///
  /// In he, this message translates to:
  /// **'שוכר/ת'**
  String get landlordDashboardScreenF12b53ff;

  /// No description provided for @landlordDashboardScreen6db621c3.
  ///
  /// In he, this message translates to:
  /// **'צפייה הבאה · \$who'**
  String landlordDashboardScreen6db621c3(Object who);

  /// No description provided for @landlordDashboardScreen7dec25c8.
  ///
  /// In he, this message translates to:
  /// **'אין צפיות מתוכננות · הוסף זמנים פנויים'**
  String get landlordDashboardScreen7dec25c8;

  /// No description provided for @compareScreen724ef1bb.
  ///
  /// In he, this message translates to:
  /// **'השוואת דירות'**
  String get compareScreen724ef1bb;

  /// No description provided for @compareScreenBbabc52c.
  ///
  /// In he, this message translates to:
  /// **'חיפוש דירה להשוואה'**
  String get compareScreenBbabc52c;

  /// No description provided for @compareScreen61e90252.
  ///
  /// In he, this message translates to:
  /// **'בחרו לפחות 2 דירות להשוואה'**
  String get compareScreen61e90252;

  /// No description provided for @compareScreen27eebc10.
  ///
  /// In he, this message translates to:
  /// **'אין מספיק נתונים להמלצה ברורה'**
  String get compareScreen27eebc10;

  /// No description provided for @compareScreen4ec49abd.
  ///
  /// In he, this message translates to:
  /// **'חסרים מחיר/שטח או עוגן שוק לחלק מהדירות. גללו למטה להשוואה המלאה.'**
  String get compareScreen4ec49abd;

  /// No description provided for @compareScreenFcb21fe2.
  ///
  /// In he, this message translates to:
  /// **'עלות אמיתית ~₪{total}/חודש '**
  String compareScreenFcb21fe2(Object total);

  /// No description provided for @compareScreen46bf1369.
  ///
  /// In he, this message translates to:
  /// **'(כולל ארנונה וועד)'**
  String get compareScreen46bf1369;

  /// No description provided for @compareScreenA8bb36b3.
  ///
  /// In he, this message translates to:
  /// **'לשים לב: \$caveat'**
  String compareScreenA8bb36b3(Object caveat);

  /// No description provided for @compareScreenC25ab447.
  ///
  /// In he, this message translates to:
  /// **'אבל הכי מתאימה לך אישית: {where}'**
  String compareScreenC25ab447(Object where);

  /// No description provided for @compareScreen332e33ea.
  ///
  /// In he, this message translates to:
  /// **' ({pct}%) — אם התקציב פחות קריטי.'**
  String compareScreen332e33ea(Object pct);

  /// No description provided for @compareScreen2f883e47.
  ///
  /// In he, this message translates to:
  /// **'השורה התחתונה'**
  String get compareScreen2f883e47;

  /// No description provided for @compareScreen08920749.
  ///
  /// In he, this message translates to:
  /// **' ב\$city'**
  String compareScreen08920749(Object city);

  /// No description provided for @compareScreen651fe4ea.
  ///
  /// In he, this message translates to:
  /// **'המחיר סביר לגודל ולאזור'**
  String get compareScreen651fe4ea;

  /// No description provided for @compareScreenE97266c1.
  ///
  /// In he, this message translates to:
  /// **'כ-\$pct% מתחת למחיר השוק\$where — מחיר טוב'**
  String compareScreenE97266c1(Object pct, Object where);

  /// No description provided for @compareScreen2514977c.
  ///
  /// In he, this message translates to:
  /// **'סביב מחיר השוק — התמורה הטובה בקבוצה'**
  String get compareScreen2514977c;

  /// No description provided for @compareScreenE036fa5f.
  ///
  /// In he, this message translates to:
  /// **'בדיוק במחיר השוק\$where'**
  String compareScreenE036fa5f(Object where);

  /// No description provided for @compareScreen41c2e13a.
  ///
  /// In he, this message translates to:
  /// **'יש בהשוואה דירה מרווחת יותר'**
  String get compareScreen41c2e13a;

  /// No description provided for @compareScreen7cb99b30.
  ///
  /// In he, this message translates to:
  /// **'בלי {feature} (יש באחת האחרות)'**
  String compareScreen7cb99b30(Object feature);

  /// No description provided for @compareScreenD948b41f.
  ///
  /// In he, this message translates to:
  /// **'יש אופציה זולה יותר בעלות החודשית'**
  String get compareScreenD948b41f;

  /// No description provided for @compareScreen5b4d6e83.
  ///
  /// In he, this message translates to:
  /// **'כמה זה יעלה לך באמת'**
  String get compareScreen5b4d6e83;

  /// No description provided for @compareScreen3b9ffcf8.
  ///
  /// In he, this message translates to:
  /// **'שכר הדירה הוא לא העלות האמיתית — ארנונה וועד בית מוסיפים כל חודש.'**
  String get compareScreen3b9ffcf8;

  /// No description provided for @compareScreen35beed96.
  ///
  /// In he, this message translates to:
  /// **'{where} נראית הכי זולה בשכר, '**
  String compareScreen35beed96(Object where);

  /// No description provided for @compareScreenFc7a9430.
  ///
  /// In he, this message translates to:
  /// **'אבל {where} זולה יותר בעלות '**
  String compareScreenFc7a9430(Object where);

  /// No description provided for @compareScreen5706cd1b.
  ///
  /// In he, this message translates to:
  /// **'החודשית הכוללת.'**
  String get compareScreen5706cd1b;

  /// No description provided for @compareScreenCbde97ef.
  ///
  /// In he, this message translates to:
  /// **'הזולה באמת'**
  String get compareScreenCbde97ef;

  /// No description provided for @compareScreenCc3022d2.
  ///
  /// In he, this message translates to:
  /// **'שכ\"ד ₪{rent} + ארנונה ~₪{arnona} '**
  String compareScreenCc3022d2(Object arnona, Object rent);

  /// No description provided for @compareScreenAab6709f.
  ///
  /// In he, this message translates to:
  /// **'+ ועד ~₪{vaad}'**
  String compareScreenAab6709f(Object vaad);

  /// No description provided for @compareScreenE1000003.
  ///
  /// In he, this message translates to:
  /// **'מה מוותרים'**
  String get compareScreenE1000003;

  /// No description provided for @compareScreenB05c14b6.
  ///
  /// In he, this message translates to:
  /// **'לעומת {where} (ההמלצה) — מה כל אחת מהאחרות נותנת ומה מפסידים:'**
  String compareScreenB05c14b6(Object where);

  /// No description provided for @compareScreen87ede2ed.
  ///
  /// In he, this message translates to:
  /// **'דומה מאוד להמלצה — בלי הבדל מהותי.'**
  String get compareScreen87ede2ed;

  /// No description provided for @compareScreenD46b7e4d.
  ///
  /// In he, this message translates to:
  /// **'זולה ב-₪\$d בחודש'**
  String compareScreenD46b7e4d(Object d);

  /// No description provided for @compareScreenF17583c1.
  ///
  /// In he, this message translates to:
  /// **'יקרה ב-₪\$d בחודש'**
  String compareScreenF17583c1(Object d);

  /// No description provided for @compareScreenF1897440.
  ///
  /// In he, this message translates to:
  /// **'גדולה ב-\$d מ\"ר'**
  String compareScreenF1897440(Object d);

  /// No description provided for @compareScreenE791ef57.
  ///
  /// In he, this message translates to:
  /// **'קטנה ב-\$d מ\"ר'**
  String compareScreenE791ef57(Object d);

  /// No description provided for @compareScreen5d0daead.
  ///
  /// In he, this message translates to:
  /// **'יותר חדרים ({rooms})'**
  String compareScreen5d0daead(Object rooms);

  /// No description provided for @compareScreenE9e5b9ac.
  ///
  /// In he, this message translates to:
  /// **'פחות חדרים ({rooms})'**
  String compareScreenE9e5b9ac(Object rooms);

  /// No description provided for @compareScreenAe9d2da6.
  ///
  /// In he, this message translates to:
  /// **'עם {feature}'**
  String compareScreenAe9d2da6(Object feature);

  /// No description provided for @compareScreenC88245ca.
  ///
  /// In he, this message translates to:
  /// **'בלי {feature}'**
  String compareScreenC88245ca(Object feature);

  /// No description provided for @compareScreen56d02b30.
  ///
  /// In he, this message translates to:
  /// **'מחיר טוב יותר יחסית לשוק (ב-\$pct%)'**
  String compareScreen56d02b30(Object pct);

  /// No description provided for @compareScreen3bce9322.
  ///
  /// In he, this message translates to:
  /// **'מחיר פחות טוב יחסית לשוק (ב-\$pct%)'**
  String compareScreen3bce9322(Object pct);

  /// No description provided for @compareScreen7f897f38.
  ///
  /// In he, this message translates to:
  /// **'התאמה גבוהה יותר לך (\$mo%)'**
  String compareScreen7f897f38(Object mo);

  /// No description provided for @compareScreen95af2d2f.
  ///
  /// In he, this message translates to:
  /// **'התאמה נמוכה יותר (\$mo%)'**
  String compareScreen95af2d2f(Object mo);

  /// No description provided for @compareScreenE33e9eb9.
  ///
  /// In he, this message translates to:
  /// **'כל הפרטים להשוואה'**
  String get compareScreenE33e9eb9;

  /// No description provided for @compareScreenCc097285.
  ///
  /// In he, this message translates to:
  /// **'מחיר'**
  String get compareScreenCc097285;

  /// No description provided for @compareScreen1e7862a6.
  ///
  /// In he, this message translates to:
  /// **'₪ למ\"ר'**
  String get compareScreen1e7862a6;

  /// No description provided for @compareScreenB50b3974.
  ///
  /// In he, this message translates to:
  /// **'חדרים'**
  String get compareScreenB50b3974;

  /// No description provided for @compareScreen16f6bd25.
  ///
  /// In he, this message translates to:
  /// **'שטח'**
  String get compareScreen16f6bd25;

  /// No description provided for @compareScreenD8b6113c.
  ///
  /// In he, this message translates to:
  /// **'{size} מ\"ר'**
  String compareScreenD8b6113c(Object size);

  /// No description provided for @compareScreen047e630b.
  ///
  /// In he, this message translates to:
  /// **'קומה'**
  String get compareScreen047e630b;

  /// No description provided for @compareScreen8d058056.
  ///
  /// In he, this message translates to:
  /// **'מעלית'**
  String get compareScreen8d058056;

  /// No description provided for @compareScreenA9655ab3.
  ///
  /// In he, this message translates to:
  /// **'חניה'**
  String get compareScreenA9655ab3;

  /// No description provided for @compareScreen86425fcf.
  ///
  /// In he, this message translates to:
  /// **'מרפסת'**
  String get compareScreen86425fcf;

  /// No description provided for @compareScreenE1cca9ff.
  ///
  /// In he, this message translates to:
  /// **'ממ\"ד'**
  String get compareScreenE1cca9ff;

  /// No description provided for @compareScreenFcf022d8.
  ///
  /// In he, this message translates to:
  /// **'מצב'**
  String get compareScreenFcf022d8;

  /// No description provided for @compareScreen206ee003.
  ///
  /// In he, this message translates to:
  /// **'התאמה'**
  String get compareScreen206ee003;

  /// No description provided for @compareScreenEf5ba2c7.
  ///
  /// In he, this message translates to:
  /// **'בחרו דירות להשוואה'**
  String get compareScreenEf5ba2c7;

  /// No description provided for @compareScreen0975a98d.
  ///
  /// In he, this message translates to:
  /// **'נבחרו {count}/{max} דירות'**
  String compareScreen0975a98d(Object count, Object max);

  /// No description provided for @compareScreen4175f994.
  ///
  /// In he, this message translates to:
  /// **'כן'**
  String get compareScreen4175f994;

  /// No description provided for @compareScreen21a2d9d6.
  ///
  /// In he, this message translates to:
  /// **'לא'**
  String get compareScreen21a2d9d6;

  /// No description provided for @compareScreenF419307d.
  ///
  /// In he, this message translates to:
  /// **'עדיין לא שמרתם דירות.\\nשמרו לפחות 2 דירות כדי להשוות ביניהן.'**
  String get compareScreenF419307d;

  /// No description provided for @compareScreen8833d8c9.
  ///
  /// In he, this message translates to:
  /// **'שמרתם דירה אחת בלבד.\\nשמרו עוד דירה כדי להשוות ביניהן.'**
  String get compareScreen8833d8c9;

  /// No description provided for @compareScreenAbca0fe8.
  ///
  /// In he, this message translates to:
  /// **'הוספת דירה להשוואה'**
  String get compareScreenAbca0fe8;

  /// No description provided for @compareScreenDd5b39ef.
  ///
  /// In he, this message translates to:
  /// **'חיפוש לפי עיר / שכונה / כתובת…'**
  String get compareScreenDd5b39ef;

  /// No description provided for @compareScreenEf52c1b3.
  ///
  /// In he, this message translates to:
  /// **'אופס! לא נמצאו דירות תואמות'**
  String get compareScreenEf52c1b3;

  /// No description provided for @compareScreen0c390fdc.
  ///
  /// In he, this message translates to:
  /// **'{price} · {rooms} חד׳'**
  String compareScreen0c390fdc(Object price, Object rooms);

  /// No description provided for @landlordPropertiesScreenContractNeedsMatch.
  ///
  /// In he, this message translates to:
  /// **'חוזה נפתח מול שוכר שכבר נוצר אתו התאמה. קבלו תחילה התאמה לנכס.'**
  String get landlordPropertiesScreenContractNeedsMatch;

  /// No description provided for @landlordPropertiesScreenSendContractTitle.
  ///
  /// In he, this message translates to:
  /// **'לשלוח חוזה?'**
  String get landlordPropertiesScreenSendContractTitle;

  /// No description provided for @landlordPropertiesScreenSendContractMessage.
  ///
  /// In he, this message translates to:
  /// **'האם אתה בטוח שאתה רוצה לשלוח חוזה?'**
  String get landlordPropertiesScreenSendContractMessage;

  /// No description provided for @landlordPropertiesScreenContractSourceTitle.
  ///
  /// In he, this message translates to:
  /// **'איך תרצה ליצור את החוזה?'**
  String get landlordPropertiesScreenContractSourceTitle;

  /// No description provided for @landlordPropertiesScreenUseOurContract.
  ///
  /// In he, this message translates to:
  /// **'להשתמש בחוזה שלנו'**
  String get landlordPropertiesScreenUseOurContract;

  /// No description provided for @landlordPropertiesScreenOurContractSubtitle.
  ///
  /// In he, this message translates to:
  /// **'חוזה סטנדרטי מטעם עורכי הדין של Rently'**
  String get landlordPropertiesScreenOurContractSubtitle;

  /// No description provided for @landlordPropertiesScreenCreateOwnContract.
  ///
  /// In he, this message translates to:
  /// **'ליצור חוזה משלך'**
  String get landlordPropertiesScreenCreateOwnContract;

  /// No description provided for @landlordPropertiesScreenOwnContractSubtitle.
  ///
  /// In he, this message translates to:
  /// **'מלא את התנאים בעצמך'**
  String get landlordPropertiesScreenOwnContractSubtitle;

  /// No description provided for @landlordPropertiesScreenSortDefault.
  ///
  /// In he, this message translates to:
  /// **'ברירת מחדל'**
  String get landlordPropertiesScreenSortDefault;

  /// No description provided for @landlordPropertiesScreenSortPriceAsc.
  ///
  /// In he, this message translates to:
  /// **'לפי מחיר עולה'**
  String get landlordPropertiesScreenSortPriceAsc;

  /// No description provided for @landlordPropertiesScreenSortPriceDesc.
  ///
  /// In he, this message translates to:
  /// **'לפי מחיר יורד'**
  String get landlordPropertiesScreenSortPriceDesc;

  /// No description provided for @landlordPropertiesScreenSortRooms.
  ///
  /// In he, this message translates to:
  /// **'לפי חדרים'**
  String get landlordPropertiesScreenSortRooms;

  /// No description provided for @landlordPropertiesScreenFilterAll.
  ///
  /// In he, this message translates to:
  /// **'הכל'**
  String get landlordPropertiesScreenFilterAll;

  /// No description provided for @landlordPropertiesScreenFilterHighPriority.
  ///
  /// In he, this message translates to:
  /// **'עדיפות שיווקית (עד 6K)'**
  String get landlordPropertiesScreenFilterHighPriority;

  /// No description provided for @landlordPropertiesScreenFilterLuxury.
  ///
  /// In he, this message translates to:
  /// **'נכסי יוקרה (10K+)'**
  String get landlordPropertiesScreenFilterLuxury;

  /// No description provided for @landlordPropertiesScreenFilterImmediate.
  ///
  /// In he, this message translates to:
  /// **'כניסה מיידית'**
  String get landlordPropertiesScreenFilterImmediate;

  /// No description provided for @landlordPropertiesScreenFilterLarge.
  ///
  /// In he, this message translates to:
  /// **'דירות גדולות (4+ חדרים)'**
  String get landlordPropertiesScreenFilterLarge;

  /// No description provided for @landlordPropertiesScreenFilterAgency.
  ///
  /// In he, this message translates to:
  /// **'בלעדיות (סוכנות)'**
  String get landlordPropertiesScreenFilterAgency;

  /// No description provided for @landlordPropertiesScreenFilterPrivate.
  ///
  /// In he, this message translates to:
  /// **'פרטי (ללא תיווך)'**
  String get landlordPropertiesScreenFilterPrivate;

  /// No description provided for @landlordPropertiesScreenFilterSortTitle.
  ///
  /// In he, this message translates to:
  /// **'סינון ומיון נכסים'**
  String get landlordPropertiesScreenFilterSortTitle;

  /// No description provided for @landlordPropertiesScreenReset.
  ///
  /// In he, this message translates to:
  /// **'איפוס'**
  String get landlordPropertiesScreenReset;

  /// No description provided for @landlordPropertiesScreenFilterByTags.
  ///
  /// In he, this message translates to:
  /// **'סינון לפי תגיות'**
  String get landlordPropertiesScreenFilterByTags;

  /// No description provided for @landlordPropertiesScreenSortByLabel.
  ///
  /// In he, this message translates to:
  /// **'מיון לפי'**
  String get landlordPropertiesScreenSortByLabel;

  /// No description provided for @landlordPropertiesScreenAddLabel.
  ///
  /// In he, this message translates to:
  /// **'הוספה'**
  String get landlordPropertiesScreenAddLabel;

  /// No description provided for @landlordPropertiesScreenSearchHint.
  ///
  /// In he, this message translates to:
  /// **'חיפוש לפי כתובת, עיר...'**
  String get landlordPropertiesScreenSearchHint;

  /// No description provided for @landlordPropertiesScreenPillLarge.
  ///
  /// In he, this message translates to:
  /// **'דירות גדולות'**
  String get landlordPropertiesScreenPillLarge;

  /// No description provided for @landlordPropertiesScreenPillPrivate.
  ///
  /// In he, this message translates to:
  /// **'פרטי'**
  String get landlordPropertiesScreenPillPrivate;

  /// No description provided for @landlordPropertiesScreenPillAgency.
  ///
  /// In he, this message translates to:
  /// **'בלעדיות'**
  String get landlordPropertiesScreenPillAgency;

  /// No description provided for @landlordPropertiesScreenPillLuxury.
  ///
  /// In he, this message translates to:
  /// **'יוקרה'**
  String get landlordPropertiesScreenPillLuxury;

  /// No description provided for @landlordPropertiesScreenPillHighPriority.
  ///
  /// In he, this message translates to:
  /// **'עד 6K'**
  String get landlordPropertiesScreenPillHighPriority;

  /// No description provided for @landlordPropertiesScreenResultsCount.
  ///
  /// In he, this message translates to:
  /// **'{filtered} מתוך {total} נכסים'**
  String landlordPropertiesScreenResultsCount(Object filtered, Object total);

  /// No description provided for @landlordPropertiesScreenContractDraft.
  ///
  /// In he, this message translates to:
  /// **'טיוטה'**
  String get landlordPropertiesScreenContractDraft;

  /// No description provided for @landlordPropertiesScreenContractSent.
  ///
  /// In he, this message translates to:
  /// **'נשלח'**
  String get landlordPropertiesScreenContractSent;

  /// No description provided for @landlordPropertiesScreenContractSigned.
  ///
  /// In he, this message translates to:
  /// **'חתום ✓'**
  String get landlordPropertiesScreenContractSigned;

  /// No description provided for @landlordPropertiesScreenBoostedTag.
  ///
  /// In he, this message translates to:
  /// **'מקודם'**
  String get landlordPropertiesScreenBoostedTag;

  /// No description provided for @landlordPropertiesScreenRoomsTag.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חד׳'**
  String landlordPropertiesScreenRoomsTag(Object rooms);

  /// No description provided for @landlordPropertiesScreenSizeTag.
  ///
  /// In he, this message translates to:
  /// **'{size} מ״ר'**
  String landlordPropertiesScreenSizeTag(Object size);

  /// No description provided for @landlordPropertiesScreenContractLabel.
  ///
  /// In he, this message translates to:
  /// **'חוזה: {status}'**
  String landlordPropertiesScreenContractLabel(Object status);

  /// No description provided for @landlordPropertiesScreenAudienceCount.
  ///
  /// In he, this message translates to:
  /// **'{count} קהל יעד'**
  String landlordPropertiesScreenAudienceCount(Object count);

  /// No description provided for @landlordPropertiesScreenEmptyTitle.
  ///
  /// In he, this message translates to:
  /// **'עדיין לא הוספת דירות'**
  String get landlordPropertiesScreenEmptyTitle;

  /// No description provided for @landlordPropertiesScreenEmptyBody.
  ///
  /// In he, this message translates to:
  /// **'הוסף נכס ראשון כדי להתחיל לקבל לייקים, מועמדים ושיחות.'**
  String get landlordPropertiesScreenEmptyBody;

  /// No description provided for @landlordPropertiesScreenNoResultsTitle.
  ///
  /// In he, this message translates to:
  /// **'לא נמצאו נכסים עם הסינון הזה'**
  String get landlordPropertiesScreenNoResultsTitle;

  /// No description provided for @landlordPropertiesScreenNoResultsBody.
  ///
  /// In he, this message translates to:
  /// **'נסה לשנות את פרמטרי החיפוש או לנקות את הפילטרים.'**
  String get landlordPropertiesScreenNoResultsBody;

  /// No description provided for @landlordPropertiesScreenClearFilters.
  ///
  /// In he, this message translates to:
  /// **'נקה סינון'**
  String get landlordPropertiesScreenClearFilters;

  /// No description provided for @contractSignFlowScreenTitle.
  ///
  /// In he, this message translates to:
  /// **'חתימה על החוזה'**
  String get contractSignFlowScreenTitle;

  /// No description provided for @contractSignFlowScreenPartiesSection.
  ///
  /// In he, this message translates to:
  /// **'הצדדים והחתימות'**
  String get contractSignFlowScreenPartiesSection;

  /// No description provided for @contractSignFlowScreenLandlord.
  ///
  /// In he, this message translates to:
  /// **'בעל הדירה'**
  String get contractSignFlowScreenLandlord;

  /// No description provided for @contractSignFlowScreenTenantWithThe.
  ///
  /// In he, this message translates to:
  /// **'השוכר/ת'**
  String get contractSignFlowScreenTenantWithThe;

  /// No description provided for @contractSignFlowScreenCancelled.
  ///
  /// In he, this message translates to:
  /// **'החוזה בוטל'**
  String get contractSignFlowScreenCancelled;

  /// No description provided for @contractSignFlowScreenDeclined.
  ///
  /// In he, this message translates to:
  /// **'החוזה נדחה'**
  String get contractSignFlowScreenDeclined;

  /// No description provided for @contractSignFlowScreenCompletedTitle.
  ///
  /// In he, this message translates to:
  /// **'הושלם — נחתם ע״י שני הצדדים'**
  String get contractSignFlowScreenCompletedTitle;

  /// No description provided for @contractSignFlowScreenCompletedBody.
  ///
  /// In he, this message translates to:
  /// **'החוזה תקף וחתום דיגיטלית. ניתן לצפות בו בכל עת.'**
  String get contractSignFlowScreenCompletedBody;

  /// No description provided for @contractSignFlowScreenWaitingForOther.
  ///
  /// In he, this message translates to:
  /// **'חתמת — ממתין לחתימת {other}'**
  String contractSignFlowScreenWaitingForOther(Object other);

  /// No description provided for @contractSignFlowScreenWaitingForOtherBody.
  ///
  /// In he, this message translates to:
  /// **'נשלחה התראה לצד השני. ברגע שיחתום/תחתום, החוזה יושלם.'**
  String get contractSignFlowScreenWaitingForOtherBody;

  /// No description provided for @contractSignFlowScreenLandlordSignedWaitingYou.
  ///
  /// In he, this message translates to:
  /// **'בעל הדירה חתם · ממתין לחתימתך'**
  String get contractSignFlowScreenLandlordSignedWaitingYou;

  /// No description provided for @contractSignFlowScreenReviewToComplete.
  ///
  /// In he, this message translates to:
  /// **'עברו על התנאים ולחצו \"חתום\" כדי להשלים את החוזה.'**
  String get contractSignFlowScreenReviewToComplete;

  /// No description provided for @contractSignFlowScreenWaitingSignature.
  ///
  /// In he, this message translates to:
  /// **'ממתין לחתימה'**
  String get contractSignFlowScreenWaitingSignature;

  /// No description provided for @contractSignFlowScreenReviewToStart.
  ///
  /// In he, this message translates to:
  /// **'עברו על התנאים ולחצו \"חתום\" כדי להתחיל.'**
  String get contractSignFlowScreenReviewToStart;

  /// No description provided for @contractSignFlowScreenTenant.
  ///
  /// In he, this message translates to:
  /// **'שוכר/ת'**
  String get contractSignFlowScreenTenant;

  /// No description provided for @contractSignFlowScreenCompletedShort.
  ///
  /// In he, this message translates to:
  /// **'הושלם'**
  String get contractSignFlowScreenCompletedShort;

  /// No description provided for @contractSignFlowScreenPropertyFallback.
  ///
  /// In he, this message translates to:
  /// **'נכס להשכרה'**
  String get contractSignFlowScreenPropertyFallback;

  /// No description provided for @contractSignFlowScreenMonthlyRent.
  ///
  /// In he, this message translates to:
  /// **'שכר דירה חודשי'**
  String get contractSignFlowScreenMonthlyRent;

  /// No description provided for @contractSignFlowScreenDeposit.
  ///
  /// In he, this message translates to:
  /// **'פיקדון'**
  String get contractSignFlowScreenDeposit;

  /// No description provided for @contractSignFlowScreenDuration.
  ///
  /// In he, this message translates to:
  /// **'תקופה'**
  String get contractSignFlowScreenDuration;

  /// No description provided for @contractSignFlowScreenDurationMonths.
  ///
  /// In he, this message translates to:
  /// **'{months} חודשים'**
  String contractSignFlowScreenDurationMonths(Object months);

  /// No description provided for @contractSignFlowScreenMoveIn.
  ///
  /// In he, this message translates to:
  /// **'כניסה'**
  String get contractSignFlowScreenMoveIn;

  /// No description provided for @contractSignFlowScreenEndDate.
  ///
  /// In he, this message translates to:
  /// **'סיום'**
  String get contractSignFlowScreenEndDate;

  /// No description provided for @contractSignFlowScreenTermsText.
  ///
  /// In he, this message translates to:
  /// **'נוסח החוזה'**
  String get contractSignFlowScreenTermsText;

  /// No description provided for @contractSignFlowScreenThatsYou.
  ///
  /// In he, this message translates to:
  /// **'זה אתה'**
  String get contractSignFlowScreenThatsYou;

  /// No description provided for @contractSignFlowScreenSigned.
  ///
  /// In he, this message translates to:
  /// **'נחתם'**
  String get contractSignFlowScreenSigned;

  /// No description provided for @contractSignFlowScreenSignedOn.
  ///
  /// In he, this message translates to:
  /// **'נחתם · {date}'**
  String contractSignFlowScreenSignedOn(Object date);

  /// No description provided for @contractSignFlowScreenSignAsLabel.
  ///
  /// In he, this message translates to:
  /// **'חתום כ{role}'**
  String contractSignFlowScreenSignAsLabel(Object role);

  /// No description provided for @contractSignFlowScreenContractCompleted.
  ///
  /// In he, this message translates to:
  /// **'החוזה הושלם'**
  String get contractSignFlowScreenContractCompleted;

  /// No description provided for @contractSignFlowScreenSignedWaitingOther.
  ///
  /// In he, this message translates to:
  /// **'חתמת · ממתין לצד השני'**
  String get contractSignFlowScreenSignedWaitingOther;

  /// No description provided for @contractSignFlowScreenBack.
  ///
  /// In he, this message translates to:
  /// **'חזרה'**
  String get contractSignFlowScreenBack;

  /// No description provided for @contractSignFlowScreenSignatureSaved.
  ///
  /// In he, this message translates to:
  /// **'החתימה נשמרה בהצלחה ✍️'**
  String get contractSignFlowScreenSignatureSaved;

  /// No description provided for @contractSignFlowScreenSignBeforeConfirm.
  ///
  /// In he, this message translates to:
  /// **'יש לחתום במסגרת לפני האישור'**
  String get contractSignFlowScreenSignBeforeConfirm;

  /// No description provided for @contractSignFlowScreenDigitalSignature.
  ///
  /// In he, this message translates to:
  /// **'חתימה דיגיטלית'**
  String get contractSignFlowScreenDigitalSignature;

  /// No description provided for @contractSignFlowScreenSignWithFinger.
  ///
  /// In he, this message translates to:
  /// **'חתמו עם האצבע במסגרת למטה'**
  String get contractSignFlowScreenSignWithFinger;

  /// No description provided for @contractSignFlowScreenClear.
  ///
  /// In he, this message translates to:
  /// **'נקה'**
  String get contractSignFlowScreenClear;

  /// No description provided for @contractSignFlowScreenSigning.
  ///
  /// In he, this message translates to:
  /// **'חותם…'**
  String get contractSignFlowScreenSigning;

  /// No description provided for @contractSignFlowScreenConfirmSignature.
  ///
  /// In he, this message translates to:
  /// **'אשר חתימה'**
  String get contractSignFlowScreenConfirmSignature;

  /// No description provided for @contractSignFlowScreenSecurityNotePart1.
  ///
  /// In he, this message translates to:
  /// **'חתימה דיגיטלית מאובטחת (Ed25519). המפתח הפרטי נשמר במכשירך בלבד; '**
  String get contractSignFlowScreenSecurityNotePart1;

  /// No description provided for @contractSignFlowScreenSecurityNotePart2.
  ///
  /// In he, this message translates to:
  /// **'כל שינוי בתנאים מבטל חתימות שכבר נחתמו.'**
  String get contractSignFlowScreenSecurityNotePart2;

  /// No description provided for @contractSignFlowScreenNotFoundTitle.
  ///
  /// In he, this message translates to:
  /// **'החוזה לא נמצא'**
  String get contractSignFlowScreenNotFoundTitle;

  /// No description provided for @contractSignFlowScreenNotFoundBody.
  ///
  /// In he, this message translates to:
  /// **'נסו לרענן את הצ׳אט. אם בעל הדירה עדיין לא שלח חוזה — הוא יופיע כאן ברגע שיישלח.'**
  String get contractSignFlowScreenNotFoundBody;

  /// No description provided for @erikChatScreenBotName.
  ///
  /// In he, this message translates to:
  /// **'עזרא'**
  String get erikChatScreenBotName;

  /// No description provided for @erikChatScreenGreetingIntro.
  ///
  /// In he, this message translates to:
  /// **'שלום, נעים מאוד. קוראים לי עזרא ואני כאן כדי לעזור לך.\n'**
  String get erikChatScreenGreetingIntro;

  /// No description provided for @erikChatScreenGreetingBody1.
  ///
  /// In he, this message translates to:
  /// **'אפשר לספר לי על דירה שתרצה להשכיר ואבנה לך מודעה, לעזור לנסח תיאור, '**
  String get erikChatScreenGreetingBody1;

  /// No description provided for @erikChatScreenGreetingBody2.
  ///
  /// In he, this message translates to:
  /// **'לתמחר, או פשוט לענות על שאלות. מה שנוח לך — לכתוב או לדבר.'**
  String get erikChatScreenGreetingBody2;

  /// No description provided for @erikChatScreenStarter1.
  ///
  /// In he, this message translates to:
  /// **'אני רוצה לפרסם דירה חדשה'**
  String get erikChatScreenStarter1;

  /// No description provided for @erikChatScreenStarter2.
  ///
  /// In he, this message translates to:
  /// **'עזור לי לנסח תיאור לדירה'**
  String get erikChatScreenStarter2;

  /// No description provided for @erikChatScreenStarter3.
  ///
  /// In he, this message translates to:
  /// **'מה כדאי לצלם בדירה?'**
  String get erikChatScreenStarter3;

  /// No description provided for @erikChatScreenStarter4.
  ///
  /// In he, this message translates to:
  /// **'איך לתמחר נכון?'**
  String get erikChatScreenStarter4;

  /// No description provided for @erikChatScreenAssistantUnavailable.
  ///
  /// In he, this message translates to:
  /// **'העוזר האישי אינו זמין כרגע. אפשר לנסות שוב מאוחר יותר.'**
  String get erikChatScreenAssistantUnavailable;

  /// No description provided for @erikChatScreenTransientError.
  ///
  /// In he, this message translates to:
  /// **'סליחה, הייתה תקלה רגעית. אפשר לנסות שוב.'**
  String get erikChatScreenTransientError;

  /// No description provided for @erikChatScreenVideoAddedBubble.
  ///
  /// In he, this message translates to:
  /// **'🎥 סרטון נוסף'**
  String get erikChatScreenVideoAddedBubble;

  /// No description provided for @erikChatScreenPhotoAddedBubble.
  ///
  /// In he, this message translates to:
  /// **'📷 תמונה נוספה'**
  String get erikChatScreenPhotoAddedBubble;

  /// No description provided for @erikChatScreenVideoAddedSnack.
  ///
  /// In he, this message translates to:
  /// **'סרטון נוסף ✓'**
  String get erikChatScreenVideoAddedSnack;

  /// No description provided for @erikChatScreenPhotoAddedSnack.
  ///
  /// In he, this message translates to:
  /// **'תמונה נוספה ✓ ({count})'**
  String erikChatScreenPhotoAddedSnack(Object count);

  /// No description provided for @erikChatScreenAttachFailed.
  ///
  /// In he, this message translates to:
  /// **'לא הצלחתי לצרף את הקובץ. אפשר לנסות שוב.'**
  String get erikChatScreenAttachFailed;

  /// No description provided for @erikChatScreenTakePhoto.
  ///
  /// In he, this message translates to:
  /// **'צלם תמונה'**
  String get erikChatScreenTakePhoto;

  /// No description provided for @erikChatScreenChooseFromGallery.
  ///
  /// In he, this message translates to:
  /// **'בחר מהגלריה'**
  String get erikChatScreenChooseFromGallery;

  /// No description provided for @erikChatScreenVideoFromGallery.
  ///
  /// In he, this message translates to:
  /// **'סרטון מהגלריה'**
  String get erikChatScreenVideoFromGallery;

  /// No description provided for @erikChatScreenTour360.
  ///
  /// In he, this message translates to:
  /// **'סיור 360°'**
  String get erikChatScreenTour360;

  /// No description provided for @erikChatScreenTour360Added.
  ///
  /// In he, this message translates to:
  /// **'סיור 360° נוסף ✓'**
  String get erikChatScreenTour360Added;

  /// No description provided for @erikChatScreenNeedPhotoToPublish.
  ///
  /// In he, this message translates to:
  /// **'רק רגע — כדי לפרסם צריך לפחות תמונה אחת של הדירה. אפשר לצלם עכשיו או לבחור מהטלפון.'**
  String get erikChatScreenNeedPhotoToPublish;

  /// No description provided for @erikChatScreenPublishedSuccessWithAddr.
  ///
  /// In he, this message translates to:
  /// **'מצוין! פרסמתי את הדירה שלך ב{addr}, היא כבר באוויר. 🎉\n'**
  String erikChatScreenPublishedSuccessWithAddr(Object addr);

  /// No description provided for @erikChatScreenPublishedSuccessNoAddr.
  ///
  /// In he, this message translates to:
  /// **'מצוין! פרסמתי את הדירה שלך, היא כבר באוויר. 🎉\n'**
  String get erikChatScreenPublishedSuccessNoAddr;

  /// No description provided for @erikChatScreenPublishedTip.
  ///
  /// In he, this message translates to:
  /// **'אפשר להוסיף עוד תמונות בכל רגע מהמסך \"הדירות שלי\". אני כאן אם תצטרך עוד משהו.'**
  String get erikChatScreenPublishedTip;

  /// No description provided for @erikChatScreenPublishFailed.
  ///
  /// In he, this message translates to:
  /// **'הייתה בעיה בפרסום. אפשר לנסות שוב, או לערוך בטופס המלא.'**
  String get erikChatScreenPublishFailed;

  /// No description provided for @erikChatScreenSubtitle.
  ///
  /// In he, this message translates to:
  /// **'{botName} · העוזר האישי'**
  String erikChatScreenSubtitle(Object botName);

  /// No description provided for @erikChatScreenHereForYou.
  ///
  /// In he, this message translates to:
  /// **'כאן בשבילך'**
  String get erikChatScreenHereForYou;

  /// No description provided for @erikChatScreenLiveVoiceTooltip.
  ///
  /// In he, this message translates to:
  /// **'שיחה קולית חיה'**
  String get erikChatScreenLiveVoiceTooltip;

  /// No description provided for @erikChatScreenReadAloudOn.
  ///
  /// In he, this message translates to:
  /// **'הקראה פעילה'**
  String get erikChatScreenReadAloudOn;

  /// No description provided for @erikChatScreenReadAloudOff.
  ///
  /// In he, this message translates to:
  /// **'הקראה כבויה'**
  String get erikChatScreenReadAloudOff;

  /// No description provided for @erikChatScreenReadAloudOnSnack.
  ///
  /// In he, this message translates to:
  /// **'עזרא יקריא את התשובות'**
  String get erikChatScreenReadAloudOnSnack;

  /// No description provided for @erikChatScreenNewConversation.
  ///
  /// In he, this message translates to:
  /// **'שיחה חדשה'**
  String get erikChatScreenNewConversation;

  /// No description provided for @erikChatScreenRetry.
  ///
  /// In he, this message translates to:
  /// **'נסה שוב'**
  String get erikChatScreenRetry;

  /// No description provided for @erikChatScreenRoomsSuffix.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חדרים'**
  String erikChatScreenRoomsSuffix(Object rooms);

  /// No description provided for @erikChatScreenSizeSuffix.
  ///
  /// In he, this message translates to:
  /// **'{size} מ״ר'**
  String erikChatScreenSizeSuffix(Object size);

  /// No description provided for @erikChatScreenFloorLabel.
  ///
  /// In he, this message translates to:
  /// **'קומה {floor}'**
  String erikChatScreenFloorLabel(Object floor);

  /// No description provided for @erikChatScreenPriceSuffix.
  ///
  /// In he, this message translates to:
  /// **'₪{price} לחודש'**
  String erikChatScreenPriceSuffix(Object price);

  /// No description provided for @erikChatScreenEntryLabel.
  ///
  /// In he, this message translates to:
  /// **'כניסה: {entryDate}'**
  String erikChatScreenEntryLabel(Object entryDate);

  /// No description provided for @erikChatScreenDraftReadyTitle.
  ///
  /// In he, this message translates to:
  /// **'טיוטת מודעה מוכנה'**
  String get erikChatScreenDraftReadyTitle;

  /// No description provided for @erikChatScreenAddPhotos.
  ///
  /// In he, this message translates to:
  /// **'הוסף תמונות של הדירה'**
  String get erikChatScreenAddPhotos;

  /// No description provided for @erikChatScreenPhotosCountAddMore.
  ///
  /// In he, this message translates to:
  /// **'{count} תמונות · הוסף עוד'**
  String erikChatScreenPhotosCountAddMore(Object count);

  /// No description provided for @erikChatScreenPublishNow.
  ///
  /// In he, this message translates to:
  /// **'פרסם עכשיו'**
  String get erikChatScreenPublishNow;

  /// No description provided for @erikChatScreenEdit.
  ///
  /// In he, this message translates to:
  /// **'עריכה'**
  String get erikChatScreenEdit;

  /// No description provided for @erikChatScreenInputHint.
  ///
  /// In he, this message translates to:
  /// **'ספר לי במילים שלך...'**
  String get erikChatScreenInputHint;

  /// No description provided for @nearbyPlacesCard29364e0f.
  ///
  /// In he, this message translates to:
  /// **'מקומות בקרבה'**
  String get nearbyPlacesCard29364e0f;

  /// No description provided for @nearbyPlacesCard7e6e0fb1.
  ///
  /// In he, this message translates to:
  /// **'הקודם'**
  String get nearbyPlacesCard7e6e0fb1;

  /// No description provided for @nearbyPlacesCard4a3e7c17.
  ///
  /// In he, this message translates to:
  /// **'עמוד {page} מתוך {total}'**
  String nearbyPlacesCard4a3e7c17(Object page, Object total);

  /// No description provided for @nearbyPlacesCard5f9edf6e.
  ///
  /// In he, this message translates to:
  /// **'הבא'**
  String get nearbyPlacesCard5f9edf6e;

  /// No description provided for @nearbyPlacesCard4745b1e9.
  ///
  /// In he, this message translates to:
  /// **'ראה עוד מקומות בסביבה'**
  String get nearbyPlacesCard4745b1e9;

  /// No description provided for @nearbyPlacesCard9197afde.
  ///
  /// In he, this message translates to:
  /// **'צפה בכולם (+\$hidden)'**
  String nearbyPlacesCard9197afde(Object hidden);

  /// No description provided for @nearbyPlacesCard6192614d.
  ///
  /// In he, this message translates to:
  /// **'הצג פחות'**
  String get nearbyPlacesCard6192614d;

  /// No description provided for @nearbyPlacesCardC3e59a4e.
  ///
  /// In he, this message translates to:
  /// **' · {radiusKm} ק״מ'**
  String nearbyPlacesCardC3e59a4e(Object radiusKm);

  /// No description provided for @nearbyPlacesCardCef7ef5e.
  ///
  /// In he, this message translates to:
  /// **'בתי ספר קרובים'**
  String get nearbyPlacesCardCef7ef5e;

  /// No description provided for @nearbyPlacesCardD7b78a1f.
  ///
  /// In he, this message translates to:
  /// **'גנים קרובים'**
  String get nearbyPlacesCardD7b78a1f;

  /// No description provided for @nearbyPlacesCard385087d3.
  ///
  /// In he, this message translates to:
  /// **'קופות חולים קרובות'**
  String get nearbyPlacesCard385087d3;

  /// No description provided for @nearbyPlacesCard19a008ff.
  ///
  /// In he, this message translates to:
  /// **'סופרים קרובים'**
  String get nearbyPlacesCard19a008ff;

  /// No description provided for @nearbyPlacesCardCdc11038.
  ///
  /// In he, this message translates to:
  /// **'פארקים קרובים'**
  String get nearbyPlacesCardCdc11038;

  /// No description provided for @nearbyPlacesCardEc7edb50.
  ///
  /// In he, this message translates to:
  /// **'בתי מרקחת קרובים'**
  String get nearbyPlacesCardEc7edb50;

  /// No description provided for @nearbyPlacesCard71ec0056.
  ///
  /// In he, this message translates to:
  /// **'גני שעשועים קרובים'**
  String get nearbyPlacesCard71ec0056;

  /// No description provided for @nearbyPlacesCard09b9bc6f.
  ///
  /// In he, this message translates to:
  /// **'מסעדות ובתי קפה קרובים'**
  String get nearbyPlacesCard09b9bc6f;

  /// No description provided for @nearbyPlacesCard117e5860.
  ///
  /// In he, this message translates to:
  /// **'חדרי כושר קרובים'**
  String get nearbyPlacesCard117e5860;

  /// No description provided for @nearbyPlacesCardD4ecbfa0.
  ///
  /// In he, this message translates to:
  /// **'ברים ופאבים קרובים'**
  String get nearbyPlacesCardD4ecbfa0;

  /// No description provided for @nearbyPlacesCard7e72c9af.
  ///
  /// In he, this message translates to:
  /// **'בתי כנסת קרובים'**
  String get nearbyPlacesCard7e72c9af;

  /// No description provided for @nearbyPlacesCard21a17e0d.
  ///
  /// In he, this message translates to:
  /// **'מוסדות תרבות קרובים'**
  String get nearbyPlacesCard21a17e0d;

  /// No description provided for @nearbyPlacesCard46be343a.
  ///
  /// In he, this message translates to:
  /// **'בתי חולים קרובים'**
  String get nearbyPlacesCard46be343a;

  /// No description provided for @nearbyPlacesCard07638922.
  ///
  /// In he, this message translates to:
  /// **'תחנות רכבת ורק״ל קרובות'**
  String get nearbyPlacesCard07638922;

  /// No description provided for @nearbyPlacesCardBb428196.
  ///
  /// In he, this message translates to:
  /// **'מסגדים וכנסיות קרובים'**
  String get nearbyPlacesCardBb428196;

  /// No description provided for @nearbyPlacesCard34ff0c6c.
  ///
  /// In he, this message translates to:
  /// **'בריכות ומרכזי ספורט'**
  String get nearbyPlacesCard34ff0c6c;

  /// No description provided for @nearbyPlacesCard5290646f.
  ///
  /// In he, this message translates to:
  /// **'גינות כלבים קרובות'**
  String get nearbyPlacesCard5290646f;

  /// No description provided for @nearbyPlacesCard6faa1286.
  ///
  /// In he, this message translates to:
  /// **'וטרינרים קרובים'**
  String get nearbyPlacesCard6faa1286;

  /// No description provided for @nearbyPlacesCard5b5ddf14.
  ///
  /// In he, this message translates to:
  /// **'תחנות אופניים קרובות'**
  String get nearbyPlacesCard5b5ddf14;

  /// No description provided for @nearbyPlacesCard5d4c2d06.
  ///
  /// In he, this message translates to:
  /// **'חללי עבודה קרובים'**
  String get nearbyPlacesCard5d4c2d06;

  /// No description provided for @nearbyPlacesCard0a96eae3.
  ///
  /// In he, this message translates to:
  /// **'חניונים קרובים'**
  String get nearbyPlacesCard0a96eae3;

  /// No description provided for @nearbyPlacesCard6278673e.
  ///
  /// In he, this message translates to:
  /// **'מרפאה'**
  String get nearbyPlacesCard6278673e;

  /// No description provided for @nearbyPlacesCardDcabfe76.
  ///
  /// In he, this message translates to:
  /// **'{m} מ׳'**
  String nearbyPlacesCardDcabfe76(Object m);

  /// No description provided for @nearbyPlacesCard0b2db321.
  ///
  /// In he, this message translates to:
  /// **'{km} ק״מ'**
  String nearbyPlacesCard0b2db321(Object km);

  /// No description provided for @nearbyPlacesCard4f9b07b3.
  ///
  /// In he, this message translates to:
  /// **'לפתוח בגוגל?'**
  String get nearbyPlacesCard4f9b07b3;

  /// No description provided for @nearbyPlacesCardE927ed2c.
  ///
  /// In he, this message translates to:
  /// **'נחפש את «\$name» בגוגל.'**
  String nearbyPlacesCardE927ed2c(Object name);

  /// No description provided for @nearbyPlacesCardA7c55a8d.
  ///
  /// In he, this message translates to:
  /// **'ביטול'**
  String get nearbyPlacesCardA7c55a8d;

  /// No description provided for @nearbyPlacesCard95337767.
  ///
  /// In he, this message translates to:
  /// **'חפש בגוגל'**
  String get nearbyPlacesCard95337767;

  /// No description provided for @panoramaSweepCaptureE7f7e04b.
  ///
  /// In he, this message translates to:
  /// **'שורה אמצעית'**
  String get panoramaSweepCaptureE7f7e04b;

  /// No description provided for @panoramaSweepCapture5c22dd54.
  ///
  /// In he, this message translates to:
  /// **'החזק את הטלפון ישר (אנכית) וסובב סיבוב מלא במקום'**
  String get panoramaSweepCapture5c22dd54;

  /// No description provided for @panoramaSweepCapture00ce3275.
  ///
  /// In he, this message translates to:
  /// **'שורה עליונה'**
  String get panoramaSweepCapture00ce3275;

  /// No description provided for @panoramaSweepCapture29b0747d.
  ///
  /// In he, this message translates to:
  /// **'הטה מעט כלפי מעלה (~30°) וסובב שוב סיבוב מלא'**
  String get panoramaSweepCapture29b0747d;

  /// No description provided for @panoramaSweepCapture8dec33ce.
  ///
  /// In he, this message translates to:
  /// **'שורה תחתונה'**
  String get panoramaSweepCapture8dec33ce;

  /// No description provided for @panoramaSweepCapture69ed4717.
  ///
  /// In he, this message translates to:
  /// **'הטה מעט כלפי מטה (~30°) וסובב שוב סיבוב מלא'**
  String get panoramaSweepCapture69ed4717;

  /// No description provided for @panoramaSweepCapture62aa1e63.
  ///
  /// In he, this message translates to:
  /// **'לא ניתן לפתוח את המצלמה. בדוק הרשאות מצלמה.'**
  String get panoramaSweepCapture62aa1e63;

  /// No description provided for @panoramaSweepCapture6b180872.
  ///
  /// In he, this message translates to:
  /// **'צריך עוד תמונות כדי לבנות סיבוב שלם. סובב עוד קצת ונסה שוב.'**
  String get panoramaSweepCapture6b180872;

  /// No description provided for @panoramaSweepCapture97f6b247.
  ///
  /// In he, this message translates to:
  /// **'מתחילים לבנות את הסיור...'**
  String get panoramaSweepCapture97f6b247;

  /// No description provided for @panoramaSweepCapture51e3560a.
  ///
  /// In he, this message translates to:
  /// **'לא הצלחנו להתחיל את העיבוד. בדוק את החיבור לאינטרנט.'**
  String get panoramaSweepCapture51e3560a;

  /// No description provided for @panoramaSweepCaptureE691fca8.
  ///
  /// In he, this message translates to:
  /// **'מעלים תמונות... {i}/{total}'**
  String panoramaSweepCaptureE691fca8(Object i, Object total);

  /// No description provided for @panoramaSweepCapture7c0fe1ba.
  ///
  /// In he, this message translates to:
  /// **'ההעלאה נכשלה באמצע. בדוק את החיבור ונסה שוב.'**
  String get panoramaSweepCapture7c0fe1ba;

  /// No description provided for @panoramaSweepCapture48d71813.
  ///
  /// In he, this message translates to:
  /// **'מחברים את התמונות לסיבוב מלא...'**
  String get panoramaSweepCapture48d71813;

  /// No description provided for @panoramaSweepCaptureEc71e067.
  ///
  /// In he, this message translates to:
  /// **'העיבוד נכשל. נסה לצלם שוב, לאט ובאור טוב.'**
  String get panoramaSweepCaptureEc71e067;

  /// No description provided for @panoramaSweepCapture99b858ac.
  ///
  /// In he, this message translates to:
  /// **'העיבוד נכשל. נסה לצלם שוב.'**
  String get panoramaSweepCapture99b858ac;

  /// No description provided for @panoramaSweepCaptureFd1988b1.
  ///
  /// In he, this message translates to:
  /// **'העיבוד לוקח יותר מדי זמן. נסה שוב מאוחר יותר.'**
  String get panoramaSweepCaptureFd1988b1;

  /// No description provided for @panoramaSweepCaptureF55e6e9c.
  ///
  /// In he, this message translates to:
  /// **'משהו השתבש. בדוק את החיבור ונסה שוב.'**
  String get panoramaSweepCaptureF55e6e9c;

  /// No description provided for @panoramaSweepCapture28a43c6d.
  ///
  /// In he, this message translates to:
  /// **'סגרת · מתוך 360°'**
  String get panoramaSweepCapture28a43c6d;

  /// No description provided for @panoramaSweepCapture1b253920.
  ///
  /// In he, this message translates to:
  /// **'{count}/{total} פריימים'**
  String panoramaSweepCapture1b253920(Object count, Object total);

  /// No description provided for @panoramaSweepCapture1dc38c15.
  ///
  /// In he, this message translates to:
  /// **'לא הצלחנו לבנות את הסיור'**
  String get panoramaSweepCapture1dc38c15;

  /// No description provided for @panoramaSweepCaptureAa69b001.
  ///
  /// In he, this message translates to:
  /// **'בונים את הסיור שלך'**
  String get panoramaSweepCaptureAa69b001;

  /// No description provided for @panoramaSweepCapture28da4336.
  ///
  /// In he, this message translates to:
  /// **'\$_stitchMsg\\n\\nאפשר להמתין כמה רגעים — אל תסגרו את המסך.'**
  String panoramaSweepCapture28da4336(Object msg);

  /// No description provided for @panoramaSweepCaptureC5ffac09.
  ///
  /// In he, this message translates to:
  /// **'נסה שוב'**
  String get panoramaSweepCaptureC5ffac09;

  /// No description provided for @panoramaSweepCapture55247199.
  ///
  /// In he, this message translates to:
  /// **'סגור'**
  String get panoramaSweepCapture55247199;

  /// No description provided for @panoramaSweepCapture7512612e.
  ///
  /// In he, this message translates to:
  /// **'סובב צעד · עצור · חזור על כך סביב'**
  String get panoramaSweepCapture7512612e;

  /// No description provided for @panoramaSweepCapture5b98f935.
  ///
  /// In he, this message translates to:
  /// **'עצור רגע כדי לצלם 🐢'**
  String get panoramaSweepCapture5b98f935;

  /// No description provided for @panoramaSweepCapture2086feda.
  ///
  /// In he, this message translates to:
  /// **'יופי — עצור רגע'**
  String get panoramaSweepCapture2086feda;

  /// No description provided for @panoramaSweepCaptureC73a59b7.
  ///
  /// In he, this message translates to:
  /// **'סובב צעד קטן והמשך'**
  String get panoramaSweepCaptureC73a59b7;

  /// No description provided for @panoramaSweepCapture6a487da4.
  ///
  /// In he, this message translates to:
  /// **'עצור'**
  String get panoramaSweepCapture6a487da4;

  /// No description provided for @panoramaSweepCaptureEdd587e1.
  ///
  /// In he, this message translates to:
  /// **'המשך שורה'**
  String get panoramaSweepCaptureEdd587e1;

  /// No description provided for @panoramaSweepCapture41e2bc7e.
  ///
  /// In he, this message translates to:
  /// **'התחל {title}'**
  String panoramaSweepCapture41e2bc7e(Object title);

  /// No description provided for @panoramaSweepCapture3ccd2a1c.
  ///
  /// In he, this message translates to:
  /// **'המשך ל{title}'**
  String panoramaSweepCapture3ccd2a1c(Object title);

  /// No description provided for @panoramaSweepCaptureF600808f.
  ///
  /// In he, this message translates to:
  /// **'סיום'**
  String get panoramaSweepCaptureF600808f;

  /// No description provided for @panoramaSweepCaptureC9e2125f.
  ///
  /// In he, this message translates to:
  /// **'סיים'**
  String get panoramaSweepCaptureC9e2125f;

  /// No description provided for @panoramaSweepCapture4c53a96e.
  ///
  /// In he, this message translates to:
  /// **'שגיאת מצלמה'**
  String get panoramaSweepCapture4c53a96e;

  /// No description provided for @brokerOwnerReportScreen9e2251dc.
  ///
  /// In he, this message translates to:
  /// **'דוח פעילות — {address}'**
  String brokerOwnerReportScreen9e2251dc(Object address);

  /// No description provided for @brokerOwnerReportScreen4af427f3.
  ///
  /// In he, this message translates to:
  /// **'דוח פעילות לבעל הנכס'**
  String get brokerOwnerReportScreen4af427f3;

  /// No description provided for @brokerOwnerReportScreen5a6b6baa.
  ///
  /// In he, this message translates to:
  /// **'בחרו נכס'**
  String get brokerOwnerReportScreen5a6b6baa;

  /// No description provided for @brokerOwnerReportScreen80dfca38.
  ///
  /// In he, this message translates to:
  /// **'סיכום פעילות · {address}'**
  String brokerOwnerReportScreen80dfca38(Object address);

  /// No description provided for @brokerOwnerReportScreenD304ce53.
  ///
  /// In he, this message translates to:
  /// **'מה לשלוח לבעל הנכס'**
  String get brokerOwnerReportScreenD304ce53;

  /// No description provided for @brokerOwnerReportScreen48227f9c.
  ///
  /// In he, this message translates to:
  /// **'צפיות'**
  String get brokerOwnerReportScreen48227f9c;

  /// No description provided for @brokerOwnerReportScreenDaa11b47.
  ///
  /// In he, this message translates to:
  /// **'מתעניינים (לייקים)'**
  String get brokerOwnerReportScreenDaa11b47;

  /// No description provided for @brokerOwnerReportScreen066de4f8.
  ///
  /// In he, this message translates to:
  /// **'שמירות'**
  String get brokerOwnerReportScreen066de4f8;

  /// No description provided for @brokerOwnerReportScreenD535641c.
  ///
  /// In he, this message translates to:
  /// **'פניות ליצירת קשר'**
  String get brokerOwnerReportScreenD535641c;

  /// No description provided for @brokerOwnerReportScreenA04be780.
  ///
  /// In he, this message translates to:
  /// **'כניסות לעמוד הנכס'**
  String get brokerOwnerReportScreenA04be780;

  /// No description provided for @brokerOwnerReportScreenAc141b12.
  ///
  /// In he, this message translates to:
  /// **'צפייה אחרונה'**
  String get brokerOwnerReportScreenAc141b12;

  /// No description provided for @brokerOwnerReportScreen564551f8.
  ///
  /// In he, this message translates to:
  /// **'הנכס נצפה {count} פעמים'**
  String brokerOwnerReportScreen564551f8(Object count);

  /// No description provided for @brokerOwnerReportScreen958d9393.
  ///
  /// In he, this message translates to:
  /// **'{count} מתעניינים סימנו אותו'**
  String brokerOwnerReportScreen958d9393(Object count);

  /// No description provided for @brokerOwnerReportScreenFa6a4018.
  ///
  /// In he, this message translates to:
  /// **'{count} שמרו אותו לעיון חוזר'**
  String brokerOwnerReportScreenFa6a4018(Object count);

  /// No description provided for @brokerOwnerReportScreen825b0fd8.
  ///
  /// In he, this message translates to:
  /// **'התקבלו {count} פניות ליצירת קשר'**
  String brokerOwnerReportScreen825b0fd8(Object count);

  /// No description provided for @brokerOwnerReportScreenDf3d7596.
  ///
  /// In he, this message translates to:
  /// **'הנכס פורסם ופעיל במערכת. בשלב זה טרם נרשמה פעילות מדידה — '**
  String get brokerOwnerReportScreenDf3d7596;

  /// No description provided for @brokerOwnerReportScreen9463334d.
  ///
  /// In he, this message translates to:
  /// **'נמשיך לעקוב ונעדכן אותך בהמשך.'**
  String get brokerOwnerReportScreen9463334d;

  /// No description provided for @brokerOwnerReportScreenF0cf8eae.
  ///
  /// In he, this message translates to:
  /// **'עדכון על \"{address}\": {summary}. אנחנו ממשיכים לקדם '**
  String brokerOwnerReportScreenF0cf8eae(Object address, Object summary);

  /// No description provided for @brokerOwnerReportScreen85a17b3a.
  ///
  /// In he, this message translates to:
  /// **'את הנכס ונשמח לעדכן בכל התקדמות.'**
  String get brokerOwnerReportScreen85a17b3a;

  /// No description provided for @brokerOwnerReportScreenE707f57e.
  ///
  /// In he, this message translates to:
  /// **'דוח פעילות — {address}'**
  String brokerOwnerReportScreenE707f57e(Object address);

  /// No description provided for @brokerOwnerReportScreenDb69622a.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חדרים · {size} מ\"ר'**
  String brokerOwnerReportScreenDb69622a(Object rooms, Object size);

  /// No description provided for @brokerOwnerReportScreenD973da64.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חדרים'**
  String brokerOwnerReportScreenD973da64(Object rooms);

  /// No description provided for @brokerOwnerReportScreenFd67190d.
  ///
  /// In he, this message translates to:
  /// **'שלח כטקסט'**
  String get brokerOwnerReportScreenFd67190d;

  /// No description provided for @brokerOwnerReportScreenC87bee7b.
  ///
  /// In he, this message translates to:
  /// **'שליחת הדוח'**
  String get brokerOwnerReportScreenC87bee7b;

  /// No description provided for @brokerOwnerReportScreenDe13d87a.
  ///
  /// In he, this message translates to:
  /// **'שליחה ב-WhatsApp'**
  String get brokerOwnerReportScreenDe13d87a;

  /// No description provided for @brokerOwnerReportScreenC23278cd.
  ///
  /// In he, this message translates to:
  /// **'לא ניתן לפתוח את WhatsApp כרגע'**
  String get brokerOwnerReportScreenC23278cd;

  /// No description provided for @brokerOwnerReportScreen217e3171.
  ///
  /// In he, this message translates to:
  /// **'שליחה ב-SMS'**
  String get brokerOwnerReportScreen217e3171;

  /// No description provided for @brokerOwnerReportScreen12d7a7d4.
  ///
  /// In he, this message translates to:
  /// **'לא ניתן לפתוח SMS כרגע'**
  String get brokerOwnerReportScreen12d7a7d4;

  /// No description provided for @brokerOwnerReportScreenB4a9fdcf.
  ///
  /// In he, this message translates to:
  /// **'העתקת הדוח'**
  String get brokerOwnerReportScreenB4a9fdcf;

  /// No description provided for @brokerOwnerReportScreen452f9d1a.
  ///
  /// In he, this message translates to:
  /// **'הדוח הועתק'**
  String get brokerOwnerReportScreen452f9d1a;

  /// No description provided for @brokerOwnerReportScreenC96fa39c.
  ///
  /// In he, this message translates to:
  /// **'אין עדיין נכסים'**
  String get brokerOwnerReportScreenC96fa39c;

  /// No description provided for @brokerOwnerReportScreen6dc67ee5.
  ///
  /// In he, this message translates to:
  /// **'הוסיפו נכס כדי להפיק דוח פעילות לבעל הנכס.'**
  String get brokerOwnerReportScreen6dc67ee5;

  /// No description provided for @brokerOwnerReportScreenA170171d.
  ///
  /// In he, this message translates to:
  /// **'לפני פחות משעה'**
  String get brokerOwnerReportScreenA170171d;

  /// No description provided for @brokerOwnerReportScreenC46e717b.
  ///
  /// In he, this message translates to:
  /// **'לפני {hours} שעות'**
  String brokerOwnerReportScreenC46e717b(Object hours);

  /// No description provided for @brokerOwnerReportScreenBe285a01.
  ///
  /// In he, this message translates to:
  /// **'אתמול'**
  String get brokerOwnerReportScreenBe285a01;

  /// No description provided for @brokerOwnerReportScreen0cfbdf39.
  ///
  /// In he, this message translates to:
  /// **'לפני {days} ימים'**
  String brokerOwnerReportScreen0cfbdf39(Object days);

  /// No description provided for @contractFormScreenCa38cedb.
  ///
  /// In he, this message translates to:
  /// **'שיפור חוזה עם AI'**
  String get contractFormScreenCa38cedb;

  /// No description provided for @contractFormScreenA7aa0554.
  ///
  /// In he, this message translates to:
  /// **'שיפור חוזה עם AI — Rently'**
  String get contractFormScreenA7aa0554;

  /// No description provided for @contractFormScreen5ff8838c.
  ///
  /// In he, this message translates to:
  /// **'התשלום אינו זמין כרגע. נסו שוב מאוחר יותר.'**
  String get contractFormScreen5ff8838c;

  /// No description provided for @contractFormScreen0bf10733.
  ///
  /// In he, this message translates to:
  /// **'לא ניתן לשפר את החוזה כרגע. נסו שוב.'**
  String get contractFormScreen0bf10733;

  /// No description provided for @contractFormScreenC2278e7d.
  ///
  /// In he, this message translates to:
  /// **'החוזה שופר והותאם בעזרת AI ✨'**
  String get contractFormScreenC2278e7d;

  /// No description provided for @contractFormScreenCbbabf55.
  ///
  /// In he, this message translates to:
  /// **'יש להזין שכר דירה חודשי'**
  String get contractFormScreenCbbabf55;

  /// No description provided for @contractFormScreen8e5a493e.
  ///
  /// In he, this message translates to:
  /// **'לא ניתן ליצור חוזה כרגע. נסו שוב.'**
  String get contractFormScreen8e5a493e;

  /// No description provided for @contractFormScreen64202d91.
  ///
  /// In he, this message translates to:
  /// **'חוזה שכירות חדש'**
  String get contractFormScreen64202d91;

  /// No description provided for @contractFormScreenEdb89494.
  ///
  /// In he, this message translates to:
  /// **'שולח…'**
  String get contractFormScreenEdb89494;

  /// No description provided for @contractFormScreenC1c55cf9.
  ///
  /// In he, this message translates to:
  /// **'שלח לחתימה'**
  String get contractFormScreenC1c55cf9;

  /// No description provided for @contractFormScreen1b58c9a0.
  ///
  /// In he, this message translates to:
  /// **'תנאי השכירות'**
  String get contractFormScreen1b58c9a0;

  /// No description provided for @contractFormScreen0ae58e28.
  ///
  /// In he, this message translates to:
  /// **'שכר דירה חודשי (₪)'**
  String get contractFormScreen0ae58e28;

  /// No description provided for @contractFormScreen99d1d056.
  ///
  /// In he, this message translates to:
  /// **'פיקדון / ערבון (₪)'**
  String get contractFormScreen99d1d056;

  /// No description provided for @contractFormScreenBdecb11c.
  ///
  /// In he, this message translates to:
  /// **'תקופת השכירות'**
  String get contractFormScreenBdecb11c;

  /// No description provided for @contractFormScreenBf1cf58d.
  ///
  /// In he, this message translates to:
  /// **'\$m חודשים'**
  String contractFormScreenBf1cf58d(Object m);

  /// No description provided for @contractFormScreenB7cdc163.
  ///
  /// In he, this message translates to:
  /// **'תאריך כניסה'**
  String get contractFormScreenB7cdc163;

  /// No description provided for @contractFormScreen67e27f00.
  ///
  /// In he, this message translates to:
  /// **'נוסח החוזה'**
  String get contractFormScreen67e27f00;

  /// No description provided for @contractFormScreen9e1017ad.
  ///
  /// In he, this message translates to:
  /// **'חזרה לנוסח הסטנדרטי'**
  String get contractFormScreen9e1017ad;

  /// No description provided for @contractFormScreen30664b86.
  ///
  /// In he, this message translates to:
  /// **'טקסט החוזה'**
  String get contractFormScreen30664b86;

  /// No description provided for @contractFormScreen374bbbdf.
  ///
  /// In he, this message translates to:
  /// **'החוזה ייחתם בחתימה דיגיטלית מאובטחת מקצה לקצה. כל צד חותם במכשירו, וכל שינוי בתנאים יבטל חתימות קודמות.'**
  String get contractFormScreen374bbbdf;

  /// No description provided for @contractFormScreenE34604a7.
  ///
  /// In he, this message translates to:
  /// **'חוזה שכירות סטנדרטי'**
  String get contractFormScreenE34604a7;

  /// No description provided for @contractFormScreenCbfee77a.
  ///
  /// In he, this message translates to:
  /// **'שפר עם AI'**
  String get contractFormScreenCbfee77a;

  /// No description provided for @contractFormScreen311875d1.
  ///
  /// In he, this message translates to:
  /// **'פיצ׳ר בתשלום · \$priceShekel₪'**
  String contractFormScreen311875d1(Object price);

  /// No description provided for @contractFormScreen82a64993.
  ///
  /// In he, this message translates to:
  /// **'מתאים את החוזה לנכס…'**
  String get contractFormScreen82a64993;

  /// No description provided for @contractFormScreen3750438e.
  ///
  /// In he, this message translates to:
  /// **'מנסח ומתאים את החוזה לנכס ולתנאים בעזרת AI'**
  String get contractFormScreen3750438e;

  /// No description provided for @contractFormScreenA78d435c.
  ///
  /// In he, this message translates to:
  /// **'שיפור החוזה בעזרת AI'**
  String get contractFormScreenA78d435c;

  /// No description provided for @contractFormScreenF4a6089f.
  ///
  /// In he, this message translates to:
  /// **'ה-AI ינסח מחדש ויתאים את החוזה לנכס ולתנאים שלכם — נוסח ברור, '**
  String get contractFormScreenF4a6089f;

  /// No description provided for @contractFormScreenC0583fa2.
  ///
  /// In he, this message translates to:
  /// **'מסודר וערוך בסעיפים, מבוסס על הנתונים בלבד.'**
  String get contractFormScreenC0583fa2;

  /// No description provided for @contractFormScreen99b411b6.
  ///
  /// In he, this message translates to:
  /// **'פיצ׳ר בתשלום'**
  String get contractFormScreen99b411b6;

  /// No description provided for @contractFormScreenFa001394.
  ///
  /// In he, this message translates to:
  /// **'המשך לתשלום \$priceShekel ₪'**
  String contractFormScreenFa001394(Object price);

  /// No description provided for @contractFormScreen98c8a5b8.
  ///
  /// In he, this message translates to:
  /// **'לא עכשיו'**
  String get contractFormScreen98c8a5b8;

  /// No description provided for @paywallScreenPerYear.
  ///
  /// In he, this message translates to:
  /// **' / שנה'**
  String get paywallScreenPerYear;

  /// No description provided for @paywallScreenPerMonth.
  ///
  /// In he, this message translates to:
  /// **' / חודש'**
  String get paywallScreenPerMonth;

  /// No description provided for @paywallScreenSubscriptionSubtitle.
  ///
  /// In he, this message translates to:
  /// **'מנוי {plan} — RENTLY PRO'**
  String paywallScreenSubscriptionSubtitle(Object plan);

  /// No description provided for @paywallScreenAnnualLabel.
  ///
  /// In he, this message translates to:
  /// **'שנתי'**
  String get paywallScreenAnnualLabel;

  /// No description provided for @paywallScreenMonthlyLabel.
  ///
  /// In he, this message translates to:
  /// **'חודשי'**
  String get paywallScreenMonthlyLabel;

  /// No description provided for @paywallScreenPaymentError.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בפתיחת התשלום. נסו שוב.'**
  String get paywallScreenPaymentError;

  /// No description provided for @paywallScreenLoginRequired.
  ///
  /// In he, this message translates to:
  /// **'צריך להתחבר לחשבון כדי לרכוש מנוי — התחבר/י ונסה שוב.'**
  String get paywallScreenLoginRequired;

  /// No description provided for @paywallScreenPaymentErrorWithCode.
  ///
  /// In he, this message translates to:
  /// **'שגיאה בפתיחת התשלום ({code}). נסו שוב.'**
  String paywallScreenPaymentErrorWithCode(Object code);

  /// No description provided for @paywallScreenEntitlementPending.
  ///
  /// In he, this message translates to:
  /// **'התשלום התקבל — הפעלת המנוי עשויה לקחת רגע. בדקו שוב בעוד מספר דקות.'**
  String get paywallScreenEntitlementPending;

  /// No description provided for @paywallScreenHeadline.
  ///
  /// In he, this message translates to:
  /// **'סגרו שכירות מהר יותר.'**
  String get paywallScreenHeadline;

  /// No description provided for @paywallScreenSubheadline.
  ///
  /// In he, this message translates to:
  /// **'RENTLY PRO נותן לדירה שלך את הבמה: יותר צופים, שוכרים מדויקים, וכל הניהול במקום אחד — עד שהיא מושכרת.'**
  String get paywallScreenSubheadline;

  /// No description provided for @paywallScreenPerMonthShort.
  ///
  /// In he, this message translates to:
  /// **'לחודש'**
  String get paywallScreenPerMonthShort;

  /// No description provided for @paywallScreenMonthlyBillingNote.
  ///
  /// In he, this message translates to:
  /// **'חיוב חודשי · ביטול בכל עת'**
  String get paywallScreenMonthlyBillingNote;

  /// No description provided for @paywallScreenMonthlyBoostsNote.
  ///
  /// In he, this message translates to:
  /// **'2 הקפצות בחודש'**
  String get paywallScreenMonthlyBoostsNote;

  /// No description provided for @paywallScreenAnnualPeriodLine.
  ///
  /// In he, this message translates to:
  /// **'לשנה · ₪37.50 לחודש'**
  String get paywallScreenAnnualPeriodLine;

  /// No description provided for @paywallScreenAnnualBillingNote.
  ///
  /// In he, this message translates to:
  /// **'משלמים 10 חודשים, מקבלים 12'**
  String get paywallScreenAnnualBillingNote;

  /// No description provided for @paywallScreenAnnualBoostsNote.
  ///
  /// In he, this message translates to:
  /// **'5 הקפצות בחודש'**
  String get paywallScreenAnnualBoostsNote;

  /// No description provided for @paywallScreenAnnualRibbon.
  ///
  /// In he, this message translates to:
  /// **'המשתלם ביותר · חיסכון {savings}'**
  String paywallScreenAnnualRibbon(Object savings);

  /// No description provided for @paywallScreenFeatureUnlimitedListings.
  ///
  /// In he, this message translates to:
  /// **'פרסום דירות ללא הגבלה'**
  String get paywallScreenFeatureUnlimitedListings;

  /// No description provided for @paywallScreenFeatureBoosts.
  ///
  /// In he, this message translates to:
  /// **'הקפצות שמביאות יותר צופים לדירה'**
  String get paywallScreenFeatureBoosts;

  /// No description provided for @paywallScreenFeatureVerifiedBadge.
  ///
  /// In he, this message translates to:
  /// **'תג \"מאומת\" — יותר אמון, יותר פניות'**
  String get paywallScreenFeatureVerifiedBadge;

  /// No description provided for @paywallScreenFeatureSearchPriority.
  ///
  /// In he, this message translates to:
  /// **'קדימות בתוצאות החיפוש של השוכרים'**
  String get paywallScreenFeatureSearchPriority;

  /// No description provided for @paywallScreenFeatureCandidateManagement.
  ///
  /// In he, this message translates to:
  /// **'ניהול מועמדים, צ׳אט ותיאום סיורים במקום אחד'**
  String get paywallScreenFeatureCandidateManagement;

  /// No description provided for @paywallScreenFeatureCalendar.
  ///
  /// In he, this message translates to:
  /// **'יומן זמינות אוטומטי לתיאום צפיות'**
  String get paywallScreenFeatureCalendar;

  /// No description provided for @paywallScreenFeatureMarketInsights.
  ///
  /// In he, this message translates to:
  /// **'תובנות שוק ומחירון אזורי חכם'**
  String get paywallScreenFeatureMarketInsights;

  /// No description provided for @paywallScreenAllPlansInclude.
  ///
  /// In he, this message translates to:
  /// **'כל מה שכלול בכל מסלול'**
  String get paywallScreenAllPlansInclude;

  /// No description provided for @paywallScreenUltraTeaserTitle.
  ///
  /// In he, this message translates to:
  /// **'צריך חשיפה מקסימלית?'**
  String get paywallScreenUltraTeaserTitle;

  /// No description provided for @paywallScreenUltraTeaserBody.
  ///
  /// In he, this message translates to:
  /// **'הקפצת Ultra — פי 5 חשיפה, זמינה בכל דירה מ-₪50.'**
  String get paywallScreenUltraTeaserBody;

  /// No description provided for @paywallScreenAnnualBillingTrial.
  ///
  /// In he, this message translates to:
  /// **'חיוב שנתי {amount}. ניתן לבטל בכל עת.'**
  String paywallScreenAnnualBillingTrial(Object amount);

  /// No description provided for @paywallScreenMonthlyBillingTrial.
  ///
  /// In he, this message translates to:
  /// **'חיוב חודשי מתחדש {amount}. ניתן לבטל בכל עת.'**
  String paywallScreenMonthlyBillingTrial(Object amount);

  /// No description provided for @paywallScreenJoinAnnual.
  ///
  /// In he, this message translates to:
  /// **'הצטרפות למסלול השנתי'**
  String get paywallScreenJoinAnnual;

  /// No description provided for @paywallScreenJoinMonthly.
  ///
  /// In he, this message translates to:
  /// **'הצטרפות למסלול החודשי'**
  String get paywallScreenJoinMonthly;

  /// No description provided for @paywallScreenSecurePayment.
  ///
  /// In he, this message translates to:
  /// **'תשלום מאובטח · קבלה נשלחת למייל'**
  String get paywallScreenSecurePayment;

  /// No description provided for @paywallScreenCouponHint.
  ///
  /// In he, this message translates to:
  /// **'קוד קופון (אופציונלי)'**
  String get paywallScreenCouponHint;

  /// No description provided for @paywallScreenFeatureBoostListings.
  ///
  /// In he, this message translates to:
  /// **'הקפצת מודעות (בוסט) לקידום בפיד'**
  String get paywallScreenFeatureBoostListings;

  /// No description provided for @paywallScreenFeatureVerifiedAndPriority.
  ///
  /// In he, this message translates to:
  /// **'תג מאומת וקדימות בחיפוש'**
  String get paywallScreenFeatureVerifiedAndPriority;

  /// No description provided for @paywallScreenFeatureAiFiltering.
  ///
  /// In he, this message translates to:
  /// **'סינון שוכרים חכם ב-AI'**
  String get paywallScreenFeatureAiFiltering;

  /// No description provided for @paywallScreenThankYou.
  ///
  /// In he, this message translates to:
  /// **'תודה רבה!'**
  String get paywallScreenThankYou;

  /// No description provided for @paywallScreenWelcomePrefix.
  ///
  /// In he, this message translates to:
  /// **'המנוי הופעל — ברוכים הבאים ל-'**
  String get paywallScreenWelcomePrefix;

  /// No description provided for @paywallScreenReceiptSent.
  ///
  /// In he, this message translates to:
  /// **'קבלה נשלחה לכתובת המייל שלך'**
  String get paywallScreenReceiptSent;

  /// No description provided for @paywallScreenLetsStart.
  ///
  /// In he, this message translates to:
  /// **'בואו נתחיל'**
  String get paywallScreenLetsStart;

  /// No description provided for @rentTrackingScreenJanuary.
  ///
  /// In he, this message translates to:
  /// **'ינואר'**
  String get rentTrackingScreenJanuary;

  /// No description provided for @rentTrackingScreenFebruary.
  ///
  /// In he, this message translates to:
  /// **'פברואר'**
  String get rentTrackingScreenFebruary;

  /// No description provided for @rentTrackingScreenMarch.
  ///
  /// In he, this message translates to:
  /// **'מרץ'**
  String get rentTrackingScreenMarch;

  /// No description provided for @rentTrackingScreenApril.
  ///
  /// In he, this message translates to:
  /// **'אפריל'**
  String get rentTrackingScreenApril;

  /// No description provided for @rentTrackingScreenMay.
  ///
  /// In he, this message translates to:
  /// **'מאי'**
  String get rentTrackingScreenMay;

  /// No description provided for @rentTrackingScreenJune.
  ///
  /// In he, this message translates to:
  /// **'יוני'**
  String get rentTrackingScreenJune;

  /// No description provided for @rentTrackingScreenJuly.
  ///
  /// In he, this message translates to:
  /// **'יולי'**
  String get rentTrackingScreenJuly;

  /// No description provided for @rentTrackingScreenAugust.
  ///
  /// In he, this message translates to:
  /// **'אוגוסט'**
  String get rentTrackingScreenAugust;

  /// No description provided for @rentTrackingScreenSeptember.
  ///
  /// In he, this message translates to:
  /// **'ספטמבר'**
  String get rentTrackingScreenSeptember;

  /// No description provided for @rentTrackingScreenOctober.
  ///
  /// In he, this message translates to:
  /// **'אוקטובר'**
  String get rentTrackingScreenOctober;

  /// No description provided for @rentTrackingScreenNovember.
  ///
  /// In he, this message translates to:
  /// **'נובמבר'**
  String get rentTrackingScreenNovember;

  /// No description provided for @rentTrackingScreenDecember.
  ///
  /// In he, this message translates to:
  /// **'דצמבר'**
  String get rentTrackingScreenDecember;

  /// No description provided for @rentTrackingScreenNoteForMonth.
  ///
  /// In he, this message translates to:
  /// **'הערה לחודש'**
  String get rentTrackingScreenNoteForMonth;

  /// No description provided for @rentTrackingScreenNoteHint.
  ///
  /// In he, this message translates to:
  /// **'למשל: שולם במזומן / הבטיח לשלם ב-15'**
  String get rentTrackingScreenNoteHint;

  /// No description provided for @rentTrackingScreenCancel.
  ///
  /// In he, this message translates to:
  /// **'ביטול'**
  String get rentTrackingScreenCancel;

  /// No description provided for @rentTrackingScreenSave.
  ///
  /// In he, this message translates to:
  /// **'שמירה'**
  String get rentTrackingScreenSave;

  /// No description provided for @rentTrackingScreenTitle.
  ///
  /// In he, this message translates to:
  /// **'מעקב תשלומים'**
  String get rentTrackingScreenTitle;

  /// No description provided for @rentTrackingScreenAddMonth.
  ///
  /// In he, this message translates to:
  /// **'חודש נוסף'**
  String get rentTrackingScreenAddMonth;

  /// No description provided for @rentTrackingScreenCollectedThisMonth.
  ///
  /// In he, this message translates to:
  /// **'נגבה החודש'**
  String get rentTrackingScreenCollectedThisMonth;

  /// No description provided for @rentTrackingScreenDebt.
  ///
  /// In he, this message translates to:
  /// **'חוב'**
  String get rentTrackingScreenDebt;

  /// No description provided for @rentTrackingScreenPaid.
  ///
  /// In he, this message translates to:
  /// **'שולם'**
  String get rentTrackingScreenPaid;

  /// No description provided for @rentTrackingScreenUnpaid.
  ///
  /// In he, this message translates to:
  /// **'לא שולם'**
  String get rentTrackingScreenUnpaid;

  /// No description provided for @rentTrackingScreenNote.
  ///
  /// In he, this message translates to:
  /// **'הערה'**
  String get rentTrackingScreenNote;

  /// No description provided for @rentTrackingScreenNoTrackingYet.
  ///
  /// In he, this message translates to:
  /// **'עדיין לא עקבת אחרי תשלומים — נתחיל?'**
  String get rentTrackingScreenNoTrackingYet;

  /// No description provided for @rentTrackingScreenStartTracking.
  ///
  /// In he, this message translates to:
  /// **'התחל מעקב (12 חודשים)'**
  String get rentTrackingScreenStartTracking;

  /// No description provided for @rentTrackingScreenNoPropertiesToTrack.
  ///
  /// In he, this message translates to:
  /// **'אין דירות למעקב. הוסיפו דירה כדי להתחיל.'**
  String get rentTrackingScreenNoPropertiesToTrack;

  /// No description provided for @rentTrackingScreenMonthsOverdue.
  ///
  /// In he, this message translates to:
  /// **'{count} חודשים בפיגור'**
  String rentTrackingScreenMonthsOverdue(Object count);

  /// No description provided for @rentTrackingScreenPaidThisMonth.
  ///
  /// In he, this message translates to:
  /// **'שולם החודש'**
  String get rentTrackingScreenPaidThisMonth;

  /// No description provided for @rentTrackingScreenAwaitingPaymentThisMonth.
  ///
  /// In he, this message translates to:
  /// **'ממתין לתשלום החודש'**
  String get rentTrackingScreenAwaitingPaymentThisMonth;

  /// No description provided for @rentTrackingScreenNextChargeOn.
  ///
  /// In he, this message translates to:
  /// **'החיוב הבא: 1 ב{month}'**
  String rentTrackingScreenNextChargeOn(Object month);

  /// No description provided for @rentTrackingScreenDueByEndOf.
  ///
  /// In he, this message translates to:
  /// **'לתשלום עד סוף {month}'**
  String rentTrackingScreenDueByEndOf(Object month);

  /// No description provided for @rentTrackingScreenRentPerMonth.
  ///
  /// In he, this message translates to:
  /// **'{rent} לחודש'**
  String rentTrackingScreenRentPerMonth(Object rent);

  /// No description provided for @matchesScreenMinutesAgo.
  ///
  /// In he, this message translates to:
  /// **'לפני {minutes} דק׳'**
  String matchesScreenMinutesAgo(Object minutes);

  /// No description provided for @matchesScreenHoursAgo.
  ///
  /// In he, this message translates to:
  /// **'לפני {hours} שע׳'**
  String matchesScreenHoursAgo(Object hours);

  /// No description provided for @matchesScreenYesterday.
  ///
  /// In he, this message translates to:
  /// **'אתמול'**
  String get matchesScreenYesterday;

  /// No description provided for @matchesScreenDaysAgo.
  ///
  /// In he, this message translates to:
  /// **'לפני {days} ימים'**
  String matchesScreenDaysAgo(Object days);

  /// No description provided for @matchesScreenWeekAgo.
  ///
  /// In he, this message translates to:
  /// **'לפני שבוע'**
  String get matchesScreenWeekAgo;

  /// No description provided for @matchesScreenWeeksAgo.
  ///
  /// In he, this message translates to:
  /// **'לפני {weeks} שבועות'**
  String matchesScreenWeeksAgo(Object weeks);

  /// No description provided for @matchesScreenAddPrivateTag.
  ///
  /// In he, this message translates to:
  /// **'הוסף תגית פרטית'**
  String get matchesScreenAddPrivateTag;

  /// No description provided for @matchesScreenEditTag.
  ///
  /// In he, this message translates to:
  /// **'ערוך תגית'**
  String get matchesScreenEditTag;

  /// No description provided for @matchesScreenOnlyYouSeeTag.
  ///
  /// In he, this message translates to:
  /// **'רק אתה רואה אותה — לא נחשפת למועמד'**
  String get matchesScreenOnlyYouSeeTag;

  /// No description provided for @matchesScreenRemoveTag.
  ///
  /// In he, this message translates to:
  /// **'הסר תגית'**
  String get matchesScreenRemoveTag;

  /// No description provided for @matchesScreenUnmatch.
  ///
  /// In he, this message translates to:
  /// **'בטל התאמה'**
  String get matchesScreenUnmatch;

  /// No description provided for @matchesScreenConfirmUnmatchTitle.
  ///
  /// In he, this message translates to:
  /// **'לבטל את ההתאמה?'**
  String get matchesScreenConfirmUnmatchTitle;

  /// No description provided for @matchesScreenConfirmUnmatchBody.
  ///
  /// In he, this message translates to:
  /// **'השיחה תוסר משני הצדדים ולא ניתן לשחזר אותה.'**
  String get matchesScreenConfirmUnmatchBody;

  /// No description provided for @matchesScreenGoBack.
  ///
  /// In he, this message translates to:
  /// **'חזרה'**
  String get matchesScreenGoBack;

  /// No description provided for @matchesScreenPrivateTag.
  ///
  /// In he, this message translates to:
  /// **'תגית פרטית'**
  String get matchesScreenPrivateTag;

  /// No description provided for @matchesScreenPrivateTagHint.
  ///
  /// In he, this message translates to:
  /// **'רק אתה רואה — המועמד לא נחשף לזה.'**
  String get matchesScreenPrivateTagHint;

  /// No description provided for @matchesScreenTagPlaceholder.
  ///
  /// In he, this message translates to:
  /// **'למשל: רציני מאוד / לבדוק ערבים'**
  String get matchesScreenTagPlaceholder;

  /// No description provided for @matchesScreenSaveTag.
  ///
  /// In he, this message translates to:
  /// **'שמור תגית'**
  String get matchesScreenSaveTag;

  /// No description provided for @matchesScreenPaidInquiries.
  ///
  /// In he, this message translates to:
  /// **'פניות בתשלום'**
  String get matchesScreenPaidInquiries;

  /// No description provided for @matchesScreenConversations.
  ///
  /// In he, this message translates to:
  /// **'שיחות'**
  String get matchesScreenConversations;

  /// No description provided for @matchesScreenSearchHint.
  ///
  /// In he, this message translates to:
  /// **'חיפוש כתובת, עיר או הודעה...'**
  String get matchesScreenSearchHint;

  /// No description provided for @matchesScreenFilterAll.
  ///
  /// In he, this message translates to:
  /// **'הכל'**
  String get matchesScreenFilterAll;

  /// No description provided for @matchesScreenFilterNew.
  ///
  /// In he, this message translates to:
  /// **'חדש'**
  String get matchesScreenFilterNew;

  /// No description provided for @matchesScreenFilterOld.
  ///
  /// In he, this message translates to:
  /// **'ישן'**
  String get matchesScreenFilterOld;

  /// No description provided for @matchesScreenFilterMatchesTomorrow.
  ///
  /// In he, this message translates to:
  /// **'תואם למחר'**
  String get matchesScreenFilterMatchesTomorrow;

  /// No description provided for @matchesScreenNoResultsFound.
  ///
  /// In he, this message translates to:
  /// **'לא נמצאו תוצאות'**
  String get matchesScreenNoResultsFound;

  /// No description provided for @matchesScreenNoResultsForSearch.
  ///
  /// In he, this message translates to:
  /// **'לא נמצאו תוצאות עבור החיפוש הזה — נסה לשנות את הסינון.'**
  String get matchesScreenNoResultsForSearch;

  /// No description provided for @matchesScreenClearFilter.
  ///
  /// In he, this message translates to:
  /// **'נקה סינון'**
  String get matchesScreenClearFilter;

  /// No description provided for @matchesScreenSigned.
  ///
  /// In he, this message translates to:
  /// **'חתום'**
  String get matchesScreenSigned;

  /// No description provided for @matchesScreenContractSent.
  ///
  /// In he, this message translates to:
  /// **'חוזה נשלח'**
  String get matchesScreenContractSent;

  /// No description provided for @matchesScreenOpenConversation.
  ///
  /// In he, this message translates to:
  /// **'שיחה פתוחה'**
  String get matchesScreenOpenConversation;

  /// No description provided for @matchesScreenRoomsCount.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חדרים'**
  String matchesScreenRoomsCount(Object rooms);

  /// No description provided for @matchesScreenSquareMeters.
  ///
  /// In he, this message translates to:
  /// **'{size} מ״ר'**
  String matchesScreenSquareMeters(Object size);

  /// No description provided for @matchesScreenElevator.
  ///
  /// In he, this message translates to:
  /// **'מעלית'**
  String get matchesScreenElevator;

  /// No description provided for @matchesScreenAirConditioned.
  ///
  /// In he, this message translates to:
  /// **'ממוזגת'**
  String get matchesScreenAirConditioned;

  /// No description provided for @matchesScreenNew.
  ///
  /// In he, this message translates to:
  /// **'חדש'**
  String get matchesScreenNew;

  /// No description provided for @matchesScreenNewConversationReady.
  ///
  /// In he, this message translates to:
  /// **'שיחה חדשה מוכנה לפתיחה'**
  String get matchesScreenNewConversationReady;

  /// No description provided for @matchesScreenNoMatchesYet.
  ///
  /// In he, this message translates to:
  /// **'עוד אין התאמות'**
  String get matchesScreenNoMatchesYet;

  /// No description provided for @matchesScreenNoMatchesLandlordBody.
  ///
  /// In he, this message translates to:
  /// **'כשתאשר שוכרים מועמדים בסוויפים — ההתאמות יופיעו כאן.'**
  String get matchesScreenNoMatchesLandlordBody;

  /// No description provided for @matchesScreenNoMatchesTenantBody.
  ///
  /// In he, this message translates to:
  /// **'כשתאהב דירה ובעל הדירה יאשר אותך — ההתאמה תופיע כאן.'**
  String get matchesScreenNoMatchesTenantBody;

  /// No description provided for @brokerClientsScreenContactsPermissionNeeded.
  ///
  /// In he, this message translates to:
  /// **'צריך הרשאת גישה לאנשי קשר כדי לייבא'**
  String get brokerClientsScreenContactsPermissionNeeded;

  /// No description provided for @brokerClientsScreenNoContactsWithPhoneFound.
  ///
  /// In he, this message translates to:
  /// **'לא נמצאו אנשי קשר עם מספר טלפון'**
  String get brokerClientsScreenNoContactsWithPhoneFound;

  /// No description provided for @brokerClientsScreenContactsImported.
  ///
  /// In he, this message translates to:
  /// **'יובאו {count} אנשי קשר לפנקס'**
  String brokerClientsScreenContactsImported(Object count);

  /// No description provided for @brokerClientsScreenClientBook.
  ///
  /// In he, this message translates to:
  /// **'פנקס לקוחות'**
  String get brokerClientsScreenClientBook;

  /// No description provided for @brokerClientsScreenImportFromContacts.
  ///
  /// In he, this message translates to:
  /// **'ייבוא מאנשי קשר'**
  String get brokerClientsScreenImportFromContacts;

  /// No description provided for @brokerClientsScreenNewClient.
  ///
  /// In he, this message translates to:
  /// **'לקוח חדש'**
  String get brokerClientsScreenNewClient;

  /// No description provided for @brokerClientsScreenHotMatches.
  ///
  /// In he, this message translates to:
  /// **'התאמות חמות'**
  String get brokerClientsScreenHotMatches;

  /// No description provided for @brokerClientsScreenStrongMatchesWaiting.
  ///
  /// In he, this message translates to:
  /// **'{count} התאמות חזקות ממתינות'**
  String brokerClientsScreenStrongMatchesWaiting(Object count);

  /// No description provided for @brokerClientsScreenPropertiesThatFitClients.
  ///
  /// In he, this message translates to:
  /// **'נכסים שמתאימים ללקוחות שלך'**
  String get brokerClientsScreenPropertiesThatFitClients;

  /// No description provided for @brokerClientsScreenSale.
  ///
  /// In he, this message translates to:
  /// **'מכירה'**
  String get brokerClientsScreenSale;

  /// No description provided for @brokerClientsScreenRent.
  ///
  /// In he, this message translates to:
  /// **'השכרה'**
  String get brokerClientsScreenRent;

  /// No description provided for @brokerClientsScreenMinRoomsPlus.
  ///
  /// In he, this message translates to:
  /// **'{rooms}+ חדרים'**
  String brokerClientsScreenMinRoomsPlus(Object rooms);

  /// No description provided for @brokerClientsScreenBudgetUpTo.
  ///
  /// In he, this message translates to:
  /// **'עד {amount}'**
  String brokerClientsScreenBudgetUpTo(Object amount);

  /// No description provided for @brokerClientsScreenEdit.
  ///
  /// In he, this message translates to:
  /// **'עריכה'**
  String get brokerClientsScreenEdit;

  /// No description provided for @brokerClientsScreenDelete.
  ///
  /// In he, this message translates to:
  /// **'מחיקה'**
  String get brokerClientsScreenDelete;

  /// No description provided for @brokerClientsScreenMatchingProperties.
  ///
  /// In he, this message translates to:
  /// **'{count} נכסים מתאימים'**
  String brokerClientsScreenMatchingProperties(Object count);

  /// No description provided for @brokerClientsScreenNoMatchingPropertiesNow.
  ///
  /// In he, this message translates to:
  /// **'אין נכסים מתאימים כרגע'**
  String get brokerClientsScreenNoMatchingPropertiesNow;

  /// No description provided for @brokerClientsScreenPropertiesForClient.
  ///
  /// In he, this message translates to:
  /// **'נכסים ל{name}'**
  String brokerClientsScreenPropertiesForClient(Object name);

  /// No description provided for @brokerClientsScreenNoMatchingPropertiesForClient.
  ///
  /// In he, this message translates to:
  /// **'אין כרגע נכסים שמתאימים לדרישות של {name}.'**
  String brokerClientsScreenNoMatchingPropertiesForClient(Object name);

  /// No description provided for @brokerClientsScreenMatchWillAppearHere.
  ///
  /// In he, this message translates to:
  /// **'ברגע שתעלה נכס מתאים — הוא יופיע כאן.'**
  String get brokerClientsScreenMatchWillAppearHere;

  /// No description provided for @brokerClientsScreenPriceRoomsSummary.
  ///
  /// In he, this message translates to:
  /// **'{price} {suffix} · {rooms} חדרים'**
  String brokerClientsScreenPriceRoomsSummary(
      Object price, Object rooms, Object suffix);

  /// No description provided for @brokerClientsScreenEnterClientName.
  ///
  /// In he, this message translates to:
  /// **'נא להזין שם לקוח'**
  String get brokerClientsScreenEnterClientName;

  /// No description provided for @brokerClientsScreenEditClient.
  ///
  /// In he, this message translates to:
  /// **'עריכת לקוח'**
  String get brokerClientsScreenEditClient;

  /// No description provided for @brokerClientsScreenClientName.
  ///
  /// In he, this message translates to:
  /// **'שם הלקוח'**
  String get brokerClientsScreenClientName;

  /// No description provided for @brokerClientsScreenPhone.
  ///
  /// In he, this message translates to:
  /// **'טלפון'**
  String get brokerClientsScreenPhone;

  /// No description provided for @brokerClientsScreenBudgetFrom.
  ///
  /// In he, this message translates to:
  /// **'תקציב מ-'**
  String get brokerClientsScreenBudgetFrom;

  /// No description provided for @brokerClientsScreenBudgetTo.
  ///
  /// In he, this message translates to:
  /// **'תקציב עד'**
  String get brokerClientsScreenBudgetTo;

  /// No description provided for @brokerClientsScreenMinRooms.
  ///
  /// In he, this message translates to:
  /// **'מינימום חדרים'**
  String get brokerClientsScreenMinRooms;

  /// No description provided for @brokerClientsScreenAreasCommaSeparated.
  ///
  /// In he, this message translates to:
  /// **'אזורים (מופרדים בפסיק)'**
  String get brokerClientsScreenAreasCommaSeparated;

  /// No description provided for @brokerClientsScreenMustHaveCommaSeparated.
  ///
  /// In he, this message translates to:
  /// **'חובה שיכלול (מופרדים בפסיק)'**
  String get brokerClientsScreenMustHaveCommaSeparated;

  /// No description provided for @brokerClientsScreenNotes.
  ///
  /// In he, this message translates to:
  /// **'הערות'**
  String get brokerClientsScreenNotes;

  /// No description provided for @brokerClientsScreenSave.
  ///
  /// In he, this message translates to:
  /// **'שמירה'**
  String get brokerClientsScreenSave;

  /// No description provided for @brokerClientsScreenClientBookEmpty.
  ///
  /// In he, this message translates to:
  /// **'פנקס הלקוחות שלך ריק'**
  String get brokerClientsScreenClientBookEmpty;

  /// No description provided for @brokerClientsScreenEmptyStateBody.
  ///
  /// In he, this message translates to:
  /// **'הוסף לקוח עם מה שהוא מחפש, והאפליקציה תראה לך אילו מהנכסים שלך מתאימים לו.'**
  String get brokerClientsScreenEmptyStateBody;

  /// No description provided for @brokerClientsScreenSelectContactsToImport.
  ///
  /// In he, this message translates to:
  /// **'בחירת אנשי קשר לייבוא'**
  String get brokerClientsScreenSelectContactsToImport;

  /// No description provided for @brokerClientsScreenSelectedCount.
  ///
  /// In he, this message translates to:
  /// **'{count} נבחרו'**
  String brokerClientsScreenSelectedCount(Object count);

  /// No description provided for @brokerClientsScreenSearchContact.
  ///
  /// In he, this message translates to:
  /// **'חיפוש איש קשר…'**
  String get brokerClientsScreenSearchContact;

  /// No description provided for @brokerClientsScreenImportClients.
  ///
  /// In he, this message translates to:
  /// **'ייבא {count} לקוחות'**
  String brokerClientsScreenImportClients(Object count);

  /// No description provided for @panoramaAlignScreen88220aef.
  ///
  /// In he, this message translates to:
  /// **'אופקי'**
  String get panoramaAlignScreen88220aef;

  /// No description provided for @panoramaAlignScreenE4c00e1b.
  ///
  /// In he, this message translates to:
  /// **'תקרה'**
  String get panoramaAlignScreenE4c00e1b;

  /// No description provided for @panoramaAlignScreenDbb59c32.
  ///
  /// In he, this message translates to:
  /// **'רצפה'**
  String get panoramaAlignScreenDbb59c32;

  /// No description provided for @panoramaAlignScreenD798b826.
  ///
  /// In he, this message translates to:
  /// **'הוסיפו לפחות שתי פנורמות כדי להרכיב סיבוב מלא.'**
  String get panoramaAlignScreenD798b826;

  /// No description provided for @panoramaAlignScreenB2dac83d.
  ///
  /// In he, this message translates to:
  /// **'מתחילים להרכיב את ה-360°...'**
  String get panoramaAlignScreenB2dac83d;

  /// No description provided for @panoramaAlignScreen62c97e13.
  ///
  /// In he, this message translates to:
  /// **'לא הצלחנו להתחיל את ההרכבה. בדקו את החיבור לאינטרנט.'**
  String get panoramaAlignScreen62c97e13;

  /// No description provided for @panoramaAlignScreen47b1e23d.
  ///
  /// In he, this message translates to:
  /// **'מעלים פנורמות... {current}/{total}'**
  String panoramaAlignScreen47b1e23d(Object current, Object total);

  /// No description provided for @panoramaAlignScreenF18b60a5.
  ///
  /// In he, this message translates to:
  /// **'ההעלאה נכשלה באמצע. בדקו את החיבור ונסו שוב.'**
  String get panoramaAlignScreenF18b60a5;

  /// No description provided for @panoramaAlignScreenD2a25e0e.
  ///
  /// In he, this message translates to:
  /// **'מחברים את הפנורמות לסיבוב מלא...'**
  String get panoramaAlignScreenD2a25e0e;

  /// No description provided for @panoramaAlignScreenBc47a202.
  ///
  /// In he, this message translates to:
  /// **'ההרכבה נכשלה. נסו לסדר מחדש שתתקבל חפיפה ברורה בין הפנורמות.'**
  String get panoramaAlignScreenBc47a202;

  /// No description provided for @panoramaAlignScreen4a2e8e0f.
  ///
  /// In he, this message translates to:
  /// **'ההרכבה לוקחת יותר מדי זמן. נסו שוב מאוחר יותר.'**
  String get panoramaAlignScreen4a2e8e0f;

  /// No description provided for @panoramaAlignScreen19c26543.
  ///
  /// In he, this message translates to:
  /// **'משהו השתבש. בדקו את החיבור ונסו שוב.'**
  String get panoramaAlignScreen19c26543;

  /// No description provided for @panoramaAlignScreenFd743c18.
  ///
  /// In he, this message translates to:
  /// **'הרכבת 360° מכמה פנורמות'**
  String get panoramaAlignScreenFd743c18;

  /// No description provided for @panoramaAlignScreenCa889149.
  ///
  /// In he, this message translates to:
  /// **'גררו כדי לסדר על הסיבוב (0° → 360°)'**
  String get panoramaAlignScreenCa889149;

  /// No description provided for @panoramaAlignScreenFde6013b.
  ///
  /// In he, this message translates to:
  /// **'הפנורמות שלכם'**
  String get panoramaAlignScreenFde6013b;

  /// No description provided for @panoramaAlignScreenD58171d2.
  ///
  /// In he, this message translates to:
  /// **'הוסף פנורמה'**
  String get panoramaAlignScreenD58171d2;

  /// No description provided for @panoramaAlignScreenE0627abd.
  ///
  /// In he, this message translates to:
  /// **'סיים והרכב 360°'**
  String get panoramaAlignScreenE0627abd;

  /// No description provided for @panoramaAlignScreenAbe1f3b1.
  ///
  /// In he, this message translates to:
  /// **'צלמו פנורמה אחת בטלפון, ואז עוד אחת מהצד השני. הוסיפו אותן כאן וגררו '**
  String get panoramaAlignScreenAbe1f3b1;

  /// No description provided for @panoramaAlignScreenE0274901.
  ///
  /// In he, this message translates to:
  /// **'כדי שיתחברו לסיבוב מלא — אנחנו נחבר אותן ל-360° חלק.'**
  String get panoramaAlignScreenE0274901;

  /// No description provided for @panoramaAlignScreen8e131b97.
  ///
  /// In he, this message translates to:
  /// **'הוסיפו את הפנורמות שצילמתם'**
  String get panoramaAlignScreen8e131b97;

  /// No description provided for @panoramaAlignScreen6b5a2c3f.
  ///
  /// In he, this message translates to:
  /// **'כל פנורמה מכסה חלק מהסיבוב. הוסיפו שתיים או יותר.'**
  String get panoramaAlignScreen6b5a2c3f;

  /// No description provided for @panoramaAlignScreenDc8906c4.
  ///
  /// In he, this message translates to:
  /// **'כך נראה ה-360° שלכם'**
  String get panoramaAlignScreenDc8906c4;

  /// No description provided for @panoramaAlignScreen4d6407f1.
  ///
  /// In he, this message translates to:
  /// **'פנורמה {index}'**
  String panoramaAlignScreen4d6407f1(Object index);

  /// No description provided for @panoramaAlignScreen49cc29de.
  ///
  /// In he, this message translates to:
  /// **'{start}° → {end}° · רוחב {width}°'**
  String panoramaAlignScreen49cc29de(Object end, Object start, Object width);

  /// No description provided for @panoramaAlignScreenF877ef0d.
  ///
  /// In he, this message translates to:
  /// **'✂ נחתך {left}% משמאל · {right}% מימין'**
  String panoramaAlignScreenF877ef0d(Object left, Object right);

  /// No description provided for @panoramaAlignScreenC32b2bbf.
  ///
  /// In he, this message translates to:
  /// **'חתוך התאמה'**
  String get panoramaAlignScreenC32b2bbf;

  /// No description provided for @panoramaAlignScreen09b6bcca.
  ///
  /// In he, this message translates to:
  /// **'מחק'**
  String get panoramaAlignScreen09b6bcca;

  /// No description provided for @panoramaAlignScreenFc5d14c7.
  ///
  /// In he, this message translates to:
  /// **'חזרה לסידור'**
  String get panoramaAlignScreenFc5d14c7;

  /// No description provided for @panoramaAlignScreen55247199.
  ///
  /// In he, this message translates to:
  /// **'סגור'**
  String get panoramaAlignScreen55247199;

  /// No description provided for @panoramaAlignScreen9b77263e.
  ///
  /// In he, this message translates to:
  /// **'חתכו את הקצוות כדי שיתאים לפנורמה הסמוכה'**
  String get panoramaAlignScreen9b77263e;

  /// No description provided for @panoramaAlignScreen16d13bac.
  ///
  /// In he, this message translates to:
  /// **'גררו את הידיות פנימה כדי להסיר חפיפה או קצה לא טוב.'**
  String get panoramaAlignScreen16d13bac;

  /// No description provided for @panoramaAlignScreen40226151.
  ///
  /// In he, this message translates to:
  /// **'איפוס'**
  String get panoramaAlignScreen40226151;

  /// No description provided for @panoramaAlignScreen2e0134d2.
  ///
  /// In he, this message translates to:
  /// **'החל חיתוך'**
  String get panoramaAlignScreen2e0134d2;

  /// No description provided for @brokerPipelineScreenBb0a46bb.
  ///
  /// In he, this message translates to:
  /// **'ליד נסגר בהצלחה 🎉'**
  String get brokerPipelineScreenBb0a46bb;

  /// No description provided for @brokerPipelineScreen5f575001.
  ///
  /// In he, this message translates to:
  /// **'ליצור עסקה במעקב העמלות מהליד הזה?'**
  String get brokerPipelineScreen5f575001;

  /// No description provided for @brokerPipelineScreen98c8a5b8.
  ///
  /// In he, this message translates to:
  /// **'לא עכשיו'**
  String get brokerPipelineScreen98c8a5b8;

  /// No description provided for @brokerPipelineScreenA250d66b.
  ///
  /// In he, this message translates to:
  /// **'צור עסקה'**
  String get brokerPipelineScreenA250d66b;

  /// No description provided for @brokerPipelineScreenBf7fa86c.
  ///
  /// In he, this message translates to:
  /// **'נוצרה עסקה במעקב העמלות — בדוק את הסכום והוסף אחוז עמלה'**
  String get brokerPipelineScreenBf7fa86c;

  /// No description provided for @brokerPipelineScreenCdec8cf6.
  ///
  /// In he, this message translates to:
  /// **'נוצרה עסקה במעקב העמלות — השלם שם את הסכום'**
  String get brokerPipelineScreenCdec8cf6;

  /// No description provided for @brokerPipelineScreenD3e8fbc2.
  ///
  /// In he, this message translates to:
  /// **'הליד'**
  String get brokerPipelineScreenD3e8fbc2;

  /// No description provided for @brokerPipelineScreen02e8a635.
  ///
  /// In he, this message translates to:
  /// **'פולואפ ליד'**
  String get brokerPipelineScreen02e8a635;

  /// No description provided for @brokerPipelineScreenEef25736.
  ///
  /// In he, this message translates to:
  /// **'הגיע הזמן לחזור ל{who}{what}'**
  String brokerPipelineScreenEef25736(Object what, Object who);

  /// No description provided for @brokerPipelineScreen0a1cdb54.
  ///
  /// In he, this message translates to:
  /// **'פייפליין לידים'**
  String get brokerPipelineScreen0a1cdb54;

  /// No description provided for @brokerPipelineScreenEd8d552e.
  ///
  /// In he, this message translates to:
  /// **'ליד חדש'**
  String get brokerPipelineScreenEd8d552e;

  /// No description provided for @brokerPipelineScreen3dd4edb0.
  ///
  /// In he, this message translates to:
  /// **'אין עדיין לידים'**
  String get brokerPipelineScreen3dd4edb0;

  /// No description provided for @brokerPipelineScreen54c02219.
  ///
  /// In he, this message translates to:
  /// **'הוסיפו לקוח מתעניין כדי לעקוב אחריו עד לסגירה'**
  String get brokerPipelineScreen54c02219;

  /// No description provided for @brokerPipelineScreen1e8e9994.
  ///
  /// In he, this message translates to:
  /// **'פולואפ באיחור ({count})'**
  String brokerPipelineScreen1e8e9994(Object count);

  /// No description provided for @brokerPipelineScreen1aadec4d.
  ///
  /// In he, this message translates to:
  /// **'פולואפ: {date}'**
  String brokerPipelineScreen1aadec4d(Object date);

  /// No description provided for @brokerPipelineScreen313f6a17.
  ///
  /// In he, this message translates to:
  /// **'העברה לשלב:'**
  String get brokerPipelineScreen313f6a17;

  /// No description provided for @brokerPipelineScreenD0f162f9.
  ///
  /// In he, this message translates to:
  /// **'קביעת פולואפ'**
  String get brokerPipelineScreenD0f162f9;

  /// No description provided for @brokerPipelineScreen470fd4ec.
  ///
  /// In he, this message translates to:
  /// **'הסרת פולואפ'**
  String get brokerPipelineScreen470fd4ec;

  /// No description provided for @brokerPipelineScreenB00960b9.
  ///
  /// In he, this message translates to:
  /// **'מחיקת ליד'**
  String get brokerPipelineScreenB00960b9;

  /// No description provided for @brokerPipelineScreen737232c2.
  ///
  /// In he, this message translates to:
  /// **'טלפון'**
  String get brokerPipelineScreen737232c2;

  /// No description provided for @brokerPipelineScreen18d43ef8.
  ///
  /// In he, this message translates to:
  /// **'יש להזין שם לקוח'**
  String get brokerPipelineScreen18d43ef8;

  /// No description provided for @brokerPipelineScreen83c5428d.
  ///
  /// In he, this message translates to:
  /// **'שם הלקוח *'**
  String get brokerPipelineScreen83c5428d;

  /// No description provided for @brokerPipelineScreen350eef65.
  ///
  /// In he, this message translates to:
  /// **'מקור הליד:'**
  String get brokerPipelineScreen350eef65;

  /// No description provided for @brokerPipelineScreenE9adf7ad.
  ///
  /// In he, this message translates to:
  /// **'נכס מקושר:'**
  String get brokerPipelineScreenE9adf7ad;

  /// No description provided for @brokerPipelineScreenEdf6c5ad.
  ///
  /// In he, this message translates to:
  /// **'בחר נכס (לא חובה)'**
  String get brokerPipelineScreenEdf6c5ad;

  /// No description provided for @brokerPipelineScreenBf7d92b1.
  ///
  /// In he, this message translates to:
  /// **'ללא נכס'**
  String get brokerPipelineScreenBf7d92b1;

  /// No description provided for @brokerPipelineScreen92b0d682.
  ///
  /// In he, this message translates to:
  /// **'הערות'**
  String get brokerPipelineScreen92b0d682;

  /// No description provided for @brokerPipelineScreenE6932339.
  ///
  /// In he, this message translates to:
  /// **'שמירה'**
  String get brokerPipelineScreenE6932339;

  /// No description provided for @panoramaSphereCapture40cd556b.
  ///
  /// In he, this message translates to:
  /// **'הכדור הושלם ✓ — במכשיר אמיתי זה נבנה עכשיו ל-360° מלא.'**
  String get panoramaSphereCapture40cd556b;

  /// No description provided for @panoramaSphereCapture97f6b247.
  ///
  /// In he, this message translates to:
  /// **'מתחילים לבנות את הסיור...'**
  String get panoramaSphereCapture97f6b247;

  /// No description provided for @panoramaSphereCapture127d1554.
  ///
  /// In he, this message translates to:
  /// **'לא הצלחנו להתחיל את העיבוד. בדקו את החיבור לאינטרנט.'**
  String get panoramaSphereCapture127d1554;

  /// No description provided for @panoramaSphereCaptureE39b6aae.
  ///
  /// In he, this message translates to:
  /// **'מעלים את התמונות...'**
  String get panoramaSphereCaptureE39b6aae;

  /// No description provided for @panoramaSphereCaptureBbb9c298.
  ///
  /// In he, this message translates to:
  /// **'ההעלאה נכשלה. בדקו את החיבור ונסו שוב.'**
  String get panoramaSphereCaptureBbb9c298;

  /// No description provided for @panoramaSphereCapture1b311f3a.
  ///
  /// In he, this message translates to:
  /// **'מעלים את התמונות... ({current}/{total})'**
  String panoramaSphereCapture1b311f3a(Object current, Object total);

  /// No description provided for @panoramaSphereCapture8844cc68.
  ///
  /// In he, this message translates to:
  /// **'בונים את הסיור...'**
  String get panoramaSphereCapture8844cc68;

  /// No description provided for @panoramaSphereCaptureA9e373df.
  ///
  /// In he, this message translates to:
  /// **'העיבוד נכשל. נסו לצלם שוב, לאט ובאור טוב.'**
  String get panoramaSphereCaptureA9e373df;

  /// No description provided for @panoramaSphereCaptureAb4f63ba.
  ///
  /// In he, this message translates to:
  /// **'העיבוד לוקח יותר מדי זמן. נסו שוב מאוחר יותר.'**
  String get panoramaSphereCaptureAb4f63ba;

  /// No description provided for @panoramaSphereCapture19c26543.
  ///
  /// In he, this message translates to:
  /// **'משהו השתבש. בדקו את החיבור ונסו שוב.'**
  String get panoramaSphereCapture19c26543;

  /// No description provided for @panoramaSphereCapture70b265d7.
  ///
  /// In he, this message translates to:
  /// **'הכדור הושלם ✓'**
  String get panoramaSphereCapture70b265d7;

  /// No description provided for @panoramaSphereCapture84b777d5.
  ///
  /// In he, this message translates to:
  /// **'צולמו {captured} מתוך {total}'**
  String panoramaSphereCapture84b777d5(Object captured, Object total);

  /// No description provided for @panoramaSphereCaptureE97ca842.
  ///
  /// In he, this message translates to:
  /// **'מצוין! בונים את הסיור...'**
  String get panoramaSphereCaptureE97ca842;

  /// No description provided for @panoramaSphereCaptureFaa5a7cd.
  ///
  /// In he, this message translates to:
  /// **'האטו — החזיקו יציב על הנקודה'**
  String get panoramaSphereCaptureFaa5a7cd;

  /// No description provided for @panoramaSphereCaptureCbe90974.
  ///
  /// In he, this message translates to:
  /// **'החזיקו רגע... ננעל ומצלם 📸'**
  String get panoramaSphereCaptureCbe90974;

  /// No description provided for @panoramaSphereCapture329e59af.
  ///
  /// In he, this message translates to:
  /// **'הרימו את הטלפון למעלה ☝️'**
  String get panoramaSphereCapture329e59af;

  /// No description provided for @panoramaSphereCapture3802a2f9.
  ///
  /// In he, this message translates to:
  /// **'הטו את הטלפון למטה 👇'**
  String get panoramaSphereCapture3802a2f9;

  /// No description provided for @panoramaSphereCaptureCc0c751f.
  ///
  /// In he, this message translates to:
  /// **'סובבו ימינה ➡️'**
  String get panoramaSphereCaptureCc0c751f;

  /// No description provided for @panoramaSphereCapture39ad314d.
  ///
  /// In he, this message translates to:
  /// **'סובבו שמאלה ⬅️'**
  String get panoramaSphereCapture39ad314d;

  /// No description provided for @panoramaSphereCapture1502911e.
  ///
  /// In he, this message translates to:
  /// **'כוונו את הנקודה למרכז — {dir}'**
  String panoramaSphereCapture1502911e(Object dir);

  /// No description provided for @panoramaSphereCaptureF1c50330.
  ///
  /// In he, this message translates to:
  /// **'כוונו את הנקודה הזוהרת אל המרכז'**
  String get panoramaSphereCaptureF1c50330;

  /// No description provided for @panoramaSphereCapture1c86586d.
  ///
  /// In he, this message translates to:
  /// **'כוונו קרוב יותר לנקודה לא-מצולמת'**
  String get panoramaSphereCapture1c86586d;

  /// No description provided for @panoramaSphereCaptureC1c39e62.
  ///
  /// In he, this message translates to:
  /// **'צלמו את הנקודה שבמרכז'**
  String get panoramaSphereCaptureC1c39e62;

  /// No description provided for @panoramaSphereCapture1dc38c15.
  ///
  /// In he, this message translates to:
  /// **'לא הצלחנו לבנות את הסיור'**
  String get panoramaSphereCapture1dc38c15;

  /// No description provided for @panoramaSphereCapture5a8e3f2d.
  ///
  /// In he, this message translates to:
  /// **'{buildMsg}\n\nאפשר להמתין כמה רגעים — אל תסגרו את המסך.'**
  String panoramaSphereCapture5a8e3f2d(Object buildMsg);

  /// No description provided for @panoramaSphereCapture3b32c520.
  ///
  /// In he, this message translates to:
  /// **'צלם מחדש'**
  String get panoramaSphereCapture3b32c520;

  /// No description provided for @panoramaSphereCapture55247199.
  ///
  /// In he, this message translates to:
  /// **'סגור'**
  String get panoramaSphereCapture55247199;

  /// No description provided for @panoramaSphereCaptureA9e4f107.
  ///
  /// In he, this message translates to:
  /// **'רחב'**
  String get panoramaSphereCaptureA9e4f107;

  /// No description provided for @panoramaSphereCapture3e20e30e.
  ///
  /// In he, this message translates to:
  /// **'רגיל'**
  String get panoramaSphereCapture3e20e30e;

  /// No description provided for @panoramaSphereCapture8fc9dc18.
  ///
  /// In he, this message translates to:
  /// **'מצב הדגמה (סימולטור)\nגררו כדי לכוון'**
  String get panoramaSphereCapture8fc9dc18;

  /// No description provided for @tenantDetailScreenE45aa6fe.
  ///
  /// In he, this message translates to:
  /// **'מחפש/ת דירה · משתמש מאומת'**
  String get tenantDetailScreenE45aa6fe;

  /// No description provided for @tenantDetailScreen54b54821.
  ///
  /// In he, this message translates to:
  /// **'מה הוא מחפש'**
  String get tenantDetailScreen54b54821;

  /// No description provided for @tenantDetailScreenDc721374.
  ///
  /// In he, this message translates to:
  /// **'למה ההתאמה הזו'**
  String get tenantDetailScreenDc721374;

  /// No description provided for @tenantDetailScreen342759aa.
  ///
  /// In he, this message translates to:
  /// **'הנכס שאהב'**
  String get tenantDetailScreen342759aa;

  /// No description provided for @tenantDetailScreenAede4a6e.
  ///
  /// In he, this message translates to:
  /// **'קצת עליו'**
  String get tenantDetailScreenAede4a6e;

  /// No description provided for @tenantDetailScreen64680a66.
  ///
  /// In he, this message translates to:
  /// **'מאפיינים חשובים'**
  String get tenantDetailScreen64680a66;

  /// No description provided for @tenantDetailScreen64967671.
  ///
  /// In he, this message translates to:
  /// **'תנאים שאינם לדיון'**
  String get tenantDetailScreen64967671;

  /// No description provided for @tenantDetailScreen6987e12c.
  ///
  /// In he, this message translates to:
  /// **'המלצות מבעלי דירות'**
  String get tenantDetailScreen6987e12c;

  /// No description provided for @tenantDetailScreenB4cc85ed.
  ///
  /// In he, this message translates to:
  /// **'מחפש דירה'**
  String get tenantDetailScreenB4cc85ed;

  /// No description provided for @tenantDetailScreen548d9521.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חדרים · {moveIn}'**
  String tenantDetailScreen548d9521(Object moveIn, Object rooms);

  /// No description provided for @tenantDetailScreen0ee38ad3.
  ///
  /// In he, this message translates to:
  /// **'תקציב מקסימלי'**
  String get tenantDetailScreen0ee38ad3;

  /// No description provided for @tenantDetailScreenB50b3974.
  ///
  /// In he, this message translates to:
  /// **'חדרים'**
  String get tenantDetailScreenB50b3974;

  /// No description provided for @tenantDetailScreen1399cd87.
  ///
  /// In he, this message translates to:
  /// **'מועד כניסה'**
  String get tenantDetailScreen1399cd87;

  /// No description provided for @tenantDetailScreenC7f6f4e8.
  ///
  /// In he, this message translates to:
  /// **'נקודות אמון'**
  String get tenantDetailScreenC7f6f4e8;

  /// No description provided for @tenantDetailScreen0333a357.
  ///
  /// In he, this message translates to:
  /// **'לפי ההעדפות שלך מול הנכס שאהב'**
  String get tenantDetailScreen0333a357;

  /// No description provided for @tenantDetailScreen9bf902f4.
  ///
  /// In he, this message translates to:
  /// **'תקציב עד ₪{budget} — מכסה את דמי השכירות (₪{price})'**
  String tenantDetailScreen9bf902f4(Object budget, Object price);

  /// No description provided for @tenantDetailScreenDe6e13c4.
  ///
  /// In he, this message translates to:
  /// **'תקציב עד ₪{budget} — מתחת לדמי השכירות (₪{price})'**
  String tenantDetailScreenDe6e13c4(Object budget, Object price);

  /// No description provided for @tenantDetailScreen1e958c2f.
  ///
  /// In he, this message translates to:
  /// **'מחפש {rooms} חדרים — תואם לנכס ({propRooms})'**
  String tenantDetailScreen1e958c2f(Object propRooms, Object rooms);

  /// No description provided for @tenantDetailScreenB8e3e192.
  ///
  /// In he, this message translates to:
  /// **'מחפש {rooms} חדרים — הנכס {propRooms} חדרים'**
  String tenantDetailScreenB8e3e192(Object propRooms, Object rooms);

  /// No description provided for @tenantDetailScreen12c58e28.
  ///
  /// In he, this message translates to:
  /// **'זמין לכניסה: {moveIn}'**
  String tenantDetailScreen12c58e28(Object moveIn);

  /// No description provided for @tenantDetailScreenE3b82a80.
  ///
  /// In he, this message translates to:
  /// **'ציין: {details}'**
  String tenantDetailScreenE3b82a80(Object details);

  /// No description provided for @tenantDetailScreen0e27d010.
  ///
  /// In he, this message translates to:
  /// **'התאמה מושלמת'**
  String get tenantDetailScreen0e27d010;

  /// No description provided for @tenantDetailScreen716b886b.
  ///
  /// In he, this message translates to:
  /// **'התאמה מצוינת'**
  String get tenantDetailScreen716b886b;

  /// No description provided for @tenantDetailScreenAb92611a.
  ///
  /// In he, this message translates to:
  /// **'התאמה טובה'**
  String get tenantDetailScreenAb92611a;

  /// No description provided for @tenantDetailScreen758f13a3.
  ///
  /// In he, this message translates to:
  /// **'התאמה סבירה'**
  String get tenantDetailScreen758f13a3;

  /// No description provided for @tenantDetailScreenD886d07f.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חדרים'**
  String tenantDetailScreenD886d07f(Object rooms);

  /// No description provided for @tenantDetailScreenFdb4eac7.
  ///
  /// In he, this message translates to:
  /// **'{size} מ״ר'**
  String tenantDetailScreenFdb4eac7(Object size);

  /// No description provided for @tenantDetailScreen6c58947e.
  ///
  /// In he, this message translates to:
  /// **'בעל דירה קודם'**
  String get tenantDetailScreen6c58947e;

  /// No description provided for @tenantDetailScreen80a413c5.
  ///
  /// In he, this message translates to:
  /// **'דלג'**
  String get tenantDetailScreen80a413c5;

  /// No description provided for @tenantDetailScreen96c6fb01.
  ///
  /// In he, this message translates to:
  /// **'אהבתי · צור קשר'**
  String get tenantDetailScreen96c6fb01;

  /// No description provided for @brokerExclusivityScreen3c0b6cc3.
  ///
  /// In he, this message translates to:
  /// **'הבלעדיות'**
  String get brokerExclusivityScreen3c0b6cc3;

  /// No description provided for @brokerExclusivityScreen8706412d.
  ///
  /// In he, this message translates to:
  /// **'הבלעדיות על {title}'**
  String brokerExclusivityScreen8706412d(Object title);

  /// No description provided for @brokerExclusivityScreen4b882a37.
  ///
  /// In he, this message translates to:
  /// **'חידוש בלעדיות'**
  String get brokerExclusivityScreen4b882a37;

  /// No description provided for @brokerExclusivityScreen7c5814c0.
  ///
  /// In he, this message translates to:
  /// **'{what} מסתיימת ב-{date}. כדאי לחדש לפני שתפוג.'**
  String brokerExclusivityScreen7c5814c0(Object date, Object what);

  /// No description provided for @brokerExclusivityScreenCff70eb7.
  ///
  /// In he, this message translates to:
  /// **'למחוק את הבלעדיות?'**
  String get brokerExclusivityScreenCff70eb7;

  /// No description provided for @brokerExclusivityScreen88ad6f14.
  ///
  /// In he, this message translates to:
  /// **'הרשומה תימחק לצמיתות.'**
  String get brokerExclusivityScreen88ad6f14;

  /// No description provided for @brokerExclusivityScreen50999a4f.
  ///
  /// In he, this message translates to:
  /// **'\"{title}\" תימחק לצמיתות.'**
  String brokerExclusivityScreen50999a4f(Object title);

  /// No description provided for @brokerExclusivityScreenA7c55a8d.
  ///
  /// In he, this message translates to:
  /// **'ביטול'**
  String get brokerExclusivityScreenA7c55a8d;

  /// No description provided for @brokerExclusivityScreen09b6bcca.
  ///
  /// In he, this message translates to:
  /// **'מחק'**
  String get brokerExclusivityScreen09b6bcca;

  /// No description provided for @brokerExclusivityScreen48eff0e3.
  ///
  /// In he, this message translates to:
  /// **'בלעדיות'**
  String get brokerExclusivityScreen48eff0e3;

  /// No description provided for @brokerExclusivityScreen3280ed69.
  ///
  /// In he, this message translates to:
  /// **'בלעדיות חדשה'**
  String get brokerExclusivityScreen3280ed69;

  /// No description provided for @brokerExclusivityScreenD408aab3.
  ///
  /// In he, this message translates to:
  /// **'אין בלעדיות פעילה.\nהוסף בלעדיות כדי לעקוב אחר תאריך הסיום.'**
  String get brokerExclusivityScreenD408aab3;

  /// No description provided for @brokerExclusivityScreen17b73df9.
  ///
  /// In he, this message translates to:
  /// **'הבלעדיות פגה לפני {days} ימים'**
  String brokerExclusivityScreen17b73df9(Object days);

  /// No description provided for @brokerExclusivityScreen95962fc0.
  ///
  /// In he, this message translates to:
  /// **'בלעדיות מסתיימת בעוד {days} ימים'**
  String brokerExclusivityScreen95962fc0(Object days);

  /// No description provided for @brokerExclusivityScreen99135f8c.
  ///
  /// In he, this message translates to:
  /// **'בתוקף · עוד {days} ימים'**
  String brokerExclusivityScreen99135f8c(Object days);

  /// No description provided for @brokerExclusivityScreen43b54956.
  ///
  /// In he, this message translates to:
  /// **'נכס ללא שם'**
  String get brokerExclusivityScreen43b54956;

  /// No description provided for @brokerExclusivityScreenAe97df84.
  ///
  /// In he, this message translates to:
  /// **'עמלה: {pct}%'**
  String brokerExclusivityScreenAe97df84(Object pct);

  /// No description provided for @brokerExclusivityScreen39fe2593.
  ///
  /// In he, this message translates to:
  /// **'עריכה'**
  String get brokerExclusivityScreen39fe2593;

  /// No description provided for @brokerExclusivityScreen7c8173fa.
  ///
  /// In he, this message translates to:
  /// **'מחיקה'**
  String get brokerExclusivityScreen7c8173fa;

  /// No description provided for @brokerExclusivityScreenFaaeacbe.
  ///
  /// In he, this message translates to:
  /// **'עריכת בלעדיות'**
  String get brokerExclusivityScreenFaaeacbe;

  /// No description provided for @brokerExclusivityScreenBa9fc140.
  ///
  /// In he, this message translates to:
  /// **'כתובת / שם הנכס'**
  String get brokerExclusivityScreenBa9fc140;

  /// No description provided for @brokerExclusivityScreen1d306e9d.
  ///
  /// In he, this message translates to:
  /// **'שם בעל הנכס'**
  String get brokerExclusivityScreen1d306e9d;

  /// No description provided for @brokerExclusivityScreenB8f119f3.
  ///
  /// In he, this message translates to:
  /// **'טלפון בעל הנכס'**
  String get brokerExclusivityScreenB8f119f3;

  /// No description provided for @brokerExclusivityScreen7ac184b0.
  ///
  /// In he, this message translates to:
  /// **'אחוז עמלה (%)'**
  String get brokerExclusivityScreen7ac184b0;

  /// No description provided for @brokerExclusivityScreen2920ef89.
  ///
  /// In he, this message translates to:
  /// **'תחילת בלעדיות'**
  String get brokerExclusivityScreen2920ef89;

  /// No description provided for @brokerExclusivityScreen27dd66e7.
  ///
  /// In he, this message translates to:
  /// **'סיום בלעדיות'**
  String get brokerExclusivityScreen27dd66e7;

  /// No description provided for @brokerExclusivityScreen92b0d682.
  ///
  /// In he, this message translates to:
  /// **'הערות'**
  String get brokerExclusivityScreen92b0d682;

  /// No description provided for @brokerExclusivityScreenE6932339.
  ///
  /// In he, this message translates to:
  /// **'שמירה'**
  String get brokerExclusivityScreenE6932339;

  /// No description provided for @remindersScreen409fc735.
  ///
  /// In he, this message translates to:
  /// **'תזכורת'**
  String get remindersScreen409fc735;

  /// No description provided for @remindersScreenF6789864.
  ///
  /// In he, this message translates to:
  /// **'התזכורת נשמרה'**
  String get remindersScreenF6789864;

  /// No description provided for @remindersScreenCa25d18a.
  ///
  /// In he, this message translates to:
  /// **'תזכורות'**
  String get remindersScreenCa25d18a;

  /// No description provided for @remindersScreen1d935aa3.
  ///
  /// In he, this message translates to:
  /// **'תזכורת חדשה'**
  String get remindersScreen1d935aa3;

  /// No description provided for @remindersScreen9d1d367d.
  ///
  /// In he, this message translates to:
  /// **'סיום חוזה'**
  String get remindersScreen9d1d367d;

  /// No description provided for @remindersScreen3e064b53.
  ///
  /// In he, this message translates to:
  /// **'אין חוזים חתומים כרגע. כשתחתום על חוזה, '**
  String get remindersScreen3e064b53;

  /// No description provided for @remindersScreen4c157f3a.
  ///
  /// In he, this message translates to:
  /// **'נזכיר לך חודש ושבוע לפני שהוא מסתיים.'**
  String get remindersScreen4c157f3a;

  /// No description provided for @remindersScreen3c8688c4.
  ///
  /// In he, this message translates to:
  /// **'תזכורות שלי'**
  String get remindersScreen3c8688c4;

  /// No description provided for @remindersScreen4ae2e566.
  ///
  /// In he, this message translates to:
  /// **'כאן לא שוכחים. נזכיר לך מתי חוזה עומד להסתיים ומתי לגבות שכר דירה.'**
  String get remindersScreen4ae2e566;

  /// No description provided for @remindersScreen3b042ffd.
  ///
  /// In he, this message translates to:
  /// **'הדירה'**
  String get remindersScreen3b042ffd;

  /// No description provided for @remindersScreenBf84b357.
  ///
  /// In he, this message translates to:
  /// **'החוזה כבר הסתיים'**
  String get remindersScreenBf84b357;

  /// No description provided for @remindersScreen9d434107.
  ///
  /// In he, this message translates to:
  /// **'החוזה מסתיים היום'**
  String get remindersScreen9d434107;

  /// No description provided for @remindersScreen4d2730e7.
  ///
  /// In he, this message translates to:
  /// **'מסתיים מחר'**
  String get remindersScreen4d2730e7;

  /// No description provided for @remindersScreenC67b1a11.
  ///
  /// In he, this message translates to:
  /// **'מסתיים בעוד {days} ימים'**
  String remindersScreenC67b1a11(Object days);

  /// No description provided for @remindersScreenD66ef141.
  ///
  /// In he, this message translates to:
  /// **'החוזה בדירה \"{title}\"'**
  String remindersScreenD66ef141(Object title);

  /// No description provided for @remindersScreenD0680cb9.
  ///
  /// In he, this message translates to:
  /// **'התזכורת הועברה לארכיון'**
  String get remindersScreenD0680cb9;

  /// No description provided for @remindersScreen0ee389c1.
  ///
  /// In he, this message translates to:
  /// **'אין תזכורות אישיות. אפשר להוסיף, למשל: \"לגבות שכר ב-10 בחודש\".'**
  String get remindersScreen0ee389c1;

  /// No description provided for @remindersScreenC6e2f375.
  ///
  /// In he, this message translates to:
  /// **'פעולות'**
  String get remindersScreenC6e2f375;

  /// No description provided for @remindersScreen39fe2593.
  ///
  /// In he, this message translates to:
  /// **'עריכה'**
  String get remindersScreen39fe2593;

  /// No description provided for @remindersScreenEd0727e5.
  ///
  /// In he, this message translates to:
  /// **'העברה לארכיון'**
  String get remindersScreenEd0727e5;

  /// No description provided for @remindersScreen7c8173fa.
  ///
  /// In he, this message translates to:
  /// **'מחיקה'**
  String get remindersScreen7c8173fa;

  /// No description provided for @remindersScreen6ee55398.
  ///
  /// In he, this message translates to:
  /// **'לגבות שכר דירה'**
  String get remindersScreen6ee55398;

  /// No description provided for @remindersScreen8dcb89b4.
  ///
  /// In he, this message translates to:
  /// **'מה להזכיר לך?'**
  String get remindersScreen8dcb89b4;

  /// No description provided for @remindersScreen634d3915.
  ///
  /// In he, this message translates to:
  /// **'למשל: לגבות שכר ב-10 בחודש'**
  String get remindersScreen634d3915;

  /// No description provided for @remindersScreenFa3782fd.
  ///
  /// In he, this message translates to:
  /// **'מתי: {when}'**
  String remindersScreenFa3782fd(Object when);

  /// No description provided for @remindersScreen276878c2.
  ///
  /// In he, this message translates to:
  /// **'שמירת תזכורת'**
  String get remindersScreen276878c2;

  /// No description provided for @profileCardB9fe4671.
  ///
  /// In he, this message translates to:
  /// **'♥ מתאים'**
  String get profileCardB9fe4671;

  /// No description provided for @profileCard80a413c5.
  ///
  /// In he, this message translates to:
  /// **'דלג'**
  String get profileCard80a413c5;

  /// No description provided for @profileCardF0f71ca3.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חדרים'**
  String profileCardF0f71ca3(Object rooms);

  /// No description provided for @profileCardD8b6113c.
  ///
  /// In he, this message translates to:
  /// **'{size} מ\"ר'**
  String profileCardD8b6113c(Object size);

  /// No description provided for @profileCard77d9ac8f.
  ///
  /// In he, this message translates to:
  /// **'קומה {floor}'**
  String profileCard77d9ac8f(Object floor);

  /// No description provided for @profileCardF069621c.
  ///
  /// In he, this message translates to:
  /// **'₪{perM2}/מ\"ר'**
  String profileCardF069621c(Object perM2);

  /// No description provided for @profileCardEa9a5392.
  ///
  /// In he, this message translates to:
  /// **'תיווך מאומת'**
  String get profileCardEa9a5392;

  /// No description provided for @profileCard6fd38fe6.
  ///
  /// In he, this message translates to:
  /// **'בעלים פרטי'**
  String get profileCard6fd38fe6;

  /// No description provided for @profileCard9077b7f7.
  ///
  /// In he, this message translates to:
  /// **'מאומתת'**
  String get profileCard9077b7f7;

  /// No description provided for @profileCard2af4ac1c.
  ///
  /// In he, this message translates to:
  /// **'{score}% התאמה'**
  String profileCard2af4ac1c(Object score);

  /// No description provided for @profileCard8342a66c.
  ///
  /// In he, this message translates to:
  /// **'מקודם'**
  String get profileCard8342a66c;

  /// No description provided for @profileCard609fac18.
  ///
  /// In he, this message translates to:
  /// **'למכירה'**
  String get profileCard609fac18;

  /// No description provided for @profileCard6f21a73d.
  ///
  /// In he, this message translates to:
  /// **'מחיר מעולה'**
  String get profileCard6f21a73d;

  /// No description provided for @profileCard3af1f153.
  ///
  /// In he, this message translates to:
  /// **'מחיר מעל הממוצע'**
  String get profileCard3af1f153;

  /// No description provided for @profileCardE310e6a5.
  ///
  /// In he, this message translates to:
  /// **'דיווח על מודעה'**
  String get profileCardE310e6a5;

  /// No description provided for @profileCard90b9bf3d.
  ///
  /// In he, this message translates to:
  /// **'חסום משתמש זה'**
  String get profileCard90b9bf3d;

  /// No description provided for @profileCard07c60eb7.
  ///
  /// In he, this message translates to:
  /// **'מידע שגוי'**
  String get profileCard07c60eb7;

  /// No description provided for @profileCard05a76ba7.
  ///
  /// In he, this message translates to:
  /// **'תמונות מזויפות'**
  String get profileCard05a76ba7;

  /// No description provided for @profileCard5a660a20.
  ///
  /// In he, this message translates to:
  /// **'תוכן פוגעני'**
  String get profileCard5a660a20;

  /// No description provided for @profileCard678b6deb.
  ///
  /// In he, this message translates to:
  /// **'הונאה'**
  String get profileCard678b6deb;

  /// No description provided for @profileCardCdf4bce0.
  ///
  /// In he, this message translates to:
  /// **'אחר'**
  String get profileCardCdf4bce0;

  /// No description provided for @profileCard356f7af6.
  ///
  /// In he, this message translates to:
  /// **'סיבת הדיווח'**
  String get profileCard356f7af6;

  /// No description provided for @profileCard30c55079.
  ///
  /// In he, this message translates to:
  /// **'הדיווח נשלח. תודה.'**
  String get profileCard30c55079;

  /// No description provided for @profileCard00fe742b.
  ///
  /// In he, this message translates to:
  /// **'חסימת משתמש'**
  String get profileCard00fe742b;

  /// No description provided for @profileCard9e821d65.
  ///
  /// In he, this message translates to:
  /// **'האם לחסום את \"{owner}\"? כל המודעות שלהם יוסרו מהעדכון שלך.'**
  String profileCard9e821d65(Object owner);

  /// No description provided for @profileCardA7c55a8d.
  ///
  /// In he, this message translates to:
  /// **'ביטול'**
  String get profileCardA7c55a8d;

  /// No description provided for @profileCard367b7d06.
  ///
  /// In he, this message translates to:
  /// **'\"{owner}\" נחסם בהצלחה.'**
  String profileCard367b7d06(Object owner);

  /// No description provided for @profileCard1257849a.
  ///
  /// In he, this message translates to:
  /// **'חסום'**
  String get profileCard1257849a;

  /// No description provided for @tenantRightsSheet09a76cb1.
  ///
  /// In he, this message translates to:
  /// **'הזכויות שלכם כשוכרים'**
  String get tenantRightsSheet09a76cb1;

  /// No description provided for @tenantRightsSheet26a4104a.
  ///
  /// In he, this message translates to:
  /// **'הפיקדון מוגבל בחוק'**
  String get tenantRightsSheet26a4104a;

  /// No description provided for @tenantRightsSheet5ea0f907.
  ///
  /// In he, this message translates to:
  /// **'לפי חוק שכירות הוגנת 2017, פיקדון במזומן/ערבות '**
  String get tenantRightsSheet5ea0f907;

  /// No description provided for @tenantRightsSheet998fde48.
  ///
  /// In he, this message translates to:
  /// **'מוגבל ל-₪{cap}. זה הסכום המרבי שמותר לבקש '**
  String tenantRightsSheet998fde48(Object cap);

  /// No description provided for @tenantRightsSheetDaadfc3a.
  ///
  /// In he, this message translates to:
  /// **'מכם בנכס הזה (הנמוך מבין ⅓ מסך השכירות לכל '**
  String get tenantRightsSheetDaadfc3a;

  /// No description provided for @tenantRightsSheet30650421.
  ///
  /// In he, this message translates to:
  /// **'התקופה או 3 חודשי שכירות).\n\n'**
  String get tenantRightsSheet30650421;

  /// No description provided for @tenantRightsSheet74e1f7e7.
  ///
  /// In he, this message translates to:
  /// **'בטוחות = כסף או ערבות שמשאירים אצל בעל הדירה '**
  String get tenantRightsSheet74e1f7e7;

  /// No description provided for @tenantRightsSheetFd0085dc.
  ///
  /// In he, this message translates to:
  /// **'להבטחת ההסכם, ומוחזרים בסוף השכירות.'**
  String get tenantRightsSheetFd0085dc;

  /// No description provided for @tenantRightsSheet8bed726a.
  ///
  /// In he, this message translates to:
  /// **'מוגבל לנמוך מבין ⅓ מסך השכירות לכל התקופה או '**
  String get tenantRightsSheet8bed726a;

  /// No description provided for @tenantRightsSheetC9040c39.
  ///
  /// In he, this message translates to:
  /// **'3 חודשי שכירות.'**
  String get tenantRightsSheetC9040c39;

  /// No description provided for @tenantRightsSheet331175e3.
  ///
  /// In he, this message translates to:
  /// **'דמי תיווך — רק אם חתמתם'**
  String get tenantRightsSheet331175e3;

  /// No description provided for @tenantRightsSheetC9a8fc94.
  ///
  /// In he, this message translates to:
  /// **'דמי תיווך (חודש שכירות + מע״מ 18%) מגיעים למתווך '**
  String get tenantRightsSheetC9a8fc94;

  /// No description provided for @tenantRightsSheetC6aca436.
  ///
  /// In he, this message translates to:
  /// **'רק אם חתמתם על הסכם תיווך. בלי חתימה — אינכם חייבים '**
  String get tenantRightsSheetC6aca436;

  /// No description provided for @tenantRightsSheet0ae2e28f.
  ///
  /// In he, this message translates to:
  /// **'לשלם תיווך. שאלו תמיד מי מייצג מי.'**
  String get tenantRightsSheet0ae2e28f;

  /// No description provided for @tenantRightsSheetD8e77ae9.
  ///
  /// In he, this message translates to:
  /// **'אל תשלמו לפני שראיתם את הדירה'**
  String get tenantRightsSheetD8e77ae9;

  /// No description provided for @tenantRightsSheet386b9b05.
  ///
  /// In he, this message translates to:
  /// **'לעולם אל תעבירו פיקדון, מקדמה או דמי תיווך לפני '**
  String get tenantRightsSheet386b9b05;

  /// No description provided for @tenantRightsSheetC75c0e1f.
  ///
  /// In he, this message translates to:
  /// **'שביקרתם בדירה פיזית ואימתתם מול מי אתם מתקשרים. '**
  String get tenantRightsSheetC75c0e1f;

  /// No description provided for @tenantRightsSheetD5e1f4c7.
  ///
  /// In he, this message translates to:
  /// **'בקשה לתשלום מראש \"כדי לשמור\" את הדירה היא דגל אדום.'**
  String get tenantRightsSheetD5e1f4c7;

  /// No description provided for @tenantRightsSheet8b33be3a.
  ///
  /// In he, this message translates to:
  /// **'דירה ראויה למגורים'**
  String get tenantRightsSheet8b33be3a;

  /// No description provided for @tenantRightsSheet6c2e4b93.
  ///
  /// In he, this message translates to:
  /// **'על בעל הדירה למסור דירה במצב ראוי למגורים ולתקן '**
  String get tenantRightsSheet6c2e4b93;

  /// No description provided for @tenantRightsSheet7be24327.
  ///
  /// In he, this message translates to:
  /// **'ליקויים מהותיים שאינם באשמתכם. דירה חייבת אוורור, '**
  String get tenantRightsSheet7be24327;

  /// No description provided for @tenantRightsSheetD89c29b2.
  ///
  /// In he, this message translates to:
  /// **'מים, חשמל ומערכת ביוב תקינים.\n\n'**
  String get tenantRightsSheetD89c29b2;

  /// No description provided for @tenantRightsSheet5e967f01.
  ///
  /// In he, this message translates to:
  /// **'ממ\"ד = מרחב מוגן דירתי, חדר ביטחון. אם קיים, '**
  String get tenantRightsSheet5e967f01;

  /// No description provided for @tenantRightsSheet18d2dbed.
  ///
  /// In he, this message translates to:
  /// **'אסור להשתמש בו כמחסן שמונע כניסה בשעת חירום.'**
  String get tenantRightsSheet18d2dbed;

  /// No description provided for @tenantRightsSheetF8a977ee.
  ///
  /// In he, this message translates to:
  /// **'מידע כללי ואינו ייעוץ משפטי. בכל ספק התייעצו עם '**
  String get tenantRightsSheetF8a977ee;

  /// No description provided for @tenantRightsSheet190074d2.
  ///
  /// In he, this message translates to:
  /// **'עורך/ת דין.'**
  String get tenantRightsSheet190074d2;

  /// No description provided for @tenantRightsSheet5e9909a0.
  ///
  /// In he, this message translates to:
  /// **'הבנתי'**
  String get tenantRightsSheet5e9909a0;

  /// No description provided for @brokerCommissionScreen6d8d1136.
  ///
  /// In he, this message translates to:
  /// **'למחוק את העסקה?'**
  String get brokerCommissionScreen6d8d1136;

  /// No description provided for @brokerCommissionScreen88ad6f14.
  ///
  /// In he, this message translates to:
  /// **'הרשומה תימחק לצמיתות.'**
  String get brokerCommissionScreen88ad6f14;

  /// No description provided for @brokerCommissionScreen5c5ec48f.
  ///
  /// In he, this message translates to:
  /// **'\"{title}\" תימחק לצמיתות.'**
  String brokerCommissionScreen5c5ec48f(Object title);

  /// No description provided for @brokerCommissionScreenA7c55a8d.
  ///
  /// In he, this message translates to:
  /// **'ביטול'**
  String get brokerCommissionScreenA7c55a8d;

  /// No description provided for @brokerCommissionScreen09b6bcca.
  ///
  /// In he, this message translates to:
  /// **'מחק'**
  String get brokerCommissionScreen09b6bcca;

  /// No description provided for @brokerCommissionScreenA8ea0bb8.
  ///
  /// In he, this message translates to:
  /// **'עמלות ופייפליין'**
  String get brokerCommissionScreenA8ea0bb8;

  /// No description provided for @brokerCommissionScreen77289a23.
  ///
  /// In he, this message translates to:
  /// **'עסקה חדשה'**
  String get brokerCommissionScreen77289a23;

  /// No description provided for @brokerCommissionScreen7d9ee511.
  ///
  /// In he, this message translates to:
  /// **'צפי בצנרת'**
  String get brokerCommissionScreen7d9ee511;

  /// No description provided for @brokerCommissionScreen8b24239f.
  ///
  /// In he, this message translates to:
  /// **'{count} עסקאות פתוחות'**
  String brokerCommissionScreen8b24239f(Object count);

  /// No description provided for @brokerCommissionScreenA848f824.
  ///
  /// In he, this message translates to:
  /// **'נסגר החודש'**
  String get brokerCommissionScreenA848f824;

  /// No description provided for @brokerCommissionScreenD5a65055.
  ///
  /// In he, this message translates to:
  /// **'עמלה שהתקבלה'**
  String get brokerCommissionScreenD5a65055;

  /// No description provided for @brokerCommissionScreenDd3b0aad.
  ///
  /// In he, this message translates to:
  /// **'כל העסקאות'**
  String get brokerCommissionScreenDd3b0aad;

  /// No description provided for @brokerCommissionScreenC9ef0566.
  ///
  /// In he, this message translates to:
  /// **'אין עדיין עסקאות. הוסף עסקה כדי לעקוב אחר העמלות.'**
  String get brokerCommissionScreenC9ef0566;

  /// No description provided for @brokerCommissionScreen6cecfe2c.
  ///
  /// In he, this message translates to:
  /// **'עסקה ללא שם'**
  String get brokerCommissionScreen6cecfe2c;

  /// No description provided for @brokerCommissionScreenD629d4dc.
  ///
  /// In he, this message translates to:
  /// **'לקוח: {name}'**
  String brokerCommissionScreenD629d4dc(Object name);

  /// No description provided for @brokerCommissionScreen84540fa4.
  ///
  /// In he, this message translates to:
  /// **'שווי עסקה'**
  String get brokerCommissionScreen84540fa4;

  /// No description provided for @brokerCommissionScreenC3eaf8a1.
  ///
  /// In he, this message translates to:
  /// **'עמלה ({pct}%)'**
  String brokerCommissionScreenC3eaf8a1(Object pct);

  /// No description provided for @brokerCommissionScreen39fe2593.
  ///
  /// In he, this message translates to:
  /// **'עריכה'**
  String get brokerCommissionScreen39fe2593;

  /// No description provided for @brokerCommissionScreen7c8173fa.
  ///
  /// In he, this message translates to:
  /// **'מחיקה'**
  String get brokerCommissionScreen7c8173fa;

  /// No description provided for @brokerCommissionScreen50b6fe45.
  ///
  /// In he, this message translates to:
  /// **'עריכת עסקה'**
  String get brokerCommissionScreen50b6fe45;

  /// No description provided for @brokerCommissionScreenBa9fc140.
  ///
  /// In he, this message translates to:
  /// **'כתובת / שם הנכס'**
  String get brokerCommissionScreenBa9fc140;

  /// No description provided for @brokerCommissionScreenC416d614.
  ///
  /// In he, this message translates to:
  /// **'שם הלקוח'**
  String get brokerCommissionScreenC416d614;

  /// No description provided for @brokerCommissionScreen8b26fe13.
  ///
  /// In he, this message translates to:
  /// **'שווי עסקה (₪)'**
  String get brokerCommissionScreen8b26fe13;

  /// No description provided for @brokerCommissionScreen7ac184b0.
  ///
  /// In he, this message translates to:
  /// **'אחוז עמלה (%)'**
  String get brokerCommissionScreen7ac184b0;

  /// No description provided for @brokerCommissionScreen4e41a655.
  ///
  /// In he, this message translates to:
  /// **'עמלה צפויה: {amount}'**
  String brokerCommissionScreen4e41a655(Object amount);

  /// No description provided for @brokerCommissionScreenE6932339.
  ///
  /// In he, this message translates to:
  /// **'שמירה'**
  String get brokerCommissionScreenE6932339;

  /// No description provided for @brokerViewingsScreen870292f7.
  ///
  /// In he, this message translates to:
  /// **'הלקוח'**
  String get brokerViewingsScreen870292f7;

  /// No description provided for @brokerViewingsScreen9d30a0d7.
  ///
  /// In he, this message translates to:
  /// **'צפייה בעוד שעה'**
  String get brokerViewingsScreen9d30a0d7;

  /// No description provided for @brokerViewingsScreen57c48e81.
  ///
  /// In he, this message translates to:
  /// **'צפייה עם {who} בשעה {time}{where}'**
  String brokerViewingsScreen57c48e81(Object time, Object where, Object who);

  /// No description provided for @brokerViewingsScreenBb5dc197.
  ///
  /// In he, this message translates to:
  /// **'תיאום צפיות'**
  String get brokerViewingsScreenBb5dc197;

  /// No description provided for @brokerViewingsScreenCfa7c35a.
  ///
  /// In he, this message translates to:
  /// **'צפייה חדשה'**
  String get brokerViewingsScreenCfa7c35a;

  /// No description provided for @brokerViewingsScreen36f66af0.
  ///
  /// In he, this message translates to:
  /// **'צפיות קרובות'**
  String get brokerViewingsScreen36f66af0;

  /// No description provided for @brokerViewingsScreen0b7ee118.
  ///
  /// In he, this message translates to:
  /// **'אין צפיות מתוכננות'**
  String get brokerViewingsScreen0b7ee118;

  /// No description provided for @brokerViewingsScreen8726f8f5.
  ///
  /// In he, this message translates to:
  /// **'היסטוריה'**
  String get brokerViewingsScreen8726f8f5;

  /// No description provided for @brokerViewingsScreen1e2e6a34.
  ///
  /// In he, this message translates to:
  /// **'אין עדיין צפיות'**
  String get brokerViewingsScreen1e2e6a34;

  /// No description provided for @brokerViewingsScreen5f6aa66c.
  ///
  /// In he, this message translates to:
  /// **'תאמו צפייה ותקבלו תזכורת שעה לפני'**
  String get brokerViewingsScreen5f6aa66c;

  /// No description provided for @brokerViewingsScreenE0d2c04b.
  ///
  /// In he, this message translates to:
  /// **'יש {count} צפיות שמתנגשות בלו\"ז — בדקו את הסימון האדום'**
  String brokerViewingsScreenE0d2c04b(Object count);

  /// No description provided for @brokerViewingsScreenA157f372.
  ///
  /// In he, this message translates to:
  /// **'התנגשות בלו\"ז'**
  String get brokerViewingsScreenA157f372;

  /// No description provided for @brokerViewingsScreen54616e37.
  ///
  /// In he, this message translates to:
  /// **'סמן: התקיימה'**
  String get brokerViewingsScreen54616e37;

  /// No description provided for @brokerViewingsScreen09644fa4.
  ///
  /// In he, this message translates to:
  /// **'סמן: לא הגיע'**
  String get brokerViewingsScreen09644fa4;

  /// No description provided for @brokerViewingsScreenB041ac86.
  ///
  /// In he, this message translates to:
  /// **'סמן: בוטלה'**
  String get brokerViewingsScreenB041ac86;

  /// No description provided for @brokerViewingsScreenC47d0392.
  ///
  /// In he, this message translates to:
  /// **'החזר לתכנון'**
  String get brokerViewingsScreenC47d0392;

  /// No description provided for @brokerViewingsScreen078baeac.
  ///
  /// In he, this message translates to:
  /// **'יש לבחור תאריך ושעה'**
  String get brokerViewingsScreen078baeac;

  /// No description provided for @brokerViewingsScreen18d43ef8.
  ///
  /// In he, this message translates to:
  /// **'יש להזין שם לקוח'**
  String get brokerViewingsScreen18d43ef8;

  /// No description provided for @brokerViewingsScreenCd846d8d.
  ///
  /// In he, this message translates to:
  /// **'נכס:'**
  String get brokerViewingsScreenCd846d8d;

  /// No description provided for @brokerViewingsScreenEdf6c5ad.
  ///
  /// In he, this message translates to:
  /// **'בחר נכס (לא חובה)'**
  String get brokerViewingsScreenEdf6c5ad;

  /// No description provided for @brokerViewingsScreenBf7d92b1.
  ///
  /// In he, this message translates to:
  /// **'ללא נכס'**
  String get brokerViewingsScreenBf7d92b1;

  /// No description provided for @brokerViewingsScreen83c5428d.
  ///
  /// In he, this message translates to:
  /// **'שם הלקוח *'**
  String get brokerViewingsScreen83c5428d;

  /// No description provided for @brokerViewingsScreen737232c2.
  ///
  /// In he, this message translates to:
  /// **'טלפון'**
  String get brokerViewingsScreen737232c2;

  /// No description provided for @brokerViewingsScreenE8e0f191.
  ///
  /// In he, this message translates to:
  /// **'בחר תאריך ושעה *'**
  String get brokerViewingsScreenE8e0f191;

  /// No description provided for @brokerViewingsScreenE6932339.
  ///
  /// In he, this message translates to:
  /// **'שמירה'**
  String get brokerViewingsScreenE6932339;

  /// No description provided for @panoramaPhotoCapture443184c1.
  ///
  /// In he, this message translates to:
  /// **'לא ניתן לפתוח את המצלמה. בדקו הרשאות מצלמה.'**
  String get panoramaPhotoCapture443184c1;

  /// No description provided for @panoramaPhotoCapture79c27a2a.
  ///
  /// In he, this message translates to:
  /// **'הצילום נכשל. נסו שוב.'**
  String get panoramaPhotoCapture79c27a2a;

  /// No description provided for @panoramaPhotoCapture97f6b247.
  ///
  /// In he, this message translates to:
  /// **'מתחילים לבנות את הסיור...'**
  String get panoramaPhotoCapture97f6b247;

  /// No description provided for @panoramaPhotoCapture127d1554.
  ///
  /// In he, this message translates to:
  /// **'לא הצלחנו להתחיל את העיבוד. בדקו את החיבור לאינטרנט.'**
  String get panoramaPhotoCapture127d1554;

  /// No description provided for @panoramaPhotoCaptureE39b6aae.
  ///
  /// In he, this message translates to:
  /// **'מעלים את התמונות...'**
  String get panoramaPhotoCaptureE39b6aae;

  /// No description provided for @panoramaPhotoCaptureBbb9c298.
  ///
  /// In he, this message translates to:
  /// **'ההעלאה נכשלה. בדקו את החיבור ונסו שוב.'**
  String get panoramaPhotoCaptureBbb9c298;

  /// No description provided for @panoramaPhotoCapture1b311f3a.
  ///
  /// In he, this message translates to:
  /// **'מעלים את התמונות... ({current}/{total})'**
  String panoramaPhotoCapture1b311f3a(Object current, Object total);

  /// No description provided for @panoramaPhotoCapture8844cc68.
  ///
  /// In he, this message translates to:
  /// **'בונים את הסיור...'**
  String get panoramaPhotoCapture8844cc68;

  /// No description provided for @panoramaPhotoCaptureA9e373df.
  ///
  /// In he, this message translates to:
  /// **'העיבוד נכשל. נסו לצלם שוב, לאט ובאור טוב.'**
  String get panoramaPhotoCaptureA9e373df;

  /// No description provided for @panoramaPhotoCaptureAb4f63ba.
  ///
  /// In he, this message translates to:
  /// **'העיבוד לוקח יותר מדי זמן. נסו שוב מאוחר יותר.'**
  String get panoramaPhotoCaptureAb4f63ba;

  /// No description provided for @panoramaPhotoCapture19c26543.
  ///
  /// In he, this message translates to:
  /// **'משהו השתבש. בדקו את החיבור ונסו שוב.'**
  String get panoramaPhotoCapture19c26543;

  /// No description provided for @panoramaPhotoCaptureEe690500.
  ///
  /// In he, this message translates to:
  /// **'כל הצילומים הושלמו ✓'**
  String get panoramaPhotoCaptureEe690500;

  /// No description provided for @panoramaPhotoCaptureE295aedd.
  ///
  /// In he, this message translates to:
  /// **'צילום {taken} מתוך {total}'**
  String panoramaPhotoCaptureE295aedd(Object taken, Object total);

  /// No description provided for @panoramaPhotoCaptureDf208dbe.
  ///
  /// In he, this message translates to:
  /// **'עמדו במרכז, החזיקו ישר וצלמו את התמונה הראשונה.'**
  String get panoramaPhotoCaptureDf208dbe;

  /// No description provided for @panoramaPhotoCaptureE97ca842.
  ///
  /// In he, this message translates to:
  /// **'מצוין! בונים את הסיור...'**
  String get panoramaPhotoCaptureE97ca842;

  /// No description provided for @panoramaPhotoCapture96988ada.
  ///
  /// In he, this message translates to:
  /// **'החזיקו את הטלפון יציב 🤳 ואז צלמו'**
  String get panoramaPhotoCapture96988ada;

  /// No description provided for @panoramaPhotoCapture25092fb6.
  ///
  /// In he, this message translates to:
  /// **'סובבו ~{deg}° ימינה — שמרו חפיפה עם הקודם'**
  String panoramaPhotoCapture25092fb6(Object deg);

  /// No description provided for @panoramaPhotoCaptureE0f98881.
  ///
  /// In he, this message translates to:
  /// **'מצוין — צלמו עכשיו 📸'**
  String get panoramaPhotoCaptureE0f98881;

  /// No description provided for @panoramaPhotoCapture1dc38c15.
  ///
  /// In he, this message translates to:
  /// **'לא הצלחנו לבנות את הסיור'**
  String get panoramaPhotoCapture1dc38c15;

  /// No description provided for @panoramaPhotoCapture5a8e3f2d.
  ///
  /// In he, this message translates to:
  /// **'{msg}\n\nאפשר להמתין כמה רגעים — אל תסגרו את המסך.'**
  String panoramaPhotoCapture5a8e3f2d(Object msg);

  /// No description provided for @panoramaPhotoCapture3b32c520.
  ///
  /// In he, this message translates to:
  /// **'צלם מחדש'**
  String get panoramaPhotoCapture3b32c520;

  /// No description provided for @panoramaPhotoCapture55247199.
  ///
  /// In he, this message translates to:
  /// **'סגור'**
  String get panoramaPhotoCapture55247199;

  /// No description provided for @panoramaPhotoCaptureA9e4f107.
  ///
  /// In he, this message translates to:
  /// **'רחב'**
  String get panoramaPhotoCaptureA9e4f107;

  /// No description provided for @panoramaPhotoCapture3e20e30e.
  ///
  /// In he, this message translates to:
  /// **'רגיל'**
  String get panoramaPhotoCapture3e20e30e;

  /// No description provided for @panoramaPhotoCapture4c53a96e.
  ///
  /// In he, this message translates to:
  /// **'שגיאת מצלמה'**
  String get panoramaPhotoCapture4c53a96e;

  /// No description provided for @subscriptionScreenF29b6ff9.
  ///
  /// In he, this message translates to:
  /// **'מסלול שנתי (RENTLY PRO)'**
  String get subscriptionScreenF29b6ff9;

  /// No description provided for @subscriptionScreen73934490.
  ///
  /// In he, this message translates to:
  /// **'מסלול חודשי (RENTLY PRO)'**
  String get subscriptionScreen73934490;

  /// No description provided for @subscriptionScreenA4257fc5.
  ///
  /// In he, this message translates to:
  /// **'מסלול PRO MAX VIP'**
  String get subscriptionScreenA4257fc5;

  /// No description provided for @subscriptionScreenB18c066f.
  ///
  /// In he, this message translates to:
  /// **'מסלול RENTLY PRO'**
  String get subscriptionScreenB18c066f;

  /// No description provided for @subscriptionScreen2b7d5edc.
  ///
  /// In he, this message translates to:
  /// **'לבטל את המנוי?'**
  String get subscriptionScreen2b7d5edc;

  /// No description provided for @subscriptionScreenD9eefdcc.
  ///
  /// In he, this message translates to:
  /// **'המנוי יישאר פעיל עד סוף תקופת החיוב הנוכחית, ולאחר מכן לא יחודש.'**
  String get subscriptionScreenD9eefdcc;

  /// No description provided for @subscriptionScreen10a2352b.
  ///
  /// In he, this message translates to:
  /// **'חזרה'**
  String get subscriptionScreen10a2352b;

  /// No description provided for @subscriptionScreen00a5e771.
  ///
  /// In he, this message translates to:
  /// **'ביטול מנוי'**
  String get subscriptionScreen00a5e771;

  /// No description provided for @subscriptionScreen6ca6bd18.
  ///
  /// In he, this message translates to:
  /// **'המנוי יבוטל בסוף התקופה'**
  String get subscriptionScreen6ca6bd18;

  /// No description provided for @subscriptionScreenA3c4c747.
  ///
  /// In he, this message translates to:
  /// **'המנוי חודש בהצלחה'**
  String get subscriptionScreenA3c4c747;

  /// No description provided for @subscriptionScreenA8ba6aa6.
  ///
  /// In he, this message translates to:
  /// **'שגיאה. נסו שוב.'**
  String get subscriptionScreenA8ba6aa6;

  /// No description provided for @subscriptionScreen3c4641b6.
  ///
  /// In he, this message translates to:
  /// **'אין מנוי פעיל'**
  String get subscriptionScreen3c4641b6;

  /// No description provided for @subscriptionScreen1abb5cf0.
  ///
  /// In he, this message translates to:
  /// **'שלוש דירות ראשונות חינם. לפרסום דירות ללא הגבלה וגישה לכל האפשרויות — הצטרפו ל-RENTLY PRO.'**
  String get subscriptionScreen1abb5cf0;

  /// No description provided for @subscriptionScreen74b0f662.
  ///
  /// In he, this message translates to:
  /// **'פרסום דירות ללא הגבלה'**
  String get subscriptionScreen74b0f662;

  /// No description provided for @subscriptionScreen6e6d4e06.
  ///
  /// In he, this message translates to:
  /// **'13-30 צילומי 360 וסיור וירטואלי'**
  String get subscriptionScreen6e6d4e06;

  /// No description provided for @subscriptionScreen6b0e2fd9.
  ///
  /// In he, this message translates to:
  /// **'סינון שוכרים חכם ב-AI ובוסטים'**
  String get subscriptionScreen6b0e2fd9;

  /// No description provided for @subscriptionScreenA324e706.
  ///
  /// In he, this message translates to:
  /// **'בחירת מסלול RENTLY PRO'**
  String get subscriptionScreenA324e706;

  /// No description provided for @subscriptionScreen7aa12af9.
  ///
  /// In he, this message translates to:
  /// **'חשבוניות וקבלות'**
  String get subscriptionScreen7aa12af9;

  /// No description provided for @subscriptionScreen680ede0e.
  ///
  /// In he, this message translates to:
  /// **'חידוש מנוי'**
  String get subscriptionScreen680ede0e;

  /// No description provided for @subscriptionScreen6b44102c.
  ///
  /// In he, this message translates to:
  /// **'מבוטל בסוף התקופה'**
  String get subscriptionScreen6b44102c;

  /// No description provided for @subscriptionScreen09900e25.
  ///
  /// In he, this message translates to:
  /// **'מנוי פעיל'**
  String get subscriptionScreen09900e25;

  /// No description provided for @subscriptionScreen98e268e7.
  ///
  /// In he, this message translates to:
  /// **'ללא מנוי'**
  String get subscriptionScreen98e268e7;

  /// No description provided for @subscriptionScreen03baa387.
  ///
  /// In he, this message translates to:
  /// **'בתוקף עד'**
  String get subscriptionScreen03baa387;

  /// No description provided for @subscriptionScreenD4bd0d5c.
  ///
  /// In he, this message translates to:
  /// **'חיוב הבא'**
  String get subscriptionScreenD4bd0d5c;

  /// No description provided for @subscriptionScreenA0d9b485.
  ///
  /// In he, this message translates to:
  /// **'כרטיס'**
  String get subscriptionScreenA0d9b485;

  /// No description provided for @brokerToolsScreenF9d349b3.
  ///
  /// In he, this message translates to:
  /// **'פנקס לקוחות'**
  String get brokerToolsScreenF9d349b3;

  /// No description provided for @brokerToolsScreen91412cfd.
  ///
  /// In he, this message translates to:
  /// **'ניהול הלקוחות שלך + אילו נכסים מתאימים לכל אחד'**
  String get brokerToolsScreen91412cfd;

  /// No description provided for @brokerToolsScreenEda2e484.
  ///
  /// In he, this message translates to:
  /// **'התאמות חמות'**
  String get brokerToolsScreenEda2e484;

  /// No description provided for @brokerToolsScreen3c455670.
  ///
  /// In he, this message translates to:
  /// **'לקוחות שמחכים בדיוק לנכס שיש לך עכשיו'**
  String get brokerToolsScreen3c455670;

  /// No description provided for @brokerToolsScreen0a1cdb54.
  ///
  /// In he, this message translates to:
  /// **'פייפליין לידים'**
  String get brokerToolsScreen0a1cdb54;

  /// No description provided for @brokerToolsScreen82dc7ac7.
  ///
  /// In he, this message translates to:
  /// **'כל הפניות במקום אחד — שום ליד לא נופל'**
  String get brokerToolsScreen82dc7ac7;

  /// No description provided for @brokerToolsScreenBb5dc197.
  ///
  /// In he, this message translates to:
  /// **'תיאום צפיות'**
  String get brokerToolsScreenBb5dc197;

  /// No description provided for @brokerToolsScreen2bf80048.
  ///
  /// In he, this message translates to:
  /// **'לקבוע ולעקוב אחרי צפיות בנכסים'**
  String get brokerToolsScreen2bf80048;

  /// No description provided for @brokerToolsScreen85518426.
  ///
  /// In he, this message translates to:
  /// **'ניתוח שוק (CMA)'**
  String get brokerToolsScreen85518426;

  /// No description provided for @brokerToolsScreen34c08639.
  ///
  /// In he, this message translates to:
  /// **'מחיר מומלץ לפי נכסים דומים באזור'**
  String get brokerToolsScreen34c08639;

  /// No description provided for @brokerToolsScreenA8bb0310.
  ///
  /// In he, this message translates to:
  /// **'אינטליגנציית אזור'**
  String get brokerToolsScreenA8bb0310;

  /// No description provided for @brokerToolsScreen5f85ee35.
  ///
  /// In he, this message translates to:
  /// **'כתובת → כל נתוני האזור + למי הוא הכי מתאים להשקעה'**
  String get brokerToolsScreen5f85ee35;

  /// No description provided for @brokerToolsScreen5ac95646.
  ///
  /// In he, this message translates to:
  /// **'מעקב בלעדיות'**
  String get brokerToolsScreen5ac95646;

  /// No description provided for @brokerToolsScreenF08ed1c1.
  ///
  /// In he, this message translates to:
  /// **'תוקף ההסכמים — שלא תחמיץ חידוש בלעדיות'**
  String get brokerToolsScreenF08ed1c1;

  /// No description provided for @brokerToolsScreenA8ea0bb8.
  ///
  /// In he, this message translates to:
  /// **'עמלות ופייפליין'**
  String get brokerToolsScreenA8ea0bb8;

  /// No description provided for @brokerToolsScreenC384e0ce.
  ///
  /// In he, this message translates to:
  /// **'מעקב עמלות צפויות והכנסות מהעסקאות'**
  String get brokerToolsScreenC384e0ce;

  /// No description provided for @brokerToolsScreen02b2074b.
  ///
  /// In he, this message translates to:
  /// **'דוח לבעל הנכס'**
  String get brokerToolsScreen02b2074b;

  /// No description provided for @brokerToolsScreenFe8f7d48.
  ///
  /// In he, this message translates to:
  /// **'דוח מסודר על הפעילות לשליחה לבעל הנכס'**
  String get brokerToolsScreenFe8f7d48;

  /// No description provided for @brokerToolsScreenE14de9a0.
  ///
  /// In he, this message translates to:
  /// **'ברושור ממותג'**
  String get brokerToolsScreenE14de9a0;

  /// No description provided for @brokerToolsScreenE45217dd.
  ///
  /// In he, this message translates to:
  /// **'דף נכס יפה עם המיתוג שלך לשיתוף'**
  String get brokerToolsScreenE45217dd;

  /// No description provided for @brokerToolsScreen2074036b.
  ///
  /// In he, this message translates to:
  /// **'כלי הסוכן'**
  String get brokerToolsScreen2074036b;

  /// No description provided for @brokerToolsScreen23d1f112.
  ///
  /// In he, this message translates to:
  /// **'כל מה שצריך לניהול העסק שלך במקום אחד — לקוחות, '**
  String get brokerToolsScreen23d1f112;

  /// No description provided for @brokerToolsScreenE0706866.
  ///
  /// In he, this message translates to:
  /// **'לידים, צפיות, עמלות ועוד. הקש על כלי כדי להתחיל.'**
  String get brokerToolsScreenE0706866;

  /// No description provided for @brokerToolsScreenA4809695.
  ///
  /// In he, this message translates to:
  /// **'הנתונים מגובים בענן'**
  String get brokerToolsScreenA4809695;

  /// No description provided for @brokerToolsScreenE2adc4d9.
  ///
  /// In he, this message translates to:
  /// **'מקומי בלבד — אין חיבור לענן'**
  String get brokerToolsScreenE2adc4d9;

  /// No description provided for @notifConsoleScreen8d5f5869.
  ///
  /// In he, this message translates to:
  /// **'תמונה גדולה'**
  String get notifConsoleScreen8d5f5869;

  /// No description provided for @notifConsoleScreen61993e0f.
  ///
  /// In he, this message translates to:
  /// **'צבע נועז'**
  String get notifConsoleScreen61993e0f;

  /// No description provided for @notifConsoleScreen3649be51.
  ///
  /// In he, this message translates to:
  /// **'חגיגת אימוג׳י'**
  String get notifConsoleScreen3649be51;

  /// No description provided for @notifConsoleScreen55b43250.
  ///
  /// In he, this message translates to:
  /// **'מינימלי'**
  String get notifConsoleScreen55b43250;

  /// No description provided for @notifConsoleScreenE47df89f.
  ///
  /// In he, this message translates to:
  /// **'טעינת ההיסטוריה נכשלה'**
  String get notifConsoleScreenE47df89f;

  /// No description provided for @notifConsoleScreenB5cb1ebd.
  ///
  /// In he, this message translates to:
  /// **'לשלוח לכל המשתמשים?'**
  String get notifConsoleScreenB5cb1ebd;

  /// No description provided for @notifConsoleScreen4d875ef7.
  ///
  /// In he, this message translates to:
  /// **'ההתראה תישלח לכל משתמשי האפליקציה. הפעולה אינה ניתנת לביטול.'**
  String get notifConsoleScreen4d875ef7;

  /// No description provided for @notifConsoleScreenA7c55a8d.
  ///
  /// In he, this message translates to:
  /// **'ביטול'**
  String get notifConsoleScreenA7c55a8d;

  /// No description provided for @notifConsoleScreen5239bffa.
  ///
  /// In he, this message translates to:
  /// **'שליחה'**
  String get notifConsoleScreen5239bffa;

  /// No description provided for @notifConsoleScreenFf800e24.
  ///
  /// In he, this message translates to:
  /// **'נשלח בהצלחה • הצליחו {sent} • נכשלו {failed}'**
  String notifConsoleScreenFf800e24(Object failed, Object sent);

  /// No description provided for @notifConsoleScreenEe5a07f1.
  ///
  /// In he, this message translates to:
  /// **'השליחה נכשלה. נסו שוב.'**
  String get notifConsoleScreenEe5a07f1;

  /// No description provided for @notifConsoleScreen18ec902a.
  ///
  /// In he, this message translates to:
  /// **'קונסולת התראות'**
  String get notifConsoleScreen18ec902a;

  /// No description provided for @notifConsoleScreen689c3cf5.
  ///
  /// In he, this message translates to:
  /// **'עיצוב ההתראה'**
  String get notifConsoleScreen689c3cf5;

  /// No description provided for @notifConsoleScreenB135a00a.
  ///
  /// In he, this message translates to:
  /// **'תוכן'**
  String get notifConsoleScreenB135a00a;

  /// No description provided for @notifConsoleScreenA21f5710.
  ///
  /// In he, this message translates to:
  /// **'כותרת'**
  String get notifConsoleScreenA21f5710;

  /// No description provided for @notifConsoleScreenF1475bfa.
  ///
  /// In he, this message translates to:
  /// **'תוכן ההתראה'**
  String get notifConsoleScreenF1475bfa;

  /// No description provided for @notifConsoleScreenC837e5e6.
  ///
  /// In he, this message translates to:
  /// **'כתובת תמונה (אופציונלי)'**
  String get notifConsoleScreenC837e5e6;

  /// No description provided for @notifConsoleScreenE95c9328.
  ///
  /// In he, this message translates to:
  /// **'תצוגה מקדימה'**
  String get notifConsoleScreenE95c9328;

  /// No description provided for @notifConsoleScreen13e7d29e.
  ///
  /// In he, this message translates to:
  /// **'היסטוריית שליחות'**
  String get notifConsoleScreen13e7d29e;

  /// No description provided for @notifConsoleScreen0264cdd3.
  ///
  /// In he, this message translates to:
  /// **'קהל יעד: כל המשתמשים'**
  String get notifConsoleScreen0264cdd3;

  /// No description provided for @notifConsoleScreen9a1364b4.
  ///
  /// In he, this message translates to:
  /// **'שליחה לכל המשתמשים'**
  String get notifConsoleScreen9a1364b4;

  /// No description provided for @notifConsoleScreenB4c5133d.
  ///
  /// In he, this message translates to:
  /// **'עדיין לא נשלחו התראות'**
  String get notifConsoleScreenB4c5133d;

  /// No description provided for @notifConsoleScreenAbaa0cd6.
  ///
  /// In he, this message translates to:
  /// **'הצליחו {sent} • נכשלו {failed} • {date}'**
  String notifConsoleScreenAbaa0cd6(Object date, Object failed, Object sent);

  /// No description provided for @notifConsoleScreen4fa84be8.
  ///
  /// In he, this message translates to:
  /// **'כותרת ההתראה'**
  String get notifConsoleScreen4fa84be8;

  /// No description provided for @notifConsoleScreen8d2574fe.
  ///
  /// In he, this message translates to:
  /// **'תוכן ההתראה יופיע כאן…'**
  String get notifConsoleScreen8d2574fe;

  /// No description provided for @atiVoiceScreenF0dad564.
  ///
  /// In he, this message translates to:
  /// **'שלום, אני אתי 👋\nספרו לי מה אתם מחפשים.'**
  String get atiVoiceScreenF0dad564;

  /// No description provided for @atiVoiceScreenF90c23d4.
  ///
  /// In he, this message translates to:
  /// **'אני מחפשת 3 חדרים בתל אביב, קרוב לים, עם מרפסת…'**
  String get atiVoiceScreenF90c23d4;

  /// No description provided for @atiVoiceScreen2c1f2bbd.
  ///
  /// In he, this message translates to:
  /// **'תל אביב'**
  String get atiVoiceScreen2c1f2bbd;

  /// No description provided for @atiVoiceScreen535bb0c7.
  ///
  /// In he, this message translates to:
  /// **'3 חדרים'**
  String get atiVoiceScreen535bb0c7;

  /// No description provided for @atiVoiceScreen2ac25940.
  ///
  /// In he, this message translates to:
  /// **'עד 8,000 ₪'**
  String get atiVoiceScreen2ac25940;

  /// No description provided for @atiVoiceScreen86425fcf.
  ///
  /// In he, this message translates to:
  /// **'מרפסת'**
  String get atiVoiceScreen86425fcf;

  /// No description provided for @atiVoiceScreen46602c9d.
  ///
  /// In he, this message translates to:
  /// **'ליד הים'**
  String get atiVoiceScreen46602c9d;

  /// No description provided for @atiVoiceScreen115e4778.
  ///
  /// In he, this message translates to:
  /// **'צריך הרשאת מיקרופון — אשרו בהגדרות המכשיר 🎙️'**
  String get atiVoiceScreen115e4778;

  /// No description provided for @atiVoiceScreen32371f9e.
  ///
  /// In he, this message translates to:
  /// **'לא הצלחתי להתחיל הקלטה 🙈\n'**
  String get atiVoiceScreen32371f9e;

  /// No description provided for @atiVoiceScreen77515f7a.
  ///
  /// In he, this message translates to:
  /// **'לא שמעתי אותך 🙈 החזק/י את הכדור ודבר/י'**
  String get atiVoiceScreen77515f7a;

  /// No description provided for @atiVoiceScreenCcaa1ca0.
  ///
  /// In he, this message translates to:
  /// **'סליחה, לקח לי רגע יותר מדי 🙈 אפשר לנסות שוב?'**
  String get atiVoiceScreenCcaa1ca0;

  /// No description provided for @atiVoiceScreenF9ff4f53.
  ///
  /// In he, this message translates to:
  /// **'מקשיבה… שחרר/י כדי לשלוח'**
  String get atiVoiceScreenF9ff4f53;

  /// No description provided for @atiVoiceScreenA6de1c7e.
  ///
  /// In he, this message translates to:
  /// **'רגע, חושבת…'**
  String get atiVoiceScreenA6de1c7e;

  /// No description provided for @atiVoiceScreen374487f8.
  ///
  /// In he, this message translates to:
  /// **'אתי מדברת · החזק/י כדי לענות'**
  String get atiVoiceScreen374487f8;

  /// No description provided for @atiVoiceScreen69a4351d.
  ///
  /// In he, this message translates to:
  /// **'החזק/י את הכדור כדי לדבר 🎙️'**
  String get atiVoiceScreen69a4351d;

  /// No description provided for @atiVoiceScreen8e4d1523.
  ///
  /// In he, this message translates to:
  /// **'אתי'**
  String get atiVoiceScreen8e4d1523;

  /// No description provided for @atiVoiceScreen5ddb8c89.
  ///
  /// In he, this message translates to:
  /// **'העוזרת החכמה שלך'**
  String get atiVoiceScreen5ddb8c89;

  /// No description provided for @atiVoiceScreen82c40bcf.
  ///
  /// In he, this message translates to:
  /// **'שיחה חדשה'**
  String get atiVoiceScreen82c40bcf;

  /// No description provided for @atiVoiceScreenE3d4bb2b.
  ///
  /// In he, this message translates to:
  /// **'שיחה חדשה 👋 מה נחפש עכשיו?'**
  String get atiVoiceScreenE3d4bb2b;

  /// No description provided for @atiVoiceScreen38f0b537.
  ///
  /// In he, this message translates to:
  /// **'מצאתי {count} דירות שמתאימות לך 👇'**
  String atiVoiceScreen38f0b537(Object count);

  /// No description provided for @atiVoiceScreen9a60c4a8.
  ///
  /// In he, this message translates to:
  /// **'מצאתי {count} דירות שמתאימות לך'**
  String atiVoiceScreen9a60c4a8(Object count);

  /// No description provided for @atiVoiceScreen193535e0.
  ///
  /// In he, this message translates to:
  /// **'הצג'**
  String get atiVoiceScreen193535e0;

  /// No description provided for @atiVoiceScreen7ddcbdea.
  ///
  /// In he, this message translates to:
  /// **'שיתוף המיקום שלי'**
  String get atiVoiceScreen7ddcbdea;

  /// No description provided for @chatPartnerProfileScreenF0d12f45.
  ///
  /// In he, this message translates to:
  /// **'{name} · {city} — דרך Rently'**
  String chatPartnerProfileScreenF0d12f45(Object city, Object name);

  /// No description provided for @chatPartnerProfileScreen025b94a3.
  ///
  /// In he, this message translates to:
  /// **'{name} — דרך Rently'**
  String chatPartnerProfileScreen025b94a3(Object name);

  /// No description provided for @chatPartnerProfileScreen1956aee8.
  ///
  /// In he, this message translates to:
  /// **'הודעות'**
  String get chatPartnerProfileScreen1956aee8;

  /// No description provided for @chatPartnerProfileScreenDbac683f.
  ///
  /// In he, this message translates to:
  /// **'תמונות'**
  String get chatPartnerProfileScreenDbac683f;

  /// No description provided for @chatPartnerProfileScreenB151b3b1.
  ///
  /// In he, this message translates to:
  /// **'הקלטות'**
  String get chatPartnerProfileScreenB151b3b1;

  /// No description provided for @chatPartnerProfileScreen3a232c1e.
  ///
  /// In he, this message translates to:
  /// **'מדיה בשיחה'**
  String get chatPartnerProfileScreen3a232c1e;

  /// No description provided for @chatPartnerProfileScreen78f089fd.
  ///
  /// In he, this message translates to:
  /// **'עדיין לא שותפו תמונות או הקלטות בשיחה.'**
  String get chatPartnerProfileScreen78f089fd;

  /// No description provided for @chatPartnerProfileScreen7c303765.
  ///
  /// In he, this message translates to:
  /// **'{count} הקלטות קוליות'**
  String chatPartnerProfileScreen7c303765(Object count);

  /// No description provided for @chatPartnerProfileScreen0a303443.
  ///
  /// In he, this message translates to:
  /// **'הדירה בשיחה'**
  String get chatPartnerProfileScreen0a303443;

  /// No description provided for @chatPartnerProfileScreen00fe742b.
  ///
  /// In he, this message translates to:
  /// **'חסימת משתמש'**
  String get chatPartnerProfileScreen00fe742b;

  /// No description provided for @chatPartnerProfileScreen59f1446c.
  ///
  /// In he, this message translates to:
  /// **'מחיקת היסטוריית השיחה'**
  String get chatPartnerProfileScreen59f1446c;

  /// No description provided for @chatPartnerProfileScreen45a6c3ab.
  ///
  /// In he, this message translates to:
  /// **'פתיחת הדירה'**
  String get chatPartnerProfileScreen45a6c3ab;

  /// No description provided for @chatPartnerProfileScreen32033594.
  ///
  /// In he, this message translates to:
  /// **'שיתוף'**
  String get chatPartnerProfileScreen32033594;

  /// No description provided for @chatPartnerProfileScreenB5c83bf6.
  ///
  /// In he, this message translates to:
  /// **'חסום את \"{name}\"?'**
  String chatPartnerProfileScreenB5c83bf6(Object name);

  /// No description provided for @chatPartnerProfileScreen09fd6568.
  ///
  /// In he, this message translates to:
  /// **'המשתמש לא יוכל יותר ליצור איתך קשר או לצפות במודעות שלך.'**
  String get chatPartnerProfileScreen09fd6568;

  /// No description provided for @chatPartnerProfileScreenA7c55a8d.
  ///
  /// In he, this message translates to:
  /// **'ביטול'**
  String get chatPartnerProfileScreenA7c55a8d;

  /// No description provided for @chatPartnerProfileScreen1257849a.
  ///
  /// In he, this message translates to:
  /// **'חסום'**
  String get chatPartnerProfileScreen1257849a;

  /// No description provided for @chatPartnerProfileScreen887fd210.
  ///
  /// In he, this message translates to:
  /// **'פעולה זו תמחק את כל ההודעות בשיחה זו. האם להמשיך?'**
  String get chatPartnerProfileScreen887fd210;

  /// No description provided for @chatPartnerProfileScreen09b6bcca.
  ///
  /// In he, this message translates to:
  /// **'מחק'**
  String get chatPartnerProfileScreen09b6bcca;

  /// No description provided for @marketBoardTemplate48227f9c.
  ///
  /// In he, this message translates to:
  /// **'צפיות'**
  String get marketBoardTemplate48227f9c;

  /// No description provided for @marketBoardTemplate066de4f8.
  ///
  /// In he, this message translates to:
  /// **'שמירות'**
  String get marketBoardTemplate066de4f8;

  /// No description provided for @marketBoardTemplate07433e11.
  ///
  /// In he, this message translates to:
  /// **'לייקים'**
  String get marketBoardTemplate07433e11;

  /// No description provided for @marketBoardTemplate23785eb4.
  ///
  /// In he, this message translates to:
  /// **'פניות'**
  String get marketBoardTemplate23785eb4;

  /// No description provided for @marketBoardTemplate60c1e500.
  ///
  /// In he, this message translates to:
  /// **'מחיר למ״ר'**
  String get marketBoardTemplate60c1e500;

  /// No description provided for @marketBoardTemplate13f110df.
  ///
  /// In he, this message translates to:
  /// **'ימים בשוק'**
  String get marketBoardTemplate13f110df;

  /// No description provided for @marketBoardTemplate95d86d7f.
  ///
  /// In he, this message translates to:
  /// **'היום'**
  String get marketBoardTemplate95d86d7f;

  /// No description provided for @marketBoardTemplateD51f71fc.
  ///
  /// In he, this message translates to:
  /// **'זמן צפייה ממוצע'**
  String get marketBoardTemplateD51f71fc;

  /// No description provided for @marketBoardTemplate261cf748.
  ///
  /// In he, this message translates to:
  /// **'החלקות בגלריה'**
  String get marketBoardTemplate261cf748;

  /// No description provided for @marketBoardTemplate2c925bfb.
  ///
  /// In he, this message translates to:
  /// **'נצפה ממש עכשיו'**
  String get marketBoardTemplate2c925bfb;

  /// No description provided for @marketBoardTemplateC88d38fc.
  ///
  /// In he, this message translates to:
  /// **'נצפה לפני {minutes} דק׳'**
  String marketBoardTemplateC88d38fc(Object minutes);

  /// No description provided for @marketBoardTemplate5787aec5.
  ///
  /// In he, this message translates to:
  /// **'נצפה לפני {hours} שע׳'**
  String marketBoardTemplate5787aec5(Object hours);

  /// No description provided for @marketBoardTemplate0a58ff05.
  ///
  /// In he, this message translates to:
  /// **'נצפה לפני {days} ימים'**
  String marketBoardTemplate0a58ff05(Object days);

  /// No description provided for @marketBoardTemplate3af8a1a1.
  ///
  /// In he, this message translates to:
  /// **'לוח שוק'**
  String get marketBoardTemplate3af8a1a1;

  /// No description provided for @marketBoardTemplate818d00f3.
  ///
  /// In he, this message translates to:
  /// **'נתוני ביקוש בזמן אמת'**
  String get marketBoardTemplate818d00f3;

  /// No description provided for @marketBoardTemplate636e854d.
  ///
  /// In he, this message translates to:
  /// **'צופה עכשיו'**
  String get marketBoardTemplate636e854d;

  /// No description provided for @marketBoardTemplate9b8e10c5.
  ///
  /// In he, this message translates to:
  /// **'{count} צופים'**
  String marketBoardTemplate9b8e10c5(Object count);

  /// No description provided for @marketBoardTemplateAd039ab0.
  ///
  /// In he, this message translates to:
  /// **'מגמת מחיר'**
  String get marketBoardTemplateAd039ab0;

  /// No description provided for @marketBoardTemplate2166e531.
  ///
  /// In he, this message translates to:
  /// **'{seconds} שנ׳'**
  String marketBoardTemplate2166e531(Object seconds);

  /// No description provided for @marketBoardTemplate80126da3.
  ///
  /// In he, this message translates to:
  /// **'{minutes} דק׳'**
  String marketBoardTemplate80126da3(Object minutes);

  /// No description provided for @marketBoardTemplateAa8238e7.
  ///
  /// In he, this message translates to:
  /// **'{hours} שע׳'**
  String marketBoardTemplateAa8238e7(Object hours);

  /// No description provided for @savedSearchesScreenC7d46456.
  ///
  /// In he, this message translates to:
  /// **'החיפוש שלי'**
  String get savedSearchesScreenC7d46456;

  /// No description provided for @savedSearchesScreenAce44591.
  ///
  /// In he, this message translates to:
  /// **'החיפושים שלי'**
  String get savedSearchesScreenAce44591;

  /// No description provided for @savedSearchesScreenDe24f588.
  ///
  /// In he, this message translates to:
  /// **'שלחנו לך התראה לדוגמה'**
  String get savedSearchesScreenDe24f588;

  /// No description provided for @savedSearchesScreenA6ccd3f5.
  ///
  /// In he, this message translates to:
  /// **'למחוק את החיפוש?'**
  String get savedSearchesScreenA6ccd3f5;

  /// No description provided for @savedSearchesScreenCa9c8510.
  ///
  /// In he, this message translates to:
  /// **'לא נודיע לך יותר על דירות חדשות מתאימות ל\"{name}\".'**
  String savedSearchesScreenCa9c8510(Object name);

  /// No description provided for @savedSearchesScreenA7c55a8d.
  ///
  /// In he, this message translates to:
  /// **'ביטול'**
  String get savedSearchesScreenA7c55a8d;

  /// No description provided for @savedSearchesScreen09b6bcca.
  ///
  /// In he, this message translates to:
  /// **'מחק'**
  String get savedSearchesScreen09b6bcca;

  /// No description provided for @savedSearchesScreen932eb7ab.
  ///
  /// In he, this message translates to:
  /// **'נודיע לך על דירות חדשות'**
  String get savedSearchesScreen932eb7ab;

  /// No description provided for @savedSearchesScreen0d57719f.
  ///
  /// In he, this message translates to:
  /// **'ההתראות כבויות'**
  String get savedSearchesScreen0d57719f;

  /// No description provided for @savedSearchesScreen0133e3ff.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חדרים'**
  String savedSearchesScreen0133e3ff(Object rooms);

  /// No description provided for @savedSearchesScreenB336259f.
  ///
  /// In he, this message translates to:
  /// **'להשכרה'**
  String get savedSearchesScreenB336259f;

  /// No description provided for @savedSearchesScreen609fac18.
  ///
  /// In he, this message translates to:
  /// **'למכירה'**
  String get savedSearchesScreen609fac18;

  /// No description provided for @savedSearchesScreenFe06d013.
  ///
  /// In he, this message translates to:
  /// **'מ-{min}'**
  String savedSearchesScreenFe06d013(Object min);

  /// No description provided for @savedSearchesScreen36f2a6b9.
  ///
  /// In he, this message translates to:
  /// **'עד {max}'**
  String savedSearchesScreen36f2a6b9(Object max);

  /// No description provided for @savedSearchesScreenA02655ab.
  ///
  /// In he, this message translates to:
  /// **'מ-{min}'**
  String savedSearchesScreenA02655ab(Object min);

  /// No description provided for @savedSearchesScreen09a44457.
  ///
  /// In he, this message translates to:
  /// **'עד {max}'**
  String savedSearchesScreen09a44457(Object max);

  /// No description provided for @savedSearchesScreenC0e45e79.
  ///
  /// In he, this message translates to:
  /// **'עדיין לא שמרת חיפוש'**
  String get savedSearchesScreenC0e45e79;

  /// No description provided for @savedSearchesScreen93343d42.
  ///
  /// In he, this message translates to:
  /// **'שמור חיפוש כדי שנודיע לך כשתעלה דירה שמתאימה.\n'**
  String get savedSearchesScreen93343d42;

  /// No description provided for @savedSearchesScreen962807e9.
  ///
  /// In he, this message translates to:
  /// **'דירות טובות נחטפות תוך ימים — שווה להיות הראשונים.'**
  String get savedSearchesScreen962807e9;

  /// No description provided for @savedSearchesScreen023a3173.
  ///
  /// In he, this message translates to:
  /// **'שלחו לי התראה לדוגמה'**
  String get savedSearchesScreen023a3173;

  /// No description provided for @boostFlowE384d773.
  ///
  /// In he, this message translates to:
  /// **'הקפצה רגילה'**
  String get boostFlowE384d773;

  /// No description provided for @boostFlow648bee95.
  ///
  /// In he, this message translates to:
  /// **'הקפצת Ultra'**
  String get boostFlow648bee95;

  /// No description provided for @boostFlowD39058af.
  ///
  /// In he, this message translates to:
  /// **'המודעה הוקפצה לראש הפיד! 🚀'**
  String get boostFlowD39058af;

  /// No description provided for @boostFlow51c32033.
  ///
  /// In he, this message translates to:
  /// **'המודעה הוקפצה! נותרו {remaining} הקפצות החודש.'**
  String boostFlow51c32033(Object remaining);

  /// No description provided for @boostFlow172c92b5.
  ///
  /// In he, this message translates to:
  /// **'ניצלת את מכסת ההקפצות החודשית.'**
  String get boostFlow172c92b5;

  /// No description provided for @boostFlowDabea174.
  ///
  /// In he, this message translates to:
  /// **'לא הצלחנו להקפיץ כרגע. נסו שוב.'**
  String get boostFlowDabea174;

  /// No description provided for @boostFlowEdb0335e.
  ///
  /// In he, this message translates to:
  /// **'פתיחת התשלום נכשלה. נסו שוב.'**
  String get boostFlowEdb0335e;

  /// No description provided for @boostFlow9ec81271.
  ///
  /// In he, this message translates to:
  /// **'{label} בוצעה! המודעה עלתה לראש הפיד 🚀'**
  String boostFlow9ec81271(Object label);

  /// No description provided for @boostFlowB43318dd.
  ///
  /// In he, this message translates to:
  /// **'הקפצת המודעה'**
  String get boostFlowB43318dd;

  /// No description provided for @boostFlow9a4075d7.
  ///
  /// In he, this message translates to:
  /// **'נגמרו ההקפצות שלך החודש'**
  String get boostFlow9a4075d7;

  /// No description provided for @boostFlow382ea104.
  ///
  /// In he, this message translates to:
  /// **'הקפיצו את המודעה'**
  String get boostFlow382ea104;

  /// No description provided for @boostFlow6497b9da.
  ///
  /// In he, this message translates to:
  /// **'קפיצה לראש הפיד = יותר צופים, מהר יותר.'**
  String get boostFlow6497b9da;

  /// No description provided for @boostFlow3635a9db.
  ///
  /// In he, this message translates to:
  /// **'רוצה שהדירה תמשיך לבלוט? הקפיצו אותה עכשיו.'**
  String get boostFlow3635a9db;

  /// No description provided for @boostFlowD9ad80b8.
  ///
  /// In he, this message translates to:
  /// **'תמורת ₪10 הדירה תעלה לראש הפיד ותגיע לכפול שוכרים היום.'**
  String get boostFlowD9ad80b8;

  /// No description provided for @boostFlow4d1b0704.
  ///
  /// In he, this message translates to:
  /// **'×2 חשיפה · ראש הפיד · 7 ימים'**
  String get boostFlow4d1b0704;

  /// No description provided for @boostFlow58bc394e.
  ///
  /// In he, this message translates to:
  /// **'כלול'**
  String get boostFlow58bc394e;

  /// No description provided for @boostFlowFaea170c.
  ///
  /// In he, this message translates to:
  /// **'נותרו {remaining}'**
  String boostFlowFaea170c(Object remaining);

  /// No description provided for @boostFlow58d8e569.
  ///
  /// In he, this message translates to:
  /// **'×5 חשיפה · מסגרת זהב · קדימות על הקפצות רגילות · 7 ימים'**
  String get boostFlow58d8e569;

  /// No description provided for @brokerCmaScreen9c3d866e.
  ///
  /// In he, this message translates to:
  /// **'ניתוח שוק ותמחור'**
  String get brokerCmaScreen9c3d866e;

  /// No description provided for @brokerCmaScreenC5a0f18d.
  ///
  /// In he, this message translates to:
  /// **'אין לך נכסים פעילים לניתוח עדיין.'**
  String get brokerCmaScreenC5a0f18d;

  /// No description provided for @brokerCmaScreen522d75ea.
  ///
  /// In he, this message translates to:
  /// **'בחר נכס לניתוח'**
  String get brokerCmaScreen522d75ea;

  /// No description provided for @brokerCmaScreen07694aa8.
  ///
  /// In he, this message translates to:
  /// **'{address} · {rooms} חד׳'**
  String brokerCmaScreen07694aa8(Object address, Object rooms);

  /// No description provided for @brokerCmaScreen0f726673.
  ///
  /// In he, this message translates to:
  /// **'נכסים להשוואה ({count})'**
  String brokerCmaScreen0f726673(Object count);

  /// No description provided for @brokerCmaScreen6fe1b49e.
  ///
  /// In he, this message translates to:
  /// **'אותה עיר · עד חדר הפרש · אותו סוג עסקה'**
  String get brokerCmaScreen6fe1b49e;

  /// No description provided for @brokerCmaScreenBc3ff8c5.
  ///
  /// In he, this message translates to:
  /// **'לא נמצאו נכסים דומים בשוק להשוואה.'**
  String get brokerCmaScreenBc3ff8c5;

  /// No description provided for @brokerCmaScreenBdb3f99c.
  ///
  /// In he, this message translates to:
  /// **'מתחת לטווח המומלץ — אפשר אולי להעלות מחיר'**
  String get brokerCmaScreenBdb3f99c;

  /// No description provided for @brokerCmaScreenEbc33063.
  ///
  /// In he, this message translates to:
  /// **'מעל הטווח המומלץ — קשה יותר להצדיק מול הקונה'**
  String get brokerCmaScreenEbc33063;

  /// No description provided for @brokerCmaScreen8d3fc214.
  ///
  /// In he, this message translates to:
  /// **'בתוך הטווח המומלץ — תמחור תואם שוק'**
  String get brokerCmaScreen8d3fc214;

  /// No description provided for @brokerCmaScreen71fb17fd.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חד׳ · {size} מ״ר · {transaction}'**
  String brokerCmaScreen71fb17fd(Object rooms, Object size, Object transaction);

  /// No description provided for @brokerCmaScreen50d090d2.
  ///
  /// In he, this message translates to:
  /// **'המחיר הנוכחי: {price}'**
  String brokerCmaScreen50d090d2(Object price);

  /// No description provided for @brokerCmaScreen130275e8.
  ///
  /// In he, this message translates to:
  /// **'מעט נכסים דומים בשוק — ההערכה מבוססת על מדד CBS לאזור.'**
  String get brokerCmaScreen130275e8;

  /// No description provided for @brokerCmaScreenC0d229c4.
  ///
  /// In he, this message translates to:
  /// **'אין מספיק נתוני שוק לחישוב טווח מומלץ.'**
  String get brokerCmaScreenC0d229c4;

  /// No description provided for @brokerCmaScreen0c53e27e.
  ///
  /// In he, this message translates to:
  /// **'טווח מחיר מומלץ (25–75 אחוזון)'**
  String get brokerCmaScreen0c53e27e;

  /// No description provided for @brokerCmaScreen6818b5d6.
  ///
  /// In he, this message translates to:
  /// **'חציון השוק: {median}'**
  String brokerCmaScreen6818b5d6(Object median);

  /// No description provided for @brokerCmaScreen4d538821.
  ///
  /// In he, this message translates to:
  /// **'מדד שוק (CBS · נדל\"ן)'**
  String get brokerCmaScreen4d538821;

  /// No description provided for @brokerCmaScreen320820a2.
  ///
  /// In he, this message translates to:
  /// **'{price} למ״ר · חציון האזור'**
  String brokerCmaScreen320820a2(Object price);

  /// No description provided for @brokerCmaScreen2b9269cd.
  ///
  /// In he, this message translates to:
  /// **'מחיר הוגן משוער לנכס: {price}'**
  String brokerCmaScreen2b9269cd(Object price);

  /// No description provided for @brokerCmaScreenE17f3334.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חד׳ · {size} מ״ר'**
  String brokerCmaScreenE17f3334(Object rooms, Object size);

  /// No description provided for @verificationInfoSheet220a89be.
  ///
  /// In he, this message translates to:
  /// **'דירה מאומתת'**
  String get verificationInfoSheet220a89be;

  /// No description provided for @verificationInfoSheet1079b7b6.
  ///
  /// In he, this message translates to:
  /// **'בעל הדירה צילם סרטון אמיתי של הדירה ישירות מתוך האפליקציה. '**
  String get verificationInfoSheet1079b7b6;

  /// No description provided for @verificationInfoSheetF194db27.
  ///
  /// In he, this message translates to:
  /// **'זה אומר שמדובר בדירה אמיתית וקיימת — לא תמונה שנלקחה מהאינטרנט.'**
  String get verificationInfoSheetF194db27;

  /// No description provided for @verificationInfoSheet92ba2f6a.
  ///
  /// In he, this message translates to:
  /// **'שימו לב: אימות מאשר שהדירה אמיתית — אבל תמיד כדאי לבדוק כל מודעה לפי הסימנים שלמטה.'**
  String get verificationInfoSheet92ba2f6a;

  /// No description provided for @verificationInfoSheet7e5cc81f.
  ///
  /// In he, this message translates to:
  /// **'שלושה סימני אזהרה להונאה'**
  String get verificationInfoSheet7e5cc81f;

  /// No description provided for @verificationInfoSheet515b9741.
  ///
  /// In he, this message translates to:
  /// **'נכון לכל מודעה — גם למאומתת.'**
  String get verificationInfoSheet515b9741;

  /// No description provided for @verificationInfoSheet34c41aab.
  ///
  /// In he, this message translates to:
  /// **'אל תשלמו כסף לפני שראיתם את הדירה פיזית'**
  String get verificationInfoSheet34c41aab;

  /// No description provided for @verificationInfoSheetF3def21a.
  ///
  /// In he, this message translates to:
  /// **'אף פעם אל תעבירו מקדמה, פיקדון או \"דמי רצינות\" לפני שביקרתם בדירה במו עיניכם '**
  String get verificationInfoSheetF3def21a;

  /// No description provided for @verificationInfoSheet62b9758c.
  ///
  /// In he, this message translates to:
  /// **'ופגשתם את בעל הדירה. בקשה לתשלום מראש היא הסימן הכי נפוץ להונאה.'**
  String get verificationInfoSheet62b9758c;

  /// No description provided for @verificationInfoSheet8e732266.
  ///
  /// In he, this message translates to:
  /// **'פיקדון חוקי מוגבל ל-3 חודשי שכירות'**
  String get verificationInfoSheet8e732266;

  /// No description provided for @verificationInfoSheetEf8e2318.
  ///
  /// In he, this message translates to:
  /// **'לפי חוק שכירות הוגנת, בעל הדירה לא יכול לדרוש פיקדון גבוה משלושה חודשי שכירות. '**
  String get verificationInfoSheetEf8e2318;

  /// No description provided for @verificationInfoSheetF18547d6.
  ///
  /// In he, this message translates to:
  /// **'דרישה לסכום גבוה בהרבה היא סימן אזהרה.'**
  String get verificationInfoSheetF18547d6;

  /// No description provided for @verificationInfoSheet488f7486.
  ///
  /// In he, this message translates to:
  /// **'מחיר נמוך בצורה חשודה = כנראה הונאה'**
  String get verificationInfoSheet488f7486;

  /// No description provided for @verificationInfoSheet0d24ccbd.
  ///
  /// In he, this message translates to:
  /// **'אם המחיר נמוך בהרבה מדירות דומות באזור, כנראה משהו לא בסדר. '**
  String get verificationInfoSheet0d24ccbd;

  /// No description provided for @verificationInfoSheet82cdbe86.
  ///
  /// In he, this message translates to:
  /// **'מרמים מפתים עם מחיר זול כדי שתעבירו כסף מהר.'**
  String get verificationInfoSheet82cdbe86;

  /// No description provided for @verificationInfoSheet0cba7786.
  ///
  /// In he, this message translates to:
  /// **'נתקלתם במשהו חשוד? '**
  String get verificationInfoSheet0cba7786;

  /// No description provided for @verificationInfoSheetE3638d06.
  ///
  /// In he, this message translates to:
  /// **'לחצו על כפתור הדיווח (⋯) שבמודעה ובחרו \"דיווח על מודעה\". '**
  String get verificationInfoSheetE3638d06;

  /// No description provided for @verificationInfoSheet49e4fb5f.
  ///
  /// In he, this message translates to:
  /// **'הצוות שלנו בודק כל דיווח ומסיר מודעות מזויפות.'**
  String get verificationInfoSheet49e4fb5f;

  /// No description provided for @verificationInfoSheetEe9c82fc.
  ///
  /// In he, this message translates to:
  /// **'הבנתי, תודה'**
  String get verificationInfoSheetEe9c82fc;

  /// No description provided for @areaRankingScreen55528b91.
  ///
  /// In he, this message translates to:
  /// **'לא מצאתי אזורים סטטיסטיים לעיר הזו. נסה שם עיר מלא (למשל: תל אביב, חיפה, ירושלים).'**
  String get areaRankingScreen55528b91;

  /// No description provided for @areaRankingScreen8b5f2411.
  ///
  /// In he, this message translates to:
  /// **'דרג אזורים בעיר'**
  String get areaRankingScreen8b5f2411;

  /// No description provided for @areaRankingScreenEf8f7b72.
  ///
  /// In he, this message translates to:
  /// **'רשימה'**
  String get areaRankingScreenEf8f7b72;

  /// No description provided for @areaRankingScreen876e3baa.
  ///
  /// In he, this message translates to:
  /// **'מפה'**
  String get areaRankingScreen876e3baa;

  /// No description provided for @areaRankingScreen80d6e90e.
  ///
  /// In he, this message translates to:
  /// **'עיר (למשל: תל אביב)'**
  String get areaRankingScreen80d6e90e;

  /// No description provided for @areaRankingScreen71771aec.
  ///
  /// In he, this message translates to:
  /// **'דרג'**
  String get areaRankingScreen71771aec;

  /// No description provided for @areaRankingScreen56ee2a52.
  ///
  /// In he, this message translates to:
  /// **'אזור {id}  ·  אשכול {ses}/10'**
  String areaRankingScreen56ee2a52(Object id, Object ses);

  /// No description provided for @areaRankingScreen2d376c8a.
  ///
  /// In he, this message translates to:
  /// **'אזור {id}'**
  String areaRankingScreen2d376c8a(Object id);

  /// No description provided for @areaRankingScreen711ab217.
  ///
  /// In he, this message translates to:
  /// **'{pct}% התאמה'**
  String areaRankingScreen711ab217(Object pct);

  /// No description provided for @areaRankingScreen581d0b4f.
  ///
  /// In he, this message translates to:
  /// **'אשכול סוציו-אקונומי'**
  String get areaRankingScreen581d0b4f;

  /// No description provided for @areaRankingScreenE642cece.
  ///
  /// In he, this message translates to:
  /// **'בטיחות'**
  String get areaRankingScreenE642cece;

  /// No description provided for @areaRankingScreen096a70c8.
  ///
  /// In he, this message translates to:
  /// **'מרכזיות'**
  String get areaRankingScreen096a70c8;

  /// No description provided for @areaRankingScreen8cf2e63d.
  ///
  /// In he, this message translates to:
  /// **'תחבורה'**
  String get areaRankingScreen8cf2e63d;

  /// No description provided for @areaRankingScreen930bb12c.
  ///
  /// In he, this message translates to:
  /// **'חינוך'**
  String get areaRankingScreen930bb12c;

  /// No description provided for @areaRankingScreenC2a64aa6.
  ///
  /// In he, this message translates to:
  /// **'ילדים / עובדים / 65+'**
  String get areaRankingScreenC2a64aa6;

  /// No description provided for @areaRankingScreenDae2e4fc.
  ///
  /// In he, this message translates to:
  /// **'💰 ציון השקעה'**
  String get areaRankingScreenDae2e4fc;

  /// No description provided for @areaRankingScreen9e42f94f.
  ///
  /// In he, this message translates to:
  /// **'ביקוש שכירות'**
  String get areaRankingScreen9e42f94f;

  /// No description provided for @areaRankingScreen4d408308.
  ///
  /// In he, this message translates to:
  /// **'הערכת תשואה (גסה)'**
  String get areaRankingScreen4d408308;

  /// No description provided for @notificationsScreen86ed07cf.
  ///
  /// In he, this message translates to:
  /// **'המכשיר עוד לא רשום להתראות 📵 סגור ופתח מחדש את האפליקציה ונסה שוב'**
  String get notificationsScreen86ed07cf;

  /// No description provided for @notificationsScreen72b5771b.
  ///
  /// In he, this message translates to:
  /// **'שלחתי התראה 🔔 אמורה לקפוץ תוך רגע (נשלח ל-{pushed} מכשירים)'**
  String notificationsScreen72b5771b(Object pushed);

  /// No description provided for @notificationsScreen34803854.
  ///
  /// In he, this message translates to:
  /// **'הטוקן רשום אבל השליחה נכשלה — כנראה טוקן ישן, סגור ופתח את האפליקציה'**
  String get notificationsScreen34803854;

  /// No description provided for @notificationsScreen5c3916c3.
  ///
  /// In he, this message translates to:
  /// **'לא הצלחתי לשלוח כרגע, נסה שוב'**
  String get notificationsScreen5c3916c3;

  /// No description provided for @notificationsScreenA8e71c4c.
  ///
  /// In he, this message translates to:
  /// **'התראות'**
  String get notificationsScreenA8e71c4c;

  /// No description provided for @notificationsScreen972c5de2.
  ///
  /// In he, this message translates to:
  /// **'שליחת התראת בדיקה'**
  String get notificationsScreen972c5de2;

  /// No description provided for @notificationsScreenFc4def53.
  ///
  /// In he, this message translates to:
  /// **'סמן הכל כנקרא'**
  String get notificationsScreenFc4def53;

  /// No description provided for @notificationsScreen40381be4.
  ///
  /// In he, this message translates to:
  /// **'לא הצלחנו לטעון התראות'**
  String get notificationsScreen40381be4;

  /// No description provided for @notificationsScreenB8dcc665.
  ///
  /// In he, this message translates to:
  /// **'משכו למטה כדי לנסות שוב'**
  String get notificationsScreenB8dcc665;

  /// No description provided for @notificationsScreen838add51.
  ///
  /// In he, this message translates to:
  /// **'אין התראות חדשות'**
  String get notificationsScreen838add51;

  /// No description provided for @notificationsScreenD3556461.
  ///
  /// In he, this message translates to:
  /// **'כאן יופיעו עדכונים על התאמות, הודעות ועוד'**
  String get notificationsScreenD3556461;

  /// No description provided for @notificationsScreenA26f165a.
  ///
  /// In he, this message translates to:
  /// **'עכשיו'**
  String get notificationsScreenA26f165a;

  /// No description provided for @notificationsScreen5fede189.
  ///
  /// In he, this message translates to:
  /// **'לפני {minutes} דק׳'**
  String notificationsScreen5fede189(Object minutes);

  /// No description provided for @notificationsScreen18f294e5.
  ///
  /// In he, this message translates to:
  /// **'לפני {hours} שע׳'**
  String notificationsScreen18f294e5(Object hours);

  /// No description provided for @notificationsScreenBe285a01.
  ///
  /// In he, this message translates to:
  /// **'אתמול'**
  String get notificationsScreenBe285a01;

  /// No description provided for @notificationsScreen0cfbdf39.
  ///
  /// In he, this message translates to:
  /// **'לפני {days} ימים'**
  String notificationsScreen0cfbdf39(Object days);

  /// No description provided for @notificationsScreen3e4eb262.
  ///
  /// In he, this message translates to:
  /// **'לפני שבוע'**
  String get notificationsScreen3e4eb262;

  /// No description provided for @notificationsScreen920434a5.
  ///
  /// In he, this message translates to:
  /// **'לפני {weeks} שבועות'**
  String notificationsScreen920434a5(Object weeks);

  /// No description provided for @propertyShareSheetF15bfc25.
  ///
  /// In he, this message translates to:
  /// **'מצאתי נכס מעניין ב-Rently'**
  String get propertyShareSheetF15bfc25;

  /// No description provided for @propertyShareSheetD886d07f.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חדרים'**
  String propertyShareSheetD886d07f(Object rooms);

  /// No description provided for @propertyShareSheet5d29dec4.
  ///
  /// In he, this message translates to:
  /// **'{size} מ\"ר'**
  String propertyShareSheet5d29dec4(Object size);

  /// No description provided for @propertyShareSheetEd00d602.
  ///
  /// In he, this message translates to:
  /// **'שלח את הנכס מהר דרך האפליקציה שנוחה לך, או העתק את הפרטים לשיתוף ידני.'**
  String get propertyShareSheetEd00d602;

  /// No description provided for @propertyShareSheet827cec4d.
  ///
  /// In he, this message translates to:
  /// **'שליחה ישירה'**
  String get propertyShareSheet827cec4d;

  /// No description provided for @propertyShareSheetC23278cd.
  ///
  /// In he, this message translates to:
  /// **'לא ניתן לפתוח את WhatsApp כרגע'**
  String get propertyShareSheetC23278cd;

  /// No description provided for @propertyShareSheet5abda5bb.
  ///
  /// In he, this message translates to:
  /// **'הודעת טקסט'**
  String get propertyShareSheet5abda5bb;

  /// No description provided for @propertyShareSheet12d7a7d4.
  ///
  /// In he, this message translates to:
  /// **'לא ניתן לפתוח SMS כרגע'**
  String get propertyShareSheet12d7a7d4;

  /// No description provided for @propertyShareSheetC57dda61.
  ///
  /// In he, this message translates to:
  /// **'שליחה במייל'**
  String get propertyShareSheetC57dda61;

  /// No description provided for @propertyShareSheet88f45e7e.
  ///
  /// In he, this message translates to:
  /// **'נכס שיכול להתאים לך'**
  String get propertyShareSheet88f45e7e;

  /// No description provided for @propertyShareSheet600502fd.
  ///
  /// In he, this message translates to:
  /// **'לא ניתן לפתוח אימייל כרגע'**
  String get propertyShareSheet600502fd;

  /// No description provided for @propertyShareSheetB26acdf0.
  ///
  /// In he, this message translates to:
  /// **'העתק פרטים'**
  String get propertyShareSheetB26acdf0;

  /// No description provided for @propertyShareSheet3a798b8a.
  ///
  /// In he, this message translates to:
  /// **'טקסט מלא לשיתוף'**
  String get propertyShareSheet3a798b8a;

  /// No description provided for @propertyShareSheet79a0ff65.
  ///
  /// In he, this message translates to:
  /// **'פרטי הנכס הועתקו'**
  String get propertyShareSheet79a0ff65;

  /// No description provided for @propertyShareSheet4aa70f6f.
  ///
  /// In he, this message translates to:
  /// **'הקישור הועתק'**
  String get propertyShareSheet4aa70f6f;

  /// No description provided for @propertyShareSheet3589781c.
  ///
  /// In he, this message translates to:
  /// **'העתק קישור לשיתוף'**
  String get propertyShareSheet3589781c;

  /// No description provided for @targetPersonasB0b0c3cf.
  ///
  /// In he, this message translates to:
  /// **'זוגות צעירים'**
  String get targetPersonasB0b0c3cf;

  /// No description provided for @targetPersonasF56f1edd.
  ///
  /// In he, this message translates to:
  /// **'משפחות עם ילדים'**
  String get targetPersonasF56f1edd;

  /// No description provided for @targetPersonas99e7c02f.
  ///
  /// In he, this message translates to:
  /// **'סטודנטים'**
  String get targetPersonas99e7c02f;

  /// No description provided for @targetPersonasD468d495.
  ///
  /// In he, this message translates to:
  /// **'אנשי הייטק'**
  String get targetPersonasD468d495;

  /// No description provided for @targetPersonasA8dc0f49.
  ///
  /// In he, this message translates to:
  /// **'מבוגרים / פרישה'**
  String get targetPersonasA8dc0f49;

  /// No description provided for @targetPersonasE86bb514.
  ///
  /// In he, this message translates to:
  /// **'משקיע תשואה'**
  String get targetPersonasE86bb514;

  /// No description provided for @targetPersonas55c1710d.
  ///
  /// In he, this message translates to:
  /// **'משקיע השבחה'**
  String get targetPersonas55c1710d;

  /// No description provided for @affordability5e721167.
  ///
  /// In he, this message translates to:
  /// **'שכר דירה לחודש הראשון'**
  String get affordability5e721167;

  /// No description provided for @affordability26a740b7.
  ///
  /// In he, this message translates to:
  /// **'פיקדון/בטוחות (מוגבל בחוק)'**
  String get affordability26a740b7;

  /// No description provided for @affordabilityFc095a4e.
  ///
  /// In he, this message translates to:
  /// **'דמי תיווך (חודש + מע״מ 18%)'**
  String get affordabilityFc095a4e;

  /// No description provided for @erikVoiceCallCc39e21a.
  ///
  /// In he, this message translates to:
  /// **'מתחבר...'**
  String get erikVoiceCallCc39e21a;

  /// No description provided for @erikVoiceCall8f3676b5.
  ///
  /// In he, this message translates to:
  /// **'מקשיב — דבר חופשי'**
  String get erikVoiceCall8f3676b5;

  /// No description provided for @erikVoiceCallD96185d1.
  ///
  /// In he, this message translates to:
  /// **'עזרא · מוכן לשיחה'**
  String get erikVoiceCallD96185d1;

  /// No description provided for @erikVoiceCall511207a2.
  ///
  /// In he, this message translates to:
  /// **'גע בכדור כדי לדבר איתי, או הקש ⌨ כדי לכתוב.'**
  String get erikVoiceCall511207a2;

  /// No description provided for @erikVoiceCall74a231d6.
  ///
  /// In he, this message translates to:
  /// **'עזרא עונה לך...'**
  String get erikVoiceCall74a231d6;

  /// No description provided for @erikVoiceCall2d820199.
  ///
  /// In he, this message translates to:
  /// **'אני מקשיב — דבר חופשי על הדירה.'**
  String get erikVoiceCall2d820199;

  /// No description provided for @erikVoiceCall4443ec8d.
  ///
  /// In he, this message translates to:
  /// **'קול פעיל'**
  String get erikVoiceCall4443ec8d;

  /// No description provided for @erikVoiceCall594c7589.
  ///
  /// In he, this message translates to:
  /// **'מושתק'**
  String get erikVoiceCall594c7589;

  /// No description provided for @erikVoiceCall04195099.
  ///
  /// In he, this message translates to:
  /// **'מקשיב...'**
  String get erikVoiceCall04195099;

  /// No description provided for @erikVoiceCall3eee9380.
  ///
  /// In he, this message translates to:
  /// **'דבר'**
  String get erikVoiceCall3eee9380;

  /// No description provided for @erikVoiceCallC6f7f477.
  ///
  /// In he, this message translates to:
  /// **'מקלדת'**
  String get erikVoiceCallC6f7f477;

  /// No description provided for @erikVoiceCall55247199.
  ///
  /// In he, this message translates to:
  /// **'סגור'**
  String get erikVoiceCall55247199;

  /// No description provided for @erikVoiceCall2f3790da.
  ///
  /// In he, this message translates to:
  /// **'כתוב לעזרא'**
  String get erikVoiceCall2f3790da;

  /// No description provided for @erikVoiceCallB8b81253.
  ///
  /// In he, this message translates to:
  /// **'כתוב הודעה...'**
  String get erikVoiceCallB8b81253;

  /// No description provided for @classicTemplate220d2733.
  ///
  /// In he, this message translates to:
  /// **'פרטי הנכס'**
  String get classicTemplate220d2733;

  /// No description provided for @classicTemplate64680a66.
  ///
  /// In he, this message translates to:
  /// **'מאפיינים חשובים'**
  String get classicTemplate64680a66;

  /// No description provided for @classicTemplateEed2fbf3.
  ///
  /// In he, this message translates to:
  /// **'גלריה'**
  String get classicTemplateEed2fbf3;

  /// No description provided for @classicTemplateAb29f776.
  ///
  /// In he, this message translates to:
  /// **'{count} תמונות'**
  String classicTemplateAb29f776(Object count);

  /// No description provided for @classicTemplateF5686614.
  ///
  /// In he, this message translates to:
  /// **'סרטון'**
  String get classicTemplateF5686614;

  /// No description provided for @classicTemplate0429d88a.
  ///
  /// In he, this message translates to:
  /// **'תמונה {index}'**
  String classicTemplate0429d88a(Object index);

  /// No description provided for @classicTemplateCb66c16b.
  ///
  /// In he, this message translates to:
  /// **'אתר מקור'**
  String get classicTemplateCb66c16b;

  /// No description provided for @classicTemplate5e4548cf.
  ///
  /// In he, this message translates to:
  /// **'צפה במקור'**
  String get classicTemplate5e4548cf;

  /// No description provided for @classicTemplateB58f6b9c.
  ///
  /// In he, this message translates to:
  /// **'נכס זה פורסם במקור באתר {host}. באפשרותך לפתוח את המודעה המקורית לצפייה בפרטים המלאים.'**
  String classicTemplateB58f6b9c(Object host);

  /// No description provided for @classicTemplateC1a89075.
  ///
  /// In he, this message translates to:
  /// **'בעל הנכס'**
  String get classicTemplateC1a89075;

  /// No description provided for @classicTemplate1c5efd6c.
  ///
  /// In he, this message translates to:
  /// **'חוות דעת'**
  String get classicTemplate1c5efd6c;

  /// No description provided for @classicTemplate16c30b46.
  ///
  /// In he, this message translates to:
  /// **'{count} ביקורות'**
  String classicTemplate16c30b46(Object count);

  /// No description provided for @classicTemplate26d0e7de.
  ///
  /// In he, this message translates to:
  /// **'מיקום'**
  String get classicTemplate26d0e7de;

  /// No description provided for @classicTemplate88aea894.
  ///
  /// In he, this message translates to:
  /// **'הקפצה'**
  String get classicTemplate88aea894;

  /// No description provided for @galleryEditorialTemplate4771acf8.
  ///
  /// In he, this message translates to:
  /// **'נכס נבחר'**
  String get galleryEditorialTemplate4771acf8;

  /// No description provided for @galleryEditorialTemplate17773b7f.
  ///
  /// In he, this message translates to:
  /// **'{type} ב{street}{number}'**
  String galleryEditorialTemplate17773b7f(
      Object number, Object street, Object type);

  /// No description provided for @galleryEditorialTemplateD886d07f.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חדרים'**
  String galleryEditorialTemplateD886d07f(Object rooms);

  /// No description provided for @galleryEditorialTemplateFdb4eac7.
  ///
  /// In he, this message translates to:
  /// **'{size} מ״ר'**
  String galleryEditorialTemplateFdb4eac7(Object size);

  /// No description provided for @galleryEditorialTemplateCa554bb0.
  ///
  /// In he, this message translates to:
  /// **'קומה {floor} מתוך {total}'**
  String galleryEditorialTemplateCa554bb0(Object floor, Object total);

  /// No description provided for @galleryEditorialTemplateD068bb57.
  ///
  /// In he, this message translates to:
  /// **'קומה {floor}'**
  String galleryEditorialTemplateD068bb57(Object floor);

  /// No description provided for @galleryEditorialTemplate19aad790.
  ///
  /// In he, this message translates to:
  /// **'{type} ב{place}. {spec}.'**
  String galleryEditorialTemplate19aad790(
      Object place, Object spec, Object type);

  /// No description provided for @galleryEditorialTemplateA765f2f3.
  ///
  /// In he, this message translates to:
  /// **'נכס למכירה'**
  String get galleryEditorialTemplateA765f2f3;

  /// No description provided for @galleryEditorialTemplate900c3a51.
  ///
  /// In he, this message translates to:
  /// **'נכס להשכרה'**
  String get galleryEditorialTemplate900c3a51;

  /// No description provided for @galleryEditorialTemplateE5340f86.
  ///
  /// In he, this message translates to:
  /// **'₪{ppm} למ״ר'**
  String galleryEditorialTemplateE5340f86(Object ppm);

  /// No description provided for @galleryEditorialTemplateB50b3974.
  ///
  /// In he, this message translates to:
  /// **'חדרים'**
  String get galleryEditorialTemplateB50b3974;

  /// No description provided for @galleryEditorialTemplateD3b9013b.
  ///
  /// In he, this message translates to:
  /// **'מ״ר'**
  String get galleryEditorialTemplateD3b9013b;

  /// No description provided for @galleryEditorialTemplate047e630b.
  ///
  /// In he, this message translates to:
  /// **'קומה'**
  String get galleryEditorialTemplate047e630b;

  /// No description provided for @galleryEditorialTemplate71c5f6b5.
  ///
  /// In he, this message translates to:
  /// **'קומות'**
  String get galleryEditorialTemplate71c5f6b5;

  /// No description provided for @neighborhoodScoreCardE642cece.
  ///
  /// In he, this message translates to:
  /// **'בטיחות'**
  String get neighborhoodScoreCardE642cece;

  /// No description provided for @neighborhoodScoreCard0fff92d0.
  ///
  /// In he, this message translates to:
  /// **'הליכתיות'**
  String get neighborhoodScoreCard0fff92d0;

  /// No description provided for @neighborhoodScoreCard5a567748.
  ///
  /// In he, this message translates to:
  /// **'בתי״ס'**
  String get neighborhoodScoreCard5a567748;

  /// No description provided for @neighborhoodScoreCard00a5eaf2.
  ///
  /// In he, this message translates to:
  /// **'גני ילדים'**
  String get neighborhoodScoreCard00a5eaf2;

  /// No description provided for @neighborhoodScoreCard8cf2e63d.
  ///
  /// In he, this message translates to:
  /// **'תחבורה'**
  String get neighborhoodScoreCard8cf2e63d;

  /// No description provided for @neighborhoodScoreCard08d4f99e.
  ///
  /// In he, this message translates to:
  /// **'ירוק'**
  String get neighborhoodScoreCard08d4f99e;

  /// No description provided for @neighborhoodScoreCard40d07087.
  ///
  /// In he, this message translates to:
  /// **'שקט'**
  String get neighborhoodScoreCard40d07087;

  /// No description provided for @neighborhoodScoreCard2de2ff3f.
  ///
  /// In he, this message translates to:
  /// **'ציון השכונה'**
  String get neighborhoodScoreCard2de2ff3f;

  /// No description provided for @neighborhoodScoreCard542929e1.
  ///
  /// In he, this message translates to:
  /// **'הצג פירוט ומקורות'**
  String get neighborhoodScoreCard542929e1;

  /// No description provided for @neighborhoodScoreCard63eefa9b.
  ///
  /// In he, this message translates to:
  /// **'הציון הכולל הוא ממוצע משוקלל של הפרמטרים הבאים, המחושבים מנתונים ציבוריים ונקודות עניין באזור.'**
  String get neighborhoodScoreCard63eefa9b;

  /// No description provided for @neighborhoodScoreCard4c69a81b.
  ///
  /// In he, this message translates to:
  /// **'אין עדיין פירוט זמין לאזור זה.'**
  String get neighborhoodScoreCard4c69a81b;

  /// No description provided for @neighborhoodScoreCard5d1b29db.
  ///
  /// In he, this message translates to:
  /// **'מקורות הנתונים'**
  String get neighborhoodScoreCard5d1b29db;

  /// No description provided for @realtimeVoiceScreenE3b9c24d.
  ///
  /// In he, this message translates to:
  /// **'שלום, אני אתי 👋 פשוט דברו איתי.'**
  String get realtimeVoiceScreenE3b9c24d;

  /// No description provided for @realtimeVoiceScreenA7587542.
  ///
  /// In he, this message translates to:
  /// **'מתחברת…'**
  String get realtimeVoiceScreenA7587542;

  /// No description provided for @realtimeVoiceScreen85084af4.
  ///
  /// In he, this message translates to:
  /// **'מקשיבה לך…'**
  String get realtimeVoiceScreen85084af4;

  /// No description provided for @realtimeVoiceScreenA6de1c7e.
  ///
  /// In he, this message translates to:
  /// **'רגע, חושבת…'**
  String get realtimeVoiceScreenA6de1c7e;

  /// No description provided for @realtimeVoiceScreen0658343f.
  ///
  /// In he, this message translates to:
  /// **'אתי מדברת · פשוט דברו כדי להפריע'**
  String get realtimeVoiceScreen0658343f;

  /// No description provided for @realtimeVoiceScreen9aea3a09.
  ///
  /// In he, this message translates to:
  /// **'דברו איתי'**
  String get realtimeVoiceScreen9aea3a09;

  /// No description provided for @realtimeVoiceScreenE60120ca.
  ///
  /// In he, this message translates to:
  /// **'הייתה תקלה בחיבור'**
  String get realtimeVoiceScreenE60120ca;

  /// No description provided for @realtimeVoiceScreen8e4d1523.
  ///
  /// In he, this message translates to:
  /// **'אתי'**
  String get realtimeVoiceScreen8e4d1523;

  /// No description provided for @realtimeVoiceScreen5a17ea8a.
  ///
  /// In he, this message translates to:
  /// **'שיחה חיה • Rently'**
  String get realtimeVoiceScreen5a17ea8a;

  /// No description provided for @realtimeVoiceScreenAf4fd15c.
  ///
  /// In he, this message translates to:
  /// **'עבור לשיחה רגילה 💬'**
  String get realtimeVoiceScreenAf4fd15c;

  /// No description provided for @realtimeVoiceScreen38f0b537.
  ///
  /// In he, this message translates to:
  /// **'מצאתי {count} דירות שמתאימות לך 👇'**
  String realtimeVoiceScreen38f0b537(Object count);

  /// No description provided for @brokerBrochureScreenE4ac75e8.
  ///
  /// In he, this message translates to:
  /// **'ברושור נכס ממותג'**
  String get brokerBrochureScreenE4ac75e8;

  /// No description provided for @brokerBrochureScreenD886d07f.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חדרים'**
  String brokerBrochureScreenD886d07f(Object rooms);

  /// No description provided for @brokerBrochureScreen5d29dec4.
  ///
  /// In he, this message translates to:
  /// **'{size} מ\"ר'**
  String brokerBrochureScreen5d29dec4(Object size);

  /// No description provided for @brokerBrochureScreenD068bb57.
  ///
  /// In he, this message translates to:
  /// **'קומה {floor}'**
  String brokerBrochureScreenD068bb57(Object floor);

  /// No description provided for @brokerBrochureScreen04734464.
  ///
  /// In he, this message translates to:
  /// **'המתווך שלך'**
  String get brokerBrochureScreen04734464;

  /// No description provided for @brokerBrochureScreenB7b87736.
  ///
  /// In he, this message translates to:
  /// **'תיווך נדל\"ן'**
  String get brokerBrochureScreenB7b87736;

  /// No description provided for @brokerBrochureScreenF2af0c97.
  ///
  /// In he, this message translates to:
  /// **'מכין ברושור…'**
  String get brokerBrochureScreenF2af0c97;

  /// No description provided for @brokerBrochureScreen0312eb6d.
  ///
  /// In he, this message translates to:
  /// **'שתף ברושור'**
  String get brokerBrochureScreen0312eb6d;

  /// No description provided for @brokerBrochureScreenC96fa39c.
  ///
  /// In he, this message translates to:
  /// **'אין עדיין נכסים'**
  String get brokerBrochureScreenC96fa39c;

  /// No description provided for @brokerBrochureScreen26099985.
  ///
  /// In he, this message translates to:
  /// **'הוסיפו נכס כדי להפיק ברושור ממותג לשיתוף.'**
  String get brokerBrochureScreen26099985;

  /// No description provided for @panoramaPoleCaptureE779f1ba.
  ///
  /// In he, this message translates to:
  /// **'לא ניתן לפתוח את המצלמה'**
  String get panoramaPoleCaptureE779f1ba;

  /// No description provided for @panoramaPoleCapture4c3842b7.
  ///
  /// In he, this message translates to:
  /// **'צלם את הרצפה'**
  String get panoramaPoleCapture4c3842b7;

  /// No description provided for @panoramaPoleCapture66a0b2bb.
  ///
  /// In he, this message translates to:
  /// **'צלם את התקרה'**
  String get panoramaPoleCapture66a0b2bb;

  /// No description provided for @panoramaPoleCapture033fdc7f.
  ///
  /// In he, this message translates to:
  /// **'כוון את הטלפון כלפי מטה אל הרצפה ועמוד במקום שבו צילמת את הפנורמה'**
  String get panoramaPoleCapture033fdc7f;

  /// No description provided for @panoramaPoleCapture1ca815b5.
  ///
  /// In he, this message translates to:
  /// **'כוון את הטלפון כלפי מעלה אל התקרה, מאותה נקודה בדיוק'**
  String get panoramaPoleCapture1ca815b5;

  /// No description provided for @panoramaPoleCapture4658faad.
  ///
  /// In he, this message translates to:
  /// **'שלב 1 מתוך 2 · רצפה'**
  String get panoramaPoleCapture4658faad;

  /// No description provided for @panoramaPoleCapture4af99b9d.
  ///
  /// In he, this message translates to:
  /// **'שלב 2 מתוך 2 · תקרה'**
  String get panoramaPoleCapture4af99b9d;

  /// No description provided for @panoramaPoleCapture80a413c5.
  ///
  /// In he, this message translates to:
  /// **'דלג'**
  String get panoramaPoleCapture80a413c5;

  /// No description provided for @panoramaPoleCapture4c53a96e.
  ///
  /// In he, this message translates to:
  /// **'שגיאת מצלמה'**
  String get panoramaPoleCapture4c53a96e;

  /// No description provided for @panoramaPoleCapture55247199.
  ///
  /// In he, this message translates to:
  /// **'סגור'**
  String get panoramaPoleCapture55247199;

  /// No description provided for @taxHelperScreenAaafbb6b.
  ///
  /// In he, this message translates to:
  /// **'מס הכנסה — בקלות'**
  String get taxHelperScreenAaafbb6b;

  /// No description provided for @taxHelperScreen7ba61d4a.
  ///
  /// In he, this message translates to:
  /// **'כמה שכר דירה אתה מקבל בחודש?'**
  String get taxHelperScreen7ba61d4a;

  /// No description provided for @taxHelperScreen84600891.
  ///
  /// In he, this message translates to:
  /// **'יש תקרת פטור על שכר דירה למגורים: {ceiling} בחודש (נכון ל-2026). '**
  String taxHelperScreen84600891(Object ceiling);

  /// No description provided for @taxHelperScreenF0b9273e.
  ///
  /// In he, this message translates to:
  /// **'כל עוד שכר הדירה שלך מתחת לתקרה הזו — אתה פטור ממס, '**
  String get taxHelperScreenF0b9273e;

  /// No description provided for @taxHelperScreen8df16fa9.
  ///
  /// In he, this message translates to:
  /// **'ואין צורך לדווח על ההכנסה הזו.'**
  String get taxHelperScreen8df16fa9;

  /// No description provided for @taxHelperScreenE7cedab0.
  ///
  /// In he, this message translates to:
  /// **'מעל התקרה יש מס. הדרך הכי פשוטה היא \"המסלול של 10%\": '**
  String get taxHelperScreenE7cedab0;

  /// No description provided for @taxHelperScreen4dd6aab6.
  ///
  /// In he, this message translates to:
  /// **'משלמים 10% מכל שכר הדירה, בלי חישובים מסובכים ובלי ניכויים. '**
  String get taxHelperScreen4dd6aab6;

  /// No description provided for @taxHelperScreen2546b90e.
  ///
  /// In he, this message translates to:
  /// **'במקרה שלך זה {amount} בחודש.'**
  String taxHelperScreen2546b90e(Object amount);

  /// No description provided for @taxHelperScreen063021d2.
  ///
  /// In he, this message translates to:
  /// **'מה זה אומר?'**
  String get taxHelperScreen063021d2;

  /// No description provided for @erikLiveVoiceScreenD5fa2760.
  ///
  /// In he, this message translates to:
  /// **'מתחבר…'**
  String get erikLiveVoiceScreenD5fa2760;

  /// No description provided for @erikLiveVoiceScreen4ec210b3.
  ///
  /// In he, this message translates to:
  /// **'אפשר לראות את הדירות הקיימות במסך \"הדירות שלי\".'**
  String get erikLiveVoiceScreen4ec210b3;

  /// No description provided for @erikLiveVoiceScreen15ec4d84.
  ///
  /// In he, this message translates to:
  /// **'מקשיב — פשוט דבר 🎙️'**
  String get erikLiveVoiceScreen15ec4d84;

  /// No description provided for @erikLiveVoiceScreenC4ad4681.
  ///
  /// In he, this message translates to:
  /// **'עזרא מדבר'**
  String get erikLiveVoiceScreenC4ad4681;

  /// No description provided for @erikLiveVoiceScreenAa5a9e29.
  ///
  /// In he, this message translates to:
  /// **'תקלה בחיבור'**
  String get erikLiveVoiceScreenAa5a9e29;

  /// No description provided for @erikLiveVoiceScreenC21710c8.
  ///
  /// In he, this message translates to:
  /// **'השיחה הסתיימה'**
  String get erikLiveVoiceScreenC21710c8;

  /// No description provided for @erikLiveVoiceScreen01302f08.
  ///
  /// In he, this message translates to:
  /// **'הדירה פורסמה! אפשר להוסיף תמונות במסך \"הדירות שלי\".'**
  String get erikLiveVoiceScreen01302f08;

  /// No description provided for @checkoutWebviewScreen4dffd049.
  ///
  /// In he, this message translates to:
  /// **'תשלום מאובטח'**
  String get checkoutWebviewScreen4dffd049;

  /// No description provided for @checkoutWebviewScreen44d94c3a.
  ///
  /// In he, this message translates to:
  /// **'הסליקה מתבצעת בעמוד המאובטח של Grow'**
  String get checkoutWebviewScreen44d94c3a;

  /// No description provided for @checkoutWebviewScreen194aef36.
  ///
  /// In he, this message translates to:
  /// **'טוען דף תשלום מאובטח…'**
  String get checkoutWebviewScreen194aef36;

  /// No description provided for @checkoutWebviewScreenB17b2010.
  ///
  /// In he, this message translates to:
  /// **'דף התשלום לא נטען'**
  String get checkoutWebviewScreenB17b2010;

  /// No description provided for @checkoutWebviewScreenF5e44e77.
  ///
  /// In he, this message translates to:
  /// **'ייתכן שיש בעיית רשת או שאמצעי התשלום אינו זמין כרגע. אפשר לנסות שוב או לחזור ולבחור אמצעי אחר.'**
  String get checkoutWebviewScreenF5e44e77;

  /// No description provided for @checkoutWebviewScreen10a2352b.
  ///
  /// In he, this message translates to:
  /// **'חזרה'**
  String get checkoutWebviewScreen10a2352b;

  /// No description provided for @checkoutWebviewScreen8c634e7d.
  ///
  /// In he, this message translates to:
  /// **'נסו שוב'**
  String get checkoutWebviewScreen8c634e7d;

  /// No description provided for @checkoutWebviewScreenE2cb5610.
  ///
  /// In he, this message translates to:
  /// **'מוצפן SSL · פרטי הכרטיס לא נשמרים באפליקציה'**
  String get checkoutWebviewScreenE2cb5610;

  /// No description provided for @checkoutWebviewScreenBb135a11.
  ///
  /// In he, this message translates to:
  /// **'Visa · Mastercard · אמריקן אקספרס · Bit'**
  String get checkoutWebviewScreenBb135a11;

  /// No description provided for @externalCheckoutScreenEd6f8b3f.
  ///
  /// In he, this message translates to:
  /// **'לא הצלחנו לפתוח את הדפדפן'**
  String get externalCheckoutScreenEd6f8b3f;

  /// No description provided for @externalCheckoutScreenFed753f2.
  ///
  /// In he, this message translates to:
  /// **'התשלום נפתח בדפדפן'**
  String get externalCheckoutScreenFed753f2;

  /// No description provided for @externalCheckoutScreenC8dbc943.
  ///
  /// In he, this message translates to:
  /// **'נסו לפתוח שוב, או חזרו ובחרו אמצעי תשלום אחר.'**
  String get externalCheckoutScreenC8dbc943;

  /// No description provided for @externalCheckoutScreen62ff1866.
  ///
  /// In he, this message translates to:
  /// **'השלימו את התשלום בדפדפן (Apple Pay / Google Pay), '**
  String get externalCheckoutScreen62ff1866;

  /// No description provided for @externalCheckoutScreen0a561779.
  ///
  /// In he, this message translates to:
  /// **'ואז חזרו לכאן ולחצו \"שילמתי — המשך\".'**
  String get externalCheckoutScreen0a561779;

  /// No description provided for @externalCheckoutScreen67490ed7.
  ///
  /// In he, this message translates to:
  /// **'שילמתי — המשך'**
  String get externalCheckoutScreen67490ed7;

  /// No description provided for @externalCheckoutScreenC4455ef4.
  ///
  /// In he, this message translates to:
  /// **'פתחו שוב'**
  String get externalCheckoutScreenC4455ef4;

  /// No description provided for @externalCheckoutScreen81b0db62.
  ///
  /// In he, this message translates to:
  /// **'פתחו שוב את דף התשלום'**
  String get externalCheckoutScreen81b0db62;

  /// No description provided for @externalCheckoutScreenA7c55a8d.
  ///
  /// In he, this message translates to:
  /// **'ביטול'**
  String get externalCheckoutScreenA7c55a8d;

  /// No description provided for @atiLiveVoiceScreenA7587542.
  ///
  /// In he, this message translates to:
  /// **'מתחברת…'**
  String get atiLiveVoiceScreenA7587542;

  /// No description provided for @atiLiveVoiceScreenAc995fe3.
  ///
  /// In he, this message translates to:
  /// **'מקשיבה — פשוט דברי 🎙️'**
  String get atiLiveVoiceScreenAc995fe3;

  /// No description provided for @atiLiveVoiceScreen746981e0.
  ///
  /// In he, this message translates to:
  /// **'אתי מדברת'**
  String get atiLiveVoiceScreen746981e0;

  /// No description provided for @atiLiveVoiceScreenAa5a9e29.
  ///
  /// In he, this message translates to:
  /// **'תקלה בחיבור'**
  String get atiLiveVoiceScreenAa5a9e29;

  /// No description provided for @atiLiveVoiceScreenC21710c8.
  ///
  /// In he, this message translates to:
  /// **'השיחה הסתיימה'**
  String get atiLiveVoiceScreenC21710c8;

  /// No description provided for @atiLiveVoiceScreen9a60c4a8.
  ///
  /// In he, this message translates to:
  /// **'מצאתי {count} דירות שמתאימות לך'**
  String atiLiveVoiceScreen9a60c4a8(Object count);

  /// No description provided for @atiLiveVoiceScreen193535e0.
  ///
  /// In he, this message translates to:
  /// **'הצג'**
  String get atiLiveVoiceScreen193535e0;

  /// No description provided for @atiVoicePropertyCard609fac18.
  ///
  /// In he, this message translates to:
  /// **'למכירה'**
  String get atiVoicePropertyCard609fac18;

  /// No description provided for @atiVoicePropertyCardB336259f.
  ///
  /// In he, this message translates to:
  /// **'להשכרה'**
  String get atiVoicePropertyCardB336259f;

  /// No description provided for @atiVoicePropertyCard77d9ac8f.
  ///
  /// In he, this message translates to:
  /// **'קומה {floor}'**
  String atiVoicePropertyCard77d9ac8f(Object floor);

  /// No description provided for @atiVoicePropertyCard5bf47d1e.
  ///
  /// In he, this message translates to:
  /// **'קומה 0'**
  String get atiVoicePropertyCard5bf47d1e;

  /// No description provided for @atiVoicePropertyCardF0f71ca3.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חדרים'**
  String atiVoicePropertyCardF0f71ca3(Object rooms);

  /// No description provided for @atiVoicePropertyCard615d28b8.
  ///
  /// In he, this message translates to:
  /// **'{size} מ״ר'**
  String atiVoicePropertyCard615d28b8(Object size);

  /// No description provided for @atiVoicePropertyCard5e3842ff.
  ///
  /// In he, this message translates to:
  /// **'למה דווקא זו?'**
  String get atiVoicePropertyCard5e3842ff;

  /// No description provided for @atiVoicePropertyCardDadd9f97.
  ///
  /// In he, this message translates to:
  /// **'למה אתי בחרה בדירה הזו'**
  String get atiVoicePropertyCardDadd9f97;

  /// No description provided for @atiVoicePropertyCard74f4db63.
  ///
  /// In he, this message translates to:
  /// **'{fit}% התאמה — '**
  String atiVoicePropertyCard74f4db63(Object fit);

  /// No description provided for @candidateFilters4754dba1.
  ///
  /// In he, this message translates to:
  /// **'פנוי מיידית'**
  String get candidateFilters4754dba1;

  /// No description provided for @candidateFiltersE5b327f6.
  ///
  /// In he, this message translates to:
  /// **'תוך חודש'**
  String get candidateFiltersE5b327f6;

  /// No description provided for @candidateFilters36c73aae.
  ///
  /// In he, this message translates to:
  /// **'1-3 חודשים'**
  String get candidateFilters36c73aae;

  /// No description provided for @candidateFilters81175383.
  ///
  /// In he, this message translates to:
  /// **'3-6 חודשים'**
  String get candidateFilters81175383;

  /// No description provided for @candidateFilters42ed7e8d.
  ///
  /// In he, this message translates to:
  /// **'סטודנט/ית'**
  String get candidateFilters42ed7e8d;

  /// No description provided for @candidateFiltersD663155d.
  ///
  /// In he, this message translates to:
  /// **'צעיר/ה מקצועי/ת'**
  String get candidateFiltersD663155d;

  /// No description provided for @candidateFilters926c043f.
  ///
  /// In he, this message translates to:
  /// **'משפחה'**
  String get candidateFilters926c043f;

  /// No description provided for @candidateFilters0aa42aa1.
  ///
  /// In he, this message translates to:
  /// **'גיל הזהב'**
  String get candidateFilters0aa42aa1;

  /// No description provided for @brokerHotMatchesScreenEda2e484.
  ///
  /// In he, this message translates to:
  /// **'התאמות חמות'**
  String get brokerHotMatchesScreenEda2e484;

  /// No description provided for @brokerHotMatchesScreenFc4def53.
  ///
  /// In he, this message translates to:
  /// **'סמן הכל כנקרא'**
  String get brokerHotMatchesScreenFc4def53;

  /// No description provided for @brokerHotMatchesScreen86958d86.
  ///
  /// In he, this message translates to:
  /// **'התאמה ל{name}'**
  String brokerHotMatchesScreen86958d86(Object name);

  /// No description provided for @brokerHotMatchesScreenB32088a8.
  ///
  /// In he, this message translates to:
  /// **'סמן כנקרא'**
  String get brokerHotMatchesScreenB32088a8;

  /// No description provided for @brokerHotMatchesScreenDcef2a46.
  ///
  /// In he, this message translates to:
  /// **'{price} {priceSuffix} · {rooms} חדרים · '**
  String brokerHotMatchesScreenDcef2a46(
      Object price, Object priceSuffix, Object rooms);

  /// No description provided for @brokerHotMatchesScreen3b25d447.
  ///
  /// In he, this message translates to:
  /// **'התאמה {score}%'**
  String brokerHotMatchesScreen3b25d447(Object score);

  /// No description provided for @brokerHotMatchesScreenC7283ce9.
  ///
  /// In he, this message translates to:
  /// **'אין התאמות חדשות כרגע'**
  String get brokerHotMatchesScreenC7283ce9;

  /// No description provided for @brokerHotMatchesScreen78ea80be.
  ///
  /// In he, this message translates to:
  /// **'כשתעלה נכס חדש שמתאים לאחד מהלקוחות בפנקס — נראה לך אותו כאן.'**
  String get brokerHotMatchesScreen78ea80be;

  /// No description provided for @panoramaSplatViewA2007314.
  ///
  /// In he, this message translates to:
  /// **'סיור תלת-מימד'**
  String get panoramaSplatViewA2007314;

  /// No description provided for @panoramaSplatView3b63a83c.
  ///
  /// In he, this message translates to:
  /// **'לא ניתן לטעון את הסיור התלת-מימדי במכשיר זה.'**
  String get panoramaSplatView3b63a83c;

  /// No description provided for @panoramaSplatView7fa2edab.
  ///
  /// In he, this message translates to:
  /// **'אחורה'**
  String get panoramaSplatView7fa2edab;

  /// No description provided for @panoramaSplatView1bb60018.
  ///
  /// In he, this message translates to:
  /// **'קדימה'**
  String get panoramaSplatView1bb60018;

  /// No description provided for @homeScreenFfcf1893.
  ///
  /// In he, this message translates to:
  /// **'חיפוש דירה'**
  String get homeScreenFfcf1893;

  /// No description provided for @homeScreen61f6102d.
  ///
  /// In he, this message translates to:
  /// **'התאמות'**
  String get homeScreen61f6102d;

  /// No description provided for @homeScreenB2367383.
  ///
  /// In he, this message translates to:
  /// **'דבר עם אתי'**
  String get homeScreenB2367383;

  /// No description provided for @homeScreenE1ea2811.
  ///
  /// In he, this message translates to:
  /// **'פרופיל'**
  String get homeScreenE1ea2811;

  /// No description provided for @homeScreen143fe31f.
  ///
  /// In he, this message translates to:
  /// **'דשבורד'**
  String get homeScreen143fe31f;

  /// No description provided for @homeScreen1881898b.
  ///
  /// In he, this message translates to:
  /// **'לקוחות'**
  String get homeScreen1881898b;

  /// No description provided for @homeScreen2c577068.
  ///
  /// In he, this message translates to:
  /// **'הדירות שלי'**
  String get homeScreen2c577068;

  /// No description provided for @ownerListingsScreenA082ba0e.
  ///
  /// In he, this message translates to:
  /// **'הדירות של {name} ב-Rently 🏠\n{link}'**
  String ownerListingsScreenA082ba0e(Object link, Object name);

  /// No description provided for @ownerListingsScreen5617dde0.
  ///
  /// In he, this message translates to:
  /// **'הקישור לדירות שלך הועתק — אפשר לשלוח לכל אחד'**
  String get ownerListingsScreen5617dde0;

  /// No description provided for @ownerListingsScreen2c577068.
  ///
  /// In he, this message translates to:
  /// **'הדירות שלי'**
  String get ownerListingsScreen2c577068;

  /// No description provided for @ownerListingsScreen8704f6e2.
  ///
  /// In he, this message translates to:
  /// **'הדירות של {name}'**
  String ownerListingsScreen8704f6e2(Object name);

  /// No description provided for @ownerListingsScreen6005f6dd.
  ///
  /// In he, this message translates to:
  /// **'שתף את דף הדירות'**
  String get ownerListingsScreen6005f6dd;

  /// No description provided for @ownerListingsScreenCc258a95.
  ///
  /// In he, this message translates to:
  /// **'אין דירות פעילות כרגע'**
  String get ownerListingsScreenCc258a95;

  /// No description provided for @ownerListingsScreenAgencyLabel.
  ///
  /// In he, this message translates to:
  /// **'מתווך נדל״ן'**
  String get ownerListingsScreenAgencyLabel;

  /// No description provided for @ownerListingsScreenPrivateLabel.
  ///
  /// In he, this message translates to:
  /// **'בעל נכס פרטי'**
  String get ownerListingsScreenPrivateLabel;

  /// No description provided for @ownerListingsScreen57ed6e46.
  ///
  /// In he, this message translates to:
  /// **' · {count} דירות'**
  String ownerListingsScreen57ed6e46(Object count);

  /// No description provided for @ownerListingsScreen2b748fae.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חד׳ · {size} מ״ר'**
  String ownerListingsScreen2b748fae(Object rooms, Object size);

  /// No description provided for @profileCompletionSheetAf5cd142.
  ///
  /// In he, this message translates to:
  /// **'הגעה ליותר בעלי דירות'**
  String get profileCompletionSheetAf5cd142;

  /// No description provided for @profileCompletionSheetBfe0b591.
  ///
  /// In he, this message translates to:
  /// **'התאמות מדויקות לפי מה שחשוב לך'**
  String get profileCompletionSheetBfe0b591;

  /// No description provided for @profileCompletionSheetB2401b38.
  ///
  /// In he, this message translates to:
  /// **'סינון מראש של הצעות לא רלוונטיות'**
  String get profileCompletionSheetB2401b38;

  /// No description provided for @profileCompletionSheet314597be.
  ///
  /// In he, this message translates to:
  /// **'השלמת הפרופיל שלך'**
  String get profileCompletionSheet314597be;

  /// No description provided for @profileCompletionSheet08b939a6.
  ///
  /// In he, this message translates to:
  /// **'כדי להפיק את המירב מהאפליקציה, נשמח שתשלים את המידע החסר בפרופיל שלך.'**
  String get profileCompletionSheet08b939a6;

  /// No description provided for @profileCompletionSheetF7c1459b.
  ///
  /// In he, this message translates to:
  /// **'פרופיל מלא עוזר לאחרים להתחבר אליך ומשפר את החוויה הכוללת שלך באפליקציה.'**
  String get profileCompletionSheetF7c1459b;

  /// No description provided for @profileCompletionSheetC2fcc265.
  ///
  /// In he, this message translates to:
  /// **'אחר כך'**
  String get profileCompletionSheetC2fcc265;

  /// No description provided for @profileCompletionSheetBbeffa00.
  ///
  /// In he, this message translates to:
  /// **'השלמת הפרופיל'**
  String get profileCompletionSheetBbeffa00;

  /// No description provided for @listingScore74a07f35.
  ///
  /// In he, this message translates to:
  /// **'מודעה מצוינת 🏆'**
  String get listingScore74a07f35;

  /// No description provided for @listingScoreE78d407d.
  ///
  /// In he, this message translates to:
  /// **'מודעה טובה מאוד 👍'**
  String get listingScoreE78d407d;

  /// No description provided for @listingScore70fd3337.
  ///
  /// In he, this message translates to:
  /// **'מודעה טובה'**
  String get listingScore70fd3337;

  /// No description provided for @listingScore15ff9d35.
  ///
  /// In he, this message translates to:
  /// **'אפשר לשפר — הוסף תמונות ופרטים'**
  String get listingScore15ff9d35;

  /// No description provided for @panoramaExperienceViewCa52b1de.
  ///
  /// In he, this message translates to:
  /// **'סיור 360°'**
  String get panoramaExperienceViewCa52b1de;

  /// No description provided for @panoramaExperienceView8a215f19.
  ///
  /// In he, this message translates to:
  /// **'אין סיור זמין'**
  String get panoramaExperienceView8a215f19;

  /// No description provided for @panoramaExperienceView6d5b61ae.
  ///
  /// In he, this message translates to:
  /// **'המשך'**
  String get panoramaExperienceView6d5b61ae;

  /// No description provided for @panoramaExperienceViewC382b650.
  ///
  /// In he, this message translates to:
  /// **'הזז את הטלפון כדי להסתכל מסביב'**
  String get panoramaExperienceViewC382b650;

  /// No description provided for @panoramaExperienceViewA48dc789.
  ///
  /// In he, this message translates to:
  /// **'גרור כדי להסתכל · הקש על החץ כדי להתקדם'**
  String get panoramaExperienceViewA48dc789;

  /// No description provided for @panoramaExperienceViewFdb5ed3b.
  ///
  /// In he, this message translates to:
  /// **'נקודה {n}'**
  String panoramaExperienceViewFdb5ed3b(Object n);

  /// No description provided for @panoramaMapPlacement89efe952.
  ///
  /// In he, this message translates to:
  /// **'מיקום הנקודה'**
  String get panoramaMapPlacement89efe952;

  /// No description provided for @panoramaMapPlacement9b8a163d.
  ///
  /// In he, this message translates to:
  /// **'הקש על המפה היכן צילמת את «{label}» בבית.'**
  String panoramaMapPlacement9b8a163d(Object label);

  /// No description provided for @panoramaMapPlacementE8290949.
  ///
  /// In he, this message translates to:
  /// **'זה בונה מפה קטנה שתעזור לעבור בין החדרים בסיור.'**
  String get panoramaMapPlacementE8290949;

  /// No description provided for @panoramaMapPlacement167194cf.
  ///
  /// In he, this message translates to:
  /// **'העלה תוכנית דירה'**
  String get panoramaMapPlacement167194cf;

  /// No description provided for @panoramaMapPlacement17cdf785.
  ///
  /// In he, this message translates to:
  /// **'החלף תוכנית'**
  String get panoramaMapPlacement17cdf785;

  /// No description provided for @panoramaMapPlacement80a413c5.
  ///
  /// In he, this message translates to:
  /// **'דלג'**
  String get panoramaMapPlacement80a413c5;

  /// No description provided for @panoramaMapPlacement1bc95f85.
  ///
  /// In he, this message translates to:
  /// **'אישור מיקום'**
  String get panoramaMapPlacement1bc95f85;

  /// No description provided for @fairRentHint2f1f13cd.
  ///
  /// In he, this message translates to:
  /// **'מחיר ממוצע באזור'**
  String get fairRentHint2f1f13cd;

  /// No description provided for @fairRentHint9b75eb76.
  ///
  /// In he, this message translates to:
  /// **'₪{amount} לחודש'**
  String fairRentHint9b75eb76(Object amount);

  /// No description provided for @fairRentHintAdcf7818.
  ///
  /// In he, this message translates to:
  /// **'השתמש במחיר המומלץ (₪{amount})'**
  String fairRentHintAdcf7818(Object amount);

  /// No description provided for @fairRentHintEa004c85.
  ///
  /// In he, this message translates to:
  /// **'המחיר המומלץ לפי השוק באזור'**
  String get fairRentHintEa004c85;

  /// No description provided for @fairRentHint1b102d50.
  ///
  /// In he, this message translates to:
  /// **'נמוך מהשוק — אפשר לבקש יותר'**
  String get fairRentHint1b102d50;

  /// No description provided for @fairRentHintAb830344.
  ///
  /// In he, this message translates to:
  /// **'גבוה מהשוק — עלול להרתיע שוכרים'**
  String get fairRentHintAb830344;

  /// No description provided for @fairRentHintA4d97966.
  ///
  /// In he, this message translates to:
  /// **'המחיר שלך נראה הוגן ✓'**
  String get fairRentHintA4d97966;

  /// No description provided for @scorecardViewBd0267a3.
  ///
  /// In he, this message translates to:
  /// **'למה זו?'**
  String get scorecardViewBd0267a3;

  /// No description provided for @scorecardView161967a5.
  ///
  /// In he, this message translates to:
  /// **'{fit}% התאמה'**
  String scorecardView161967a5(Object fit);

  /// No description provided for @scorecardView2c98190f.
  ///
  /// In he, this message translates to:
  /// **'כמה הדירה חזקה בכל פרמטר:'**
  String get scorecardView2c98190f;

  /// No description provided for @scorecardView5d1b29db.
  ///
  /// In he, this message translates to:
  /// **'מקורות הנתונים'**
  String get scorecardView5d1b29db;

  /// No description provided for @scorecardViewE2d283c3.
  ///
  /// In he, this message translates to:
  /// **'כל נתון מבוסס על מקור רשמי וניתן לאימות:'**
  String get scorecardViewE2d283c3;

  /// No description provided for @scorecardViewBf4062b1.
  ///
  /// In he, this message translates to:
  /// **'מקור: {source}'**
  String scorecardViewBf4062b1(Object source);

  /// No description provided for @scorecardViewA33028e6.
  ///
  /// In he, this message translates to:
  /// **'ביטחון {pct}%'**
  String scorecardViewA33028e6(Object pct);

  /// No description provided for @priceBadge76f81691.
  ///
  /// In he, this message translates to:
  /// **'₪{amount}/מ״ר'**
  String priceBadge76f81691(Object amount);

  /// No description provided for @priceBadgeB51a666b.
  ///
  /// In he, this message translates to:
  /// **'−{pct}% מתחת לחציון האזור'**
  String priceBadgeB51a666b(Object pct);

  /// No description provided for @priceBadgeE1ecf729.
  ///
  /// In he, this message translates to:
  /// **'+{pct}% מעל חציון האזור'**
  String priceBadgeE1ecf729(Object pct);

  /// No description provided for @priceBadgeB40e964e.
  ///
  /// In he, this message translates to:
  /// **'סביב חציון האזור'**
  String get priceBadgeB40e964e;

  /// No description provided for @priceBadge9b42587f.
  ///
  /// In he, this message translates to:
  /// **'מחיר מצוין לאזור'**
  String get priceBadge9b42587f;

  /// No description provided for @priceBadge66371906.
  ///
  /// In he, this message translates to:
  /// **'מעל מחיר השוק'**
  String get priceBadge66371906;

  /// No description provided for @priceBadge25a4bda0.
  ///
  /// In he, this message translates to:
  /// **'מחיר הוגן לאזור'**
  String get priceBadge25a4bda0;

  /// No description provided for @rentalTax68d523ba.
  ///
  /// In he, this message translates to:
  /// **'שכר הדירה שלך {rent} → אתה פטור ממס. אין מה לדווח.'**
  String rentalTax68d523ba(Object rent);

  /// No description provided for @rentalTax9b398d34.
  ///
  /// In he, this message translates to:
  /// **'אתה מעל תקרת הפטור ({ceiling}). '**
  String rentalTax9b398d34(Object ceiling);

  /// No description provided for @rentalTaxDa3d1e79.
  ///
  /// In he, this message translates to:
  /// **'חלק מהשכר עדיין פטור. המסלול הפשוט: 10% מהשכר = '**
  String get rentalTaxDa3d1e79;

  /// No description provided for @rentalTaxA2791ae8.
  ///
  /// In he, this message translates to:
  /// **'{amount} לחודש.'**
  String rentalTaxA2791ae8(Object amount);

  /// No description provided for @rentalTaxDaaf39c6.
  ///
  /// In he, this message translates to:
  /// **'המסלול הפשוט: 10% מהשכר = {amount} לחודש.'**
  String rentalTaxDaaf39c6(Object amount);

  /// No description provided for @scan3dViewer48726f5e.
  ///
  /// In he, this message translates to:
  /// **'סריקה תלת-מימדית'**
  String get scan3dViewer48726f5e;

  /// No description provided for @scan3dViewerBf032028.
  ///
  /// In he, this message translates to:
  /// **'לא ניתן לטעון את המודל התלת-מימדי של חדר זה.'**
  String get scan3dViewerBf032028;

  /// No description provided for @scan3dViewerE24e43eb.
  ///
  /// In he, this message translates to:
  /// **'חדר {roomNumber}'**
  String scan3dViewerE24e43eb(Object roomNumber);

  /// No description provided for @scan3dViewer444becda.
  ///
  /// In he, this message translates to:
  /// **'לא ניתן לטעון את המודל התלת-מימדי במכשיר זה.'**
  String get scan3dViewer444becda;

  /// No description provided for @auraHeroTemplateD068bb57.
  ///
  /// In he, this message translates to:
  /// **'קומה {floor}'**
  String auraHeroTemplateD068bb57(Object floor);

  /// No description provided for @auraHeroTemplate08bca18d.
  ///
  /// In he, this message translates to:
  /// **'חדש'**
  String get auraHeroTemplate08bca18d;

  /// No description provided for @auraHeroTemplateFdb4eac7.
  ///
  /// In he, this message translates to:
  /// **'{sizeM2} מ״ר'**
  String auraHeroTemplateFdb4eac7(Object sizeM2);

  /// No description provided for @auraHeroTemplateB50b3974.
  ///
  /// In he, this message translates to:
  /// **'חדרים'**
  String get auraHeroTemplateB50b3974;

  /// No description provided for @auraHeroTemplateD3b9013b.
  ///
  /// In he, this message translates to:
  /// **'מ״ר'**
  String get auraHeroTemplateD3b9013b;

  /// No description provided for @auraHeroTemplate047e630b.
  ///
  /// In he, this message translates to:
  /// **'קומה'**
  String get auraHeroTemplate047e630b;

  /// No description provided for @estateCardTemplate7de9ac58.
  ///
  /// In he, this message translates to:
  /// **'מאומת'**
  String get estateCardTemplate7de9ac58;

  /// No description provided for @estateCardTemplate08bca18d.
  ///
  /// In he, this message translates to:
  /// **'חדש'**
  String get estateCardTemplate08bca18d;

  /// No description provided for @estateCardTemplateCdc7944d.
  ///
  /// In he, this message translates to:
  /// **'₪{price} למ״ר'**
  String estateCardTemplateCdc7944d(Object price);

  /// No description provided for @estateCardTemplateD886d07f.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חדרים'**
  String estateCardTemplateD886d07f(Object rooms);

  /// No description provided for @estateCardTemplateFdb4eac7.
  ///
  /// In he, this message translates to:
  /// **'{sizeM2} מ״ר'**
  String estateCardTemplateFdb4eac7(Object sizeM2);

  /// No description provided for @estateCardTemplateD068bb57.
  ///
  /// In he, this message translates to:
  /// **'קומה {floor}'**
  String estateCardTemplateD068bb57(Object floor);

  /// No description provided for @fomoWidgets67fb588b.
  ///
  /// In he, this message translates to:
  /// **'מסתכל עכשיו'**
  String get fomoWidgets67fb588b;

  /// No description provided for @fomoWidgets5fc943b9.
  ///
  /// In he, this message translates to:
  /// **'{count} מסתכלים עכשיו'**
  String fomoWidgets5fc943b9(Object count);

  /// No description provided for @fomoWidgets668ee081.
  ///
  /// In he, this message translates to:
  /// **'{likesCount} אהבו היום'**
  String fomoWidgets668ee081(Object likesCount);

  /// No description provided for @fomoWidgetsD5424d20.
  ///
  /// In he, this message translates to:
  /// **'דירה הועלתה לאחרונה'**
  String get fomoWidgetsD5424d20;

  /// No description provided for @fomoWidgetsC646d563.
  ///
  /// In he, this message translates to:
  /// **'⚠ פג תוקף בעוד {label}'**
  String fomoWidgetsC646d563(Object label);

  /// No description provided for @fomoWidgetsF3d9f53a.
  ///
  /// In he, this message translates to:
  /// **'פג תוקף בעוד {label}'**
  String fomoWidgetsF3d9f53a(Object label);

  /// No description provided for @introNoteComposerF2616667.
  ///
  /// In he, this message translates to:
  /// **'משפחה שקטה, חוזה ארוך'**
  String get introNoteComposerF2616667;

  /// No description provided for @introNoteComposer7d2e4fae.
  ///
  /// In he, this message translates to:
  /// **'אישור הכנסה מוכן'**
  String get introNoteComposer7d2e4fae;

  /// No description provided for @introNoteComposerEf3d8df0.
  ///
  /// In he, this message translates to:
  /// **'הוסיפו מילה קצרה על עצמכם'**
  String get introNoteComposerEf3d8df0;

  /// No description provided for @introNoteComposer76250a91.
  ///
  /// In he, this message translates to:
  /// **'משפט אחד שגורם לבעל הדירה לשים לב אליכם (לא חובה).'**
  String get introNoteComposer76250a91;

  /// No description provided for @introNoteComposer6a9bc309.
  ///
  /// In he, this message translates to:
  /// **'למשל: זוג צעיר, ללא חיות, חוזה לשנתיים'**
  String get introNoteComposer6a9bc309;

  /// No description provided for @introNoteComposerBec7436c.
  ///
  /// In he, this message translates to:
  /// **'{remaining} תווים נותרו'**
  String introNoteComposerBec7436c(Object remaining);

  /// No description provided for @notificationPermissionService95b74d9c.
  ///
  /// In he, this message translates to:
  /// **'נשארים מעודכנים'**
  String get notificationPermissionService95b74d9c;

  /// No description provided for @notificationPermissionServiceC4d3318f.
  ///
  /// In he, this message translates to:
  /// **'נשמח לעדכן אתכם על התאמות חדשות, הודעות מבעלי דירות ושוכרים, '**
  String get notificationPermissionServiceC4d3318f;

  /// No description provided for @notificationPermissionService18ca271e.
  ///
  /// In he, this message translates to:
  /// **'ועדכונים חשובים בזמן אמת. אפשר לכבות בכל רגע מההגדרות.'**
  String get notificationPermissionService18ca271e;

  /// No description provided for @notificationPermissionService98c8a5b8.
  ///
  /// In he, this message translates to:
  /// **'לא עכשיו'**
  String get notificationPermissionService98c8a5b8;

  /// No description provided for @notificationPermissionService1540caea.
  ///
  /// In he, this message translates to:
  /// **'אפשר התראות'**
  String get notificationPermissionService1540caea;

  /// No description provided for @savedPropertiesScreen2f416fd3.
  ///
  /// In he, this message translates to:
  /// **'הדירות ששמרתי'**
  String get savedPropertiesScreen2f416fd3;

  /// No description provided for @savedPropertiesScreen18453b28.
  ///
  /// In he, this message translates to:
  /// **'השווה דירות שמורות'**
  String get savedPropertiesScreen18453b28;

  /// No description provided for @savedPropertiesScreen059db4ef.
  ///
  /// In he, this message translates to:
  /// **'הסר מהשמורים'**
  String get savedPropertiesScreen059db4ef;

  /// No description provided for @savedPropertiesScreenB6c4a8c7.
  ///
  /// In he, this message translates to:
  /// **'התאמה {score}%'**
  String savedPropertiesScreenB6c4a8c7(Object score);

  /// No description provided for @savedPropertiesScreen83541358.
  ///
  /// In he, this message translates to:
  /// **'עדיין לא שמרת דירות — סמנו ❤ בדירות שאהבתם כדי לחזור אליהן בקלות.'**
  String get savedPropertiesScreen83541358;

  /// No description provided for @paymentMethodSelector68e0442a.
  ///
  /// In he, this message translates to:
  /// **'ביט'**
  String get paymentMethodSelector68e0442a;

  /// No description provided for @paymentMethodSelectorC5a87fbf.
  ///
  /// In he, this message translates to:
  /// **'כרטיס אשראי'**
  String get paymentMethodSelectorC5a87fbf;

  /// No description provided for @paymentMethodSelectorEdd25759.
  ///
  /// In he, this message translates to:
  /// **'בחירת אמצעי תשלום'**
  String get paymentMethodSelectorEdd25759;

  /// No description provided for @paymentMethodSelectorE7d7f19a.
  ///
  /// In he, this message translates to:
  /// **'תשלום מאובטח · Grow · Morning'**
  String get paymentMethodSelectorE7d7f19a;

  /// No description provided for @panoramaWideCaptureE779f1ba.
  ///
  /// In he, this message translates to:
  /// **'לא ניתן לפתוח את המצלמה'**
  String get panoramaWideCaptureE779f1ba;

  /// No description provided for @panoramaWideCapture67274c54.
  ///
  /// In he, this message translates to:
  /// **'החזק את הטלפון אנכי וישר, ועמוד במרכז החדר'**
  String get panoramaWideCapture67274c54;

  /// No description provided for @panoramaWideCapture4c53a96e.
  ///
  /// In he, this message translates to:
  /// **'שגיאת מצלמה'**
  String get panoramaWideCapture4c53a96e;

  /// No description provided for @panoramaWideCapture55247199.
  ///
  /// In he, this message translates to:
  /// **'סגור'**
  String get panoramaWideCapture55247199;

  /// No description provided for @actionButton197aa0f3.
  ///
  /// In he, this message translates to:
  /// **'פתח סיור תלת־ממדי'**
  String get actionButton197aa0f3;

  /// No description provided for @actionButtonC1272587.
  ///
  /// In he, this message translates to:
  /// **'אהבתי דירה'**
  String get actionButtonC1272587;

  /// No description provided for @actionButton4031e827.
  ///
  /// In he, this message translates to:
  /// **'דלג על דירה'**
  String get actionButton4031e827;

  /// No description provided for @panoramaPsvTourCa52b1de.
  ///
  /// In he, this message translates to:
  /// **'סיור 360°'**
  String get panoramaPsvTourCa52b1de;

  /// No description provided for @panoramaPsvTour4968e76c.
  ///
  /// In he, this message translates to:
  /// **'גרסה {versionNumber}'**
  String panoramaPsvTour4968e76c(Object versionNumber);

  /// No description provided for @cinematicGlassTemplateB50b3974.
  ///
  /// In he, this message translates to:
  /// **'חדרים'**
  String get cinematicGlassTemplateB50b3974;

  /// No description provided for @cinematicGlassTemplateD3b9013b.
  ///
  /// In he, this message translates to:
  /// **'מ״ר'**
  String get cinematicGlassTemplateD3b9013b;

  /// No description provided for @cinematicGlassTemplate047e630b.
  ///
  /// In he, this message translates to:
  /// **'קומה'**
  String get cinematicGlassTemplate047e630b;

  /// No description provided for @assistantPropertyCard7de9ac58.
  ///
  /// In he, this message translates to:
  /// **'מאומת'**
  String get assistantPropertyCard7de9ac58;

  /// No description provided for @assistantPropertyCardF0f71ca3.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חדרים'**
  String assistantPropertyCardF0f71ca3(Object rooms);

  /// No description provided for @assistantPropertyCard615d28b8.
  ///
  /// In he, this message translates to:
  /// **'{sizeM2} מ״ר'**
  String assistantPropertyCard615d28b8(Object sizeM2);

  /// No description provided for @swipeToConfirm55ebef41.
  ///
  /// In he, this message translates to:
  /// **'גרור לאישור'**
  String get swipeToConfirm55ebef41;

  /// No description provided for @swipeToConfirmA7c55a8d.
  ///
  /// In he, this message translates to:
  /// **'ביטול'**
  String get swipeToConfirmA7c55a8d;

  /// No description provided for @panoramaWebTourCa52b1de.
  ///
  /// In he, this message translates to:
  /// **'סיור 360°'**
  String get panoramaWebTourCa52b1de;

  /// No description provided for @leadsInboxScreenEb3c6f60.
  ///
  /// In he, this message translates to:
  /// **'מועמדים'**
  String get leadsInboxScreenEb3c6f60;

  /// No description provided for @leadsInboxScreen1956aee8.
  ///
  /// In he, this message translates to:
  /// **'הודעות'**
  String get leadsInboxScreen1956aee8;

  /// No description provided for @profileCompletionBar809182d3.
  ///
  /// In he, this message translates to:
  /// **'השלמת הפרופיל — {percent}%'**
  String profileCompletionBar809182d3(Object percent);

  /// No description provided for @profileCompletionBarE215150d.
  ///
  /// In he, this message translates to:
  /// **'הפרופיל מושלם — בעלי דירות רואים אותך ראשון'**
  String get profileCompletionBarE215150d;

  /// No description provided for @mapStylePropertyCardC6efa96a.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חד׳'**
  String mapStylePropertyCardC6efa96a(Object rooms);

  /// No description provided for @mapStylePropertyCard615d28b8.
  ///
  /// In he, this message translates to:
  /// **'{sizeM2} מ״ר'**
  String mapStylePropertyCard615d28b8(Object sizeM2);

  /// No description provided for @recommendedForYouStripBd1114e6.
  ///
  /// In he, this message translates to:
  /// **'מומלץ בשבילך'**
  String get recommendedForYouStripBd1114e6;

  /// No description provided for @recommendedForYouStrip0edc8568.
  ///
  /// In he, this message translates to:
  /// **'{rooms} חד׳ · {sizeM2} מ״ר'**
  String recommendedForYouStrip0edc8568(Object rooms, Object sizeM2);

  /// No description provided for @speedModeSliderE8be715a.
  ///
  /// In he, this message translates to:
  /// **'מותאם אישית'**
  String get speedModeSliderE8be715a;

  /// No description provided for @speedModeSlider0a97f110.
  ///
  /// In he, this message translates to:
  /// **'מהיר'**
  String get speedModeSlider0a97f110;

  /// No description provided for @termTooltip32942004.
  ///
  /// In he, this message translates to:
  /// **'הסבר על המונח {term}'**
  String termTooltip32942004(Object term);

  /// No description provided for @termTooltip5e9909a0.
  ///
  /// In he, this message translates to:
  /// **'הבנתי'**
  String get termTooltip5e9909a0;

  /// No description provided for @whyDetailsAa1ccf6a.
  ///
  /// In he, this message translates to:
  /// **'למה בחרתי לך את זו? · {fitPct}% התאמה'**
  String whyDetailsAa1ccf6a(Object fitPct);

  /// No description provided for @whyDetails80b99f5e.
  ///
  /// In he, this message translates to:
  /// **'מתאימה למה שחיפשת — אזור, תקציב וגודל'**
  String get whyDetails80b99f5e;

  /// No description provided for @trustScoreBadge65bb303d.
  ///
  /// In he, this message translates to:
  /// **'ציון דייר'**
  String get trustScoreBadge65bb303d;

  /// No description provided for @profileHeader31a7e3af.
  ///
  /// In he, this message translates to:
  /// **'תקציב עד {budget} • {rooms} חדרים'**
  String profileHeader31a7e3af(Object budget, Object rooms);

  /// No description provided for @safeMedia773c5c3a.
  ///
  /// In he, this message translates to:
  /// **'וידאו'**
  String get safeMedia773c5c3a;

  /// No description provided for @brokerViewingsScreen7c8173fa.
  ///
  /// In he, this message translates to:
  /// **'מחיקה'**
  String get brokerViewingsScreen7c8173fa;
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
