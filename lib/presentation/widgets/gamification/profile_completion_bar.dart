import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

class ProfileCompletionBar extends StatelessWidget {
  ProfileCompletionBar({
    super.key,
    required this.percent,
    required this.hint,
    required this.onTap,
  });

  final int percent;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (percent >= 100) return const _CompleteBanner();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.12),
              AppColors.navy.withValues(alpha: 0.06),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.25),
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person_outline_rounded,
                    size: 18, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.of(context)!
                      .profileCompletionBar809182d3(percent),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.navy,
                  ),
                ),
                const Spacer(),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: AppColors.textSecondary),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: percent / 100,
                minHeight: 7,
                backgroundColor: AppColors.borderLight,
                valueColor:
                    AlwaysStoppedAnimation<Color>(_barColor(percent)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hint,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _barColor(int p) {
    if (p >= 80) return AppColors.success;
    if (p >= 50) return AppColors.primary;
    return AppColors.warning;
  }
}

class _CompleteBanner extends StatelessWidget {
  const _CompleteBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.success.withValues(alpha: 0.3),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_rounded,
              color: AppColors.success, size: 20),
          const SizedBox(width: 8),
          Text(
            AppLocalizations.of(context)!.profileCompletionBarE215150d,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }
}
