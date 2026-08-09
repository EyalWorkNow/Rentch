import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:dating_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:dating_app/presentation/widgets/rently_icon.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> showPropertyShareSheet(
  BuildContext context,
  RentalProperty property,
) async {
  final message = _shareMessage(context, property);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return FractionallySizedBox(
        heightFactor: 0.8,
        child: _PropertyShareSheet(
          property: property,
          message: message,
        ),
      );
    },
  );
}

String _shareMessage(BuildContext context, RentalProperty property) {
  final l10n = AppLocalizations.of(context)!;
  // The Rently share link renders a rich banner (photo + price) in WhatsApp via
  // the backend OpenGraph page (GET /p/:id).
  final shareLink = '${AppConfig.publicShareBaseUrl}/p/${property.id}';
  final details = <String>[
    l10n.propertyShareSheetF15bfc25,
    property.address,
    '${property.priceLabel} ${property.priceSuffixLabel}',
    l10n.propertyShareSheetD886d07f(property.roomsLabel),
    l10n.propertyShareSheet5d29dec4(property.sizeM2),
    shareLink,
  ];
  return details.join('\n');
}

Future<void> _shareViaUri(
  BuildContext context,
  Uri uri,
  String errorMessage, {
  Uri? fallback,
}) async {
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return;
  }
  // Primary scheme unavailable (e.g. WhatsApp app not installed) → try the web
  // fallback before giving up.
  if (fallback != null && await canLaunchUrl(fallback)) {
    await launchUrl(fallback, mode: LaunchMode.externalApplication);
    return;
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: const Duration(milliseconds: 2500),
      content: Text(errorMessage),
    ),
  );
}

Future<void> _copyToClipboard(
  BuildContext context,
  String value,
  String confirmation,
) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: const Duration(milliseconds: 2500),
      content: Text(confirmation),
    ),
  );
}

class _PropertyShareSheet extends StatelessWidget {
  const _PropertyShareSheet({
    required this.property,
    required this.message,
  });

  final RentalProperty property;
  final String message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
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
          padding: EdgeInsets.fromLTRB(20, 14, 20, bottomInset + 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                child: Container(
                  width: 54,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.navy.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Send listing',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: AppColors.navy,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.propertyShareSheetEd00d602,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PropertyPreviewCard(property: property),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _ShareActionCard(
                            icon: IconsaxPlusLinear.message_text,
                            label: 'WhatsApp',
                            subtitle: l10n.propertyShareSheet827cec4d,
                            onTap: () async {
                              Navigator.of(context).pop();
                              // whatsapp:// opens the WhatsApp APP directly (no
                              // wa.me web-page bounce); falls back to wa.me only
                              // if the app isn't installed.
                              final wa = Uri.parse(
                                  'whatsapp://send?text=${Uri.encodeComponent(message)}');
                              final web = Uri.parse(
                                  'https://wa.me/?text=${Uri.encodeComponent(message)}');
                              await _shareViaUri(
                                context,
                                wa,
                                l10n.propertyShareSheetC23278cd,
                                fallback: web,
                              );
                            },
                          ),
                          _ShareActionCard(
                            icon: IconsaxPlusLinear.sms,
                            label: 'SMS',
                            subtitle: l10n.propertyShareSheet5abda5bb,
                            onTap: () async {
                              Navigator.of(context).pop();
                              await _shareViaUri(
                                context,
                                Uri(
                                  scheme: 'sms',
                                  queryParameters: <String, String>{
                                    'body': message,
                                  },
                                ),
                                l10n.propertyShareSheet12d7a7d4,
                              );
                            },
                          ),
                          _ShareActionCard(
                            icon: IconsaxPlusLinear.sms_edit,
                            label: 'Email',
                            subtitle: l10n.propertyShareSheetC57dda61,
                            onTap: () async {
                              Navigator.of(context).pop();
                              await _shareViaUri(
                                context,
                                Uri(
                                  scheme: 'mailto',
                                  queryParameters: <String, String>{
                                    'subject': l10n.propertyShareSheet88f45e7e,
                                    'body': message,
                                  },
                                ),
                                l10n.propertyShareSheet600502fd,
                              );
                            },
                          ),
                          _ShareActionCard(
                            icon: IconsaxPlusLinear.copy,
                            label: l10n.propertyShareSheetB26acdf0,
                            subtitle: l10n.propertyShareSheet3a798b8a,
                            onTap: () async {
                              Navigator.of(context).pop();
                              await _copyToClipboard(
                                context,
                                message,
                                l10n.propertyShareSheet79a0ff65,
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _ShareLinkButton(
                        onTap: () async {
                          Navigator.of(context).pop();
                          // Copy the SAME public /p/<id> share link the message
                          // uses — it opens the app at the apartment (rently://)
                          // or falls back to the store. property.url is an
                          // unrelated external listing URL, not a Rently link.
                          await _copyToClipboard(
                            context,
                            '${AppConfig.publicShareBaseUrl}/p/${property.id}',
                            l10n.propertyShareSheet4aa70f6f,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PropertyPreviewCard extends StatelessWidget {
  _PropertyPreviewCard({required this.property});

  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [AppColors.navy, AppColors.primary],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  property.priceLabel,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  property.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _PropertyMetaPill(label: l10n.propertyShareSheetD886d07f(property.roomsLabel)),
                    _PropertyMetaPill(label: l10n.propertyShareSheet5d29dec4(property.sizeM2)),
                    _PropertyMetaPill(label: property.city),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const RentlyIcon(
              IconsaxPlusLinear.send_2,
              color: Colors.white,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }
}

class _PropertyMetaPill extends StatelessWidget {
  const _PropertyMetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _ShareActionCard extends StatelessWidget {
  _ShareActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final width = (MediaQuery.sizeOf(context).width - 64) / 2;
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: AppColors.primary, size: 20),
                ),
                const SizedBox(height: 14),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShareLinkButton extends StatelessWidget {
  const _ShareLinkButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: const RentlyIcon(IconsaxPlusLinear.link_1, size: 18),
        label: Text(AppLocalizations.of(context)!.propertyShareSheet3589781c),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navy,
          side: BorderSide(
            color: AppColors.navy.withValues(alpha: 0.12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}
