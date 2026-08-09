// A friendly, plain-Hebrew bottom sheet that explains a tenant's key rights for
// a SPECIFIC monthly rent — built for apartment-seekers (incl. new immigrants)
// who don't know their legal rights and get blindsided by deposits and fees.
//
// It is intentionally read-only: it computes nothing the law doesn't already
// define and reuses the deposit cap from rental_contract so there's one source
// of truth. No jargon — ממ"ד / בטוחות are defined inline.

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_contract.dart';
import 'package:flutter/material.dart';

/// Bottom sheet explaining the tenant's rights for [monthlyRent].
class TenantRightsSheet {
  const TenantRightsSheet._();

  /// Opens the rights sheet. [termMonths] is used only to compute the legal
  /// deposit cap (lower of ⅓ of lease-term rent or 3 months' rent).
  static Future<void> show(
    BuildContext context, {
    required int monthlyRent,
    int termMonths = 12,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TenantRightsBody(
        monthlyRent: monthlyRent,
        termMonths: termMonths,
      ),
    );
  }
}

class _TenantRightsBody extends StatelessWidget {
  _TenantRightsBody({
    required this.monthlyRent,
    required this.termMonths,
  });

  final int monthlyRent;
  final int termMonths;

  @override
  Widget build(BuildContext context) {
    // Reuse the contract model's cap — never reimplement the legal math.
    final depositCap = maxLegalDepositNis(
      monthlyRent: monthlyRent,
      termMonths: termMonths,
    );

    return Directionality(
      textDirection: Directionality.of(context),
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    Icon(Icons.verified_user_rounded,
                        color: AppColors.primary, size: 28),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'הזכויות שלכם כשוכרים',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    _RightCard(
                      icon: Icons.shield_rounded,
                      title: 'הפיקדון מוגבל בחוק',
                      body: depositCap > 0
                          ? 'לפי חוק שכירות הוגנת 2017, פיקדון במזומן/ערבות '
                              'מוגבל ל-₪$depositCap. זה הסכום המרבי שמותר לבקש '
                              'מכם בנכס הזה (הנמוך מבין ⅓ מסך השכירות לכל '
                              'התקופה או 3 חודשי שכירות).\n\n'
                              'בטוחות = כסף או ערבות שמשאירים אצל בעל הדירה '
                              'להבטחת ההסכם, ומוחזרים בסוף השכירות.'
                          : 'לפי חוק שכירות הוגנת 2017, פיקדון במזומן/ערבות '
                              'מוגבל לנמוך מבין ⅓ מסך השכירות לכל התקופה או '
                              '3 חודשי שכירות.',
                    ),
                    const SizedBox(height: 12),
                    _RightCard(
                      icon: Icons.handshake_rounded,
                      title: 'דמי תיווך — רק אם חתמתם',
                      body: 'דמי תיווך (חודש שכירות + מע״מ 18%) מגיעים למתווך '
                          'רק אם חתמתם על הסכם תיווך. בלי חתימה — אינכם חייבים '
                          'לשלם תיווך. שאלו תמיד מי מייצג מי.',
                    ),
                    const SizedBox(height: 12),
                    _RightCard(
                      icon: Icons.remove_red_eye_rounded,
                      title: 'אל תשלמו לפני שראיתם את הדירה',
                      body: 'לעולם אל תעבירו פיקדון, מקדמה או דמי תיווך לפני '
                          'שביקרתם בדירה פיזית ואימתתם מול מי אתם מתקשרים. '
                          'בקשה לתשלום מראש "כדי לשמור" את הדירה היא דגל אדום.',
                    ),
                    const SizedBox(height: 12),
                    _RightCard(
                      icon: Icons.home_repair_service_rounded,
                      title: 'דירה ראויה למגורים',
                      body: 'על בעל הדירה למסור דירה במצב ראוי למגורים ולתקן '
                          'ליקויים מהותיים שאינם באשמתכם. דירה חייבת אוורור, '
                          'מים, חשמל ומערכת ביוב תקינים.\n\n'
                          'ממ"ד = מרחב מוגן דירתי, חדר ביטחון. אם קיים, '
                          'אסור להשתמש בו כמחסן שמונע כניסה בשעת חירום.',
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'מידע כללי ואינו ייעוץ משפטי. בכל ספק התייעצו עם '
                      'עורך/ת דין.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 52,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: const Text(
                          'הבנתי',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textOnPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RightCard extends StatelessWidget {
  _RightCard({
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.primaryDark, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
