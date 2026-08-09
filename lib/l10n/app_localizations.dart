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
