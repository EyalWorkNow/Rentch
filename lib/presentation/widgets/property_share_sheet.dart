import 'package:dating_app/core/constants/app_colors.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax_plus/iconsax_plus.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> showPropertyShareSheet(
  BuildContext context,
  RentalProperty property,
) async {
  final message = _shareMessage(property);
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

String _shareMessage(RentalProperty property) {
  final details = <String>[
    'מצאתי נכס מעניין ב-Rentch',
    property.address,
    '${property.priceLabel} ${property.priceSuffixLabel}',
    '${property.roomsLabel} חדרים',
    '${property.sizeM2} מ"ר',
    if (property.url.trim().isNotEmpty) property.url.trim(),
  ];
  return details.join('\n');
}

Future<void> _shareViaUri(
  BuildContext context,
  Uri uri,
  String errorMessage,
) async {
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return;
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(errorMessage)),
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
    SnackBar(content: Text(confirmation)),
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
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
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
                'שלח את הנכס מהר דרך האפליקציה שנוחה לך, או העתק את הפרטים לשיתוף ידני.',
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
                            icon: IconsaxPlusBold.message_text,
                            label: 'WhatsApp',
                            subtitle: 'שליחה ישירה',
                            onTap: () async {
                              Navigator.of(context).pop();
                              await _shareViaUri(
                                context,
                                Uri.parse(
                                  'https://wa.me/?text=${Uri.encodeComponent(message)}',
                                ),
                                'לא ניתן לפתוח את WhatsApp כרגע',
                              );
                            },
                          ),
                          _ShareActionCard(
                            icon: IconsaxPlusBold.sms,
                            label: 'SMS',
                            subtitle: 'הודעת טקסט',
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
                                'לא ניתן לפתוח SMS כרגע',
                              );
                            },
                          ),
                          _ShareActionCard(
                            icon: IconsaxPlusBold.sms_edit,
                            label: 'Email',
                            subtitle: 'שליחה במייל',
                            onTap: () async {
                              Navigator.of(context).pop();
                              await _shareViaUri(
                                context,
                                Uri(
                                  scheme: 'mailto',
                                  queryParameters: <String, String>{
                                    'subject': 'נכס שיכול להתאים לך',
                                    'body': message,
                                  },
                                ),
                                'לא ניתן לפתוח אימייל כרגע',
                              );
                            },
                          ),
                          _ShareActionCard(
                            icon: IconsaxPlusBold.copy,
                            label: 'העתק פרטים',
                            subtitle: 'טקסט מלא לשיתוף',
                            onTap: () async {
                              Navigator.of(context).pop();
                              await _copyToClipboard(
                                context,
                                message,
                                'פרטי הנכס הועתקו',
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _ShareLinkButton(
                        onTap: () async {
                          Navigator.of(context).pop();
                          await _copyToClipboard(
                            context,
                            property.url.trim().isEmpty
                                ? message
                                : property.url.trim(),
                            property.url.trim().isEmpty
                                ? 'פרטי הנכס הועתקו'
                                : 'הקישור הועתק',
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
  const _PropertyPreviewCard({required this.property});

  final RentalProperty property;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF0E3050), Color(0xFF15BFC9)],
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
                    _PropertyMetaPill(label: '${property.roomsLabel} חדרים'),
                    _PropertyMetaPill(label: '${property.sizeM2} מ"ר'),
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
            child: const Icon(
              IconsaxPlusBold.send_2,
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
  const _ShareActionCard({
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
        icon: const Icon(IconsaxPlusBold.link_1, size: 18),
        label: const Text('העתק קישור לשיתוף'),
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
