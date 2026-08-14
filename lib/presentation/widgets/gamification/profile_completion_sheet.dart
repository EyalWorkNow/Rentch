import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/providers/dating_provider.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:dating_app/presentation/features/user/profile/edit_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:provider/provider.dart';

/// A once-per-launch nudge for tenants with an incomplete profile. Shows how far
/// along they are, what's missing, and WHY it matters — completing the profile
/// is what unlocks reach + accurate matches + pre-filtered (relevant) offers.
class ProfileCompletionSheet {
  /// Shows the sheet if the current user is a tenant whose profile is < 100%.
  /// No-op otherwise. Safe to call unconditionally on app entry.
  static Future<void> maybeShow(BuildContext context) async {
    final provider = context.read<DatingProvider>();
    if (provider.isLandlord) return; // tenants only
    final profile = provider.tenantProfile;
    if (profile == null) return;
    final pct = provider.profileCompletion;
    if (pct >= 100) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ProfileCompletionSheet(
        percent: pct,
        hint: provider.profileCompletionHint(AppLocalizations.of(context)!),
        onComplete: () {
          Navigator.of(ctx).pop();
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => EditProfileScreen(profile: profile),
          ));
        },
      ),
    );
  }
}

class _ProfileCompletionSheet extends StatelessWidget {
  const _ProfileCompletionSheet({
    required this.percent,
    required this.hint,
    required this.onComplete,
  });

  final int percent;
  final String hint;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final benefits = <(IconData, String)>[
      (IconsaxPlusBold.eye, l10n.profileCompletionSheetAf5cd142),
      (IconsaxPlusBold.magic_star, l10n.profileCompletionSheetBfe0b591),
      (IconsaxPlusBold.filter, l10n.profileCompletionSheetB2401b38),
    ];
    return Directionality(
      textDirection: Directionality.of(context),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: EdgeInsets.fromLTRB(
            20, 10, 20, 16 + MediaQuery.of(context).padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Header
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.person, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(l10n.profileCompletionSheet314597be,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: AppColors.navy)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l10n.profileCompletionSheet08b939a6,
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                  height: 1.4),
            ),
            const SizedBox(height: 16),
            const Divider(color: AppColors.borderLight, height: 1),
            const SizedBox(height: 16),
            // Middle section (Circle + Checklist)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Circular Progress
                SizedBox(
                  width: 85,
                  height: 85,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              blurRadius: 14,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),
                      CircularProgressIndicator(
                        value: percent / 100,
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        backgroundColor: AppColors.borderLight.withValues(alpha: 0.6),
                        valueColor: AlwaysStoppedAnimation<Color>(
                            percent >= 50 ? AppColors.primary : AppColors.warning),
                      ),
                      Center(
                        child: Text(
                          '$percent%',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: AppColors.navy,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                // Texts & Checklist
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hint,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (int i = 0; i < benefits.length; i++) ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              benefits[i].$1,
                              size: 14,
                              color: i == 0 ? AppColors.success : AppColors.slate300,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                benefits[i].$2,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: i == 0 ? AppColors.navy : AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (i < benefits.length - 1) const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(color: AppColors.borderLight, height: 1),
            const SizedBox(height: 12),
            // Bottom text
            Text(
              l10n.profileCompletionSheetF7c1459b,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            // Buttons Row
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.borderLight, width: 1.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.profileCompletionSheetC2fcc265,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: AppColors.navy)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                      ),
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        onComplete();
                      },
                      child: Text(l10n.profileCompletionSheetBbeffa00,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w900)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
