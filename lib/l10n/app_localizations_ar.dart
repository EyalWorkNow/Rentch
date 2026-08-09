// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get onboardingHeadline => 'شقتك بانتظارك هنا';

  @override
  String get onboardingSubtitle =>
      'بحث ذكي حسب ما يهمك حقًا — الميزانية والمنطقة ونمط الحياة. انشر شقة خلال ثوانٍ، مع كل التوافقات والمحادثات في مكان واحد.';

  @override
  String get getStarted => 'لنبدأ';

  @override
  String get next => 'التالي';

  @override
  String get introSwipeTitle => 'اكتشف الشقق بالتمرير';

  @override
  String get introSwipeBody =>
      'مرّر يمينًا 👍 لحفظ شقة أعجبتك، ويسارًا 👎 للتخطي. يمكنك أيضًا البحث عبر آتي (البحث الذكي)، في المعرض أو على الخريطة.';

  @override
  String get introAtiTitle => 'آتي — البحث الذكي';

  @override
  String get introAtiBody =>
      'أخبر آتي عمّا تبحث عنه بأسلوبك الخاص، وستجد لك أنسب الشقق.';

  @override
  String get introTourTitle => 'جولات ثلاثية الأبعاد';

  @override
  String get introTourBody =>
      'ادخل الشقة قبل أن تغادر المنزل — جولة 360° وتجربة ثلاثية الأبعاد مباشرة من الشاشة.';

  @override
  String get introMatchTitle => 'التوافقات والمحادثات';

  @override
  String get introMatchBody =>
      'عند وجود توافق متبادل يمكنك التحدث مباشرة، وتحديد موعد للمعاينة وإتمام الصفقة — كل ذلك في مكان واحد.';

  @override
  String get introProfileTitle => 'ملفك الشخصي';

  @override
  String get introProfileBody =>
      'أكمل بياناتك للحصول على توافقات أدق. كلما كان ملفك الشخصي أكثر اكتمالاً، كانت التوافقات أفضل.';

  @override
  String get skip => 'تخطي';

  @override
  String get letsGetStarted => 'لنبدأ الآن!';
}
