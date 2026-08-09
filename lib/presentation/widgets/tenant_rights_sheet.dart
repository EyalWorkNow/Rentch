// A friendly, plain-Hebrew bottom sheet that explains a tenant's key rights for
// a SPECIFIC monthly rent — built for apartment-seekers (incl. new immigrants)
// who don't know their legal rights and get blindsided by deposits and fees.
//
// It is intentionally read-only: it computes nothing the law doesn't already
// define and reuses the deposit cap from rental_contract so there's one source
// of truth. No jargon — ממ"ד / בטוחות are defined inline.

import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_contract.dart';
import 'package:dating_app/l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context)!;
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
                    Expanded(
                      child: Text(
                        l10n.tenantRightsSheet09a76cb1,
                        style: const TextStyle(
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
                      title: l10n.tenantRightsSheet26a4104a,
                      body: depositCap > 0
                          ? l10n.tenantRightsSheet5ea0f907 +
                              l10n.tenantRightsSheet998fde48(depositCap) +
                              l10n.tenantRightsSheetDaadfc3a +
                              l10n.tenantRightsSheet30650421 +
                              l10n.tenantRightsSheet74e1f7e7 +
                              l10n.tenantRightsSheetFd0085dc
                          : l10n.tenantRightsSheet5ea0f907 +
                              l10n.tenantRightsSheet8bed726a +
                              l10n.tenantRightsSheetC9040c39,
                    ),
                    const SizedBox(height: 12),
                    _RightCard(
                      icon: Icons.handshake_rounded,
                      title: l10n.tenantRightsSheet331175e3,
                      body: l10n.tenantRightsSheetC9a8fc94 +
                          l10n.tenantRightsSheetC6aca436 +
                          l10n.tenantRightsSheet0ae2e28f,
                    ),
                    const SizedBox(height: 12),
                    _RightCard(
                      icon: Icons.remove_red_eye_rounded,
                      title: l10n.tenantRightsSheetD8e77ae9,
                      body: l10n.tenantRightsSheet386b9b05 +
                          l10n.tenantRightsSheetC75c0e1f +
                          l10n.tenantRightsSheetD5e1f4c7,
                    ),
                    const SizedBox(height: 12),
                    _RightCard(
                      icon: Icons.home_repair_service_rounded,
                      title: l10n.tenantRightsSheet8b33be3a,
                      body: l10n.tenantRightsSheet6c2e4b93 +
                          l10n.tenantRightsSheet7be24327 +
                          l10n.tenantRightsSheetD89c29b2 +
                          l10n.tenantRightsSheet5e967f01 +
                          l10n.tenantRightsSheet18d2dbed,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.tenantRightsSheetF8a977ee +
                          l10n.tenantRightsSheet190074d2,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
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
                        child: Text(
                          l10n.tenantRightsSheet5e9909a0,
                          style: const TextStyle(
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
