import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/l10n/app_localizations.dart';
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
      builder: (_) => Directionality(
        textDirection: Directionality.of(context),
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
          color: AppColors.slate50,
          borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
          boxShadow: [
            BoxShadow(
              color: AppColors.navyShadow,
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
                      children: [
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
  _VerifiedHeader();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [AppColors.navy, AppColors.primary],
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
              Expanded(
                child: Text(
                  l10n.verificationInfoSheet220a89be,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '${l10n.verificationInfoSheet1079b7b6}'
            '${l10n.verificationInfoSheetF194db27}',
            style: const TextStyle(
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
            child: Text(
              l10n.verificationInfoSheet92ba2f6a,
              style: const TextStyle(
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
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.verificationInfoSheet7e5cc81f,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.verificationInfoSheet515b9741,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 14),
        _RedFlagCard(
          icon: IconsaxPlusBold.money_remove,
          title: l10n.verificationInfoSheet34c41aab,
          body: '${l10n.verificationInfoSheetF3def21a}'
              '${l10n.verificationInfoSheet62b9758c}',
        ),
        const SizedBox(height: 12),
        _RedFlagCard(
          icon: IconsaxPlusBold.shield_tick,
          title: l10n.verificationInfoSheet8e732266,
          body: '${l10n.verificationInfoSheetEf8e2318}'
              '${l10n.verificationInfoSheetF18547d6}',
        ),
        const SizedBox(height: 12),
        _RedFlagCard(
          icon: IconsaxPlusBold.warning_2,
          title: l10n.verificationInfoSheet488f7486,
          body: '${l10n.verificationInfoSheet0d24ccbd}'
              '${l10n.verificationInfoSheet82cdbe86}',
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
  _ReportNote();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.navy,
                  height: 1.5,
                ),
                children: [
                  TextSpan(
                    text: l10n.verificationInfoSheet0cba7786,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  TextSpan(
                    text: '${l10n.verificationInfoSheetE3638d06}'
                        '${l10n.verificationInfoSheet49e4fb5f}',
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
  _GotItButton();

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
        child: Text(
          AppLocalizations.of(context)!.verificationInfoSheetEe9c82fc,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}
