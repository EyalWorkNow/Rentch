import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';
import 'package:flutter/material.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

/// A friendly, reassuring bottom sheet that explains — in plain Hebrew — what
/// the "דירה מאומתת" badge means and shows clear anti-scam red flags for ANY
/// listing.
///
/// Wire it to the verified badge:
///   GestureDetector(
///     onTap: () => VerificationInfoSheet.show(context),
///     child: theVerifiedBadge,
///   );
class VerificationInfoSheet {
  const VerificationInfoSheet._();

  /// Opens the info sheet. Safe to call from a tap handler.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const Directionality(
        textDirection: TextDirection.rtl,
        child: _VerificationInfoSheetBody(),
      ),
    );
  }
}

class _VerificationInfoSheetBody extends StatelessWidget {
  const _VerificationInfoSheetBody();

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFFF7FBFF),
          borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
          boxShadow: [
            BoxShadow(
              color: Color(0x26072946),
              blurRadius: 30,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 14, 20, bottomInset + 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 54,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.navy.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        _VerifiedHeader(),
                        SizedBox(height: 20),
                        _RedFlagsSection(),
                        SizedBox(height: 18),
                        _ReportNote(),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                _GotItButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VerifiedHeader extends StatelessWidget {
  const _VerifiedHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF0E3050), Color(0xFF15BFC9)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const RentlyIcon(
                  IconsaxPlusBold.verify,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'דירה מאומתת',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'בעל הדירה צילם סרטון אמיתי של הדירה ישירות מתוך האפליקציה. '
            'זה אומר שמדובר בדירה אמיתית וקיימת — לא תמונה שנלקחה מהאינטרנט.',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'שימו לב: אימות מאשר שהדירה אמיתית — אבל תמיד כדאי לבדוק כל מודעה לפי הסימנים שלמטה.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RedFlagsSection extends StatelessWidget {
  const _RedFlagsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          'שלושה סימני אזהרה להונאה',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppColors.navy,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'נכון לכל מודעה — גם למאומתת.',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        SizedBox(height: 14),
        _RedFlagCard(
          icon: IconsaxPlusBold.money_remove,
          title: 'אל תשלמו כסף לפני שראיתם את הדירה פיזית',
          body:
              'אף פעם אל תעבירו מקדמה, פיקדון או "דמי רצינות" לפני שביקרתם בדירה במו עיניכם '
              'ופגשתם את בעל הדירה. בקשה לתשלום מראש היא הסימן הכי נפוץ להונאה.',
        ),
        SizedBox(height: 12),
        _RedFlagCard(
          icon: IconsaxPlusBold.shield_tick,
          title: 'פיקדון חוקי מוגבל ל-3 חודשי שכירות',
          body:
              'לפי חוק שכירות הוגנת, בעל הדירה לא יכול לדרוש פיקדון גבוה משלושה חודשי שכירות. '
              'דרישה לסכום גבוה בהרבה היא סימן אזהרה.',
        ),
        SizedBox(height: 12),
        _RedFlagCard(
          icon: IconsaxPlusBold.warning_2,
          title: 'מחיר נמוך בצורה חשודה = כנראה הונאה',
          body:
              'אם המחיר נמוך בהרבה מדירות דומות באזור, כנראה משהו לא בסדר. '
              'מרמים מפתים עם מחיר זול כדי שתעבירו כסף מהר.',
        ),
      ],
    );
  }
}

class _RedFlagCard extends StatelessWidget {
  const _RedFlagCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.coral.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.coral.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: AppColors.coral, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportNote extends StatelessWidget {
  const _ReportNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RentlyIcon(
            IconsaxPlusBold.flag,
            color: AppColors.primaryDark,
            size: 24,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.navy,
                  height: 1.5,
                ),
                children: [
                  TextSpan(
                    text: 'נתקלתם במשהו חשוד? ',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  TextSpan(
                    text:
                        'לחצו על כפתור הדיווח (⋯) שבמודעה ובחרו "דיווח על מודעה". '
                        'הצוות שלנו בודק כל דיווח ומסיר מודעות מזויפות.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GotItButton extends StatelessWidget {
  const _GotItButton();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: () => Navigator.of(context).maybePop(),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.textOnPrimary,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: const Text(
          'הבנתי, תודה',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}
